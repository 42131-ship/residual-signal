extends SceneTree
## D3 门禁：actions_left 是「一天一次外出」的真消耗，不再写死 1。
## 覆盖：服务层 no_action_left / 同一天第二次出发被拒且状态不动 / 出发消耗后跨天恢复 /
##       出发即落盘 / RunState 存档往返（0 保留、负数夹 0）。
## 运行（要渲染，读走廊场景与 HUD）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/m2a_actions.gd -- ACTIONS

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
	var run := RunState.current
	_check(run != null, "RunState.current missing")
	if run == null:
		return _finish()
	var budget := int(_corridor._travel.actions_per_day())
	_check(run.actions_left == budget,
		"fresh run must start with %d action(s), got %d" % [budget, run.actions_left])

	# ① 服务层：actions_left=0 → no_action_left；=预算 → 放行
	var blocked: Dictionary = _corridor._travel.can_travel("school", "gas_station",
		{"fuel": 10, "actions_left": 0, "hour": 12})
	_check(not bool(blocked.get("ok", true)), "can_travel must reject zero actions")
	_check(str(blocked.get("reason", "")) == "no_action_left",
		"reason must be no_action_left, got %s" % str(blocked.get("reason", "")))
	var allowed: Dictionary = _corridor._travel.can_travel("school", "gas_station",
		{"fuel": 10, "actions_left": budget, "hour": 12})
	_check(bool(allowed.get("ok", false)),
		"can_travel must allow with budget, got %s" % str(allowed.get("reason", "")))

	# ② 同一天第二次出发：把行动次数打空，_depart_to 必须被拒且世界状态不动
	run.actions_left = 0
	var day_before := int(_corridor._day.day)
	var building_before := str(_corridor._current_building)
	_corridor._depart_to("gas_station")
	await process_frame
	_check(int(_corridor._day.day) == day_before, "refused departure must not advance the day")
	_check(str(_corridor._current_building) == building_before, "refused departure must not move building")
	_check(RunState.current.actions_left == 0, "refused departure must not consume from zero")

	# ③ 有行动次数：出发成功 → 换楼 + 天数 +1 + 新一天恢复行动预算
	run.actions_left = budget
	_corridor._depart_to("gas_station")
	await process_frame
	_check(str(_corridor._current_building) == "gas_station", "departure must move to gas_station")
	_check(int(_corridor._day.day) == day_before + 1, "departure must advance one day")
	_check(int(RunState.current.actions_left) == budget,
		"new day must restore %d action(s), got %d" % [budget, RunState.current.actions_left])
	_check(FileAccess.file_exists(RunState.SAVE_PATH), "departure must persist the run")
	var reloaded := RunState.load_saved()
	_check(reloaded != null, "saved run must load back")
	if reloaded != null:
		_check(reloaded.actions_left == budget,
			"saved actions_left must be restored budget, got %d" % reloaded.actions_left)
		_check(reloaded.building == "gas_station", "saved building mismatch: %s" % reloaded.building)

	# ④ 存档往返：0 必须保留，负数必须夹到 0
	var tmp := RunState.new()
	tmp.new_run()
	tmp.actions_left = 0
	var data := tmp.to_dict()
	_check(int(data.get("actions_left", -1)) == 0, "to_dict must keep 0 actions")
	var restored := RunState.new()
	_check(restored.from_dict(data), "from_dict must accept a v1 dict")
	_check(restored.actions_left == 0, "roundtrip must keep 0 actions, got %d" % restored.actions_left)
	data["actions_left"] = -3
	var clamped := RunState.new()
	clamped.from_dict(data)
	_check(clamped.actions_left == 0, "negative actions must clamp to 0, got %d" % clamped.actions_left)

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("ACTIONS_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("M2A_ACTIONS_OK guard=no_action_left depart=consume restore=per_day save=roundtrip")
		quit(0)
		return
	print("M2A_ACTIONS_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
