extends CharacterBody2D
class_name Player

signal stepped(is_running: bool)

## 三档速度：蹲下（潜行，最慢）< 步行（默认）< 疾跑（逃跑，最快）。
## 依据 design/CONTROLS.md v0.2（用户 2026-11-23 拍板：步行 / 蹲下潜行 / 疾跑）。
const CROUCH_SPEED := 12.0
const WALK_SPEED := 24.0
const SPRINT_SPEED := 44.0
const DEPTH_SPEED_SCALE := 0.8
const ACCELERATION := 600.0
const DECELERATION := 900.0
const STEP_DISTANCE := 16.0

## 脚底允许活动区域（世界坐标）。纵深轴（W/S）只在这个矩形内移动。
## 由 corridor.gd 在 _ready 里写入；空矩形表示不限制（测试/复用默认）。
var walk_bounds := Rect2()

var _distance_since_step := 0.0
var _movement_locked := false
var _sprint_action_available := false
var _crouch_action_available := false
var _previous_global_position := Vector2.ZERO
var facing_x := 1.0
var facing_y := 0.0
var gear := "walk"


func _ready() -> void:
	_previous_global_position = global_position
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(14, 40)
	collision.shape = rectangle
	collision.position = Vector2(0, -20)
	add_child(collision)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = false
	camera.limit_left = 0
	camera.limit_top = 0
	add_child(camera)

	_sprint_action_available = InputMap.has_action("sprint")
	_crouch_action_available = InputMap.has_action("crouch")


func _physics_process(delta: float) -> void:
	if _movement_locked:
		velocity = Vector2.ZERO
		_previous_global_position = global_position
		_distance_since_step = 0.0
		return

	var direction := _get_direction()
	var crouching := _crouch_action_available and Input.is_action_pressed("crouch")
	var sprinting := _sprint_action_available and Input.is_action_pressed("sprint")
	var speed := WALK_SPEED
	gear = "walk"
	if crouching:
		speed = CROUCH_SPEED
		gear = "crouch"
	elif sprinting:
		speed = SPRINT_SPEED
		gear = "sprint"
	var target_velocity := Vector2(
		direction.x * speed,
		direction.y * speed * DEPTH_SPEED_SCALE,
	)
	var rate := ACCELERATION if direction != Vector2.ZERO else DECELERATION
	if direction.x != 0.0:
		facing_x = signf(direction.x)
	if direction.y != 0.0:
		facing_y = signf(direction.y)

	velocity = velocity.move_toward(target_velocity, rate * delta)
	move_and_slide()
	_clamp_to_walk_bounds()

	var distance_moved := global_position.distance_to(_previous_global_position)
	_previous_global_position = global_position
	if distance_moved > 0.0:
		_distance_since_step += distance_moved
		while _distance_since_step >= STEP_DISTANCE:
			_distance_since_step -= STEP_DISTANCE
			stepped.emit(gear == "sprint")
	elif direction == Vector2.ZERO and velocity.is_zero_approx():
		_distance_since_step = 0.0


func _clamp_to_walk_bounds() -> void:
	if walk_bounds.size == Vector2.ZERO:
		return
	global_position = Vector2(
		clampf(global_position.x, walk_bounds.position.x, walk_bounds.end.x),
		clampf(global_position.y, walk_bounds.position.y, walk_bounds.end.y),
	)


func _get_direction() -> Vector2:
	var left := _is_action_pressed("move_left", KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right := _is_action_pressed("move_right", KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	var up := _is_action_pressed("move_up", KEY_W) or Input.is_key_pressed(KEY_UP)
	var down := _is_action_pressed("move_down", KEY_S) or Input.is_key_pressed(KEY_DOWN)
	return Vector2(float(right) - float(left), float(down) - float(up))


func _is_action_pressed(action: StringName, fallback_key: Key) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_key_pressed(fallback_key)
