class_name ChaseCameraRig
extends Node3D
## Camera director. Nine cameras, each updated every physics tick whether or not it is on
## screen, so every one can be recorded into the take and switching never jumps:
##
##   1 chase      lagged spring-arm follow (the default)
##   2 driver     driver's eye (the car's DriverCam; live car only)
##   3 heli       high overhead follow, slow heading lag, looking down with a little lead
##   4 front      tracking vehicle ahead of the car, looking back at it
##   5 side       Russian-arm profile: alongside, matching speed, slight lead
##   6 wheel      rigid mount low on the left flank, looking forward at the front wheel
##   7 bumper     rigid mount on the front bumper, looking ahead
##   8 trackside  broadcast camera planted ahead of the car; pans and zooms as it passes,
##                then leapfrogs ahead again
##   9 orbit      slow orbit around the car
##   10 crane      starts low ahead, cranes up and back over the car as it passes, then resets
##   11 drone      loose FPV chase: swings wide on the outside of turns, drifts in height
##   12 lowchase   knee-high behind the car, long lens - speed and dust
##   13 pan        locked-off tripod that only pans and tilts; replants when the car gets far
##   14 rearwheel  rigid mount at the rear wheel, looking back along the car
##
## C / gamepad Y cycles; number keys 1-9 jump. Everything follows `_follow` - the live car, or
## the replay ghost (where "driver" is replaced by the take's recorded camera).
## Runs in _physics_process at tick rate: deterministic, and physics-interpolated like the car.

signal camera_changed(camera_name: String)

@export var car_path: NodePath
@export var pivot_height: float = 1.3
@export var arm_length: float = 6.5
@export var pitch_deg: float = -11.0
@export var position_sharpness: float = 14.0   ## 1/s - higher = tighter follow
@export var yaw_sharpness: float = 3.5
@export var chase_fov: float = 60.0

@onready var _arm: SpringArm3D = $Arm
@onready var _chase_cam: Camera3D = $Arm/Camera

var active_camera: Camera3D
## All cameras in TakeFormat.CAMERA_NAMES order (what the recorder captures).
var cameras: Array[Camera3D] = []
## Set by the browser while a replay is on screen; takes the driver cam's place in the cycle.
var replay_cam: Camera3D = null:
	set(v):
		replay_cam = v
		if v == null and active_camera != null and not cameras.has(active_camera):
			_set_active(_chase_cam)
## The take's own recorded cameras, added to the cycle while watching a replay.
var replay_cams: Array[Camera3D] = []
var replay_cam_names: PackedStringArray = PackedStringArray()


## While watching a replay: every live camera aimed at the ghost, then every angle the take
## itself recorded. Otherwise the live set.
func watch_list() -> Array[Camera3D]:
	var out := cycle_list()
	out.append_array(replay_cams)
	return out

var _car: DrivingCar
var _follow: Node3D
var _driver_cam: Camera3D
var _yaw: float = 0.0
var _cams := {}          # name -> Camera3D
var _state := {}         # per-camera smoothing state
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	process_physics_priority = 50   # after the car (0) and player (40), before the recorder (100)
	top_level = true
	_car = get_node(car_path) as DrivingCar
	_follow = _car
	_driver_cam = _car.get_node("DriverCam") as Camera3D
	_arm.spring_length = arm_length
	_arm.rotation_degrees.x = pitch_deg
	var s := SphereShape3D.new()
	s.radius = 0.25
	_arm.shape = s
	_arm.collision_mask = DrivingCar.LAYER_WORLD
	_arm.add_excluded_object(_car.get_rid())   # the ghost has no collider, nothing to exclude
	_chase_cam.fov = chase_fov
	for n in TakeFormat.CAMERA_NAMES:
		var cam: Camera3D
		if n == "chase":
			cam = _chase_cam
		elif n == "driver":
			cam = _driver_cam
		else:
			cam = Camera3D.new()
			cam.name = "Cam_" + n
			cam.top_level = true
			cam.near = 0.05
			cam.far = 4000.0
			add_child(cam)
		cameras.append(cam)
		_cams[n] = cam
	_car.teleported.connect(func() -> void: if _follow == _car: snap())
	snap()
	_set_active(_chase_cam)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_toggle"):
		cycle(1)
	elif event.is_action_pressed(&"camera_prev"):
		cycle(-1)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			select_index(k - KEY_1)


