extends SceneTree
## 主界面门禁：三项菜单、可移动可确认、结局栏四槽且未解锁不剧透、解锁后显示标题。
## 运行（要渲染，抓两张界面图）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/main_menu.gd -- MENU

const SCENE: PackedScene = preload("res://game/scenes/main_menu.tscn")

var _menu: Node2D
var _prefix := "MENU"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("MENU"):
			_prefix = argument
	# 门禁必须控制前置条件：先清掉上一次跑测试留下的存档，否则「继续」会读到它。
	RunState.current = null
	if FileAccess.file_exists(RunState.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))
	_menu = SCENE.instantiate() as Node2D
	root.add_child(_menu)
	await process_frame
	await process_frame
	_check(_menu.view_name() == "root", "menu must start on the root view")
	_check(_menu.current_index() == 0, "cursor must start on the first entry")

	# ⓪ 生图背景已落地：KeyArt 引用量化后的图，Scrim 铺满视口保证文字对比度
	var art := _menu.get_node_or_null("KeyArt") as Sprite2D
	_check(art != null, "quantized key art must be mounted behind the menu")
	if art != null:
		_check(art.texture != null, "key art has no texture")
		if art.texture != null:
			_check(str(art.texture.resource_path).ends_with("maps/menu_bg.png"),
				"key art must use the quantized map, got %s" % art.texture.resource_path)
			_check(art.texture.get_size() == Vector2(384, 216), "key art must be 384x216")
		_check(not art.centered, "key art must be top-left anchored")
	var scrim := _menu.get_node_or_null("Scrim") as ColorRect
	_check(scrim != null, "a scrim must sit between the art and the text")
	if scrim != null:
		_check(scrim.size == Vector2(384, 216), "scrim must cover the viewport")
		_check(scrim.color.a > 0.3 and scrim.color.a < 0.8, "scrim alpha must stay in a readable range")
	await _capture("%s_root" % _prefix)

	# ① 选择项数量与顺序：新游戏 / 继续 / 结局栏
	var items: Array = _menu.ITEMS
	_check(items.size() == 3, "menu must hold 3 entries, got %d" % items.size())
	_check(items[0] == "新游戏" and items[1] == "继续" and items[2] == "结局栏",
		"entries must be 新游戏/继续/结局栏, got %s" % str(items))

	# ② 上下移动是循环的
	_menu.move(1)
	_check(_menu.current_index() == 1, "moving down must reach index 1")
	_menu.move(1)
	_check(_menu.current_index() == 2, "moving down must reach index 2")
	_menu.move(1)
	_check(_menu.current_index() == 0, "cursor must wrap back to 0")

	# ③ 没有进度时「继续」不能假装能继续
	_menu.move(1)
	_menu.confirm()
	_check(_menu.current_index() == 1, "cursor stays on 继续")
	_check(_menu.run_state().day == 0, "a missing run must not fabricate a day")

	# ④ 新游戏重置一局（但不清结局档案）
	_menu.run_state().unlock_ending("school", "military")
	_menu.run_state().day = 7
	_menu.move(-1)
	_menu.confirm()
	var run: RunState = _menu.run_state()
	_check(run.day == 0 and run.sediment == 0, "new game must reset day and sediment")
	_check(run.building == "school", "new game must start at school")
	_check(run.unlocked_for("school").has("military"), "new game must keep unlocked endings")

	# ⑤ 结局栏：四个槽，未解锁只给占位
	_menu.move(2)
	_menu.confirm()
	_check(_menu.view_name() == "endings", "结局栏 must open")
	var book: EndingBook = _menu.ending_book()
	_check(book.slot_count("school") == 4, "school must expose 4 slots")
	var rows := book.entries("school")
	_check(rows.size() == 4, "gallery must list 4 rows, got %d" % rows.size())
	var locked_rows := 0
	for row: Dictionary in rows:
		if not bool(row["unlocked"]):
			locked_rows += 1
			_check(str(row["label"]) == "？？？", "locked row leaks its title: %s" % str(row["label"]))
			_check(not str(row["summary"]).contains("直升机"), "locked row leaks its summary")
	_check(locked_rows == 3, "exactly the three unearned endings must be masked, got %d" % locked_rows)
	await _capture("%s_endings" % _prefix)

	# ⑥ Esc 返回主菜单
	var back := InputEventKey.new()
	back.physical_keycode = KEY_ESCAPE
	back.keycode = KEY_ESCAPE
	back.pressed = true
	_menu._unhandled_input(back)
	await process_frame
	_check(_menu.view_name() == "root", "Esc must return to the root view")

	if not _failures.is_empty():
		print("MENU_FAILED count=%d" % _failures.size())
		for failure: String in _failures:
			print("  - " + failure)
		quit(1)
		return
	print("MENU_OK entries=3 wrap=yes endings_slots=4 masked=3 unlock=kept_on_new_game")
	quit(0)


func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		_check(false, "capture failed at " + label)
		return
	image.save_png(ProjectSettings.globalize_path("res://design/previews/%s.png" % label))
	print("MENU_SHOT res://design/previews/%s.png" % label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("MENU_FAIL " + message)
