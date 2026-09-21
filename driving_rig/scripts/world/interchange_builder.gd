class_name InterchangeBuilder
extends RefCounted
## A grade-separated highway interchange at real dimensions: a six-lane mainline, an arterial
## crossing it on a bridge, and six ramps (four diamond, two loops for the left turns).
##
## Dimensions are AASHTO-ish rather than invented:
##   lanes 12 ft (3.66 m), outside shoulder 10 ft, inside 4 ft -> 15.2 m per carriageway
##   median 12 m, so the bridge spans 42 m
##   vertical clearance 16 ft 6 in + 1.4 m of deck -> the crossing road sits 6.4 m up
##   loop radius >= 43 m (40 km/h design speed), ramp grades <= 6 %
##
## Ramps are Hermite curves between real endpoints and tangents; `measure()` reports each one's
## length, tightest radius and steepest grade so the numbers can be checked rather than assumed.
##
## Axes: +X east, -Z north. The mainline runs north-south, the arterial east-west over it.

const LANE: float = 3.66
const CARRIAGEWAY: float = 15.2        # 3 lanes + shoulders
const MEDIAN: float = 12.0
const CROSSING_W: float = 18.0         # 2 lanes each way + shoulders
const RAMP_W: float = 8.5              # one lane + shoulders
const DECK_Y: float = 6.4              # clearance + deck thickness
const MAIN_LEN: float = 1400.0
const CROSS_LEN: float = 520.0
const SPAN: float = 46.0               # half the bridge span either side of centre

var _rng := RandomNumberGenerator.new()
var ramps: Array[Dictionary] = []      # name + measurements, for the report and the tests


