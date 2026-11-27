extends SceneTree
## 战斗门禁（真渲染）：敌人存在/追击抓伤、近战命中、耐久耗尽、枪械弹匣与装填、击杀。
## 运行（不能加 --headless，要截图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_combat.gd -- CORRIDOR-COMBAT
## 通过输出一行 `CORRIDOR_COMBAT_OK ...`。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _actor: Player
var _prefix := "CORRIDOR-COMBAT"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("CORRIDOR-"):
			_prefix = argument
	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	_actor = _corridor.get_node_or_null("Player") as Player
	await process_frame
	await process_frame
	if _actor == null:
		_check(false, "player missing")
		_finish()
		return

	var enemies: Array = _corridor._enemies
	_check(enemies.size() == 2, "expected 2 enemies, got %d" % enemies.size())
	if enemies.size() != 2:
		_finish()
		return
	var first: Enemy = enemies[0]
	var second: Enemy = enemies[1]

	# ① 敌人抓伤：站到身边等它出手，体力必须下降。
	await _place(second.global_position.x - 24.0, second.global_position.y)
	await _wait_physics(100)
	_check(_corridor._health < 1.0, "enemy attack did not damage the player: %.2f" % _corridor._health)
	# ① 之后把感染体改成「只当画面元素」：后面几段要等 0.75s 挥击锁，
	# 站着不动的玩家会被连续抓伤打到 0 体力触发「倒下」，把这张门禁搅黄（门禁不是测 D9）。
	_corridor.disarm_enemies()

	# ② 近战：装备撬棍（伤害 2 / 耐久 8），两下打死第一只。
	_corridor._inventory.add("crowbar")
	_corridor._equip_item("crowbar")
	_check(_corridor._weapon_durability == 8, "crowbar durability should be 8, got %d" % _corridor._weapon_durability)
	_check(_corridor._weapon_damage == 2, "crowbar damage should be 2")
	await _place(first.global_position.x - 24.0, first.global_position.y)
	_actor.facing_x = 1.0
	_check(first.hp == 4, "enemy hp should start at 4")
	_corridor._unhandled_input(_mouse_left())
	await process_frame
	_check(first.hp == 2, "first crowbar hit should deal 2, hp=%d" % first.hp)
	_check(_corridor._weapon_durability == 7, "durability should drop to 7, got %d" % _corridor._weapon_durability)

	# 命中反馈：顿帧冻结双方、受击者闪白、镜头抖 1px。
	_check(_corridor._hitstop_frames > 0, "a landed hit must freeze the world for a few frames")
	_check(absf(_corridor._camera.offset.x) >= 1.0, "a landed hit must shake the camera by 1px")
	var hit_sprite := first.get_node_or_null("BodySprite") as Sprite2D
	_check(hit_sprite != null and hit_sprite.modulate.r > 1.5, "the struck enemy must flash")
	_check(not _actor.is_physics_processing(), "player physics must be frozen during hitstop")
	for _frame in range(8):
		await process_frame
	_check(_corridor._hitstop_frames == 0, "hitstop must end on its own")
	_check(_corridor._camera.offset == Vector2.ZERO, "camera must return to zero offset")
	if hit_sprite != null:
		_check(hit_sprite.modulate == Color.WHITE, "flash must be cleared after the feedback window")
	_check(_actor.is_physics_processing(), "player physics must resume after hitstop")

	# 挥击有 0.75s 可重入锁（ATTACK_FRAMES=45）：第二下必须先等锁放手，否则输入被忽略。
	await _wait_attack_ready()
	_corridor._unhandled_input(_mouse_left())
	await process_frame
	_check(first.dead, "second hit should kill the enemy")
	_check(_corridor._enemies_killed == 1, "kill counter should be 1, got %d" % _corridor._enemies_killed)
	await _capture("%s_enemy" % _prefix)

	# ③ 枪械：装填消耗弹药，射击消耗弹匣、伤害更高、噪声更大。
	_corridor._inventory.add("pistol")
	_corridor._inventory.add("ammo_9mm")
	_corridor._equip_item("pistol")
	_check(_corridor._magazine == 0, "fresh firearm should have empty magazine")
	await _press(KEY_R)
	_check(_corridor._magazine == 6, "reload should fill 6 rounds, got %d" % _corridor._magazine)
	_check(not _corridor._inventory.has("ammo_9mm"), "reload did not consume the ammo item")
	await _place(second.global_position.x - 30.0, second.global_position.y)
	_actor.facing_x = 1.0
	await _wait_attack_ready()
	var noise_before: int = _corridor._noise
	_corridor._unhandled_input(_mouse_left())
	await process_frame
	_check(second.hp == 1, "pistol hit should deal 3, hp=%d" % second.hp)
	_check(_corridor._magazine == 5, "shot did not consume the magazine round")
	_check(_corridor._noise > noise_before, "gunshot should raise noise")
	await _wait_attack_ready()
	_corridor._unhandled_input(_mouse_left())
	await process_frame
	_check(second.dead, "second pistol shot should kill the enemy")
	_check(_corridor._enemies_killed == 2, "kill counter should be 2")

	# ④ 耐久耗尽：把撬棍耐久设成 1，再挥一下必须损坏并卸下。
	_corridor._inventory.add("crowbar")
	_corridor._equip_item("crowbar")
	_corridor._weapon_durability = 1
	var dummy := Enemy.new()
	dummy.position = Vector2(300, 168)
	dummy.player = _actor
	_corridor.add_child(dummy)
	_corridor._enemies.append(dummy)
	await _place(276.0, 168.0)
	_actor.facing_x = 1.0
	await _wait_attack_ready()
	_corridor._unhandled_input(_mouse_left())
	await process_frame
	_check(_corridor._equipped == "", "broken weapon should be unequipped")
	_check(_corridor._weapon_durability == 0, "broken weapon durability should be 0")
	_finish()


func _wait_physics(frames: int) -> void:
	for _frame in range(frames):
		await physics_frame


## 等 0.75s 挥击锁放手（ATTACK_FRAMES=45，在 _process 里递减；顿帧期间不递减）。
func _wait_attack_ready() -> void:
	for _frame in range(180):
		if _corridor._attack_frames <= 0:
			return
		await process_frame
	_check(false, "attack lock never released")


func _place(x: float, y: float) -> void:
	_actor.global_position = Vector2(x, y)
	_actor.velocity = Vector2.ZERO
	await process_frame
	await process_frame


func _press(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.keycode = keycode
	down.pressed = true
	_corridor._unhandled_input(down)
	await process_frame
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.keycode = keycode
	up.pressed = false
	_corridor._unhandled_input(up)
	await process_frame


func _mouse_left() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _capture(label: String) -> void:
	_actor.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		_actor.set_physics_process(true)
		_check(false, "capture failed")
		return
	var path := "res://design/previews/%s.png" % label
	if rendered.save_png(ProjectSettings.globalize_path(path)) != OK:
		_actor.set_physics_process(true)
		_check(false, "could not save " + path)
		return
	print("COMBAT_SHOT %s" % path)
	_actor.set_physics_process(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("COMBAT_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CORRIDOR_COMBAT_OK enemies=2 melee=damage2 durability=8 firearm=magazine6 reload=ammo kills=2 broken=unequip")
		quit(0)
		return
	print("CORRIDOR_COMBAT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
