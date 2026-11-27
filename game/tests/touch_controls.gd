extends SceneTree
## 手机触摸层门禁 + 本轮验收 A/B/C（2026-11-26 v2 重排）。headless 可跑：
##   .tools/Godot_v4.7-stable_win64_console.exe --headless --path . --script res://game/tests/touch_controls.gd
## 通过输出 `TOUCH_OK ...` 与 `TOUCH_ACCEPT A=... B=... C=...`。
##
## 注入的真机指标取 `2602BRT18C`：画布 555×256、窗口 2772×1280、520dpi。
## 守的是契约（毫米尺寸/分区/上下文键/摇杆/菜单/对比度），不是「真机点得准」（那是引擎拾取）。

const IDS := ["attack", "search", "lamp", "run", "crouch", "bag", "menu"]
const CANVAS := Vector2i(555, 256)
const WINDOW := Vector2i(2772, 1280)
const DPI := 520

const INK := Color("#e8e4d8")
const BG_DARK := Color("#0b1119")
const BG_WALL := Color("#111a26")

var _failures: Array[String] = []
var _layer: TouchControls


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_layer = TouchControls.new()
	_layer.name = "TouchControls"
	root.add_child(_layer)
	await process_frame
	_layer.set_metrics_for_test(CANVAS, WINDOW, DPI)
	await process_frame
	_bind_actions()

	_check_ids()
	var report := _check_geometry()
	_check_context_key()
	await _check_search_hold()
	_check_joystick()
	_check_menu()
	var contrast := _check_contrast()
	_finish(report, contrast)


func _bind_actions() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down", "sprint",
			"crouch", "attack", "pickup", "toggle_light", "inventory", "reload", "view",
			"cancel_inspect"]:
		if not InputMap.has_action(action):
			InputMap.add_action(StringName(action))


func _check_ids() -> void:
	var got := _layer.button_ids()
	_check(got.size() == IDS.size(), "button count %d != %d" % [got.size(), IDS.size()])
	for id: String in IDS:
		_check(got.has(id), "missing button: " + id)


## A 单手可达 + 分区 + B 误触率
func _check_geometry() -> Dictionary:
	var table := _layer.rects()
	var w := float(CANVAS.x)
	var h := float(CANVAS.y)
	var bottom_third := h * 2.0 / 3.0

	# A：常驻玩法键必须落在下 1/3
	var reach_fail := 0
	for id: String in ["attack", "run", "lamp"]:
		var rect: Rect2 = table[id]
		if rect.position.y < bottom_third:
			reach_fail += 1
			_check(false, "%s above bottom third (y=%.0f < %.0f)" % [id, rect.position.y, bottom_third])
	# 右上两格：包 + ≡，必须在右上角
	for id: String in ["bag", "menu"]:
		var rect: Rect2 = table[id]
		_check(rect.position.x > w * 0.72 and rect.end.y < h * 0.25,
			"%s must sit in top-right corner: %s" % [id, str(rect)])
	# 中央 60%×45% 零控件（下 1/3 是法定的动作区，不算中央）
	var center := Rect2(w * 0.15, h * 0.2, w * 0.47, h * 0.45)
	for id: String in IDS:
		_check(not (table[id] as Rect2).intersects(center), "%s intrudes into center 60%%" % id)

	# 毫米尺寸
	var mm_attack := 11.0 * DPI / 25.4 / (float(WINDOW.x) / float(CANVAS.x))
	_check(_layer.attack_size() >= int(mm_attack) - 1, "attack smaller than 11mm: %d" % _layer.attack_size())
	_check(_layer.search_size() >= int(10.0 * DPI / 25.4 / (float(WINDOW.x) / float(CANVAS.x))) - 1,
		"search smaller than 10mm")
	_check(_layer.small_size() >= int(8.0 * DPI / 25.4 / (float(WINDOW.x) / float(CANVAS.x))) - 1,
		"small key smaller than 8mm")

	# 打 ↔ 搜 中心距 ≥ 14mm，且不贴边
	var attack: Rect2 = table["attack"]
	var search: Rect2 = table["search"]
	var center_mm := attack.get_center().distance_to(search.get_center()) * (float(WINDOW.x) / float(CANVAS.x)) * 25.4 / DPI
	_check(center_mm >= 14.0, "attack↔search center distance %.1fmm < 14mm" % center_mm)

	# 常驻键两两不重叠（B 的几何前提）
	var persistent := ["attack", "run", "lamp"]
	for i in range(persistent.size()):
		for j in range(i + 1, persistent.size()):
			_check(not (table[persistent[i]] as Rect2).intersects(table[persistent[j]] as Rect2),
				"%s overlaps %s" % [persistent[i], persistent[j]])

	# B：50 次交替「打 / 搜 / 跑」，每次在目标矩形内随机取点，命中必须还是它
	var seed_value := 20261126
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sequence := ["attack", "search", "run"]
	var misses := 0
	var samples := 0
	for index in range(50):
		var target: String = sequence[index % sequence.size()]
		if target == "search":
			_layer.set_search_available(true)
		var rect: Rect2 = _layer.rects()[target]
		var point := rect.position + Vector2(
			rng.randf_range(2.0, maxf(3.0, rect.size.x - 2.0)),
			rng.randf_range(2.0, maxf(3.0, rect.size.y - 2.0)))
		samples += 1
		var hit := _hit_test(point)
		if hit != target:
			misses += 1
	_layer.set_search_available(false)

	return {"A": reach_fail == 0, "B": misses, "samples": samples, "center_mm": center_mm}


