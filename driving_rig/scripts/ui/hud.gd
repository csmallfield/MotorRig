extends CanvasLayer
## On-screen readout plus the utility actions that don't belong to car/camera/recorder
## (recover, reset, open takes folder, help toggle).

@export var car_path: NodePath
@export var recorder_path: NodePath
@export var player_path: NodePath
@export var browser_path: NodePath

var _car: DrivingCar
var _rec: TakeRecorder
var _player: TakePlayer
var _browser: TakeBrowser
var _speed: Label
var _status: Label
var _info: Label
var _help: Label
var _msg: Label
var _msg_time: float = 0.0
var _help_wanted: bool = true

const HELP_TEXT := """GAMEPAD                      KEYBOARD
RT / LT   throttle / brake   W / S  (↑ / ↓)
Left stick   steer           A / D  (← / →)
B   handbrake                Space
X   reverse gear (at a stop) X
Y   next camera (9 angles)   C     1-9 jump to a camera
Start   record / stop        R
LB   take browser            Tab
RB   watch replay full screen V
L3   ghost play / pause      P
View/Back   recover upright  Backspace
                             Esc   back to the start menu
                             Home   reset to spawn
                             O   open takes folder
                             F1   toggle this help
The left trigger is only ever the brake."""


func _ready() -> void:
	_car = get_node(car_path) as DrivingCar
	_rec = get_node(recorder_path) as TakeRecorder
	_player = get_node(player_path) as TakePlayer
	_browser = get_node(browser_path) as TakeBrowser
	_browser.message.connect(func(m: String) -> void: _flash(m, 4.0))
	_car.gear_changed.connect(func(rev: bool) -> void: _flash("Gear: %s" % ("REVERSE" if rev else "DRIVE"), 1.5))
	var rig := get_node_or_null(^"../ChaseCam") as ChaseCameraRig
	if rig:
		rig.camera_changed.connect(func(n: String) -> void: _flash("Camera: %s" % n, 1.5))
	_speed = _make_label(48, Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_status = _make_label(40, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER)
	_info = _make_label(16, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_help = _make_label(16, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_msg = _make_label(20, Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER)
	_help.text = HELP_TEXT
	_rec.take_saved.connect(_on_take_saved)
	_rec.take_failed.connect(func(m: String) -> void: _flash("Take write FAILED: " + m))


func _make_label(font_size: int, preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = font_size
	ls.outline_size = maxi(4, font_size / 6)
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	l.horizontal_alignment = align
	add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 24)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH if align == HORIZONTAL_ALIGNMENT_CENTER \
			else (Control.GROW_DIRECTION_BEGIN if align == HORIZONTAL_ALIGNMENT_RIGHT else Control.GROW_DIRECTION_END)
	return l


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"recover"):
		if _car.reset_locked:
			_flash("Recover disabled while recording")
		else:
			_car.recover_upright()
	elif event.is_action_pressed(&"reset_spawn"):
		if _car.reset_locked:
			_flash("Reset disabled while recording")
		else:
			_car.reset_to_spawn()
	elif event.is_action_pressed(&"open_takes_folder"):
		OS.shell_open(ProjectSettings.globalize_path(_rec.takes_dir))
	elif event.is_action_pressed(&"main_menu"):
		if _rec.state != TakeRecorder.State.IDLE:
			_flash("Finish the take before leaving")
		elif get_node_or_null(^"/root/SimConfig"):
			get_node(^"/root/SimConfig").go_menu()
	elif event.is_action_pressed(&"toggle_help"):
		_help_wanted = not _help_wanted


func _process(delta: float) -> void:
	var kmh := absf(_car.forward_speed) * 3.6
	_speed.text = "%s %3d km/h" % ["R" if _car.is_reversing else "D", roundi(kmh)]

	_speed.visible = not (_browser.is_open or _browser.is_watching)
	_info.visible = not _browser.is_watching
	_help.visible = _help_wanted and not (_browser.is_open or _browser.is_watching)
	match _rec.state:
		TakeRecorder.State.IDLE:
			_status.text = ""
			if _player.active and not _browser.is_open:
				var rig := get_node_or_null(^"../ChaseCam") as ChaseCameraRig
				var cam := ("   ·   %s" % rig.camera_label(rig.active_camera)) if rig and _browser.is_watching else ""
				_status.text = "%s %s  %+.2f s%s" % ["▶" if _player.playing else "❚❚",
					"WATCHING" if _browser.is_watching else "GHOST", _player.current_time(), cam]
		TakeRecorder.State.COUNTDOWN:
			_status.text = str(_rec.countdown_remaining())
		TakeRecorder.State.RECORDING:
			_status.text = "● REC  %s" % _fmt_time(_rec.recorded_seconds())
		TakeRecorder.State.POST_ROLL:
			_status.text = "● REC  %s  (handles)" % _fmt_time(_rec.recorded_seconds())
		TakeRecorder.State.SAVING:
			_status.text = "Saving…"
	_status.modulate = Color(1, 0.3, 0.3) if _rec.state in [TakeRecorder.State.RECORDING,
			TakeRecorder.State.POST_ROLL] else Color.WHITE

	var comp := PackedStringArray()
	for i in 4:
		comp.append("%s %4.1fcm%s" % [DrivingCar.WHEEL_NAMES[i], _car.wheel_compression[i] * 100.0,
				"" if _car.wheel_grounded[i] else "*"])
	_info.text = "%d fps · %d Hz physics · %s\n%s\nsteer %+.2f  thr %.2f  brk %.2f%s" % [
		Engine.get_frames_per_second(), Engine.physics_ticks_per_second,
		ProjectSettings.get_setting("physics/3d/physics_engine"),
		"  ".join(comp), _car.input_steer, _car.input_throttle, _car.input_brake,
		"  HANDBRAKE" if _car.input_handbrake else ""]

	if _msg_time > 0.0:
		_msg_time -= delta
		_msg.modulate.a = clampf(_msg_time, 0.0, 1.0)


func _on_take_saved(path: String, s: Dictionary) -> void:
	_flash("Saved %s — %d samples · %.2f s · %.0f m · peak %.0f km/h · %.2f g lat\n%s" % [
		path.get_file(), s["samples"], s["duration_s"], s["distance_m"], s["peak_speed_kmh"],
		s["max_lateral_g"], ProjectSettings.globalize_path(path)], 6.0)


func _flash(text: String, seconds: float = 3.0) -> void:
	_msg.text = text
	_msg_time = seconds
	_msg.modulate.a = 1.0


func _fmt_time(sec: float) -> String:
	return "%02d:%05.2f" % [int(sec) / 60, fmod(sec, 60.0)]
