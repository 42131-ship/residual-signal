extends SceneTree
## D11 门禁：房间级状态——三个区块各有独立灯光档与容器，敌人按区分布。
## 覆盖：A/B/C 灯光档递减且平滑过渡 / 光照 uniform 跟着变 / 容器按区各一档 / 敌人不在 A 区。
## 运行（要渲染，读走廊场景与光照材质）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/room_light.gd -- ROOM

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
	if actor == null:
		return _finish()
	_check(_corridor._light_material != null, "flashlight shader material missing")

	# ① 容器按区：三个容器分别在 A/B/C，档位互不相同（数据既有，本次加门禁锁住）
	var loot = _corridor._loot
	_check(loot != null, "loot service missing")
	if loot != null:
		var ids: Array = loot.container_ids()
		_check(ids.size() == 3, "expected 3 containers, got %d" % ids.size())
		var rooms := {}
		var tiers := {}
		for id: String in ids:
			rooms[loot.room_of(id)] = true
			tiers[loot.tier_of(id)] = true
		_check(rooms.has("A") and rooms.has("B") and rooms.has("C"),
			"each room must own one container, got %s" % str(rooms.keys()))
		_check(tiers.size() == 3, "container tiers must differ per room, got %s" % str(tiers.keys()))

	# ② 敌人按区：初始两只在 B/C，不在 A（A 区是入门区，给玩家喘息）
	var zones := {}
	for enemy: Enemy in _corridor._enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var tile_x: float = enemy.global_position.x / 16.0
		var zone := 0
		if tile_x >= 12.0 and tile_x < 26.0:
			zone = 1
		elif tile_x >= 26.0:
			zone = 2
		zones[zone] = true
	_check(not zones.has(0), "no enemy should start in room A")
	_check(zones.has(1) and zones.has(2), "enemies should start in rooms B and C, got %s" % str(zones.keys()))
	# 灯光是静态流程门禁，不需要敌人真的追打（D9 倒下会锁移动）。
	_corridor.disarm_enemies()

	# ③ 灯光档：A > B > C，且换区是平滑过渡（不是一帧切换）
	var expected: Array[float] = [1.15, 0.85, 0.62]
	var positions := [Vector2(100, 160), Vector2(300, 160), Vector2(560, 160)]
	var measured: Array[float] = []
	for index in range(3):
		actor.global_position = positions[index]
		actor.velocity = Vector2.ZERO
		await physics_frame
		_check(_corridor.current_room_index() == index,
			"room index at x=%.0f must be %d, got %d" % [positions[index].x, index, _corridor.current_room_index()])
		for _i in range(75):
			await process_frame
		measured.append(_corridor.room_light_factor())
		_check(absf(_corridor.room_light_factor() - expected[index]) < 0.05,
			"room %d light must converge to %.2f, got %.3f" % [index, expected[index], _corridor.room_light_factor()])
	_check(measured[0] > measured[1] and measured[1] > measured[2],
		"lights must get darker A->B->C, got %s" % str(measured))

	# ④ 着色器 uniform 必须跟着区块变化（否则只有内部变量、画面不变）
	var tint_c: Variant = _corridor._light_material.get_shader_parameter("outside_tint")
	actor.global_position = positions[0]
	actor.velocity = Vector2.ZERO
	for _i in range(75):
		await process_frame
	var tint_a: Variant = _corridor._light_material.get_shader_parameter("outside_tint")
	_check(_tint_x(tint_a) > _tint_x(tint_c) + 0.05,
		"outside_tint must brighten in room A (A=%.2f C=%.2f)" % [_tint_x(tint_a), _tint_x(tint_c)])

	# ⑤ 平滑：从 A 走到 C 的下一帧不应瞬间跳到目标值
	actor.global_position = positions[2]
	actor.velocity = Vector2.ZERO
	await physics_frame
	await process_frame
	_check(_corridor.room_light_factor() > expected[2] + 0.05,
		"zone light must fade smoothly, got %.3f on the first frame in C" % _corridor.room_light_factor())
	for _i in range(75):
		await process_frame
	_check(absf(_corridor.room_light_factor() - expected[2]) < 0.05,
		"zone light must settle in room C, got %.3f" % _corridor.room_light_factor())

	_finish()


func _tint_x(value: Variant) -> float:
	if value is Vector4:
		return (value as Vector4).x
	if value is Color:
		return (value as Color).r
	return -1.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("ROOM_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("ROOM_LIGHT_OK zones=3 light=A>B>C uniforms=follow containers=A/B/C enemies=B/C smooth=yes")
		quit(0)
		return
	print("ROOM_LIGHT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
