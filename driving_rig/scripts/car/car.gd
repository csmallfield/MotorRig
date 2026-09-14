class_name DrivingCar
extends RigidBody3D
## Proxy car for the driving rig.
##
## Physicality lives in the suspension (ShapeCast spring-dampers + anti-roll bars).
## Forgiveness lives in the tires (gently falling grip curve, understeer bias, ABS,
## low-speed hold). Body, collider, casts and wheel chains are all generated from the
## exported dimensions, so the take `meta` block can never drift from the physical car.
##
## Conventions (also written into every take):
##   wheel order        FL, FR, RL, RR
##   steer              rad about chassis +Y, positive = left
##   spin_cumulative    rad, positive = forward roll, never wrapped (visual: rotate -X)
##   compression        m, 0 = full droop, grows upward toward the hardpoint
##   slip_long          (ω·r − v_long) / max(|v_long|, 1 m/s)
##   slip_lat           slip angle in rad (atan2(v_lat, max(|v_long|, ref)))

signal teleported

enum Drive { RWD, FWD, AWD }

const WHEEL_COUNT: int = 4
const WHEEL_NAMES: PackedStringArray = ["FL", "FR", "RL", "RR"]
const GRAVITY: float = 9.81
const LAYER_WORLD: int = 1
const LAYER_CAR: int = 2
const VIS_LAYER_BODY: int = 1 << 1   ## render layer 2: body shell, culled by the driver cam
const MAX_COMP_VEL: float = 8.0        # m/s — clamps damper spikes from cast pops
const LOAD_CAP_FACTOR: float = 3.5     # × static wheel load, caps tire grip spikes

## --- Tuning: set from a CarProfile at spawn (see scripts/profiles/car_profile.gd). ---
## Plain vars, not Inspector exports: the profile .tres is the one place to tune.
## Full size, not half-extents. Deliberately narrower than the track so the wheels sit
## outboard and suspension/spin read from any angle (a 1.8 m box hides them completely).
var body_size: Vector3 = Vector3(1.3, 1.0, 4.4)
var com_offset: Vector3 = Vector3(0.0, -0.1, 0.0)
var wheelbase: float = 2.65
var track_front: float = 1.58
var track_rear: float = 1.56
var wheel_radius: float = 0.34
var wheel_width: float = 0.24
var hardpoint_height: float = -0.09   ## chassis-local Y of the suspension top mounts

var susp_rest: float = 0.32           ## hardpoint → wheel centre at full droop
var susp_max_travel: float = 0.18
var spring_rate_front: float = 40000.0
var spring_rate_rear: float = 40000.0
var damp_bump: float = 2600.0
var damp_rebound: float = 3400.0
var arb_front: float = 9000.0
var arb_rear: float = 5000.0
var bump_stop_rate: float = 250000.0
var visual_droop_rate: float = 30.0   ## 1/s — how fast an unloaded wheel drops

var tire_mu: float = 1.15
var front_grip: float = 1.0
var rear_grip: float = 1.08           ## > front: understeer bias, no snap oversteer
var peak_slip_angle_deg: float = 8.0
var falloff_width_deg: float = 25.0
var falloff_floor: float = 0.82   ## grip kept at full slide
var low_speed_slip_ref: float = 3.0   ## m/s — keeps slip angle sane at crawl
var rolling_resistance: float = 0.012
var tire_force_lift: float = 0.0      ## raise tire force point → less roll

var drive: Drive = Drive.AWD
var awd_rear_bias: float = 0.6
var engine_power_kw: float = 160.0
var max_drive_force: float = 9000.0
var top_speed_kmh: float = 220.0
var reverse_force: float = 4000.0
var reverse_top_speed_kmh: float = 35.0
var brake_force: float = 14000.0
var brake_bias_front: float = 0.65
var abs_enabled: bool = true
var handbrake_force: float = 6000.0
var handbrake_rear_grip: float = 0.55
var drag_coefficient: float = 0.42    ## F = c · v²

