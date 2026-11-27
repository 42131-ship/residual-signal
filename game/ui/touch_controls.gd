extends CanvasLayer
class_name TouchControls

## 手机触摸层 v2（2026-11-26 重排，目标：手机玩家舒适圈）。
##
## 屏幕分区（唯一合法布局）：
##   左上 = 信息（只读，HUD 自己画，本层不放按钮）
##   右上 = 次要动作，最多两格：包 + ≡
##   左下 = 移动：浮动摇杆（按下才出现，松手归位）
##   右下 = 主动作：打（主）+ 搜（上下文，贴近可搜索物才出现）+ 灯/跑（上排小键）
##   中央 60% = 纯世界，零控件
##
## 尺寸用**毫米**换算，不写死像素：`_mm()` 取屏幕 DPI 与当前画布缩放，
## 于是 11mm 在 520dpi/5× 的手机上是 45 画布像素，在桌面（96dpi）上是 8 —— 桌面本就不挂这一层。
##
## 为什么命中用 TouchScreenButton：Control 走「触摸→鼠标仿真」，多指会被合并成单指针，
## 而这个游戏要「左手走 + 右手打」同时成立。

signal emitted(id: String)

const DESIGN := Vector2i(384, 216)

## 触控键表。id / 动作 / 尺寸(mm) / 语义 / 合成的键
## kind: hold=按住即动作状态；tap=发一次事件；toggle=开关（跑）
const KEYS := {
	"attack": {"size_mm": 11.0, "label": "攻击", "kind": "tap", "key": -1, "action": "attack"},
	"search": {"size_mm": 10.0, "label": "搜", "kind": "tap", "key": 69, "action": "pickup"},
	"lamp": {"size_mm": 11.0, "label": "手电筒", "kind": "tap", "key": 70, "action": "toggle_light"},
	"run": {"size_mm": 11.0, "label": "奔跑", "kind": "hold", "key": 0, "action": "sprint"},
	"crouch": {"size_mm": 11.0, "label": "蹲下", "kind": "hold", "key": 0, "action": "crouch"},
	"bag": {"size_mm": 11.0, "label": "背包", "kind": "tap", "key": 4194306, "action": "inventory"},
	"menu": {"size_mm": 11.0, "label": "", "kind": "menu", "key": 0, "action": ""},
}

## 步态循环：走 → 跑 → 蹲（一个键，标签就是当前状态；手机上没有第二个修饰键可按）
const GAITS := ["走", "跑", "蹲"]

## 边距（画布像素，按 384 基准；手机按 _mm 再放大一档）
const GAP := 6
const EDGE := 10

const INK := Color("#e8e4d8")
const FILL := Color(0.043, 0.067, 0.098, 0.62)
const FILL_HOT := Color(0.129, 0.208, 0.278, 0.9)
const EDGE_COLOR := Color("#354b60")
const GHOST := Color(0.91, 0.89, 0.85, 0.30)

var _buttons: Dictionary = {}
var _visuals: Dictionary = {}
var _buttons_root: Node2D
var _canvas := Vector2i(DESIGN)
var _inset := Vector4(0, 0, 0, 0)     # 安全区（左/上/右/下）
var _dimmed := false
var _menu_open := false
var _menu_index := 0
var _menu_layer: Node2D
var _search_available := false
var _run_on := false
var _gait_index := 0
var _held: Dictionary = {}
## 手指 index -> 按钮 id：按下即响应，抬起按同一 index 释放（不依赖 TouchScreenButton 拾取）
var _touch_owner: Dictionary = {}

# 浮动摇杆
var _stick: Node2D
var _stick_base := Vector2.ZERO
var _stick_touch := -1
var _stick_dir := Vector2.ZERO
var _stick_active := false

# 门禁可观测
var last_emitted := ""
var last_key := -1
var last_mouse := false
var _test_canvas: Vector2i = Vector2i.ZERO
var _test_window: Vector2i = Vector2i.ZERO
var _test_dpi: int = 0

const MENU_ITEMS := ["继续", "暂停", "装填", "查看", "蹲下", "退出"]


