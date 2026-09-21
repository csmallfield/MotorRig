extends SceneTree
## Headless regression suite — run after retuning anything:
##
##   godot --headless --path . --fixed-fps 240 --script res://tests/run_tests.gd
##   godot --headless --path . --fixed-fps 240 --script res://tests/run_tests.gd -- corner_100 flick
##   ... -- car_profiles                                   every car profile on disk
##   ... -- car:user://profiles/cars/mine.tres:corner      one profile, one check (settle|corner|flick)
##
## (Windows: use the *console* exe, e.g. Godot_v4.7-stable_win64_console.exe.)
## Each test instantiates a fresh main scene. Takes go to user://test_takes, never your takes.
## Exit code = number of failures.

const TAKES_DIR: String = "user://test_takes"
const REF_CAR: String = "res://profiles/cars/sedan_awd.tres"
const REF_WORLD: String = "res://profiles/worlds/default_hills.tres"
const REF_MODE: String = "res://profiles/modes/standard.tres"
const ALL: Array[String] = ["settle", "accel_brake", "corner_60", "corner_100", "corner_140",
	"flick", "catch", "bumps", "ramp", "hills", "record_replay", "format_compat", "validator",
	"export", "scene_export", "browser", "menu", "car_profiles", "world_profiles", "drive_modes",
	"cameras", "camera_record", "steering_wheel", "custom_chassis", "mode_loose", "mode_stunt",
	"mode_drivable", "reverse_gear", "watch_mode", "layout", "audio_files", "audio_engine", "audio_impact",
	"interchange", "interchange_drive", "interchange_finish", "vehicle_models"]
const FLAT: Array[String] = ["accel_brake", "corner_60", "corner_100", "corner_140", "flick", "catch",
	"reverse_gear"]

var queue: Array[String] = []
var results: Array = []
var main: Node
var car: DrivingCar
var rec: TakeRecorder
var player: TakePlayer
var browser: TakeBrowser
var t: int = 0
var st: Dictionary = {}
var cur: String = ""
var cooldown: int = 0
var last_take: String = ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in (args if args.size() > 0 else ALL):
		if a == "car_profiles":
			for e: Dictionary in root.get_node("SimConfig").scan_cars():
				if e["profile"]:
					for kind in ["spawn", "settle", "corner", "flick"]:
						queue.append("car:%s:%s" % [e["path"], kind])
		elif a == "world_profiles":
			for e: Dictionary in root.get_node("SimConfig").scan_worlds():
				if e["profile"]:
					queue.append("world:%s" % e["path"])
		elif a == "mode_drivable":
			for e: Dictionary in root.get_node("SimConfig").scan_modes():
				if e["profile"] and not String(e["path"]).ends_with("stunt.tres"):
					queue.append("drivable:%s" % e["path"])   # Stunt is meant to tip over
		elif a == "drive_modes":
			for e: Dictionary in root.get_node("SimConfig").scan_modes():
				if e["profile"]:
					queue.append("mode:%s" % e["path"])
		elif a in ALL or a.begins_with("car:") or a.begins_with("world:") or a.begins_with("mode:"):
			queue.append(a)   # e.g. car:res://profiles/cars/suv_awd.tres:corner
		else:
			print("unknown test: ", a)
	DirAccess.make_dir_recursive_absolute(TAKES_DIR)
	var d := DirAccess.open(TAKES_DIR)
	for f in d.get_files():
		d.remove(f)
	print("Driving Rig tests — Godot %s, %d Hz, %s\n" % [Engine.get_version_info()["string"],
		Engine.physics_ticks_per_second, ProjectSettings.get_setting("physics/3d/physics_engine")])


func _physics_process(_d: float) -> bool:
	if cooldown > 0:
		cooldown -= 1
		return false
	if main == null:
		if queue.is_empty():
			_finish()
			return false
		cur = queue.pop_front()
		_start(cur)
		return false
	t += 1
	# Writing or loading a take happens on a worker thread. Headless --fixed-fps spins the sim
	# flat out, so yield a little wall clock while one is in flight or the test can time out
	# waiting for a file that is still being written.
	if rec and (rec.state == TakeRecorder.State.SAVING or (player and player.loading)):
		OS.delay_msec(10)
	var fn := "_t_" + cur
	if cur.begins_with("car:"):
		fn = "_t_car_" + cur.rsplit(":", true, 1)[1]
	elif cur.begins_with("world:"):
		fn = "_t_world"
	elif cur.begins_with("mode:"):
		fn = "_t_mode"
	elif cur.begins_with("drivable:"):
		fn = "_t_drivable"
	# most tests are done inside a minute of sim; driving four ramps end to end is not
	var cap := 240 * (200 if cur == "interchange_drive" else 60)
	if call(fn) or t > cap:
		if t > cap:                      # the cap is per test, so the report must use it too
			_result(false, "timeout")
		main.queue_free()
		main = null
		cooldown = 3
	return false


func _start(test_name: String) -> void:
	# Always pin profiles: the menu selection (SimConfig) must never change what tests measure.
	Engine.physics_ticks_per_second = 240
	main = load("res://scenes/main.tscn").instantiate()
	var car_path := REF_CAR
	var mode_path := REF_MODE
	var world: WorldProfile = load(REF_WORLD)
	if test_name.begins_with("car:"):
		car_path = test_name.split(":", true, 1)[1].rsplit(":", true, 1)[0]
	if test_name.begins_with("world:"):
		world = load(test_name.substr(6))
	if test_name.begins_with("mode:"):
		mode_path = test_name.substr(5)
	if test_name == "mode_loose":
		mode_path = "res://profiles/modes/loose.tres"
	if test_name == "mode_stunt":
		mode_path = "res://profiles/modes/stunt.tres"
	if test_name.begins_with("interchange"):
		world = load("res://profiles/worlds/interchange.tres")
	if test_name.begins_with("drivable:"):
		mode_path = test_name.substr(9)
	if test_name in FLAT or test_name.ends_with(":corner") or test_name.ends_with(":flick") \
			or test_name in ["mode_loose", "mode_stunt"] or test_name.begins_with("mode:") \
			or test_name.begins_with("drivable:"):
		world = world.duplicate()
		world.flat_radius = 5000.0
	main.get_node("Car").profile = load(car_path)
	main.get_node("Car").drive_mode = load(mode_path)
	main.get_node("Terrain").profile = world
	main.get_node("Recorder").takes_dir = TAKES_DIR
	root.add_child(main)
	car = main.get_node("Car")
	rec = main.get_node("Recorder")
	player = main.get_node("TakePlayer")
	browser = main.get_node("TakeBrowser")
	car.use_player_input = false
	t = 0
	st = {}


func _result(ok: bool, detail: String) -> void:
	results.append([cur, ok, detail])
	var label := cur
	if cur.begins_with("car:"):
		label = "%s %s" % [cur.rsplit(":", true, 1)[0].get_file().get_basename(), cur.rsplit(":", true, 1)[1]]
	elif cur.begins_with("world:"):
		label = "world " + cur.get_file().get_basename()
	elif cur.begins_with("mode:"):
		label = "mode " + cur.get_file().get_basename()
	elif cur.begins_with("drivable:"):
		label = "drivable " + cur.get_file().get_basename()
	print("%s  %-22s %s" % ["PASS" if ok else "FAIL", label, detail])


func _finish() -> void:
	var fails := 0
	for r: Array in results:
		if not r[1]:
			fails += 1
	print("\n%d / %d passed" % [results.size() - fails, results.size()])
	quit(fails)


# === helpers ===

func sec() -> float:
	return t / 240.0

func roll_deg() -> float:
	return rad_to_deg(asin(clampf(car.global_basis.x.y, -1.0, 1.0)))

func pitch_deg() -> float:
	return rad_to_deg(asin(clampf(-car.global_basis.z.y, -1.0, 1.0)))

func body_slip_deg() -> float:
	var v := car.linear_velocity
	v.y = 0.0
	if v.length() < 2.0:
		return 0.0
	var f := -car.global_basis.z
	f.y = 0.0
	return rad_to_deg(f.normalized().signed_angle_to(v.normalized(), Vector3.UP))

func kmh() -> float:
	return car.forward_speed * 3.6

func drive(th: float, br: float, steer: float, hb: bool = false) -> void:
	car.input_throttle = th
	car.input_brake = br
	car.input_steer = steer
	car.input_handbrake = hb

func place(pos: Vector3, yaw: float) -> void:
	car._request_reset(Transform3D(Basis(Vector3.UP, yaw), pos))

## Drop height that suits the vehicle: a bus rests at 1.87 m, so the sedan's 1.0 would bury it.
func spawn_y() -> float:
	return _predicted_ride_y() + 0.25


func air_count() -> int:
	var a := 0
	for i in 4:
		a += 1 - car.wheel_grounded[i]
	return a

## Ride height the front springs settle at. The front axle carries only its share of the
## weight when the centre of mass sits off centre, so the naive mass/4 is wrong for anything
## nose- or tail-heavy (it was 9 mm out on the limo).
func _predicted_ride_y() -> float:
	var front_share: float = clampf((car.wheelbase * 0.5 - car.com_offset.z) / car.wheelbase, 0.0, 1.0)
	var comp := car.mass * car._gravity * front_share * 0.5 / car.spring_rate_front
	return -(car.hardpoint_height - (car.susp_rest - comp) - car.wheel_radius)


# === tests (return true when finished) ===

func _t_settle() -> bool:
	var y := car.global_position.y
	if sec() > 4.0 and sec() <= 6.0:
		st["lo"] = minf(st.get("lo", 99.0), y)
		st["hi"] = maxf(st.get("hi", -99.0), y)
	if t == 6 * 240:
		st["rest"] = y
		st["jit"] = (st["hi"] - st["lo"]) * 1000.0
		st["ride_err"] = absf(y - _predicted_ride_y()) * 1000.0
		st["tilt"] = maxf(absf(roll_deg()), absf(pitch_deg()))
		car.apply_central_impulse(Vector3(0, -4000, 0))
		car.apply_torque_impulse(car.global_basis.z * 1500.0)
	if t == 8 * 240:
		var settle_err := absf(y - st["rest"]) * 1000.0
		var ok: bool = st["jit"] < 0.5 and st["ride_err"] < 2.0 and st["tilt"] < 0.05 and settle_err < 2.0
		_result(ok, "rest jitter %.3f mm · ride height err %.2f mm · tilt %.3f° · 2 s after push %.2f mm" % [
			st["jit"], st["ride_err"], st["tilt"], settle_err])
		return true
	return false


