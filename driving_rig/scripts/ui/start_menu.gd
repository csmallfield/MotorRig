extends Control
## Start menu. Lists every car and world profile found on disk (project + your user folder),
## shows what each one is, warns about bad combinations, and starts the sim.
## Gamepad: D-pad between lists, A / double-click picks, Start drives.

const BG := Color(0.06, 0.07, 0.09)
const ACCENT := Color(0.94, 0.54, 0.14)

var _cfg: Node
var _cars: Array[Dictionary] = []
var _worlds: Array[Dictionary] = []
var _modes: Array[Dictionary] = []
var _car_list: ItemList
var _world_list: ItemList
var _mode_list: ItemList
var _mode_info: Label
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
	var keep_mode: String = _cfg.mode_path
	_cars = _cfg.scan_cars()
	_worlds = _cfg.scan_worlds()
	_modes = _cfg.scan_modes()
	_fill(_car_list, _cars, keep_car)
	_fill(_world_list, _worlds, keep_world)
	_fill(_mode_list, _modes, keep_mode)
	_on_changed()


func item_count(which: Variant) -> int:
	if which is bool:
		return (_car_list if which else _world_list).item_count
	return {"cars": _car_list, "worlds": _world_list, "modes": _mode_list}[which].item_count


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
	var m := _selected(_mode_list, _modes)
	_car_info.text = _describe(c)
	_world_info.text = _describe(w)
	_mode_info.text = _describe(m)
	var ok: bool = not c.is_empty() and not w.is_empty() and c["profile"] != null and w["profile"] != null \
			and _cfg.select(c["path"], w["path"], m["path"] if not m.is_empty() and m["profile"] != null else "")
	_drive.disabled = not ok
	var warn: PackedStringArray = _cfg.warnings() if ok else PackedStringArray(["Pick a car and a world."])
	if _cars.is_empty() or _worlds.is_empty() or _modes.is_empty():
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
## Laid out for 1920 x 1080; the project scales the whole UI with the window (stretch mode
## canvas_items), so it looks the same at 4K. Everything is reachable on a controller:
##   D-pad / stick   move: up and down a list, left and right between lists and buttons
##   A               pick: in a list, move on to the next one (car -> world -> driving -> DRIVE);
##                   on a button, press it
##   Start           drive, from anywhere

const LOGO := "res://graphic_elements/SVG/motorrig_logo.svg"


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 16)
	margin.add_child(v)

	var logo := TextureRect.new()
	logo.texture = load(LOGO)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 150)
	v.add_child(logo)
	var sub := Label.new()
	sub.text = "v%s  -  pick a car, a world and how it drives" % ProjectSettings.get_setting("application/config/version", "dev")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override(&"font_size", 18)
	sub.modulate = Color(0.7, 0.72, 0.78)
	v.add_child(sub)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 32)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var car_col := _column(cols, "CAR")
	var world_col := _column(cols, "WORLD")
	var mode_col := _column(cols, "DRIVING")
	_car_list = car_col[0]
	_car_info = car_col[1]
	_world_list = world_col[0]
	_world_info = world_col[1]
	_mode_list = mode_col[0]
	_mode_info = mode_col[1]

	_warn = Label.new()
	_warn.add_theme_color_override(&"font_color", Color(1.0, 0.7, 0.3))
	_warn.add_theme_font_size_override(&"font_size", 16)
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_warn)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override(&"separation", 16)
	v.add_child(btns)
	_drive = Button.new()
	_drive.text = "DRIVE  >"
	_drive.custom_minimum_size = Vector2(260, 60)
	_drive.add_theme_font_size_override(&"font_size", 24)
	_drive.pressed.connect(drive)
	_drive.add_theme_stylebox_override(&"focus", _focus_box())
	btns.add_child(_drive)
	var row: Array[Control] = [_drive]
	for spec: Array in [["Rescan", rescan], ["Open my profiles folder", func() -> void: _cfg.open_user_profiles()],
			["Quit", func() -> void: get_tree().quit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(0, 60)
		b.add_theme_font_size_override(&"font_size", 18)
		b.pressed.connect(spec[1])
		b.add_theme_stylebox_override(&"focus", _focus_box())
		btns.add_child(b)
		row.append(b)

	var hint := Label.new()
	hint.text = ("Controller: D-pad / stick to move, A to pick (car > world > driving > DRIVE), Start to drive.   "
			+ "Profiles are .tres files: project ones in res://profiles/cars|worlds|modes, yours in %s - "
			+ "duplicate one, edit it in the Inspector, then Rescan.") % ProjectSettings.globalize_path("user://profiles")
	hint.modulate = Color(0.55, 0.57, 0.62)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override(&"font_size", 14)
	v.add_child(hint)

	# Focus: explicit, so a controller always goes where it looks like it should.
	var lists: Array[ItemList] = [_car_list, _world_list, _mode_list]
	for i in lists.size():
		var l := lists[i]
		l.focus_neighbor_left = lists[maxi(i - 1, 0)].get_path()
		l.focus_neighbor_right = (lists[i + 1] if i + 1 < lists.size() else _drive).get_path()
		l.focus_neighbor_bottom = _drive.get_path()          # down off the end of a list
		l.focus_neighbor_top = l.get_path()
		l.focus_next = l.focus_neighbor_right
		l.focus_previous = l.focus_neighbor_left
	for i in row.size():
		var b := row[i]
		b.focus_neighbor_top = _car_list.get_path()          # up from the buttons: start at the car
		b.focus_neighbor_bottom = b.get_path()
		b.focus_neighbor_left = row[maxi(i - 1, 0)].get_path()
		b.focus_neighbor_right = row[mini(i + 1, row.size() - 1)].get_path()


## Where the controller is: an accent outline on the focused list or button.
static func _focus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = ACCENT
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	sb.set_expand_margin_all(3)
	return sb


## A (or Enter, or a double-click) in a list: that's the pick - move on to the next column.
func _advance_from(list: ItemList) -> void:
	var order: Array[Control] = [_car_list, _world_list, _mode_list, _drive]
	order[order.find(list) + 1].grab_focus()


func _column(parent: Control, heading: String) -> Array:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 10)
	parent.add_child(col)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override(&"font_size", 24)
	h.add_theme_color_override(&"font_color", ACCENT)
	col.add_child(h)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.size_flags_stretch_ratio = 3.0                     # the list gets most of the height
	list.add_theme_font_size_override(&"font_size", 22)
	list.add_theme_constant_override(&"v_separation", 6)
	list.add_theme_stylebox_override(&"focus", _focus_box())
	list.item_selected.connect(_on_changed)
	list.item_activated.connect(func(_i: int) -> void: _advance_from(list))
	col.add_child(list)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.clip_text = true
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_theme_font_size_override(&"font_size", 15)
	info.modulate = Color(0.82, 0.84, 0.88)
	col.add_child(info)
	return [list, info]