func _ready() -> void:
	layer = 20
	_canvas = ScreenLayout.canvas_of(self)
	_build()
	apply_safe_area()
	await get_tree().process_frame
	var canvas := ScreenLayout.canvas_of(self)
	if canvas != _canvas:
		_canvas = canvas
		_rebuild()


# ── 尺寸与几何 ─────────────────────────────────────────────

## 毫米 → 画布像素。桌面/门禁可用 set_metrics_for_test 注入固定值，保证断言可复现。
func _mm(mm_value: float) -> int:
	var dpi := float(_test_dpi if _test_dpi > 0 else maxi(160, DisplayServer.screen_get_dpi()))
	var win := float(_test_window.x if _test_window.x > 0 else maxi(1, DisplayServer.window_get_size().x))
	var scale := win / float(maxi(1, _canvas.x))
	if scale <= 0.0:
		scale = 1.0
	return int(round(mm_value / 25.4 * dpi / scale))


func set_metrics_for_test(canvas: Vector2i, window: Vector2i, dpi: int) -> void:
	_test_canvas = canvas
	_test_window = window
	_test_dpi = dpi
	_canvas = canvas
	_rebuild()


## 主键边长（画布像素）
func attack_size() -> int:
	return maxi(24, _mm(11.0))


func search_size() -> int:
	return maxi(22, _mm(10.0))


func small_size() -> int:
	return maxi(24, _mm(11.0))


## 六颗常驻/上下文控件的矩形（全部从画布右下角与右上角推出来）
func rects() -> Dictionary:
	var w := float(_canvas.x)
	var h := float(_canvas.y)
	var r := _inset.z
	var b := _inset.w
	var t := _inset.y
	var a := float(attack_size())
	var s := float(search_size())
	var m := float(small_size())
	var g := float(maxi(GAP, _mm(2.0)))

	var out := {}
	# 右下：打
	var attack := Rect2(w - r - EDGE - a, h - b - EDGE - a, a, a)
	out["attack"] = attack
	# 打正上方：搜（上下文）。中心距 = (a+s)/2 + 间隙，必须 ≥ 14mm
	var search_gap := maxf(g, float(_mm(4.0)))
	var search := Rect2(attack.get_center().x - s * 0.5,
		attack.position.y - search_gap - s, s, s)
	out["search"] = search
	# 打左侧：跑；灯在跑左边（两颗小键同一排，和「打」物理隔开）
	# 一排：手电筒 / 奔跑 / 攻击；蹲下单独放在手电筒上方（三颗各管一件事，不再循环）
	var run := Rect2(attack.position.x - g - m, attack.position.y + a - m, m, m)
	var lamp := Rect2(run.position.x - g - m, run.position.y, m, m)
	var crouch := Rect2(lamp.position.x, lamp.position.y - g - m, m, m)
	out["run"] = run
	out["lamp"] = lamp
	out["crouch"] = crouch
	# 右上：包 + ≡（两格，右对齐）
	var menu := Rect2(w - r - EDGE - m, t + EDGE, m, m)
	var bag := Rect2(menu.position.x - g - m, t + EDGE, m, m)
	out["bag"] = bag
	out["menu"] = menu
	return out


func _build() -> void:
	var root := Node2D.new()
	root.name = "Buttons"
	add_child(root)
	_buttons_root = root
	for id: String in KEYS.keys():
		var spec: Dictionary = KEYS[id]
		var button := TouchScreenButton.new()
		button.name = "T_" + id
		var shape := RectangleShape2D.new()
		shape.size = Vector2.ONE
		button.shape = shape
		button.passby_press = false
		# 不再连 pressed/released：按下即在 _input 里按矩形命中派发，避免「点多次才灵」与双触发。
		root.add_child(button)
		_buttons[id] = button
		_visuals[id] = _build_visual(root, id)
	_apply_rects()
	_build_stick()
	_build_menu()


func _rebuild() -> void:
	if _buttons_root != null:
		_buttons_root.queue_free()
	_buttons.clear()
	_visuals.clear()
	_menu_layer = null
	_stick = null
	_build()
	apply_safe_area()