var max_steer_deg: float = 32.0
## Full stick maps to the angle the tires can actually use at the current speed:
## atan(wheelbase · μg / v²) + margin. Past that the front just runs beyond peak slip
## and the car wobbles in yaw. Raise the margin to allow provoked understeer; set it
## very high to effectively disable the limiter.
var steer_grip_margin_deg: float = 2.5
var steer_rate: float = 4.5           ## input units / s toward target
var steer_return_rate: float = 6.0
var ackermann: float = 1.0
var traction_control: bool = false
var driver_eye: Vector3 = Vector3(-0.3, 0.47, 0.2)
var chassis_scene: PackedScene
var chassis_transform: Transform3D = Transform3D.IDENTITY
var hide_chassis_in_driver_cam: bool = true
var steering_ratio: float = 15.0
var steering_wheel_radius: float = 0.19
var steering_wheel_offset: Vector3 = Vector3(0.0, -0.28, -0.5)
var steering_column_tilt_deg: float = 20.0
## Steering-wheel rotation, rad (+ = counter-clockwise as the driver sees it = turning left).
var steering_wheel_angle: float = 0.0
var _steering_wheel: Node3D
var body_color: Color = Color(0.86, 0.42, 0.10)

## Drive mode (see scripts/profiles/drive_mode.gd)
var throttle_gamma: float = 1.0
var brake_gamma: float = 1.0
var steer_gamma: float = 1.0
var low_speed_hold: bool = true
var kerb_trip: float = 0.0
## Pedal values after the mode's response curve - what the physics uses. The raw device
## values stay in input_* and are what gets recorded.
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0

## World physics (from the active WorldProfile)
var surface_grip: float = 1.0
var air_density_scale: float = 1.0
var _gravity: float = 9.81


## Explicit profile (tests, tools). Otherwise SimConfig's selection, else built-in defaults.
@export var profile: CarProfile
## Explicit drive mode; otherwise SimConfig's selection, else a neutral one (no change).
@export var drive_mode: DriveMode

@export_group("Visuals")
@export var body_material: Material
@export var wheel_material: Material
@export var accent_material: Material

# === INPUT (raw device values — these are what gets recorded) ===
var use_player_input: bool = true   ## false → something else (re-sim, tests) writes input_*
var input_throttle: float = 0.0
var input_brake: float = 0.0
var input_steer: float = 0.0        ## −1 full left … +1 full right
var input_handbrake: bool = false

# === PUBLIC STATE (read by recorder / HUD every tick — never reassigned, only indexed) ===
var wheel_compression := PackedFloat64Array()
var wheel_steer := PackedFloat64Array()
var wheel_spin := PackedFloat64Array()
var wheel_omega := PackedFloat64Array()
var wheel_grounded := PackedByteArray()
var wheel_contact_p := PackedVector3Array()
var wheel_contact_n := PackedVector3Array()
var wheel_slip_long := PackedFloat64Array()
var wheel_slip_lat := PackedFloat64Array()
var wheel_load := PackedFloat64Array()
var hardpoints := PackedVector3Array()
var forward_speed: float = 0.0
var is_reversing: bool = false
var reset_locked: bool = false      ## recorder sets this while a take is running

# === PRIVATE ===
var _casts: Array[ShapeCast3D] = []
var _steer_nodes: Array[Node3D] = []
var _susp_nodes: Array[Node3D] = []
var _spin_nodes: Array[Node3D] = []
var _raw_comp := PackedFloat64Array()
var _prev_comp := PackedFloat64Array()
var _susp_force := PackedFloat64Array()
var _steer_smoothed: float = 0.0
var _reverse_timer: float = 0.0
var _corner_mass: float = 300.0
var _static_load: float = 2943.0
var _pending_reset: bool = false
var _reset_xform: Transform3D
var _spawn_xform: Transform3D
var _just_reset: bool = false


var active_profile: CarProfile   ## what this car was actually built from
var active_mode: DriveMode


func _ready() -> void:
	_apply_profile(_resolve_profile())
	_apply_mode(_resolve_mode())
	_apply_world(WorldProfile.active)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	collision_layer = LAYER_CAR
	collision_mask = LAYER_WORLD
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	physics_material_override = pm
	_corner_mass = mass * 0.25
	_static_load = mass * _gravity * 0.25
	_alloc_state()
	_build_body()
	_build_wheels()
	_spawn_xform = global_transform


# === PROFILE ===

func _resolve_profile() -> CarProfile:
	if profile:
		return profile
	var cfg := get_node_or_null(^"/root/SimConfig")
	if cfg and cfg.get("car_profile"):
		return cfg.get("car_profile")
	return CarProfile.new()


