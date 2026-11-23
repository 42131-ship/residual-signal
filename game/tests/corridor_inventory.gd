extends SceneTree
## 背包界面门禁（真渲染）：E 搜索入包、Tab 开背包、E 使用、Q 丢弃、左键攻击、Esc/Tab 关闭。
## 运行（不能加 --headless，要截图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_inventory.gd -- CORRIDOR-INV
## 通过输出一行 `CORRIDOR_INVENTORY_OK ...`。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const LOCKER := {"x": 80.0, "y": 136.0}

var _corridor: Node2D
var _actor: Player
var _prefix := "CORRIDOR-INV"
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

	# ① 搜索一个柜子：按住 E 到进度满，物资自动进背包。
	await _place(float(LOCKER["x"]), float(LOCKER["y"]))
	await _search(str(LOCKER.get("id", "locker_bank")))
	_check(_corridor._inspection_open, "search panel did not open")
	var picked: int = _corridor._inventory.total()
	_check(picked >= 1 and picked <= 2, "search should put 1-2 items into the backpack, got %d" % picked)
	_check(str(_corridor._panel_lines[1]).contains("背包"),
		"search panel should mention the backpack: %s" % str(_corridor._panel_lines))
	await _press(KEY_ESCAPE)

	# ② 注入确定性物品，覆盖消耗品 / 用不上 / 武器三类。
	_corridor._inventory.add("bottled_water")
	_corridor._inventory.add("coins")
	_corridor._inventory.add("crowbar")

	# ③ Tab 打开背包：锁移动、截图。
	await _press(KEY_TAB)
	_check(_corridor._inventory_open, "Tab did not open the backpack")
	_check(_actor._movement_locked, "backpack did not lock movement")
	await _capture("%s_panel" % _prefix)

	# ④ 使用瓶装水：物资增加、数量减少。
	var water_index := _find_item("bottled_water")
	_check(water_index >= 0, "bottled_water missing from backpack")
	if water_index >= 0:
		_corridor._inventory_index = water_index
		_corridor._render_inventory()
		var supplies_before: float = _corridor._supplies
		var count_before: int = _corridor._inventory.count_of("bottled_water")
		await _press(KEY_E)
		_check(_corridor._supplies > supplies_before, "using bottled_water did not raise supplies")
		_check(_corridor._inventory.count_of("bottled_water") == count_before - 1,
			"using bottled_water did not consume it")
		_check(_corridor._inventory.has("bottled_water") == false or true, "sanity")

	# ⑤ 用不上的东西：不消耗、提示「用不上」。
	var coins_index := _find_item("coins")
	_check(coins_index >= 0, "coins missing from backpack")
	if coins_index >= 0:
		_corridor._inventory_index = coins_index
		_corridor._render_inventory()
		var coins_before: int = _corridor._inventory.count_of("coins")
		await _press(KEY_E)
		_check(_corridor._inventory.count_of("coins") == coins_before, "unusable item was consumed")
		_check(str(_corridor._inventory_toast).contains("用不上"), "no 'unusable' feedback: %s" % str(_corridor._inventory_toast))

	# ⑥ 装备撬棍：不消耗，标题显示装备。
	var crowbar_index := _find_item("crowbar")
	_check(crowbar_index >= 0, "crowbar missing from backpack")
	if crowbar_index >= 0:
		_corridor._inventory_index = crowbar_index
		_corridor._render_inventory()
		await _press(KEY_E)
		_check(_corridor._equipped == "crowbar", "crowbar was not equipped")
		_check(_corridor._inventory.count_of("crowbar") == 1, "equipping consumed the weapon")

	# ⑦ Q 丢弃：数量减少（背包仍开着）。
	var drop_index := _find_item("crowbar")
	_check(drop_index >= 0, "crowbar missing before drop test")
	if drop_index >= 0:
		_corridor._inventory_index = drop_index
		_corridor._render_inventory()
		var total_before: int = _corridor._inventory.total()
		await _press(KEY_Q)
		_check(_corridor._inventory.total() == total_before - 1, "Q did not drop an item")

	# ⑧ Tab 关闭：解锁移动。
	await _press(KEY_TAB)
	_check(not _corridor._inventory_open, "Tab did not close the backpack")
	_check(not _actor._movement_locked, "closing the backpack did not unlock movement")

	# ⑨ 左键攻击（面板关闭后）：计数增加；已装备近战武器会提高噪声。
	var attacks_before: int = _corridor._attacks
	var noise_before: int = _corridor._noise
	_corridor._unhandled_input(_mouse_left())
	_check(_corridor._attacks == attacks_before + 1, "left click did not trigger an attack")
	_check(_corridor._noise > noise_before, "equipped melee attack should raise noise")
	_finish()


## 按住 E 搜索：起手 → 推进进度 → 到点结算（松手会中断，所以这里不松）。
func _search(container_id: String) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEY_E
	down.keycode = KEY_E
	down.pressed = true
	_corridor._unhandled_input(down)
	Input.action_press("pickup")
	var required: float = float(_corridor._loot.search_seconds_of(container_id))
	var steps := int(ceil(required / 0.1)) + 3
	for _i in steps:
		_corridor._update_search(0.1)
	Input.action_release("pickup")
	_check(_corridor._search_id.is_empty(), "%s search did not finish" % container_id)
	await process_frame


func _find_item(item_id: String) -> int:
	var ids: Array[String] = _corridor._inventory.ids()
	return ids.find(item_id)


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


func _mouse_left() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


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
	print("INV_SHOT %s" % path)
	_actor.set_physics_process(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("INV_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CORRIDOR_INVENTORY_OK search=pickup tab=open use=consume unusable=kept equip=melee attack=left_click drop=q")
		quit(0)
		return
	print("CORRIDOR_INVENTORY_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
