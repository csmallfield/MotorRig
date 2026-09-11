extends Control
## Start menu. Lists every car and world profile found on disk (project + your user folder),
## shows what each one is, warns about bad combinations, and starts the sim.
## Gamepad: D-pad between lists, A / double-click picks, Start drives.

const BG := Color(0.06, 0.07, 0.09)
const ACCENT := Color(0.94, 0.54, 0.14)

var _cfg: Node
var _cars: Array[Dictionary] = []
var _worlds: Array[Dictionary] = []
var _car_list: ItemList
var _world_list: ItemList
var _car_info: Label
var _world_info: Label
var _warn: Label
var _drive: Button


func _ready() -> void:
	_cfg = get_node(^"/root/SimConfig")
	_build()
	rescan()
	_drive.grab_focus()


func rescan() -> void:
	var keep_car: String = _cfg.car_path
	var keep_world: String = _cfg.world_path
	_cars = _cfg.scan_cars()
	_worlds = _cfg.scan_worlds()
	_fill(_car_list, _cars, keep_car)
	_fill(_world_list, _worlds, keep_world)
	_on_changed()


func item_count(cars: bool) -> int:
	return (_car_list if cars else _world_list).item_count


func drive() -> void:
	if _drive.disabled:
		return
	_cfg.start_sim()


func _fill(list: ItemList, entries: Array[Dictionary], keep: String) -> void:
	list.clear()
	var first := -1
	var kept := -1
	for i in entries.size():
		var e: Dictionary = entries[i]
		var valid: bool = e["profile"] != null
		var label: String = (e["name"] + ("   (yours)" if e["user"] else "")) if valid \
				else "%s   - invalid" % String(e["path"]).get_file()
		var idx := list.add_item(label)
		list.set_item_tooltip(idx, "%s\n%s" % [e["path"], e["error"]] if e["error"] != "" else e["path"])
		if not valid:
			list.set_item_disabled(idx, true)
			list.set_item_custom_fg_color(idx, Color(0.6, 0.35, 0.35))
			continue
		if first == -1:
			first = idx
		if e["path"] == keep:
			kept = idx
	var sel := kept if kept >= 0 else first
	if sel >= 0:
		list.select(sel)


func _selected(list: ItemList, entries: Array[Dictionary]) -> Dictionary:
	var s := list.get_selected_items()
	return entries[s[0]] if s.size() > 0 and s[0] < entries.size() else {}


func _on_changed(_i: int = 0) -> void:
	var c := _selected(_car_list, _cars)
	var w := _selected(_world_list, _worlds)
	_car_info.text = _describe(c)
	_world_info.text = _describe(w)
	var ok: bool = not c.is_empty() and not w.is_empty() and c["profile"] != null and w["profile"] != null \
			and _cfg.select(c["path"], w["path"])
	_drive.disabled = not ok
	var warn: PackedStringArray = _cfg.warnings() if ok else PackedStringArray(["Pick a car and a world."])
	if _cars.is_empty() or _worlds.is_empty():
		warn.append("No profiles found - add .tres files to res://profiles or your profiles folder.")
	_warn.text = "\n".join(warn)


func _describe(e: Dictionary) -> String:
	if e.is_empty() or e["profile"] == null:
		return ""
	var p: Resource = e["profile"]
	return "%s\n\n%s\n\n%s" % [p.call("summary"), p.get("description"), e["path"]]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"record_toggle"):      # Start / R
		get_viewport().set_input_as_handled()
		drive()


# === UI ===

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	margin.add_child(v)

	var title := Label.new()
	title.text = "DRIVING RIG"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", ACCENT)
	v.add_child(title)
	var sub := Label.new()
	sub.text = "v%s  -  pick a car and a world" % ProjectSettings.get_setting("application/config/version", "dev")
	sub.modulate = Color(0.7, 0.72, 0.78)
	v.add_child(sub)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var car_col := _column(cols, "CAR")
	var world_col := _column(cols, "WORLD")
	_car_list = car_col[0]
	_car_info = car_col[1]
	_world_list = world_col[0]
	_world_info = world_col[1]
	_car_list.focus_neighbor_right = _world_list.get_path()
	_world_list.focus_neighbor_left = _car_list.get_path()

	_warn = Label.new()
	_warn.add_theme_color_override(&"font_color", Color(1.0, 0.7, 0.3))
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_warn)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override(&"separation", 12)
	v.add_child(btns)
	_drive = Button.new()
	_drive.text = "DRIVE  >"
	_drive.custom_minimum_size = Vector2(220, 52)
	_drive.add_theme_font_size_override(&"font_size", 22)
	_drive.pressed.connect(drive)
	btns.add_child(_drive)
	for spec: Array in [["Rescan", rescan], ["Open my profiles folder", func() -> void: _cfg.open_user_profiles()],
			["Quit", func() -> void: get_tree().quit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(spec[1])
		btns.add_child(b)

	var hint := Label.new()
	hint.text = ("Profiles are .tres files: project ones in res://profiles/cars|worlds, yours in %s  -  "
			+ "duplicate one, edit it in the Inspector, then Rescan.   Gamepad: D-pad, A to pick, Start to drive.") % \
			ProjectSettings.globalize_path("user://profiles")
	hint.modulate = Color(0.55, 0.57, 0.62)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", 13)
	v.add_child(hint)


func _column(parent: Control, heading: String) -> Array:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	parent.add_child(col)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override(&"font_size", 20)
	col.add_child(h)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 220)
	list.add_theme_font_size_override(&"font_size", 18)
	list.item_selected.connect(_on_changed)
	list.item_activated.connect(func(_i: int) -> void: drive())
	col.add_child(list)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override(&"font_size", 14)
	info.modulate = Color(0.82, 0.84, 0.88)
	col.add_child(info)
	return [list, info]