## 把矩形写回按钮与外观（外观按当前矩形重画）
func _apply_rects() -> void:
	var table := rects()
	for id: String in table.keys():
		var rect: Rect2 = table[id]
		var button: TouchScreenButton = _buttons[id]
		button.position = rect.position
		button.shape.size = rect.size
		if id == "menu":
			button.visible = not _menu_open
		elif id == "search":
			button.visible = _search_available
		var visual: Node2D = _visuals[id]
		_draw_visual(visual, id, rect)
		visual.visible = button.visible


func _build_visual(parent: Node2D, id: String) -> Node2D:
	var node := Node2D.new()
	node.name = "V_" + id
	parent.add_child(node)
	return node


## 外观：底 + 1px 边 + 居中标签。色值只取调色板里的 UI 色（#e8e4d8 正文、#354b60 边）。
func _draw_visual(node: Node2D, id: String, rect: Rect2) -> void:
	for child: Node in node.get_children():
		child.queue_free()
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = FILL_HOT if _is_hot(id) else FILL
	fill.position = rect.position
	fill.size = rect.size
	node.add_child(fill)
	for edge: Array in [
		[rect.position, Vector2(rect.size.x, 1)],
		[Vector2(rect.position.x, rect.end.y - 1), Vector2(rect.size.x, 1)],
		[rect.position, Vector2(1, rect.size.y)],
		[Vector2(rect.end.x - 1, rect.position.y), Vector2(1, rect.size.y)],
	]:
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = EDGE_COLOR if not (_menu_open and id == "menu") else INK
		line.position = Vector2(edge[0])
		line.size = Vector2(edge[1])
		node.add_child(line)
	var label := String(KEYS[id].get("label", ""))
	if id == "menu":
		# ≡ 用三条 1px 横线画（图集里没有 ≡，也不该为它加字形）
		for index in range(3):
			var bar := ColorRect.new()
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.color = INK
			bar.size = Vector2(rect.size.x * 0.5, 1)
			bar.position = rect.position + Vector2(rect.size.x * 0.25, rect.size.y * 0.5 - 3 + index * 3)
			node.add_child(bar)
		return
	if label.is_empty():
		return
	var holder := Node2D.new()
	holder.name = "Label"
	node.add_child(holder)
	var text := label

	var width := PixelFont.width_of(text)
	var at := Vector2(
		rect.position.x + int((rect.size.x - width) * 0.5),
		rect.position.y + int((rect.size.y - 12) * 0.5),
	)
	PixelFont.draw(holder, text, at, INK)


func _is_hot(id: String) -> bool:
	if id == "run":
		return _run_on
	if id == "crouch":
		return Input.is_action_pressed(&"crouch")
	if id == "search":
		return _search_available
	return _held.has(id)


# ── 浮动摇杆 ───────────────────────────────────────────────

func _build_stick() -> void:
	_stick = Node2D.new()
	_stick.name = "Stick"
	_stick.visible = false
	add_child(_stick)


## 按下即出现在触点，松手归位；只在左下象限生效（不抢右侧动作区）。
func _stick_begin(pos: Vector2, index: int) -> void:
	if _menu_open:
		return
	if pos.x > _canvas.x * 0.55 or pos.y < _canvas.y * 0.5:
		return
	_stick_touch = index
	_stick_active = true
	_stick_base = pos
	_stick_dir = Vector2.ZERO
	_stick.visible = true
	_stick.position = pos
	_draw_stick()


func _stick_move(pos: Vector2) -> void:
	if not _stick_active:
		return
	var radius := float(maxi(20, _mm(12.0)))
	var delta := pos - _stick_base
	if delta.length() > radius:
		_stick_base = pos - delta.normalized() * radius
		delta = delta.normalized() * radius
	var dead := radius * 0.25
	_stick_dir = Vector2.ZERO if delta.length() < dead else (delta / radius)
	_apply_stick_actions()
	_draw_stick()


