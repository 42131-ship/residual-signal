extends SceneTree
## 出行层门禁：五栋楼、路线对称、一天一次、燃料门槛、夜里风险翻倍。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/travel.gd

var _failures: Array[String] = []


func _initialize() -> void:
	var travel := TravelService.new()
	if not travel.load_all():
		_fail("load failed: " + travel.load_error())
		return

	# ① 五栋楼，学校是唯一安全屋
	var ids := travel.building_ids()
	_check(ids.size() == 5, "expected 5 buildings, got %d" % ids.size())
	_check(ids.has("school") and ids.has("gas_station"), "school and gas_station must exist")
	var safehouses: Array[String] = []
	for id: String in ids:
		if travel.is_safehouse(id):
			safehouses.append(id)
	_check(safehouses == ["school"], "school must be the only safehouse, got %s" % str(safehouses))

	# ② 学校 <-> 加油站 是首个可玩外部线，双向都要通
	var there := travel.route("school", "gas_station")
	var back := travel.route("gas_station", "school")
	_check(not there.is_empty(), "school->gas_station route missing")
	_check(not back.is_empty(), "gas_station->school route missing")
	_check(there == back, "routes must be symmetric: %s vs %s" % [str(there), str(back)])
	_check(int(there.get("cost", 0)) >= 1, "route cost must be at least 1")
	_check(int(there.get("fuel", -1)) == 0, "the first leg must not need fuel")

	# ③ 所有邻接都对称（防止只写一侧）
	for id: String in ids:
		for other: String in travel.neighbors(id):
			_check(not travel.route(other, id).is_empty(), "%s->%s has no return route" % [id, other])
			_check(str(other) != id, "%s lists itself as a neighbour" % id)

	# ④ 一天一次行动
	_check(travel.actions_per_day() == 1, "one outing per day, got %d" % travel.actions_per_day())
	var blocked := travel.can_travel("school", "gas_station", {"fuel": 5, "actions_left": 0, "hour": 12})
	_check(not bool(blocked.get("ok", true)), "no actions left must block travel")
	_check(str(blocked.get("reason", "")) == "no_action_left", "wrong block reason: %s" % str(blocked.get("reason")))
	var allowed := travel.can_travel("school", "gas_station", {"fuel": 0, "actions_left": 1, "hour": 12})
	_check(bool(allowed.get("ok", false)), "a free route with an action left must be allowed")

	# ⑤ 燃料门槛：去军事基地要 2，只有 1 就不行
	var no_fuel := travel.can_travel("hospital", "military_base", {"fuel": 1, "actions_left": 1, "hour": 12})
	_check(not bool(no_fuel.get("ok", true)), "not enough fuel must block the long leg")
	_check(str(no_fuel.get("reason", "")) == "not_enough_fuel", "wrong fuel reason: %s" % str(no_fuel.get("reason")))

	# ⑥ 没路就是没路
	var nowhere := travel.can_travel("school", "military_base", {"fuel": 9, "actions_left": 1, "hour": 12})
	_check(not bool(nowhere.get("ok", true)), "there must be no direct school->military route")

	# ⑦ 夜里风险翻倍
	var day_risk := travel.risk_of("gas_station", "hospital", 12)
	var night_risk := travel.risk_of("gas_station", "hospital", 19)
	_check(day_risk > 0, "route risk must be positive by day")
	_check(night_risk == day_risk * 2, "night risk must double: %d -> %d" % [day_risk, night_risk])
	_check(travel.night_hour() == 18, "night starts at 18:00, got %d" % travel.night_hour())

	if not _failures.is_empty():
		print("TRAVEL_FAILED count=%d" % _failures.size())
		for failure: String in _failures:
			print("  - " + failure)
		quit(1)
		return
	print("TRAVEL_OK buildings=5 safehouse=school first_leg=school<->gas_station actions_per_day=1 night=2x")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("TRAVEL_FAIL " + message)


func _fail(detail: String) -> void:
	push_error("TRAVEL_FAIL " + detail)
	print("TRAVEL_FAIL " + detail)
	quit(1)