func build(parent: Node3D, p: WorldProfile, mats: Dictionary) -> Dictionary:
	_rng.seed = p.seed_value
	var cx := (MEDIAN + CARRIAGEWAY) * 0.5      # carriageway centre offset from the median line
	var road := SurfaceBuilder.new()
	var ramp_mesh := SurfaceBuilder.new()
	var paint := SurfaceBuilder.new()
	var props := SurfaceBuilder.new()

	# --- ground: grass, well past everything ---
	var grass := SurfaceBuilder.new()
	# the grass top sits 8 cm below the roads: at the same height the two z-fight everywhere
	grass.box(Vector3(0.0, -0.18, 0.0), Vector3(2600.0, 0.2, 1900.0))
	_static_box(parent, "ground", Vector3(0.0, -0.18, 0.0), Vector3(2600.0, 0.2, 1900.0))
	_add(parent, "GroundGeo", grass, mats.get("ground"))

	# --- mainline: two carriageways at grade ---
	for dir: float in [-1.0, 1.0]:
		var centre := _straight(Vector3(dir * cx, 0.0, -MAIN_LEN * 0.5), Vector3(dir * cx, 0.0, MAIN_LEN * 0.5), 60)
		var edges: Array = road.ribbon(centre, CARRIAGEWAY)
		_lane_lines(paint, centre, CARRIAGEWAY, 3)
	# median barrier, and the piers' foundations sit inside it
	props.box(Vector3(0.0, 0.45, 0.0), Vector3(0.6, 0.9, MAIN_LEN))
	_static_box(parent, "median_barrier", Vector3(0.0, 0.45, 0.0), Vector3(0.6, 0.9, MAIN_LEN))

	# --- crossing arterial: flat over the bridge, then down the embankment to grade ---
	# Three pieces: the two approaches sit on embankment fill, the bridge span does not - it is
	# a deck on piers, and anything driving underneath has to be able to get through.
	var cross := PackedVector3Array()
	for piece in [[-CROSS_LEN, -SPAN, true], [-SPAN, SPAN, false], [SPAN, CROSS_LEN, true]]:
		var seg := PackedVector3Array()
		var steps := 60
		for i in steps + 1:
			var x: float = lerpf(piece[0], piece[1], float(i) / steps)
			seg.append(Vector3(x, _crossing_y(x), 0.0))
		road.ribbon(seg, CROSSING_W, 0.35, 0.0, piece[2])
		for v in seg:
			cross.append(v)
	_lane_lines(paint, cross, CROSSING_W, 2)

	# --- bridge: deck edges, parapets and piers in the median ---
	for side: float in [-1.0, 1.0]:
		var y := DECK_Y - 0.45
		props.box(Vector3(0.0, y + 0.9, side * (CROSSING_W * 0.5 - 0.3)), Vector3(SPAN * 2.0, 0.9, 0.5))
		_static_box(parent, "parapet_%d" % int(side), Vector3(0.0, y + 0.9, side * (CROSSING_W * 0.5 - 0.3)),
				Vector3(SPAN * 2.0, 0.9, 0.5))
	# the deck itself is solid: something too tall for the 5 m clearance hits it
	# deck top 3 cm under the road surface laid on it (same reason), underside unchanged so the
	# clearance stays 5.00 m: the deck is 3 cm thinner, not 3 cm lower
	props.box(Vector3(0.0, DECK_Y - 0.715, 0.0), Vector3(SPAN * 2.0, 1.37, CROSSING_W))
	_static_box(parent, "bridge_deck", Vector3(0.0, DECK_Y - 0.715, 0.0), Vector3(SPAN * 2.0, 1.37, CROSSING_W))
	for pz: float in [-CROSSING_W * 0.25, CROSSING_W * 0.25]:
		props.box(Vector3(0.0, (DECK_Y - 1.4) * 0.5, pz), Vector3(2.0, DECK_Y - 1.4, 2.0))
		_static_box(parent, "pier_%d" % int(pz), Vector3(0.0, (DECK_Y - 1.4) * 0.5, pz), Vector3(2.0, DECK_Y - 1.4, 2.0))

	# --- ramps ---
	var rails := SurfaceBuilder.new()
	var paths: Array[Dictionary] = []
	for r in _ramp_specs(cx):
		paths.append({"name": r["name"], "pts": _hermite(r["p0"], r["t0"], r["p1"], r["t1"], 110)})
	# the two left-turn loops: a Hermite can't make 270 degrees without cusping, so these are
	# built as real geometry - a taper, a constant-radius arc, then a straight to the merge
	paths.append({"name": "SE loop ramp", "pts": _loop(1.0, cx)})
	paths.append({"name": "NW loop ramp", "pts": _loop(-1.0, cx)})
	for r in paths:
		var pts: PackedVector3Array = r["pts"]
		var m := measure(pts)
		m["name"] = r["name"]
		m["points"] = pts          # kept so the surface can be checked against the path
		ramps.append(m)
		ramp_mesh.ribbon(pts, RAMP_W)
		_ramp_barriers(rails, pts, RAMP_W)

	# --- furniture: gantry over the mainline, lighting down both carriageways ---
	if p.build_test_props:
		_gantry(parent, props, Vector3(0.0, 0.0, 300.0), cx)
		_gantry(parent, props, Vector3(0.0, 0.0, -300.0), cx)
		var z := -MAIN_LEN * 0.5 + 50.0
		while z < MAIN_LEN * 0.5 - 50.0:
			for dir2: float in [-1.0, 1.0]:
				_light(parent, props, Vector3(dir2 * (MEDIAN * 0.5 - 1.5), 0.0, z))
			z += 60.0

	_collide_mesh(parent, "road_collider", road)
	_collide_mesh(parent, "ramp_collider", ramp_mesh)
	_collide_mesh(parent, "rail_collider", rails, true)
	_add(parent, "RailGeo", rails, mats.get("structure"))
	_add(parent, "RoadGeo", road, mats.get("road"))
	_add(parent, "RampGeo", ramp_mesh, mats.get("road"))
	_add(parent, "StructureGeo", props, mats.get("structure"))
	var paint_mi := _add(parent, "RoadPaintGeo", paint, mats.get("paint"))
	if paint_mi:
		paint_mi.set_meta(&"drv_collides", false)
	return {"ramps": ramps, "deck_y": DECK_Y, "span": SPAN * 2.0,
		"width": CROSS_LEN * 2.0, "depth": MAIN_LEN}


## Length, tightest radius and steepest grade of a path - the numbers that say whether a ramp
## is drivable or a hairpin with a cliff in it.
static func measure(pts: PackedVector3Array) -> Dictionary:
	var length := 0.0
	var min_r := INF
	var max_grade := 0.0
	for i in pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var flat := Vector2(seg.x, seg.z).length()
		length += seg.length()
		if flat > 0.01:
			max_grade = maxf(max_grade, absf(seg.y) / flat)
	for i in range(1, pts.size() - 1):
		var a := Vector2(pts[i - 1].x, pts[i - 1].z)
		var b := Vector2(pts[i].x, pts[i].z)
		var c := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var bc := c - b
		var turn := absf(ab.angle_to(bc))
		if turn > 1e-5:
			min_r = minf(min_r, (ab.length() + bc.length()) * 0.5 / turn)
	return {"length": length, "min_radius": min_r, "max_grade": max_grade}


