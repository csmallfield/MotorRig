class_name TakeRecorder
extends Node
## Per-tick capture into a pre-allocated ring buffer. The ring runs continuously, so the
## pre-roll handle is always available (and "save the last N seconds" is possible later).
##
## Start → 3-2-1 → IN … Start → OUT → post-roll handle → write on a worker thread.
## Nothing is allocated in _physics_process while a take is live.
##
## Layout lives in TakeFormat. File layout: line 1 is `{"meta":{…},"summary":{…},` so a browser can read the header
## by reading one line; the whole file is still a single valid JSON document.

signal state_changed(new_state: int)
signal take_saved(path: String, summary: Dictionary)
signal take_failed(message: String)

enum State { IDLE, COUNTDOWN, RECORDING, POST_ROLL, SAVING }

const STRIDE: int = TakeFormat.STRIDE
const O_WHEELS: int = TakeFormat.O_WHEELS
const W_STRIDE: int = TakeFormat.W_STRIDE

@export var car_path: NodePath
@export var camera_rig_path: NodePath
@export var terrain_path: NodePath
@export var countdown_seconds: int = 3
@export var max_take_seconds: float = 180.0
@export var handle_frames: int = 8
## Handles are specified in frames; ticks are sized for the slowest delivery rate so
## there are ≥ `handle_frames` of handle at any fps chosen later in Maya.
@export var handle_fps_basis: float = 24.0
@export var unit_scale: float = 100.0
@export var takes_dir: String = "user://takes"

var state: State = State.IDLE
var tick_hz: int = 240
var handle_ticks: int = 80
var last_saved_path: String = ""
var blocked: bool = false   ## set by the take browser — no new takes while it's open
var last_summary: Dictionary = {}

var _car: DrivingCar
var _cam_rig: ChaseCameraRig
var _terrain: Terrain
var _buf := PackedFloat64Array()
var _cap: int = 0
var _max_ticks: int = 0
var _tick: int = 0
var _in_tick: int = -1
var _out_tick: int = -1
var _countdown_end: int = 0
var _toggle_requested: bool = false
var _prev_q := Quaternion.IDENTITY
var _thread: Thread


func _ready() -> void:
	process_physics_priority = 100   # sample after car (0) and camera (50) have updated
	_car = get_node(car_path) as DrivingCar
	_cam_rig = get_node(camera_rig_path) as ChaseCameraRig
	_terrain = get_node_or_null(terrain_path) as Terrain
	tick_hz = Engine.physics_ticks_per_second
	handle_ticks = ceili(handle_frames * tick_hz / handle_fps_basis)
	_max_ticks = int(max_take_seconds * tick_hz)
	_cap = _max_ticks + handle_ticks * 2 + tick_hz * 10   # 10 s margin for the writer
	_buf.resize(_cap * STRIDE)
	_buf.fill(0.0)
	DirAccess.make_dir_recursive_absolute(takes_dir)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"record_toggle"):
		request_toggle()


## Consumed on the next physics tick so IN/OUT land on an exact sample.
func request_toggle() -> void:
	_toggle_requested = true


func countdown_remaining() -> int:
	return ceili(float(_countdown_end - _tick) / tick_hz) if state == State.COUNTDOWN else 0


func recorded_seconds() -> float:
	match state:
		State.RECORDING:
			return float(_tick - _in_tick) / tick_hz
		State.POST_ROLL, State.SAVING:
			return float(_out_tick - _in_tick) / tick_hz
	return 0.0


func _physics_process(_delta: float) -> void:
	_capture(_tick)
	var toggle := _toggle_requested
	_toggle_requested = false
	match state:
		State.IDLE:
			if toggle and not blocked:
				_countdown_end = _tick + countdown_seconds * tick_hz
				_car.reset_locked = true
				_set_state(State.COUNTDOWN)
		State.COUNTDOWN:
			if toggle:
				_car.reset_locked = false
				_set_state(State.IDLE)
			elif _tick >= _countdown_end:
				_in_tick = _tick
				_set_state(State.RECORDING)
		State.RECORDING:
			if toggle or _tick - _in_tick >= _max_ticks:
				_out_tick = _tick
				_set_state(State.POST_ROLL)
		State.POST_ROLL:
			if _tick >= _out_tick + handle_ticks:
				_finalize()
	_tick += 1


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


