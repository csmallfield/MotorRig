class_name TakeFormat
extends RefCounted
## Everything that knows the take layout lives here, so recorder, replay, validator and
## tests can't drift apart:
##   • the flat float64 per-sample layout used in memory (recorder ring, replay buffer)
##   • the JSON line writer (one sample per line)
##   • the header reader (line 1 only) and the streaming sample loader
##   • the path thumbnail

const O_POS: int = 0        # 3
const O_QUAT: int = 3       # 4  xyzw
const O_VEL: int = 7        # 3
const O_ANGVEL: int = 10    # 3
const O_INPUT: int = 13     # 4  throttle, brake, steer, handbrake
const O_CAM: int = 17       # 8  p3, q4, fov
const O_WHEELS: int = 25
const W_STRIDE: int = 12    # compression, steer, spin, grounded, cp3, cn3, slip_long, slip_lat
const STRIDE: int = O_WHEELS + W_STRIDE * 4   # 73

const SAMPLES_OPEN: String = '"samples":['


# === WRITE ===

static func header_line(meta: Dictionary, summary: Dictionary) -> String:
	return '{"meta":%s,"summary":%s,\n%s\n' % [JSON.stringify(meta), JSON.stringify(summary), SAMPLES_OPEN]


static func sample_line(d: PackedFloat64Array, o: int, t: float) -> String:
	return '{"t":%.6f,"chassis":{"p":%s,"q":%s},"wheels":[%s],"input":{"throttle":%.4f,"brake":%.4f,"steer":%.4f,"handbrake":%s},"vel":%s,"angvel":%s,"camera":{"p":%s,"q":%s,"fov":%.3f}}' % [
		t,
		_v3(d, o + O_POS), _v4(d, o + O_QUAT),
		_wheels_json(d, o),
		d[o + O_INPUT], d[o + O_INPUT + 1], d[o + O_INPUT + 2],
		"true" if d[o + O_INPUT + 3] > 0.5 else "false",
		_v3(d, o + O_VEL), _v3(d, o + O_ANGVEL),
		_v3(d, o + O_CAM), _v4(d, o + O_CAM + 3), d[o + O_CAM + 7],
	]


static func _wheels_json(d: PackedFloat64Array, o: int) -> String:
	var parts := PackedStringArray()
	for w in 4:
		var k := o + O_WHEELS + w * W_STRIDE
		parts.append('{"compression":%.5f,"steer":%.6f,"spin_cumulative":%.5f,"grounded":%s,"contact_p":%s,"contact_n":%s,"slip_long":%.4f,"slip_lat":%.4f}' % [
			d[k], d[k + 1], d[k + 2], "true" if d[k + 3] > 0.5 else "false",
			_v3(d, k + 4), _v3(d, k + 7), d[k + 10], d[k + 11]])
	return ",".join(parts)


static func _v3(d: PackedFloat64Array, o: int) -> String:
	return "[%.5f,%.5f,%.5f]" % [d[o], d[o + 1], d[o + 2]]


static func _v4(d: PackedFloat64Array, o: int) -> String:
	return "[%.7f,%.7f,%.7f,%.7f]" % [d[o], d[o + 1], d[o + 2], d[o + 3]]


# === READ ===

## Reads line 1 only. Falls back to a full parse for files that were reformatted.
static func read_header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var line := f.get_line().strip_edges()
	f.close()
	if line.ends_with(","):
		var h: Variant = JSON.parse_string(line.left(-1) + "}")
		if h is Dictionary and (h as Dictionary).has("meta"):
			return h
	var full: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if full is Dictionary and (full as Dictionary).has("meta"):
		return {"meta": full["meta"], "summary": (full as Dictionary).get("summary", {})}
	return {}


