class_name TakeBrowser
extends CanvasLayer
## Spec 2.3 + 2.4. Tab / LB toggles. While open the car is parked, recording is blocked and
## the chase cam follows the replay ghost. Closing keeps a playing ghost running on a loop
## while you drive — for matching a previous take.

signal message(text: String)

@export var car_path: NodePath
@export var recorder_path: NodePath
@export var player_path: NodePath
@export var camera_rig_path: NodePath

const COLS: PackedStringArray = ["★", "Take", "Dur", "Dist", "Peak", "Lat g", "Air"]

var is_open: bool = false
var _car: DrivingCar
var _rec: TakeRecorder
var _player: TakePlayer
var _rig: ChaseCameraRig
var _index: TakeIndex
var _headers: Dictionary = {}   # file → header
var _thumbs: Dictionary = {}    # file → Texture2D
var _selected: String = ""
var _validate_thread: Thread   # dedicated thread — keep off Jolt's WorkerThreadPool

var _panel: PanelContainer
var _tree: Tree
var _count: Label
var _thumb_big: TextureRect
var _details: Label
var _label_edit: LineEdit
var _btn_play: Button
var _btn_stop: Button
var _btn_fav: Button
var _btn_delete: Button
var _btn_export: Button
var _slider: HSlider
var _time: Label
var _loop: CheckBox
var _hide_live: CheckBox
var _fav_only: CheckBox
var _speed: OptionButton
var _status: Label
var _confirm: ConfirmationDialog
var _file_dialog: FileDialog


func _ready() -> void:
	layer = 5
	_car = get_node(car_path) as DrivingCar
	_rec = get_node(recorder_path) as TakeRecorder
	_player = get_node(player_path) as TakePlayer
	_rig = get_node(camera_rig_path) as ChaseCameraRig
	_index = _rec.index   # shared — see TakeRecorder.index
	_build_ui()
	_panel.visible = false
	_rec.take_saved.connect(func(p: String, _s: Dictionary) -> void:
		_thumbs.erase(p.get_file())
		if is_open:
			refresh())
	_player.loaded.connect(_on_player_loaded)
	_player.load_failed.connect(func(m: String) -> void: _set_status("Load failed: " + m))
	_player.stopped.connect(_on_player_stopped)


# === OPEN / CLOSE ===

func _input(event: InputEvent) -> void:
	# _input, not _unhandled_input: Tab is also ui_focus_next and the GUI would eat it.
	if event.is_action_pressed(&"browser_toggle"):
		get_viewport().set_input_as_handled()
		if is_open:
			close()
		else:
			open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"replay_play_pause") and _player.active:
		_player.toggle_play()


func open() -> void:
	if _rec.state != TakeRecorder.State.IDLE:
		message.emit("Finish the take before opening the browser")
		return
	is_open = true
	_panel.visible = true
	_car.use_player_input = false
	_car.input_throttle = 0.0
	_car.input_brake = 0.0
	_car.input_steer = 0.0
	_car.input_handbrake = false
	_rec.blocked = true
	refresh()
	if _player.active:
		_attach_view()
	_tree.grab_focus()


func close() -> void:
	is_open = false
	_panel.visible = false
	_car.use_player_input = true
	_rec.blocked = false
	_car.visible = true
	_rig.replay_cam = null
	_rig.follow(_car)
	if _player.active:
		message.emit("Ghost keeps playing — Tab/LB, then Stop, to remove it")


func _attach_view() -> void:
	_rig.follow(_player.ghost)
	_rig.replay_cam = _player.recorded_cam
	_car.visible = not _hide_live.button_pressed


# === LIST ===

