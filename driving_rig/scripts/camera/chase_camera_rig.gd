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
## Then the WILD bank, ported back from Full Throttle Flux. Everything above is broadcast
## coverage: safe framing, subject always held. These deliberately break that - near-misses,
## overshoot, lens moves that draw attention to themselves, and a camera that loses the car.
##
##   15 handheld    operator at the roadside, wide lens, never steady, always a beat behind
##   16 overtake    comes up from behind, draws level, pulls ahead, drops back
##   17 kamikaze    flown head-on against the direction of travel; contact lands mid-take
##   18 vertigo     dolly and zoom opposed: the car holds its size, the background stretches
##   19 roadkill    on the surface, in the car's path, not beside it
##   20 helilost    drifts ahead, gets left behind, hauls back on
##   21 whip        dead still on a wide lens, then snaps through the pass
##   22 crashzoom   punch in, HOLD, punch out, hold wide
##   23 skim        ahead of the car looking back, a hand's width off the ground
##   24 crossing    cable cam at its own constant speed; sometimes it meets the car
##   25 fisheye     hard mount on the nose looking BACK down the body, widest lens in the rig
##   26 fisheye_rear  the same behind the tail looking forward, half a cycle out of step
##
## The two banks cycle separately (B / D-pad right switches bank) - 26 cameras is too many for
## one cycle.
##
## C / gamepad Y cycles; number keys 1-9 jump. Everything follows `_follow` - the live car, or
## the replay ghost (where "driver" is replaced by the take's recorded camera).
## Runs in _physics_process at tick rate: deterministic, and physics-interpolated like the car.

signal camera_changed(camera_name: String)
signal bank_changed(bank: String)

## Which half of the rig C cycles through; see set_bank().
var bank: int = 0

@export var car_path: NodePath
@export var pivot_height: float = 1.3
@export var arm_length: float = 6.5
@export var pitch_deg: float = -11.0
@export var position_sharpness: float = 14.0   ## 1/s - higher = tighter follow
@export var yaw_sharpness: float = 3.5
@export var chase_fov: float = 60.0

@export_group("Scaling")
## Vehicle length the framing was authored for (the sedan).
@export var reference_length: float = 4.4
## And the top speed the plant distances were authored for. A camera planted 40 m ahead of a
## 95 km/h bus is a long wait; ahead of a 280 km/h sports car it is passed before it has
## finished panning, so plants scale with the car's top speed as well as its size.
@export var reference_speed_kmh: float = 180.0

@export_group("Wild cameras")
## Handheld shake amplitude, in metres at the reference vehicle length.
@export var handheld_shake: float = 0.09
## Seconds for one overtake pass: behind, alongside, ahead, and back.
@export var overtake_period: float = 7.0
## Length of one kamikaze take, seconds. Contact lands in the middle.
@export var kamikaze_take_seconds: float = 4.6
## Camera speed as a fraction of the car's, flying the other way.
@export var kamikaze_speed_fraction: float = 0.55
## Seconds for one full vertigo push-in and pull-out, per approach angle.
@export var vertigo_period: float = 8.0
## Seconds between crash zoom punches.
@export var crashzoom_period: float = 5.0
## Seconds between the heli losing the car and reacquiring it.
@export var helilost_period: float = 9.0
## Fraction of the crossing covered per second: 0.14 is about seven seconds. 0.33 read as a
## flyby rather than a crossing.
@export var crossing_rate: float = 0.14
## Height above the ground for the cable cam, and the clearance it keeps.
@export var crossing_height: float = 9.0
@export var crossing_clearance: float = 6.0
## How far the fisheye mounts stand off the body. Higher gives the car more room in frame.
@export var fisheye_standoff: float = 1.2

@export_group("Orbit")
## The orbit ramps between these rates rather than turning at a constant speed, so it eases
## into a sweep and back out again.
@export var orbit_speed_min: float = 0.12
@export var orbit_speed_max: float = 0.85
## How quickly it moves between the two, in cycles per second.
@export var orbit_ramp_rate: float = 0.22

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


## Everything is framed for a 4.4 m sedan; a 12 m bus needs the cameras further out. One
## factor, from the vehicle's own size, scales every distance and height.
func _size_scale() -> float:
	var b := _body_size()
	return clampf(maxf(b.z, b.y * 2.2) / reference_length, 0.85, 3.0)


