class_name Terrain
extends Node3D
## Drivable ground. Two sources, same contract: render mesh and collision are built from
## the *same* triangles, so wheels never float or sink relative to what you see — and,
## later, relative to the Maya set.
##
##   PROCEDURAL  seeded heightmap: flat pad at the origin, hills blending in beyond it
##   SCENE       any imported glTF/scene — every MeshInstance3D gets a trimesh collider
##               built from its own render mesh (no simplified proxy)

enum Source { PROCEDURAL, SCENE }

const LAYER_WORLD: int = 1

@export var source: Source = Source.PROCEDURAL
@export_group("Procedural")
@export var seed_value: int = 1234
@export var size: float = 800.0
@export var cell: float = 2.0
@export var flat_radius: float = 150.0
@export var blend_distance: float = 120.0
@export var amplitude: float = 14.0
@export var frequency: float = 0.006
@export_range(1, 6) var octaves: int = 3   ## more octaves = sharper crests = more airtime
@export var build_test_props: bool = true
@export_group("Scene")
@export var imported_scene: PackedScene
@export_group("Materials")
@export var material: Material
@export var props_material: Material
@export var marker_material: Material

## Written into every take's meta so a take always names the ground it was driven on.
var collision_source_id: String = ""

var _noise := FastNoiseLite.new()


func _ready() -> void:
	match source:
		Source.PROCEDURAL:
			_build_procedural()
			if build_test_props:
				_build_test_props()
		Source.SCENE:
			_build_from_scene()


# === PROCEDURAL ===

func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var w := smoothstep(flat_radius, flat_radius + blend_distance, d)
	if w <= 0.0:
		return 0.0
	return _noise.get_noise_2d(x, z) * amplitude * w


func _build_procedural() -> void:
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = octaves
	_noise.fractal_gain = 0.35

	var n := int(round(size / cell))
	var verts_per_side := n + 1
	var half := size * 0.5
	var heights := PackedFloat32Array()
	heights.resize(verts_per_side * verts_per_side)
	for iz in verts_per_side:
		for ix in verts_per_side:
			heights[iz * verts_per_side + ix] = height_at(-half + ix * cell, -half + iz * cell)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(heights.size())
	normals.resize(heights.size())
	for iz in verts_per_side:
		for ix in verts_per_side:
			var idx := iz * verts_per_side + ix
			verts[idx] = Vector3(-half + ix * cell, heights[idx], -half + iz * cell)
			var hl := heights[iz * verts_per_side + maxi(ix - 1, 0)]
			var hr := heights[iz * verts_per_side + mini(ix + 1, n)]
			var hd := heights[maxi(iz - 1, 0) * verts_per_side + ix]
			var hu := heights[mini(iz + 1, n) * verts_per_side + ix]
			normals[idx] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()

	# Godot front faces are clockwise seen from the front: (00, 10, 01), (10, 11, 01).
	var indices := PackedInt32Array()
	indices.resize(n * n * 6)
	var faces := PackedVector3Array()
	faces.resize(n * n * 6)
	var k := 0
	for iz in n:
		for ix in n:
			var i00 := iz * verts_per_side + ix
			var i10 := i00 + 1
			var i01 := i00 + verts_per_side
			var i11 := i01 + 1
			for idx in [i00, i10, i01, i10, i11, i01]:
				indices[k] = idx
				faces[k] = verts[idx]
				k += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "GroundGeo"
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	_add_static("Ground", shape, Transform3D.IDENTITY)

	collision_source_id = "proc_heightmap_seed%d_%dm_cell%.2f" % [seed_value, int(size), cell]


func _build_test_props() -> void:
	# Speed bumps on the pad (8 cm tall) — suspension and kerb-climb check.
	var bump_r := 0.45
	var bump_h := 0.08
	for j in 3:
		var m := CylinderMesh.new()
		m.top_radius = bump_r
		m.bottom_radius = bump_r
		m.height = 10.0
		# Collide against the render mesh itself, not an analytic cylinder: the exported OBJ
		# (and so the Maya set) is this mesh, and "same geometry" is the rule. An analytic
		# cylinder sat up to 0.6 mm off the 64-sided mesh the wheels are shown rolling on.
		var xf := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, bump_h - bump_r, -30.0 - j * 4.0))
		_add_prop("SpeedBump%d" % j, m, m.create_trimesh_shape(), xf)

	# Launch ramp off to the right — airtime / landing check. Rises toward −Z.
	var ramp := PrismMesh.new()
	ramp.left_to_right = 1.0
	ramp.size = Vector3(9.0, 1.4, 5.0)
	var ramp_xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(18.0, 0.7, -30.0))
	_add_prop("Ramp", ramp, ramp.create_convex_shape(), ramp_xf)

	# A mark to hit: painted cross on the pad, no collision.
	var mark_i := 0
	for dims in [Vector3(3.0, 0.002, 0.25), Vector3(0.25, 0.002, 3.0)]:
		var mk := BoxMesh.new()
		mk.size = dims
		var mi := MeshInstance3D.new()
		mi.name = "Mark%d" % mark_i
		mark_i += 1
		mi.mesh = mk
		mi.material_override = marker_material
		mi.position = Vector3(0.0, 0.001, -55.0)
		mi.set_meta(&"drv_collides", false)   # paint: no collider, flagged in scene exports
		add_child(mi)

	collision_source_id += "+props"


func _add_prop(prop_name: String, mesh: Mesh, shape: Shape3D, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = prop_name + "Geo"
	mi.mesh = mesh
	mi.material_override = props_material
	mi.transform = xf
	add_child(mi)
	_add_static(prop_name, shape, xf)


func _add_static(body_name: String, shape: Shape3D, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.transform = xf
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)


# === SCENE (imported set) ===

func _build_from_scene() -> void:
	if imported_scene == null:
		push_error("Terrain: source is SCENE but no imported_scene is set.")
		return
	var inst := imported_scene.instantiate()
	add_child(inst)
	var count := 0
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		_add_static("Col_%s" % mi.name, shape, global_transform.affine_inverse() * mi.global_transform)
		count += 1
	collision_source_id = "scene:%s" % imported_scene.resource_path
	print("Terrain: built %d trimesh colliders from %s" % [count, imported_scene.resource_path])
