extends SceneTree
## 状态系统门禁：伤口/感染/中毒/成瘾 的阶段、推进、消退、倍率与用药。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/status.gd
## 通过输出一行 `STATUS_OK ...`。

var _failures: Array[String] = []


func _initialize() -> void:
	var s := StatusService.new()
	if not s.load_all():
		_fail("load failed: " + s.load_error())
		return
	_check(s.ids() == ["addiction", "infection", "poison", "wound"], "ids must be the four documented states")
	_check(s.label_of("wound") == "伤口", "wound label must come from data")
	_check(not s.has("wound") and s.stage_of("wound") == 0, "fresh service must be clean")

	# ① 阶段与上限
	_check(s.apply("wound") == 1, "first scratch -> stage 1")
	_check(s.apply("wound") == 2, "second scratch -> stage 2")
	_check(s.apply("wound") == 3, "third scratch -> stage 3")
	_check(s.apply("wound") == 3, "stage must clamp at max 3")
	_check(s.max_stage_of("wound") == 3, "max stage comes from data")

	# ② 未知 id 不炸、不生效
	_check(s.apply("nonsense") == 0 and not s.has("nonsense"), "unknown status must be ignored")

	# ③ 用药：对症才治，不对症不动
	_check(s.cure_with_item("bandage") == "wound", "bandage must cure the wound")
	_check(not s.has("wound"), "wound must be gone after bandage")
	_check(s.cure_with_item("bandage") == "", "curing nothing must return empty")
	_check(not s.cure("wound"), "curing an absent status must report false")

	# ④ 感染按 4 游戏小时恶化一级，到顶不再涨
	s.apply("infection")
	_check(s.stage_of("infection") == 1, "infection starts at 1")
	s.tick_hours(3.9)
	_check(s.stage_of("infection") == 1, "3.9h must not advance the stage")
	s.tick_hours(0.2)
	_check(s.stage_of("infection") == 2, "4.1h must advance to stage 2")
	s.tick_hours(4.0)
	_check(s.stage_of("infection") == 3, "8.1h must reach stage 3")
	s.tick_hours(20.0)
	_check(s.stage_of("infection") == 3, "infection must cap at 3")
	_check(s.cure_with_item("antibiotics") == "infection", "antibiotics must cure infection")

	# ⑤ 中毒 6 小时自行消退
	var p := StatusService.new()
	p.load_all()
	p.apply("poison")
	p.tick_hours(5.0)
	_check(p.has("poison"), "poison must still be active at 5h")
	p.tick_hours(1.5)
	_check(not p.has("poison"), "poison must fade by 6.5h")

	# ⑥ 倍率与掉血随阶段变化
	var m := StatusService.new()
	m.load_all()
	var base_drain := m.health_drain_per_hour()
	m.apply("wound")
	m.apply("wound")
	var two_drain := m.health_drain_per_hour()
	_check(base_drain == 0.0, "clean state must not drain health")
	_check(two_drain > 0.0, "wounded state must drain health")
	_check(m.speed_multiplier() <= 1.0, "speed multiplier must never exceed 1")
	m.apply("poison")
	_check(m.speed_multiplier() < 1.0, "poison must slow the player")
	m.apply("addiction")
	_check(m.noise_multiplier() > 1.0, "addiction must raise noise")
	_check(m.speed_multiplier() >= 0.35, "speed multiplier must stay bounded")

	# ⑦ summary / active 供 HUD 用，且顺序稳定
	var rows := m.active()
	_check(rows.size() >= 3, "active() must list every active status")
	var again := m.active()
	_check(str(rows) == str(again), "active() order must be stable")
	_check(m.summary().contains("伤口"), "summary must contain the label")

	if not _failures.is_empty():
		print("STATUS_FAILED count=%d" % _failures.size())
		for failure: String in _failures:
			print("  - " + failure)
		quit(1)
		return
	print("STATUS_OK states=4 wound_cap=3 infection=4h poison_decay=6h cures=ok multipliers=bounded")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("STATUS_FAIL " + message)


func _fail(detail: String) -> void:
	push_error("STATUS_FAIL " + detail)
	print("STATUS_FAIL " + detail)
	quit(1)
