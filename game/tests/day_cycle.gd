extends SceneTree
## 结算门禁：离场/未离场的沉积差、体力恢复、物资消耗、30 天收束。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/day_cycle.gd

var _failures: Array[String] = []


func _initialize() -> void:
	var cycle := DayCycle.new()
	cycle.new_run()
	_check(cycle.day == 0 and cycle.sediment == 0, "fresh run must start at day 0 / sediment 0")
	_check(cycle.day_label() == "第 1 / 30 天", "day label should read 第 1 / 30 天, got %s" % cycle.day_label())

	# ① 成功离场：沉积 +1，体力回 0.25，物资不变
	var extract := cycle.settle({"extracted": true, "supplies": 0.8, "health": 0.5, "kills": 2, "noise": 4})
	_check(int(extract["sediment"]) == 1, "an extracted day must add 1 sediment, got %d" % int(extract["sediment"]))
	_check(int(extract["next_day"]) == 1, "day must advance to 1")
	_check(absf(float(extract["health"]) - 0.75) < 0.001, "sleeping must restore 0.25 health")
	_check(absf(float(extract["supplies"]) - 0.8) < 0.001, "an extracted day must not consume supplies")
	_check((extract["lines"] as Array).size() >= 2, "settlement must produce summary lines")

	# ② 没能离场：沉积 +2，物资 -0.05，体力只回 0.1
	var lost := cycle.settle({"extracted": false, "supplies": 0.8, "health": 0.5})
	_check(int(lost["sediment"]) == 3, "a lost day must add 2 sediment, got %d" % int(lost["sediment"]))
	_check(absf(float(lost["supplies"]) - 0.75) < 0.001, "a lost day must consume 0.05 supplies")
	_check(absf(float(lost["supplies_delta"]) + 0.05) < 0.001,
		"a lost day must report a -0.05 supplies delta, got %s" % str(lost["supplies_delta"]))
	_check(absf(float(extract["supplies_delta"])) < 0.001,
		"an extracted day must report a zero supplies delta, got %s" % str(extract["supplies_delta"]))
	_check(absf(float(lost["health"]) - 0.6) < 0.001, "a lost day must only restore 0.1 health")

	# ③ 沉积有上限 40
	for _i in range(40):
		cycle.settle({"extracted": false})
	_check(cycle.sediment <= 40, "sediment must cap at 40, got %d" % cycle.sediment)
	_check(cycle.sediment == 40, "sediment should sit at the cap after enough bad days")

	# ④ 30 天收束
	var run := DayCycle.new()
	run.new_run()
	for _i in range(29):
		run.settle({"extracted": true})
	_check(not run.finished, "day 29 must not be finished")
	var last := run.settle({"extracted": true})
	_check(bool(last["finished"]), "day 30 must finish the run")
	_check(run.day == 30, "day must clamp at 30, got %d" % run.day)
	var extra := run.settle({"extracted": true})
	_check(run.day == 30, "settling past day 30 must not overflow, got %d" % run.day)
	_check(bool(extra["finished"]), "still finished")

	# ⑤ 数值夹取
	var clamp_cycle := DayCycle.new()
	clamp_cycle.new_run()
	var clamped := clamp_cycle.settle({"extracted": true, "supplies": 9.0, "health": 7.0})
	_check(float(clamped["supplies"]) <= 1.0, "supplies must clamp to 1")
	_check(float(clamped["health"]) <= 1.0, "health must clamp to 1")

	if not _failures.is_empty():
		print("DAY_FAILED count=%d" % _failures.size())
		for failure: String in _failures:
			print("  - " + failure)
		quit(1)
		return
	print("DAY_OK extract=+1 sediment lost=+2 cap=40 days=30 rested=0.25/0.10")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("DAY_FAIL " + message)