func _stick_end() -> void:
	_stick_active = false
	_stick_touch = -1
	_stick_dir = Vector2.ZERO
	_stick.visible = false
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if InputMap.has_action(action):
			Input.action_release(action)


func _apply_stick_actions() -> void:
	if not _stick_active:
		return
	var threshold := 0.28
	_axis(&"move_left", &"move_right", _stick_dir.x, threshold)
	_axis(&"move_up", &"move_down", _stick_dir.y, threshold)


func _axis(neg: StringName, pos: StringName, value: float, threshold: float) -> void:
	if InputMap.has_action(neg):
		if value < -threshold:
			Input.action_press(neg)
		else:
			Input.action_release(neg)
	if InputMap.has_action(pos):
		if value > threshold:
			Input.action_press(pos)
		else:
			Input.action_release(pos)


func _draw_stick() -> void:
	for child: Node in _stick.get_children():
		child.queue_free()
	var radius := float(maxi(20, _mm(12.0)))
	var knob := float(maxi(10, _mm(6.0)))
	var base := ColorRect.new()
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.color = Color(0, 0, 0, 0)
	base.position = Vector2(-radius, -radius)
	base.size = Vector2(radius * 2, radius * 2)
	_stick.add_child(base)
	_ring(_stick, radius)
	var knob_rect := ColorRect.new()
	knob_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob_rect.color = GHOST
	knob_rect.position = _stick_dir * radius * 0.8 - Vector2(knob, knob) * 0.5
	knob_rect.size = Vector2(knob, knob)
	_stick.add_child(knob_rect)


## 用 1px 线段画圆环（像素风不用抗锯齿圆）
func _ring(parent: Node2D, radius: float) -> void:
	var steps := 24
	var last := Vector2.ZERO
	for index in range(steps + 1):
		var angle := TAU * float(index) / float(steps)
		var point := Vector2(cos(angle), sin(angle)) * radius
		if index > 0:
			var mid := (last + point) * 0.5
			var seg := ColorRect.new()
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			seg.color = Color(0.91, 0.89, 0.85, 0.18)
			seg.position = mid - Vector2(1, 1)
			seg.size = Vector2(2, 2)
			parent.add_child(seg)
		last = point


# ── ≡ 菜单 ─────────────────────────────────────────────────

func _build_menu() -> void:
	_menu_layer = Node2D.new()
	_menu_layer.name = "Menu"
	_menu_layer.visible = false
	add_child(_menu_layer)


func open_menu() -> void:
	_menu_open = true
	_menu_index = 0
	_apply_rects()
	_draw_menu()


func close_menu() -> void:
	_menu_open = false
	_menu_layer.visible = false
	_apply_rects()


func menu_open() -> bool:
	return _menu_open


func menu_items() -> Array:
	return MENU_ITEMS


func menu_rows() -> Array:
	var out := []
	var w := float(_canvas.x)
	var item_h := float(maxi(18, _mm(9.0)))
	var pad := 4.0
	var width := 72.0
	var height := item_h * MENU_ITEMS.size() + pad * 2
	var x := w - 12.0 - width
	var y := _inset.y + 8.0
	for index in range(MENU_ITEMS.size()):
		out.append(Rect2(x, y + pad + index * item_h, width, item_h - 2))
	return out


func _draw_menu() -> void:
	for child: Node in _menu_layer.get_children():
		child.queue_free()
	_menu_layer.visible = true
	var rows := menu_rows()
	var first: Rect2 = rows[0]
	var last: Rect2 = rows[rows.size() - 1]
	var panel := ColorRect.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.color = Color(0.043, 0.067, 0.098, 0.94)
	panel.position = Vector2(first.position.x - 4, first.position.y - 4)
	panel.size = Vector2(first.size.x + 8, last.end.y - first.position.y + 8)
	_menu_layer.add_child(panel)
	for index in range(rows.size()):
		var row: Rect2 = rows[index]
		if index == _menu_index:
			var bar := ColorRect.new()
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.color = Color(0.129, 0.208, 0.278, 1)
			bar.position = row.position
			bar.size = row.size
			_menu_layer.add_child(bar)
		PixelFont.draw(_menu_layer, MENU_ITEMS[index],
			row.position + Vector2(6, int((row.size.y - 12) * 0.5)), INK)