## Copies every profile property onto the same-named car property (mass included).
func _apply_profile(p: CarProfile) -> void:
	active_profile = p
	for prop in p.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = prop["name"]
		if n in ["display_name", "description", "tuned_at_hz"]:
			continue
		if prop["type"] == TYPE_NIL:
			continue
		set(n, p.get(n))


func _resolve_mode() -> DriveMode:
	if drive_mode:
		return drive_mode
	var cfg := get_node_or_null(^"/root/SimConfig")
	if cfg and cfg.get("drive_mode"):
		return cfg.get("drive_mode")
	return DriveMode.new()


func _apply_mode(m: DriveMode) -> void:
	active_mode = m
	m.apply_to(self)


func _apply_world(w: WorldProfile) -> void:
	if w:
		surface_grip = w.surface_grip
		air_density_scale = w.air_density_scale
	var space := get_world_3d().space if is_inside_tree() else RID()
	_gravity = PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY) \
			if space.is_valid() else (w.gravity if w else GRAVITY)


## Trigger response: out = in^gamma (1.0 = linear).
static func _curve(x: float, gamma: float) -> float:
	return x if is_equal_approx(gamma, 1.0) else pow(clampf(x, 0.0, 1.0), gamma)


func _tinted(mat: Material, c: Color) -> Material:
	if not (mat is ShaderMaterial):
		return mat
	var m := (mat as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter(&"base_color", c)
	m.set_shader_parameter(&"line_color", c.lerp(Color.WHITE, 0.45))
	m.set_shader_parameter(&"major_color", c.lerp(Color.WHITE, 0.8))
	return m


# === BUILD ===

func _alloc_state() -> void:
	wheel_compression.resize(WHEEL_COUNT)
	wheel_steer.resize(WHEEL_COUNT)
	wheel_spin.resize(WHEEL_COUNT)
	wheel_omega.resize(WHEEL_COUNT)
	wheel_slip_long.resize(WHEEL_COUNT)
	wheel_slip_lat.resize(WHEEL_COUNT)
	wheel_load.resize(WHEEL_COUNT)
	wheel_grounded.resize(WHEEL_COUNT)
	wheel_contact_p.resize(WHEEL_COUNT)
	wheel_contact_n.resize(WHEEL_COUNT)
	hardpoints.resize(WHEEL_COUNT)
	_raw_comp.resize(WHEEL_COUNT)
	_prev_comp.resize(WHEEL_COUNT)
	_susp_force.resize(WHEEL_COUNT)
	wheel_compression.fill(0.0)
	wheel_steer.fill(0.0)
	wheel_spin.fill(0.0)
	wheel_omega.fill(0.0)
	wheel_slip_long.fill(0.0)
	wheel_slip_lat.fill(0.0)
	wheel_load.fill(0.0)
	wheel_grounded.fill(0)
	_raw_comp.fill(0.0)
	_prev_comp.fill(0.0)
	_susp_force.fill(0.0)


func _build_body() -> void:
	var shape := BoxShape3D.new()
	shape.size = body_size
	var col := CollisionShape3D.new()
	col.name = "BodyCollider"
	col.shape = shape
	add_child(col)

	if chassis_scene:
		_build_chassis_model()
	else:
		var box := BoxMesh.new()
		box.size = body_size
		var mi := MeshInstance3D.new()
		mi.name = "BodyGeo"
		mi.mesh = box
		mi.material_override = _tinted(body_material, body_color)
		mi.layers = VIS_LAYER_BODY
		add_child(mi)

		# Nose bar so heading reads at a glance (the proxy box is otherwise symmetric).
		var nose := BoxMesh.new()
		nose.size = Vector3(body_size.x * 0.8, 0.12, 0.12)
		var nose_mi := MeshInstance3D.new()
		nose_mi.name = "NoseGeo"
		nose_mi.mesh = nose
		nose_mi.material_override = accent_material
		nose_mi.position = Vector3(0.0, body_size.y * 0.5 - 0.06, -body_size.z * 0.5 + 0.02)
		add_child(nose_mi)

	var driver_cam := get_node_or_null(^"DriverCam") as Camera3D
	if driver_cam:
		driver_cam.cull_mask &= ~VIS_LAYER_BODY   # see out through the proxy shell
		driver_cam.position = driver_eye
	_steering_wheel = build_steering_wheel(self, driver_eye, steering_wheel_offset, steering_column_tilt_deg,
			steering_wheel_radius, wheel_material, accent_material)


func _build_chassis_model() -> void:
	var inst := chassis_scene.instantiate()
	var holder := Node3D.new()
	holder.name = "ChassisModel"
	holder.transform = chassis_transform
	add_child(holder)
	holder.add_child(inst)
	if hide_chassis_in_driver_cam:
		for v in holder.find_children("*", "VisualInstance3D", true, false):
			(v as VisualInstance3D).layers = VIS_LAYER_BODY
		if inst is VisualInstance3D:
			(inst as VisualInstance3D).layers = VIS_LAYER_BODY


## Torus rim + a spoke + a marker at 12 o'clock, on a tilted column. Returns the node that
## rotates (about its local +Z, which points at the driver). Shared with the replay ghost.
static func build_steering_wheel(parent: Node3D, eye: Vector3, offset: Vector3, tilt_deg: float,
		radius: float, rim_mat: Material, marker_mat: Material) -> Node3D:
	var column := Node3D.new()
	column.name = "SteeringColumn"
	column.position = eye + offset
	column.rotation = Vector3(-deg_to_rad(tilt_deg), 0.0, 0.0)
	parent.add_child(column)
	var wheel := Node3D.new()
	wheel.name = "SteeringWheel"
	column.add_child(wheel)
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.016
	torus.outer_radius = radius + 0.016
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = torus
	rim.material_override = rim_mat
	rim.rotation = Vector3(PI * 0.5, 0.0, 0.0)   # torus axis Y -> column axis Z
	wheel.add_child(rim)
	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(radius * 2.0, 0.025, 0.02)
	var spoke := MeshInstance3D.new()
	spoke.name = "Spoke"
	spoke.mesh = spoke_mesh
	spoke.material_override = rim_mat
	wheel.add_child(spoke)
	var mark_mesh := BoxMesh.new()
	mark_mesh.size = Vector3(0.035, 0.05, 0.04)
	var mark := MeshInstance3D.new()
	mark.name = "TopMarker"
	mark.mesh = mark_mesh
	mark.material_override = marker_mat
	mark.position = Vector3(0.0, radius, 0.0)
	wheel.add_child(mark)
	return wheel


func _build_wheels() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = wheel_radius
	cyl.bottom_radius = wheel_radius
	cyl.height = wheel_width
	cyl.radial_segments = 24
	cyl.rings = 1

	for i in WHEEL_COUNT:
		var front := i < 2
		var left := i % 2 == 0
		var track := track_front if front else track_rear
		var hp := Vector3((-0.5 if left else 0.5) * track, hardpoint_height,
				(-0.5 if front else 0.5) * wheelbase)
		hardpoints[i] = hp
		var wn := WHEEL_NAMES[i]

		var sphere := SphereShape3D.new()
		sphere.radius = wheel_radius
		var cast := ShapeCast3D.new()
		cast.name = "cast_%s" % wn
		cast.shape = sphere
		cast.position = hp
		cast.target_position = Vector3(0.0, -susp_rest, 0.0)
		cast.collision_mask = LAYER_WORLD
		cast.max_results = 4
		cast.enabled = false   # updated manually each tick, in a known order
		add_child(cast)
		cast.add_exception(self)
		_casts.append(cast)

		# steer → susp → spin → geo  (same chain the Maya importer builds)
		var steer := Node3D.new()
		steer.name = "wheel_%s_steer" % wn
		steer.position = hp
		add_child(steer)
		var susp := Node3D.new()
		susp.name = "wheel_%s_susp" % wn
		susp.position = Vector3(0.0, -susp_rest, 0.0)
		steer.add_child(susp)
		var spin := Node3D.new()
		spin.name = "wheel_%s_spin" % wn
		susp.add_child(spin)
		var geo := MeshInstance3D.new()
		geo.name = "wheel_%s_geo" % wn
		geo.mesh = cyl
		geo.material_override = wheel_material
		geo.rotation = Vector3(0.0, 0.0, PI * 0.5)   # cylinder axis Y → X
		spin.add_child(geo)

		_steer_nodes.append(steer)
		_susp_nodes.append(susp)
		_spin_nodes.append(spin)

		wheel_contact_p[i] = to_global(hp + Vector3(0.0, -susp_rest - wheel_radius, 0.0))
		wheel_contact_n[i] = Vector3.UP


# === PHYSICS ===

func _physics_process(delta: float) -> void:
	if _just_reset:
		_just_reset = false
		reset_physics_interpolation()
		for i in WHEEL_COUNT:
			_prev_comp[i] = _raw_comp[i]

	if use_player_input:
		_poll_player_input()
	throttle = _curve(input_throttle, throttle_gamma)
	brake = _curve(input_brake, brake_gamma)
	steer = signf(input_steer) * _curve(absf(input_steer), steer_gamma)

	var xf := global_transform
	var basis := xf.basis
	var up := basis.y
	var fwd_body := -basis.z
	var v_body := linear_velocity
	var w_body := angular_velocity
	var com_w := basis * com_offset
	forward_speed = v_body.dot(fwd_body)

	_update_steering(delta)

	# --- Suspension pass: casts, raw compression, spring/damper forces
	for i in WHEEL_COUNT:
		var cast := _casts[i]
		cast.force_shapecast_update()
		var grounded := cast.is_colliding()
		var comp := 0.0
		if grounded:
			comp = susp_rest - _refine_cast_distance(i, cast, -up)
		var comp_vel := clampf((comp - _prev_comp[i]) / delta, -MAX_COMP_VEL, MAX_COMP_VEL)
		_prev_comp[i] = comp
		_raw_comp[i] = comp
		wheel_grounded[i] = 1 if grounded else 0

		var f := 0.0
		if grounded:
			var k := spring_rate_front if i < 2 else spring_rate_rear
			f = k * comp + (damp_bump if comp_vel > 0.0 else damp_rebound) * comp_vel
			if comp > susp_max_travel:
				f += bump_stop_rate * (comp - susp_max_travel)
		_susp_force[i] = f

	# --- Anti-roll bars: couple left/right compression per axle
	_apply_arb(0, 1, arb_front)
	_apply_arb(2, 3, arb_rear)

	# --- Drive / brake demand
	var drive_total := _drive_force()
	var brake_in := brake
	var throttle_in := throttle
	if is_reversing:
		brake_in = throttle
		throttle_in = brake
	var holding := throttle_in < 0.02 and absf(forward_speed) < 0.6


	# --- Tire pass
	for i in WHEEL_COUNT:
		var front := i < 2
		var rear := not front
		if wheel_grounded[i] == 0:
			wheel_load[i] = 0.0
			wheel_slip_long[i] = 0.0
			wheel_slip_lat[i] = 0.0
			_spin_airborne(i, delta, throttle_in, brake_in)
			continue

		var load := clampf(_susp_force[i], 0.0, _static_load * LOAD_CAP_FACTOR)
		wheel_load[i] = load
		var cp := wheel_contact_p[i]
		var r_origin := cp - xf.origin
		apply_force(up * maxf(_susp_force[i], 0.0), r_origin)

		var n := wheel_contact_n[i]
		# Kerb strike: a wheel jammed against a sloped or vertical face is pushed along that
		# face, not only up its own axis. Zero on flat ground (the normal is vertical), large
		# against a kerb - which is what trips a sliding car into a roll.
		if kerb_trip > 0.0:
			var n_h := Vector3(n.x, 0.0, n.z)
			if n_h.length_squared() > 1e-6:
				apply_force(n_h * maxf(_susp_force[i], 0.0) * kerb_trip, r_origin)
		var steer_fwd := fwd_body.rotated(up, wheel_steer[i])
		var fwd := steer_fwd - n * steer_fwd.dot(n)
		if fwd.length_squared() < 1e-6:
			continue
		fwd = fwd.normalized()
		var right := fwd.cross(n)

		var v := v_body + w_body.cross(r_origin - com_w)
		var vl := v.dot(fwd)
		var vs := v.dot(right)
		var abs_vl := absf(vl)

		var hb := input_handbrake and rear
		var grip := tire_mu * surface_grip * (front_grip if front else rear_grip)
		if hb:
			grip *= handbrake_rear_grip
		var fmax := grip * load

		# Lateral: slip-angle grip curve, blended into a velocity-cancelling hold at crawl.
		var alpha := atan2(vs, maxf(abs_vl, low_speed_slip_ref))
		var f_lat := -signf(alpha) * _grip_curve(absf(alpha)) * fmax
		var crawl := (1.0 - clampf(v.length() / 2.0, 0.0, 1.0)) if low_speed_hold else 0.0
		if crawl > 0.0:
			f_lat = lerpf(f_lat, -vs * _corner_mass / delta * 0.35, crawl)

		# Longitudinal: drive + velocity-limited brake (never pushes the car backwards).
		var f_drive := drive_total * _drive_share(i)
		if traction_control and f_drive != 0.0:
			var spare := sqrt(maxf(fmax * fmax - f_lat * f_lat, 0.0)) * 0.95
			f_drive = signf(f_drive) * minf(absf(f_drive), spare)
		var f_brake_cap := brake_in * brake_force * (brake_bias_front if front else 1.0 - brake_bias_front) * 0.5
		if hb:
			f_brake_cap = maxf(f_brake_cap, handbrake_force * 0.5)
		var f_long := f_drive
		if f_brake_cap > 0.0:
			f_long -= clampf(vl * _corner_mass / delta * 0.5, -f_brake_cap, f_brake_cap)
		if holding and f_brake_cap <= 0.0 and low_speed_hold:
			f_long = -vl * _corner_mass / delta * 0.35
		elif abs_vl > 0.1:
			f_long -= signf(vl) * rolling_resistance * load

		# Friction circle.
		var f2 := Vector2(f_long, f_lat)
		var mag := f2.length()
		if mag > fmax and mag > 0.0:
			f2 *= fmax / mag
		var lat_used := absf(f2.y)
		var long_avail := sqrt(maxf(fmax * fmax - lat_used * lat_used, 0.0))

		apply_force(fwd * f2.x + right * f2.y, r_origin + up * tire_force_lift)

		# Wheel angular velocity (derived, not integrated — see README "tire model").
		var omega := vl / wheel_radius
		if hb and abs_vl > 0.3:
			omega = 0.0
		elif f_brake_cap > long_avail and abs_vl > 0.5:
			omega = (vl * 0.88 if abs_enabled else 0.0) / wheel_radius
		elif absf(f_drive) > long_avail and long_avail >= 0.0 and f_drive != 0.0:
			var ratio := absf(f_drive) / maxf(long_avail, 1.0)
			var excess := minf((ratio - 1.0) * 8.0, 20.0)
			omega = (vl + signf(f_drive) * excess) / wheel_radius
		wheel_omega[i] = omega
		wheel_slip_long[i] = (omega * wheel_radius - vl) / maxf(abs_vl, 1.0)
		wheel_slip_lat[i] = alpha

	# --- Aero drag
	apply_central_force(-v_body * v_body.length() * drag_coefficient * air_density_scale)

	# --- Integrate spin, update visuals
	for i in WHEEL_COUNT:
		wheel_spin[i] += wheel_omega[i] * delta
		if wheel_grounded[i] == 1:
			wheel_compression[i] = minf(_raw_comp[i], susp_max_travel * 1.1)
		else:
			wheel_compression[i] = lerpf(wheel_compression[i], 0.0, 1.0 - exp(-visual_droop_rate * delta))
			wheel_contact_p[i] = to_global(hardpoints[i] + Vector3(0.0,
					-(susp_rest - wheel_compression[i]) - wheel_radius, 0.0))
			wheel_contact_n[i] = up
		_steer_nodes[i].rotation.y = wheel_steer[i]
		_susp_nodes[i].position.y = -(susp_rest - wheel_compression[i])
		_spin_nodes[i].rotation.x = -fmod(wheel_spin[i], TAU)

	steering_wheel_angle = (wheel_steer[0] + wheel_steer[1]) * 0.5 * steering_ratio
	if _steering_wheel:
		_steering_wheel.rotation.z = steering_wheel_angle

	if global_position.y < -100.0 and not reset_locked:
		reset_to_spawn()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_reset:
		_pending_reset = false
		state.transform = _reset_xform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_just_reset = true
		teleported.emit.call_deferred()


## Cast fractions come back quantized (~1/512 of the cast length under Jolt), which turns
## into damper noise on terrain. Solve the sphere-centre distance exactly against each
## contact plane instead: dot(o + dir·d − c, n) = r. Takes the nearest (first-hit) solution,
## kept inside the cast's safe/unsafe bracket. Also writes the chosen contact p/n.
func _refine_cast_distance(i: int, cast: ShapeCast3D, dir: Vector3) -> float:
	var o := cast.global_position
	var lo := susp_rest * cast.get_closest_collision_safe_fraction()
	var hi := susp_rest * cast.get_closest_collision_unsafe_fraction()
	var best := INF
	var best_k := 0
	for k in cast.get_collision_count():
		var n := cast.get_collision_normal(k)
		var denom := -dir.dot(n)
		if denom < 0.2:   # near-vertical face: fall back to the bracket
			continue
		var d := ((o - cast.get_collision_point(k)).dot(n) - wheel_radius) / denom
		if d < best:
			best = d
			best_k = k
	wheel_contact_p[i] = cast.get_collision_point(best_k)
	wheel_contact_n[i] = cast.get_collision_normal(best_k)
	if best == INF:
		return lo
	return clampf(best, maxf(lo - 0.002, 0.0), minf(hi + 0.002, susp_rest))


func _apply_arb(a: int, b: int, rate: float) -> void:
	if wheel_grounded_raw(a) and wheel_grounded_raw(b):
		var f := (_raw_comp[a] - _raw_comp[b]) * rate
		_susp_force[a] += f
		_susp_force[b] -= f


func wheel_grounded_raw(i: int) -> bool:
	return wheel_grounded[i] == 1


## Generous curve: smooth rise to peak (zero slope at peak), then a slow ease down
## to `falloff_floor`. No cliff, so a slide stays catchable.
func _grip_curve(alpha_abs: float) -> float:
	var peak := deg_to_rad(peak_slip_angle_deg)
	if alpha_abs <= peak:
		var x := alpha_abs / peak
		return x * (2.0 - x)
	var t := clampf((alpha_abs - peak) / deg_to_rad(falloff_width_deg), 0.0, 1.0)
	return lerpf(1.0, falloff_floor, t * t * (3.0 - 2.0 * t))


func _drive_share(i: int) -> float:
	var front := i < 2
	match drive:
		Drive.RWD:
			return 0.0 if front else 0.5
		Drive.FWD:
			return 0.5 if front else 0.0
		_:
			return (1.0 - awd_rear_bias) * 0.5 if front else awd_rear_bias * 0.5


func _drive_force() -> float:
	# Gear: holding brake at a standstill engages reverse; throttle at a standstill leaves it.
	if not is_reversing:
		if brake > 0.1 and throttle < 0.05 and forward_speed < 0.5:
			_reverse_timer += get_physics_process_delta_time()
			if _reverse_timer > 0.25:
				is_reversing = true
				_reverse_timer = 0.0
		else:
			_reverse_timer = 0.0
	elif throttle > 0.1 and brake < 0.05 and forward_speed > -0.5:
		is_reversing = false
		_reverse_timer = 0.0

	var speed := absf(forward_speed)
	if is_reversing:
		var fade_r := clampf(1.0 - pow(speed / (reverse_top_speed_kmh / 3.6), 6.0), 0.0, 1.0)
		return -brake * reverse_force * fade_r
	var cap := minf(max_drive_force, engine_power_kw * 1000.0 / maxf(speed, 1.0))
	var fade := clampf(1.0 - pow(speed / (top_speed_kmh / 3.6), 6.0), 0.0, 1.0)
	return throttle * cap * fade


func _update_steering(delta: float) -> void:
	var target := steer
	var returning := absf(target) < absf(_steer_smoothed) or signf(target) != signf(_steer_smoothed)
	_steer_smoothed = move_toward(_steer_smoothed, target,
			(steer_return_rate if returning else steer_rate) * delta)

	var v2 := maxf(forward_speed * forward_speed, 1.0)
	var grip_lim := atan(wheelbase * tire_mu * surface_grip * front_grip * _gravity / v2) + deg_to_rad(steer_grip_margin_deg)
	var d := -_steer_smoothed * minf(deg_to_rad(max_steer_deg), grip_lim)   # stick right → −yaw

	wheel_steer[2] = 0.0
	wheel_steer[3] = 0.0
	if absf(d) < 1e-5:
		wheel_steer[0] = 0.0
		wheel_steer[1] = 0.0
		return
	var turn_r := wheelbase / tan(absf(d))
	var half := track_front * 0.5
	var inner := atan(wheelbase / (turn_r - half))
	var outer := atan(wheelbase / (turn_r + half))
	var s := signf(d)
	var fl := (inner if s > 0.0 else outer) * s   # left turn → FL is the inner wheel
	var fr := (outer if s > 0.0 else inner) * s
	wheel_steer[0] = lerpf(d, fl, ackermann)
	wheel_steer[1] = lerpf(d, fr, ackermann)


func _spin_airborne(i: int, delta: float, throttle_in: float, brake_in: float) -> void:
	var w := wheel_omega[i]
	if input_handbrake and i >= 2:
		w = 0.0
	elif brake_in > 0.05:
		w = move_toward(w, 0.0, 80.0 * brake_in * delta)
	elif _drive_share(i) > 0.0 and throttle_in > 0.05:
		var dir := -1.0 if is_reversing else 1.0
		w = move_toward(w, dir * (top_speed_kmh / 3.6) / wheel_radius, 60.0 * throttle_in * delta)
	else:
		w *= 1.0 - 0.3 * delta
	wheel_omega[i] = w


func _poll_player_input() -> void:
	input_throttle = Input.get_action_strength(&"throttle")
	input_brake = Input.get_action_strength(&"brake")
	input_steer = Input.get_axis(&"steer_left", &"steer_right")
	input_handbrake = Input.is_action_pressed(&"handbrake")


# === RESET ===

## Upright in place (keeps heading), dropped just above the ground.
func recover_upright() -> void:
	var p := global_position
	var fwd := -global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-4:
		fwd = Vector3.FORWARD
	var yaw := atan2(-fwd.x, -fwd.z)
	var ground := _ground_height_at(p)
	_request_reset(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, ground + 1.0, p.z)))


