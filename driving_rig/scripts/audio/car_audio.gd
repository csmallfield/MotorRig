class_name CarAudio
extends Node3D
## Everything the car makes noise with. Created by the car itself, so no scene wiring.
##
## Engine: a pseudo-gearbox turns road speed into rpm (a real gearbox isn't modelled, but the
## ear expects one - without it a car pitches up like a siren all the way to top speed).
## Whatever engine layers exist are crossfaded by rpm and each is pitched to hit the exact rpm,
## so one file works and three sound properly.
##
## Skid, roll and wind are continuous loops whose gain and pitch follow the physics each tick.
## Impacts and bumps are one-shots picked at random from the numbered variants, with pitch and
## level variance so a run of kerb strikes doesn't machine-gun.

const PITCH_MIN: float = 0.55
const PITCH_MAX: float = 2.2
const IMPACT_COOLDOWN: float = 0.10

var enabled: bool = true
var report: String = ""

var _car: DrivingCar
var _lib: AudioLibrary
var _engine: Array[AudioStreamPlayer3D] = []
var _engine_rpm: PackedFloat64Array = PackedFloat64Array()
var _skid: AudioStreamPlayer3D
var _roll: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _impacts: Array[AudioStream] = []
var _bumps: Array[AudioStream] = []
var _oneshot: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _rpm: float = 0.0
var _since_impact: float = 1.0
var _air_prev: int = 0


func setup(car: DrivingCar) -> void:
	_car = car
	_rng.randomize()
	var set_name := car.active_profile.resource_path.get_file().get_basename() if car.active_profile else ""
	_lib = AudioLibrary.new(set_name)
	for layer in _lib.engine_layers():
		var p := _player("engine_%d" % int(layer["rpm"]), AudioLibrary.set_looping(layer["stream"]),
				car.engine_volume_db)
		_engine.append(p)
		_engine_rpm.append(layer["rpm"])
	_skid = _loop_player("skid", "skid")
	_roll = _loop_player("roll", "tyre_roll")
	_wind = _loop_player("wind", "wind")
	_scrape = _loop_player("scrape", "scrape")
	_impacts = _lib.variants("impact")
	_bumps = _lib.variants("bump")
	if not (_impacts.is_empty() and _bumps.is_empty()):
		_oneshot = _player("oneshot", null, 0.0)
	report = _lib.describe()
	if not _lib.missing.is_empty():
		report += "   missing: " + ", ".join(_lib.missing)
	car.impacted.connect(_on_impact)


func _physics_process(delta: float) -> void:
	if _car == null or not enabled:
		return
	var speed := absf(_car.forward_speed)
	_since_impact += delta

	# --- engine: pseudo-gearbox, then crossfade the layers around the rpm ---
	_rpm = lerpf(_rpm, _target_rpm(speed), 1.0 - exp(-8.0 * delta))
	for i in _engine.size():
		var p := _engine[i]
		p.pitch_scale = clampf(_rpm / maxf(_engine_rpm[i], 1.0), PITCH_MIN, PITCH_MAX)
		p.volume_db = linear_to_db(_layer_gain(i) * (0.55 + 0.45 * _car.throttle)) + _car.engine_volume_db
		if not p.playing:
			p.play()

	# --- tyres: roll with speed, skid with how hard they're sliding ---
	var slide := 0.0
	var grounded := 0
	for i in 4:
		if _car.wheel_grounded[i]:
			grounded += 1
			var lon: float = absf(_car.wheel_slip_long[i])
			var lat: float = absf(_car.wheel_slip_lat[i]) / deg_to_rad(20.0)
			slide = maxf(slide, sqrt(lon * lon + lat * lat))
	var moving := clampf(speed / 8.0, 0.0, 1.0)
	_set_loop(_roll, clampf(speed / 30.0, 0.0, 1.0) * float(grounded) / 4.0,
			0.75 + clampf(speed / 45.0, 0.0, 1.2))
	_set_loop(_skid, clampf((slide - 0.25) / 0.75, 0.0, 1.0) * moving * float(grounded) / 4.0,
			0.85 + 0.35 * clampf(slide, 0.0, 2.0) + _rng.randf_range(-0.02, 0.02))
	_set_loop(_wind, clampf((speed - 8.0) / 45.0, 0.0, 1.0), 0.8 + clampf(speed / 60.0, 0.0, 0.8))

	# --- landings: all four off the ground, then back on ---
	var air := 4 - grounded
	if _air_prev >= 3 and air == 0:
		_one_shot(_bumps, clampf(absf(_car.linear_velocity.y) / 6.0 + 0.3, 0.3, 1.0))
	_air_prev = air