## 点菜单行；返回被点的项名（空 = 没点中面板）
func tap_menu_at(pos: Vector2) -> String:
	if not _menu_open:
		return ""
	var rows := menu_rows()
	for index in range(rows.size()):
		if (rows[index] as Rect2).has_point(pos):
			_menu_index = index
			_draw_menu()
			return MENU_ITEMS[index]
	return ""


func activate_menu_row(index: int) -> String:
	if index < 0 or index >= MENU_ITEMS.size():
		return ""
	_menu_index = index
	_draw_menu()
	return MENU_ITEMS[index]


# ── 输入分发 ───────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _menu_open:
				var hit := tap_menu_at(touch.position)
				if not hit.is_empty():
					_on_menu_choice(hit)
				return
			# 按下即响应：先按矩形命中直接派发，不等 TouchScreenButton 的拾取（真机反馈「点多次才灵」）。
			var target := _button_at(touch.position)
			if not target.is_empty():
				_touch_owner[touch.index] = target
				_on_pressed(target)
				return
			_stick_begin(touch.position, touch.index)
		else:
			var owned: String = _touch_owner.get(touch.index, "")
			if not owned.is_empty():
				_touch_owner.erase(touch.index)
				_on_released(owned)
			elif touch.index == _stick_touch:
				_stick_end()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_touch:
			_stick_move(drag.position)
		return


## 触点落在哪颗键上（按可见性与上下文键的可用性过滤）。
func _button_at(point: Vector2) -> String:
	var table := rects()
	for id: String in table.keys():
		if id == "search" and not _search_available:
			continue
		if not button_visible(id):
			continue
		if (table[id] as Rect2).has_point(point):
			return id
	return ""


func _on_pressed(id: String) -> void:
	var spec: Dictionary = KEYS.get(id, {})
	if spec.is_empty():
		return
	if spec["kind"] == "hold":
		Input.action_press(StringName(spec["action"]))
		_held[id] = spec["action"]
		_apply_rects()
		last_emitted = id
		emitted.emit(id)
		return
	if spec["kind"] == "menu":
		if _menu_open:
			close_menu()
		else:
			open_menu()
		last_emitted = "menu"
		emitted.emit(id)
		return
	if id == "search":
		_tap_key(69, "pickup")
	elif id == "attack":
		_send_mouse_left()
		_pulse("attack")
	elif id == "lamp":
		_tap_key(70, "toggle_light")
	elif id == "run":
		_toggle_run()
	elif id == "crouch":
		_toggle_crouch()
	elif id == "bag":
		_tap_key(4194306, "inventory")
	last_emitted = id
	emitted.emit(id)
	_apply_rects()


func _on_released(id: String) -> void:
	var spec: Dictionary = KEYS.get(id, {})
	if spec.is_empty():
		return
	if spec["kind"] == "hold":
		Input.action_release(StringName(spec["action"]))
		_held.erase(id)
	_apply_rects()


func _on_menu_choice(item: String) -> void:
	match item:
		"继续":
			close_menu()
		"暂停":
			_tap_key(4194305, "cancel_inspect")   # Esc：走廊里等价「暂停/收起」
			close_menu()
		"装填":
			_tap_key(82, "reload")
			close_menu()
		"查看":
			_tap_key(86, "view")
			close_menu()
		"蹲下":
			_toggle_crouch()
			close_menu()
		"退出":
			_tap_key(4194305, "cancel_inspect")
			close_menu()


func _toggle_run() -> void:
	_run_on = not _run_on
	if InputMap.has_action(&"sprint"):
		if _run_on:
			Input.action_press(&"sprint")
		else:
			Input.action_release(&"sprint")