## A second scale from the car's top speed, so plants stay far enough ahead of a fast car and
## close enough in front of a slow one.
func _speed_scale() -> float:
	var top: float = 0.0
	if _follow is DrivingCar:
		top = (_follow as DrivingCar).top_speed_kmh
	elif _follow != null and _follow.has_meta(&"drv_top_speed_kmh"):
		top = float(_follow.get_meta(&"drv_top_speed_kmh"))
	if top <= 1.0:
		return 1.0
	return clampf(top / maxf(reference_speed_kmh, 1.0), 0.55, 1.8)


## Where the car will be `ahead` metres from now, assuming it holds its current speed and rate
## of turn: a circular arc rather than a straight line, so a plant plonked 60 m "ahead" during a
## corner lands on the corner rather than out in the scenery.
##
## This is the stand-in for FTF's track spline, which the cameras there use to follow the
## racing surface. It is honest for a second or two and drifts after that - a take knows its
## own future exactly, and a later pass over a recorded take could use that instead.
func _route_point(p: Vector3, fwd: Vector3, speed: float, ahead: float) -> Vector3:
	var yaw_rate := _follow_angular_y()
	if absf(yaw_rate) < 0.02 or speed < 1.0:
		return p + fwd * ahead
	var t := ahead / maxf(speed, 1.0)
	var turned := clampf(yaw_rate * t, -PI * 0.8, PI * 0.8)
	var radius := speed / yaw_rate
	var side := fwd.cross(Vector3.UP).normalized()
	# arc of `turned` radians about the centre `radius` to the side
	return p + fwd * (radius * sin(turned)) + side * (radius * (1.0 - cos(turned))) * -1.0


## Underdamped spring toward a moving point: overshoots, then settles. Used where a camera
## should feel operated rather than driven by maths.
func _spring(key: String, target: Vector3, freq: float, damping: float, dt: float,
		snap_now: bool) -> Vector3:
	var pos: Vector3 = _state.get(key + "_p", target)
	var vel: Vector3 = _state.get(key + "_v", Vector3.ZERO)
	if snap_now:
		pos = target
		vel = Vector3.ZERO
	else:
		var w := TAU * freq
		vel += ((target - pos) * (w * w) - vel * (2.0 * damping * w)) * dt
		pos += vel * dt
	_state[key + "_p"] = pos
	_state[key + "_v"] = vel
	return pos


## Slide between a ring of offsets, holding each for `hold` seconds and easing across the last
## quarter, so a mount sweeps through its positions instead of cutting between them.
func _blend_offsets(clock: float, hold: float, offsets: Array) -> Vector3:
	var n := offsets.size()
	var idx := int(clock / hold) % n
	var ph := fposmod(clock / hold, 1.0)
	var a: Vector3 = offsets[idx]
	if ph < 0.75:
		return a
	var b: Vector3 = offsets[posmod(idx + 1, n)]
	var t := (ph - 0.75) / 0.25
	return a.lerp(b, t * t * (3.0 - 2.0 * t))


## Cycles an approach direction per take: back, front, side, three-quarter, overhead.
## `frontal` drops the rear angles, for moves that need something to push into.
func _angle_for(take: int, fwd: Vector3, side_dir: Vector3, frontal: bool = false) -> Vector3:
	var choices: Array[Vector3] = [fwd, (fwd + side_dir * 0.8).normalized(),
		side_dir, (fwd * 0.5 + Vector3.UP * 0.9).normalized(),
		(fwd - side_dir * 0.8).normalized()]
	if not frontal:
		choices.append(-fwd)
		choices.append((-fwd + side_dir * 0.7).normalized())
	return choices[posmod(take, choices.size())]