## The cameras C cycles through right now (replay swaps the driver cam for the recorded one).
func cycle_list() -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	for i in cameras.size():
		if TakeFormat.CAMERA_NAMES[i] == "driver" and _follow != _car:
			if replay_cam:
				out.append(replay_cam)
			continue
		out.append(cameras[i])
	return out


func cycle(step: int) -> void:
	var list := watch_list() if not replay_cams.is_empty() else cycle_list()
	var i := list.find(active_camera)
	_set_active(list[(i + step + list.size()) % list.size()])


func select_index(i: int) -> void:
	if i < 0 or i >= cameras.size():
		return
	var cam := cameras[i]
	if TakeFormat.CAMERA_NAMES[i] == "driver" and _follow != _car:
		cam = replay_cam if replay_cam else _chase_cam
	_set_active(cam)


func active_index() -> int:
	return cameras.find(active_camera)   # -1 while a replay's recorded camera is on screen


func camera_label(cam: Camera3D) -> String:
	if cam == replay_cam:
		return "as recorded"
	var k := replay_cams.find(cam)
	if k >= 0:
		return "take: %s" % (replay_cam_names[k] if k < replay_cam_names.size() else "?")
	var i := cameras.find(cam)
	return TakeFormat.CAMERA_NAMES[i] if i >= 0 else "?"


## Point every camera at another body (the replay ghost) or back at the car.
func follow(target: Node3D) -> void:
	if target == _follow:
		return
	_follow = target
	if active_camera == _driver_cam and target != _car:
		_set_active(_chase_cam)
	snap()


func snap() -> void:
	global_position = _target_pos()
	_yaw = _target_yaw()
	rotation = Vector3(0.0, _yaw, 0.0)
	_state.clear()
	_update_cinematic(0.0, true)
	reset_physics_interpolation()
	for c in cameras:
		c.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	global_position = global_position.lerp(_target_pos(), 1.0 - exp(-position_sharpness * delta))
	_yaw = lerp_angle(_yaw, _target_yaw(), 1.0 - exp(-yaw_sharpness * delta))
	rotation = Vector3(0.0, _yaw, 0.0)
	_update_cinematic(delta, false)


func _target_pos() -> Vector3:
	return _follow.global_position + Vector3.UP * pivot_height


func _target_yaw() -> float:
	var fwd := -_follow.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-4:
		return _yaw
	return atan2(-fwd.x, -fwd.z)


func _set_active(cam: Camera3D) -> void:
	active_camera = cam
	cam.make_current()
	camera_changed.emit(camera_label(cam))


# === cinematic cameras ===