func _t_accel_brake() -> bool:
	if t == 1:
		place(Vector3(0, 0.8, 100), PI)
	if not st.has("brake_v"):
		drive(1.0 if sec() > 1.0 else 0.0, 0.0, 0.0)
		if not st.has("t100") and kmh() >= 100.0:
			st["t100"] = sec() - 1.0
		if kmh() >= 120.0:
			st["brake_v"] = car.forward_speed
			st["brake_t"] = sec()
			st["brake_p"] = car.global_position
	else:
		drive(0.0, 1.0, 0.0)
		if car.forward_speed < 0.3:
			var dt: float = sec() - st["brake_t"]
			var g: float = st["brake_v"] / dt / 9.81
			var dist: float = car.global_position.distance_to(st["brake_p"])
			var ok: bool = st["t100"] > 3.0 and st["t100"] < 7.0 and g > 0.9 and g < 1.3
			_result(ok, "0-100 %.2f s · 120→0 %.1f m, avg %.2f g" % [st["t100"], dist, g])
			return true
	return false


func _corner(target: float) -> bool:
	if t == 1:
		place(Vector3(280, 0.8, 280), PI * 0.25)
	if not st.has("go"):
		drive(1.0, 0.0, 0.0)
		if kmh() >= target:
			st["go"] = sec()
			st["yr"] = PackedFloat64Array()
			st["v"] = PackedVector3Array()
		return false
	drive(clampf((target - kmh()) * 0.1, 0.0, 1.0), 0.0, 1.0)
	var el: float = sec() - st["go"]
	st["slip"] = maxf(st.get("slip", 0.0), absf(body_slip_deg()))
	if el > 2.0:
		st["yr"].append(car.angular_velocity.y)
		var hv := car.linear_velocity
		hv.y = 0.0
		st["v"].append(hv)
	if el > 4.0:
		var yr: PackedFloat64Array = st["yr"]
		var m := 0.0
		for y in yr:
			m += y
		m /= yr.size()
		var sd := 0.0
		for y in yr:
			sd += (y - m) * (y - m)
		sd = sqrt(sd / yr.size())
		var vl: PackedVector3Array = st["v"]
		var acc := 0.0
		for j in range(12, vl.size() - 12, 12):
			acc = maxf(acc, (vl[j + 12] - vl[j - 12]).length() / (24.0 / 240.0) / 9.81)
		var ok: bool = st["slip"] < 12.0 and sd < 0.05 and acc > 0.8 and acc < 1.35
		_result(ok, "full lock @%d: body slip %.1f° · yaw-rate s.d. %.3f · %.2f g" % [target, st["slip"], sd, acc])
		return true
	return false

func _t_corner_60() -> bool:
	return _corner(60.0)

func _t_corner_100() -> bool:
	return _corner(100.0)

func _t_corner_140() -> bool:
	return _corner(140.0)


func _t_flick() -> bool:
	if t == 1:
		place(Vector3(280, 0.8, 280), PI * 0.25)
	if not st.has("go"):
		drive(1.0, 0.0, 0.0)
		if kmh() >= 110.0:
			st["go"] = sec()
		return false
	var el: float = sec() - st["go"]
	drive(0.0, 0.0, 0.35 if el < 0.4 else (-0.35 if el < 0.8 else 0.0))
	st["slip"] = maxf(st.get("slip", 0.0), absf(body_slip_deg()))
	if el > 3.0:
		_result(st["slip"] < 10.0 and kmh() > 80.0, "lift-off flick @110: max body slip %.1f° · exit %.0f km/h" % [st["slip"], kmh()])
		return true
	return false


func _t_catch() -> bool:
	if t == 1:
		place(Vector3(280, 0.8, 280), PI * 0.25)
	if not st.has("go"):
		drive(1.0, 0.0, 0.0)
		if kmh() >= 60.0:
			st["go"] = sec()
		return false
	var el: float = sec() - st["go"]
	if el < 0.5:
		drive(0.0, 0.0, 0.6, true)
	else:
		drive(0.3, 0.0, clampf(body_slip_deg() / 25.0, -1.0, 1.0))
	st["slip"] = maxf(st.get("slip", 0.0), absf(body_slip_deg()))
	if el > 4.0:
		_result(absf(body_slip_deg()) < 3.0, "handbrake kick: peak %.1f° · after countersteer %.1f°" % [st["slip"], body_slip_deg()])
		return true
	return false


func _t_bumps() -> bool:
	if t == 1:
		place(Vector3(0, 0.8, 20), 0.0)
	drive(clampf((40.0 - kmh()) * 0.3, 0.0, 1.0), 0.0, 0.0)
	var z := car.global_position.z
	if z < -25.0 and z > -48.0:
		st["pitch"] = maxf(st.get("pitch", 0.0), absf(pitch_deg()))
		if air_count() == 4:
			st["air"] = st.get("air", 0) + 1
	if z < -55.0:
		_result(st.get("air", 0) == 0 and st["pitch"] < 4.0, "3× 8 cm bumps @40: all-wheels-air %d ticks · max pitch %.2f°" % [st.get("air", 0), st["pitch"]])
		return true
	return false


func _t_ramp() -> bool:
	if t == 1:
		place(Vector3(18, 0.8, 20), 0.0)
	drive(clampf((70.0 - kmh()) * 0.3, 0.0, 1.0), 0.0, 0.0)
	if air_count() == 4 and t > 240:
		st["air"] = st.get("air", 0) + 1
	if car.global_position.z < -90.0:
		var up := car.global_basis.y.y > 0.95
		_result(up and st.get("air", 0) > 72, "ramp @70: airtime %.2f s · landed upright %s" % [st.get("air", 0) / 240.0, up])
		return true
	return false


func _t_hills() -> bool:
	if t == 1:
		place(Vector3(0, 0.8, 0), PI)
		car.contact_monitor = true
		car.max_contacts_reported = 4
	drive(clampf((50.0 - kmh()) * 0.5, 0.0, 1.0), 0.0, 0.0)
	if t > 240:
		if air_count() == 4:
			st["air"] = st.get("air", 0) + 1
		if car.get_contact_count() > 0:
			st["scrape"] = st.get("scrape", 0) + 1
	if car.global_position.z > 380.0:
		var ok: bool = st.get("air", 0) == 0 and st.get("scrape", 0) == 0
		_result(ok, "hills @50: airtime %d ticks · body contact %d ticks" % [st.get("air", 0), st.get("scrape", 0)])
		return true
	return false


## Record live, logging every wheel mesh's world transform per tick; then rebuild the ghost
## from the file (meta only) and compare every sample. This is the spec 2.3 test, measured.
func _t_record_replay() -> bool:
	if t == 1:
		st["live"] = {}
		var src := GDScript.new()
		src.source_code = "extends Node\nvar cb: Callable\nfunc _physics_process(_d: float) -> void:\n\tcb.call()\n"
		src.reload()
		var logger := Node.new()
		logger.set_script(src)
		logger.process_physics_priority = 200   # after the recorder captured this tick
		logger.set("cb", _log_live)
		main.add_child(logger)
		rec.take_saved.connect(func(p: String, _s: Dictionary) -> void: st["saved"] = p)
	if t == 120:
		rec.request_toggle()
	drive(0.55 if sec() > 0.5 else 0.0, 0.0, 0.3 * sin(sec() * 0.9) if sec() > 5.0 else 0.0)
	if t == 120 + 3 * 240 + 2400:
		rec.request_toggle()
	if st.has("saved") and not st.has("loading"):
		st["loading"] = true
		player.loaded.connect(func(_p: String) -> void: st["loaded"] = true)
		player.load_failed.connect(func(m: String) -> void: _result(false, "load failed: " + m))
		player.load_take(st["saved"])
	if st.has("loaded"):
		player.playing = false
		var meta := player.meta
		var start_tick: int = rec._in_tick - int(meta["in_index"])
		var expected := 2400 + 2 * rec.handle_ticks + 1
		var max_pos := 0.0
		var max_rot := 0.0
		var compared := 0
		for i in player.n:
			var o := i * TakeFormat.STRIDE
			player.ghost.apply(player.data, o, o, 0.0)
			var live: Array = st["live"].get(start_tick + i, [])
			if live.is_empty():
				continue
			for w in 4:
				var gx: Transform3D = player.ghost.wheel_geos[w].global_transform
				var lx: Transform3D = live[w]
				max_pos = maxf(max_pos, gx.origin.distance_to(lx.origin))
				for c in 3:
					max_rot = maxf(max_rot, (gx.basis[c] - lx.basis[c]).length())
			compared += 1
		# v2 precision claim, per channel, against the raw (unrounded) ring buffer
		var prec := _worst_channel_error(player.data, player.n, func(i: int, o: int) -> float:
			return rec._buf[((start_tick + i) % rec._cap) * TakeFormat.STRIDE + o])
		var hdr := TakeFormat.read_header(st["saved"])
		var png_ok := FileAccess.file_exists(TakeFormat.stem(st["saved"]) + ".png")
		var kb := FileAccess.get_file_as_bytes(st["saved"]).size() / 1024.0
		last_take = st["saved"]
		var profiles_ok: bool = (meta.get("car_profile", {}) as Dictionary).get("name", "") == "Proxy Sedan AWD" \
				and (meta.get("world_profile", {}) as Dictionary).get("name", "") == "Default Hills" \
				and (meta.get("car_params", {}) as Dictionary).get("mass", 0.0) == 1200.0
		var ok: bool = player.n == expected and compared == player.n and max_pos < 1e-4 and max_rot < 1e-3 \
				and int(hdr["summary"]["samples"]) == expected and png_ok and player.format_version == 2 \
				and str(st["saved"]).ends_with(".json.gz") and kb < 800.0 and prec[0] <= 1.0 and profiles_ok
		_result(ok, "v%d %s, %.0f KB for 10 s · %d samples (expect %d) · every channel within its stated precision of the raw data (worst: %s at %.2f×) · ghost vs live: wheel pos err %.4f mm, rot err %.6f · thumbnail %s" % [
			player.format_version, str(st["saved"]).get_file(), kb, player.n, expected, prec[1], prec[0],
			max_pos * 1000.0, max_rot, png_ok] + (" · profiles in meta" if profiles_ok else " · PROFILES MISSING FROM META"))
		return true
	return false