## Returns {meta, summary, data: PackedFloat64Array, n} or {error}. Streams one sample per
## line when the file has the writer's layout (low peak memory); otherwise full parse.
## Safe to call from a worker thread.
static func load_take(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "cannot open %s (%d)" % [path, FileAccess.get_open_error()]}
	var first := f.get_line().strip_edges()
	var second := f.get_line().strip_edges()
	if first.ends_with(",") and second == SAMPLES_OPEN:
		var hdr: Variant = JSON.parse_string(first.left(-1) + "}")
		if hdr is Dictionary:
			var summary: Dictionary = (hdr as Dictionary).get("summary", {})
			var data := PackedFloat64Array()
			data.resize(maxi(int(summary.get("samples", 0)), 1) * STRIDE)
			var n := 0
			var json := JSON.new()
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line.begins_with("]"):
					break
				if line.is_empty():
					continue
				if line.ends_with(","):
					line = line.left(-1)
				if json.parse(line) != OK:
					f.close()
					return {"error": "line %d: %s" % [n + 3, json.get_error_message()]}
				if (n + 1) * STRIDE > data.size():
					data.resize((n + 2048) * STRIDE)
				var err := store_sample(data, n * STRIDE, json.data)
				if err != "":
					f.close()
					return {"error": "sample %d: %s" % [n, err]}
				n += 1
			f.close()
			data.resize(n * STRIDE)
			return {"meta": hdr["meta"], "summary": summary, "data": data, "n": n}
	f.close()

	var full: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (full is Dictionary and (full as Dictionary).has("meta") and (full as Dictionary).has("samples")):
		return {"error": "not a take file"}
	var samples: Array = full["samples"]
	var d := PackedFloat64Array()
	d.resize(samples.size() * STRIDE)
	for i in samples.size():
		var e := store_sample(d, i * STRIDE, samples[i])
		if e != "":
			return {"error": "sample %d: %s" % [i, e]}
	return {"meta": full["meta"], "summary": (full as Dictionary).get("summary", {}), "data": d, "n": samples.size()}


## Unpacks one sample dictionary into the flat layout. Returns "" or an error string.
static func store_sample(d: PackedFloat64Array, o: int, s: Variant) -> String:
	if not s is Dictionary:
		return "not an object"
	var sd: Dictionary = s
	var ch: Variant = sd.get("chassis")
	if not ch is Dictionary:
		return "chassis"
	if not _put(d, o + O_POS, ch.get("p"), 3):
		return "chassis.p"
	if not _put(d, o + O_QUAT, ch.get("q"), 4):
		return "chassis.q"
	if not _put(d, o + O_VEL, sd.get("vel"), 3):
		return "vel"
	if not _put(d, o + O_ANGVEL, sd.get("angvel"), 3):
		return "angvel"
	var inp: Variant = sd.get("input", {})
	if inp is Dictionary:
		d[o + O_INPUT] = float(inp.get("throttle", 0.0))
		d[o + O_INPUT + 1] = float(inp.get("brake", 0.0))
		d[o + O_INPUT + 2] = float(inp.get("steer", 0.0))
		d[o + O_INPUT + 3] = 1.0 if inp.get("handbrake", false) else 0.0
	var cam: Variant = sd.get("camera")
	if cam is Dictionary and _put(d, o + O_CAM, cam.get("p"), 3) and _put(d, o + O_CAM + 3, cam.get("q"), 4):
		d[o + O_CAM + 7] = float(cam.get("fov", 50.0))
	else:
		for k in 8:
			d[o + O_CAM + k] = 0.0
		d[o + O_CAM + 6] = 1.0
		d[o + O_CAM + 7] = 50.0
	var wheels: Variant = sd.get("wheels")
	if not (wheels is Array and (wheels as Array).size() == 4):
		return "wheels"
	for w in 4:
		var wd: Variant = wheels[w]
		if not wd is Dictionary:
			return "wheels[%d]" % w
		var k := o + O_WHEELS + w * W_STRIDE
		d[k] = float(wd.get("compression", 0.0))
		d[k + 1] = float(wd.get("steer", 0.0))
		d[k + 2] = float(wd.get("spin_cumulative", 0.0))
		d[k + 3] = 1.0 if wd.get("grounded", false) else 0.0
		if not _put(d, k + 4, wd.get("contact_p"), 3):
			return "wheels[%d].contact_p" % w
		if not _put(d, k + 7, wd.get("contact_n"), 3):
			return "wheels[%d].contact_n" % w
		d[k + 10] = float(wd.get("slip_long", 0.0))
		d[k + 11] = float(wd.get("slip_lat", 0.0))
	return ""


