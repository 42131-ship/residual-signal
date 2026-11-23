extends SceneTree
## Stage 2 检查框门禁：真图形渲染 + 真实按键事件。
## 运行（不能加 --headless，否则读不到帧）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_inspect.gd -- CORRIDOR-INSPECT
##
## 覆盖：数据↔节点一一对应、28px 边界含/不含、同距朝向裁决、15 条文本逐条打开、
## 中文与按键提示真的落到像素上、Esc/E 关闭、按住与重复不重复开、面板期间锁移动。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const DATA := "res://data/prop_inspections.json"
const VIEW_SIZE := Vector2i(384, 216)

var _corridor: Node2D
var _actor: Player
var _records: Dictionary = {}
var _order: Array[String] = []
var _prefix := "CORRIDOR-INSPECT"
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
	if _actor == null:
		_check(false, "player missing")
		return _finish()
	await process_frame
	await process_frame

	_verify_catalog()
	if not _failures.is_empty():
		return _finish()

	await _verify_boundary()
	await _verify_ties()
	await _verify_all_records()
	await _verify_hold_and_lock()
	await _capture_open_panel()
	_finish()


# ── 数据与节点 ────────────────────────────────────────────────

func _verify_catalog() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_check(parsed is Dictionary, "inspection JSON unreadable")
	if not parsed is Dictionary:
		return
	_check(str(parsed.get("schema")) == "corridor-inspections.v1", "unexpected schema")
	var range_value := float(parsed.get("interaction_range_x", -1))
	_check(is_equal_approx(range_value, 28.0), "range must stay 28px, got %s" % range_value)
	var records: Array = parsed.get("records", [])
	_check(records.size() == 15, "expected 15 records, got %d" % records.size())
	var props := _corridor.get_node_or_null("Props")
	_check(props != null, "Props node missing")
	if props == null:
		return
	_check(props.get_child_count() == 15, "expected 15 prop nodes, got %d" % props.get_child_count())
	for value: Variant in records:
		if not value is Dictionary:
			_check(false, "record is not an object")
			continue
		var record: Dictionary = value
		var id := str(record.get("id", ""))
		var title := str(record.get("title", ""))
		var lines: Array = record.get("lines", [])
		_check(not id.is_empty() and not title.is_empty(), "record without id/title")
		_check(lines.size() == 2, "%s must carry exactly two lines" % id)
		for line: Variant in lines:
			_check(line is String and not str(line).is_empty(), "%s has an empty line" % id)
		_check(props.get_node_or_null(NodePath(id)) is Sprite2D, "%s has no Sprite2D" % id)
		_records[id] = record
		_order.append(id)


# ── 边界：44 进（28px，含），43 不进（29px）────────────────────

func _verify_boundary() -> void:
	# wall_clock_stopped 中心 x=80，focus_offset_x=-8 → 锚点 72。
	await _place(43.0)
	_check(_corridor._nearest_inspection_id() == "", "x=43 (29px) must be out of range")
	_check(not _corridor._inspection_prompt_root.visible, "prompt must stay hidden at x=43")

	await _place(44.0)
	_check(_corridor._nearest_inspection_id() == "wall_clock_stopped", "x=44 (28px) must target the clock")
	_check(_corridor._inspection_prompt_root.visible, "prompt must be visible at x=44")
	_check(str(_corridor._inspection_prompt_root.get_meta("target_id", "")) == "wall_clock_stopped",
		"prompt must name the clock")

	# 空按 E：范围外不能打开，也不能沿用上一次对象。
	await _place(4.0)
	await _press(KEY_E)
	_check(not _corridor._inspection_open, "E outside any range must not open a panel")


# ── 同距裁决：x=80 / x=288 / x=520 / x=536 ───────────────────

func _verify_ties() -> void:
	await _place(80.0)
	_actor.facing_x = 1.0
	await process_frame
	_check(_corridor._nearest_inspection_id() == "locker_bank", "x=80 facing right must pick the locker")
	_actor.facing_x = -1.0
	await process_frame
	_check(_corridor._nearest_inspection_id() == "wall_clock_stopped", "x=80 facing left must pick the clock")

	await _place(288.0)
	_actor.facing_x = 1.0
	await process_frame
	_check(_corridor._nearest_inspection_id() == "chair_toppled", "x=288 facing right must pick the chair")
	_actor.facing_x = -1.0
	await process_frame
	_check(_corridor._nearest_inspection_id() == "window_night", "x=288 facing left must pick the window")

	await _place(520.0)
	_actor.facing_x = 1.0
	await process_frame
	_check(_corridor._nearest_inspection_id() == "drinking_fountain", "x=520 facing right must pick the fountain")
	_actor.facing_x = -1.0
	await process_frame
	_check(_corridor._nearest_inspection_id() == "intercom_broken", "x=520 facing left must pick the intercom")

	await _place(536.0)
	_actor.facing_x = 1.0
	await process_frame
	_check(_corridor._nearest_inspection_id() == "notice_board_torn", "x=536 facing right must pick the notice board")
	_actor.facing_x = -1.0
	await process_frame
	_check(_corridor._nearest_inspection_id() == "drinking_fountain", "x=536 facing left must pick the fountain")


# ── 15 条逐条打开 ─────────────────────────────────────────────

