class_name PlaygroundBuilder
extends RefCounted
## A vehicle playground: a big hill on the west side that any vehicle can build speed on, a
## tabletop jump and a mega kicker at its foot, and an obstacle course to the east.
##
## The hill is the design point. It drops 42 m over 210 m (20 %), which is steep enough that
## gravity does the work: coasting from the top, a 12 t bus reaches the bottom about as fast as
## a sedan (~95 km/h), so every vehicle gets to fly. The tabletop is forgiving on purpose - a
## short hop lands on the 30 m table, a long one on the 50 m down-slope behind it.
##
## Everything solid is built through SurfaceBuilder.solid()/face(), which orient every face
## away from the solid's centre, and collides against the same triangles you see.
##
## Axes: +X east, -Z north. The hill is west, the course is east, the hub is in the middle.

const HALF: float = 330.0
const CELL: float = 2.0
const HILL_TOP: float = 42.0
const HILL_Z: float = -100.0              # centre line of the hill lanes
const HILL_W: float = 70.0
const SUMMIT_X: float = -320.0            # flat summit to here
const SUMMIT_END: float = -290.0
const FOOT_X: float = -110.0              # the slope meets the ground here

var spawns: Array[Dictionary] = []        # {name, transform}
## The two jump lines: lip x, lip height, kicker angle, lane z and half-width. The landing
## hills are computed from these.
var jumps: Array[Dictionary] = [
	# Calibrated, not the ramp's nominal angle. Coasting vehicles come back down to table height
	# ~30 m out, which back-solves to an *effective* launch of 9 deg off the 13 deg tabletop kicker
	# and 11.5 off the 15 deg mega one (the suspension and pitch in the air cost a few degrees).
	# The table ends just before that, so they land on the slope; faster, further-flying vehicles
	# land further down it, where it is steeper - which is what their steeper arrival needs.
	{"name": "tabletop", "lip_x": -75.0, "lip_y": 3.5, "launch_deg": 9.0, "design_kmh": 108.0,
		"z": HILL_Z + 16.0, "half": 8.0, "pit": 8.0},
	# the mega lane is matched to the big-air vehicles instead: the monster truck comes back to
	# table height ~36 m out (effective launch ~11 deg at 110 km/h), so the table ends at ~33 m
	{"name": "mega", "lip_x": -78.0, "lip_y": 6.0, "launch_deg": 11.2, "design_kmh": 110.0,
		"z": HILL_Z - 18.0, "half": 7.0, "pit": 10.0, "max_slope": 22.0},
]
var _landing_profiles: Array[PackedFloat32Array] = []
const LAND_STEP: float = 0.5
const LAND_LEN: float = 160.0
var features: Dictionary = {}             # name -> Vector3, for tests and the report

var _rng := RandomNumberGenerator.new()


