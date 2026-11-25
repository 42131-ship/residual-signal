extends SceneTree
## 出口门禁：走到尽头 → 打开旅行图 → 图上只列相邻可达的楼 → 选一栋 → 结算翻页；
## 燃料不足的楼不出现在可选集里，直接调 _depart_to 也必须被挡住。
## 运行（要渲染，抓一张旅行图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_exit.gd -- CORRIDOR-EXIT

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _actor: Player
var _prefix := "CORRIDOR-EXIT"
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
	# D9 之后敌人抓伤会触发「倒下」；这张门禁不测战斗，让感染体只当画面元素。
	_corridor.disarm_enemies()
	await process_frame
	await process_frame
	if _actor == null:
		_check(false, "player missing")
		return _finish()

	var day: DayCycle = _corridor._day
	_check(day != null, "corridor must own a DayCycle")
	if day == null:
		return _finish()
	_check(str(_corridor._current_building) == "school", "a run must start at school")

	# ① 没到出口：不提示，也不开图
	await _place(300.0, 128.0)
	_check(not _corridor._at_exit, "mid-corridor must not count as the exit")
	await _press(KEY_E)
	_check(not _corridor._map_open, "pressing E away from the exit must not open the map")
	_check(day.day == 0, "no settlement away from the exit")

	# ② 走到尽头按 E → 打开旅行图，可选集 = 学校的邻居
	await _place(600.0, 128.0)
	_check(_corridor._at_exit, "the far end must arm the exit")
	await _press(KEY_E)
	_check(_corridor._map_open, "leaving must open the travel map")
	var map: Node2D = _corridor._map
	_check(map != null, "travel map instance missing")
	if map == null:
		return _finish()
	var selectable: Array = map.selectable_ids()
	_check(selectable.size() == 2, "school must offer 2 neighbours, got %d" % selectable.size())
	_check("gas_station" in selectable, "gas_station must be selectable from school")
	_check("hospital" not in selectable, "hospital must not be reachable from school")
	await _capture("%s_map" % _prefix)

	# ③ W/S 遍历只走可选集，Esc 关闭不结算
	var first_id: String = map.selected_id()
	map.move(1)
	_check(map.selected_id() != first_id, "moving the cursor must change the selection")
	map.move(-1)
	_check(map.selected_id() == first_id, "moving back must return to the first choice")
	await _press(KEY_ESCAPE)
	_check(not _corridor._map_open, "Esc must close the map")
	_check(day.day == 0, "cancelling must not settle the day")

	# ④ 选学校 -> 加油站：确认后结算、换楼、回入口、面板打开
	await _place(600.0, 128.0)
	await _press(KEY_E)
	var guard := 0
	while str(_corridor._map.selected_id()) != "gas_station" and guard < 8:
		_corridor._map.move(1)
		guard += 1
	_check(str(_corridor._map.selected_id()) == "gas_station", "could not select gas_station on the map")
	await _press(KEY_E)
	_check(not _corridor._map_open, "confirming must close the map")
	_check(day.day == 1, "one outing must advance to day 1, got %d" % day.day)
	_check(day.sediment == 1, "an extracted day must add 1 sediment, got %d" % day.sediment)
	_check(str(_corridor._current_building) == "gas_station", "the run must move to gas_station")
	_check(_actor.position.x < 60.0, "the player must be back at the entrance, got %s" % str(_actor.position))
	_check(_corridor._inspection_open, "settlement panel must open after the trip")
	await _press(KEY_ESCAPE)

	# ⑤ 燃料门槛：在加油站、燃料 0 时医院不可选；硬调 _depart_to 也不结算
	_corridor._fuel = 0
	await _place(600.0, 128.0)
	await _press(KEY_E)
	_check(_corridor._map_open, "the map must reopen at the new building")
	_check("hospital" not in _corridor._map.selectable_ids(), "hospital must be blocked without fuel")
	_check("hospital" in _corridor._map.neighbor_ids(), "hospital must still be drawn greyed out")
	var before_day: int = day.day
	_corridor._depart_to("hospital")
	await process_frame
	_check(day.day == before_day, "a blocked destination must not settle the day")
	_check(str(_corridor._current_building) == "gas_station", "a blocked destination must not move the run")
	_check(str(_corridor._combat_message).contains("燃料"), "blocked destination should explain why")
	_corridor._close_travel_map()

	_finish()


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
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.keycode = keycode
	up.pressed = false
	_corridor._unhandled_input(up)
	await process_frame


func _capture(label: String) -> void:
	_actor.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(ProjectSettings.globalize_path("res://design/previews/%s.png" % label))
		print("EXIT_SHOT res://design/previews/%s.png" % label)
	_actor.set_physics_process(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("EXIT_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CORRIDOR_EXIT_OK map=open selectable=2 picked=gas_station day=1 sediment=1 fuel_gate=blocked")
		quit(0)
		return
	print("CORRIDOR_EXIT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