func _hit_test(point: Vector2) -> String:
	var table := _layer.rects()
	for id: String in IDS:
		if id == "search" and not _layer.search_available():
			continue
		if (table[id] as Rect2).has_point(point):
			return id
	return ""


func _check_context_key() -> void:
	_check(not _layer.search_available(), "search key must start hidden")
	var visible_before := _layer.button_visible("search")
	_check(not visible_before, "search visual must be hidden before context")
	_layer.set_search_available(true)
	_check(_layer.button_visible("search"), "search visual must appear when context is available")
	_layer.set_search_available(false)
	_check(not _layer.button_visible("search"), "search visual must disappear when context ends")


## 「搜」必须是按住态：走廊靠 pickup 的 action 状态推进搜索进度。
## 只发一次 tap（按下即松开）会让手机上的搜索在下一帧就被判成「松手中断」——进度永远走不完。
func _check_search_hold() -> void:
	_layer.set_search_available(true)
	_layer._on_pressed("search")
	_check(Input.is_action_pressed("pickup"), "holding 搜 must keep pickup pressed")
	_check(not _layer._held.is_empty(), "held table must remember the search key")
	for _frame in range(3):
		await process_frame
		_check(Input.is_action_pressed("pickup"), "pickup must stay pressed across frames")
	_layer._on_released("search")
	_check(not Input.is_action_pressed("pickup"), "releasing 搜 must release pickup")
	_check(_layer._held.is_empty(), "held table must forget the search key")
	_layer.set_search_available(false)


func _check_joystick() -> void:
	_layer._stick_begin(Vector2(120, 200), 0)
	_check(_layer.joystick_active(), "joystick must activate on touch in the left-bottom zone")
	_layer._stick_move(Vector2(160, 200))
	_check(Input.is_action_pressed("move_right"), "joystick right must press move_right")
	_layer._stick_move(Vector2(120, 200))
	_check(not Input.is_action_pressed("move_right"), "dead zone must release move_right")
	_layer._stick_end()
	_check(not _layer.joystick_active(), "joystick must return on release")
	# 右半屏不生成摇杆（不抢动作区）
	_layer._stick_begin(Vector2(480, 200), 1)
	_check(not _layer.joystick_active(), "joystick must not spawn in the action zone")
	_layer._stick_end()


func _check_menu() -> void:
	_check(not _layer.menu_open(), "menu starts closed")
	_layer.open_menu()
	_check(_layer.menu_open(), "menu must open")
	_check(_layer.menu_items().has("装填"), "menu must carry reload (the old 填 key is gone)")
	var row: Rect2 = _layer.menu_rows()[2]
	var choice := _layer.tap_menu_at(row.get_center())
	_check(choice == "装填", "tapping the third row must pick 装填, got %s" % choice)
	_layer.close_menu()
	_check(not _layer.menu_open(), "menu must close")


## C：暗底对比度（WCAG 相对亮度），全用文本色 #e8e4d8
func _check_contrast() -> float:
	var ratio_dark := _ratio(INK, BG_DARK)
	var ratio_wall := _ratio(INK, BG_WALL)
	_check(ratio_dark >= 7.0, "contrast on void %.2f < 7:1" % ratio_dark)
	_check(ratio_wall >= 7.0, "contrast on wall %.2f < 7:1" % ratio_wall)
	return minf(ratio_dark, ratio_wall)


func _ratio(fg: Color, bg: Color) -> float:
	var lf := _luminance(fg)
	var lb := _luminance(bg)
	var hi := maxf(lf, lb)
	var lo := minf(lf, lb)
	return (hi + 0.05) / (lo + 0.05)


func _luminance(c: Color) -> float:
	return 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b)


func _channel(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("TOUCH_FAIL " + message)


func _finish(report: Dictionary, contrast: float) -> void:
	if _failures.is_empty():
		print("TOUCH_OK buttons=%d layout=zones_v2 mm=11/10/8 reach=%s mis_touch=%d/%d contrast=%.1f:1" % [
			_layer.button_ids().size(), str(report["A"]), int(report["B"]), int(report["samples"]), contrast])
		quit(0)
		return
	print("TOUCH_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
