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

@export var hang_angle := 0.0

@onready var _menu_root: CanvasLayer = $Menu
@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _camera_controller: CameraController = $CameraController
@onready var _ground_shapecast: ShapeCast3D = $GroundShapeCast

# TODO: Consider breaking all this climbing stuff out into its own class? Maybe this is fine.
@onready var _climb_shapecast: ShapeCast3D = $ClimbShapeCast
@onready var _climb_area: Area3D = $ClimbArea
@onready var _head_root: Node3D = $HeadRoot
@onready var _left_hand: Node3D = $CharacterRotationRoot/LeftHand
@onready var _left_shoulder: Node3D = $CharacterRotationRoot/LeftShoulder
@onready var _right_hand: Node3D = $CharacterRotationRoot/RightHand
@onready var _right_shoulder: Node3D = $CharacterRotationRoot/RightShoulder

@onready var _move_direction := Vector3.ZERO
@onready var _last_strong_direction := Vector3.FORWARD
@onready var _gravity: float = -30.0
@onready var _ground_height: float = 0.0
@onready var _start_position := global_transform.origin
@onready var _is_on_floor_buffer := false
@onready var _climbing_mode := false

var wall_normal: Vector3
var wall_relative_up: Vector3

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_controller.setup(self)
	_camera_controller.set_pivot(_camera_controller.CAMERA_PIVOT.THIRD_PERSON)


func _physics_process(delta: float) -> void:

	# Raycasts out from player's hips. If anything is hit and player presses E, _climbing_mode becomes true. if nothing is hit, _climbing_mode becomes false
	climbing_shapecast()

	# Checks if _ground_shapecast is hitting anything. If it is, set _ground_height to the heighest contact point. 
	calculate_ground_height()

	# Checks for jumping input. Set is_just_jumping. Add y velocity if jumping.
	grounded_state_check()

	# WASD input is taken here. Character is rotated to face _last_strong_direction if we're walking, or -wall_normal if we're climbing.
	orient_me(delta)

	# _move_direction is applied to velocity. Check to see if we're in climbing mode.
	falling(delta)

	if _climbing_mode:
		update_climbing_anim()

	move_and_check_stuck()


func climbing_raycast() -> void:
	var space_state = get_world_3d().direct_space_state

	var facing := _rotation_root.transform.basis * -Vector3.FORWARD

	var q = PhysicsRayQueryParameters3D.create(global_position+Vector3.UP, global_position+Vector3.UP+facing)
	q.exclude = [self]
	var r = space_state.intersect_ray(q)

	DebugDraw.draw_line(global_position+Vector3.UP, global_position+Vector3.UP+(facing), Color(1,0,0))
	if not r.is_empty():
		DebugDraw.draw_box(r.position, Vector3(0.2, 0.2, 0.2), Color(0,0,1))
		wall_normal = r.normal
		if Input.is_action_just_pressed("use"):
			_climbing_mode = not _climbing_mode
	elif _climbing_mode:
		_climbing_mode = false

func climbing_shapecast() -> void:
	var space_state = get_world_3d().direct_space_state
	var facing := _rotation_root.transform.basis * -Vector3.FORWARD

	var q_from := global_position+Vector3.UP
	var q_to := global_position+Vector3.UP+facing

	var q = PhysicsRayQueryParameters3D.create(q_from, q_to)
	q.exclude = [self]
	var r = space_state.intersect_ray(q)

	if _climb_shapecast.get_collision_count() > 0:
		if not r.is_empty():
			DebugDraw.draw_box(r.position, Vector3(0.2, 0.2, 0.2), Color(0,0,1))
			wall_normal = r.normal
			draw_wall_angles(r.position, wall_normal)
		if Input.is_action_just_pressed("use"):
			_climbing_mode = not _climbing_mode
			enter_climbing_anim()
	elif _climbing_mode:
		_climbing_mode = false
		exit_climbing_anim()