## Road speed to rpm through a pretend gearbox: each gear runs from ~35 % of the band to the
## redline, then drops back. Wheelspin pushes the rpm up on its own.
func _target_rpm(speed: float) -> float:
	var idle: float = _car.engine_idle_rpm
	var red: float = _car.engine_redline_rpm
	var top := maxf(_car.top_speed_kmh / 3.6, 1.0)
	var gears: int = maxi(_car.gear_count, 1)
	var frac := clampf(speed / top, 0.0, 1.0)
	var g := clampi(int(frac * gears), 0, gears - 1)
	var within := frac * gears - g
	var rpm := lerpf(idle + (red - idle) * 0.35, red * 0.95, within)
	if speed < 0.5:
		rpm = idle + (red - idle) * 0.45 * _car.throttle      # revving at a standstill
	var spin := 0.0
	for i in 4:
		if _car.wheel_grounded[i]:
			spin = maxf(spin, clampf(_car.wheel_slip_long[i], 0.0, 1.5))
	return clampf(rpm + spin * (red - idle) * 0.35, idle, red)


## Triangular crossfade between the layers either side of the current rpm.
func _layer_gain(i: int) -> float:
	if _engine.size() == 1:
		return 1.0
	var here := _engine_rpm[i]
	var lo := _engine_rpm[i - 1] if i > 0 else here * 0.5
	var hi := _engine_rpm[i + 1] if i < _engine.size() - 1 else here * 2.0
	if _rpm <= here:
		return clampf((_rpm - lo) / maxf(here - lo, 1.0), 0.0, 1.0)
	return clampf((hi - _rpm) / maxf(hi - here, 1.0), 0.0, 1.0)


func _on_impact(strength: float, at: Vector3) -> void:
	if _since_impact < IMPACT_COOLDOWN:
		return
	_since_impact = 0.0
	# a scrape along a wall is a long string of small contacts; a crash is one big one
	var hard := clampf(strength / 6.0, 0.0, 1.0)
	_one_shot(_impacts, clampf(0.25 + hard, 0.25, 1.0), at)


func _one_shot(pool: Array[AudioStream], gain: float, at: Vector3 = Vector3.ZERO) -> void:
	if pool.is_empty() or _oneshot == null:
		return
	_oneshot.stream = pool[_rng.randi_range(0, pool.size() - 1)]
	_oneshot.position = to_local(at) if at != Vector3.ZERO else Vector3.ZERO
	_oneshot.pitch_scale = _rng.randf_range(0.92, 1.09)
	_oneshot.volume_db = linear_to_db(clampf(gain, 0.001, 1.0)) * 1.0
	_oneshot.play()


func _set_loop(p: AudioStreamPlayer3D, gain: float, pitch: float) -> void:
	if p == null:
		return
	p.pitch_scale = clampf(pitch, PITCH_MIN, PITCH_MAX)
	p.volume_db = linear_to_db(maxf(gain, 0.0001))
	if gain > 0.002 and not p.playing:
		p.play()
	elif gain <= 0.002 and p.playing:
		p.stop()


func _loop_player(name: String, base: String) -> AudioStreamPlayer3D:
	var s := _lib.one(base)
	return _player(name, AudioLibrary.set_looping(s), 0.0) if s else null


func _player(name: String, stream: AudioStream, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = name
	p.stream = stream
	p.volume_db = db
	p.unit_size = 12.0
	p.max_distance = 220.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(p)
	return p
