class_name TakeValidator
extends RefCounted
## Structural validation of a take — the same rules as docs/take.schema.json, so an
## exported file can be checked in-app without a JSON-Schema library. Checks every sample,
## not a subset: a single malformed sample is enough to break a Maya import.
## Safe to call from a worker thread.

const MAX_ERRORS: int = 20

const META_NUMBERS: PackedStringArray = ["take", "tick_hz", "unit_scale", "handles", "in_index",
	"out_index", "wheelbase", "track_f", "track_r", "wheel_radius", "wheel_width", "susp_rest",
	"susp_max_travel"]
const WHEEL_NUMBERS: PackedStringArray = ["compression", "steer", "spin_cumulative", "slip_long", "slip_lat"]
const INPUT_NUMBERS: PackedStringArray = ["throttle", "brake", "steer"]


static func validate_file(path: String) -> PackedStringArray:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return PackedStringArray(["cannot read %s" % path])
	var json := JSON.new()
	if json.parse(text) != OK:
		return PackedStringArray(["JSON parse error line %d: %s" % [json.get_error_line(), json.get_error_message()]])
	return validate(json.data)


static func validate(root: Variant) -> PackedStringArray:
	var e := PackedStringArray()
	if not root is Dictionary:
		e.append("root: not an object")
		return e
	var r: Dictionary = root
	var meta: Variant = r.get("meta")
	if not meta is Dictionary:
		e.append("meta: missing")
		return e
	_check_meta(meta, e)
	var samples: Variant = r.get("samples")
	if not (samples is Array and (samples as Array).size() >= 2):
		e.append("samples: missing or fewer than 2")
		return e
	var arr: Array = samples
	var in_i := int(meta.get("in_index", -1))
	var out_i := int(meta.get("out_index", -1))
	if in_i < 0 or out_i >= arr.size() or in_i >= out_i:
		e.append("meta.in_index/out_index out of range (%d, %d, n=%d)" % [in_i, out_i, arr.size()])
	var prev_t := -INF
	for i in arr.size():
		if e.size() >= MAX_ERRORS:
			e.append("… stopping after %d errors" % MAX_ERRORS)
			break
		prev_t = _check_sample(arr[i], i, prev_t, e)
	return e


static func _check_meta(m: Dictionary, e: PackedStringArray) -> void:
	for k in META_NUMBERS:
		if not _is_num(m.get(k)):
			e.append("meta.%s: missing or not a number" % k)
	if m.get("up_axis") != "Y":
		e.append("meta.up_axis: expected \"Y\"")
	if m.get("forward") != "-Z":
		e.append("meta.forward: expected \"-Z\"")
	if _is_num(m.get("tick_hz")) and float(m["tick_hz"]) <= 0.0:
		e.append("meta.tick_hz: must be > 0")
	var body: Variant = m.get("body")
	if not body is Dictionary:
		e.append("meta.body: missing")
	else:
		if not _is_vec(body.get("extents"), 3):
			e.append("meta.body.extents: expected [x,y,z]")
		if not _is_vec(body.get("com_offset"), 3):
			e.append("meta.body.com_offset: expected [x,y,z]")
	var hp: Variant = m.get("hardpoints")
	if not (hp is Array and (hp as Array).size() == 4):
		e.append("meta.hardpoints: expected 4 entries (FL FR RL RR)")
	else:
		for i in 4:
			if not _is_vec(hp[i], 3):
				e.append("meta.hardpoints[%d]: expected [x,y,z]" % i)


static func _check_sample(s: Variant, i: int, prev_t: float, e: PackedStringArray) -> float:
	var where := "samples[%d]" % i
	if not s is Dictionary:
		e.append(where + ": not an object")
		return prev_t
	var sd: Dictionary = s
	var t: Variant = sd.get("t")
	if not _is_num(t):
		e.append(where + ".t: missing")
	elif float(t) <= prev_t:
		e.append(where + ".t: not strictly increasing")
	var ch: Variant = sd.get("chassis")
	if not ch is Dictionary:
		e.append(where + ".chassis: missing")
	else:
		if not _is_vec(ch.get("p"), 3):
			e.append(where + ".chassis.p")
		if not _is_vec(ch.get("q"), 4):
			e.append(where + ".chassis.q")
		else:
			var q: Array = ch["q"]
			var len2 := float(q[0]) ** 2 + float(q[1]) ** 2 + float(q[2]) ** 2 + float(q[3]) ** 2
			if absf(sqrt(len2) - 1.0) > 1e-3:
				e.append(where + ".chassis.q: not unit length")
	var wheels: Variant = sd.get("wheels")
	if not (wheels is Array and (wheels as Array).size() == 4):
		e.append(where + ".wheels: expected 4")
	else:
		for w in 4:
			var wd: Variant = wheels[w]
			if not wd is Dictionary:
				e.append("%s.wheels[%d]: not an object" % [where, w])
				continue
			for k in WHEEL_NUMBERS:
				if not _is_num(wd.get(k)):
					e.append("%s.wheels[%d].%s" % [where, w, k])
			if not wd.get("grounded") is bool:
				e.append("%s.wheels[%d].grounded: not bool" % [where, w])
			if not _is_vec(wd.get("contact_p"), 3):
				e.append("%s.wheels[%d].contact_p" % [where, w])
			if not _is_vec(wd.get("contact_n"), 3):
				e.append("%s.wheels[%d].contact_n" % [where, w])
	var inp: Variant = sd.get("input")
	if not inp is Dictionary:
		e.append(where + ".input: missing")
	else:
		for k in INPUT_NUMBERS:
			if not _is_num(inp.get(k)):
				e.append("%s.input.%s" % [where, k])
		if not inp.get("handbrake") is bool:
			e.append(where + ".input.handbrake: not bool")
	if not _is_vec(sd.get("vel"), 3):
		e.append(where + ".vel")
	if not _is_vec(sd.get("angvel"), 3):
		e.append(where + ".angvel")
	var cam: Variant = sd.get("camera")   # optional per spec
	if cam != null:
		if not (cam is Dictionary and _is_vec(cam.get("p"), 3) and _is_vec(cam.get("q"), 4)
				and _is_num(cam.get("fov"))):
			e.append(where + ".camera: malformed")
	return float(t) if _is_num(t) else prev_t


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


static func _is_vec(v: Variant, n: int) -> bool:
	if not (v is Array and (v as Array).size() == n):
		return false
	for x: Variant in v:
		if not _is_num(x):
			return false
	return true
