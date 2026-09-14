@tool
class_name DriveMode
extends Resource
## How the car responds to you - layered on top of whatever car profile you picked, so one
## mode works for all four cars. Edit in the Inspector; profiles live in res://profiles/modes
## or user://profiles/modes, and the start menu lists both.
##
## Multipliers are x1.0 = "leave the car profile alone", so the shipped Standard mode changes
## nothing at all. Every take records the mode it was driven with.

@export_group("Identity")
@export var display_name: String = "Standard"
@export_multiline var description: String = ""

@export_group("Input response")
## Exponent on the analog triggers/stick: out = in^gamma. 1.0 = linear (what the pedal reads
## is what you get). 2.0 = finer control near the bottom, and the last part of the travel
## bites much harder - what most driving games use.
@export_range(0.5, 4.0) var throttle_gamma: float = 1.0
@export_range(0.5, 4.0) var brake_gamma: float = 1.0
@export_range(0.5, 4.0) var steer_gamma: float = 1.0
## Steering rates, x the car profile's (higher = whip the wheel over faster).
@export_range(0.25, 6.0) var steer_rate_scale: float = 1.0
@export_range(0.25, 6.0) var steer_return_scale: float = 1.0

@export_group("Limits and assists")
## Full stick = what the tyres can use at this speed, plus this margin. The car profile's
## value (2.5 deg) keeps the car planted; a large value (40) means full lock at any speed -
## you can ask for more than the tyres can give, and understeer or spin if you do.
@export var steer_grip_margin_deg: float = -1.0      ## < 0 = keep the car profile's value
@export_enum("Car profile", "Force on", "Force off") var abs_mode: int = 0
@export_enum("Car profile", "Force on", "Force off") var traction_control_mode: int = 0
## Below ~2 m/s the tyres cancel sideways slip so the car doesn't creep. Turning this off
## lets it slide to a standstill (useful for drifting into a mark).
@export var low_speed_hold: bool = true

@export_group("Force multipliers")
@export_range(0.25, 6.0) var brake_force_scale: float = 1.0
@export_range(0.25, 4.0) var engine_scale: float = 1.0
@export_range(0.25, 4.0) var drive_force_scale: float = 1.0
@export_range(0.25, 4.0) var handbrake_force_scale: float = 1.0

@export_group("Grip")
@export_range(0.25, 2.0) var tire_mu_scale: float = 1.0
@export_range(0.25, 2.0) var front_grip_scale: float = 1.0
## < 1 = the rear lets go first: power oversteer, drifts, donuts.
@export_range(0.25, 2.0) var rear_grip_scale: float = 1.0
## Grip a fully sliding tyre keeps, x the car profile's falloff_floor - separately per axle.
## FRONT decides whether the car still turns when you wind the wheel past what the tyres can
## use: keep it high (1.1-1.2) or full lock just plows straight on. REAR decides how a slide
## behaves: high = progressive and catchable, low = it spins and stays spun. Below about 0.85
## the car gets very hard to drive.
@export_range(0.3, 1.25) var falloff_floor_front_scale: float = 1.0
@export_range(0.3, 1.25) var falloff_floor_rear_scale: float = 1.0
## Slip angle where tyres make their most grip, x the car profile's 8 deg. Wider = more warning
## before they let go, and easier to hold an angle.
@export_range(0.5, 3.0) var peak_slip_angle_scale: float = 1.0
## Width of the falloff past the peak, x the car profile's. Wider = gentler, more progressive.
@export_range(0.5, 3.0) var falloff_width_scale: float = 1.0
@export_range(0.25, 2.0) var handbrake_rear_grip_scale: float = 1.0
## Raises the centre of mass, metres (+ = higher = more roll, and easier to trip over a kerb).
@export var com_raise: float = 0.0
## Sideways shove when a wheel jams into something (a kerb face, a bump, a bank), x the
## suspension force. 0 = off: wheels are only ever pushed along their own axis, so a sliding
## car rides over kerbs instead of tripping on them - and can't roll, because tyre grip alone
## can't tip it (that needs more than ~1.3 g). Above 0 the car can be tripped and rolled.
@export_range(0.0, 3.0) var kerb_trip: float = 0.0


