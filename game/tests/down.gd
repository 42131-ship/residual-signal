extends SceneTree
## D9 门禁：体力归零触发「倒下」结算（丢 1 沉积 + 翻到次日 + 回学校 + 体力回 0.3）。
## 覆盖：敌人抓伤打空 / 同一天再次打空也必须结算（锁定期只防同帧）/ 感染体回巢脱战 /
## advance_hours 流血打空 / 存档一致。
## 运行（要渲染，读走廊场景与 HUD）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/down.gd -- DOWN

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	RunState.current = null
	RunState.clear_saved()

	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	await process_frame
	await process_frame
	_check(int(_corridor._day.day) == 0, "a fresh run must start on day 0")
	_check(int(_corridor._day.sediment) == 0, "a fresh run must start with 0 sediment")

	# ① 敌人抓伤把体力打空 → 倒下：丢 1 沉积（floor 0）、翻到 Day 1、回学校、体力 0.3
	_corridor._health = 0.1
	_corridor._on_enemy_attacked(1)
	await _wait_down(1)
	_check(_corridor.down_count() == 1, "taking lethal damage must trigger exactly one down")
	_check(int(_corridor._day.day) == 1, "down must advance to day 1, got %d" % _corridor._day.day)
	_check(int(_corridor._day.sediment) == 0, "down must lose 1 sediment (floor 0), got %d" % _corridor._day.sediment)
	_check(_corridor._health >= 0.3 - 0.001, "down must restore health to 0.3, got %.2f" % _corridor._health)
	_check(str(_corridor._current_building) == "school", "down must drag the player back to school, got %s" % _corridor._current_building)
	_check(_corridor.last_down_day() == 1, "last_down_day must record the resulting day")
	_check(str(_corridor._panel_title).contains("倒下"), "down must open a panel explaining what happened, got %s" % _corridor._panel_title)
	_check(FileAccess.file_exists(RunState.SAVE_PATH), "down must persist the run")
	var reloaded := RunState.load_saved()
	_check(reloaded != null, "saved run must load after down")
	if reloaded != null:
		_check(reloaded.day == 1, "saved day must be 1, got %d" % reloaded.day)
		_check(reloaded.building == "school", "saved building must be school, got %s" % reloaded.building)
		_check(reloaded.health >= 0.3 - 0.001, "saved health must be restored")

	# ② 同一天再被打空：必须再结算一次（每次倒下抵一天），只由锁定期防同帧重复。
	# 旧实现按世界日只放行一次，结果「被打到 0 体力却什么都不发生」——真机截图出现过。
	_check(_corridor._down_lockout > 0.0, "a down must start the lockout window")
	_corridor._health = 0.0
	for _frame in range(40):
		await process_frame
	_check(_corridor.down_count() == 1, "the lockout window must swallow immediate re-triggers")
	await _wait_down(2)
	_check(_corridor.down_count() == 2, "being beaten to 0 again must settle another down, got %d" % _corridor.down_count())
	_check(int(_corridor._day.day) == 2, "the second down must advance to day 2, got %d" % _corridor._day.day)
	_check(_corridor._health >= 0.3 - 0.001, "the second down must restore health to 0.3")
	# 倒下后感染体必须回巢 + 脱战，否则玩家在面板上还没看清就被贴脸再打死。
	for enemy: Enemy in _corridor._enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.dead:
			continue
		_check(enemy.global_position.distance_to(enemy.home) < 1.0,
			"%s must return home after a down" % enemy.name)
		_check(enemy.grace > 0.0, "%s must drop aggro after a down" % enemy.name)

	# ③ 隔一天再倒下：先出门到加油站（Day 3、沉积 +1），再被打倒（沉积 1→0、Day 4）
	await _wait_ready()
	_corridor._health = 1.0
	_corridor._depart_to("gas_station")
	await process_frame
	await process_frame
	_check(int(_corridor._day.day) == 3, "departure must advance to day 3, got %d" % _corridor._day.day)
	_check(str(_corridor._current_building) == "gas_station", "departure must move to gas_station")
	_check(int(_corridor._day.sediment) == 1, "extracted day must add 1 sediment, got %d" % _corridor._day.sediment)
	_corridor._health = 0.1
	_corridor._on_enemy_attacked(1)
	await _wait_down(3)
	_check(_corridor.down_count() == 3, "a new day may settle another down")
	_check(int(_corridor._day.day) == 4, "third down must advance to day 4, got %d" % _corridor._day.day)
	_check(int(_corridor._day.sediment) == 0, "third down must lose the 1 sediment, got %d" % _corridor._day.sediment)
	_check(str(_corridor._current_building) == "school", "third down must return to school")

	# ④ advance_hours 路径：伤口每小时掉体力，打空也必须触发倒下
	await _wait_ready()
	_corridor._health = 1.0
	_corridor._depart_to("gas_station")
	await process_frame
	await process_frame
	_check(int(_corridor._day.day) == 5, "fourth outing must advance to day 5, got %d" % _corridor._day.day)
	_corridor._health = 0.05
	_corridor._status.apply("wound")
	var drain: float = _corridor._status.health_drain_per_hour()
	_check(drain > 0.0, "wound must drain health per hour, got %.3f" % drain)
	_corridor.advance_hours(1.0)
	await _wait_down(4)
	_check(_corridor.down_count() == 4, "blood loss must also trigger a down")
	_check(int(_corridor._day.day) == 6, "blood-loss down must advance to day 6, got %d" % _corridor._day.day)
	_check(_corridor._health >= 0.3 - 0.001, "down must always restore health to 0.3")

	_finish()


## 等无敌帧与倒下锁都过期：门禁不能靠「恰好还没锁」办事。
func _wait_ready() -> void:
	for _frame in range(600):
		if _corridor._hurt_immune <= 0.0 and _corridor._down_lockout <= 0.0:
			await process_frame
			return
		await process_frame
	_check(false, "hurt/down timers never expired")


func _wait_down(target: int) -> void:
	for _frame in range(240):
		await process_frame
		if _corridor.down_count() >= target:
			await process_frame
			return


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("DOWN_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("DOWN_OK damage=trigger repeat_down=settles lockout=dampens blood_loss=trigger sediment=floor0 enemies=rehomed save=ok")
		quit(0)
		return
	print("DOWN_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