func _update_cinematic(dt: float, snap_now: bool) -> void:
	if _space == null:
		_space = get_world_3d().direct_space_state
	var f := _follow.global_transform
	var p := f.origin
	var fwd := -f.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var vel := (_follow as RigidBody3D).linear_velocity if _follow is RigidBody3D else _ghost_velocity(p, dt)

	# heli: high and behind, slow heading, looking down with lead
	var hf := _smooth_dir("heli_dir", fwd, 1.0, dt, snap_now)
	var heli_pos := _clear_ground(p + Vector3.UP * 28.0 - hf * 18.0, 10.0)
	_place("heli", heli_pos, p + fwd * 5.0, 2.5, 6.0, 35.0, dt, snap_now)

	# front: tracking vehicle ahead, looking back
	var ff := _smooth_dir("front_dir", fwd, 3.0, dt, snap_now)
	_place("front", _clear_ground(p + ff * 9.0 + Vector3.UP * 1.3, 0.6), p + Vector3.UP * 0.4, 6.0, 10.0, 50.0, dt, snap_now)

	# side: Russian arm alongside (driver's side), slight lead
	var sf := _smooth_dir("side_dir", fwd, 3.0, dt, snap_now)
	var right := sf.cross(Vector3.UP).normalized()
	_place("side", _clear_ground(p - right * 6.5 + Vector3.UP * 1.1 + sf * 1.0, 0.5), p + Vector3.UP * 0.4, 5.0, 10.0, 42.0, dt, snap_now)

	# wheel: rigid, low on the left flank behind the front wheel, looking at it
	var hp := _hardpoint(0)
	var r := _wheel_radius()
	_rigid("wheel", f, Vector3(hp.x - 0.35, hp.y - 0.30, hp.z + 1.3), Vector3(hp.x + 0.05, hp.y - 0.35, hp.z - 1.5), 70.0)

	# bumper: rigid on the nose, looking ahead
	var bs := _body_size()
	_rigid("bumper", f, Vector3(0.0, -bs.y * 0.5 + r * 0.9, -bs.z * 0.5 - 0.05),
			Vector3(0.0, -bs.y * 0.5 + r * 0.9, -bs.z * 0.5 - 20.0), 75.0)

	# trackside: planted ahead, pans + zooms, leapfrogs when the car is past or far
	var ts: Dictionary = _state.get("trackside", {})
	var plant: Vector3 = ts.get("plant", Vector3.INF)
	var rel := p - plant
	var replant := snap_now or plant == Vector3.INF or rel.length() > 80.0 or rel.dot(fwd) > 25.0
	if replant:
		var side_sign: float = -float(ts.get("side", 1.0))
		var ahead := clampf(maxf(vel.length(), 8.0) * 3.0, 30.0, 70.0)
		plant = _clear_ground(p + fwd * ahead + fwd.cross(Vector3.UP).normalized() * 9.0 * side_sign + Vector3.UP * 1.6, 1.6)
		_state["trackside"] = {"plant": plant, "side": side_sign}
	var dist := plant.distance_to(p)
	_look("trackside", plant, p + Vector3.UP * 0.4, 8.0, snap_now or replant,
			clampf(rad_to_deg(2.0 * atan(4.5 / maxf(dist, 1.0))), 6.0, 55.0), dt)

	# crane: plant ahead and low, rise and swing back over the car as it goes past
	var cr: Dictionary = _state.get("crane", {})
	var cplant: Vector3 = cr.get("plant", Vector3.INF)
	var crel := p - cplant
	var crane_replant := snap_now or cplant == Vector3.INF or crel.length() > 90.0 or crel.dot(fwd) > 18.0
	if crane_replant:
		cplant = _clear_ground(p + fwd * clampf(maxf(vel.length(), 8.0) * 2.6, 26.0, 60.0)
				+ fwd.cross(Vector3.UP).normalized() * 5.0, 0.8)
		cr = {"plant": cplant, "t": 0.0}
		_state["crane"] = cr
	var ct: float = minf(float(cr.get("t", 0.0)) + dt * 0.3, 1.0)
	cr["t"] = ct
	var rise := ct * ct * (3.0 - 2.0 * ct)        # ease up and back
	var crane_pos := cplant + Vector3.UP * (1.2 + 13.0 * rise) - fwd * (18.0 * rise)
	_place("crane", _clear_ground(crane_pos, 1.0), p + Vector3.UP * 0.4, 6.0, 5.0,
			lerpf(50.0, 42.0, rise), dt, crane_replant)   # snap on replant: easing loses the car

	# drone: swings to the outside of the turn and breathes in height - handheld FPV feel
	var turn := clampf(-_follow_angular_y() * 1.4, -1.0, 1.0)
	var side_dir := fwd.cross(Vector3.UP).normalized()
	var bob: float = float(_state.get("orbit_ang", 0.0)) * 0.6
	var drone_target := p - fwd * 7.5 + side_dir * (5.0 * turn) + Vector3.UP * (3.4 + 0.8 * sin(bob))
	_place("drone", _clear_ground(drone_target, 1.2), p + fwd * 3.0, 3.0, 4.0, 55.0, dt, snap_now)

	# lowchase: knee-high, close, long lens
	var lf := _smooth_dir("low_dir", fwd, 2.0, dt, snap_now)
	_place("lowchase", _clear_ground(p - lf * 7.0 + Vector3.UP * 0.45, 0.35), p + Vector3.UP * 0.5,
			8.0, 7.0, 34.0, dt, snap_now)

	# pan: a locked-off tripod. It never moves - it only pans and tilts - until the car gets
	# far enough away that there is nothing to see, then it replants.
	var pn: Dictionary = _state.get("pan", {})
	var pplant: Vector3 = pn.get("plant", Vector3.INF)
	if snap_now or pplant == Vector3.INF or pplant.distance_to(p) > 110.0:
		pplant = _clear_ground(p - fwd * 14.0 + fwd.cross(Vector3.UP).normalized() * 16.0 + Vector3.UP * 3.0, 3.0)
		_state["pan"] = {"plant": pplant}
	_look("pan", pplant, p + Vector3.UP * 0.4, 5.0, snap_now,
			clampf(rad_to_deg(2.0 * atan(5.0 / maxf(pplant.distance_to(p), 1.0))), 8.0, 60.0), dt)

	# rearwheel: rigid at the back wheel, looking forward along the flank
	var rhp := _hardpoint(3)
	_rigid("rearwheel", f, Vector3(rhp.x + 0.42, rhp.y + 0.05, rhp.z + 0.5),
			Vector3(rhp.x + 0.1, rhp.y - 0.15, rhp.z - 2.0), 68.0)

	# orbit: slow circle in world space
	var ang: float = float(_state.get("orbit_ang", 0.0)) + 0.25 * dt
	_state["orbit_ang"] = ang
	var orbit_pos := _clear_ground(p + Vector3(cos(ang), 0.0, sin(ang)) * 9.0 + Vector3.UP * 2.5, 0.8)
	_place("orbit", orbit_pos, p + Vector3.UP * 0.4, 8.0, 12.0, 50.0, dt, snap_now)


