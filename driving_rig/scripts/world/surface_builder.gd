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


## A flat ribbon of road along a centreline: one quad per segment, plus optional side walls
## dropping to `ground` wherever the ribbon is raised (embankment fill, so it isn't floating).
## Returns the left and right edge points, for barriers and markings.
func ribbon(centre: PackedVector3Array, width: float, skirt_from: float = 0.35,
		ground: float = 0.0, skirt: bool = true) -> Array:
	var half := width * 0.5
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in centre.size():
		var fwd: Vector3 = (centre[mini(i + 1, centre.size() - 1)] - centre[maxi(i - 1, 0)])
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
		var side := fwd.cross(Vector3.UP).normalized()
		left.append(centre[i] - side * half)
		right.append(centre[i] + side * half)
	for i in centre.size() - 1:
		_quad4(left[i], right[i], right[i + 1], left[i + 1], Vector3.UP)
		if skirt and (centre[i].y > ground + skirt_from or centre[i + 1].y > ground + skirt_from):
			var lo_a := Vector3(left[i].x, ground, left[i].z)
			var lo_b := Vector3(left[i + 1].x, ground, left[i + 1].z)
			_quad4(lo_a, left[i], left[i + 1], lo_b, (left[i] - centre[i]).normalized())
			var ro_a := Vector3(right[i].x, ground, right[i].z)
			var ro_b := Vector3(right[i + 1].x, ground, right[i + 1].z)
			_quad4(right[i], ro_a, ro_b, right[i + 1], (right[i] - centre[i]).normalized())
	return [left, right]


## A barrier wall that follows a path: inner face, outer face and a cap, extruded along the
## points it is given. `side` is +1 for the right of the direction of travel, -1 for the left.
## Being one strip rather than a row of boxes, it bends with the road instead of sitting at
## whatever angle a box happens to have.
func wall_strip(path: PackedVector3Array, offset: float, height: float, thickness: float, side: float) -> void:
	if path.size() < 2:
		return
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	for i in path.size():
		var fwd: Vector3 = path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
		var right := fwd.cross(Vector3.UP).normalized() * side
		inner.append(path[i] + right * offset)
		outer.append(path[i] + right * (offset + thickness))
	var up := Vector3.UP * height
	for i in path.size() - 1:
		var n_in := (path[i] - inner[i])
		n_in.y = 0.0
		n_in = n_in.normalized()
		# inner face looks back at the road, outer face away from it, cap looks up
		if side > 0.0:
			_quad4(inner[i + 1], inner[i + 1] + up, inner[i] + up, inner[i], n_in)
			_quad4(outer[i], outer[i] + up, outer[i + 1] + up, outer[i + 1], -n_in)
			_quad4(inner[i] + up, inner[i + 1] + up, outer[i + 1] + up, outer[i] + up, Vector3.UP)
		else:
			_quad4(inner[i], inner[i] + up, inner[i + 1] + up, inner[i + 1], n_in)
			_quad4(outer[i + 1], outer[i + 1] + up, outer[i] + up, outer[i], -n_in)
			_quad4(inner[i + 1] + up, inner[i] + up, outer[i] + up, outer[i + 1] + up, Vector3.UP)


## Every triangle as a flat vertex list - what ConcavePolygonShape3D wants, so the collider is
## exactly the surface you can see.
func triangles() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in _indices:
		out.append(_verts[i])
	return out


func _quad4(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var base := _verts.size()
	for v: Vector3 in [a, b, c, d]:
		_push(v, n)
	_tri(base, base + 2, base + 1)
	_tri(base, base + 3, base + 2)


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