func reset_to_spawn() -> void:
	_request_reset(_spawn_xform)


func _request_reset(xf: Transform3D) -> void:
	if reset_locked:
		return
	_reset_xform = xf
	_pending_reset = true
	is_reversing = false
	_steer_smoothed = 0.0


func _ground_height_at(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 200.0, p + Vector3.DOWN * 400.0,
			LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if hit else p.y


# === META (single source of truth for the Maya proxy) ===

func build_take_meta() -> Dictionary:
	var hps: Array = []
	for hp in hardpoints:
		hps.append([hp.x, hp.y, hp.z])
	return {
		"body": {
			"extents": [body_size.x, body_size.y, body_size.z],
			"extents_are": "full_size",
			"com_offset": [com_offset.x, com_offset.y, com_offset.z],
			"mass": mass,
		},
		"wheelbase": wheelbase,
		"track_f": track_front,
		"track_r": track_rear,
		"wheel_radius": wheel_radius,
		"wheel_width": wheel_width,
		"susp_rest": susp_rest,
		"susp_max_travel": susp_max_travel,
		"hardpoints": hps,
		"wheel_order": ["FL", "FR", "RL", "RR"],
		"conventions": {
			"steer": "rad about chassis +Y, + = left",
			"spin_cumulative": "rad, + = forward roll, rotate wheel about -X",
			"compression": "m from full droop; wheel centre = hardpoint - (susp_rest - compression) * chassis_up",
			"slip_long": "(omega*r - v_long) / max(|v_long|, 1.0)",
			"slip_lat": "slip angle rad",
			"input_steer": "-1 left .. +1 right (raw device)",
			"t": "seconds relative to in point; handles are negative / beyond out",
		},
		"car_params": active_profile.to_dict(),
		"car_profile": {"name": active_profile.display_name, "path": active_profile.resource_path},
		"drive_mode": {"name": active_mode.display_name, "path": active_mode.resource_path,
			"params": active_mode.to_dict()},
		"world_profile": _world_meta(),
	}


func _world_meta() -> Dictionary:
	var w := WorldProfile.active
	if w == null:
		return {}
	return {"name": w.display_name, "path": w.resource_path, "params": w.to_dict()}