## 走 → 跑 → 蹲 → 走。标签永远显示「现在的状态」，玩家按一下就换一档。
func _cycle_gait() -> void:
	_gait_index = (_gait_index + 1) % GAITS.size()
	for action: StringName in [&"sprint", &"crouch"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	if _gait_index == 1 and InputMap.has_action(&"sprint"):
		Input.action_press(&"sprint")
	elif _gait_index == 2 and InputMap.has_action(&"crouch"):
		Input.action_press(&"crouch")
	_draw_visual(_visuals["run"], "run", rects()["run"])
	_run_on = _gait_index == 1


func gait_index() -> int:
	return _gait_index


func _toggle_crouch() -> void:
	if not InputMap.has_action(&"crouch"):
		return
	if Input.is_action_pressed(&"crouch"):
		Input.action_release(&"crouch")
	else:
		Input.action_press(&"crouch")


func _pulse(action: String) -> void:
	if InputMap.has_action(StringName(action)):
		Input.action_press(StringName(action))
		Input.action_release(StringName(action))


func _tap_key(keycode: int, action: String) -> void:
	_send_key(keycode)
	if InputMap.has_action(StringName(action)):
		Input.action_press(StringName(action))
		Input.action_release(StringName(action))


func _send_key(keycode: int) -> void:
	last_key = keycode
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)


func _send_mouse_left() -> void:
	last_mouse = true
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)


# ── 对外接口（走廊/门禁）────────────────────────────────────

## 走廊每帧告诉触摸层「现在附近有没有可搜索物」：true 才出现「搜」。
func set_search_available(value: bool) -> void:
	if value == _search_available:
		return
	_search_available = value
	_apply_rects()


func search_available() -> bool:
	return _search_available


func run_on() -> bool:
	return _run_on


func joystick_active() -> bool:
	return _stick_active


func joystick_dir() -> Vector2:
	return _stick_dir


func set_dimmed(value: bool) -> void:
	_dimmed = value
	if _buttons_root != null:
		_buttons_root.modulate.a = 0.35 if value else 1.0
	if _stick != null:
		_stick.modulate.a = 0.35 if value else 1.0


func is_dimmed() -> bool:
	return _dimmed


func button_ids() -> Array:
	return _buttons.keys()


func button_visible(id: String) -> bool:
	var button: TouchScreenButton = _buttons.get(id)
	return button != null and button.visible


## 这个点是不是落在了触摸层的按钮上（场景里的点击导航用它避让，别和触控键抢触点）
func hits_any(point: Vector2) -> bool:
	var table := rects()
	for id: String in table.keys():
		if id == "search" and not _search_available:
			continue
		if not _buttons.has(id):
			continue
		if not (table[id] as Rect2).has_point(point):
			continue
		if not button_visible(id):
			continue
		return true
	if _menu_open:
		for row: Rect2 in menu_rows():
			if row.has_point(point):
				return true
	return false


func button_rect(id: String) -> Rect2:
	var i := KEYS.keys().find(id)
	if i < 0:
		return Rect2()
	return rects()[id]


func press(id: String) -> void:
	_on_pressed(id)


func release(id: String) -> void:
	_on_released(id)


func apply_safe_area() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		win = Vector2(_test_window) if _test_window.x > 0 else win
	if win.x <= 0.0 or win.y <= 0.0:
		return
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		_inset = Vector4(0, 0, 0, 0)
		_apply_rects()
		return
	var view := Vector2(_canvas)
	var scale := maxf(0.0001, win.x / view.x)
	var origin := (win - view * scale) * 0.5
	_inset = Vector4(
		maxf(0.0, (safe.position.x - origin.x) / scale),
		maxf(0.0, (safe.position.y - origin.y) / scale),
		maxf(0.0, (win.x - (safe.position.x + safe.size.x) - origin.x) * -1.0 / scale),
		maxf(0.0, (win.y - (safe.position.y + safe.size.y) - origin.y) * -1.0 / scale),
	)
	_apply_rects()


func set_safe_inset_for_test(inset: Vector4) -> void:
	_inset = inset
	_apply_rects()


func safe_inset() -> Vector4:
	return _inset


func _process(_delta: float) -> void:
	for id: String in _held:
		Input.action_press(_held[id])
	if _stick_active:
		_apply_stick_actions()