func _log_live() -> void:
	var xs: Array = []
	for wn in DrivingCar.WHEEL_NAMES:
		xs.append((car.get_node("wheel_%s_steer/wheel_%s_susp/wheel_%s_spin/wheel_%s_geo" % [wn, wn, wn, wn]) as Node3D).global_transform)
	st["live"][rec._tick - 1] = xs


## Largest |a − b| over all channels, as a multiple of each channel's rounding step
## (0.5 · 10^-decimals; 0/1 flags use 0.5). ≤ 1.0 means every value honours its precision.
func _worst_channel_error(a: PackedFloat64Array, n: int, b: Callable, skip_optional: bool = false) -> Array:
	var worst := 0.0
	var worst_name := "-"
	for ch in TakeFormat.CHANNELS:
		if skip_optional and ch.get("optional", false):
			continue
		var tol := 0.5 if ch.get("flag", false) else 0.5 * pow(10.0, -int(ch["dec"])) * 1.0001
		for base in TakeFormat.group_bases(ch):
			for c in int(ch["comps"]):
				for i in n:
					var rel := absf(a[i * TakeFormat.STRIDE + base + c] - float(b.call(i, base + c))) / tol
					if rel > worst:
						worst = rel
						worst_name = ch["name"]
	return [worst, worst_name]


## The legacy v1 reader and the v2 reader must decode the same take to identical values,
## so v1 takes already on disk replay and export exactly. (Precision vs the raw data is
## checked in record_replay.)
func _t_format_compat() -> bool:
	if last_take == "":
		_result(false, "needs record_replay first")
		return true
	var v2 := TakeFormat.load_take(last_take)
	var d: PackedFloat64Array = v2["data"]
	var n: int = v2["n"]
	var meta: Dictionary = v2["meta"]
	var v1_path := TAKES_DIR.path_join("take_0900.json")
	var f := FileAccess.open(v1_path, FileAccess.WRITE)
	f.store_string(TakeFormat.v1_header_line(meta, v2["summary"]))
	for i in n:
		f.store_string(TakeFormat.v1_sample_line(d, i * TakeFormat.STRIDE,
				float(i - int(meta["in_index"])) / float(meta["tick_hz"])) + (",\n" if i < n - 1 else "\n"))
	f.store_string("]}\n")
	f.close()
	var v1 := TakeFormat.load_take(v1_path)
	var d1: PackedFloat64Array = v1["data"]
	var cmp := _worst_channel_error(d, n, func(i: int, o: int) -> float: return d1[i * TakeFormat.STRIDE + o], true)
	var ok: bool = int(v1["format_version"]) == 1 and v1["n"] == n and cmp[0] <= 1.0
	_result(ok, "v1 reader vs v2 reader on the same take: %d samples each, worst difference %.2f× rounding step" % [v1["n"], cmp[0]])
	st["v1_path"] = v1_path
	return true


## Export re-encodes: a v1 take exported to .json.gz must come out as valid v2.
func _t_export() -> bool:
	var v1_path := TAKES_DIR.path_join("take_0900.json")
	if not FileAccess.file_exists(v1_path):
		_result(false, "needs format_compat first")
		return true
	if t == 1:
		browser.open()
		browser.select_file("take_0900.json")
		st["dst"] = OS.get_user_data_dir().path_join("exported_test.json.gz")
		browser.export_to(st["dst"])
		return false
	if browser._validate_thread == null and t > 2:
		var dst: String = st["dst"]
		var errs := TakeValidator.validate_file(dst)
		var r := TakeFormat.load_take(dst)
		var kb := FileAccess.get_file_as_bytes(dst).size() / 1024.0
		var src_kb := FileAccess.get_file_as_bytes(v1_path).size() / 1024.0
		var ok: bool = errs.is_empty() and int(r.get("format_version", 0)) == 2 and r.get("n", 0) > 0
		_result(ok, "v1 take (%.0f KB) exported → v2 gz (%.0f KB, %.1f× smaller) · %d validation errors" % [
			src_kb, kb, src_kb / maxf(kb, 0.01), errs.size()])
		DirAccess.remove_absolute(dst)
		DirAccess.remove_absolute(v1_path)
		browser.close()
		return true
	return false


func _t_validator() -> bool:
	if last_take == "":
		_result(false, "needs record_replay first")
		return true
	var errs := TakeValidator.validate_file(last_take)
	var text := TakeFormat._read_text(last_take)
	var bad_path := TAKES_DIR.path_join("corrupt.json")
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	# a grounded flag of 2, and a non-numeric value that also makes vel.x one sample too long
	f.store_string(text.replace('"wheels.grounded":[[1,', '"wheels.grounded":[[2,').replace('"vel":[[', '"vel":[["x",'))
	f.close()
	var bad := TakeValidator.validate_file(bad_path)
	DirAccess.remove_absolute(bad_path)
	_result(errs.is_empty() and bad.size() > 0, "real take: %d errors · corrupted copy: %d errors (first: %s)" % [
		errs.size(), bad.size(), bad[0] if bad.size() > 0 else "-"])
	return true


## Export the scene from the browser: files, manifest, and the ground's first vertex landing
## exactly on the terrain height function at the terrain corner, in cm.
func _t_scene_export() -> bool:
	if t == 1:
		st["parent"] = OS.get_user_data_dir().path_join("test_scene_export")
		st["t0"] = Time.get_ticks_msec()
		browser.scene_exported.connect(func(r: Dictionary) -> void: st["result"] = r)
		st["dir"] = browser.export_scene_to(st["parent"])
		return false
	if not st.has("result"):
		OS.delay_msec(20)   # headless --fixed-fps spins flat out; yield like a paced frame would
		return false
	var r: Dictionary = st["result"]
	var dir: String = st["dir"]
	var ms: int = Time.get_ticks_msec() - st["t0"]
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("scene.json")))
	var ok: bool = r.get("ok", false) and man is Dictionary
	var detail := "export failed: %s" % r.get("error", "?")
	if ok:
		var terrain: Terrain = main.get_node("Terrain")
		var objs: Array = man["objects"]
		var ground: Dictionary = objs.filter(func(o: Dictionary) -> bool: return o["name"] == "Ground")[0]
		var f := FileAccess.open(dir.path_join("Ground.obj"), FileAccess.READ)
		var first_v := PackedFloat64Array()
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("v "):
				for part in line.substr(2).split(" "):
					first_v.append(part.to_float())
				break
		f.close()
		var half := terrain.size * 0.5
		var want := Vector3(-half, terrain.height_at(-half, -half), -half) * 100.0
		var err := Vector3(first_v[0], first_v[1], first_v[2]).distance_to(want)
		var names := objs.map(func(o: Dictionary) -> String: return o["name"])
		ok = objs.size() >= 7 and int(ground["vertices"]) == 160801 and int(ground["triangles"]) == 320000 \
				and err < 0.001 and man["collision_source"] == terrain.collision_source_id and man["units"] == "cm"
		var mb := 0.0
		for o: Dictionary in objs:
			mb += FileAccess.get_file_as_bytes(dir.path_join(o["file"])).size() / 1048576.0
		detail = "%d objects %s · ground %d verts / %d tris · %.1f MB · %.1f s · ground corner vertex err %.4f cm" % [
			objs.size(), str(names), ground["vertices"], ground["triangles"], mb, ms / 1000.0, err]
	_result(ok, detail)
	return true


func _t_browser() -> bool:
	if t == 1:
		browser.open()
		st["items"] = browser.item_count()
		if st["items"] == 0:
			_result(false, "no takes listed (run record_replay first)")
			return true
		browser.select_file(last_take.get_file())
		browser.replay_selected()
	if player.active and not st.has("t0"):
		st["t0"] = t
		st["pos0"] = player.pos
	if st.has("t0") and t == st["t0"] + 240:
		var advanced: float = player.pos - st["pos0"]
		var following: bool = main.get_node("ChaseCam")._follow == player.ghost
		var blocked := rec.blocked and not car.use_player_input
		player.stop()
		browser.close()
		var restored := car.use_player_input and not rec.blocked and car.visible
		var ok: bool = absf(advanced - 240.0) < 2.0 and following and blocked and restored
		_result(ok, "%d listed · ghost advanced %.0f samples in 1 s · cam follows ghost %s · input/record locked %s · restored on close %s" % [
			st["items"], advanced, following, blocked, restored])
		return true
	return false


# === profiles ===

## Every car profile on disk: settles cleanly at its own ride height.
func _t_car_settle() -> bool:
	if t == 1:
		place(Vector3(0, spawn_y(), 0), 0.0)
	var y := car.global_position.y
	if sec() > 3.0 and sec() <= 5.0:
		st["lo"] = minf(st.get("lo", 99.0), y)
		st["hi"] = maxf(st.get("hi", -99.0), y)
	if t == 5 * 240:
		var jit: float = (st["hi"] - st["lo"]) * 1000.0
		var err := absf(y - _predicted_ride_y()) * 1000.0
		var tilt := maxf(absf(roll_deg()), absf(pitch_deg()))
		_result(jit < 0.5 and err < 3.0 and tilt < 0.1, "%s: jitter %.3f mm · ride height err %.2f mm · tilt %.3f deg" % [
			car.active_profile.display_name, jit, err, tilt])
		return true
	return false


