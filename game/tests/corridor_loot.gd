extends SceneTree
## 可搜索柜门禁（真渲染）：两个柜子用 E 搜索，同一天第二次显示「翻过」，面板可关。
## 运行（不能加 --headless，要截图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_loot.gd -- CORRIDOR-LOOT
## 通过输出一行 `CORRIDOR_LOOT_OK ...`。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const VIEW_SIZE := Vector2i(384, 216)
const CONTAINERS := {
	"locker_bank": {"x": 80.0, "y": 136.0, "label": "储物柜"},
	"first_aid_cabinet": {"x": 416.0, "y": 136.0, "label": "急救柜"},
}

var _corridor: Node2D
var _actor: Player
var _prefix := "CORRIDOR-LOOT"
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

	for id: String in CONTAINERS:
		var spec: Dictionary = CONTAINERS[id]
		await _place(float(spec["x"]), float(spec["y"]))
		_check(_corridor._nearest_inspection_id() == id, "%s is not the nearest target" % id)
		await _press(KEY_E)
		_check(_corridor._inspection_open, "%s search did not open a panel" % id)
		_check(str(_corridor._inspection_panel_root.get_meta("inspection_id", "")) == id,
			"%s panel shows the wrong container" % id)
		_check(_actor._movement_locked, "%s search did not lock movement" % id)
		if id == "locker_bank":
			await _capture("%s_panel" % _prefix)
		await _press(KEY_ESCAPE)
		_check(not _corridor._inspection_open, "%s panel did not close on Esc" % id)

	# 同一天第二次搜同一个柜子：必须显示「今天已经翻过」，而不是再给一份物资。
	await _place(float(CONTAINERS["locker_bank"]["x"]), float(CONTAINERS["locker_bank"]["y"]))
	await _press(KEY_E)
	_check(_corridor._inspection_open, "second search did not open the refusal panel")
	_check(_corridor._panel_lines.has("今天已经翻过"),
		"second same-day search should be refused, panel lines=%s" % str(_corridor._panel_lines))
	await _press(KEY_E)
	_check(not _corridor._inspection_open, "E should also close the panel")
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
	print("LOOT_SHOT %s" % path)
	_actor.set_physics_process(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("LOOT_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CORRIDOR_LOOT_OK containers=%d refresh=per_day panel=ok" % CONTAINERS.size())
		quit(0)
		return
	print("CORRIDOR_LOOT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