func apply_to(car: Node) -> void:
	car.set("throttle_gamma", throttle_gamma)
	car.set("brake_gamma", brake_gamma)
	car.set("steer_gamma", steer_gamma)
	car.set("low_speed_hold", low_speed_hold)
	car.set("steer_rate", float(car.get("steer_rate")) * steer_rate_scale)
	car.set("steer_return_rate", float(car.get("steer_return_rate")) * steer_return_scale)
	if steer_grip_margin_deg >= 0.0:
		car.set("steer_grip_margin_deg", steer_grip_margin_deg)
	if abs_mode != 0:
		car.set("abs_enabled", abs_mode == 1)
	if traction_control_mode != 0:
		car.set("traction_control", traction_control_mode == 1)
	car.set("brake_force", float(car.get("brake_force")) * brake_force_scale)
	car.set("engine_power_kw", float(car.get("engine_power_kw")) * engine_scale)
	car.set("max_drive_force", float(car.get("max_drive_force")) * drive_force_scale)
	car.set("handbrake_force", float(car.get("handbrake_force")) * handbrake_force_scale)
	car.set("tire_mu", float(car.get("tire_mu")) * tire_mu_scale)
	car.set("front_grip", float(car.get("front_grip")) * front_grip_scale)
	car.set("rear_grip", float(car.get("rear_grip")) * rear_grip_scale)
	var floor_base: float = float(car.get("falloff_floor"))
	car.set("falloff_floor_front", clampf(floor_base * falloff_floor_front_scale, 0.0, 1.0))
	car.set("falloff_floor_rear", clampf(floor_base * falloff_floor_rear_scale, 0.0, 1.0))
	car.set("peak_slip_angle_deg", float(car.get("peak_slip_angle_deg")) * peak_slip_angle_scale)
	car.set("falloff_width_deg", float(car.get("falloff_width_deg")) * falloff_width_scale)
	car.set("handbrake_rear_grip", clampf(float(car.get("handbrake_rear_grip")) * handbrake_rear_grip_scale, 0.0, 1.0))
	car.set("kerb_trip", kerb_trip)
	if not is_zero_approx(com_raise):
		car.set("com_offset", (car.get("com_offset") as Vector3) + Vector3(0.0, com_raise, 0.0))


func to_dict() -> Dictionary:
	var d := {}
	for p in get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v: Variant = get(p["name"])
		if v is float or v is int or v is bool or v is String:
			d[p["name"]] = v
	return d


## True when nothing at all is changed (the shipped Standard mode).
func is_neutral() -> bool:
	for p in get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		if n in ["display_name", "description"]:
			continue
		var v: Variant = get(n)
		if n.ends_with("_gamma") or n.ends_with("_scale"):
			if not is_equal_approx(float(v), 1.0):
				return false
		elif n == "steer_grip_margin_deg":
			if float(v) >= 0.0:
				return false
		elif n == "low_speed_hold":
			if not v:
				return false
		elif n in ["com_raise", "kerb_trip"]:
			if not is_zero_approx(float(v)):
				return false
		elif int(v) != 0:
			return false
	return true


func summary() -> String:
	if is_neutral():
		return "The car profile exactly as tuned - assists on, steering limited to what the tyres can use."
	var bits := PackedStringArray()
	if not is_equal_approx(throttle_gamma, 1.0) or not is_equal_approx(brake_gamma, 1.0):
		bits.append("triggers ^%.1f/%.1f" % [throttle_gamma, brake_gamma])
	if steer_grip_margin_deg >= 20.0:
		bits.append("unlimited steering")
	if abs_mode == 2:
		bits.append("no ABS")
	if traction_control_mode == 2:
		bits.append("no TC")
	if not is_equal_approx(brake_force_scale, 1.0):
		bits.append("brakes x%.1f" % brake_force_scale)
	if rear_grip_scale < 1.0:
		bits.append("loose rear (x%.2f)" % rear_grip_scale)
	if not is_zero_approx(com_raise):
		bits.append("COM +%.2f m" % com_raise)
	if not low_speed_hold:
		bits.append("no low-speed hold")
	if kerb_trip > 0.0:
		bits.append("trips on kerbs")
	return "  |  ".join(bits)