# === CAPTURE (hot path: indexed writes only) ===

func _capture(tick: int) -> void:
	var b := (tick % _cap) * STRIDE
	var xf := _car.global_transform
	var q := xf.basis.get_rotation_quaternion()
	if q.dot(_prev_q) < 0.0:   # keep hemisphere continuous for resampling
		q = -q
	_prev_q = q
	var v := _car.linear_velocity
	var av := _car.angular_velocity
	_buf[b + 0] = xf.origin.x
	_buf[b + 1] = xf.origin.y
	_buf[b + 2] = xf.origin.z
	_buf[b + 3] = q.x
	_buf[b + 4] = q.y
	_buf[b + 5] = q.z
	_buf[b + 6] = q.w
	_buf[b + 7] = v.x
	_buf[b + 8] = v.y
	_buf[b + 9] = v.z
	_buf[b + 10] = av.x
	_buf[b + 11] = av.y
	_buf[b + 12] = av.z
	_buf[b + 13] = _car.input_throttle
	_buf[b + 14] = _car.input_brake
	_buf[b + 15] = _car.input_steer
	_buf[b + 16] = 1.0 if _car.input_handbrake else 0.0
	var cam := _cam_rig.active_camera
	if cam:
		var cx := cam.global_transform
		var cq := cx.basis.get_rotation_quaternion()
		_buf[b + 17] = cx.origin.x
		_buf[b + 18] = cx.origin.y
		_buf[b + 19] = cx.origin.z
		_buf[b + 20] = cq.x
		_buf[b + 21] = cq.y
		_buf[b + 22] = cq.z
		_buf[b + 23] = cq.w
		_buf[b + 24] = cam.fov
	for w in 4:
		var o := b + O_WHEELS + w * W_STRIDE
		var cp := _car.wheel_contact_p[w]
		var cn := _car.wheel_contact_n[w]
		_buf[o + 0] = _car.wheel_compression[w]
		_buf[o + 1] = _car.wheel_steer[w]
		_buf[o + 2] = _car.wheel_spin[w]
		_buf[o + 3] = float(_car.wheel_grounded[w])
		_buf[o + 4] = cp.x
		_buf[o + 5] = cp.y
		_buf[o + 6] = cp.z
		_buf[o + 7] = cn.x
		_buf[o + 8] = cn.y
		_buf[o + 9] = cn.z
		_buf[o + 10] = _car.wheel_slip_long[w]
		_buf[o + 11] = _car.wheel_slip_lat[w]


# === FINALIZE ===

func _finalize() -> void:
	_set_state(State.SAVING)
	_car.reset_locked = false
	var start := maxi(_in_tick - handle_ticks, maxi(_tick - _cap + 1, 0))
	var n := _tick - start + 1
	var a := start % _cap
	var data: PackedFloat64Array
	if a + n <= _cap:
		data = _buf.slice(a * STRIDE, (a + n) * STRIDE)
	else:
		data = _buf.slice(a * STRIDE)
		data.append_array(_buf.slice(0, (n - (_cap - a)) * STRIDE))

	var take_no := _next_take_number()
	var path := "%s/take_%04d.json" % [takes_dir, take_no]
	var meta := {
		"take": take_no,
		"tick_hz": tick_hz,
		"unit_scale": unit_scale,
		"up_axis": "Y",
		"forward": "-Z",
		"collision_source": _terrain.collision_source_id if _terrain else "unknown",
		"handles": handle_frames,
		"handle_fps_basis": handle_fps_basis,
		"handle_ticks": handle_ticks,
		"in_index": _in_tick - start,
		"out_index": _out_tick - start,
		"godot_version": Engine.get_version_info()["string"],
		"rig_version": ProjectSettings.get_setting("application/config/version", "dev"),
		"created": Time.get_datetime_string_from_system(),
	}
	meta.merge(_car.build_take_meta())
	_thread = Thread.new()
	_thread.start(_write_take.bind(path, meta, data, n))