static func _put(d: PackedFloat64Array, o: int, v: Variant, n: int) -> bool:
	if not (v is Array and (v as Array).size() == n):
		return false
	for i in n:
		d[o + i] = float(v[i])
	return true


# === THUMBNAIL ===

## Top-down path (−Z up), 10 m grid, coloured by speed; handles grey, IN green, OUT red.
static func render_thumbnail(d: PackedFloat64Array, n: int, in_i: int, out_i: int, size: int = 160) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.11, 0.13))
	if n < 2:
		return img
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var peak := 1.0
	for i in n:
		var o := i * STRIDE
		var p := Vector2(d[o], d[o + 2])
		mn = mn.min(p)
		mx = mx.max(p)
		peak = maxf(peak, Vector3(d[o + 7], d[o + 8], d[o + 9]).length())
	var extent := maxf(maxf(mx.x - mn.x, mx.y - mn.y), 20.0)
	var scale := float(size - 16) / extent
	var c := (mn + mx) * 0.5
	var half := Vector2(size, size) * 0.5

	var grid_col := Color(0.16, 0.19, 0.22)
	var g0 := c - Vector2(extent, extent) * 0.6
	var gx := ceilf(g0.x / 10.0) * 10.0
	while gx < c.x + extent * 0.6:
		var px := int((gx - c.x) * scale + half.x)
		if px >= 0 and px < size:
			for y in size:
				img.set_pixel(px, y, grid_col)
		gx += 10.0
	var gz := ceilf(g0.y / 10.0) * 10.0
	while gz < c.y + extent * 0.6:
		var py := int((gz - c.y) * scale + half.y)
		if py >= 0 and py < size:
			for x in size:
				img.set_pixel(x, py, grid_col)
		gz += 10.0

	var step := maxi(1, n / 1500)
	var prev := _px(d, 0, c, scale, half)
	for i in range(step, n, step):
		var cur := _px(d, i, c, scale, half)
		var col := Color(0.42, 0.44, 0.48)
		if i >= in_i and i <= out_i:
			var o := i * STRIDE
			var sp := Vector3(d[o + 7], d[o + 8], d[o + 9]).length() / peak
			col = Color(0.2, 0.55, 1.0).lerp(Color(1.0, 0.35, 0.15), sp)
		_line(img, prev, cur, col)
		prev = cur
	_dot(img, _px(d, clampi(in_i, 0, n - 1), c, scale, half), Color(0.3, 1.0, 0.4))  # IN
	_dot(img, _px(d, clampi(out_i, 0, n - 1), c, scale, half), Color(1.0, 0.25, 0.25))
	return img


static func _px(d: PackedFloat64Array, i: int, c: Vector2, scale: float, half: Vector2) -> Vector2:
	var o := i * STRIDE
	return (Vector2(d[o], d[o + 2]) - c) * scale + half


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	var w := img.get_width()
	var h := img.get_height()
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		var x := int(p.x)
		var y := int(p.y)
		for dy in range(-1, 2):   # 3 px: survives downscaling to list-icon size
			for dx in range(-1, 2):
				if x + dx >= 0 and y + dy >= 0 and x + dx < w and y + dy < h:
					img.set_pixel(x + dx, y + dy, col)


static func _dot(img: Image, p: Vector2, col: Color) -> void:
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)
