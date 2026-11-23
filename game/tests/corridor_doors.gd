extends SceneTree
## 门门禁（真渲染）：初始常开、E 开关、关闭挡路、挂锁上锁、钥匙开锁。
## 运行（不能加 --headless，要截图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_doors.gd -- CORRIDOR-DOOR
## 通过输出一行 `CORRIDOR_DOORS_OK ...`。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _actor: Player
var _prefix := "CORRIDOR-DOOR"
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
		_finish()
		return

	var doors: Array = _corridor._doors
	_check(doors.size() == 2, "expected 2 doors, got %d" % doors.size())
	if doors.size() != 2:
		_finish()
		return
	var door: Dictionary = doors[0]
	var center := float(door["center_x"])
	_check(bool(door["open"]), "doors should start open")
	_check((door["shape"] as CollisionShape2D).disabled, "open door should have collision disabled")

	# ① 开着的门不挡路。
	await _place(center - 70.0)
	var passed := await _walk_right_until(center + 26.0, 400)
	_check(passed, "open door blocked the player (x=%.1f)" % _actor.global_position.x)
	if not passed:
		_finish()
		return

	# ② 靠近 → E 关门：碰撞开启、提示变化、截图。
	await _place(center - 34.0)
	_check(str(_corridor._door_prompt_text).contains("关门"),
		"prompt should offer closing, got %s" % str(_corridor._door_prompt_text))
	await _press(KEY_E)
	_check(not bool(door["open"]), "E did not close the door")
	_check(not (door["shape"] as CollisionShape2D).disabled, "closed door must enable collision")
	_check(str(_corridor._door_prompt_text).contains("开门"),
		"prompt should offer opening, got %s" % str(_corridor._door_prompt_text))
	await _capture("%s_closed" % _prefix)

	# ③ 关着的门挡路。
	await _place(center - 30.0)
	var blocked := await _walk_right_until(center - 4.0, 160)
	_check(not blocked and _actor.global_position.x < center - 4.0,
		"closed door did not block the player (x=%.1f)" % _actor.global_position.x)

	# ④ 再开、穿过去。
	await _place(center - 34.0)
	await _press(KEY_E)
	_check(bool(door["open"]), "E did not reopen the door")
	await _place(center - 70.0)
	_check(await _walk_right_until(center + 26.0, 400), "reopened door still blocks")

	# ⑤ 挂锁锁门：关闭后 E 上锁，消耗挂锁，锁着的门挡路、提示「锁着」。
	await _place(center - 34.0)
	await _press(KEY_E)  # 关
	_corridor._inventory.add("padlock")
	await _press(KEY_E)  # 锁
	_check(bool(door["locked"]), "padlock did not lock the door")
	_check(not _corridor._inventory.has("padlock"), "padlock was not consumed")
	_check(str(_corridor._door_prompt_text).contains("锁着"),
		"locked prompt should say locked, got %s" % str(_corridor._door_prompt_text))
	await _place(center - 30.0)
	var locked_blocked := await _walk_right_until(center - 4.0, 160)
	_check(not locked_blocked and _actor.global_position.x < center - 4.0,
		"locked door did not block the player")
	await _capture("%s_locked" % _prefix)

	# ⑥ 钥匙开锁：E 撬开，门打开。
	_corridor._inventory.add("keys")
	_corridor._draw_door_prompt()
	await _place(center - 34.0)
	_check(str(_corridor._door_prompt_text).contains("撬"),
		"key prompt should allow prying, got %s" % str(_corridor._door_prompt_text))
	await _press(KEY_E)
	_check(not bool(door["locked"]) and bool(door["open"]), "keys did not unlock and open the door")
	await _capture("%s_open" % _prefix)
	_finish()


func _walk_right_until(target_x: float, budget: int) -> bool:
	Input.action_press("move_right")
	for _frame in range(budget):
		await physics_frame
		if _actor.global_position.x >= target_x:
			Input.action_release("move_right")
			return true
	Input.action_release("move_right")
	return false


func _place(x: float) -> void:
	_actor.global_position = Vector2(x, 128.0)
	_actor.velocity = Vector2.ZERO
	await process_frame
	await process_frame


func _press(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.keycode = keycode
	down.pressed = true
	_corridor._unhandled_input(down)
	await process_frame
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
	var rendered := root.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		_actor.set_physics_process(true)
		_check(false, "capture failed")
		return
	var path := "res://design/previews/%s.png" % label
	if rendered.save_png(ProjectSettings.globalize_path(path)) != OK:
		_actor.set_physics_process(true)
		_check(false, "could not save " + path)
		return
	print("DOOR_SHOT %s" % path)
	_actor.set_physics_process(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("DOOR_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CORRIDOR_DOORS_OK doors=2 open=默认 close=挡路 lock=padlock unlock=keys screenshots=3")
		quit(0)
		return
	print("CORRIDOR_DOORS_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