func _next_take_number() -> int:
	var best := 0
	var dir := DirAccess.open(takes_dir)
	if dir:
		for f in dir.get_files():
			if f.begins_with("take_") and f.ends_with(".json"):
				best = maxi(best, f.substr(5, f.length() - 10).to_int())
	return best + 1


# === WRITER (worker thread) ===

func _write_take(path: String, meta: Dictionary, data: PackedFloat64Array, n: int) -> void:
	var in_i: int = meta["in_index"]
	var out_i: int = meta["out_index"]
	var summary := _summarize(data, n, in_i, out_i)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_on_write_done.call_deferred(false, path, {}, "open failed (%d)" % FileAccess.get_open_error())
		return
	f.store_string(TakeFormat.header_line(meta, summary))
	var inv := 1.0 / tick_hz
	for i in n:
		f.store_string(TakeFormat.sample_line(data, i * STRIDE, float(i - in_i) * inv)
				+ (",\n" if i < n - 1 else "\n"))
	f.store_string("]}\n")
	var err := f.get_error()
	f.close()
	if err != OK and err != ERR_FILE_EOF:
		_on_write_done.call_deferred(false, path, {}, "write error (%d)" % err)
		return
	TakeFormat.render_thumbnail(data, n, in_i, out_i).save_png(path.get_basename() + ".png")
	_on_write_done.call_deferred(true, path, summary, "")


func _summarize(d: PackedFloat64Array, n: int, in_i: int, out_i: int) -> Dictionary:
	var dt := 1.0 / tick_hz
	var distance := 0.0
	var peak_speed := 0.0
	var max_lat := 0.0
	var max_long := 0.0
	var air := 0
	var finite := true
	var k := maxi(1, tick_hz / 40)   # 25 ms central difference for accelerations
	for i in range(in_i, out_i + 1):
		var o := i * STRIDE
		var p := Vector3(d[o], d[o + 1], d[o + 2])
		if not p.is_finite():
			finite = false
			continue
		if i > in_i:
			var po := (i - 1) * STRIDE
			distance += p.distance_to(Vector3(d[po], d[po + 1], d[po + 2]))
		var vel := Vector3(d[o + 7], d[o + 8], d[o + 9])
		peak_speed = maxf(peak_speed, vel.length())
		var grounded_any := false
		for w in 4:
			if d[o + O_WHEELS + w * W_STRIDE + 3] > 0.5:
				grounded_any = true
		if not grounded_any:
			air += 1
		if i - k >= 0 and i + k < n:
			var a := (_vel_at(d, i + k) - _vel_at(d, i - k)) / (2.0 * k * dt)
			var basis := Basis(Quaternion(d[o + 3], d[o + 4], d[o + 5], d[o + 6]))
			max_lat = maxf(max_lat, absf(a.dot(basis.x)) / 9.81)
			max_long = maxf(max_long, absf(a.dot(-basis.z)) / 9.81)
	return {
		"duration_s": snappedf(float(out_i - in_i) * dt, 0.0001),
		"samples": n,
		"distance_m": snappedf(distance, 0.01),
		"peak_speed_kmh": snappedf(peak_speed * 3.6, 0.1),
		"max_lateral_g": snappedf(max_lat, 0.01),
		"max_longitudinal_g": snappedf(max_long, 0.01),
		"airtime_ticks": air,
		"airtime_s": snappedf(air * dt, 0.001),
		"finite": finite,
	}


func _vel_at(d: PackedFloat64Array, i: int) -> Vector3:
	var o := i * STRIDE + TakeFormat.O_VEL
	return Vector3(d[o], d[o + 1], d[o + 2])


func _on_write_done(ok: bool, path: String, summary: Dictionary, message: String) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	_set_state(State.IDLE)
	if ok:
		last_saved_path = path
		last_summary = summary
		print("Take saved: %s  (%d samples, %.2f s)" % [ProjectSettings.globalize_path(path),
				summary["samples"], summary["duration_s"]])
		take_saved.emit(path, summary)
	else:
		push_error("Take write failed: %s — %s" % [path, message])
		take_failed.emit(message)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