## Full lock, at a speed the vehicle can actually reach: no spin, no wobble, and upright
## unless it is physically top-heavy enough to tip (a quad is - so is a real one).
func _t_car_corner() -> bool:
	if t == 1:
		place(Vector3(280, spawn_y(), 280), PI * 0.25)
		st["target"] = minf(80.0, car.top_speed_kmh * 0.7)
	if not st.has("go"):
		drive(1.0, 0.0, 0.0)
		if kmh() >= st["target"]:
			st["go"] = sec()
			st["yr"] = PackedFloat64Array()
		return false
	drive(clampf((st["target"] - kmh()) * 0.1, 0.0, 1.0), 0.0, 1.0)
	var el: float = sec() - st["go"]
	st["slip"] = maxf(st.get("slip", 0.0), absf(body_slip_deg()))
	st["roll"] = maxf(st.get("roll", 0.0), absf(roll_deg()))
	st["minup"] = minf(st.get("minup", 1.0), car.global_basis.y.y)
	if el > 2.0:
		st["yr"].append(car.angular_velocity.y)
	if el > 4.0:
		var yr: PackedFloat64Array = st["yr"]
		var m := 0.0
		for v in yr:
			m += v
		m /= yr.size()
		var sd := 0.0
		for v in yr:
			sd += (v - m) * (v - m)
		sd = sqrt(sd / yr.size())
		# static stability factor: half the track over the centre-of-mass height. Below the
		# tyres' grip the vehicle tips before it slides - true of quads, and of this one.
		var com_h: float = _predicted_ride_y() + car.com_offset.y
		var ssf: float = (car.track_front * 0.5) / maxf(com_h, 0.01)
		var tippy: bool = ssf < car.tire_mu * car.front_grip
		var ok: bool = st["slip"] < 15.0 and sd < 0.08 and (tippy or (st["roll"] < 12.0 and st["minup"] > 0.9))
		_result(ok, "%s full lock @%.0f: body slip %.1f deg · yaw s.d. %.3f · roll %.1f deg · upright %s · SSF %.2f vs grip %.2f%s" % [
			car.active_profile.display_name, st["target"], st["slip"], sd, st["roll"],
			st["minup"] > 0.9, ssf, car.tire_mu * car.front_grip, " (tips by design)" if tippy else ""])
		return true
	return false


## Lift-off flick near the car's pace: stays catchable.
func _t_car_flick() -> bool:
	var target := minf(110.0, car.top_speed_kmh * 0.6)
	if t == 1:
		place(Vector3(280, spawn_y(), 280), PI * 0.25)
	if not st.has("go"):
		drive(1.0, 0.0, 0.0)
		if kmh() >= target:
			st["go"] = sec()
		return false
	var el: float = sec() - st["go"]
	drive(0.0, 0.0, 0.35 if el < 0.4 else (-0.35 if el < 0.8 else 0.0))
	st["slip"] = maxf(st.get("slip", 0.0), absf(body_slip_deg()))
	if el > 3.0:
		_result(st["slip"] < 12.0 and car.global_basis.y.y > 0.9, "%s flick @%d: max body slip %.1f deg" % [
			car.active_profile.display_name, target, st["slip"]])
		return true
	return false


## Every world profile on disk: builds, applies its physics, and the reference car settles.
func _t_world() -> bool:
	if t == 4 * 240:
		var w: WorldProfile = main.get_node("Terrain").profile
		var terrain: Terrain = main.get_node("Terrain")
		var g: float = PhysicsServer3D.area_get_param(car.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY)
		var settled := absf(car.linear_velocity.y) < 0.01 and car.global_basis.y.y > 0.999
		var ok: bool = terrain.collision_source_id != "" and WorldProfile.active == w \
				and Engine.physics_ticks_per_second == w.tick_hz and is_equal_approx(g, w.gravity) \
				and is_equal_approx(car.surface_grip, w.surface_grip) and settled
		_result(ok, "%s: %s · g %.2f · %d Hz · grip %.2f · car settled %s" % [w.display_name,
			terrain.collision_source_id, g, Engine.physics_ticks_per_second, car.surface_grip, settled])
		return true
	return false


## The start menu lists what's on disk, selects, and warns on a tick mismatch — without
## disturbing the user's saved selection.
func _t_menu() -> bool:
	var cfg: Node = root.get_node("SimConfig")
	var keep_car: String = cfg.car_path
	var keep_world: String = cfg.world_path
	var keep_mode: String = cfg.mode_path
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	main.add_child(menu)
	var cars: int = cfg.scan_cars().size()
	var worlds: int = cfg.scan_worlds().size()
	var modes: int = cfg.scan_modes().size()
	var listed: bool = menu.item_count("cars") == cars and menu.item_count("worlds") == worlds \
			and menu.item_count("modes") == modes and cars >= 4 and worlds >= 4 and modes >= 5
	var picked: bool = cfg.select("res://profiles/cars/sports_rwd.tres", "res://profiles/worlds/wet_hills.tres",
			"res://profiles/modes/loose.tres") \
			and cfg.car_profile.display_name == "Sports RWD" and cfg.world_profile.surface_grip == 0.7 \
			and cfg.drive_mode.display_name == "Loose"
	var clean: bool = cfg.warnings().size() == 1 and "Loose" in cfg.warnings()[0]   # mode warning only
	cfg.select("res://profiles/cars/sports_rwd.tres", "res://profiles/worlds/wet_hills.tres", REF_MODE)
	clean = clean and cfg.warnings().is_empty()
	var fast: WorldProfile = (cfg.world_profile as WorldProfile).duplicate()
	fast.tick_hz = 120
	cfg.world_profile = fast
	var warned: bool = cfg.warnings().size() == 1 and "Hz" in cfg.warnings()[0]
	var bogus := FileAccess.open("user://profiles/cars/zz_not_a_profile.tres", FileAccess.WRITE)
	bogus.store_string("[gd_resource type=\"Resource\" format=3]\n[resource]\n")
	bogus.close()
	var flagged := false
	for e: Dictionary in cfg.scan_cars():
		if String(e["path"]).ends_with("zz_not_a_profile.tres"):
			flagged = e["profile"] == null and e["error"] != ""
	DirAccess.remove_absolute("user://profiles/cars/zz_not_a_profile.tres")
	if keep_car != "" and keep_world != "":
		cfg.select(keep_car, keep_world, keep_mode)
	_result(listed and picked and clean and warned and flagged,
		"%d cars, %d worlds, %d modes listed · select ok %s · tick-mismatch warning %s · invalid file flagged %s" % [
		cars, worlds, modes, picked, warned, flagged])
	return true


# === cameras, steering wheel, custom chassis ===

func _rig() -> ChaseCameraRig:
	return main.get_node("ChaseCam")


## All nine cameras, every tick, driving into the hills with steering: tracking cameras keep
## the car in frame, rigid mounts stay fixed to the car, nothing goes under the ground.
func _t_cameras() -> bool:
	var rig := _rig()
	if t == 1:
		place(Vector3(20, 0.9, 90), PI)
		st["seen"] = {}
		st["frames"] = 0
		st["rigid_err"] = 0.0
		st["under"] = 0
		st["nonfinite"] = 0
		st["changed"] = []
		st["rigid0"] = {}
		rig.camera_changed.connect(func(n: String) -> void: st["changed"].append(n))
		# check after the rig has placed the cameras this tick (priority 200), not before the
		# physics step moves the car
		var src := GDScript.new()
		src.source_code = "extends Node\nvar cb: Callable\nfunc _physics_process(_d: float) -> void:\n\tcb.call()\n"
		src.reload()
		var logger := Node.new()
		logger.set_script(src)
		logger.process_physics_priority = 200
		logger.set("cb", _check_cameras)
		main.add_child(logger)
	drive(clampf((60.0 - kmh()) * 0.3, 0.0, 1.0), 0.0, 0.35 * sin(sec() * 0.8))
	if t == 240 * 12:
		var start := rig.active_camera
		var visited := {}
		for k in rig.cycle_list().size():
			rig.cycle(1)
			visited[rig.camera_label(rig.active_camera)] = true
		var wraps := rig.active_camera == start
		rig.select_index(2)
		var direct := rig.camera_label(rig.active_camera) == "heli"
		var worst := 2.0
		var worst_n := ""
		for n: String in ["chase", "heli", "front", "side", "trackside", "orbit", "crane", "drone", "lowchase", "pan"]:
			var frac: float = float(st["seen"].get(n, 0)) / st["frames"]
			if frac < worst:
				worst = frac
				worst_n = n
		var heli_h := rig.cameras[2].global_position.y - car.global_position.y
		var ok: bool = worst > 0.97 and st["rigid_err"] < 1e-4 and st["under"] == 0 and st["nonfinite"] == 0 \
				and visited.size() == TakeFormat.CAMERA_NAMES.size() and wraps and direct \
				and heli_h > 8.0 and st["changed"].size() >= TakeFormat.CAMERA_NAMES.size()
		_result(ok, "%d ticks x %d cams · car in frame >= %.1f%% (worst %s) · rigid mounts drift %.6f m · below ground %d · heli +%.0f m · cycle %d/%d wraps %s · 1-9 jump %s" % [
			st["frames"], TakeFormat.CAMERA_NAMES.size(), worst * 100.0, worst_n, st["rigid_err"],
			st["under"], heli_h, visited.size(), TakeFormat.CAMERA_NAMES.size(), wraps, direct])
		return true
	return false


## Rotation between two quaternions, precise near zero (acos of a dot product isn't: float32
## can only resolve ~1e-3 rad there).
func _quat_angle(a: Quaternion, b: Quaternion) -> float:
	var d := Vector4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w)
	if a.dot(b) < 0.0:
		d = Vector4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)
	return 4.0 * asin(minf(d.length() * 0.5, 1.0))   # chord |dq| = 2 sin(theta/4)


