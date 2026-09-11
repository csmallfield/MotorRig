extends Node
## Autoload "SimConfig": finds profiles on disk, holds the current selection, remembers the
## last choice, and switches between the start menu and the sim.
##
## The car and terrain look this up dynamically (get_node_or_null("/root/SimConfig")), so
## they still work without it (tests, running main.tscn on its own) using built-in defaults.

const MENU_SCENE: String = "res://scenes/menu.tscn"
const SIM_SCENE: String = "res://scenes/main.tscn"
const CAR_DIRS: PackedStringArray = ["res://profiles/cars", "user://profiles/cars"]
const WORLD_DIRS: PackedStringArray = ["res://profiles/worlds", "user://profiles/worlds"]
const SETTINGS_PATH: String = "user://settings.cfg"

var car_profile: CarProfile
var world_profile: WorldProfile
var car_path: String = ""
var world_path: String = ""


func _ready() -> void:
	for d in [CAR_DIRS[1], WORLD_DIRS[1]]:
		DirAccess.make_dir_recursive_absolute(d)
	_restore_last()


## [{path, name, profile (or null), error, user (bool)}], sorted: project first, then yours.
func scan_cars() -> Array[Dictionary]:
	return _scan(CAR_DIRS, "CarProfile")


func scan_worlds() -> Array[Dictionary]:
	return _scan(WORLD_DIRS, "WorldProfile")


func select(car: String, world: String) -> bool:
	var c := _load_as(car, "CarProfile")
	var w := _load_as(world, "WorldProfile")
	if c == null or w == null:
		return false
	car_profile = c
	world_profile = w
	car_path = car
	world_path = world
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("selection", "car", car)
	cfg.set_value("selection", "world", world)
	cfg.save(SETTINGS_PATH)
	return true


## Warnings worth showing before driving (empty = fine).
func warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if car_profile and world_profile and car_profile.tuned_at_hz != world_profile.tick_hz:
		out.append("Car tuned at %d Hz but the world runs at %d Hz - suspension will behave differently." % [
			car_profile.tuned_at_hz, world_profile.tick_hz])
	if world_profile and world_profile.source == WorldProfile.Source.SCENE and world_profile.imported_scene == null:
		out.append("World source is SCENE but no imported_scene is set.")
	return out


func start_sim() -> void:
	get_tree().change_scene_to_file(SIM_SCENE)


func go_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func open_user_profiles() -> void:
	OS.shell_open(ProjectSettings.globalize_path("user://profiles"))


# === internals ===

func _restore_last() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var cars := scan_cars()
	var worlds := scan_worlds()
	var c: String = cfg.get_value("selection", "car", "")
	var w: String = cfg.get_value("selection", "world", "")
	if not _has(cars, c):
		c = _first_valid(cars)
	if not _has(worlds, w):
		w = _first_valid(worlds)
	if c != "" and w != "":
		select(c, w)
	else:   # nothing usable on disk: built-in defaults
		car_profile = CarProfile.new()
		world_profile = WorldProfile.new()


func _scan(dirs: PackedStringArray, type_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in dirs:
		var da := DirAccess.open(d)
		if da == null:
			continue
		var files := Array(da.get_files())
		files.sort()
		for f: String in files:
			# exported builds list converted resources as "name.tres.remap"
			var name := f.trim_suffix(".remap")
			if not (name.ends_with(".tres") or name.ends_with(".res")):
				continue
			var path := d.path_join(name)
			var res := _load_as(path, type_name)
			out.append({"path": path, "profile": res, "user": d.begins_with("user://"),
				"name": (res.get("display_name") if res else name.get_basename()),
				"error": "" if res else "not a %s (or failed to load)" % type_name})
	return out


func _load_as(path: String, type_name: String) -> Resource:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if r == null or r.get_script() == null or r.get_script().get_global_name() != type_name:
		return null
	return r


func _has(list: Array[Dictionary], path: String) -> bool:
	for e in list:
		if e["path"] == path and e["profile"] != null:
			return true
	return false


func _first_valid(list: Array[Dictionary]) -> String:
	for e in list:
		if e["profile"] != null:
			return e["path"]
	return ""
