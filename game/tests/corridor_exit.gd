extends SceneTree
## 出口门禁：走到尽头 → 选楼面板（按 TravelService 的门槛）→ 选一栋 → 结算翻页；
## 以及「燃料不够」的选项必须被挡住且不结算。
## 运行（要渲染，抓一张选楼面板）：
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

	# ① 没到出口：没有提示，按 E 也不开面板
	await _place(300.0, 128.0)
	_check(not _corridor._at_exit, "mid-corridor must not count as the exit")
	await _press(KEY_E)
	_check(not _corridor._exit_choice_open, "pressing E away from the exit must not open the chooser")
	_check(day.day == 0, "no settlement away from the exit")

	# ② 走到尽头 → 按 E → 打开选楼面板，列出学校的邻居
	await _place(600.0, 128.0)
	_check(_corridor._at_exit, "the far end must arm the exit")
	await _press(KEY_E)
	_check(_corridor._exit_choice_open, "leaving must open the building chooser")
	var choices: Array = _corridor._exit_choices
	_check(choices.size() == 2, "school must offer 2 neighbours, got %d" % choices.size())
	var ids: Array[String] = []
	for choice: Dictionary in choices:
		ids.append(str(choice["id"]))
		_check(bool(choice["ok"]), "%s should be reachable on day 0" % str(choice["id"]))
	_check("gas_station" in ids, "gas_station must be reachable from school")
	await _capture("%s_choices" % _prefix)

	# ③ 上下移动 + 取消
	_corridor._move_exit_choice(1)
	_check(_corridor._exit_choice_index == 1, "down must move the cursor")
	_corridor._move_exit_choice(-1)
	_check(_corridor._exit_choice_index == 0, "up must move the cursor back")
	await _press(KEY_ESCAPE)
	_check(not _corridor._exit_choice_open, "Esc must close the chooser without settling")
	_check(day.day == 0, "cancelling must not settle the day")

	# ④ 选学校->加油站：结算翻页、换楼、回入口
	await _place(600.0, 128.0)
	await _press(KEY_E)
	var gas_index := -1
	for index in range(_corridor._exit_choices.size()):
		if str((_corridor._exit_choices[index] as Dictionary)["id"]) == "gas_station":
			gas_index = index
	_check(gas_index >= 0, "gas_station must be in the chooser")
	if gas_index >= 0:
		while _corridor._exit_choice_index != gas_index:
			_corridor._move_exit_choice(1)
		await _press(KEY_E)
	_check(not _corridor._exit_choice_open, "confirming must close the chooser")
	_check(day.day == 1, "one outing must advance to day 1, got %d" % day.day)
	_check(day.sediment == 1, "an extracted day must add 1 sediment, got %d" % day.sediment)
	_check(str(_corridor._current_building) == "gas_station", "the run must move to gas_station")
	_check(_actor.position.x < 60.0, "the player must be back at the entrance, got %s" % str(_actor.position))
	_check(_corridor._inspection_open, "settlement panel must open after the trip")
	_check(str(_corridor._inspection_panel_root.get_meta("inspection_id", "")) == "exit",
		"settlement panel must be tagged as the exit")
	await _press(KEY_ESCAPE)

	# ⑤ 燃料门槛：在加油站，医院要 1 燃料，手上 0 → 选项灰掉且不结算
	_corridor._fuel = 0
	await _place(600.0, 128.0)
	await _press(KEY_E)
	_check(_corridor._exit_choice_open, "chooser must reopen at the new building")
	var hospital_index := -1
	for index in range(_corridor._exit_choices.size()):
		var choice: Dictionary = _corridor._exit_choices[index]
		if str(choice["id"]) == "hospital":
			hospital_index = index
			_check(not bool(choice["ok"]), "hospital must be blocked without fuel")
			_check(str(choice["reason"]) == "not_enough_fuel", "wrong block reason: %s" % str(choice["reason"]))
	if hospital_index >= 0:
		while _corridor._exit_choice_index != hospital_index:
			_corridor._move_exit_choice(1)
		var before_day: int = day.day
		await _press(KEY_E)
		_check(day.day == before_day, "a blocked choice must not settle the day")
		_check(_corridor._exit_choice_open, "a blocked choice must keep the chooser open")
		_check(str(_corridor._combat_message).contains("燃料"), "blocked choice should explain why")
	_corridor._close_exit_choices()

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
		print("CORRIDOR_EXIT_OK chooser=2 picked=gas_station day=1 sediment=1 fuel_gate=blocked")
		quit(0)
		return
	print("CORRIDOR_EXIT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
