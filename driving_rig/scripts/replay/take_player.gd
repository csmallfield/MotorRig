class_name TakePlayer
extends Node
## Plays a take back onto a GhostCar — no re-simulation. Loads on a worker thread
## (streaming, one sample per line), steps at physics rate with sub-sample interpolation so
## slow-motion and mismatched tick rates work, and drives a camera from the recorded
## camera channel.

signal loaded(path: String)
signal load_failed(message: String)
signal stopped

@export var ghost_body_material: Material
@export var wheel_material: Material
@export var accent_material: Material

var active: bool = false        ## a take is loaded and the ghost is in the world
var loading: bool = false
var playing: bool = false
var loop: bool = true
var speed: float = 1.0
var pos: float = 0.0            ## sample index (fractional)
var path: String = ""
var meta: Dictionary = {}
var summary: Dictionary = {}
var data := PackedFloat64Array()
var n: int = 0
var take_hz: float = 240.0
var format_version: int = 2
var in_index: int = 0
var out_index: int = 0

var ghost: GhostCar
## The camera that was on screen when the take was shot.
var recorded_cam: Camera3D
## One camera per angle the take recorded (rig 0.7+). Empty for older takes.
var recorded_cams: Array[Camera3D] = []
var recorded_cam_names: PackedStringArray = PackedStringArray()
## Dedicated thread, not WorkerThreadPool: Jolt runs its physics jobs on the pool, and a
## long parse there starves the solver.
var _thread: Thread


func _ready() -> void:
	process_physics_priority = 40   # before the chase camera (50) so it follows this tick's pose
	ghost = GhostCar.new()
	ghost.name = "Ghost"
	ghost.visible = false
	add_child(ghost)
	recorded_cam = Camera3D.new()
	recorded_cam.name = "RecordedCam"
	add_child(recorded_cam)
	for i in TakeFormat.CAMERA_NAMES.size():
		var c := Camera3D.new()
		c.name = "RecordedCam_" + TakeFormat.CAMERA_NAMES[i]
		c.near = 0.05
		c.far = 4000.0
		add_child(c)
		recorded_cams.append(c)


func load_take(take_path: String) -> void:
	if loading:
		return
	loading = true
	_thread = Thread.new()
	_thread.start(_load_task.bind(take_path), Thread.PRIORITY_LOW)


func _load_task(take_path: String) -> void:
	var r := TakeFormat.load_take(take_path)
	_on_loaded.call_deferred(r, take_path)


func _on_loaded(r: Dictionary, take_path: String) -> void:
	_thread.wait_to_finish()
	_thread = null
	loading = false
	if r.has("error"):
		load_failed.emit(str(r["error"]))
		return
	path = take_path
	meta = r["meta"]
	summary = r["summary"]
	data = r["data"]
	n = r["n"]
	format_version = int(r.get("format_version", 1))
	take_hz = float(meta.get("tick_hz", 240))
	in_index = int(meta.get("in_index", 0))
	out_index = int(meta.get("out_index", n - 1))
	# a take only has per-camera tracks if it was recorded with them (rig 0.7+)
	recorded_cam_names = PackedStringArray(meta.get("camera_names", [])) if bool(meta.get("all_cameras", false)) \
			else PackedStringArray()
	ghost.build(meta, ghost_body_material, wheel_material, accent_material)
	ghost.visible = true
	active = true
	playing = true
	seek(0.0)
	_ensure_thumbnail()
	loaded.emit(path)


func stop() -> void:
	active = false
	playing = false
	ghost.visible = false
	data = PackedFloat64Array()
	n = 0
	path = ""
	stopped.emit()


func toggle_play() -> void:
	if not active:
		return
	if not playing and pos >= n - 1:
		seek(0.0)
	playing = not playing


func seek(sample: float) -> void:
	pos = clampf(sample, 0.0, maxf(n - 1, 0))
	_apply()
	ghost.reset_physics_interpolation()
	recorded_cam.reset_physics_interpolation()
	for c in recorded_cams:
		c.reset_physics_interpolation()


## Seconds relative to the take's IN point (handles are negative / past OUT).
func current_time() -> float:
	return (pos - in_index) / take_hz


func _physics_process(delta: float) -> void:
	if not (active and playing):
		return
	pos += delta * take_hz * speed
	if pos >= n - 1:
		if loop:
			seek(0.0)
			return
		pos = n - 1
		playing = false
	_apply()


func _apply() -> void:
	if n == 0:
		return
	var i0 := int(pos)
	var i1 := mini(i0 + 1, n - 1)
	var f := pos - i0
	var o0 := i0 * TakeFormat.STRIDE
	var o1 := i1 * TakeFormat.STRIDE
	ghost.apply(data, o0, o1, f)
	var c0 := o0 + TakeFormat.O_CAM
	var c1 := o1 + TakeFormat.O_CAM
	var cp := Vector3(data[c0], data[c0 + 1], data[c0 + 2]).lerp(Vector3(data[c1], data[c1 + 1], data[c1 + 2]), f)
	var cq := Quaternion(data[c0 + 3], data[c0 + 4], data[c0 + 5], data[c0 + 6]).normalized()
	cq = cq.slerp(Quaternion(data[c1 + 3], data[c1 + 4], data[c1 + 5], data[c1 + 6]).normalized(), f)
	recorded_cam.global_transform = Transform3D(Basis(cq), cp)
	recorded_cam.fov = lerpf(data[c0 + 7], data[c1 + 7], f)
	for k in recorded_cam_names.size():
		var k0 := o0 + TakeFormat.O_CAMS + k * TakeFormat.C_STRIDE
		var k1 := o1 + TakeFormat.O_CAMS + k * TakeFormat.C_STRIDE
		var p := Vector3(data[k0], data[k0 + 1], data[k0 + 2]).lerp(Vector3(data[k1], data[k1 + 1], data[k1 + 2]), f)
		var q := Quaternion(data[k0 + 3], data[k0 + 4], data[k0 + 5], data[k0 + 6]).normalized()
		q = q.slerp(Quaternion(data[k1 + 3], data[k1 + 4], data[k1 + 5], data[k1 + 6]).normalized(), f)
		recorded_cams[k].global_transform = Transform3D(Basis(q), p)
		recorded_cams[k].fov = lerpf(data[k0 + 7], data[k1 + 7], f)


## Takes recorded before thumbnails existed get one the first time they're replayed.
func _ensure_thumbnail() -> void:
	var png := TakeFormat.stem(path) + ".png"
	if not FileAccess.file_exists(png):
		TakeFormat.render_thumbnail(data, n, in_index, out_index).save_png(png)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
