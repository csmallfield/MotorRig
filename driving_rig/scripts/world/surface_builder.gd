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


## One flat convex face, oriented so its normal points away from `inside` - the winding follows
## from that rather than from the order the corners happen to be listed in. Every solid below is
## built from these, so none of them can come out inside-out.
func face(pts: PackedVector3Array, inside: Vector3) -> void:
	var n := (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if n.length_squared() < 1e-12 and pts.size() > 3:
		n = (pts[2] - pts[0]).cross(pts[3] - pts[0])
	if n.length_squared() < 1e-12:
		return                                   # degenerate: nothing to draw
	n = n.normalized()
	var centre := Vector3.ZERO
	for p in pts:
		centre += p
	centre /= pts.size()
	if n.dot(centre - inside) < 0.0:
		n = -n
	for i in range(1, pts.size() - 1):
		var a := pts[0]
		var b := pts[i]
		var c := pts[i + 1]
		# Godot's front faces wind so that (b - a) x (c - a) points away from the normal
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		var base := _verts.size()
		_push(a, n)
		_push(b, n)
		_push(c, n)
		_tri(base, base + 1, base + 2)


## A closed convex solid from its faces (each a list of corners); faces are oriented outward
## from the solid's own centre.
func solid(faces: Array) -> void:
	var centre := Vector3.ZERO
	var n := 0
	for f: PackedVector3Array in faces:
		for p in f:
			centre += p
			n += 1
	centre /= maxf(n, 1)
	for f: PackedVector3Array in faces:
		face(f, centre)


## A box of `size` placed by `xf` (rotation and all - box() above is axis-aligned only).
func box_xf(xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var c := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var v := [c.call(-1, -1, -1), c.call(1, -1, -1), c.call(1, 1, -1), c.call(-1, 1, -1),
		c.call(-1, -1, 1), c.call(1, -1, 1), c.call(1, 1, 1), c.call(-1, 1, 1)]
	solid([
		PackedVector3Array([v[0], v[1], v[2], v[3]]), PackedVector3Array([v[4], v[5], v[6], v[7]]),
		PackedVector3Array([v[0], v[1], v[5], v[4]]), PackedVector3Array([v[3], v[2], v[6], v[7]]),
		PackedVector3Array([v[0], v[3], v[7], v[4]]), PackedVector3Array([v[1], v[2], v[6], v[5]]),
	])


## A ramp: `length` long along local -Z, rising from 0 at the back edge (+Z) to `height` at the
## lip (-Z), `width` wide. Drive toward -Z to go up it and off the end.
func wedge(xf: Transform3D, width: float, length: float, height: float) -> void:
	var w := width * 0.5
	var l := length * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var bl: Vector3 = p.call(-w, 0.0, l)
	var br: Vector3 = p.call(w, 0.0, l)
	var fl: Vector3 = p.call(-w, 0.0, -l)
	var fr: Vector3 = p.call(w, 0.0, -l)
	var tl: Vector3 = p.call(-w, height, -l)
	var tr: Vector3 = p.call(w, height, -l)
	solid([
		PackedVector3Array([bl, br, tr, tl]),          # the slope
		PackedVector3Array([fl, fr, tr, tl]),          # the drop at the lip
		PackedVector3Array([bl, br, fr, fl]),          # underside
		PackedVector3Array([bl, fl, tl]),              # sides
		PackedVector3Array([br, fr, tr]),
	])


## A cylinder lying along local X (logs, pipes), placed by `xf`.
func cylinder_xf(xf: Transform3D, radius: float, length: float, segments: int = 14) -> void:
	var ring_a := PackedVector3Array()
	var ring_b := PackedVector3Array()
	for i in segments:
		var a := TAU * i / segments
		var o := Vector3(0.0, cos(a) * radius, sin(a) * radius)
		ring_a.append(xf * (o + Vector3(-length * 0.5, 0, 0)))
		ring_b.append(xf * (o + Vector3(length * 0.5, 0, 0)))
	var faces := [ring_a, ring_b]
	for i in segments:
		var j := (i + 1) % segments
		faces.append(PackedVector3Array([ring_a[i], ring_a[j], ring_b[j], ring_b[i]]))
	solid(faces)


## Terrain from a height function: nx x nz cells of `cell` metres from (x0, z0). Each cell is a
## flat quad split in two, each triangle facing up.
func heightfield(x0: float, z0: float, nx: int, nz: int, cell: float, height: Callable) -> void:
	var ys := PackedFloat32Array()
	ys.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			ys[j * (nx + 1) + i] = height.call(x0 + i * cell, z0 + j * cell)
	# one shared vertex per grid point with a smooth normal (central differences), rather than
	# three per triangle: a 330 x 330 field is 110 k vertices instead of 650 k, and it shades
	# like ground instead of like facets
	var w := nx + 1
	var base := _verts.size()
	for j in nz + 1:
		for i in nx + 1:
			var y := ys[j * w + i]
			var dx := ys[j * w + mini(i + 1, nx)] - ys[j * w + maxi(i - 1, 0)]
			var dz := ys[mini(j + 1, nz) * w + i] - ys[maxi(j - 1, 0) * w + i]
			var span_x := cell * float(mini(i + 1, nx) - maxi(i - 1, 0))
			var span_z := cell * float(mini(j + 1, nz) - maxi(j - 1, 0))
			_push(Vector3(x0 + i * cell, y, z0 + j * cell), Vector3(-dx / span_x, 1.0, -dz / span_z).normalized())
	# (a, b, c) and (a, c, d) with b one step +X and d one step +Z is the winding face() picks
	# for an upward face - checked by the primitives test
	for j in nz:
		for i in nx:
			var a := base + j * w + i
			var b := a + 1
			var c := a + w + 1
			var d := a + w
			_tri(a, b, c)
			_tri(a, c, d)


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
