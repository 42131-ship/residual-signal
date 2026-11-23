extends SceneTree
## 可达性门禁：只用 WASD/方向键（不瞬移），验证玩家能走遍可走地面带的四个角与中心。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/traverse.gd
## 通过输出一行 `TRAVERSE_OK ...`。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const BOUNDS := Rect2(14.0, 128.0, 588.0, 88.0)

var _corridor: Node2D
var _actor: Player


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	_actor = _corridor.get_node_or_null("Player") as Player
	await process_frame
	await process_frame
	if _actor == null:
		_fail("player missing")
		return

	# 可达目标：四角 + 中心（当前 demo 是一条连续房间带，还没有分隔墙）。
	var waypoints := [
		{"x": BOUNDS.end.x, "y": BOUNDS.position.y, "label": "right_top"},
		{"x": BOUNDS.end.x, "y": BOUNDS.end.y, "label": "right_bottom"},
		{"x": BOUNDS.position.x, "y": BOUNDS.end.y, "label": "left_bottom"},
		{"x": BOUNDS.position.x, "y": BOUNDS.position.y, "label": "left_top"},
		{"x": 320.0, "y": 172.0, "label": "center"},
	]
	for point: Dictionary in waypoints:
		if not await _move_towards(float(point["x"]), float(point["y"]), str(point["label"])):
			return

	# 边界不泄漏：故意朝四个方向顶满，仍必须留在矩形内。
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_press(action)
		for _frame in range(240):
			await physics_frame
		Input.action_release(action)
		if not BOUNDS.grow(0.6).has_point(_actor.global_position):
			_fail("%s leaked outside walkable bounds: %s" % [action, str(_actor.global_position)])
			return

	print("TRAVERSE_OK waypoints=%d bounds=%.0fx%.0f corners=4 center=1 leaks=0" % [
		waypoints.size(), BOUNDS.size.x, BOUNDS.size.y])
	_cleanup()
	quit(0)


func _cleanup() -> void:
	if _corridor != null and is_instance_valid(_corridor):
		_corridor.free()
		_corridor = null


func _move_towards(target_x: float, target_y: float, label: String) -> bool:
	var budget := 6000
	while budget > 0:
		budget -= 1
		var dx := target_x - _actor.global_position.x
		var dy := target_y - _actor.global_position.y
		if absf(dx) <= 1.5 and absf(dy) <= 1.5:
			break
		_release_moves()
		if dx > 1.5:
			Input.action_press("move_right")
		elif dx < -1.5:
			Input.action_press("move_left")
		if dy > 1.5:
			Input.action_press("move_down")
		elif dy < -1.5:
			Input.action_press("move_up")
		await physics_frame
	_release_moves()
	await physics_frame
	if absf(_actor.global_position.x - target_x) > 3.0 or absf(_actor.global_position.y - target_y) > 3.0:
		_fail("could not reach %s: %s" % [label, str(_actor.global_position)])
		return false
	return true


func _release_moves() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)


func _fail(detail: String) -> void:
	_release_moves()
	_cleanup()
	push_error("TRAVERSE_FAIL " + detail)
	print("TRAVERSE_FAIL " + detail)
	quit(1)
