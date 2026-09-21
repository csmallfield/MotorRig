@tool
class_name CarProfile
extends Resource
## Everything that defines a car: dimensions, mass, suspension, tyres, drivetrain, steering.
## Edit in the Inspector (double-click the .tres). Property names match DrivingCar's, which
## copies them in at spawn. Every take records the profile it was driven with.
##
## Profiles live in res://profiles/cars (ship with the project) or user://profiles/cars
## (your AppData — the only place that works in an exported build). The start menu lists both.

enum Drive { RWD, FWD, AWD }

@export_group("Identity")
@export var display_name: String = "Proxy Sedan AWD"
@export_multiline var description: String = ""
@export var body_color: Color = Color(0.86, 0.42, 0.10)
## Physics tick the suspension/tyres were tuned at. The menu warns if the world runs at a
## different rate — spring behaviour is rate-dependent.
@export var tuned_at_hz: int = 240

@export_group("Chassis model")
## Your own body model (a .tscn, or an imported .glb/.gltf/.blend scene). Empty = the proxy box.
## Visual only: the collider is still the box from body_size, so size that to match.
@export var chassis_scene: PackedScene
## Offset / rotation / scale to fit the model to the car (car space: -Z forward, Y up, metres).
@export var chassis_transform: Transform3D = Transform3D.IDENTITY
## Hide the model from the driver cam (right for the solid proxy box; turn off for a model
## with a modelled interior and see-through glass).
@export var hide_chassis_in_driver_cam: bool = true

@export_group("Dimensions")
@export var mass: float = 1200.0
@export var body_size: Vector3 = Vector3(1.3, 1.0, 4.4)       ## full size, not half-extents
@export var com_offset: Vector3 = Vector3(0.0, -0.1, 0.0)
@export var wheelbase: float = 2.65
@export var track_front: float = 1.58
@export var track_rear: float = 1.56
@export var wheel_radius: float = 0.34
@export var wheel_width: float = 0.24
@export var hardpoint_height: float = -0.09   ## chassis-local Y of the suspension top mounts
@export var driver_eye: Vector3 = Vector3(-0.3, 0.47, 0.2)

@export_group("Suspension")
@export var susp_rest: float = 0.32           ## hardpoint -> wheel centre at full droop
@export var susp_max_travel: float = 0.18
@export var spring_rate_front: float = 40000.0
@export var spring_rate_rear: float = 40000.0
@export var damp_bump: float = 2600.0
@export var damp_rebound: float = 3400.0
@export var arb_front: float = 9000.0
@export var arb_rear: float = 5000.0
@export var bump_stop_rate: float = 250000.0
@export var visual_droop_rate: float = 30.0

@export_group("Tires")
@export var tire_mu: float = 1.15
@export var front_grip: float = 1.0
@export var rear_grip: float = 1.08           ## > front: understeer bias, no snap oversteer
@export var peak_slip_angle_deg: float = 8.0
@export var falloff_width_deg: float = 25.0
@export_range(0.0, 1.0) var falloff_floor: float = 0.82
@export var low_speed_slip_ref: float = 3.0
@export var rolling_resistance: float = 0.012
@export var tire_force_lift: float = 0.0

@export_group("Drivetrain")
@export var drive: Drive = Drive.AWD
@export_range(0.0, 1.0) var awd_rear_bias: float = 0.6
@export var engine_power_kw: float = 160.0
@export var max_drive_force: float = 9000.0
@export var top_speed_kmh: float = 220.0
@export var reverse_force: float = 4000.0
@export var reverse_top_speed_kmh: float = 35.0
@export var brake_force: float = 14000.0
@export_range(0.0, 1.0) var brake_bias_front: float = 0.65
@export var abs_enabled: bool = true
## Caps drive force at the grip left over after cornering, per wheel — keeps powerful
## rear-drive cars from spinning up on throttle.
@export var traction_control: bool = false
@export var handbrake_force: float = 6000.0
@export_range(0.0, 1.0) var handbrake_rear_grip: float = 0.55
@export var drag_coefficient: float = 0.42    ## F = c * v^2 (x world air_density_scale)

@export_group("Sound")
## Folder under res://audio (or user://audio) to take this vehicle's sounds from. Empty = the
## profile's own file name, e.g. city_bus.tres looks in res://audio/city_bus/ first, then
## res://audio/default/.
@export var audio_set: String = ""
@export var engine_idle_rpm: float = 800.0
@export var engine_redline_rpm: float = 6500.0
## Pretend gearbox: how many times the rpm sweeps up and drops back on the way to top speed.
@export_range(1, 10) var gear_count: int = 5
@export_range(-24.0, 12.0) var engine_volume_db: float = 0.0

@export_group("Steering wheel")
## Steering-wheel turns per road-wheel angle: 15 means 32 deg of lock = 480 deg (1.3 turns).
@export var steering_ratio: float = 15.0
@export var steering_wheel_radius: float = 0.19
## Wheel centre relative to driver_eye (car space).
@export var steering_wheel_offset: Vector3 = Vector3(0.0, -0.28, -0.5)
## Column tilt back from vertical.
@export var steering_column_tilt_deg: float = 20.0

@export_group("Steering")
@export var max_steer_deg: float = 32.0
@export var steer_grip_margin_deg: float = 2.5
@export var steer_rate: float = 4.5
@export var steer_return_rate: float = 6.0
@export_range(0.0, 1.0) var ackermann: float = 1.0


## {name: value} of every tunable (numbers, bools, vectors) — for take metadata.
func to_dict() -> Dictionary:
	var d := {}
	for p in get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v: Variant = get(p["name"])
		if v is Vector3:
			d[p["name"]] = [v.x, v.y, v.z]
		elif v is Color:
			d[p["name"]] = [v.r, v.g, v.b]
		elif v is float or v is int or v is bool or v is String:
			d[p["name"]] = v
	d["chassis_scene"] = chassis_scene.resource_path if chassis_scene else ""
	var t := chassis_transform
	d["chassis_transform"] = [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]
	return d


func summary() -> String:
	return "%d kg  |  %s%s  |  %d kW  |  %.1f m long, %.2f m wheelbase  |  springs %d/%d kN/m%s" % [
		mass, ["RWD", "FWD", "AWD"][drive], (" %d%% rear" % roundi(awd_rear_bias * 100)) if drive == Drive.AWD else "",
		engine_power_kw, body_size.z, wheelbase, roundi(spring_rate_front / 1000.0),
		roundi(spring_rate_rear / 1000.0), "  |  TC" if traction_control else ""]
