extends SceneTree
## 可搜索柜门禁（真渲染）：E 搜索，面板显示随机件数的物品；剧情模式搜过永久为空。
## 运行（不能加 --headless，要截图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_loot.gd -- CORRIDOR-LOOT
## 通过输出一行 `CORRIDOR_LOOT_OK ...`。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const CONTAINERS := {
	"locker_bank": {"x": 80.0, "y": 136.0},
	"trash_bin": {"x": 384.0, "y": 160.0},
	"first_aid_cabinet": {"x": 416.0, "y": 136.0},
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

	# ① 两个容器都能搜：面板标题正确、锁移动、有随机物品与件数，并截图。
	for id: String in CONTAINERS:
		var spec: Dictionary = CONTAINERS[id]
		await _place(float(spec["x"]), float(spec["y"]))
		_check(_corridor._nearest_inspection_id() == id, "%s is not the nearest target" % id)
		await _search(id)
		_check(_corridor._inspection_open, "%s search did not open a panel" % id)
		_check(str(_corridor._inspection_panel_root.get_meta("inspection_id", "")) == id,
			"%s panel shows the wrong container" % id)
		_check(_actor._movement_locked, "%s search did not lock movement" % id)
		var lines: Array = _corridor._panel_lines
		_check(lines.size() == 2, "%s panel needs two lines, got %s" % [id, str(lines)])
		_check(str(lines[0]).begins_with("找到："), "%s panel missing 找到 prefix: %s" % [id, str(lines)])
		_check(str(lines[1]).contains("背包"),
			"%s panel should mention the backpack: %s" % [id, str(lines)])
		await _capture("%s_%s" % [_prefix, id])
		await _press(KEY_ESCAPE)
		_check(not _corridor._inspection_open, "%s panel did not close on Esc" % id)

	# ② 剧情模式不刷新：搜过的柜子换多少世界日都还是空的。
	await _place(float(CONTAINERS["locker_bank"]["x"]), float(CONTAINERS["locker_bank"]["y"]))
	await _search("locker_bank")
	_check(_corridor._inspection_open, "second search did not open the refusal panel")
	_check(_corridor._panel_lines.has("已经搜过一次"),
		"second search should be refused, panel=%s" % str(_corridor._panel_lines))
	await _press(KEY_ESCAPE)
	_corridor._world_day = 28
	await _search("locker_bank")
	_check(_corridor._panel_lines.has("已经搜过一次"),
		"story mode must not refresh after day change, panel=%s" % str(_corridor._panel_lines))
	_check(_corridor._panel_lines.has("剧情模式不会刷新"),
		"refusal should explain story mode, panel=%s" % str(_corridor._panel_lines))
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


## 按住 E 搜索：Down 起手 → 逐帧推进进度 → 到点结算。松手会中断，所以这里不松。
func _search(container_id: String) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEY_E
	down.keycode = KEY_E
	down.pressed = true
	_corridor._unhandled_input(down)
	_check(not _corridor._search_id.is_empty(), "%s did not start a timed search" % container_id)
	Input.action_press("pickup")
	var required: float = float(_corridor._loot.search_seconds_of(container_id))
	var steps := int(ceil(required / 0.1)) + 3
	var progress_seen := 0.0
	for _i in steps:
		_corridor._update_search(0.1)
		progress_seen = maxf(progress_seen, _corridor._search_elapsed / maxf(0.001, _corridor._search_required))
	Input.action_release("pickup")
	_check(progress_seen > 0.0, "%s search never showed progress" % container_id)
	_check(_corridor._search_id.is_empty(), "%s search did not finish" % container_id)
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
		print("CORRIDOR_LOOT_OK containers=%d story=never panel=ok" % CONTAINERS.size())
		quit(0)
		return
	print("CORRIDOR_LOOT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
