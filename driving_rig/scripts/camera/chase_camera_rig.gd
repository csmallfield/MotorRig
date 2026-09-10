class_name ChaseCameraRig
extends Node3D
## Lagged chase camera (SpringArm3D) plus the car's driver-eye camera, toggled with
## gamepad Y / keyboard C. Follows the live car by default; the take browser points it at
## the replay ghost, and while a replay is shown Y/C toggles chase ↔ recorded camera. Runs in _physics_process at tick rate so its motion is
## deterministic and gets the same physics interpolation as the car.

@export var car_path: NodePath
@export var pivot_height: float = 1.3
@export var arm_length: float = 6.5
@export var pitch_deg: float = -11.0
@export var position_sharpness: float = 14.0   ## 1/s — higher = tighter follow
@export var yaw_sharpness: float = 3.5
@export var chase_fov: float = 60.0

@onready var _arm: SpringArm3D = $Arm
@onready var _chase_cam: Camera3D = $Arm/Camera

var active_camera: Camera3D
## Set by the browser while a replay is on screen; replaces the driver cam in the toggle.
var replay_cam: Camera3D = null:
	set(v):
		replay_cam = v
		if v == null and active_camera != _chase_cam and active_camera != _driver_cam:
			_set_active(_chase_cam)
var _car: DrivingCar
var _follow: Node3D
var _driver_cam: Camera3D
var _yaw: float = 0.0


func _ready() -> void:
	process_physics_priority = 50   # after the car (0), before the recorder (100)
	top_level = true
	_car = get_node(car_path) as DrivingCar
	_follow = _car
	_driver_cam = _car.get_node("DriverCam") as Camera3D
	_arm.spring_length = arm_length
	_arm.rotation_degrees.x = pitch_deg
	var s := SphereShape3D.new()
	s.radius = 0.25
	_arm.shape = s
	_arm.collision_mask = DrivingCar.LAYER_WORLD
	_arm.add_excluded_object(_car.get_rid())   # the ghost has no collider, nothing to exclude
	_chase_cam.fov = chase_fov
	_car.teleported.connect(func() -> void: if _follow == _car: snap())
	snap()
	_set_active(_chase_cam)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_toggle"):
		var alt := replay_cam if replay_cam else _driver_cam
		_set_active(alt if active_camera == _chase_cam else _chase_cam)


## Point the chase rig at another body (the replay ghost) or back at the car.
func follow(target: Node3D) -> void:
	if target == _follow:
		return
	_follow = target
	if active_camera == _driver_cam and target != _car:
		_set_active(_chase_cam)
	snap()


func _physics_process(delta: float) -> void:
	global_position = global_position.lerp(_target_pos(), 1.0 - exp(-position_sharpness * delta))
	_yaw = lerp_angle(_yaw, _target_yaw(), 1.0 - exp(-yaw_sharpness * delta))
	rotation = Vector3(0.0, _yaw, 0.0)


func snap() -> void:
	global_position = _target_pos()
	_yaw = _target_yaw()
	rotation = Vector3(0.0, _yaw, 0.0)
	reset_physics_interpolation()


func _target_pos() -> Vector3:
	return _follow.global_position + Vector3.UP * pivot_height


func _target_yaw() -> float:
	var fwd := -_follow.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-4:
		return _yaw
	return atan2(-fwd.x, -fwd.z)


func _set_active(cam: Camera3D) -> void:
	active_camera = cam
	cam.make_current()
