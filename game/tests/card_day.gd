extends SceneTree
## D12 门禁：每天开始抽 1 张事件卡并作用于 world_state；效果随 RunState 存档/重载保留。
## 覆盖：Day0 不抽 / Day1 必抽 1 张 / 卡效果改 world_state / 同日去重 / 存档镜像 / 新场景读回。
## 运行（要渲染，读走廊场景）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/card_day.gd -- CARD

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
	_check(_corridor._card != null, "card engine must be online")
	_check(_corridor.cards_fired() == 0, "day 0 must not draw a card, got %d" % _corridor.cards_fired())
	_check(int(_corridor._state.day) == 0, "world_state.day must start at 0")

	# ① Day 1 出发：新的一天必须抽 1 张，且 world_state.day 对齐
	_corridor._depart_to("gas_station")
	await process_frame
	await process_frame
	_check(int(_corridor._day.day) == 1, "departure must advance to day 1")
	_check(int(_corridor._state.day) == 1, "world_state.day must follow DayCycle, got %d" % _corridor._state.day)
	_check(_corridor.cards_fired() == 1, "day 1 must draw exactly 1 card, got %d" % _corridor.cards_fired())
	_check(not _corridor.last_card_id().is_empty(), "a card id must be recorded")
	_check(not _corridor.last_card_text().is_empty(), "a rendered card text must be recorded")

	# ② 同日去重：再手动抽一次必须被拒
	var again: Dictionary = _corridor._fire_daily_card()
	_check(not bool(again.get("fired", true)), "the same day must not draw a second card")
	_check(_corridor.cards_fired() == 1, "rejected draw must not increase the counter")

	# ③ 卡效果真的写进 world_state：用已知卡「敲三下」的开门效果（trust +0.1 / control -0.1）
	var target: Dictionary = {}
	for card: Dictionary in _corridor._data.cards():
		if str(card.get("card_id", "")) == "l_knock_three_times":
			target = card
			break
	_check(not target.is_empty(), "l_knock_three_times must exist in the card pool")
	if target.is_empty():
		return _finish()
	var trust_before: float = _corridor._state.var_of("trust")
	var entries: Array = _corridor._card.fire(target, {"choice": "开门"})
	var trust_after: float = _corridor._state.var_of("trust")
	_check(entries.size() >= 1, "firing the open-door effect must produce at least one entry")
	_check(trust_after > trust_before + 0.05, "card effect must raise world_state.trust, %.2f -> %.2f" % [trust_before, trust_after])

	# ④ 落盘：RunState 里要有六组变量的镜像，读档后必须一致
	_corridor._persist_run()
	var reloaded := RunState.load_saved()
	_check(reloaded != null, "run must be saved after a card fires")
	if reloaded != null:
		_check(reloaded.world_vars.has("trust"), "saved run must mirror world_state.trust")
		_check(absf(float(reloaded.world_vars.get("trust", -1.0)) - trust_after) < 0.001,
			"saved trust must equal world_state.trust")
		_check(reloaded.world_vars.has("control"), "saved run must mirror world_state.control")

	# ⑤ 新走廊实例（模拟切场景/重启）：变量必须从 RunState 恢复
	var second := SCENE.instantiate() as Node2D
	root.add_child(second)
	await process_frame
	await process_frame
	_check(second._state != null, "second corridor must have world_state online")
	if second._state != null:
		_check(absf(second._state.var_of("trust") - trust_after) < 0.001,
			"new scene must restore world_state.trust, got %.3f expected %.3f" % [second._state.var_of("trust"), trust_after])
	second.queue_free()
	await process_frame

	# ⑥ 第二天：再出发一天，抽卡计数最多 +1，且仍不可同日重复
	var before: int = _corridor.cards_fired()
	_corridor._depart_to("school")
	await process_frame
	await process_frame
	_check(_corridor.cards_fired() >= before, "card counter must not decrease")
	_check(_corridor.cards_fired() <= before + 1, "at most 1 card per day, got %d -> %d" % [before, _corridor.cards_fired()])
	var day2_again: Dictionary = _corridor._fire_daily_card()
	_check(not bool(day2_again.get("fired", true)), "day 2 must also dedupe the same-day draw")

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("CARD_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CARD_DAY_OK day0=none day1=draw effect=world_state persist=run_state scene=restore dedupe=same_day")
		quit(0)
		return
	print("CARD_DAY_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
