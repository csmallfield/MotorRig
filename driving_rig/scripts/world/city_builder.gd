class_name CityBuilder
extends RefCounted
## A New York style grid at real dimensions (Manhattan: 264 ft x 900 ft blocks, 60 ft streets,
## 100 ft avenues, 15 ft sidewalks, 6 in curbs).
##
## Render meshes are merged per category - one for all buildings, one for all curbs and so on -
## so the whole city is a handful of draw calls and a handful of OBJs when you export the scene.
## Collision is separate and primitive (a box per building, a box per sidewalk slab, a cylinder
## per pole), which is both fast and exactly the same shape as the geometry you see.
##
## Axes: +X east, -Z north. Avenues run north-south (long blocks between them), streets east-west.

const LAYER_WORLD: int = 1
const FT: float = 0.3048

var _rng := RandomNumberGenerator.new()


## Builds into `parent` and returns {bounds: AABB, buildings: int, props: int}.
func build(parent: Node3D, p: WorldProfile, mats: Dictionary) -> Dictionary:
	_rng.seed = p.seed_value
	var bx: int = p.city_blocks_x
	var bz: int = p.city_blocks_z
	var bw: float = p.block_size_x       # east-west, avenue to avenue
	var bd: float = p.block_size_z       # north-south, street to street
	var av: float = p.avenue_width
	var st: float = p.street_width
	var walk: float = p.sidewalk_width
	var curb: float = p.curb_height

	var total_w := bx * bw + (bx + 1) * av
	var total_d := bz * bd + (bz + 1) * st
	var x0 := -total_w * 0.5
	var z0 := -total_d * 0.5

	var road := SurfaceBuilder.new()          # flat asphalt under everything
	var slab := SurfaceBuilder.new()          # raised sidewalk slabs (the curbs)
	var build_mesh := SurfaceBuilder.new()
	var prop_mesh := SurfaceBuilder.new()
	var paint := SurfaceBuilder.new()         # lane markings and crosswalks: visual only
	road.box(Vector3(0.0, -0.05, 0.0), Vector3(total_w, 0.1, total_d))

	var buildings := 0
	var props := 0
	for ix in bx:
		for iz in bz:
			var cx := x0 + av + ix * (bw + av) + bw * 0.5
			var cz := z0 + st + iz * (bd + st) + bd * 0.5
			var centre := Vector3(cx, 0.0, cz)
			# sidewalk slab: the block plus its sidewalk, raised by the curb height
			var slab_size := Vector3(bw + walk * 2.0, curb, bd + walk * 2.0)
			slab.box(centre + Vector3(0.0, curb * 0.5, 0.0), slab_size)
			_static_box(parent, "curb_%d_%d" % [ix, iz], centre + Vector3(0.0, curb * 0.5, 0.0), slab_size)
			buildings += _block_buildings(parent, build_mesh, centre, bw, bd, p, ix, iz)
			if p.build_test_props:
				props += _block_props(parent, prop_mesh, centre, bw, bd, walk, curb, ix, iz)
	if p.city_road_markings:
		_markings(paint, x0, z0, total_w, total_d, bx, bz, bw, bd, av, st)

	_add_mesh(parent, "RoadGeo", road, mats.get("road"))
	_add_mesh(parent, "SidewalkGeo", slab, mats.get("sidewalk"))
	_add_mesh(parent, "BuildingsGeo", build_mesh, mats.get("buildings"))
	if p.build_test_props:
		_add_mesh(parent, "StreetPropsGeo", prop_mesh, mats.get("props"))
	if p.city_road_markings:
		var mi := _add_mesh(parent, "RoadPaintGeo", paint, mats.get("paint"))
		if mi:
			mi.set_meta(&"drv_collides", false)     # paint: wheels drive straight over it
	# ground plane well beyond the city, so driving off the edge doesn't drop you into space
	var apron := SurfaceBuilder.new()
	apron.box(Vector3(0.0, -0.15, 0.0), Vector3(total_w + 600.0, 0.2, total_d + 600.0))
	_add_mesh(parent, "ApronGeo", apron, mats.get("road"))
	_static_box(parent, "apron", Vector3(0.0, -0.15, 0.0), Vector3(total_w + 600.0, 0.2, total_d + 600.0))
	return {"width": total_w, "depth": total_d, "buildings": buildings, "props": props}