func _check_cameras() -> void:
	if main == null or cur != "cameras" or t <= 480:
		return   # the logger can outlive its test by a frame
	var rig := _rig()
	st["frames"] += 1
	var inv := car.global_transform.affine_inverse()
	for i in rig.cameras.size():
		var n: String = TakeFormat.CAMERA_NAMES[i]
		var cam := rig.cameras[i]
		var x := cam.global_transform
		if not (x.origin.is_finite() and x.basis.x.is_finite()):
			st["nonfinite"] += 1
			continue
		if n in ["chase", "heli", "front", "side", "trackside", "orbit", "crane", "drone", "lowchase", "pan"]:
			if cam.is_position_in_frustum(car.global_position):
				st["seen"][n] = st["seen"].get(n, 0) + 1
			if x.origin.y < _ground_y(x.origin) + 0.3:
				st["under"] += 1
		if n in ["wheel", "bumper", "driver", "rearwheel"]:
			var local := inv * x
			if not st["rigid0"].has(n):
				st["rigid0"][n] = local
			st["rigid_err"] = maxf(st["rigid_err"], (local.origin - (st["rigid0"][n] as Transform3D).origin).length())


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 300.0, p + Vector3.DOWN * 300.0, DrivingCar.LAYER_WORLD)
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if hit else -INF


## Switch cameras mid-take: camera.active records the switches at the right ticks, and every
## camera's recorded path matches its live path (within the 1 mm / 1e-5 precision).
func _t_camera_record() -> bool:
	var rig := _rig()
	if t == 1:
		st["live"] = {}
		var src := GDScript.new()
		src.source_code = "extends Node\nvar cb: Callable\nfunc _physics_process(_d: float) -> void:\n\tcb.call()\n"
		src.reload()
		var logger := Node.new()
		logger.set_script(src)
		logger.process_physics_priority = 200
		logger.set("cb", func() -> void:
			if main == null or cur != "camera_record" or not is_instance_valid(rig):
				return
			var xs: Array = []
			for c in rig.cameras:
				xs.append(c.global_transform)
			st["live"][rec._tick - 1] = [xs, rig.active_index()])
		main.add_child(logger)
		rec.take_saved.connect(func(p: String, _s: Dictionary) -> void: st["saved"] = p)
		rec.request_toggle()
	drive(0.5, 0.0, 0.3 * sin(sec()))
	var in_t := 1 + 3 * 240
	if t == in_t + 480:
		rig.select_index(2)     # heli
		st["switch1"] = rec._tick
	if t == in_t + 960:
		rig.select_index(5)     # wheel
		st["switch2"] = rec._tick
	if t == in_t + 1440:
		rec.request_toggle()
	if st.has("saved") and not st.has("checked"):
		st["checked"] = true
		var r := TakeFormat.load_take(st["saved"])
		var d: PackedFloat64Array = r["data"]
		var meta: Dictionary = r["meta"]
		var start: int = rec._in_tick - int(meta["in_index"])
		var n: int = r["n"]
		var pos_err := 0.0
		var rot_err := 0.0
		var per := {}
		var active_ok := 0
		for i in n:
			var live: Array = st["live"].get(start + i, [])
			if live.is_empty():
				continue
			if int(d[i * TakeFormat.STRIDE + TakeFormat.O_ACTIVE]) == int(live[1]):
				active_ok += 1
			for k in TakeFormat.CAMERA_NAMES.size():
				var o := i * TakeFormat.STRIDE + TakeFormat.O_CAMS + k * TakeFormat.C_STRIDE
				var lx: Transform3D = live[0][k]
				var pe := Vector3(d[o], d[o + 1], d[o + 2]).distance_to(lx.origin)
				pos_err = maxf(pos_err, pe)
				var q := Quaternion(d[o + 3], d[o + 4], d[o + 5], d[o + 6]).normalized()
				var re := _quat_angle(q, lx.basis.get_rotation_quaternion())
				rot_err = maxf(rot_err, re)
				var nm: String = TakeFormat.CAMERA_NAMES[k]
				per[nm] = [maxf(per.get(nm, [0.0, 0.0])[0], pe), maxf(per.get(nm, [0.0, 0.0])[1], re)]
		var a1 := int(d[(st["switch1"] - start) * TakeFormat.STRIDE + TakeFormat.O_ACTIVE])
		var a2 := int(d[(st["switch2"] - start) * TakeFormat.STRIDE + TakeFormat.O_ACTIVE])
		var names_ok: bool = Array(meta.get("camera_names", [])) == Array(TakeFormat.CAMERA_NAMES)
		# file precision: positions 1 mm per axis (vector <= sqrt(3) x 0.5 mm), quaternions 1e-5
		var ok: bool = names_ok and active_ok == n and a1 == 2 and a2 == 5 and pos_err < 0.00087 and rot_err < 1e-4
		_result(ok, "9 cameras recorded · active track matches live on %d/%d samples (switch to heli, wheel at the right ticks: %s) · camera pos err %.2f mm, rot err %.6f rad" % [
			active_ok, n, a1 == 2 and a2 == 5, pos_err * 1000.0, rot_err])
		return true
	return false


## Turning left: road wheels steer +, the steering wheel turns ratio x that, counter-clockwise
## from the driver's seat - its top marker moves to the driver's left.
func _t_steering_wheel() -> bool:
	if t == 1:
		place(Vector3(280, 1.0, 280), PI * 0.25)
	drive(0.0, 0.0, -1.0 if sec() > 1.0 else 0.0)
	if t == 3 * 240:
		var mean_steer := (car.wheel_steer[0] + car.wheel_steer[1]) * 0.5
		var want := mean_steer * car.steering_ratio
		var wheel := car.get_node("SteeringColumn/SteeringWheel") as Node3D
		var marker := wheel.get_node("TopMarker") as Node3D
		var column := car.get_node("SteeringColumn") as Node3D
		var inv := car.global_transform.affine_inverse()
		var dx := (inv * marker.global_position).x - (inv * column.global_position).x
		var ok := mean_steer > 0.1 and absf(car.steering_wheel_angle - want) < 1e-6 \
				and absf(wheel.rotation.z - want) < 1e-4 and dx < -0.1
		_result(ok, "left lock: road wheels %.1f deg -> steering wheel %.0f deg (ratio %.0f:1) · top marker %.2f m to the driver's left" % [
			rad_to_deg(mean_steer), rad_to_deg(car.steering_wheel_angle), car.steering_ratio, -dx])
		return true
	return false


## A custom chassis model replaces the proxy box; the collider and handling don't change, and
## the replay ghost rebuilds the same model from the take's meta.
func _t_custom_chassis() -> bool:
	if t == 1:
		# rebuild the scene with a profile that has a chassis model
		main.queue_free()
		main = load("res://scenes/main.tscn").instantiate()
		var p: CarProfile = (load(REF_CAR) as CarProfile).duplicate()
		p.chassis_scene = load("res://tests/fixtures/chassis_test.tscn")
		p.chassis_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0))
		main.get_node("Car").profile = p
		main.get_node("Terrain").profile = load(REF_WORLD)
		main.get_node("Recorder").takes_dir = TAKES_DIR
		root.add_child(main)
		car = main.get_node("Car")
		rec = main.get_node("Recorder")
		player = main.get_node("TakePlayer")
		browser = main.get_node("TakeBrowser")
		car.use_player_input = false
		return false
	if t == 5 * 240:
		var model := car.get_node_or_null("ChassisModel")
		var has_box := car.get_node_or_null("BodyGeo") != null
		var col := car.get_node("BodyCollider") as CollisionShape3D
		var layers_ok := true
		for v in model.find_children("*", "VisualInstance3D", true, false):
			layers_ok = layers_ok and (v as VisualInstance3D).layers == DrivingCar.VIS_LAYER_BODY
		var settled := absf(car.linear_velocity.y) < 0.01 and absf(car.global_position.y - _predicted_ride_y()) < 0.003
		var ghost := GhostCar.new()
		main.add_child(ghost)
		var meta := car.build_take_meta()
		meta["susp_rest"] = car.susp_rest
		ghost.build(meta, null, null, null)
		var ghost_model := ghost.get_node_or_null("chassis_model") != null and ghost.get_node_or_null("body_geo") == null
		var ok: bool = model != null and not has_box and (col.shape as BoxShape3D).size == car.body_size \
				and layers_ok and settled and ghost_model
		_result(ok, "model in, box out %s · collider still %s · driver-cam layer %s · settles at ride height %s · ghost rebuilds model %s" % [
			model != null and not has_box, (col.shape as BoxShape3D).size, layers_ok, settled, ghost_model])
		return true
	return false


# === drive modes ===

## Every drive mode on disk: builds, applies, car drives and stays finite. Standard must be
## exactly neutral - the reference numbers depend on it.
func _t_mode() -> bool:
	if t == 1:
		place(Vector3(280, 1.0, 280), PI * 0.25)
	# straight line: loose modes spin out on a steering sweep, which says nothing about whether
	# the mode itself is sound
	drive(1.0, 0.0, 0.0)
	if t == 6 * 240:
		var m: DriveMode = car.drive_mode
		var neutral_ok: bool = (m.display_name != "Standard") or m.is_neutral()
		var ref: CarProfile = load(REF_CAR)
		var untouched: bool = not m.is_neutral() or (is_equal_approx(car.brake_force, ref.brake_force)
				and is_equal_approx(car.tire_mu, ref.tire_mu) and car.abs_enabled == ref.abs_enabled
				and is_equal_approx(car.throttle_gamma, 1.0))
		var speed := car.linear_velocity.length() * 3.6
		var sane: bool = car.global_position.is_finite() and car.global_basis.y.y > 0.5 and speed > 30.0
		_result(neutral_ok and untouched and sane, "%s: %s · drives straight at %.0f km/h, upright %s" % [
			m.display_name, m.summary().left(80), speed, car.global_basis.y.y > 0.5])
		return true
	return false


