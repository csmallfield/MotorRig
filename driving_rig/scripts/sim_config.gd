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
const MODE_DIRS: PackedStringArray = ["res://profiles/modes", "user://profiles/modes"]
const SETTINGS_PATH: String = "user://settings.cfg"

var car_profile: CarProfile
var world_profile: WorldProfile
var drive_mode: DriveMode
var car_path: String = ""
var world_path: String = ""
var mode_path: String = ""


func _ready() -> void:
	add_gamepad_ui_buttons()
	for d in [CAR_DIRS[1], WORLD_DIRS[1], MODE_DIRS[1]]:
		DirAccess.make_dir_recursive_absolute(d)
	_restore_last()


## [{path, name, profile (or null), error, user (bool)}], sorted: project first, then yours.
func scan_cars() -> Array[Dictionary]:
	return _scan(CAR_DIRS, "CarProfile")


func scan_worlds() -> Array[Dictionary]:
	return _scan(WORLD_DIRS, "WorldProfile")


func scan_modes() -> Array[Dictionary]:
	return _scan(MODE_DIRS, "DriveMode")


func select(car: String, world: String, mode: String = "") -> bool:
	var c := _load_as(car, "CarProfile")
	var w := _load_as(world, "WorldProfile")
	if c == null or w == null:
		return false
	var m := _load_as(mode, "DriveMode") if mode != "" else drive_mode
	if m == null:
		return false
	car_profile = c
	world_profile = w
	drive_mode = m
	car_path = car
	world_path = world
	if mode != "":
		mode_path = mode
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("selection", "car", car)
	cfg.set_value("selection", "world", world)
	cfg.set_value("selection", "mode", mode_path)
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
	if drive_mode and not drive_mode.is_neutral():
		out.append("%s changes the car's handling - the car profile's tested numbers no longer apply." % drive_mode.display_name)
	return out


func start_sim() -> void:
	var what := car_profile.display_name if car_profile else "the car"
	_switch_to(SIM_SCENE, "Loading %s..." % what, car_profile.chassis_path if car_profile else "")


func go_menu() -> void:
	_switch_to(MENU_SCENE, "Loading...")


# === loading screen ===
## The full car models take a moment to load. Loading happens on a thread behind a loading
## screen (so the window keeps drawing instead of freezing), then the scene switches; the screen
## stays up until the new scene's first frame - which is when the car and world get built.

var _loading: PackedStringArray = []
var _loaded: Array[Resource] = []      ## held until the switch, so nothing unloads in between
var _overlay: CanvasLayer
var _overlay_label: Label
var _overlay_bar: ProgressBar


func _switch_to(scene: String, text: String, extra: String = "") -> void:
	if not _loading.is_empty():
		return                                       # already on its way
	_show_overlay(text)
	_loading = [scene]
	if extra != "" and ResourceLoader.exists(extra):
		_loading.append(extra)                       # the car's model: the slow part
	for p in _loading:
		if ResourceLoader.load_threaded_request(p, "", true) != OK:
			_loading.clear()
			get_tree().change_scene_to_file(scene)   # couldn't thread it: plain load
			_hide_overlay()
			return


func _process(_delta: float) -> void:
	if _loading.is_empty():
		return
	var sum := 0.0
	var ready := true
	for p in _loading:
		var prog := []
		var st := ResourceLoader.load_threaded_get_status(p, prog)
		if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Couldn't load %s" % p)
			var scene: String = _loading[0]
			_loading.clear()
			get_tree().change_scene_to_file(scene)
			_hide_overlay()
			return
		sum += 1.0 if st == ResourceLoader.THREAD_LOAD_LOADED else (float(prog[0]) if prog.size() > 0 else 0.0)
		ready = ready and st == ResourceLoader.THREAD_LOAD_LOADED
	_overlay_bar.value = 100.0 * sum / _loading.size()
	if ready:
		_finish_switch()


func _finish_switch() -> void:
	_loaded.clear()
	for p in _loading:
		_loaded.append(ResourceLoader.load_threaded_get(p))
	_loading.clear()
	_overlay_label.text = _overlay_label.text.trim_suffix("...") + " - starting..."
	await get_tree().process_frame                   # let the full bar draw
	get_tree().change_scene_to_packed(_loaded[0] as PackedScene)
	await get_tree().scene_changed
	await get_tree().process_frame                   # the new scene has built and drawn once
	_loaded.clear()
	_hide_overlay()


func _show_overlay(text: String) -> void:
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.layer = 128
		var bg := ColorRect.new()
		bg.color = Color(0.06, 0.07, 0.09)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(bg)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_CENTER)
		box.custom_minimum_size = Vector2(420, 0)
		box.position = Vector2(-210, -30)
		box.add_theme_constant_override("separation", 12)
		bg.add_child(box)
		_overlay_label = Label.new()
		_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay_label.add_theme_font_size_override("font_size", 22)
		box.add_child(_overlay_label)
		_overlay_bar = ProgressBar.new()
		_overlay_bar.custom_minimum_size = Vector2(420, 10)
		_overlay_bar.show_percentage = false
		box.add_child(_overlay_bar)
		add_child(_overlay)
	_overlay_label.text = text
	_overlay_bar.value = 0.0
	_overlay.visible = true


func _hide_overlay() -> void:
	if _overlay:
		_overlay.visible = false


func open_user_profiles() -> void:
	OS.shell_open(ProjectSettings.globalize_path("user://profiles"))


## Godot's built-in menu actions already take the D-pad and left stick for moving between
## controls, but ui_accept / ui_cancel have no controller button - so A couldn't press anything.
## A presses / picks, B backs out (closes a popup or dialog, or the take browser).
static func add_gamepad_ui_buttons() -> void:
	for spec in [[&"ui_accept", JOY_BUTTON_A], [&"ui_cancel", JOY_BUTTON_B]]:
		var has := false
		for e in InputMap.action_get_events(spec[0]):
			has = has or (e is InputEventJoypadButton and e.button_index == spec[1])
		if not has:
			var ev := InputEventJoypadButton.new()
			ev.button_index = spec[1]
			ev.device = -1
			InputMap.action_add_event(spec[0], ev)


# === internals ===

func _restore_last() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var cars := scan_cars()
	var worlds := scan_worlds()
	var modes := scan_modes()
	var c: String = cfg.get_value("selection", "car", "")
	var w: String = cfg.get_value("selection", "world", "")
	var m: String = cfg.get_value("selection", "mode", "")
	if not _has(cars, c):
		c = _first_valid(cars)
	if not _has(worlds, w):
		w = _first_valid(worlds)
	if not _has(modes, m):
		m = _default_mode(modes)
	drive_mode = DriveMode.new()   # neutral: changes nothing
	if c != "" and w != "":
		select(c, w, m)
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


## First run: Standard, not whatever sorts first alphabetically.
func _default_mode(list: Array[Dictionary]) -> String:
	for e in list:
		if e["profile"] != null and String(e["path"]).get_file() == "standard.tres":
			return e["path"]
	return _first_valid(list)


func _first_valid(list: Array[Dictionary]) -> String:
	for e in list:
		if e["profile"] != null:
			return e["path"]
	return ""