func build(parent: Node3D, p: WorldProfile, mats: Dictionary) -> Dictionary:
	_rng.seed = p.seed_value
	var ground := SurfaceBuilder.new()
	var solids := SurfaceBuilder.new()
	var rocks := SurfaceBuilder.new()
	var marks := SurfaceBuilder.new()

	# --- the land: hill, whoops, moguls, the bowl, an off-camber strip ---
	var n := int(HALF * 2.0 / CELL)
	ground.heightfield(-HALF, -HALF, n, n, CELL, _height)
	# a skirt of flat ground beyond the edge, so driving off the map isn't driving into space
	ground.face(PackedVector3Array([Vector3(-HALF - 400, -0.02, -HALF - 400), Vector3(HALF + 400, -0.02, -HALF - 400),
		Vector3(HALF + 400, -0.02, -HALF), Vector3(-HALF - 400, -0.02, -HALF)]), Vector3(0, -10, -HALF - 200))
	ground.face(PackedVector3Array([Vector3(-HALF - 400, -0.02, HALF), Vector3(HALF + 400, -0.02, HALF),
		Vector3(HALF + 400, -0.02, HALF + 400), Vector3(-HALF - 400, -0.02, HALF + 400)]), Vector3(0, -10, HALF + 200))
	ground.face(PackedVector3Array([Vector3(-HALF - 400, -0.02, -HALF), Vector3(-HALF, -0.02, -HALF),
		Vector3(-HALF, -0.02, HALF), Vector3(-HALF - 400, -0.02, HALF)]), Vector3(-HALF - 200, -10, 0))
	ground.face(PackedVector3Array([Vector3(HALF, -0.02, -HALF), Vector3(HALF + 400, -0.02, -HALF),
		Vector3(HALF + 400, -0.02, HALF), Vector3(HALF, -0.02, HALF)]), Vector3(HALF + 200, -10, 0))

	# --- the jump line at the foot of the hill (south lane): kicker, table, landing ---
	var lane_a := HILL_Z + 16.0
	var east := Basis(Vector3.UP, -PI * 0.5)           # local -Z (the way up a wedge) -> +X
	var west := Basis(Vector3.UP, PI * 0.5)
	# The kicker is a solid; the table and landing behind it are part of the ground (see
	# _landing_hill), shaped like a ski-jump landing so it follows the flight path.
	_ramp(solids, east, Vector3(-82.5, 0.0, lane_a), 16.0, 15.0, 3.5)
	features["tabletop"] = Vector3(-75.0, 3.5, lane_a)
	# --- and the mega jump (north lane): a 6 m kicker, a 40 m table and an 80 m landing slope.
	# Into flat ground a 10 m drop bottoms out anything; onto a slope it's a landing.
	var lane_b := HILL_Z - 18.0
	_ramp(solids, east, Vector3(-89.0, 0.0, lane_b), 14.0, 22.0, 6.0)
	features["mega_kicker"] = Vector3(-80.0, 5.5, lane_b)

	# --- small kicker park: five sizes in a row ---
	var kx := 70.0
	for h: float in [0.5, 1.0, 1.5, 2.0, 2.8]:
		_ramp(solids, east, Vector3(kx, 0.0, -130.0), 6.0, h * 5.5, h)
		kx += h * 5.5 + 24.0
	features["kickers"] = Vector3(70.0, 0.0, -130.0)

	# --- step-up: a ramp onto a 1.5 m ledge and a drop off the far side ---
	_ramp(solids, east, Vector3(235.0, 0.0, -130.0), 10.0, 9.0, 1.5)
	solids.box_xf(Transform3D(Basis.IDENTITY, Vector3(252.0, 0.75, -130.0)), Vector3(25.0, 1.5, 10.0))
	features["step_up"] = Vector3(252.0, 1.5, -130.0)

	# --- stairs: eight 25 cm steps up, eight down ---
	for i in 8:
		var w := 4.0 * (8 - i)
		solids.box_xf(Transform3D(Basis.IDENTITY, Vector3(250.0, 0.125 + i * 0.25, -40.0)), Vector3(w, 0.25, 10.0))
	features["stairs"] = Vector3(250.0, 2.0, -40.0)

	# --- log crossing: logs of different sizes across a lane ---
	var lx := 70.0
	for r: float in [0.15, 0.25, 0.35, 0.25, 0.45, 0.2, 0.3]:
		solids.cylinder_xf(Transform3D(Basis(Vector3.UP, PI * 0.5 + _rng.randf_range(-0.2, 0.2)),
				Vector3(lx, r - 0.05, -40.0)), r, 12.0, 12)
		lx += _rng.randf_range(9.0, 16.0)
	features["logs"] = Vector3(70.0, 0.0, -40.0)

	# --- rock garden: tumbled blocks you have to pick a line through ---
	for i in 90:
		var at := Vector3(_rng.randf_range(215.0, 305.0), 0.0, _rng.randf_range(60.0, 170.0))
		var s := Vector3(_rng.randf_range(0.6, 2.2), _rng.randf_range(0.3, 1.1), _rng.randf_range(0.6, 2.2))
		var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).rotated(
				Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(-0.25, 0.25))
		rocks.box_xf(Transform3D(b, at + Vector3.UP * s.y * 0.35), s)
	features["rocks"] = Vector3(260.0, 0.0, 115.0)

	# --- tunnel: 7 m wide, 4.5 m tall, 40 m long ---
	for side: float in [-1.0, 1.0]:
		solids.box_xf(Transform3D(Basis.IDENTITY, Vector3(40.0, 2.25, 230.0 + side * 3.9)), Vector3(40.0, 4.5, 0.8))
	solids.box_xf(Transform3D(Basis.IDENTITY, Vector3(40.0, 4.9, 230.0)), Vector3(40.0, 0.8, 8.6))
	features["tunnel"] = Vector3(40.0, 0.0, 230.0)

	# --- slalom poles and a line of markers across the hub ---
	var px := 60.0
	var flip := 1.0
	while px < 210.0:
		solids.cylinder_xf(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(px, 1.0, 5.0 * flip)), 0.18, 2.0, 10)
		px += 18.0
		flip = -flip
	features["slalom"] = Vector3(60.0, 0.0, 0.0)
	for mz: float in [-20.0, 0.0, 20.0]:
		marks.face(PackedVector3Array([Vector3(-4, 0.03, mz - 0.2), Vector3(4, 0.03, mz - 0.2),
			Vector3(4, 0.03, mz + 0.2), Vector3(-4, 0.03, mz + 0.2)]), Vector3(0, -5, mz))

	_collide(parent, "ground_collider", ground)
	_collide(parent, "solids_collider", solids)
	_collide(parent, "rocks_collider", rocks)
	_add(parent, "GroundGeo", ground, mats.get("ground"))
	_add(parent, "RampsGeo", solids, mats.get("structure"))
	_add(parent, "RocksGeo", rocks, mats.get("rocks"))
	var m := _add(parent, "MarkingsGeo", marks, mats.get("paint"))
	if m:
		m.set_meta(&"drv_collides", false)

	# --- a wall of crates to drive through (these move) ---
	if p.build_test_props:
		var crates := 0
		for row in 4:
			for col in 6 - row:
				var c := _crate(mats.get("crate"), 1.2)
				c.position = Vector3(30.0, 0.62 + row * 1.22, 100.0 + (col - (5 - row) * 0.5) * 1.24)
				parent.add_child(c)
				crates += 1
		features["crates"] = Vector3(30.0, 0.0, 100.0)

	# --- spawn points: D-pad up / F2 cycles through them ---
	_spawn("Hub", Vector3(0.0, 0.0, 0.0), 0.0)
	_spawn("Hill top: tabletop (cars)", Vector3((SUMMIT_X + SUMMIT_END) * 0.5, 0.0, lane_a), -PI * 0.5)
	_spawn("Hill top: mega jump (monster truck, buggy)", Vector3((SUMMIT_X + SUMMIT_END) * 0.5, 0.0, lane_b), -PI * 0.5)
	_spawn("Obstacle course", Vector3(45.0, 0.0, -40.0), -PI * 0.5)
	_spawn("Whoops and moguls", Vector3(45.0, 0.0, 50.0), -PI * 0.5)
	_spawn("Bowl", Vector3(180.0, 0.0, -180.0), -PI * 0.5)     # the floor, not the rim
	return {"spawns": spawns.size(), "features": features.size()}


