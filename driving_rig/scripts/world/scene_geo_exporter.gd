class_name SceneGeoExporter
extends RefCounted
## Exports the drivable scene (everything under the Terrain node) as OBJ files that land in
## the take's space. Each object records whether the wheels can touch it ("collides"):
## visual-only geometry (road paint) is flagged false.
##
## the same space as the takes: world space, Godot metres × unit_scale (→ cm), Y-up,
## right-handed. One OBJ per MeshInstance3D, a shared scene.mtl, and scene.json describing
## it all (including the collision source, so Maya can warn on a take/ground mismatch).
##
## Winding: Godot treats clockwise triangles as front faces; OBJ and Maya use
## counter-clockwise. Faces are reversed on export (unless the node's transform mirrors,
## which flips them already).
##
## collect() touches nodes → main thread. write() only touches the collected arrays → safe
## on a worker thread.

const FORMAT_NAME: String = "driving_rig_scene"
const FORMAT_VERSION: int = 1


static func collect(root: Node, skip: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var obj_name := _unique_name(mi, used)
		if obj_name in skip:
			continue
		var surfaces: Array = []
		for s in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue   # PrimitiveMesh types (box, cylinder, prism…) are always triangles
			var a := mi.mesh.surface_get_arrays(s)
			surfaces.append({"v": a[Mesh.ARRAY_VERTEX], "n": a[Mesh.ARRAY_NORMAL], "i": a[Mesh.ARRAY_INDEX]})
		if not surfaces.is_empty():
			out.append({"name": obj_name, "xform": mi.global_transform, "surfaces": surfaces, "color": _color(mi),
				"collides": bool(mi.get_meta(&"drv_collides", true))})
	return out


## Returns {ok, dir, objects, error}. `meta` supplies unit_scale, collision_source, versions.
static func write(dir: String, objects: Array[Dictionary], meta: Dictionary) -> Dictionary:
	var scale: float = meta.get("unit_scale", 100.0)
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return {"ok": false, "error": "cannot create %s (%s)" % [dir, error_string(err)]}
	var listed: Array = []
	var mtl := PackedStringArray(["# Driving Rig scene materials"])
	for o in objects:
		var r := _write_obj(dir.path_join("%s.obj" % o["name"]), o, scale)
		if not r.get("ok", false):
			return {"ok": false, "error": r.get("error", "write failed")}
		var c: Color = o["color"]
		mtl.append("newmtl %s\nKd %.4f %.4f %.4f\nKa 0 0 0\nKs 0 0 0" % [o["name"], c.r, c.g, c.b])
		listed.append({"name": o["name"], "file": "%s.obj" % o["name"], "vertices": r["vertices"],
			"triangles": r["triangles"], "bounds_min": r["bmin"], "bounds_max": r["bmax"],
			"color": [c.r, c.g, c.b], "collides": o.get("collides", true)})
	var fm := FileAccess.open(dir.path_join("scene.mtl"), FileAccess.WRITE)
	fm.store_string("\n".join(mtl) + "\n")
	fm.close()
	var manifest := {
		"format": FORMAT_NAME, "format_version": FORMAT_VERSION,
		"units": "cm", "unit_scale": scale, "up_axis": "Y", "forward": "-Z",
		"space": "world", "winding": "ccw",
		"collision_source": meta.get("collision_source", "unknown"),
		"godot_version": Engine.get_version_info()["string"],
		"rig_version": meta.get("rig_version", "dev"),
		"created": Time.get_datetime_string_from_system(),
		"objects": listed,
	}
	var fj := FileAccess.open(dir.path_join("scene.json"), FileAccess.WRITE)
	fj.store_string(JSON.stringify(manifest, "  ") + "\n")
	fj.close()
	return {"ok": true, "dir": dir, "objects": listed.size()}


static func _write_obj(path: String, o: Dictionary, scale: float) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())]}
	var xf: Transform3D = o["xform"]
	var nbasis := xf.basis.inverse().transposed()
	var reverse := xf.basis.determinant() > 0.0   # CW (Godot) → CCW (OBJ); a mirror already flips
	f.store_string("# Driving Rig scene geometry - %s\n# units: cm (Godot metres x %s), Y-up, right-handed, world space, CCW faces\nmtllib scene.mtl\no %s\nusemtl %s\n" % [
		o["name"], String.num(scale), o["name"], o["name"]])
	var base := 1
	var vtotal := 0
	var ttotal := 0
	var bmin := Vector3(INF, INF, INF)
	var bmax := Vector3(-INF, -INF, -INF)
	for surf: Dictionary in o["surfaces"]:
		var v: PackedVector3Array = surf["v"]
		var lines := PackedStringArray()
		lines.resize(v.size())
		for k in v.size():
			var p := (xf * v[k]) * scale
			bmin = bmin.min(p)
			bmax = bmax.max(p)
			lines[k] = "v %s %s %s" % [_n(p.x), _n(p.y), _n(p.z)]
		f.store_string("\n".join(lines) + "\n")
		var has_n: bool = surf["n"] != null and (surf["n"] as PackedVector3Array).size() == v.size()
		if has_n:
			var nv: PackedVector3Array = surf["n"]
			for k in nv.size():
				var q := (nbasis * nv[k]).normalized()
				lines[k] = "vn %s %s %s" % [String.num(q.x, 5), String.num(q.y, 5), String.num(q.z, 5)]
			f.store_string("\n".join(lines) + "\n")
		var idx: PackedInt32Array
		if surf["i"] != null and (surf["i"] as PackedInt32Array).size() > 0:
			idx = surf["i"]
		else:
			idx = PackedInt32Array(range(v.size()))
		var faces := PackedStringArray()
		faces.resize(idx.size() / 3)
		for t in faces.size():
			var a := idx[t * 3] + base
			var b := idx[t * 3 + 1] + base
			var c := idx[t * 3 + 2] + base
			if reverse:
				var tmp := b
				b = c
				c = tmp
			faces[t] = ("f %d//%d %d//%d %d//%d" % [a, a, b, b, c, c]) if has_n else ("f %d %d %d" % [a, b, c])
		f.store_string("\n".join(faces) + "\n")
		base += v.size()
		vtotal += v.size()
		ttotal += faces.size()
	f.close()
	return {"ok": true, "vertices": vtotal, "triangles": ttotal,
		"bmin": [bmin.x, bmin.y, bmin.z], "bmax": [bmax.x, bmax.y, bmax.z]}


static func _n(x: float) -> String:
	return "0" if absf(x) < 0.00005 else String.num(x, 4)   # 1 µm resolution in cm


static func _unique_name(mi: MeshInstance3D, used: Dictionary) -> String:
	var raw := String(mi.name)
	if raw.ends_with("Geo") and raw.length() > 3:
		raw = raw.left(-3)
	var clean := ""
	for ch in raw:
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" else "_"
	clean = clean.strip_edges().trim_prefix("_")
	if clean.is_empty() or (clean[0] >= "0" and clean[0] <= "9"):
		clean = "mesh_" + clean
	var out := clean
	var k := 2
	while used.has(out.to_lower()):
		out = "%s_%d" % [clean, k]
		k += 1
	used[out.to_lower()] = true
	return out


static func _color(mi: MeshInstance3D) -> Color:
	var m: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
	if m is ShaderMaterial:
		var c: Variant = (m as ShaderMaterial).get_shader_parameter(&"base_color")
		if c is Color:
			return c
	elif m is StandardMaterial3D:
		return (m as StandardMaterial3D).albedo_color
	return Color(0.5, 0.5, 0.5)
