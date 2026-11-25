extends SceneTree
## D4 门禁：燃料是「门槛」不是消耗池（见 data/travel/routes.json 注释）。
## 覆盖：开局 0 燃料 → 到加油站补给 +1 → 医院（需 1）解锁；旅程不扣燃料；
##       第二次到加油站到 2 → 军事基地（需 2）解锁；上限 3；RunState 落盘一致。
## 运行（要渲染，读走廊场景与旅行图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/travel_fuel.gd -- FUEL

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
	_check(str(_corridor._current_building) == "school", "a fresh run must start at school")
	_check(int(_corridor._fuel) == 0, "a fresh run must start with 0 fuel, got %d" % _corridor._fuel)

	# ① 门槛语义：学校 → 加油站要 0 燃料（可走）；加油站 → 医院要 1（0 时被挡）
	_check(_can("school", "gas_station", 0), "school -> gas_station must be open at 0 fuel")
	var blocked: Dictionary = _corridor._travel.can_travel("gas_station", "hospital",
		{"fuel": 0, "actions_left": 1, "hour": 12})
	_check(not bool(blocked.get("ok", true)), "gas_station -> hospital must be blocked at 0 fuel")
	_check(str(blocked.get("reason", "")) == "not_enough_fuel",
		"reason must be not_enough_fuel, got %s" % str(blocked.get("reason", "")))

	# ② 到加油站补给 +1，医院随即可达；补给要落进 RunState
	_corridor._depart_to("gas_station")
	await process_frame
	_check(str(_corridor._current_building) == "gas_station", "departure must move to gas_station")
	_check(int(_corridor._fuel) == 1, "arriving at gas_station must refuel +1, got %d" % _corridor._fuel)
	_check(int(RunState.current.fuel) == 1, "RunState.fuel must mirror the refuel, got %d" % RunState.current.fuel)
	_check(_can("gas_station", "hospital", 1), "gas_station -> hospital must open after refueling")
	if FileAccess.file_exists(RunState.SAVE_PATH):
		var saved := RunState.load_saved()
		_check(saved != null and saved.fuel == 1, "saved run must keep the refueled fuel")
	# 旅行图上医院从灰显变为可选
	_place_at_exit()
	await process_frame
	await process_frame
	_corridor._open_travel_map()
	await process_frame
	var selectable: Array = _corridor._map.selectable_ids() if _corridor._map != null else []
	_check("hospital" in selectable, "travel map must offer hospital after refueling, got %s" % str(selectable))
	_corridor._close_travel_map()

	# ③ 旅程不消耗燃料：去医院后燃料仍是 1
	_corridor._depart_to("hospital")
	await process_frame
	_check(str(_corridor._current_building) == "hospital", "departure must move to hospital")
	_check(int(_corridor._fuel) == 1, "fuel must not be spent by travel, got %d" % _corridor._fuel)
	var military_blocked: Dictionary = _corridor._travel.can_travel("hospital", "military_base",
		{"fuel": 1, "actions_left": 1, "hour": 12})
	_check(not bool(military_blocked.get("ok", true)), "military_base must stay blocked at 1 fuel")

	# ④ 第二次到加油站 → 2 燃料，军事基地解锁
	_corridor._depart_to("gas_station")
	await process_frame
	_check(int(_corridor._fuel) == 2, "second gas_station visit must reach 2 fuel, got %d" % _corridor._fuel)
	_corridor._depart_to("hospital")
	await process_frame
	_check(_can("hospital", "military_base", 2), "hospital -> military_base must open at 2 fuel")
	_place_at_exit()
	await process_frame
	await process_frame
	_corridor._open_travel_map()
	await process_frame
	selectable = _corridor._map.selectable_ids() if _corridor._map != null else []
	_check("military_base" in selectable, "travel map must offer military_base at 2 fuel, got %s" % str(selectable))
	_corridor._close_travel_map()

	# ⑤ 上限 3：回学校再回加油站，燃料最多 3
	_corridor._fuel = 3
	_corridor._depart_to("school")
	await process_frame
	_check(int(_corridor._fuel) == 3, "fuel must be unchanged when leaving gas_station at cap")
	_corridor._depart_to("gas_station")
	await process_frame
	_check(int(_corridor._fuel) == 3, "refuel must clamp at FUEL_MAX=3, got %d" % _corridor._fuel)

	_finish()


func _can(from: String, to: String, fuel: int) -> bool:
	var verdict: Dictionary = _corridor._travel.can_travel(from, to,
		{"fuel": fuel, "actions_left": 1, "hour": 12})
	return bool(verdict.get("ok", false))


func _place_at_exit() -> void:
	var actor := _corridor.get_node_or_null("Player") as Player
	if actor != null:
		actor.global_position = Vector2(600.0, 128.0)
		actor.velocity = Vector2.ZERO


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("FUEL_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("TRAVEL_FUEL_OK start=0 refuel=+1 no_spend=yes cap=3 hospital_at_1=yes military_at_2=yes")
		quit(0)
		return
	print("TRAVEL_FUEL_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
