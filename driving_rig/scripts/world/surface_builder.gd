class_name SurfaceBuilder
extends RefCounted
## Accumulates boxes and cylinders into one ArrayMesh, so a whole city is a handful of draw
## calls and a handful of OBJ files instead of hundreds. Winding matches Godot's convention
## (clockwise seen from the front), which the scene exporter flips for Maya.

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _indices := PackedInt32Array()


func box(centre: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	# per face: origin corner, two edge vectors, normal
	var faces := [
		[Vector3(-h.x, -h.y, h.z), Vector3(size.x, 0, 0), Vector3(0, size.y, 0), Vector3(0, 0, 1)],    # +Z
		[Vector3(h.x, -h.y, -h.z), Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), Vector3(0, 0, -1)],  # -Z
		[Vector3(h.x, -h.y, h.z), Vector3(0, 0, -size.z), Vector3(0, size.y, 0), Vector3(1, 0, 0)],    # +X
		[Vector3(-h.x, -h.y, -h.z), Vector3(0, 0, size.z), Vector3(0, size.y, 0), Vector3(-1, 0, 0)],  # -X
		[Vector3(-h.x, h.y, h.z), Vector3(size.x, 0, 0), Vector3(0, 0, -size.z), Vector3(0, 1, 0)],    # +Y
		[Vector3(-h.x, -h.y, -h.z), Vector3(size.x, 0, 0), Vector3(0, 0, size.z), Vector3(0, -1, 0)],  # -Y
	]
	for f: Array in faces:
		_quad(centre + f[0], f[1], f[2], f[3])


func cylinder(centre: Vector3, radius: float, height: float, segments: int = 12) -> void:
	var half := height * 0.5
	var base := _verts.size()
	for i in segments:
		var a := TAU * i / segments
		var d := Vector3(cos(a), 0.0, sin(a))
		_push(centre + d * radius + Vector3(0.0, -half, 0.0), d)
		_push(centre + d * radius + Vector3(0.0, half, 0.0), d)
	for i in segments:
		var a0 := base + i * 2
		var a1 := base + ((i + 1) % segments) * 2
		_tri(a0, a1, a0 + 1)
		_tri(a1, a1 + 1, a0 + 1)
	var top := _verts.size()
	_push(centre + Vector3(0.0, half, 0.0), Vector3.UP)
	for i in segments:
		_push(centre + Vector3(cos(TAU * i / segments), 0.0, sin(TAU * i / segments)) * radius
				+ Vector3(0.0, half, 0.0), Vector3.UP)
	for i in segments:
		_tri(top, top + 1 + ((i + 1) % segments), top + 1 + i)


func commit() -> ArrayMesh:
	if _verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func vertex_count() -> int:
	return _verts.size()


func _quad(origin: Vector3, edge_a: Vector3, edge_b: Vector3, normal: Vector3) -> void:
	var base := _verts.size()
	_push(origin, normal)
	_push(origin + edge_a, normal)
	_push(origin + edge_a + edge_b, normal)
	_push(origin + edge_b, normal)
	_tri(base, base + 2, base + 1)
	_tri(base, base + 3, base + 2)


func _push(v: Vector3, n: Vector3) -> void:
	_verts.append(v)
	_normals.append(n)


func _tri(a: int, b: int, c: int) -> void:
	_indices.append(a)
	_indices.append(b)
	_indices.append(c)