## What Loose is for: brakes that lock all four wheels, full steering lock at speed,
## a sustained donut, and a drift you can hold - none of which Standard can do.
func _t_mode_loose() -> bool:
	if t == 1:
		place(Vector3(300, 1.0, 300), PI * 0.25)
		st["stage"] = "brake"
	match st["stage"]:
		"brake":
			if not st.has("go"):
				drive(1.0, 0.0, 0.0)
				if kmh() >= 100.0:
					st["go"] = sec()
					st["v0"] = car.forward_speed
			else:
				drive(0.0, 1.0, 0.0)
				var locked := 0
				for i in 4:
					if car.wheel_slip_long[i] < -0.9:
						locked += 1
				st["locked"] = maxi(st.get("locked", 0), locked)
				if car.forward_speed < 0.3:
					st["brake_g"] = st["v0"] / (sec() - st["go"]) / 9.81
					st["stage"] = "steer"
					st.erase("go")
		"steer":
			if not st.has("go"):
				drive(1.0, 0.0, 0.0)
				if kmh() >= 120.0:
					st["go"] = sec()
			else:
				drive(0.0, 0.0, 1.0)
				st["steer_deg"] = maxf(st.get("steer_deg", 0.0), rad_to_deg(absf(car.wheel_steer[0])))
				if sec() - st["go"] > 0.6:
					st["stage"] = "donut"
					st.erase("go")
					place(Vector3(300, 1.0, 300), PI * 0.25)
					st["t0"] = t
		"donut":
			var el: int = t - st["t0"]
			drive(1.0, 0.0, 1.0, el > 60)   # handbrake donut: pull it and keep it pulled
			if el > 480:
				st["slip"] = maxf(st.get("slip", 0.0), absf(body_slip_deg()))
				st["yaw"] = maxf(st.get("yaw", 0.0), absf(car.angular_velocity.y))
				st["donut_kmh"] = maxf(st.get("donut_kmh", 0.0), car.linear_velocity.length() * 3.6)
			if el == 240 * 7:
				var ok: bool = st.get("locked", 0) == 4 and st.get("steer_deg", 0.0) > 20.0 \
						and st.get("slip", 0.0) > 60.0 and st.get("yaw", 0.0) > 1.5 \
						and st.get("donut_kmh", 0.0) > 15.0 and st["brake_g"] > 0.9
				_result(ok, "all 4 wheels lock (%.2f g stop) · full lock at 120 = %.0f deg road-wheel angle · sustained donut %.0f deg slip, %.1f rad/s, %.0f km/h" % [
					st["brake_g"], st["steer_deg"], st["slip"], st["yaw"], st["donut_kmh"]])
				return true
	return false


## Stunt: a hard corner at the grip limit puts it on its roof; a quick flick does not.
func _t_mode_stunt() -> bool:
	if t == 1:
		place(Vector3(300, 1.2, 300), PI * 0.25)
		st["stage"] = "corner"
	if not st.has("go"):
		drive(1.0, 0.0, 0.0)
		if kmh() >= 90.0:
			st["go"] = t
		return false
	var el: int = t - st["go"]
	if st["stage"] == "corner":
		drive(0.5, 0.0, 0.25)
		st["roll"] = maxf(st.get("roll", 0.0), absf(roll_deg()))
		st["up"] = minf(st.get("up", 1.0), car.global_basis.y.y)
		if el == 240 * 5:
			st["stage"] = "flick"
			st.erase("go")
			place(Vector3(300, 1.2, 300), PI * 0.25)
	else:
		drive(0.6, 0.0, 0.4 if el < 60 else (-0.4 if el < 120 else 0.0))
		st["flick_roll"] = maxf(st.get("flick_roll", 0.0), absf(roll_deg()))
		st["flick_up"] = minf(st.get("flick_up", 1.0), car.global_basis.y.y)
		if el == 240 * 3:
			var rolled: bool = st.get("up", 1.0) < 0.0
			var survived: bool = st.get("flick_up", 1.0) > 0.8
			_result(rolled and survived, "hard corner rolls it (%.0f deg, upside down %s) · quick flick does not (%.0f deg)" % [
				st.get("roll", 0.0), rolled, st.get("flick_roll", 0.0)])
			return true
	return false


## The two things that made 0.9.0's modes unusable, as a permanent check on every mode:
##   1. it tracks straight at full throttle (no spinning out in a straight line)
##   2. a steady corner is a corner, not a spin - and full lock still turns rather than plowing
func _t_drivable() -> bool:
	if t == 1:
		place(Vector3(300, 1.0, 300), PI * 0.25)
		st["stage"] = "straight"
	match st["stage"]:
		"straight":
			drive(1.0, 0.0, 0.0)
			if t > 60:
				st["wander"] = maxf(st.get("wander", 0.0), absf(body_slip_deg()))
			if t == 240 * 7:
				st["top"] = car.linear_velocity.length() * 3.6
				st["stage"] = "corner"
				place(Vector3(300, 1.0, 300), PI * 0.25)
				st["settle"] = t
		"corner", "full":
			if t < st.get("settle", 0) + 60:
				return false
			if not st.has("go"):
				drive(1.0, 0.0, 0.0)
				if kmh() >= 80.0:
					st["go"] = t
				return false
			var steer: float = 0.35 if st["stage"] == "corner" else 1.0
			drive(0.35, 0.0, steer)
			var el: int = t - st["go"]
			if el > 180:
				var key: String = "slip_" + str(st["stage"])
				st[key] = maxf(st.get(key, 0.0), absf(body_slip_deg()))
			if el == 240 * 3:
				var speed := car.linear_velocity.length()
				var r: float = speed / maxf(absf(car.angular_velocity.y), 0.001)
				st["r_" + str(st["stage"])] = r
				st["kmh_" + str(st["stage"])] = speed * 3.6
				# radius against the tightest the tyres allow at this speed (v^2 / mu.g).
				# A plowing car needs far more room than that; a sliding one needs less.
				var mu: float = maxf(car.tire_mu * car.surface_grip * car.front_grip, 0.01)
				st["ratio_" + str(st["stage"])] = r / maxf(speed * speed / (mu * car._gravity), 0.01)
				if st["stage"] == "corner":
					st["stage"] = "full"
					st.erase("go")
					place(Vector3(300, 1.0, 300), PI * 0.25)
					st["settle"] = t
				else:
					var name: String = car.drive_mode.display_name
					# a corner at 80 km/h must stay a corner (< 50 deg of slip), turn at all
					# (radius < 120 m), and full lock must turn tighter than a third-lock does
					# 1. tracks straight at full throttle
					# 2. a steady corner stays a corner: not spun, and speed not scrubbed away
					# 3. full lock actually turns: either a tight radius, or visibly sideways.
					#    Plowing is the combination of a wide radius AND no slip angle - which
					#    is exactly what 0.9.0's Loose did.
					var ok: bool = st.get("wander", 0.0) < 5.0 and st.get("top", 0.0) > 100.0 \
							and st.get("slip_corner", 0.0) < 60.0 and st.get("kmh_corner", 0.0) > 40.0 \
							and (st.get("ratio_full", 99.0) < 1.6 or st.get("slip_full", 0.0) > 25.0)
					_result(ok, "%s: straight %.0f km/h, wander %.1f deg · corner: radius %.0f m, %.0f deg slip, holds %.0f km/h · full lock radius %.0f m (%.2fx tightest possible, %.0f deg slip)" % [
						name, st.get("top", 0.0), st.get("wander", 0.0), st.get("r_corner", 0.0),
						st.get("slip_corner", 0.0), st.get("kmh_corner", 0.0),
						st.get("r_full", 0.0), st.get("ratio_full", 0.0), st.get("slip_full", 0.0)])
					return true
	return false


## Reverse is a gear you select (X), not something the brake does. Holding the brake must
## always just brake, and reverse must not engage at speed.
func _t_reverse_gear() -> bool:
	if t == 1:
		place(Vector3(300, 1.0, 300), PI * 0.25)
		st["stage"] = "brake_holds"
	match st["stage"]:
		"brake_holds":
			drive(0.0, 1.0, 0.0)                      # brake held from a standstill
			if t == 240 * 3:
				st["crept"] = car.linear_velocity.length()
				st["still_drive"] = not car.is_reversing
				st["stage"] = "select"
		"select":
			drive(0.0, 0.0, 0.0)
			if t == 240 * 3 + 10:
				st["at_rest"] = car.toggle_reverse() and car.is_reversing
			elif t > 240 * 3 + 10:
				drive(1.0, 0.0, 0.0)                  # throttle now goes backwards
				if t == 240 * 6:
					st["back_kmh"] = -car.forward_speed * 3.6
					st["stage"] = "no_change_at_speed"
					car.is_reversing = false
					st.erase("go")
		"no_change_at_speed":
			drive(1.0, 0.0, 0.0)
			if kmh() > 60.0 and not st.has("tried"):
				st["tried"] = true
				st["refused"] = not car.toggle_reverse() and not car.is_reversing
				st["stage"] = "brake_at_speed"
				st["t0"] = t
		"brake_at_speed":
			drive(0.0, 1.0, 0.0)                      # brake to a stop and keep holding
			if t - st["t0"] == 240 * 5:
				var ok: bool = st.get("still_drive", false) and st.get("crept", 9.0) < 0.05 \
						and st.get("at_rest", false) and st.get("back_kmh", 0.0) > 10.0 \
						and st.get("refused", false) and not car.is_reversing \
						and car.linear_velocity.length() < 0.05
				_result(ok, "brake at a standstill just holds (no creep, stays in D) · X selects reverse, %.0f km/h backwards · X refused at speed · braking to a stop never selects reverse" % st.get("back_kmh", 0.0))
				return true
	return false