func refresh() -> void:
	var files: Array[String] = []
	var dir := DirAccess.open(_rec.takes_dir)
	if dir:
		for f in dir.get_files():
			if TakeFormat.is_take_file(f):
				files.append(f)
	files.sort()
	files.reverse()
	_headers.clear()
	_tree.clear()
	var root := _tree.create_item()
	var shown := 0
	var sel_item: TreeItem = null
	for f in files:
		if _fav_only.button_pressed and not _index.is_favourite(f):
			continue
		var h := _index.get_header(f)
		if h.is_empty():
			h = TakeFormat.read_header(_path(f))   # first sighting (v1 take, or copied in)
			if h.is_empty():
				continue
			_index.set_header(f, h)
		_headers[f] = h
		var s: Dictionary = h.get("summary", {})
		var it := _tree.create_item(root)
		it.set_metadata(0, f)
		it.set_text(0, "★" if _index.is_favourite(f) else "")
		it.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
		it.set_icon(1, _thumb(f))
		it.set_icon_max_width(1, 44)
		it.set_text(1, _display_name(f))
		it.set_text(2, "%.1fs" % float(s.get("duration_s", 0)))
		it.set_text(3, "%.0fm" % float(s.get("distance_m", 0)))
		it.set_text(4, "%.0f" % float(s.get("peak_speed_kmh", 0)))
		it.set_text(5, "%.2f" % float(s.get("max_lateral_g", 0)))
		it.set_text(6, "%.2fs" % float(s.get("airtime_s", 0)))
		for c in range(2, COLS.size()):
			it.set_text_alignment(c, HORIZONTAL_ALIGNMENT_RIGHT)
		if f == _selected:
			sel_item = it
		shown += 1
	_count.text = "%d take%s%s" % [shown, "" if shown == 1 else "s", " (favourites)" if _fav_only.button_pressed else ""]
	if sel_item:
		sel_item.select(1)
		_show_details(_selected)
	elif shown == 0:
		_selected = ""
		_show_details("")


func item_count() -> int:
	return _tree.get_root().get_child_count() if _tree.get_root() else 0


func select_file(f: String) -> void:
	_selected = f
	refresh()


func _on_tree_selected() -> void:
	var it := _tree.get_selected()
	if it:
		_show_details(it.get_metadata(0))


func _show_details(f: String) -> void:
	_selected = f
	var has := f != "" and _headers.has(f)
	for b: Button in [_btn_play, _btn_fav, _btn_delete, _btn_export]:
		b.disabled = not has
	_label_edit.editable = has
	if not has:
		_thumb_big.texture = null
		_details.text = "No take selected.\nPress Start / R to record one."
		_label_edit.text = ""
		return
	var h: Dictionary = _headers[f]
	var s: Dictionary = h.get("summary", {})
	var m: Dictionary = h.get("meta", {})
	_thumb_big.texture = _thumb(f)
	_label_edit.text = _index.get_label(f)
	_btn_fav.text = "★ Unfavourite" if _index.is_favourite(f) else "☆ Favourite"
	var fv := int(h.get("format_version", 1))
	_details.text = "%s   (%s%s)\n%s\n%.2f s  ·  %d samples  ·  %.1f m\npeak %.1f km/h  ·  lat %.2f g  ·  long %.2f g\nairtime %.2f s  (%d ticks)\n%s\nGodot %s  ·  rig %s" % [
		_display_name(f), f, "" if fv >= 2 else " · format v1, exports as v2", str(m.get("created", "")),
		float(s.get("duration_s", 0)), int(s.get("samples", 0)), float(s.get("distance_m", 0)),
		float(s.get("peak_speed_kmh", 0)), float(s.get("max_lateral_g", 0)), float(s.get("max_longitudinal_g", 0)),
		float(s.get("airtime_s", 0)), int(s.get("airtime_ticks", 0)),
		str(m.get("collision_source", "")), str(m.get("godot_version", "?")), str(m.get("rig_version", "?"))]


func _thumb(f: String) -> Texture2D:
	if _thumbs.has(f):
		return _thumbs[f]
	var png := TakeFormat.stem(_path(f)) + ".png"
	var tex: Texture2D = null
	if FileAccess.file_exists(png):
		var img := Image.load_from_file(png)
		if img:
			tex = ImageTexture.create_from_image(img)
	if tex:
		_thumbs[f] = tex
	return tex


func _display_name(f: String) -> String:
	var l := _index.get_label(f)
	return l if l != "" else TakeFormat.stem(f)


func _path(f: String) -> String:
	return _rec.takes_dir.path_join(f)


# === ACTIONS ===

func replay_selected() -> void:
	if _selected == "":
		return
	_set_status("Loading %s…" % _selected)
	_player.load_take(_path(_selected))


func _on_player_loaded(p: String) -> void:
	_thumbs.erase(p.get_file())   # may have just been generated
	_slider.max_value = maxf(_player.n - 1, 1)
	_set_status("Replaying %s — %d samples" % [_display_name(p.get_file()), _player.n])
	if is_open:
		_attach_view()
		refresh()


