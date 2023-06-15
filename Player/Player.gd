class_name Playa
extends CharacterBody3D

signal weapon_switched(weapon_name: String)


## Character maximum run speed on the ground.
@export var move_speed := 8.0
## Movement acceleration (how fast character achieve maximum speed)
@export var acceleration := 4.0
## Jump impulse
@export var jump_initial_impulse := 12.0
## Jump impulse when player keeps pressing jump
@export var jump_additional_force := 4.5
## Player model rotaion speed
@export var rotation_speed := 12.0
## Minimum horizontal speed on the ground. This controls when the character's animation tree changes
## between the idle and running states.
@export var stopping_speed := 1.0

@onready var _menu_root: CanvasLayer = $Menu
@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _camera_controller: CameraController = $CameraController
@onready var _ground_shapecast: ShapeCast3D = $GroundShapeCast
@onready var _climb_area: Area3D = $ClimbArea

@onready var _move_direction := Vector3.ZERO
@onready var _last_strong_direction := Vector3.FORWARD
@onready var _gravity: float = -30.0
@onready var _ground_height: float = 0.0
@onready var _start_position := global_transform.origin
@onready var _is_on_floor_buffer := false
@onready var _climbing_mode := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_controller.setup(self)
	# _climb_area.body_entered.connect(_on_climb_area_body_entered) # Signals are cool!

# func _on_climb_area_body_entered(body):
	# # 1. indentify if what we're touching is static world geometry (OK)
	# # 2. parse the faces of the mesh for their normals
	# # 3. draw a debug arrow to represent the normal
	# # if body is StaticBody3D:
	# #	var c = body.get_node('CollisionShape3D').shape
	# print(body.name)

func _process(delta: float):
	pass

func climbing_raycast(delta: float) -> void:
	var space_state = get_world_3d().direct_space_state

	var q = PhysicsRayQueryParameters3D.create(global_position+Vector3.UP, global_position+Vector3.UP+_last_strong_direction)
	q.exclude = [self]
	var r = space_state.intersect_ray(q)

	DebugDraw.draw_line(global_position+Vector3.UP, global_position+Vector3.UP+(_last_strong_direction), Color(1,0,0))
	if not r.is_empty():
		DebugDraw.draw_box(r.position, Vector3(0.2, 0.2, 0.2), Color(0,0,1))
		if Input.is_action_just_pressed("use"):
			_climbing_mode = not _climbing_mode
	elif _climbing_mode:
		_climbing_mode = false

func calculate_ground_height(delta: float) -> void:
	if _ground_shapecast.get_collision_count() > 0:
		for collision_result in _ground_shapecast.collision_result:
			_ground_height = max(_ground_height, collision_result.point.y)
	else:
		_ground_height = global_position.y + _ground_shapecast.target_position.y
	if global_position.y < _ground_height:
		_ground_height = global_position.y

func grounded_state_check(delta: float) -> void:
	var is_just_jumping := Input.is_action_just_pressed("jump") and is_on_floor()
	var is_air_boosting := Input.is_action_pressed("jump") and not is_on_floor() and velocity.y > 0.0
	var is_just_on_floor := is_on_floor() and not _is_on_floor_buffer

	_is_on_floor_buffer = is_on_floor()

	if is_just_jumping:
		velocity.y += jump_initial_impulse
	elif is_air_boosting:
		velocity.y += jump_additional_force * delta

func orient_me(delta: float) -> void:
	_move_direction = _get_camera_oriented_input()

	# To not orient quickly to the last input, we save a last strong direction,
	# this also ensures a good normalized value for the rotation basis.
	if _move_direction.length() > 0.2:
		_last_strong_direction = _move_direction.normalized()

	_orient_character_to_direction(_last_strong_direction, delta)

func falling(delta: float) -> void:
	# We separate out the y velocity to not interpolate on the gravity
	var y_velocity := velocity.y
	velocity.y = 0.0
	velocity = velocity.lerp(_move_direction * move_speed, acceleration * delta)
	if _move_direction.length() == 0 and velocity.length() < stopping_speed:
		velocity = Vector3.ZERO
	velocity.y = y_velocity

	if _climbing_mode:
		velocity.y = 2 if Input.is_action_pressed("jump") else -2 if Input.is_action_pressed("crouch") else 0
	else:
		velocity.y += _gravity * delta


func _physics_process(delta: float) -> void:

	climbing_raycast(delta)

	calculate_ground_height(delta)

	grounded_state_check(delta)

	orient_me(delta)

	falling(delta)

	_camera_controller.set_pivot(_camera_controller.CAMERA_PIVOT.THIRD_PERSON)

	var position_before := global_position
	move_and_slide()
	var position_after := global_position

	# If velocity is not 0 but the difference of positions after move_and_slide is,
	# character might be stuck somewhere!
	var delta_position := position_after - position_before
	var epsilon := 0.001
	if delta_position.length() < epsilon and velocity.length() > epsilon:
		global_position += get_wall_normal() * 0.1


func reset_position() -> void:
	transform.origin = _start_position

func _get_camera_oriented_input() -> Vector3:

	var raw_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var input := Vector3.ZERO
	# This is to ensure that diagonal input isn't stronger than axis aligned input
	input.x = -raw_input.x * sqrt(1.0 - raw_input.y * raw_input.y / 2.0)
	input.z = -raw_input.y * sqrt(1.0 - raw_input.x * raw_input.x / 2.0)

	input = _camera_controller.global_transform.basis * input
	input.y = 0.0
	return input


func play_foot_step_sound() -> void:
#	_step_sound.pitch_scale = randfn(1.2, 0.2)
#	_step_sound.play()
	pass


func damage(_impact_point: Vector3, force: Vector3) -> void:
	pass


func _orient_character_to_direction(direction: Vector3, delta: float) -> void:
	var left_axis := Vector3.UP.cross(direction)
	var rotation_basis := Basis(left_axis, Vector3.UP, direction).get_rotation_quaternion()
	var model_scale := _rotation_root.transform.basis.get_scale()
	_rotation_root.transform.basis = Basis(_rotation_root.transform.basis.get_rotation_quaternion().slerp(rotation_basis, delta * rotation_speed)).scaled(
		model_scale
	)