## Watch mode: RB hides the browser, parks the car and lets you watch the replay from any
## angle - the live cameras aimed at the ghost, plus every angle the take itself recorded.
func _t_watch_mode() -> bool:
	var rig: ChaseCameraRig = main.get_node("ChaseCam")
	if t == 1:
		if not FileAccess.file_exists(last_take):
			_result(false, "needs record_replay first")
			return true
		browser.open()
		browser.select_file(last_take.get_file())
		browser.watch()                      # not loaded yet: should load, then watch
		return false
	if not player.active:
		return false
	if not st.has("t0"):
		st["t0"] = t
		st["pos0"] = player.pos
		st["names"] = Array(player.recorded_cam_names)
		st["live_labels"] = []
		st["take_labels"] = []
		return false
	if t == st["t0"] + 240:
		st["advanced"] = player.pos - st["pos0"]
		# cycle every camera watch mode offers and record what each one was
		var list := rig.watch_list()
		for i in list.size():
			rig.cycle(1)
			var label := rig.camera_label(rig.active_camera)
			if label.begins_with("take: "):
				st["take_labels"].append(label.substr(6))
			else:
				st["live_labels"].append(label)
		# a take camera must sit where the take says it was
		rig.select_index(0)
		var k: int = st["names"].find("heli")
		var cam: Camera3D = player.recorded_cams[k]
		var i0 := int(player.pos) * TakeFormat.STRIDE + TakeFormat.O_CAMS + k * TakeFormat.C_STRIDE
		st["cam_err"] = cam.global_position.distance_to(Vector3(player.data[i0], player.data[i0 + 1], player.data[i0 + 2]))
		st["panel_hidden"] = not browser._panel.visible and not browser.is_open
		st["hud"] = main.get_node("HUD")._status.text.contains("WATCHING")
		st["parked"] = not car.use_player_input and rec.blocked
		browser.stop_watching()
		return false
	if t == st["t0"] + 260:
		var back_in_browser: bool = browser._panel.visible and browser.is_open and not browser.is_watching
		var ok: bool = st.get("panel_hidden", false) and st.get("hud", false) and st.get("parked", false) \
				and absf(st.get("advanced", 0.0) - 240.0) < 2.0 \
				and st["take_labels"].size() == TakeFormat.CAMERA_NAMES.size() \
				and st["live_labels"].size() >= TakeFormat.CAMERA_NAMES.size() \
				and st.get("cam_err", 9.9) < 0.01 and back_in_browser and rig.replay_cams.is_empty()
		_result(ok, "panel hidden + HUD watch readout, car parked, ghost ran %.0f samples in 1 s · %d live cameras + %d from the take (%s...) · take camera matches the file to %.4f m · Tab returns to the browser" % [
			st.get("advanced", 0.0), st["live_labels"].size(), st["take_labels"].size(),
			", ".join(PackedStringArray(st["take_labels"]).slice(0, 3)), st.get("cam_err", 9.9)])
		return true
	return false


## The sample layout must match the camera list. (Adding cameras without moving O_ACTIVE let
## the extra ones overwrite the next field and corrupted every take written.)
func _t_layout() -> bool:
	var want: int = TakeFormat.O_CAMS + TakeFormat.C_STRIDE * TakeFormat.CAMERA_NAMES.size()
	var named := {}
	for n in TakeFormat.CAMERA_NAMES:
		named[n] = true
	var rig: ChaseCameraRig = main.get_node("ChaseCam")
	var ok: bool = TakeFormat.O_ACTIVE == want and TakeFormat.STRIDE == want + 1 \
			and named.size() == TakeFormat.CAMERA_NAMES.size() \
			and rig.cameras.size() == TakeFormat.CAMERA_NAMES.size()
	_result(ok, "%d cameras, all named uniquely · O_ACTIVE %d (want %d) · STRIDE %d · rig builds %d" % [
		TakeFormat.CAMERA_NAMES.size(), TakeFormat.O_ACTIVE, want, TakeFormat.STRIDE, rig.cameras.size()])
	return true


## The path a player actually takes: pick the profile, press DRIVE, hold the throttle. No
## teleporting the car to a convenient spot first - that is what hid the bus and the garbage
## truck spawning inside the road, where they could not move at all.
func _t_car_spawn() -> bool:
	if t == 1:
		st["spawn_y"] = car.global_position.y
	car.input_throttle = 1.0
	if t == 240 * 5:
		# the ground reference is where the wheels are touching, not a raycast that can miss
		var bottom: float = car.global_position.y - car.body_size.y * 0.5
		var ground := 0.0
		var touching := 0
		for i in 4:
			if car.wheel_grounded[i]:
				ground += car.wheel_contact_p[i].y
				touching += 1
		ground = ground / touching if touching > 0 else bottom
		var ok: bool = kmh() > 20.0 and touching == 4 and bottom > ground + 0.05 \
				and car.global_basis.y.y > 0.99
		_result(ok, "%s: scene spawn %.2f m, rests at %.2f (needs %.2f) · body %.2f m clear of the road · %.0f km/h from a standstill" % [
			car.active_profile.display_name, st["spawn_y"], car.global_position.y,
			car.rest_height(), bottom - ground, kmh()])
		return true
	return false


# === sound ===

## Files are picked up from disk by name, per vehicle, with a fallback - and anything missing
## is silent rather than an error.
func _t_audio_files() -> bool:
	var dir := "user://audio/default"
	var vdir := "user://audio/sedan_awd"
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.make_dir_recursive_absolute(vdir)
	for f in ["skid.wav", "tyre_roll.wav", "engine_0800.wav", "engine_4000.wav",
			"impact_01.wav", "impact_02.wav", "impact_03.wav"]:
		_write_wav(dir.path_join(f), 0.05)
	_write_wav(vdir.path_join("engine_1200.wav"), 0.05)     # this vehicle's own engine
	var lib := AudioLibrary.new("sedan_awd")
	var layers := lib.engine_layers()
	var vehicle_wins: bool = layers.size() == 1 and is_equal_approx(layers[0]["rpm"], 1200.0)
	var fallback := AudioLibrary.new("no_such_vehicle")
	var shared := fallback.engine_layers()
	var sorted_ok: bool = shared.size() == 2 and shared[0]["rpm"] < shared[1]["rpm"]
	var got_skid: bool = fallback.one("skid") != null
	var got_hits: bool = fallback.variants("impact").size() == 3
	var missing_is_quiet: bool = fallback.one("no_such_sound") == null and "no_such_sound" in fallback.missing
	var looped: bool = AudioLibrary.set_looping(fallback.one("skid")) is AudioStreamWAV
	for d in [dir, vdir]:
		var da := DirAccess.open(d)
		for f in da.get_files():
			da.remove(f)
	_result(vehicle_wins and sorted_ok and got_skid and got_hits and missing_is_quiet and looped,
		"per-vehicle folder wins (%s) · shared folder found %d engine layers in rpm order, skid, %d impacts · a missing sound is silent, not an error" % [
		vehicle_wins, shared.size(), fallback.variants("impact").size()])
	return true


func _write_wav(path: String, seconds: float) -> void:
	var rate := 22050
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	var n := int(rate * seconds)
	var d := PackedByteArray()
	d.resize(n * 2)
	for i in n:
		var v := int(sin(TAU * 220.0 * i / rate) * 8000.0)
		d.encode_s16(i * 2, v)
	w.data = d
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(_wav_bytes(d, rate))
	f.close()


func _wav_bytes(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	var head := PackedByteArray()
	head.resize(4)
	head.encode_u32(0, 36 + pcm.size())
	out.append_array(head)
	out.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, 1)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * 2)
	fmt.encode_u16(16, 2)
	fmt.encode_u16(18, 16)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	var dl := PackedByteArray()
	dl.resize(4)
	dl.encode_u32(0, pcm.size())
	out.append_array(dl)
	out.append_array(pcm)
	return out


## The pretend gearbox: rpm climbs within a gear and drops at the change, stays inside
## idle..redline, and wheelspin lifts it. Engine layers pitch toward the rpm they were
## recorded at.
func _t_audio_engine() -> bool:
	if t == 1:
		place(Vector3(300, spawn_y(), 300), PI * 0.25)
		st["rpm"] = []
		st["shifts"] = 0
	drive(1.0, 0.0, 0.0)
	if t > 240 and t % 12 == 0 and kmh() < car.top_speed_kmh * 0.98:
		var rpm: float = car.audio._target_rpm(absf(car.forward_speed))
		var prev: float = st["rpm"][-1] if not st["rpm"].is_empty() else rpm
		if rpm < prev - 200.0:
			st["shifts"] += 1
		st["rpm"].append(rpm)
		st["min"] = minf(st.get("min", 9e9), rpm)
		st["max"] = maxf(st.get("max", 0.0), rpm)
	if t == 240 * 14:
		var idle: float = car.engine_idle_rpm
		var red: float = car.engine_redline_rpm
		var in_range: bool = st.get("min", 0.0) >= idle - 1.0 and st.get("max", 0.0) <= red + 1.0
		var shifted: bool = st["shifts"] >= 2                      # several gear changes on the way up
		var climbs: bool = st["rpm"].size() > 10 and st["rpm"][-1] > st["rpm"][0]
		_result(in_range and shifted and climbs, "rpm stayed inside %.0f-%.0f (saw %.0f-%.0f) · %d gear changes accelerating to %.0f km/h" % [
			idle, red, st.get("min", 0.0), st.get("max", 0.0), st["shifts"], kmh()])
		return true
	return false


## Hitting something reports an impact, scaled by how hard - and the tyres doing their job
## never report one.
func _t_audio_impact() -> bool:
	if t == 1:
		st["hits"] = []
		car.impacted.connect(func(strength: float, _p: Vector3) -> void: st["hits"].append(strength))
		place(Vector3(300, spawn_y(), 300), PI * 0.25)
	if t < 240 * 6:
		drive(1.0, 0.0, 0.35 * sin(sec()))     # drive hard, corner, bounce: no collisions
		if t == 240 * 6 - 1:
			st["driving_hits"] = st["hits"].size()
		return false
	if t == 240 * 6:
		# put a wall in front of the car and drive into it
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(40, 8, 2)
		shape.shape = box
		wall.add_child(shape)
		wall.collision_layer = DrivingCar.LAYER_WORLD
		main.add_child(wall)
		wall.global_position = car.global_position - car.global_basis.z * 60.0 + Vector3.UP * 3.0
		st["hits"] = []
	drive(1.0, 0.0, 0.0)
	if t == 240 * 12:
		var hits: Array = st["hits"]
		var hardest := 0.0
		for h: float in hits:
			hardest = maxf(hardest, h)
		var ok: bool = st.get("driving_hits", 99) == 0 and hits.size() > 0 and hardest > 2.0
		_result(ok, "%d impacts while driving hard (want 0) · hit a wall: %d contacts reported, hardest %.1f m/s" % [
			st.get("driving_hits", -1), hits.size(), hardest])
		return true
	return false


