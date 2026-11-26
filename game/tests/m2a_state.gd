extends SceneTree
## M2a 门禁：物资的真源是 world_state，RunState 只是存档镜像，两边不许漂移。
## 运行（要渲染，抓一张 HUD）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/m2a_state.gd -- M2A

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _prefix := "M2A"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("M2A"):
			_prefix = argument
	RunState.current = null
	RunState.clear_saved()

	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	await process_frame
	await process_frame

	# ① world_state 必须在线，且开局的物资已经灌进去
	_check(_corridor.supplies_online(), "corridor must run with world_state online")
	var state: WorldState = _corridor._state
	_check(state != null, "world_state missing")
	if state == null:
		return _finish()
	_check(is_equal_approx(state.var_of("supplies"), _corridor._get_supplies()),
		"world_state and accessor disagree at boot")
	_check(is_equal_approx(state.var_of("supplies"), 0.8), "fresh run should start at 0.8 supplies")

	# ② 用药 -> world_state 上涨，访问器与镜像同步；且必须走 add_var（changed 信号）
	var emissions: Array = []
	state.changed.connect(func(name: String, old_value: float, new_value: float) -> void:
		if name == "supplies":
			emissions.append([old_value, new_value]))
	var before: float = state.var_of("supplies")
	_corridor._inventory.add("bottled_water")
	_corridor._inventory_index = _find_item("bottled_water")
	_corridor._use_selected_item()
	var after: float = state.var_of("supplies")
	_check(after > before, "drinking water must raise world_state.supplies (%.3f -> %.3f)" % [before, after])
	_check(not emissions.is_empty(), "supplies change must go through add_var (changed signal)")
	if not emissions.is_empty():
		var last: Array = emissions[emissions.size() - 1]
		_check(is_equal_approx(float(last[0]), before), "changed() old value must be the pre-drink value")
		_check(is_equal_approx(float(last[1]), after), "changed() new value must be the post-drink value")
	_check(is_equal_approx(_corridor._get_supplies(), after), "accessor must read world_state")
	_check(is_equal_approx(RunState.current.supplies, after), "RunState mirror must follow world_state")

	# ②b 增量语义：两次 +0.05 必须等于一次 +0.1（不是覆盖写）
	var base: float = state.var_of("supplies")
	if base > 0.85:
		_corridor._set_supplies(0.5)
		base = state.var_of("supplies")
	_corridor._add_supplies(0.05)
	_corridor._add_supplies(0.05)
	_check(absf(state.var_of("supplies") - (base + 0.1)) < 0.001,
		"two +0.05 adds must equal +0.1, got %.3f from %.3f" % [state.var_of("supplies"), base])

	# ③ 结算后仍然一致（结算会改物资）
	var actor := _corridor.get_node_or_null("Player") as Player
	actor.global_position = Vector2(600.0, 128.0)
	actor.velocity = Vector2.ZERO
	await process_frame
	await process_frame
	await _press(KEY_E)
	if _corridor._map_open:
		var guard := 0
		while str(_corridor._map.selected_id()) != "gas_station" and guard < 8:
			_corridor._map.move(1)
			guard += 1
		await _press(KEY_E)
	_check(is_equal_approx(state.var_of("supplies"), _corridor._get_supplies()),
		"after settlement world_state and accessor must agree")
	_check(is_equal_approx(RunState.current.supplies, state.var_of("supplies")),
		"after settlement the mirror must equal the source")

	# ④ 夹取：写超界也不许出 0..1
	_corridor._set_supplies(3.0)
	_check(state.var_of("supplies") <= 1.0, "supplies must clamp at 1")
	_corridor._set_supplies(-2.0)
	_check(state.var_of("supplies") >= 0.0, "supplies must clamp at 0")

	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	if shot != null:
		shot.save_png(ProjectSettings.globalize_path("res://design/previews/%s_hud.png" % _prefix))
		print("M2A_SHOT res://design/previews/%s_hud.png" % _prefix)
	_finish()


func _find_item(item_id: String) -> int:
	var ids: Array = _corridor._inventory.ids()
	for index in range(ids.size()):
		if str(ids[index]) == item_id:
			return index
	return -1


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


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("M2A_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("M2A_OK source=world_state mirror=run_state drink=rises settle=in_sync clamp=0..1")
		quit(0)
		return
	print("M2A_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
