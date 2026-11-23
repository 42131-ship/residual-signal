extends SceneTree
## 出口门禁：走到尽头 → 提示 → E 离场 → 结算翻页；再来一次能连翻两天。
## 运行（要渲染，抓一张结算面板）：
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

	# ① 没到出口就没有提示，按 E 也不结算
	await _place(300.0, 128.0)
	_check(not _corridor._at_exit, "mid-corridor must not count as the exit")
	await _press(KEY_E)
	_check(day.day == 0, "pressing E away from the exit must not settle the day")

	# ② 走到尽头 → 提示亮起
	await _place(600.0, 128.0)
	_check(_corridor._at_exit, "the far end must arm the exit")
	await process_frame
	await RenderingServer.frame_post_draw

	# ③ 按 E 离场 → 结算面板 + 翻页 + 沉积 +1
	await _press(KEY_E)
	_check(_corridor._inspection_open, "leaving must open the settlement panel")
	_check(str(_corridor._inspection_panel_root.get_meta("inspection_id", "")) == "exit",
		"settlement panel must be tagged as the exit")
	_check(day.day == 1, "one extracted day must advance to day 1, got %d" % day.day)
	_check(day.sediment == 1, "an extracted day must add 1 sediment, got %d" % day.sediment)
	_check(not _corridor._at_exit, "leaving must disarm the exit prompt")
	await _capture("%s_settlement" % _prefix)

	# ④ 关掉面板，再走一次，能连翻到第 2 天
	await _press(KEY_ESCAPE)
	_check(not _corridor._inspection_open, "Esc must close the settlement panel")
	await _place(600.0, 128.0)
	await _press(KEY_E)
	_check(day.day == 2, "a second exit must advance to day 2, got %d" % day.day)
	_check(day.sediment == 2, "second extracted day must be sediment 2, got %d" % day.sediment)
	await _press(KEY_ESCAPE)

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
		print("CORRIDOR_EXIT_OK days=2 sediment=2 panel=ok")
		quit(0)
		return
	print("CORRIDOR_EXIT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
