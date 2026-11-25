extends SceneTree
## D10 门禁：≥阈值噪声把听程内的感染体引向声源 2 秒。
## 覆盖：小声（1）不惊动 / 枪声（3）惊动 / 听程外不理 / 朝声源移动 / 2 秒后停下 /
##       看见玩家时「看见优先于听见」。
## 运行（要渲染，读走廊场景）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/enemy_hearing.gd -- HEAR

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	RunState.current = null
	if FileAccess.file_exists(RunState.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	await process_frame
	await process_frame
	var actor := _corridor.get_node_or_null("Player") as Player
	_check(actor != null, "player missing")
	var enemies: Array = _corridor._enemies
	_check(enemies.size() >= 2, "corridor must spawn 2 enemies, got %d" % enemies.size())
	if actor == null or enemies.size() < 2:
		return _finish()
	var near: Enemy = enemies[0]
	var far: Enemy = enemies[1]

	# 布置：玩家在左端；near 在听程内、追击范围外；far 在听程外。
	actor.global_position = Vector2(100, 128)
	actor.velocity = Vector2.ZERO
	near.global_position = Vector2(390, 160)
	far.global_position = Vector2(560, 200)
	await physics_frame
	await physics_frame
	var near_start := near.global_position
	var far_start := far.global_position
	_check(near.global_position.distance_to(actor.global_position) > Enemy.CHASE_RANGE,
		"near enemy must start outside chase range, dist=%.1f" % near.global_position.distance_to(actor.global_position))
	_check(near.global_position.distance_to(actor.global_position) < Enemy.HEAR_RANGE,
		"near enemy must start inside hearing range")
	_check(far.global_position.distance_to(actor.global_position) > Enemy.HEAR_RANGE,
		"far enemy must start outside hearing range")
	_check(not near.is_investigating(), "enemy must be idle before any noise")

	# ① 近战噪声 1：不惊动
	_corridor._emit_noise(1)
	await physics_frame
	_check(not near.is_investigating(), "quiet noise (1) must not alert the enemy")

	# ② 枪声 3：惊动听程内的敌人，声源=玩家位置；听程外不动
	_corridor._emit_noise(3)
	await physics_frame
	_check(near.is_investigating(), "noise (3) must alert an enemy within hearing range")
	_check(not far.is_investigating(), "enemy outside hearing range must stay unaware")
	_check(near.hearing_target().distance_to(actor.global_position) < 2.0,
		"hearing target must be the noise source (player position)")

	# ③ 朝声源移动（玩家在左，所以 x 必须变小）
	for _i in range(30):
		await physics_frame
	_check(near.global_position.x < near_start.x - 2.0,
		"investigating enemy must walk toward the sound, x %.1f -> %.1f" % [near_start.x, near.global_position.x])
	_check(far.global_position.distance_to(far_start) < 1.0, "far enemy must not move")

	# ④ 2 秒后停下（此时仍在追击范围外：起点选位留了余量）
	for _i in range(95):
		await physics_frame
	_check(not near.is_investigating(), "investigation must end after ~2s")
	var stopped := near.global_position
	for _i in range(30):
		await physics_frame
	_check(near.global_position.distance_to(stopped) < 1.0, "enemy must stop after the investigation window")

	# ⑤ 看见优先于听见：玩家进入追击范围后 hearing 必须被清掉
	_corridor._emit_noise(3)
	await physics_frame
	actor.global_position = near.global_position + Vector2(80, 0)
	await physics_frame
	await physics_frame
	_check(not near.is_investigating(), "seeing the player must cancel hearing")

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("HEAR_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("ENEMY_HEARING_OK quiet=ignored loud=alert range=320s move=toward stop=after2s sight=wins")
		quit(0)
		return
	print("ENEMY_HEARING_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