func _place(n: String, target: Vector3, look_at_pt: Vector3, pos_sharp: float, rot_sharp: float,
		fov: float, dt: float, snap_now: bool) -> void:
	var cam: Camera3D = _cams[n]
	var pos := target if snap_now else cam.global_position.lerp(target, 1.0 - exp(-pos_sharp * dt))
	_look(n, pos, look_at_pt, rot_sharp, snap_now, fov, dt)


func _look(n: String, pos: Vector3, look_at_pt: Vector3, rot_sharp: float, snap_now: bool, fov: float,
		dt: float = 0.0) -> void:
	var cam: Camera3D = _cams[n]
	var dir := look_at_pt - pos
	if dir.length_squared() < 1e-6:
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	var want := Basis.looking_at(dir, up)
	var b := want if snap_now else cam.global_basis.orthonormalized().slerp(want, 1.0 - exp(-rot_sharp * dt))
	cam.global_transform = Transform3D(b, pos)
	cam.fov = fov


func _rigid(n: String, f: Transform3D, local_pos: Vector3, local_look: Vector3, fov: float) -> void:
	var cam: Camera3D = _cams[n]
	var pos := f * local_pos
	cam.global_transform = Transform3D(Basis.looking_at((f * local_look) - pos, f.basis.y), pos)
	cam.fov = fov


func _smooth_dir(key: String, want: Vector3, sharp: float, dt: float, snap_now: bool) -> Vector3:
	var cur: Vector3 = _state.get(key, want)
	if snap_now or cur.dot(want) < -0.99:
		cur = want
	else:
		cur = cur.slerp(want, 1.0 - exp(-sharp * dt)).normalized()
	_state[key] = cur
	return cur


func _clear_ground(pos: Vector3, min_height: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 300.0, pos + Vector3.DOWN * 300.0,
			DrivingCar.LAYER_WORLD)
	var hit := _space.intersect_ray(q)
	if hit:
		pos.y = maxf(pos.y, (hit["position"] as Vector3).y + min_height)
	return pos


## Yaw rate of whatever we're following (the ghost is not a rigid body).
func _follow_angular_y() -> float:
	if _follow is RigidBody3D:
		return (_follow as RigidBody3D).angular_velocity.y
	var yaw := _target_yaw()
	var prev: float = _state.get("yaw_prev", yaw)
	_state["yaw_prev"] = yaw
	return wrapf(yaw - prev, -PI, PI) * float(Engine.physics_ticks_per_second)


func _ghost_velocity(p: Vector3, dt: float) -> Vector3:
	var last: Vector3 = _state.get("ghost_last", p)
	_state["ghost_last"] = p
	return (p - last) / dt if dt > 0.0 else Vector3.ZERO


func _hardpoint(i: int) -> Vector3:
	if _follow is DrivingCar:
		return (_follow as DrivingCar).hardpoints[i]
	if _follow.has_method("hardpoint"):
		return _follow.call("hardpoint", i)
	return _car.hardpoints[i]


func _wheel_radius() -> float:
	var v: Variant = _follow.get("wheel_radius")
	return float(v) if v != null else _car.wheel_radius


func _body_size() -> Vector3:
	var v: Variant = _follow.get("body_size")
	return v if v is Vector3 else _car.body_size
