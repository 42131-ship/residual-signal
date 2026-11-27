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
## D10：听声。>= 阈值的声音（枪声 3 / 噪声道具 2–3）会把它引向声源 2 秒；
## 潜行的意义由此成立——不发出 ≥3 的声音就不会暴露位置。
const HEAR_RANGE := 320.0
const HEAR_SECONDS := 2.0
const HEAR_SPEED_FACTOR := 0.85
const WALK_TOP := 128.0
const WALK_BOTTOM := 216.0
const CHAR_PATH := "res://art/generated_candidates/characters/SPR-student_infected_32.png"
const ANIM_ID := "student_infected"

var hp := 4
var speed := 18.0
var damage := 1
var dead := false
var player: Node2D
## 区块拴绳：感染体只在自己那段走廊里活动（x 范围；空 Rect2 = 不限）。
## 没有它，两只隔着整条走廊的感染体会一起扑向站着搜柜子的玩家 —— 真机实测 10 秒围死。
var leash := Rect2()
## 脱战时间：> 0 时完全忽略玩家（倒下后给玩家爬起来的机会，不然醒来就被原地再打死）。
var grace := 0.0
## 出生点：倒下结算时送回这里。
var home := Vector2.ZERO
var _cooldown := 0.0
var _sprite: Sprite2D
var _anim_time := 0.0
var _chasing := false
## D10：剩余循声时间与声源坐标；>0 表示正在调查。
var hearing_time := 0.0
var _hearing_target := Vector2.ZERO


func _ready() -> void:
	z_index = int(global_position.y)
	var texture: Texture2D = CharAnim.frame_texture(ANIM_ID, 0)
	if texture == null:
		texture = load(CHAR_PATH) as Texture2D
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
	if grace > 0.0:
		grace = maxf(0.0, grace - delta)
		_chasing = false
		_advance_anim(delta)
		return
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	# 玩家不在自己这段走廊里 = 看不见（哪怕直线距离很近）。范围判定之外再加区块判定。
	var player_in_leash := leash.size.x <= 0.0 or (
		player.global_position.x >= leash.position.x and player.global_position.x <= leash.end.x)
	if distance > CHASE_RANGE or not player_in_leash:
		_chasing = false
		# D10：没看见玩家时，循声走向声源；2 秒后停在原地。
		if hearing_time > 0.0:
			hearing_time = maxf(0.0, hearing_time - delta)
			var to_sound := _hearing_target - global_position
			if to_sound.length() > 6.0:
				global_position += to_sound.normalized() * speed * HEAR_SPEED_FACTOR * delta
				_clamp_to_leash()
				if _sprite != null:
					_sprite.flip_h = to_sound.x < 0.0
				_chasing = true
		z_index = int(global_position.y)
		_advance_anim(delta)
		return
	# 玩家进入追击范围：看见优先于听见。
	hearing_time = 0.0
	if distance > ATTACK_RANGE:
		global_position += to_player.normalized() * speed * delta
		_clamp_to_leash()
		if _sprite != null:
			_sprite.flip_h = to_player.x < 0.0
		_chasing = true
	elif _cooldown <= 0.0:
		_cooldown = ATTACK_COOLDOWN
		attacked.emit(damage)
	z_index = int(global_position.y)
	_advance_anim(delta)


## 关在走道里，再关在自己的区块里。
func _clamp_to_leash() -> void:
	global_position.y = clampf(global_position.y, WALK_TOP, WALK_BOTTOM)
	if leash.size.x > 0.0:
		global_position.x = clampf(global_position.x, leash.position.x, leash.end.x)


## 倒下结算：送回出生点、忘掉玩家、脱战一段时间。
func reset_after_down(grace_seconds: float) -> void:
	global_position = home
	hearing_time = 0.0
	_chasing = false
	grace = maxf(grace, grace_seconds)
	z_index = int(global_position.y)


## D10：走廊发出 ≥阈值噪声时调用。声源超出听程返回 false（远处的敌人不受影响）。
func hear(source: Vector2) -> bool:
	if dead:
		return false
	if global_position.distance_to(source) > HEAR_RANGE:
		return false
	_hearing_target = source
	hearing_time = HEAR_SECONDS
	return true


func is_investigating() -> bool:
	return hearing_time > 0.0


func hearing_target() -> Vector2:
	return _hearing_target


## 追人时播 walk，站着播 idle；死亡那帧由 take_damage 直接切。
func _advance_anim(delta: float) -> void:
	if _sprite == null or not CharAnim.has(ANIM_ID):
		return
	_anim_time += delta
	_sprite.texture = CharAnim.frame_texture(ANIM_ID, CharAnim.frame_at(ANIM_ID, "walk" if _chasing else "idle", _anim_time))


func take_damage(amount: int) -> void:
	if dead:
		return
	hp = maxi(0, hp - maxi(1, amount))
	damaged.emit(amount)
	if hp == 0:
		dead = true
		if _sprite != null and CharAnim.has(ANIM_ID):
			_sprite.texture = CharAnim.frame_texture(ANIM_ID, int(CharAnim.anim_meta("death").get("start", 7)) + 2)
		visible = true
		set_physics_process(false)
		died.emit(self)
