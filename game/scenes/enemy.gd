class_name Enemy
extends Node2D
## 最简单的感染体：进入范围就追，贴身就抓一下。
## 不做寻路/碰撞（走廊是直线房间，WASD 已限制在可走区域内）。

signal attacked(damage: int)
signal damaged(amount: int)
signal died(enemy: Enemy)

const CHASE_RANGE := 240.0
const ATTACK_RANGE := 22.0
const ATTACK_COOLDOWN := 1.2
const WALK_TOP := 128.0
const WALK_BOTTOM := 216.0
const CHAR_PATH := "res://art/generated_candidates/characters/SPR-student_infected_32.png"

var hp := 4
var speed := 18.0
var damage := 1
var dead := false
var player: Node2D
var _cooldown := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	z_index = int(global_position.y)
	var texture := load(CHAR_PATH) as Texture2D
	if texture != null:
		_sprite = Sprite2D.new()
		_sprite.name = "BodySprite"
		_sprite.texture = texture
		_sprite.centered = false
		_sprite.position = Vector2(-16, -30)
		add_child(_sprite)


func _physics_process(delta: float) -> void:
	if dead or player == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	if distance > CHASE_RANGE:
		return
	if distance > ATTACK_RANGE:
		global_position += to_player.normalized() * speed * delta
		global_position.y = clampf(global_position.y, WALK_TOP, WALK_BOTTOM)
		if _sprite != null:
			_sprite.flip_h = to_player.x < 0.0
	elif _cooldown <= 0.0:
		_cooldown = ATTACK_COOLDOWN
		attacked.emit(damage)
	z_index = int(global_position.y)


func take_damage(amount: int) -> void:
	if dead:
		return
	hp = maxi(0, hp - maxi(1, amount))
	damaged.emit(amount)
	if hp == 0:
		dead = true
		visible = false
		set_physics_process(false)
		died.emit(self)
