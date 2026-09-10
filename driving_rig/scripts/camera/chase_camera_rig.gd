class_name ChaseCameraRig
extends Node3D
## Lagged chase camera (SpringArm3D) plus the car's driver-eye camera, toggled with
## gamepad Y / keyboard C. Runs in _physics_process at tick rate so its motion is
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
var _car: DrivingCar
var _driver_cam: Camera3D
var _yaw: float = 0.0


func _ready() -> void:
	process_physics_priority = 50   # after the car (0), before the recorder (100)
	top_level = true
	_car = get_node(car_path) as DrivingCar
	_driver_cam = _car.get_node("DriverCam") as Camera3D
	_arm.spring_length = arm_length
	_arm.rotation_degrees.x = pitch_deg
	var s := SphereShape3D.new()
	s.radius = 0.25
	_arm.shape = s
	_arm.collision_mask = DrivingCar.LAYER_WORLD
	_arm.add_excluded_object(_car.get_rid())
	_chase_cam.fov = chase_fov
	_car.teleported.connect(snap)
	snap()
	_set_active(_chase_cam)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_toggle"):
		_set_active(_driver_cam if active_camera == _chase_cam else _chase_cam)


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
	return _car.global_position + Vector3.UP * pivot_height


func _target_yaw() -> float:
	var fwd := -_car.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-4:
		return _yaw
	return atan2(-fwd.x, -fwd.z)


func _set_active(cam: Camera3D) -> void:
	active_camera = cam
	cam.make_current()