# === layout ===

func _ramp_specs(cx: float) -> Array[Dictionary]:
	var edge := cx + CARRIAGEWAY * 0.5 + RAMP_W * 0.5 + 0.02   # beside the carriageway, not on it
	var join := CROSSING_W * 0.5 + RAMP_W * 0.5             # and joins alongside the arterial
	var out: Array[Dictionary] = []
	# A partial cloverleaf: one ramp per quadrant, so no two ramps ever want the same ground.
	# Direct ramps take the north-east and south-west quadrants, loops the other two.
	# Northbound travels -Z on the +X carriageway; southbound +Z on -X.
	out.append({"name": "NE direct ramp", "p0": Vector3(edge, 0.0, 300.0), "t0": Vector3(0, 0, -420),
		"p1": Vector3(190.0, DECK_Y, join), "t1": Vector3(300, 0, 0)})
	out.append({"name": "SW direct ramp", "p0": Vector3(-edge, 0.0, -300.0), "t0": Vector3(0, 0, 420),
		"p1": Vector3(-190.0, DECK_Y, -join), "t1": Vector3(-300, 0, 0)})
	return out


## A cloverleaf loop on the `sign` side: leave the mainline heading along the carriageway,
## 270 degrees around a constant radius, out onto the arterial heading the other way. Climbs
## the whole length, so the grade stays gentle.
func _loop(sign: float, cx: float) -> PackedVector3Array:
	var radius := 52.0                                  # 40 km/h design speed needs 43 m
	var edge := (cx + CARRIAGEWAY * 0.5 + RAMP_W * 0.5 + 0.02) * sign
	var join := (CROSSING_W * 0.5 + RAMP_W * 0.5) * -sign
	var centre_z := join - radius * sign
	# the exit is 120 m upstream, so the ramp runs *with* the traffic into the arc rather than
	# doubling back on it
	var start_z := centre_z + 95.0 * sign
	var pts := PackedVector3Array()
	for i in 24:
		pts.append(Vector3(edge, 0.0, lerpf(start_z, centre_z, float(i) / 24.0)))
	var c := Vector3(edge + radius * sign, 0.0, centre_z)
	var steps := 90
	for i in steps + 1:
		var a := PI + TAU * 0.75 * float(i) / steps     # 180 -> 450 degrees
		pts.append(c + Vector3(cos(a) * radius * sign, 0.0, sin(a) * radius * sign))
	var tail := pts[pts.size() - 1]
	for i in range(1, 13):                              # straight out to the arterial
		pts.append(tail + Vector3(-30.0 * sign * float(i) / 12.0, 0.0, 0.0))
	# climb the whole way, easing in and out so there is no kink at either end
	var total := 0.0
	var dist := PackedFloat32Array([0.0])
	for i in pts.size() - 1:
		total += Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		dist.append(total)
	# stay at grade until the ramp is clear of the bridge, then climb: the first stretch runs
	# right under the arterial and needs the full 5 m of headroom
	for i in pts.size():
		var t := clampf((dist[i] / maxf(total, 1.0) - 0.38) / 0.62, 0.0, 1.0)
		pts[i] = Vector3(pts[i].x, DECK_Y * t * t * (3.0 - 2.0 * t), pts[i].z)
	return pts


func _crossing_y(x: float) -> float:
	var flat := 260.0                     # elevated across the whole interchange
	var down := 420.0                     # then 4 % down to grade
	var a := absf(x)
	if a <= flat:
		return DECK_Y
	if a >= down:
		return 0.0
	var t := (a - flat) / (down - flat)
	return DECK_Y * (1.0 - t * t * (3.0 - 2.0 * t))