## The land, as one height function.
func _height(x: float, z: float) -> float:
	var y := 0.0
	# the hill: a flat summit, a long 20 % run down to the east, falling away to the sides
	var t := clampf((x - SUMMIT_END) / (FOOT_X - SUMMIT_END), 0.0, 1.0)
	var along := HILL_TOP * (1.0 - _eased_ramp(t, 0.08))
	var across := absf(z - HILL_Z) - HILL_W * 0.5
	var side := 1.0 - _smooth(0.0, 55.0, across)
	y = maxf(y, along * side)
	# landing hills behind the kickers - added after the hill, not max'd with it: their pits go
	# below ground, and max(pit, 0) would fill them back in
	for j in jumps.size():
		y += _landing_at(j, x, z)
	# whoops: a lane of evenly spaced rollers, the classic suspension test
	if x > 60.0 and x < 200.0 and absf(z - 50.0) < 9.0:
		var roll := 0.5 + 0.5 * cos((x - 60.0) * TAU / 8.0)
		y += 0.65 * roll * (1.0 - _smooth(6.0, 9.0, absf(z - 50.0)))
	# moguls: a field of bumps offset row to row
	if x > 60.0 and x < 200.0 and z > 80.0 and z < 200.0:
		var mo := maxf(0.0, sin((x - 60.0) * TAU / 11.0) * sin((z - 80.0) * TAU / 11.0))
		var edge := _smooth(0.0, 6.0, minf(minf(x - 60.0, 200.0 - x), minf(z - 80.0, 200.0 - z)))
		y += 1.1 * mo * edge
	# the bowl: a banked ring to ride round, walls rising to 5 m
	var r := Vector2(x - 180.0, z + 180.0).length()
	if r < 70.0:
		y += 5.0 * _smooth(28.0, 44.0, r) * (1.0 - _smooth(50.0, 64.0, r))
	# off-camber strip: tilted 14 degrees sideways, for rolling over (or not)
	if x > 60.0 and x < 200.0 and z > -95.0 and z < -70.0:
		var tilt := (z + 95.0) * tan(deg_to_rad(14.0))
		var ramp_in := _smooth(60.0, 70.0, x) * (1.0 - _smooth(190.0, 200.0, x))
		y += tilt * ramp_in
	return y


## A ramp standing on the ground, sunk 5 cm with its lip height unchanged: a wedge set exactly
## on y = 0 has a paper-thin back edge lying in the ground's own plane, which flickers.
func _ramp(sb: SurfaceBuilder, b: Basis, at: Vector3, width: float, length: float, height: float) -> void:
	sb.wedge(Transform3D(b, at + Vector3.DOWN * 0.05), width, length, height + 0.05)