# === highway interchange ===

func _interchange() -> InterchangeBuilder:
	return (main.get_node("Terrain") as Terrain).interchange


## The geometry has to be buildable in the real world: ramp radii and grades within highway
## standards, the surface actually present along every path, the bridge giving its clearance,
## and no two ramps wanting the same ground at the same height.
func _t_interchange() -> bool:
	if t < 3:
		return false
	var b := _interchange()
	var space := car.get_world_3d().direct_space_state
	var tight := INF
	var steep := 0.0
	var shortest := INF
	var surface_err := 0.0
	var missing := 0
	for r: Dictionary in b.ramps:
		tight = minf(tight, r["min_radius"])
		steep = maxf(steep, r["max_grade"])
		shortest = minf(shortest, r["length"])
		# interior points only: the first and last sit exactly on the ribbon's open end, where a
		# ray can slip past the edge
		var n_pts: int = (r["points"] as PackedVector3Array).size()
		for i in range(1, n_pts - 1, 5):
			var p: Vector3 = r["points"][i]
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p - Vector3.UP * 5.0,
					DrivingCar.LAYER_WORLD)
			var hit := space.intersect_ray(q)
			if hit:
				surface_err = maxf(surface_err, absf((hit["position"] as Vector3).y - p.y))
			else:
				missing += 1
	# clearance: upward off the mainline onto the underside of the deck
	var up := PhysicsRayQueryParameters3D.create(Vector3(13.6, 0.2, 0.0), Vector3(13.6, 14.0, 0.0),
			DrivingCar.LAYER_WORLD)
	var deck := space.intersect_ray(up)
	var clearance: float = (deck["position"] as Vector3).y if deck else 0.0
	# no two ramps within 10 m of each other at the same height
	var closest := INF
	for i in b.ramps.size():
		for j in range(i + 1, b.ramps.size()):
			var pa: PackedVector3Array = b.ramps[i]["points"]
			var pb: PackedVector3Array = b.ramps[j]["points"]
			for a in range(0, pa.size(), 4):
				for c in range(0, pb.size(), 4):
					if absf(pa[a].y - pb[c].y) <= 4.5:
						closest = minf(closest, Vector2(pa[a].x - pb[c].x, pa[a].z - pb[c].z).length())
	var ok: bool = b.ramps.size() == 4 and tight >= 43.0 and steep <= 0.06 and shortest >= 200.0 \
			and surface_err < 0.05 and missing == 0 and clearance >= 4.99 and closest > 10.0
	_result(ok, "%d ramps · tightest radius %.0f m (40 km/h needs 43) · steepest grade %.1f%% · shortest %.0f m · surface within %.3f m of every path, %d gaps · bridge clearance %.2f m · closest two ramps at the same height %.0f m" % [
		b.ramps.size(), tight, steep * 100.0, shortest, surface_err, missing, clearance, closest])
	return true


## And it has to be drivable: follow each ramp's centreline from the mainline up to the
## arterial, including the loop that passes under the bridge on its way round.
func _t_interchange_drive() -> bool:
	if t < 3:
		return false
	var b := _interchange()
	if not st.has("idx"):
		st["idx"] = 0
		st["worst_off"] = 0.0
		st["worst_pct"] = 100
		st["done"] = 0
		_ramp_start(b)
		return false
	var pts: PackedVector3Array = b.ramps[st["idx"]]["points"]
	var best: int = st["seg"]
	for i in range(st["seg"], mini(st["seg"] + 40, pts.size())):
		if car.global_position.distance_to(pts[i]) < car.global_position.distance_to(pts[best]):
			best = i
	st["seg"] = best
	var target: Vector3 = pts[mini(best + 12, pts.size() - 1)]
	var local := car.global_basis.inverse() * (target - car.global_position)
	drive(clampf((55.0 - kmh()) * 0.15, 0.0, 1.0), 0.0, clampf(local.x / maxf(absf(local.z), 1.0) * 1.6, -1.0, 1.0))
	st["off"] = maxf(st["off"], Vector2(car.global_position.x - pts[best].x, car.global_position.z - pts[best].z).length())
	if best >= pts.size() - 20 or t - int(st["t0"]) > 240 * 40:
		var pct := int(100.0 * best / (pts.size() - 1))
		st["worst_pct"] = mini(st["worst_pct"], pct)
		st["worst_off"] = maxf(st["worst_off"], st["off"])
		st["climbed"] = maxf(st.get("climbed", 0.0), car.global_position.y)
		st["idx"] += 1
		if st["idx"] >= b.ramps.size():
			var ok: bool = st["worst_pct"] >= 80 and st["worst_off"] < 6.0 and st.get("climbed", 0.0) > 6.0
			_result(ok, "all %d ramps driven from the mainline to the arterial: %d%% of the shortest run, never more than %.1f m off the centreline, climbing to %.1f m" % [
				b.ramps.size(), st["worst_pct"], st["worst_off"], st.get("climbed", 0.0)])
			return true
		_ramp_start(b)
	return false


func _ramp_start(b: InterchangeBuilder) -> void:
	var pts: PackedVector3Array = b.ramps[st["idx"]]["points"]
	var fwd := (pts[3] - pts[0]).normalized()
	place(pts[0] + Vector3.UP * spawn_y(), atan2(-fwd.x, -fwd.z))
	st["seg"] = 0
	st["off"] = 0.0
	st["t0"] = t


## The two things 0.14.0 got wrong, which the geometry and drive tests could not see:
##   * rails drawn as axis-aligned boxes, so on any ramp not heading north-south they sat
##     crossways to the road (with the collider pointing a different way from what you saw)
##   * roads laid at exactly the height of the ground and of each other - z-fighting everywhere
func _t_interchange_finish() -> bool:
	if t < 3:
		return false
	var b := _interchange()
	var space := car.get_world_3d().direct_space_state
	var want := InterchangeBuilder.RAMP_W * 0.5 + 0.05
	var rail_err := 0.0
	var rail_checks := 0
	var rail_misses := 0
	for r: Dictionary in b.ramps:
		var pts: PackedVector3Array = r["points"]
		for i in range(2, pts.size() - 2, 4):
			var p := pts[i]
			if p.y < 1.5 or (absf(p.z) < 16.0 and p.y > 5.4):
				continue                                    # at grade, or where you merge
			var fwd := pts[i + 1] - pts[i - 1]
			fwd.y = 0.0
			var out := fwd.normalized().cross(Vector3.UP)
			for side: float in [-1.0, 1.0]:
				var from := p + Vector3.UP * 0.5
				var q := PhysicsRayQueryParameters3D.create(from, from + out * side * 8.0, DrivingCar.LAYER_WORLD)
				var hit := space.intersect_ray(q)
				rail_checks += 1
				if hit:
					rail_err = maxf(rail_err, absf(from.distance_to(hit["position"]) - want))
				else:
					rail_misses += 1
	# coplanar surfaces: first hit, then everything else within 5 mm of it
	var coplanar := 0
	var samples := 0
	for x in range(-480, 481, 12):
		for z in range(-680, 681, 12):
			var q1 := PhysicsRayQueryParameters3D.create(Vector3(x, 30, z), Vector3(x, -5, z), DrivingCar.LAYER_WORLD)
			var a := space.intersect_ray(q1)
			if not a:
				continue
			samples += 1
			var y1: float = (a["position"] as Vector3).y
			var q2 := PhysicsRayQueryParameters3D.create(Vector3(x, y1 + 0.01, z), Vector3(x, y1 - 0.02, z),
					DrivingCar.LAYER_WORLD)
			q2.exclude = [a["rid"]]
			q2.hit_from_inside = true
			var c := space.intersect_ray(q2)
			if c and absf((c["position"] as Vector3).y - y1) < 0.005:
				coplanar += 1
	var ok: bool = rail_checks > 80 and rail_misses == 0 and rail_err < 0.02 and coplanar == 0
	_result(ok, "rails: %d sideways checks along the raised ramps, all hit %.2f m out (worst %.3f m off), %d misses · %d of %d points have two surfaces within 5 mm (z-fighting)" % [
		rail_checks, want, rail_err, rail_misses, coplanar, samples])
	return true


## Every vehicle body faces outward. 0.15.0 shipped with every triangle inside-out and neither
## a render nor a winding check caught it: the mesh was *consistently* inside-out, winding and
## normals agreeing with each other, both pointing in. What gives it away is signed volume -
## every closed shell encloses a positive volume under one winding convention and a negative
## one under the other. Each material surface here is built from closed solids, so each must
## come out with the same sign as a box Godot made itself.
func _t_vehicle_models() -> bool:
	var outward := signf(_signed_volume(BoxMesh.new().get_mesh_arrays()))
	var report := PackedStringArray()
	var bad := 0
	var checked := 0
	var tris := 0
	var da := DirAccess.open("res://profiles/cars")
	for f in da.get_files():
		if not f.ends_with(".tres"):
			continue
		var prof: CarProfile = load("res://profiles/cars/" + f)
		if prof.chassis_scene == null:
			report.append("%s: no model" % f.get_basename())
			bad += 1
			continue
		var inst := prof.chassis_scene.instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for sfc in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(sfc)
				tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				var vol := _signed_volume(arr)
				checked += 1
				if signf(vol) != outward:
					bad += 1
					report.append("%s surface %d inside-out (%.2f m3)" % [f.get_basename(), sfc, vol])
		inst.free()
	_result(bad == 0 and checked >= 16, "%d surfaces across 8 bodies (%d triangles), every one enclosing a positive volume like Godot's own box%s" % [
		checked, tris, ("" if report.is_empty() else " - " + "; ".join(report.slice(0, 4)))])
	return true


## Volume enclosed by a closed triangle mesh, signed by its winding (divergence theorem).
func _signed_volume(arr: Array) -> float:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var vol := 0.0
	for t in range(0, idx.size(), 3):
		vol += v[idx[t]].dot(v[idx[t + 1]].cross(v[idx[t + 2]])) / 6.0
	return vol