static func _hermite(p0: Vector3, t0: Vector3, p1: Vector3, t1: Vector3, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		var t2 := t * t
		var t3 := t2 * t
		var p := (2.0 * t3 - 3.0 * t2 + 1.0) * p0 + (t3 - 2.0 * t2 + t) * t0 \
				+ (-2.0 * t3 + 3.0 * t2) * p1 + (t3 - t2) * t1
		# heights ease between the ends rather than following the curve's own overshoot, which
		# dipped the ramp a few mm below grade and into the ground
		var e := t2 * (3.0 - 2.0 * t)
		out.append(Vector3(p.x, lerpf(p0.y, p1.y, e), p.z))
	return out


static func _straight(a: Vector3, b: Vector3, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		out.append(a.lerp(b, float(i) / n))
	return out


# === furniture ===

## Barriers along both sides of a ramp wherever it is high enough to fall off - except the
## inside edge where the ramp runs alongside the arterial, which is where you merge. Built as
## one continuous wall per run, so it bends with the ramp.
func _ramp_barriers(rails: SurfaceBuilder, pts: PackedVector3Array, width: float) -> void:
	for side: float in [-1.0, 1.0]:
		var run := PackedVector3Array()
		for i in pts.size():
			var p := pts[i]
			var fwd: Vector3 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
			fwd.y = 0.0
			var edge := p + fwd.normalized().cross(Vector3.UP) * side * (width * 0.5 + 0.05)
			var merging := absf(edge.z) < CROSSING_W * 0.5 + 0.6 and p.y > DECK_Y - 1.0
			if p.y > 1.2 and not merging:
				run.append(p)
			else:
				if run.size() > 1:
					rails.wall_strip(run, width * 0.5 + 0.05, 0.9, 0.35, side)
				run = PackedVector3Array()
		if run.size() > 1:
			rails.wall_strip(run, width * 0.5 + 0.05, 0.9, 0.35, side)


func _gantry(parent: Node3D, sb: SurfaceBuilder, at: Vector3, cx: float) -> void:
	var span := cx * 2.0 + CARRIAGEWAY
	sb.box(at + Vector3(0.0, 7.4, 0.0), Vector3(span, 0.5, 0.5))
	sb.box(at + Vector3(0.0, 6.2, 0.0), Vector3(9.0, 2.0, 0.25))      # the sign panel itself
	for s: float in [-1.0, 1.0]:
		var pole := at + Vector3(s * span * 0.5, 3.7, 0.0)
		sb.cylinder(pole, 0.25, 7.4)
		_static_cylinder(parent, "gantry_%d_%d" % [int(at.z), int(s)], pole, 0.25, 7.4)


func _light(parent: Node3D, sb: SurfaceBuilder, at: Vector3) -> void:
	sb.cylinder(at + Vector3(0.0, 6.0, 0.0), 0.14, 12.0)
	sb.box(at + Vector3(0.0, 11.8, 0.0), Vector3(2.4, 0.2, 0.2))
	_static_cylinder(parent, "light_%d_%d" % [int(at.x), int(at.z)], at + Vector3(0.0, 6.0, 0.0), 0.14, 12.0)


func _lane_lines(paint: SurfaceBuilder, centre: PackedVector3Array, width: float, lanes: int) -> void:
	for l in range(1, lanes):
		var off := -width * 0.5 + 3.05 + l * LANE
		var i := 0
		while i < centre.size() - 1:
			var a := centre[i]
			var b := centre[mini(i + 1, centre.size() - 1)]
			var fwd := (b - a)
			fwd.y = 0.0
			if fwd.length() < 0.5:
				i += 1
				continue
			var side := fwd.normalized().cross(Vector3.UP) * off
			paint.box((a + b) * 0.5 + side + Vector3(0.0, 0.02, 0.0),
					Vector3(0.15, 0.02, fwd.length() * 0.45) if absf(fwd.x) < absf(fwd.z)
					else Vector3(fwd.length() * 0.45, 0.02, 0.15))
			i += 1


# === helpers ===

func _add(parent: Node3D, name: String, sb: SurfaceBuilder, mat: Material) -> MeshInstance3D:
	var mesh := sb.commit()
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## One trimesh collider for a whole road surface: exactly the geometry you can see, which is
## what the wheels' shape casts need on a curved, sloping ramp.
func _collide_mesh(parent: Node3D, name: String, sb: SurfaceBuilder, both_sides: bool = false) -> void:
	var tris := sb.triangles()
	if tris.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	shape.backface_collision = both_sides
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = CityBuilder.LAYER_WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


func _static_box(parent: Node3D, name: String, at: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_static_body(parent, name, shape, at)


func _static_cylinder(parent: Node3D, name: String, at: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_static_body(parent, name, shape, at)


func _static_body(parent: Node3D, name: String, shape: Shape3D, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = CityBuilder.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