## Height of jump j's landing hill at (x, z). The profile is built once per jump.
func _landing_at(j: int, x: float, z: float) -> float:
	var jp: Dictionary = jumps[j]
	var u := x - float(jp["lip_x"])
	if u < 0.0 or u > LAND_LEN:
		return 0.0
	if _landing_profiles.size() <= j:
		for k in jumps.size():
			_landing_profiles.append(_landing_profile(jumps[k]))
	var prof: PackedFloat32Array = _landing_profiles[j]
	var i := int(u / LAND_STEP)
	var f := u / LAND_STEP - i
	var h := lerpf(prof[mini(i, prof.size() - 1)], prof[mini(i + 1, prof.size() - 1)], f)
	var across := absf(z - float(jp["z"])) - float(jp["half"])
	return h * (1.0 - _smooth(0.0, 10.0, across))


## A ski-jump landing, from the kicker's own launch. Follow the flight path for the design speed
## (just under it), so the hill steepens with distance the same way a falling car's path does:
## a slow jump lands early where it's gentle, a fast one further down where it's steep, and both
## arrive nearly parallel to the surface. Then round the bottom off into a long run-out.
func _landing_profile(jp: Dictionary) -> PackedFloat32Array:
	var v := float(jp["design_kmh"]) / 3.6
	var ang := deg_to_rad(float(jp["launch_deg"]))
	var a := tan(ang)
	var vx := v * cos(ang)
	var b := 9.81 / (2.0 * vx * vx)
	var lip_y: float = jp["lip_y"]
	var n := int(LAND_LEN / LAND_STEP) + 1
	var raw := PackedFloat32Array()
	raw.resize(n)
	var max_drop := tan(deg_to_rad(float(jp.get("max_slope", 24.0)))) * LAND_STEP
	# The hill carries on below ground level into a landing pit, so it keeps following the
	# flight path far enough to catch faster jumps too - a 3.5 m table alone runs out of height
	# at 50 m. Then a long run-out climbs back to the surface.
	var floor_y: float = -float(jp["pit"])
	var prev := lip_y
	var bottom_u := -1.0
	for i in n:
		var u := i * LAND_STEP
		var y: float
		if bottom_u < 0.0:
			var flight := lip_y + a * u - b * u * u - 0.6       # 60 cm under the design path
			y = minf(lip_y, flight)                             # flat table until the path comes down
			y = maxf(y, prev - max_drop)
			if y <= floor_y:
				y = floor_y
				bottom_u = u
		else:
			var t := clampf((u - bottom_u) / 70.0, 0.0, 1.0)    # 70 m run-out back up (~7 %)
			y = floor_y * (1.0 - _eased_ramp(t, 0.3))
		raw[i] = y
		prev = y
	# smooth over ~10 m so the crest and the foot are curves, not corners
	var out := PackedFloat32Array()
	out.resize(n)
	var r := int(5.0 / LAND_STEP)
	for i in n:
		var s := 0.0
		var w := 0.0
		for k in range(-r, r + 1):
			var kk := clampi(i + k, 0, n - 1)
			var wt := 1.0 - absf(k) / float(r + 1)
			s += raw[kk] * wt
			w += wt
		out[i] = s / w
	# the table has to stay flush with the lip for the first metres
	for i in int(3.0 / LAND_STEP):
		out[i] = lip_y
	return out


## 0 -> 1 at a constant rate in the middle, easing in and out over `e` at each end: continuous
## in height *and* slope, so neither the crest nor the foot of the hill kicks the car into the air.
static func _eased_ramp(t: float, e: float) -> float:
	var k := 1.0 / (2.0 * e * (1.0 - e))
	if t < e:
		return t * t * k
	if t > 1.0 - e:
		return 1.0 - (1.0 - t) * (1.0 - t) * k
	return (t - e * 0.5) / (1.0 - e)


static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _spawn(name: String, at: Vector3, yaw: float) -> void:
	var y := _height(at.x, at.z)
	spawns.append({"name": name, "transform": Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.z))})


func _crate(mat: Material, size: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "crate"
	body.mass = 45.0
	body.collision_layer = CityBuilder.LAYER_WORLD
	body.collision_mask = CityBuilder.LAYER_WORLD | 2
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mi.mesh = mesh
	mi.material_override = mat
	mi.set_meta(&"drv_dynamic", true)
	body.add_child(mi)
	return body


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


func _collide(parent: Node3D, name: String, sb: SurfaceBuilder) -> void:
	var tris := sb.triangles()
	if tris.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = CityBuilder.LAYER_WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