func _on_player_stopped() -> void:
	_rig.replay_cam = null
	_rig.follow(_car)
	_car.visible = true


func _on_fav() -> void:
	if _selected != "":
		_index.set_favourite(_selected, not _index.is_favourite(_selected))
		refresh()


func _on_label_submitted(text: String) -> void:
	if _selected != "":
		_index.set_label(_selected, text)
		refresh()
		_tree.grab_focus()


func _on_delete() -> void:
	if _selected == "":
		return
	_confirm.dialog_text = "Move %s (%s) to the recycle bin?" % [_display_name(_selected), _selected]
	_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	var json := _path(_selected)
	if _player.active and _player.path == json:
		_player.stop()
	for p in [json, TakeFormat.stem(json) + ".png"]:
		if FileAccess.file_exists(p):
			var err := OS.move_to_trash(ProjectSettings.globalize_path(p))
			if err != OK:
				DirAccess.remove_absolute(p)
	_index.forget(_selected)
	_thumbs.erase(_selected)
	_set_status("Deleted " + _selected)
	_selected = ""
	refresh()


func _on_export() -> void:
	if _selected == "":
		return
	var base := _display_name(_selected).validate_filename()
	_file_dialog.current_dir = _index.get_setting("last_export_dir",
			OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	_file_dialog.current_file = base + ".json.gz"
	_file_dialog.popup_centered_ratio(0.6)


## Re-encode the take as format v2 at dst (gzipped if dst ends in .gz), then validate the
## written file — all on a dedicated thread. Older v1 takes come out as v2 too, so the
## Maya importer only ever has to read one format.
func export_to(dst: String) -> void:
	if _validate_thread:
		return
	var src := _path(_selected)
	_set_status("Exporting → %s…" % dst)
	_validate_thread = Thread.new()
	_validate_thread.start(func() -> void:
		var r := TakeFormat.load_take(src)
		if r.has("error"):
			_on_validated.call_deferred(dst, PackedStringArray(["read failed: " + str(r["error"])]))
			return
		var err := TakeFormat.write_take(dst, r["meta"], r["summary"], r["data"], r["n"], dst.ends_with(".gz"))
		if err != OK:
			_on_validated.call_deferred(dst, PackedStringArray(["write failed: " + error_string(err)]))
			return
		_on_validated.call_deferred(dst, TakeValidator.validate_file(dst)), Thread.PRIORITY_LOW)
	_index.set_setting("last_export_dir", dst.get_base_dir())


func _on_validated(dst: String, errs: PackedStringArray) -> void:
	_validate_thread.wait_to_finish()
	_validate_thread = null
	if errs.is_empty():
		_set_status("Exported ✓ valid → %s" % dst)
	else:
		_set_status("Exported, but INVALID (%d): %s" % [errs.size(), "; ".join(errs.slice(0, 3))])


func _set_status(t: String) -> void:
	_status.text = t
	if not is_open:
		message.emit(t)


# === PER-FRAME ===

func _process(_delta: float) -> void:
	if not is_open:
		return
	var on := _player.active
	_btn_stop.disabled = not on
	_slider.editable = on
	_btn_play.text = ("❚❚  Pause" if _player.playing else "▶  Play") if on else "▶  Replay"
	if on:
		_slider.set_value_no_signal(_player.pos)
		_time.text = "t %+.2f / %.2f s  (IN→OUT; handles outside)   ·   %s" % [_player.current_time(),
				float(_player.summary.get("duration_s", 0.0)), _display_name(_player.path.get_file())]
	else:
		_time.text = "—"


func _on_play_pressed() -> void:
	if _player.active and _player.path == _path(_selected):
		_player.toggle_play()
	else:
		replay_selected()


# === UI BUILD ===

func _build_ui() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.10, 0.98)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override(&"panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -700.0
	_panel.offset_right = -12.0
	_panel.offset_top = 12.0
	_panel.offset_bottom = -12.0
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	_panel.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "TAKES"
	title.add_theme_font_size_override(&"font_size", 22)
	head.add_child(title)
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.modulate = Color(0.7, 0.7, 0.75)
	head.add_child(_count)
	_fav_only = CheckBox.new()
	_fav_only.text = "Favourites only"
	_fav_only.toggled.connect(func(_on: bool) -> void: refresh())
	head.add_child(_fav_only)
	var folder := Button.new()
	folder.text = "Folder"
	folder.tooltip_text = "Open the takes folder (O)"
	folder.pressed.connect(func() -> void: OS.shell_open(ProjectSettings.globalize_path(_rec.takes_dir)))
	head.add_child(folder)

	_tree = Tree.new()
	_tree.columns = COLS.size()
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 260)
	for c in COLS.size():
		_tree.set_column_title(c, COLS[c])
		_tree.set_column_expand(c, c == 1)
		_tree.set_column_clip_content(c, c == 1)
		if c != 1:
			_tree.set_column_custom_minimum_width(c, 36 if c == 0 else 72)
	_tree.item_selected.connect(_on_tree_selected)
	_tree.item_activated.connect(func() -> void: replay_selected())
	v.add_child(_tree)

	var det := HBoxContainer.new()
	det.add_theme_constant_override(&"separation", 12)
	v.add_child(det)
	_thumb_big = TextureRect.new()
	_thumb_big.custom_minimum_size = Vector2(160, 160)
	_thumb_big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	det.add_child(_thumb_big)
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	det.add_child(dv)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override(&"font_size", 14)
	dv.add_child(_details)
	var lrow := HBoxContainer.new()
	dv.add_child(lrow)
	var ll := Label.new()
	ll.text = "Label"
	lrow.add_child(ll)
	_label_edit = LineEdit.new()
	_label_edit.placeholder_text = "e.g. hero_pass_A — Enter to set"
	_label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label_edit.text_submitted.connect(_on_label_submitted)
	lrow.add_child(_label_edit)

	var btns := HBoxContainer.new()
	v.add_child(btns)
	_btn_play = _button(btns, "▶  Replay", _on_play_pressed)
	_btn_stop = _button(btns, "■  Stop", func() -> void: _player.stop())
	_btn_fav = _button(btns, "☆ Favourite", _on_fav)
	_btn_export = _button(btns, "Export…", _on_export)
	_btn_delete = _button(btns, "Delete", _on_delete)

	_slider = HSlider.new()
	_slider.step = 1.0
	_slider.min_value = 0.0
	_slider.value_changed.connect(func(val: float) -> void:
		if _player.active:
			_player.playing = false
			_player.seek(val))
	v.add_child(_slider)
	_time = Label.new()
	_time.add_theme_font_size_override(&"font_size", 14)
	v.add_child(_time)

	var opts := HBoxContainer.new()
	opts.add_theme_constant_override(&"separation", 16)
	v.add_child(opts)
	_loop = CheckBox.new()
	_loop.text = "Loop"
	_loop.button_pressed = true
	_loop.toggled.connect(func(on: bool) -> void: _player.loop = on)
	opts.add_child(_loop)
	_hide_live = CheckBox.new()
	_hide_live.text = "Hide live car"
	_hide_live.button_pressed = true
	_hide_live.toggled.connect(func(on: bool) -> void:
		if is_open and _player.active:
			_car.visible = not on)
	opts.add_child(_hide_live)
	var sl := Label.new()
	sl.text = "Speed"
	opts.add_child(sl)
	_speed = OptionButton.new()
	for x in [0.25, 0.5, 1.0, 2.0]:
		_speed.add_item("%s×" % str(x))
	_speed.select(2)
	_speed.item_selected.connect(func(i: int) -> void: _player.speed = [0.25, 0.5, 1.0, 2.0][i])
	opts.add_child(_speed)
	var hint := Label.new()
	hint.text = "Y/C: chase ↔ recorded cam   X/P: play/pause"
	hint.modulate = Color(0.65, 0.65, 0.7)
	hint.add_theme_font_size_override(&"font_size", 13)
	opts.add_child(hint)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.75, 0.9, 1.0)
	_status.add_theme_font_size_override(&"font_size", 14)
	v.add_child(_status)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete take"
	_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm)

	_file_dialog = FileDialog.new()
	_file_dialog.title = "Export take"
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.json.gz ; Take, compressed (v2)", "*.json ; Take, plain (v2)"])
	_file_dialog.file_selected.connect(export_to)
	add_child(_file_dialog)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _exit_tree() -> void:
	if _validate_thread and _validate_thread.is_started():
		_validate_thread.wait_to_finish()
