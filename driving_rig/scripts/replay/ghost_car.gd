class_name GhostCar
extends Node3D
## Visual-only car rebuilt from a take's `meta` alone — deliberately not a copy of the live
## car scene. This is exactly the job the Maya importer has, so if the ghost matches the
## live drive, both the channels *and* the meta are proven sufficient.
##
## Hierarchy mirrors the live car and the Maya rig:
##   GhostCar (chassis) → wheel_XX_steer → wheel_XX_susp → wheel_XX_spin → wheel_XX_geo


var susp_rest: float = 0.32
var wheel_radius: float = 0.34
var body_size: Vector3 = Vector3(1.3, 1.0, 4.4)
var steering_ratio: float = 15.0
var wheel_geos: Array[Node3D] = []
var _steering_wheel: Node3D
var _steer: Array[Node3D] = []
var _susp: Array[Node3D] = []
var _spin: Array[Node3D] = []


func build(meta: Dictionary, body_mat: Material, wheel_mat: Material, accent_mat: Material) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_steering_wheel = null
	wheel_geos.clear()
	_steer.clear()
	_susp.clear()
	_spin.clear()

	var body: Dictionary = meta["body"]
	var ext := _v3(body["extents"])
	body_size = ext
	wheel_radius = float(meta["wheel_radius"])
	var cp: Dictionary = meta.get("car_params", {})
	var model_path: String = cp.get("chassis_scene", "")
	if model_path != "" and ResourceLoader.exists(model_path):
		var holder := Node3D.new()
		holder.name = "chassis_model"
		var t: Array = cp.get("chassis_transform", [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
		holder.transform = Transform3D(Basis(Vector3(t[0], t[1], t[2]), Vector3(t[3], t[4], t[5]),
				Vector3(t[6], t[7], t[8])), Vector3(t[9], t[10], t[11]))
		add_child(holder)
		holder.add_child((load(model_path) as PackedScene).instantiate())
	else:
		_build_box(ext, body_mat, accent_mat)
	if cp.has("steering_ratio") and cp.has("driver_eye"):
		steering_ratio = float(cp["steering_ratio"])
		_steering_wheel = DrivingCar.build_steering_wheel(self, _v3(cp["driver_eye"]), _v3(cp["steering_wheel_offset"]),
				float(cp["steering_column_tilt_deg"]), float(cp["steering_wheel_radius"]), wheel_mat, accent_mat)
	_build_wheels(meta, wheel_mat)


func _build_box(ext: Vector3, body_mat: Material, accent_mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = ext
	var bmi := MeshInstance3D.new()
	bmi.name = "body_geo"
	bmi.mesh = box
	bmi.material_override = body_mat
	add_child(bmi)
	var nose := BoxMesh.new()
	nose.size = Vector3(ext.x * 0.8, 0.12, 0.12)
	var nmi := MeshInstance3D.new()
	nmi.name = "nose_geo"
	nmi.mesh = nose
	nmi.material_override = accent_mat
	nmi.position = Vector3(0.0, ext.y * 0.5 - 0.06, -ext.z * 0.5 + 0.02)
	add_child(nmi)


func _build_wheels(meta: Dictionary, wheel_mat: Material) -> void:
	susp_rest = float(meta["susp_rest"])
	var cyl := CylinderMesh.new()
	cyl.top_radius = float(meta["wheel_radius"])
	cyl.bottom_radius = cyl.top_radius
	cyl.height = float(meta["wheel_width"])
	cyl.radial_segments = 24
	cyl.rings = 1
	var names: Array = meta.get("wheel_order", ["FL", "FR", "RL", "RR"])
	var hps: Array = meta["hardpoints"]
	for i in 4:
		var wn: String = names[i]
		var steer := Node3D.new()
		steer.name = "wheel_%s_steer" % wn
		steer.position = _v3(hps[i])
		add_child(steer)
		var susp := Node3D.new()
		susp.name = "wheel_%s_susp" % wn
		susp.position = Vector3(0.0, -susp_rest, 0.0)
		steer.add_child(susp)
		var spin := Node3D.new()
		spin.name = "wheel_%s_spin" % wn
		susp.add_child(spin)
		var geo := MeshInstance3D.new()
		geo.name = "wheel_%s_geo" % wn
		geo.mesh = cyl
		geo.material_override = wheel_mat
		geo.rotation = Vector3(0.0, 0.0, PI * 0.5)
		spin.add_child(geo)
		_steer.append(steer)
		_susp.append(susp)
		_spin.append(spin)
		wheel_geos.append(geo)


## Pose from samples o0/o1 (flat-layout offsets), blended by f ∈ [0,1).
## spin_cumulative is never wrapped, so plain lerp is correct — the reason for that rule.
func apply(d: PackedFloat64Array, o0: int, o1: int, f: float) -> void:
	var p := Vector3(d[o0], d[o0 + 1], d[o0 + 2])
	var q := Quaternion(d[o0 + 3], d[o0 + 4], d[o0 + 5], d[o0 + 6]).normalized()
	if f > 0.0:
		p = p.lerp(Vector3(d[o1], d[o1 + 1], d[o1 + 2]), f)
		q = q.slerp(Quaternion(d[o1 + 3], d[o1 + 4], d[o1 + 5], d[o1 + 6]).normalized(), f)
	global_transform = Transform3D(Basis(q), p)
	for w in _steer.size():
		var k0 := o0 + TakeFormat.O_WHEELS + w * TakeFormat.W_STRIDE
		var k1 := o1 + TakeFormat.O_WHEELS + w * TakeFormat.W_STRIDE
		_susp[w].position.y = -(susp_rest - lerpf(d[k0], d[k1], f))
		_steer[w].rotation.y = lerpf(d[k0 + 1], d[k1 + 1], f)
		_spin[w].rotation.x = -fmod(lerpf(d[k0 + 2], d[k1 + 2], f), TAU)
	if _steering_wheel and _steer.size() >= 2:
		_steering_wheel.rotation.z = (_steer[0].rotation.y + _steer[1].rotation.y) * 0.5 * steering_ratio


func hardpoint(i: int) -> Vector3:
	return _steer[i].position if i < _steer.size() else Vector3.ZERO


static func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
