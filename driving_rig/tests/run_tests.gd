extends SceneTree
## Headless regression suite — run after retuning anything:
##
##   godot --headless --path . --fixed-fps 240 --script res://tests/run_tests.gd
##   godot --headless --path . --fixed-fps 240 --script res://tests/run_tests.gd -- corner_100 flick
##
## (Windows: use the *console* exe, e.g. Godot_v4.7-stable_win64_console.exe.)
## Each test instantiates a fresh main scene. Takes go to user://test_takes, never your takes.
## Exit code = number of failures.

const TAKES_DIR: String = "user://test_takes"
const ALL: Array[String] = ["settle", "accel_brake", "corner_60", "corner_100", "corner_140",
	"flick", "catch", "bumps", "ramp", "hills", "record_replay", "format_compat", "validator",
	"export", "browser"]
const FLAT: Array[String] = ["accel_brake", "corner_60", "corner_100", "corner_140", "flick", "catch"]

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
		if a in ALL:
			queue.append(a)
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
	if call("_t_" + cur) or t > 240 * 60:
		if t > 240 * 60:
			_result(false, "timeout")
		main.queue_free()
		main = null
		cooldown = 3
	return false


func _start(test_name: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	if test_name in FLAT:
		main.get_node("Terrain").flat_radius = 5000.0
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
	print("%s  %-14s %s" % ["PASS" if ok else "FAIL", cur, detail])


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

func air_count() -> int:
	var a := 0
	for i in 4:
		a += 1 - car.wheel_grounded[i]
	return a

func _predicted_ride_y() -> float:
	var comp := car.mass * DrivingCar.GRAVITY * 0.25 / car.spring_rate_front
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
		var ok: bool = player.n == expected and compared == player.n and max_pos < 1e-4 and max_rot < 1e-3 \
				and int(hdr["summary"]["samples"]) == expected and png_ok and player.format_version == 2 \
				and str(st["saved"]).ends_with(".json.gz") and kb < 600.0 and prec[0] <= 1.0
		_result(ok, "v%d %s, %.0f KB for 10 s · %d samples (expect %d) · every channel within its stated precision of the raw data (worst: %s at %.2f×) · ghost vs live: wheel pos err %.4f mm, rot err %.6f · thumbnail %s" % [
			player.format_version, str(st["saved"]).get_file(), kb, player.n, expected, prec[1], prec[0],
			max_pos * 1000.0, max_rot, png_ok])
		return true
	return false


func _log_live() -> void:
	var xs: Array = []
	for wn in DrivingCar.WHEEL_NAMES:
		xs.append((car.get_node("wheel_%s_steer/wheel_%s_susp/wheel_%s_spin/wheel_%s_geo" % [wn, wn, wn, wn]) as Node3D).global_transform)
	st["live"][rec._tick - 1] = xs


## Largest |a − b| over all channels, as a multiple of each channel's rounding step
## (0.5 · 10^-decimals; 0/1 flags use 0.5). ≤ 1.0 means every value honours its precision.
func _worst_channel_error(a: PackedFloat64Array, n: int, b: Callable) -> Array:
	var worst := 0.0
	var worst_name := "-"
	for ch in TakeFormat.CHANNELS:
		var tol := 0.5 if ch.get("flag", false) else 0.5 * pow(10.0, -int(ch["dec"])) * 1.0001
		for w in (4 if ch.get("wheel", false) else 1):
			var base: int = (TakeFormat.O_WHEELS + w * TakeFormat.W_STRIDE if ch.get("wheel", false) else 0) + int(ch["off"])
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
	var cmp := _worst_channel_error(d, n, func(i: int, o: int) -> float: return d1[i * TakeFormat.STRIDE + o])
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