# wpoint is a point on the wall in front of the player, from a raycast.
# wnorm is the normal of the surface of the wall where wpoint lands.
func draw_wall_angles(wpoint: Vector3, wnorm: Vector3) -> void:
	# blue line is just wnorm, the normal of the wall
	DebugDraw.draw_line(wpoint, wpoint+wnorm, Color(0,0,1))

	# red line is the cross-product of wnorm and universal y axis, aka "up." produces a vector
	#   directly LEFT of the player.
	# could be changed to opposite of gravity direction for space gameplay, ie mario galaxy or outer wilds? 
	DebugDraw.draw_line(wpoint, wpoint+(wnorm.cross(Vector3.UP)), Color(1,0,0))

	# green line is what I want, the angle that the player's body should be oriented on the wall.
	# it is the cross product of the red and blue lines.
	DebugDraw.draw_line(wpoint, wpoint+(wnorm.cross(Vector3.UP).cross(wnorm)), Color(0,1,0))

# func get_wall_relative_up(normal: Vector3) -> Vector3:
	# return normal.cross(Vector3.UP).cross(normal)

# This overload uses the global wall_normal, probably bad. sigh
func get_wall_relative_up() -> Vector3:
	return wall_normal.cross(Vector3.UP).cross(wall_normal)

func enter_climbing_anim() -> void:
	pass

func update_climbing_anim() -> void:
	pass

func exit_climbing_anim() -> void:
	pass

# Checks if _ground_shapecast is hitting anything. If it is, set _ground_height to the heighest contact point. 
func calculate_ground_height() -> void:
	if _ground_shapecast.get_collision_count() > 0:
		for collision_result in _ground_shapecast.collision_result:
			_ground_height = max(_ground_height, collision_result.point.y)
	else:
		_ground_height = global_position.y + _ground_shapecast.target_position.y
	if global_position.y < _ground_height:
		_ground_height = global_position.y

# Checks for jumping input. Set is_just_jumping. Add y velocity if jumping.
func grounded_state_check() -> void:
	var is_just_jumping := Input.is_action_just_pressed("jump") and is_on_floor()

	_is_on_floor_buffer = is_on_floor()

	if is_just_jumping:
		velocity.y += jump_initial_impulse

# WASD input is taken here. Character is rotated to face _last_strong_direction if we're walking, or -wall_normal if we're climbing.
func orient_me(delta: float) -> void:

	# Gets WASD input, transforms it per the way _camera_controller is facing, outputs it as Vector3 'input'.
	_move_direction = _get_camera_oriented_input()


	# To not orient quickly to the last input, we save a last strong direction,
	# this also ensures a good normalized value for the rotation basis.
	if _move_direction.length() > 0.2:
		_last_strong_direction = _move_direction.normalized()

	if _climbing_mode and velocity.length() > 0.1:
		_move_direction -= wall_normal
		_last_strong_direction = -wall_normal

	# Rotates _rotation_root to face Vector3 direction.

	var orient_direction := _last_strong_direction

	_orient_character_to_direction(orient_direction, delta)
	_orient_head_to_look(delta)

# _move_direction is applied to velocity. Check to see if we're in climbing mode. If we are, don't do gravity
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

func move_and_check_stuck() -> void:
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

# Gets WASD input, transforms it per the way _camera_controller is facing, outputs it as Vector3 'input'.
func _get_camera_oriented_input() -> Vector3:

	var raw_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var input := Vector3.ZERO
	# This is to ensure that diagonal input isn't stronger than axis aligned input
	input.x = -raw_input.x * sqrt(1.0 - raw_input.y * raw_input.y / 2.0)
	input.z = -raw_input.y * sqrt(1.0 - raw_input.x * raw_input.x / 2.0)

	input = _camera_controller.global_transform.basis * input
	input.y = 0.0
	return input

# Rotates _rotation_root to face Vector3 direction.
func _orient_character_to_direction(direction: Vector3, delta: float) -> void:
	var left_axis := Vector3.UP.cross(direction)
	var up_axis := get_wall_relative_up() if _climbing_mode else Vector3.UP
	var rotation_basis := Basis(left_axis, up_axis, direction).get_rotation_quaternion()
	var model_scale := _rotation_root.transform.basis.get_scale()
	_rotation_root.transform.basis = Basis(_rotation_root.transform.basis.get_rotation_quaternion().slerp(rotation_basis, delta * rotation_speed)).scaled(
		model_scale
	)

func _orient_head_to_look(delta: float) -> void:
	var model_scale := _head_root.transform.basis.get_scale()
	_head_root.transform.basis = Basis(_head_root.transform.basis.get_rotation_quaternion().slerp(_camera_controller.transform.basis, delta * rotation_speed)).scaled(model_scale)