func _verify_all_records() -> void:
	for id: String in _order:
		var record: Dictionary = _records[id]
		var anchor := await _focus_x(id)
		await _place(anchor)
		await _press(KEY_E)
		_check(_corridor._inspection_open, "%s did not open" % id)
		var shown := str(_corridor._inspection_panel_root.get_meta("inspection_id", ""))
		_check(shown == id, "%s opened %s instead" % [id, shown])
		_check(_corridor._inspection_panel_root.visible, "%s panel hidden after open" % id)
		_check(_actor._movement_locked, "%s did not lock movement" % id)
		await _press(KEY_ESCAPE)
		_check(not _corridor._inspection_open, "%s did not close on Esc" % id)
		_check(not _corridor._inspection_panel_root.visible, "%s panel still visible" % id)
		_check(not _actor._movement_locked, "%s did not unlock movement" % id)
		# 文案必须逐字来自数据。
		_check(str(record.get("title", "")).length() > 0, "%s lost its title" % id)


# ── 按住 / 重复 / 锁移动 ─────────────────────────────────────

func _verify_hold_and_lock() -> void:
	var anchor := await _focus_x("desk_flipped")
	await _place(anchor)
	var before := _actor.global_position.x

	# 键盘重复（echo）不能当第二次按下。
	await _send_key(KEY_E, true, true)
	await process_frame
	_check(not _corridor._inspection_open, "echo press must be ignored")

	await _press(KEY_E)
	_check(_corridor._inspection_open, "normal press must open")

	# 按住不放：持续多帧也只开一个面板。
	for _frame in range(30):
		await process_frame
	_check(_corridor._inspection_open, "holding E must keep a single panel")
	_check(is_equal_approx(str(_corridor._inspection_panel_root.get_meta("inspection_id", "")).length() > 0, true),
		"panel lost its id")

	# 面板开着时按方向键，玩家不能移动。
	Input.action_press("move_right")
	for _frame in range(20):
		await physics_frame
	Input.action_release("move_right")
	_check(absf(_actor.global_position.x - before) < 0.5,
		"player moved %.2fpx while the panel was open" % absf(_actor.global_position.x - before))

	await _press(KEY_E)
	_check(not _corridor._inspection_open, "second E must close the panel")

	# 关掉之后必须能重新走，并且不会立刻弹回面板。
	Input.action_press("move_right")
	for _frame in range(12):
		await physics_frame
	Input.action_release("move_right")
	_check(_actor.global_position.x > before + 1.0, "movement did not resume after closing")
	_check(not _corridor._inspection_open, "panel reopened by itself")
	# 走开一点，避免下一段截图停在道具堆里。
	await _place(200.0)


# ── 中文与按键提示真的落像素 ─────────────────────────────────

func _capture_open_panel() -> void:
	# trash_bin 的正文是全表最长的一行（12 字 = 144px），最容易裁切。
	await _place(await _focus_x("trash_bin"))
	await _press(KEY_E)
	_check(_corridor._inspection_open, "panel must be open before capture")
	_actor.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.get_size() != VIEW_SIZE:
		_check(false, "capture is not native 384x216")
		_actor.set_physics_process(true)
		return
	var path := "res://design/previews/%s_panel.png" % _prefix
	image.save_png(ProjectSettings.globalize_path(path))

	var title_ink := _ink_pixels(image, Rect2i(16, 156, 200, 14))
	var body_ink := _ink_pixels(image, Rect2i(16, 172, 220, 30))
	var esc_ink := _ink_pixels(image, Rect2i(322, 156, 46, 14))
	_check(title_ink > 80, "Chinese title barely rendered: %d ink px" % title_ink)
	_check(body_ink > 160, "two Chinese body lines barely rendered: %d ink px" % body_ink)
	_check(esc_ink > 20, "ESC hint missing: %d ink px" % esc_ink)
	print("PANEL_INK title=%d body=%d esc=%d shot=%s" % [title_ink, body_ink, esc_ink, path])

	# 面板不能盖到最底部（信封图标 y=195..200 那一带留给 HUD 原有元素）。
	_check(_ink_pixels(image, Rect2i(16, 210, 340, 5)) < 40, "panel bleeds past the bottom edge")

	await _press(KEY_ESCAPE)
	await process_frame
	await RenderingServer.frame_post_draw
	var closed := root.get_texture().get_image()
	_check(closed != null, "post-Esc capture failed")
	if closed != null:
		closed.save_png(ProjectSettings.globalize_path("res://design/previews/%s_closed.png" % _prefix))
		var still := _ink_pixels(closed, Rect2i(16, 172, 220, 30))
		_check(still < body_ink / 4, "body text still on screen after Esc: %d" % still)
	_actor.set_physics_process(true)


# ── 工具 ─────────────────────────────────────────────────────

func _focus_x(id: String) -> float:
	var prop := _corridor.get_node_or_null("Props/" + id) as Sprite2D
	var record: Dictionary = _records.get(id, {})
	if prop == null:
		return 0.0
	return prop.global_position.x + float(record.get("focus_offset_x", 0.0))


func _place(x: float) -> void:
	_actor.global_position = Vector2(x, 128.0)
	_actor.velocity = Vector2.ZERO
	await process_frame
	await process_frame


func _send_key(keycode: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame


func _press(keycode: Key) -> void:
	await _send_key(keycode, true, false)
	await _send_key(keycode, false, false)
	await process_frame


func _ink_pixels(image: Image, area: Rect2i) -> int:
	var count := 0
	var limit := Rect2i(Vector2i.ZERO, VIEW_SIZE)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if not limit.has_point(Vector2i(x, y)):
				continue
			var pixel := image.get_pixel(x, y)
			# 面板底色是 #0b1119；文字用 #9fb2bd / #f6f6f0，亮度差足够区分。
			if pixel.get_luminance() > 0.28:
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("INSPECT_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CORRIDOR_INSPECT_OK records=%d ties=8 boundary=28px" % _order.size())
		quit(0)
		return
	Input.action_release("move_right")
	print("CORRIDOR_INSPECT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
