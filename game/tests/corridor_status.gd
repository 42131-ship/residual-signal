extends SceneTree
## 状态系统在走廊里的落地门禁：抓伤→伤口、污染食物→中毒/成瘾、对症用药、HUD 与移速。
## 运行（要真实渲染，抓 HUD 截图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_status.gd -- CORRIDOR-STATUS
## 通过输出一行 `CORRIDOR_STATUS_OK ...`。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _actor: Player
var _prefix := "CORRIDOR-STATUS"
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

	var status: StatusService = _corridor._status
	_check(status != null, "corridor did not create a StatusService")
	if status == null:
		return _finish()
	_check(status.ids().size() == 4, "expected four states, got %d" % status.ids().size())

	# ① 被感染体抓伤 → 伤口一级，再抓一级。
	_corridor._on_enemy_attacked(1)
	_check(status.stage_of("wound") == 1, "scratch must raise wound to 1")
	_corridor._on_enemy_attacked(1)
	_check(status.stage_of("wound") == 2, "second scratch must raise wound to 2")

	# ② 搜索/耗时行为推进小时：伤口掉体力，且移速被状态接管。
	var health_before: float = _corridor._health
	_corridor.advance_hours(2.0)
	_check(_corridor._health < health_before, "wound must drain health over hours")
	_check(_actor.status_speed_scale <= 1.0, "status must own the speed scale")

	# ③ 污染食物 → 中毒；止痛片还会成瘾。
	_corridor._inventory.add("expired_milk")
	_corridor._inventory_index = _find_item("expired_milk")
	_corridor._use_selected_item()
	_check(status.has("poison"), "contaminated food must cause poison")
	_corridor._inventory.add("painkillers")
	_corridor._inventory_index = _find_item("painkillers")
	_corridor._use_selected_item()
	_check(status.has("addiction"), "painkillers must cause addiction")
	_check(_actor.status_speed_scale < 1.0, "poison must slow the player down")
	_check(status.noise_multiplier() > 1.0, "addiction must raise noise")

	# ④ 对症用药：绷带治伤口，不对症的药不动别的状态。
	_corridor._inventory.add("bandage")
	_corridor._inventory_index = _find_item("bandage")
	_corridor._use_selected_item()
	_check(not status.has("wound"), "bandage must cure the wound")
	_check(status.has("poison"), "bandage must not cure poison")

	# ⑤ 中毒会自行消退（6 游戏小时）。
	_corridor.advance_hours(7.0)
	_check(not status.has("poison"), "poison must fade after its decay window")

	# ⑥ HUD 真的有状态行，并留下截图。
	_corridor._status.apply("infection")
	_corridor._refresh_hud_stats()
	var summary := status.summary()
	_check(summary.contains("感染"), "summary must list the active infection: %s" % summary)
	_check(_corridor._hud_stats_root.get_child_count() > 0, "HUD stats root stayed empty")
	_actor.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	if shot == null:
		_check(false, "capture failed")
	else:
		shot.save_png(ProjectSettings.globalize_path("res://design/previews/%s_hud.png" % _prefix))
		print("STATUS_SHOT res://design/previews/%s_hud.png" % _prefix)
	_actor.set_physics_process(true)
	_finish()


func _find_item(item_id: String) -> int:
	var ids: Array = _corridor._inventory.ids()
	for index: int in ids.size():
		if str(ids[index]) == item_id:
			return index
	return -1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("STATUS_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CORRIDOR_STATUS_OK states=4 wound=scratch poison=food addiction=pills cure=bandage hud=ok")
		quit(0)
		return
	print("CORRIDOR_STATUS_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