func _ready() -> void:
	process_physics_priority = 50   # after the car (0) and player (40), before the recorder (100)
	top_level = true
	_car = get_node(car_path) as DrivingCar
	_follow = _car
	_driver_cam = _car.get_node("DriverCam") as Camera3D
	_arm.spring_length = arm_length   # rescaled per vehicle in _physics_process
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
	elif event.is_action_pressed(&"camera_bank"):
		set_bank(bank + 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			select_in_bank(k - KEY_1)


## The cameras C cycles through right now (replay swaps the driver cam for the recorded one).
## The cameras C steps through: the current bank only. 26 live plus a take's 26 is far too many
## for one cycle, so they come in three: broadcast, wild, and (while watching) the take's own.
func cycle_list() -> Array[Camera3D]:
	if bank == 2 and not replay_cams.is_empty():
		return replay_cams.duplicate()
	var out: Array[Camera3D] = []
	var from := TakeFormat.WILD_FROM if bank == 1 else 0
	var to := cameras.size() if bank == 1 else TakeFormat.WILD_FROM
	for i in range(from, to):
		if TakeFormat.CAMERA_NAMES[i] == "driver" and _follow != _car:
			if replay_cam:
				out.append(replay_cam)
			continue
		out.append(cameras[i])
	return out


## 0 = broadcast coverage, 1 = the wild bank, 2 = the take's recorded cameras (only while one
## is on screen). Switching moves to that bank's first camera.
func set_bank(b: int) -> void:
	bank = posmod(b, 3 if not replay_cams.is_empty() else 2)
	var list := cycle_list()
	if not list.is_empty() and not list.has(active_camera):
		_set_active(list[0])
	bank_changed.emit(bank_name())


func bank_name() -> String:
	return ["broadcast", "wild", "take"][bank]


func cycle(step: int) -> void:
	var list := cycle_list()
	if list.is_empty():
		return
	var i := list.find(active_camera)
	if i < 0:
		_set_active(list[0])        # came from the other bank
		return
	_set_active(list[(i + step + list.size()) % list.size()])


## Number keys jump within the current bank, so 1-9 reaches the wild cameras too.
func select_in_bank(i: int) -> void:
	var list := cycle_list()
	if i >= 0 and i < list.size():
		_set_active(list[i])


func select_index(i: int) -> void:
	if i < 0 or i >= cameras.size():
		return
	bank = 1 if i >= TakeFormat.WILD_FROM else 0
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
	var k := _size_scale()
	var sp := _speed_scale()
	_arm.spring_length = arm_length * k
	_arm.rotation_degrees.x = pitch_deg
	var f := _follow.global_transform
	var p := f.origin
	var fwd := -f.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var vel := (_follow as RigidBody3D).linear_velocity if _follow is RigidBody3D else _ghost_velocity(p, dt)

	# heli: high and behind, slow heading, looking down with lead
	var hf := _smooth_dir("heli_dir", fwd, 1.0, dt, snap_now)
	var heli_pos := _clear_ground(p + Vector3.UP * (28.0 * k) - hf * (18.0 * k), 10.0)
	_place("heli", heli_pos, p + fwd * 5.0, 2.5, 6.0, 35.0, dt, snap_now)

	# front: tracking vehicle ahead, looking back
	var ff := _smooth_dir("front_dir", fwd, 3.0, dt, snap_now)
	_place("front", _clear_ground(p + ff * (9.0 * k) + Vector3.UP * (1.3 * k), 0.6),
			p + Vector3.UP * (0.4 * k), 6.0, 10.0, 50.0, dt, snap_now)

	# side: Russian arm alongside (driver's side), slight lead
	var sf := _smooth_dir("side_dir", fwd, 3.0, dt, snap_now)
	var right := sf.cross(Vector3.UP).normalized()
	_place("side", _clear_ground(p - right * (6.5 * k) + Vector3.UP * (1.1 * k) + sf * 1.0, 0.5),
			p + Vector3.UP * (0.4 * k), 5.0, 10.0, 42.0, dt, snap_now)

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
	# Hold and range scale with the car's speed: what matters is how long a shot runs, and a
	# fast car covers the same ground in a fraction of the time.
	var replant := snap_now or plant == Vector3.INF or rel.length() > 80.0 * sp or rel.dot(fwd) > 25.0 * sp
	if replant:
		var side_sign: float = -float(ts.get("side", 1.0))
		var ahead := clampf(maxf(vel.length(), 8.0) * 3.0, 30.0, 70.0 * sp)
		plant = _clear_ground(_route_point(p, fwd, vel.length(), ahead)
				+ fwd.cross(Vector3.UP).normalized() * (9.0 * k) * side_sign
				+ Vector3.UP * (1.6 * k), 1.6)
		_state["trackside"] = {"plant": plant, "side": side_sign}
	var dist := plant.distance_to(p)
	_look("trackside", plant, p + Vector3.UP * (0.4 * k), 8.0, snap_now or replant,
			clampf(rad_to_deg(2.0 * atan(4.5 * k / maxf(dist, 1.0))), 6.0, 55.0), dt)

	# crane: plant ahead and low, rise and swing back over the car as it goes past
	var cr: Dictionary = _state.get("crane", {})
	var cplant: Vector3 = cr.get("plant", Vector3.INF)
	var crel := p - cplant
	var crane_replant := snap_now or cplant == Vector3.INF or crel.length() > 90.0 * sp \
			or crel.dot(fwd) > 18.0 * sp
	if crane_replant:
		cplant = _clear_ground(_route_point(p, fwd, vel.length(),
				clampf(maxf(vel.length(), 8.0) * 2.6, 26.0, 60.0 * sp))
				+ fwd.cross(Vector3.UP).normalized() * 5.0, 0.8)
		cr = {"plant": cplant, "t": 0.0}
		_state["crane"] = cr
	var ct: float = minf(float(cr.get("t", 0.0)) + dt * 0.3, 1.0)
	cr["t"] = ct
	var rise := ct * ct * (3.0 - 2.0 * ct)        # ease up and back
	var crane_pos := cplant + Vector3.UP * (1.2 + 13.0 * rise * k) - fwd * (18.0 * rise * k)
	_place("crane", _clear_ground(crane_pos, 1.0), p + Vector3.UP * 0.4, 6.0, 5.0,
			lerpf(50.0, 42.0, rise), dt, crane_replant)   # snap on replant: easing loses the car

	# drone: swings to the outside of the turn and breathes in height - handheld FPV feel
	var turn := clampf(-_follow_angular_y() * 1.4, -1.0, 1.0)
	var side_dir := fwd.cross(Vector3.UP).normalized()
	var bob: float = float(_state.get("orbit_ang", 0.0)) * 0.6
	var drone_target := p - fwd * (7.5 * k) + side_dir * (5.0 * turn * k) + Vector3.UP * (3.4 * k + 0.8 * sin(bob))
	_place("drone", _clear_ground(drone_target, 1.2), p + fwd * 3.0, 3.0, 4.0, 55.0, dt, snap_now)

	# lowchase: knee-high, close, long lens
	var lf := _smooth_dir("low_dir", fwd, 2.0, dt, snap_now)
	_place("lowchase", _clear_ground(p - lf * (7.0 * k) + Vector3.UP * 0.45, 0.35),
			p + Vector3.UP * (0.5 * k), 8.0, 7.0, 34.0, dt, snap_now)

	# pan: a locked-off tripod. It never moves - it only pans and tilts - until the car gets
	# far enough away that there is nothing to see, then it replants.
	var pn: Dictionary = _state.get("pan", {})
	var pplant: Vector3 = pn.get("plant", Vector3.INF)
	# A locked tripod should hold: its whole shot is the car receding, and replanting early
	# throws away the one thing it does.
	if snap_now or pplant == Vector3.INF or pplant.distance_to(p) > 150.0 * sp:
		pplant = _clear_ground(p - fwd * (14.0 * k) + fwd.cross(Vector3.UP).normalized() * (16.0 * k)
				+ Vector3.UP * (3.0 * k), 3.0)
		_state["pan"] = {"plant": pplant}
	_look("pan", pplant, p + Vector3.UP * (0.4 * k), 5.0, snap_now,
			clampf(rad_to_deg(2.0 * atan(5.0 * k / maxf(pplant.distance_to(p), 1.0))), 8.0, 60.0), dt)

	# rearwheel: rigid at the back wheel, looking forward along the flank
	var rhp := _hardpoint(3)
	_rigid("rearwheel", f, Vector3(rhp.x + 0.42, rhp.y + 0.05, rhp.z + 0.5),
			Vector3(rhp.x + 0.1, rhp.y - 0.15, rhp.z - 2.0), 68.0)

	# orbit: slow circle in world space
	# ramps between a slow drift and a quick sweep rather than turning at one rate
	var ophase: float = float(_state.get("orbit_phase", 0.0)) + orbit_ramp_rate * dt
	_state["orbit_phase"] = ophase
	var orate := lerpf(orbit_speed_min, orbit_speed_max, 0.5 - 0.5 * cos(ophase * TAU))
	var ang: float = float(_state.get("orbit_ang", 0.0)) + orate * dt
	_state["orbit_ang"] = ang
	var orbit_pos := _clear_ground(p + Vector3(cos(ang), 0.0, sin(ang)) * (9.0 * k) + Vector3.UP * (2.5 * k), 0.8)
	_place("orbit", orbit_pos, p + Vector3.UP * (0.4 * k), 8.0, 12.0, 50.0, dt, snap_now)

	_update_wild(dt, snap_now, k, sp, p, fwd, side_dir, vel, f)


# === the wild bank ===

## Everything above is broadcast coverage: safe framing, the car always held. These deliberately
## break that. Ported from Full Throttle Flux, which got them from this rig in the first place.
##
## Where FTF leans on its track spline to keep a camera on the racing surface, these use
## `_route_point` - where the car will be if it holds its current speed and rate of turn.
func _update_wild(dt: float, snap_now: bool, k: float, sp: float, p: Vector3, fwd: Vector3,
		side_dir: Vector3, vel: Vector3, f: Transform3D) -> void:
	var speed := maxf(vel.length(), 4.0)
	var clock: float = float(_state.get("clock", 0.0)) + dt
	_state["clock"] = clock
	var up_pt := p + Vector3.UP * (0.5 * k)
	var body := _body_size()

	# handheld: operator at the roadside, wide lens, never steady, always a beat behind
	var hh: Dictionary = _state.get("handheld", {})
	var hplant: Vector3 = hh.get("plant", Vector3.INF)
	var hrel := p - hplant
	if snap_now or hplant == Vector3.INF or hrel.dot(fwd) > 45.0 * sp or hrel.length() > 110.0 * sp:
		var hside: float = -float(hh.get("side", 1.0))
		hplant = _route_point(p, fwd, speed, clampf(speed * 1.6, 25.0, 80.0 * sp)) \
				+ fwd.cross(Vector3.UP).normalized() * (5.0 * k) * hside
		hplant = _clear_ground(hplant + Vector3.UP * (1.7 * k), 1.5)
		_state["handheld"] = {"plant": hplant, "side": hside}
	var shake := Vector3(sin(clock * 3.1) + 0.4 * sin(clock * 7.9),
			sin(clock * 2.3 + 1.1) + 0.3 * sin(clock * 6.1),
			sin(clock * 1.7 + 2.2)) * (handheld_shake * k)
	_look("handheld", hplant + shake, _spring("hh_aim", up_pt, 1.6, 0.45, dt, snap_now),
			9.0, snap_now, 70.0, dt)

	# overtake: comes up from behind, draws level, pulls ahead, drops back
	var oph := fposmod(clock / maxf(overtake_period, 0.5), 1.0)
	var tri := 1.0 - absf(oph * 2.0 - 1.0)
	var ease_t := tri * tri * (3.0 - 2.0 * tri)
	_place("overtake", _clear_ground(p + fwd * lerpf(-11.0 * k, 15.0 * k, ease_t)
			+ side_dir * (3.6 * k) + Vector3.UP * (1.1 * k), 0.8),
			up_pt, 7.0, 8.0, lerpf(38.0, 62.0, tri), dt, snap_now)

	# kamikaze: planted far enough ahead that contact lands mid-take, then flown back into the
	# oncoming car and straight past it, so the car recedes behind rather than the shot cutting
	_kamikaze(dt, snap_now, k, sp, p, fwd, speed, up_pt)

	# vertigo: dolly and zoom opposed, so the car holds its size while the background stretches
	var vtake := int(clock / maxf(vertigo_period, 1.0))
	var vph := fposmod(clock / maxf(vertigo_period, 1.0), 1.0)
	var vramp := 0.5 - 0.5 * cos(vph * TAU)
	var vdist := lerpf(5.0 * k, 22.0 * k, vramp)
	var vdir := _angle_for(vtake, fwd, side_dir)
	var vfov := clampf(rad_to_deg(2.0 * atan(2.6 * k / maxf(vdist, 1.0))), 11.0, 96.0)
	_place("vertigo", _clear_ground(p + vdir * vdist + Vector3.UP * (1.3 * k), 0.8),
			up_pt, 9.0, 9.0, vfov, dt, snap_now)

	# roadkill: on the surface, in the car's path rather than beside it
	var rk: Dictionary = _state.get("roadkill", {})
	var rplant: Vector3 = rk.get("plant", Vector3.INF)
	var rrel := p - rplant
	if snap_now or rplant == Vector3.INF or rrel.dot(fwd) > 30.0 * sp or rrel.length() > 90.0 * sp:
		var rside: float = -float(rk.get("side", 1.0))
		rplant = _route_point(p, fwd, speed, clampf(speed * 1.5, 25.0, 75.0 * sp)) \
				+ fwd.cross(Vector3.UP).normalized() * (1.1 * k) * rside
		rplant = _clear_ground(rplant + Vector3.UP * (0.22 * k), 0.18)
		_state["roadkill"] = {"plant": rplant, "side": rside}
	var rnear := clampf(1.0 - rplant.distance_to(p) / (22.0 * k), 0.0, 1.0)
	_look("roadkill", rplant, p + Vector3.UP * (0.3 * k), lerpf(2.5, 16.0, rnear * rnear),
			snap_now, 96.0, dt)

	# helilost: drifts ahead, gets left behind, hauls back on
	var lph := fposmod(clock / maxf(helilost_period, 1.0), 1.0)
	var lcurve := 0.5 - 0.5 * cos(lph * TAU)
	_place("helilost", _clear_ground(p + fwd * lerpf(14.0 * k, -16.0 * k, lcurve)
			+ side_dir * (5.0 * k) + Vector3.UP * (13.0 * k), 6.0),
			p, lerpf(0.22, 1.9, lcurve * lcurve), lerpf(0.5, 1.4, lcurve), 42.0, dt, snap_now)

	# whip: dead still on a wide lens, then snaps through the pass
	var wh: Dictionary = _state.get("whip", {})
	var wplant: Vector3 = wh.get("plant", Vector3.INF)
	var wrel := p - wplant
	if snap_now or wplant == Vector3.INF or wrel.dot(fwd) > 50.0 * sp or wrel.length() > 120.0 * sp:
		var wside: float = -float(wh.get("side", 1.0))
		wplant = _route_point(p, fwd, speed, clampf(speed * 1.8, 30.0, 90.0 * sp)) \
				+ fwd.cross(Vector3.UP).normalized() * (2.6 * k) * wside
		wplant = _clear_ground(wplant + Vector3.UP * (1.1 * k), 1.0)
		_state["whip"] = {"plant": wplant, "side": wside}
	var wnear := clampf(1.0 - wplant.distance_to(p) / (26.0 * k), 0.0, 1.0)
	_look("whip", wplant, up_pt, lerpf(1.4, 26.0, pow(wnear, 3.0)), snap_now, 74.0, dt)

	# crashzoom: punch in, HOLD, punch out, hold wide. The holds are the point - without them
	# it reads as a continuous pulse.
	var czph := fposmod(clock / maxf(crashzoom_period, 1.0), 1.0)
	var czfov: float
	if czph < 0.07:
		czfov = lerpf(72.0, 24.0, ease(czph / 0.07, 0.35))
	elif czph < 0.45:
		czfov = 24.0
	elif czph < 0.56:
		czfov = lerpf(24.0, 72.0, ease((czph - 0.45) / 0.11, 0.35))
	else:
		czfov = 72.0
	var czdir := _angle_for(int(clock / maxf(crashzoom_period, 1.0)), fwd, side_dir, true)
	_place("crashzoom", _clear_ground(p + czdir * (7.0 * k) + Vector3.UP * (1.4 * k), 1.0),
			up_pt, 6.0, 7.0, czfov, dt, snap_now)

	# skim: ahead of the car looking back, a hand's width off the ground, sliding between four
	# positions rather than cutting
	var soff := _blend_offsets(clock, 4.5, [
			fwd * (5.0 * k) + Vector3.UP * (0.35 * k),
			fwd * (6.5 * k) + side_dir * (2.2 * k) + Vector3.UP * (0.9 * k),
			fwd * (6.5 * k) - side_dir * (2.2 * k) + Vector3.UP * (0.9 * k),
			fwd * (4.5 * k) + Vector3.UP * (2.2 * k)])
	_place("skim", _clear_ground(p + soff, 0.28), up_pt, 10.0, 11.0, 90.0, dt, snap_now)

	# crossing: cable cam at its own constant speed. Sometimes it meets the car, sometimes not.
	var cs: Dictionary = _state.get("crossing", {})
	var ccentre: Vector3 = cs.get("centre", Vector3.INF)
	var caxis: Vector3 = cs.get("axis", side_dir)
	var ct2: float = float(cs.get("t", 0.0)) + dt * crossing_rate
	if snap_now or ccentre == Vector3.INF or ct2 >= 1.0 or (p - ccentre).dot(fwd) > 30.0 * sp:
		ccentre = _route_point(p, fwd, speed, clampf(speed * 2.2, 40.0, 130.0 * sp))
		caxis = side_dir
		ct2 = 0.0
	_state["crossing"] = {"centre": ccentre, "axis": caxis, "t": ct2}
	_look("crossing", _clear_ground(ccentre + caxis * lerpf(26.0 * k, -26.0 * k, ct2)
			+ Vector3.UP * (crossing_height * k), crossing_clearance),
			up_pt, 6.0, snap_now, 46.0, dt)

	# fisheye: hard-mounted on the nose looking BACK down the body, widest lens in the rig.
	# Slides between four mounts, so the body swings through frame instead of cutting.
	var g := fisheye_standoff
	var mount := _blend_offsets(clock, 6.5, [
			Vector3(0.0, -body.y * 0.30, -body.z * 0.50 - 0.9 * g),
			Vector3(-body.x * 1.10 * g, -body.y * 0.05, -body.z * 0.42 - 0.6 * g),
			Vector3(body.x * 1.10 * g, -body.y * 0.05, -body.z * 0.42 - 0.6 * g),
			Vector3(0.0, body.y * 1.20 * g, -body.z * 0.40 - 0.6 * g)])
	var aim := _blend_offsets(clock, 6.5, [
			Vector3(0.0, body.y * 0.90, body.z * 0.60),
			Vector3(body.x * 0.20, body.y * 0.30, body.z * 0.60),
			Vector3(-body.x * 0.20, body.y * 0.30, body.z * 0.60),
			Vector3(0.0, -body.y * 0.25, body.z * 0.60)])
	_rigid("fisheye", f, mount, aim, 118.0)

	# fisheye_rear: the same behind the tail looking forward, half a cycle out of step so the
	# two are never on the same mount at once
	var rmount := _blend_offsets(clock + 1.75, 6.5, [
			Vector3(0.0, -body.y * 0.30, body.z * 0.50 + 0.9 * g),
			Vector3(body.x * 1.10 * g, -body.y * 0.05, body.z * 0.42 + 0.6 * g),
			Vector3(-body.x * 1.10 * g, -body.y * 0.05, body.z * 0.42 + 0.6 * g),
			Vector3(0.0, body.y * 1.20 * g, body.z * 0.40 + 0.6 * g)])
	var raim := _blend_offsets(clock + 1.75, 6.5, [
			Vector3(0.0, body.y * 0.90, -body.z * 0.60),
			Vector3(-body.x * 0.20, body.y * 0.30, -body.z * 0.60),
			Vector3(body.x * 0.20, body.y * 0.30, -body.z * 0.60),
			Vector3(0.0, -body.y * 0.25, -body.z * 0.60)])
	_rigid("fisheye_rear", f, rmount, raim, 118.0)


## Fly the kamikaze camera back down the car's own route into the oncoming car. Planted at the
## distance the two close in half a take, so contact lands in the middle of it.
func _kamikaze(dt: float, snap_now: bool, k: float, sp: float, p: Vector3, fwd: Vector3,
		speed: float, up_pt: Vector3) -> void:
	var st: Dictionary = _state.get("kamikaze", {})
	var t: float = float(st.get("t", 999.0)) + dt
	if snap_now or st.is_empty() or t > kamikaze_take_seconds:
		var closing := speed * (1.0 + kamikaze_speed_fraction)
		var ahead := clampf(closing * kamikaze_take_seconds * 0.5, 40.0, 220.0 * sp)
		var side := -float(st.get("side", 1.0))
		var start := _route_point(p, fwd, speed, ahead) \
				+ fwd.cross(Vector3.UP).normalized() * (1.6 * k * side)
		st = {"t": 0.0, "pos": _clear_ground(start + Vector3.UP * (1.5 * k), 1.0),
			"dir": fwd, "side": side}
	else:
		st["t"] = t
	# fly back along the car's heading at its own speed; it keeps going after the pass
	var dir: Vector3 = st["dir"]
	var pos: Vector3 = (st["pos"] as Vector3) - dir * (speed * kamikaze_speed_fraction * dt)
	st["pos"] = pos
	_state["kamikaze"] = st
	_look("kamikaze", _clear_ground(pos, 0.9), up_pt, 7.0, snap_now, 62.0, dt)


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
