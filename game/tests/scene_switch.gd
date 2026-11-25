extends SceneTree
## 场景切换门禁：出门 -> 结算 -> RunState 落盘 -> 重新加载场景后仍是新楼与新天数。
## 运行（要渲染）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/scene_switch.gd -- SWITCH

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _prefix := "SWITCH"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("SWITCH"):
			_prefix = argument
	# 从干净档案开始，避免上一次运行留下的 user://run.json 影响断言
	RunState.current = null
	if FileAccess.file_exists(RunState.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

	var first := SCENE.instantiate() as Node2D
	root.add_child(first)
	await process_frame
	await process_frame
	_check(str(first._current_building) == "school", "a fresh run must start at school")
	_check(first._day.day == 0, "a fresh run must start on day 0")

	# ① 走到出口 -> 打开地图 -> 选加油站 -> 确认
	var actor := first.get_node_or_null("Player") as Player
	_check(actor != null, "player missing")
	if actor == null:
		return _finish()
	actor.global_position = Vector2(600.0, 128.0)
	actor.velocity = Vector2.ZERO
	await process_frame
	await process_frame
	await _press(first, KEY_E)
	_check(first._map_open, "the travel map must open at the exit")
	if not first._map_open:
		return _finish()
	var guard := 0
	while str(first._map.selected_id()) != "gas_station" and guard < 8:
		first._map.move(1)
		guard += 1
	await _press(first, KEY_E)

	# ② 状态必须写进 RunState 并落盘
	var state := RunState.current
	_check(state != null, "RunState.current must exist")
	if state == null:
		return _finish()
	_check(state.building == "gas_station", "RunState.building must move to gas_station, got %s" % state.building)
	_check(state.day == 1, "RunState.day must advance to 1, got %d" % state.day)
	_check(state.sediment == 1, "sediment must be 1, got %d" % state.sediment)
	_check(state.visited.has("school") and state.visited.has("gas_station"), "visited must record both buildings")
	_check(FileAccess.file_exists(RunState.SAVE_PATH), "run must be saved to disk")
	var reloaded := RunState.load_saved()
	_check(reloaded != null, "saved run must load back")
	if reloaded != null:
		_check(reloaded.building == "gas_station", "saved building mismatch: %s" % reloaded.building)
		_check(reloaded.day == 1, "saved day mismatch: %d" % reloaded.day)
		_check(reloaded.visited.has("gas_station"), "saved visited lost gas_station")

	# ③ 模拟「重新加载场景」：新建一个走廊，必须读到新楼与新天数
	var second := SCENE.instantiate() as Node2D
	root.add_child(second)
	await process_frame
	await process_frame
	_check(str(second._current_building) == "gas_station", "reloaded scene must resume at gas_station")
	_check(second._day.day == 1, "reloaded scene must resume on day 1, got %d" % second._day.day)
	_check(second._visited.has("school"), "reloaded scene must keep the visit history")
	_check(second.current_building_id() == "gas_station", "public accessor must agree")

	# ④ 从加油站出发：到站补给 +1 后，医院（需 1 燃料）从灰显变为可选；燃料是门槛不消耗
	var actor2 := second.get_node_or_null("Player") as Player
	actor2.global_position = Vector2(600.0, 128.0)
	actor2.velocity = Vector2.ZERO
	await process_frame
	await process_frame
	await _press(second, KEY_E)
	_check(second._map_open, "map must open at the gas station exit")
	if second._map_open:
		var neighbours: Array = second._map.neighbor_ids()
		var allowed: Array = second._map.selectable_ids()
		_check("school" in neighbours, "gas_station must be adjacent to school")
		_check("hospital" in neighbours, "gas_station must be adjacent to hospital")
		_check(int(second._fuel) == 1, "arriving at gas_station must refuel +1, got %d" % second._fuel)
		_check("hospital" in allowed, "hospital must become reachable after refueling at gas_station")
		_check("school" in allowed, "school must stay reachable")
		# 门槛仍有效：燃料归零时医院被挡（服务层直测，不依赖地图已算好的可选集）
		var fuel_gate: Dictionary = second._travel.can_travel("gas_station", "hospital",
			{"fuel": 0, "actions_left": 1, "hour": 12})
		_check(not bool(fuel_gate.get("ok", true)) and str(fuel_gate.get("reason", "")) == "not_enough_fuel",
			"zero fuel must still block hospital")
	await _capture("%s_gas_station" % _prefix)
	_finish()


func _press(node: Node2D, keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.keycode = keycode
	down.pressed = true
	node._unhandled_input(down)
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.keycode = keycode
	up.pressed = false
	node._unhandled_input(up)
	await process_frame


func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(ProjectSettings.globalize_path("res://design/previews/%s.png" % label))
		print("SWITCH_SHOT res://design/previews/%s.png" % label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("SWITCH_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("SCENE_SWITCH_OK school->gas_station day=1 saved=yes reload=gas_station neighbours=3 refuel=1")
		quit(0)
		return
	print("SCENE_SWITCH_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