## Buildings around the block edge, leaving the middle empty (backyards / air shafts).
func _block_buildings(parent: Node3D, mesh: SurfaceBuilder, centre: Vector3, bw: float, bd: float,
		p: WorldProfile, ix: int, iz: int) -> int:
	var depth: float = p.building_depth
	var count := 0
	for side in 4:
		var along := bw if side < 2 else bd
		var edge_z := side < 2
		var pos := -along * 0.5
		while pos < along * 0.5 - 6.0:
			var w := minf(_rng.randf_range(p.lot_width_min, p.lot_width_max), along * 0.5 - pos)
			var h := _rng.randf_range(p.building_height_min, p.building_height_max)
			if _rng.randf() < 0.06:
				h *= _rng.randf_range(1.6, 2.6)      # the occasional tower
			var mid := pos + w * 0.5
			var size: Vector3
			var at: Vector3
			if edge_z:
				var zside := -1.0 if side == 0 else 1.0
				size = Vector3(w, h, depth)
				at = centre + Vector3(mid, h * 0.5, zside * (bd * 0.5 - depth * 0.5))
			else:
				var xside := -1.0 if side == 2 else 1.0
				size = Vector3(depth, h, w)
				at = centre + Vector3(xside * (bw * 0.5 - depth * 0.5), h * 0.5, mid)
			mesh.box(at, size)
			_static_box(parent, "bld_%d_%d_%d_%d" % [ix, iz, side, count], at, size)
			pos += w
			count += 1
	return count


## Hydrants on the corners, light poles down the sidewalks.
func _block_props(parent: Node3D, mesh: SurfaceBuilder, centre: Vector3, bw: float, bd: float,
		walk: float, curb: float, ix: int, iz: int) -> int:
	var n := 0
	var hx := bw * 0.5 + walk * 0.5
	var hz := bd * 0.5 + walk * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := centre + Vector3(sx * hx, curb, sz * hz)
			mesh.cylinder(at + Vector3(0.0, 0.45, 0.0), 0.16, 0.9)
			mesh.box(at + Vector3(0.0, 0.62, 0.0), Vector3(0.52, 0.14, 0.2))   # side caps
			_static_cylinder(parent, "hydrant_%d_%d_%d_%d" % [ix, iz, int(sx), int(sz)],
					at + Vector3(0.0, 0.45, 0.0), 0.16, 0.9)
			n += 1
	var spacing := 28.0
	for sz2 in [-1.0, 1.0]:
		var k := -bw * 0.5 + spacing
		while k < bw * 0.5 - 4.0:
			var at := centre + Vector3(k, curb, sz2 * hz)
			_light_pole(parent, mesh, at, "pole_%d_%d_%d_%d" % [ix, iz, int(sz2), int(k)])
			n += 1
			k += spacing
	for sx2 in [-1.0, 1.0]:
		var k2 := -bd * 0.5 + spacing
		while k2 < bd * 0.5 - 4.0:
			var at := centre + Vector3(sx2 * hx, curb, k2)
			_light_pole(parent, mesh, at, "pole_%d_%d_%d_%d" % [ix, iz, int(sx2) + 10, int(k2)])
			n += 1
			k2 += spacing
	return n


func _light_pole(parent: Node3D, mesh: SurfaceBuilder, at: Vector3, name: String) -> void:
	var h := 9.0
	mesh.cylinder(at + Vector3(0.0, h * 0.5, 0.0), 0.11, h)
	mesh.box(at + Vector3(0.0, h - 0.15, 0.0), Vector3(1.8, 0.16, 0.16))
	_static_cylinder(parent, name, at + Vector3(0.0, h * 0.5, 0.0), 0.11, h)


func _markings(paint: SurfaceBuilder, x0: float, z0: float, total_w: float, total_d: float,
		bx: int, bz: int, bw: float, bd: float, av: float, st: float) -> void:
	var y := 0.012
	for ix in bx + 1:
		var cx := x0 + ix * (bw + av) + av * 0.5
		var zz := -total_d * 0.5
		while zz < total_d * 0.5:
			paint.box(Vector3(cx, y, zz + 1.5), Vector3(0.16, 0.02, 3.0))
			zz += 8.0
	for iz in bz + 1:
		var cz := z0 + iz * (bd + st) + st * 0.5
		var xx := -total_w * 0.5
		while xx < total_w * 0.5:
			paint.box(Vector3(xx + 1.5, y, cz), Vector3(3.0, 0.02, 0.16))
			xx += 8.0


# === helpers ===

func _add_mesh(parent: Node3D, name: String, sb: SurfaceBuilder, mat: Material) -> MeshInstance3D:
	var mesh := sb.commit()
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


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
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
