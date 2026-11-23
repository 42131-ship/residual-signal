extends CharacterBody2D
class_name Player

signal stepped(is_running: bool)

const SLOW_SPEED := 12.0
const NORMAL_SPEED := 24.0
const ACCELERATION := 600.0
const DECELERATION := 900.0
const STEP_DISTANCE := 16.0

var _distance_since_step := 0.0
var _movement_locked := false
var _walk_action_available := false
var _previous_global_position := Vector2.ZERO
var facing_x := 1.0


func _ready() -> void:
	_previous_global_position = global_position
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 28)
	collision.shape = rectangle
	collision.position = Vector2(0, -14)
	add_child(collision)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = false
	camera.limit_left = 0
	camera.limit_top = 0
	add_child(camera)

	_walk_action_available = InputMap.has_action("walk")


func _physics_process(delta: float) -> void:
	if _movement_locked:
		velocity = Vector2.ZERO
		_previous_global_position = global_position
		_distance_since_step = 0.0
		return

	var direction := _get_direction()
	var walking := _walk_action_available and Input.is_action_pressed("walk")
	var target_speed := SLOW_SPEED if walking else NORMAL_SPEED
	var target_velocity := direction * target_speed
	var rate := ACCELERATION if direction != 0.0 else DECELERATION
	if direction != 0.0:
		facing_x = direction

	velocity.x = move_toward(velocity.x, target_velocity, rate * delta)
	velocity.y = 0.0
	move_and_slide()

	var distance_moved := global_position.distance_to(_previous_global_position)
	_previous_global_position = global_position
	if distance_moved > 0.0:
		_distance_since_step += distance_moved
		while _distance_since_step >= STEP_DISTANCE:
			_distance_since_step -= STEP_DISTANCE
			stepped.emit(not walking)
	elif direction == 0.0 and is_zero_approx(velocity.x):
		_distance_since_step = 0.0


func _get_direction() -> float:
	var left := _is_action_pressed("move_left", KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right := _is_action_pressed("move_right", KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	return float(right) - float(left)


func _is_action_pressed(action: StringName, fallback_key: Key) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_key_pressed(fallback_key)