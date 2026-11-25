extends CanvasLayer
class_name TouchControls

## 手机触摸层 v1（2026-11-26）。只在手机 / RS_TOUCH=1 时由 MobileSupport 挂上，桌面不受影响。
##
## 为什么不用 Control 按钮：Control 走「触摸 → 鼠标仿真」，多指会被合并成单指针；
## 而这个游戏必须能「左手走路 + 右手攻击」同时进行。所以命中用 TouchScreenButton
## （引擎原生多点触控），外观自己画（项目风格：程序绘制，不引外部贴图）。
##
## 一次性动作（E/V/F/Tab/R/Esc/攻击）不能只改动作状态：走廊与菜单的输入都走事件，
## 所以这里额外合成一个 InputEventKey / InputEventMouseButton 交给 Input.parse_input_event()。
## 这是有意选择的「桥」——不改 corridor.gd / main_menu.gd 里的热路径，风险最小；
## 代价是事件对引擎来说与真键盘无异（桌面按住这些键时也会被当成同一个动作，无副作用）。

signal emitted(id: String)

const VIEW := Vector2i(384, 216)
const INK := Color("#9fb2bd")
const HOT := Color("#f6f6f0")
const FILL := Color(0.043, 0.067, 0.098, 0.62)
const FILL_HOT := Color(0.129, 0.208, 0.278, 0.85)
const EDGE := Color("#354b60")
const GAITS := ["走", "跑", "蹲"]

## 按键表：kind = hold（按住即动作状态）/ tap（补一个合成事件）
## rect 是 384×216 原生坐标；所有按钮都躲开左侧 HUD（x < 130 且 y < 140 那块是 HUD 文字）。
## 十字键同时发一个合成按键事件：走廊的旅行图/背包、主菜单的选项都只认事件不认状态，
## 没有这一下，手机上「能走但打不开地图、选不了菜单」。按住的状态仍然只由 action_press 维持。
const SPECS := [
	{"id": "left", "action": "move_left", "rect": [14, 164, 28, 28], "label": "", "arrow": "left", "kind": "hold", "key": 65},
	{"id": "right", "action": "move_right", "rect": [70, 164, 28, 28], "label": "", "arrow": "right", "kind": "hold", "key": 68},
	{"id": "up", "action": "move_up", "rect": [42, 142, 28, 28], "label": "", "arrow": "up", "kind": "hold", "key": 87},
	{"id": "down", "action": "move_down", "rect": [42, 186, 28, 28], "label": "", "arrow": "down", "kind": "hold", "key": 83},
	{"id": "gait", "action": "", "rect": [282, 138, 34, 34], "label": "走", "kind": "gait"},
	{"id": "light", "action": "toggle_light", "rect": [326, 138, 34, 34], "label": "灯", "kind": "tap", "key": 70},
	{"id": "attack", "action": "attack", "rect": [282, 176, 34, 34], "label": "打", "kind": "tap", "key": -1},
	{"id": "pickup", "action": "pickup", "rect": [326, 176, 34, 34], "label": "E", "kind": "tap", "key": 69},
	{"id": "reload", "action": "reload", "rect": [238, 138, 34, 34], "label": "填", "kind": "tap", "key": 82},
	{"id": "bag", "action": "inventory", "rect": [272, 10, 32, 24], "label": "包", "kind": "tap", "key": 4194306},
	{"id": "look", "action": "view", "rect": [308, 10, 32, 24], "label": "看", "kind": "tap", "key": 86},
	{"id": "menu", "action": "cancel_inspect", "rect": [344, 10, 32, 24], "label": "退", "kind": "tap", "key": 4194305},
]

var _buttons: Dictionary = {}      # id -> TouchScreenButton
var _visuals: Dictionary = {}      # id -> Node2D（重绘标签用）
var _spec_by_id: Dictionary = {}   # id -> Dictionary
var _buttons_root: Node2D
var _gait_index := 0
var _dimmed := false
## 面板（检查/背包/旅行图）打开时压到 0.35 透明度：还能点，但不挡字
const DIM_ALPHA := 0.35
var _safe_canvas := Rect2(0, 0, VIEW.x, VIEW.y)
var last_emitted := ""
## 门禁可观测：最近一次合成出去的键 / 鼠标
var last_key := -1
var last_mouse := false


func _ready() -> void:
	layer = 20
	_build()
	apply_safe_area()


func _build() -> void:
	var root := Node2D.new()
	root.name = "Buttons"
	add_child(root)
	_buttons_root = root
	for raw: Dictionary in SPECS:
		var spec: Dictionary = raw.duplicate(true)
		var id := String(spec["id"])
		_spec_by_id[id] = spec
		var rect := _rect_of(spec)
		var button := TouchScreenButton.new()
		button.name = "T_" + id
		button.position = rect.position
		var shape := RectangleShape2D.new()
		shape.size = Vector2(rect.size)
		button.shape = shape
		button.passby_press = false
		button.pressed.connect(_on_pressed.bind(id))
		button.released.connect(_on_released.bind(id))
		root.add_child(button)
		_buttons[id] = button
		_visuals[id] = _build_visual(root, id, rect, String(spec["label"]), String(spec.get("arrow", "")))


func _rect_of(spec: Dictionary) -> Rect2i:
	var r: Array = spec["rect"]
	return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))


## 一个按钮的外观：底 + 1px 边 + 居中标签（或点阵箭头）。全部 ColorRect / 点阵字，天然过像素门禁。
func _build_visual(parent: Node2D, id: String, rect: Rect2i, label: String, arrow: String) -> Node2D:
	var node := Node2D.new()
	node.name = "V_" + id
	parent.add_child(node)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = FILL
	fill.position = Vector2(rect.position)
	fill.size = Vector2(rect.size)
	node.add_child(fill)
	for edge: Array in [
		[rect.position, Vector2(rect.size.x, 1)],
		[Vector2(rect.position.x, rect.end.y - 1), Vector2(rect.size.x, 1)],
		[rect.position, Vector2(1, rect.size.y)],
		[Vector2(rect.end.x - 1, rect.position.y), Vector2(1, rect.size.y)],
	]:
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = EDGE
		line.position = Vector2(edge[0])
		line.size = Vector2(edge[1])
		node.add_child(line)
	if arrow.is_empty():
		_set_label(node, rect, label)
	else:
		_draw_arrow(node, rect, arrow)
	return node


## 方向键箭头：不依赖字体（图集里没有 ←↑↓），直接按 7×7 点阵画，格子放大 2 倍。
const ARROWS := {
	"left": [
		"...#...",
		"..##...",
		".####..",
		"#######",
		".####..",
		"..##...",
		"...#...",
	],
	"right": [
		"...#...",
		"...##..",
		"..####.",
		"#######",
		"..####.",
		"...##..",
		"...#...",
	],
	"up": [
		"...#...",
		"..###..",
		".#####.",
		"#######",
		"...#...",
		"...#...",
		"...#...",
	],
	"down": [
		"...#...",
		"...#...",
		"...#...",
		"#######",
		".#####.",
		"..###..",
		"...#...",
	],
}
const ARROW_CELL := 2


func _draw_arrow(node: Node2D, rect: Rect2i, direction: String) -> void:
	var rows: Array = ARROWS.get(direction, [])
	if rows.is_empty():
		return
	var cells := rows.size()
	var span := cells * ARROW_CELL
	var origin := Vector2(
		rect.position.x + int((rect.size.x - span) * 0.5),
		rect.position.y + int((rect.size.y - span) * 0.5),
	)
	for row in range(cells):
		var line := String(rows[row])
		for col in range(line.length()):
			if line[col] != "#":
				continue
			var pixel := ColorRect.new()
			pixel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pixel.color = INK
			pixel.position = origin + Vector2(col * ARROW_CELL, row * ARROW_CELL)
			pixel.size = Vector2(ARROW_CELL, ARROW_CELL)
			node.add_child(pixel)


func _set_label(node: Node2D, rect: Rect2i, label: String) -> void:
	var old := node.get_node_or_null("Label")
	if old != null:
		old.queue_free()
	var holder := Node2D.new()
	holder.name = "Label"
	node.add_child(holder)
	var width := PixelFont.width_of(label)
	var glyph_h := 12 if not PixelFont.ORDER.contains(label.substr(0, 1)) else 8
	var at := Vector2(
		rect.position.x + int((rect.size.x - width) * 0.5),
		rect.position.y + int((rect.size.y - glyph_h) * 0.5),
	)
	PixelFont.draw(holder, label, at, HOT)


func _on_pressed(id: String) -> void:
	var spec: Dictionary = _spec_by_id.get(id, {})
	if spec.is_empty():
		return
	if spec["kind"] == "gait":
		_cycle_gait()
		_light_up(id, true)
	elif spec["kind"] == "hold":
		# 顺序要紧：先发键事件、再压动作状态。反过来会被合成键的 release 立刻清掉。
		var key := int(spec.get("key", -1))
		if key >= 0:
			_send_key(key)
		Input.action_press(StringName(spec["action"]))
		_light_up(id, true)
	else:
		_tap(spec)
		_light_up(id, true)
	last_emitted = id
	emitted.emit(id)


func _on_released(id: String) -> void:
	var spec: Dictionary = _spec_by_id.get(id, {})
	if spec.is_empty():
		return
	if spec["kind"] == "hold":
		Input.action_release(StringName(spec["action"]))
	_light_up(id, false)


func _light_up(id: String, hot: bool) -> void:
	var visual: Node2D = _visuals.get(id)
	if visual == null:
		return
	var fill := visual.get_node_or_null("Fill") as ColorRect
	if fill != null:
		fill.color = FILL_HOT if hot else FILL


## 一次性动作：先合成事件（走廊/菜单靠事件），再保证动作状态按下这一帧也是真的。
func _tap(spec: Dictionary) -> void:
	var action := StringName(spec["action"])
	var key := int(spec.get("key", -1))
	if key < 0:
		_send_mouse_left()
	else:
		_send_key(key)
	if action != &"" and InputMap.has_action(action):
		Input.action_press(action)
		Input.action_release(action)


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


## 步态：走 → 跑 → 蹲 → 走。手机上一只手按两个速度键太别扭，改成循环切换。
func _cycle_gait() -> void:
	_gait_index = (_gait_index + 1) % GAITS.size()
	if InputMap.has_action(&"sprint"):
		Input.action_release(&"sprint")
	if InputMap.has_action(&"crouch"):
		Input.action_release(&"crouch")
	match _gait_index:
		1:
			if InputMap.has_action(&"sprint"):
				Input.action_press(&"sprint")
		2:
			if InputMap.has_action(&"crouch"):
				Input.action_press(&"crouch")
	var rect := _rect_of(_spec_by_id["gait"])
	_set_label(_visuals["gait"], rect, GAITS[_gait_index])


func gait_index() -> int:
	return _gait_index


## 安全区：刘海/挖孔在横屏会吃掉左右边。把每个按钮的矩形挪回安全区内。
func apply_safe_area() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return
	var scale := minf(win.x / float(VIEW.x), win.y / float(VIEW.y))
	if scale <= 0.0:
		return
	var origin := (win - Vector2(VIEW) * scale) * 0.5
	var home := Rect2(
		(safe.position.x - origin.x) / scale,
		(safe.position.y - origin.y) / scale,
		safe.size.x / scale,
		safe.size.y / scale,
	)
	_set_safe_rect(home)


## 门禁用：直接给一个 384 空间的安全矩形，绕开真机。
func _set_safe_rect(home: Rect2) -> void:
	_safe_canvas = home.intersection(Rect2(0, 0, VIEW.x, VIEW.y))
	for id: String in _buttons.keys():
		var spec: Dictionary = _spec_by_id[id]
		var rect := _rect_of(spec)
		var moved := rect
		if home.size.x > 0.0:
			if moved.end.x > int(home.end.x):
				moved.position.x -= moved.end.x - int(home.end.x)
			if moved.position.x < int(home.position.x):
				moved.position.x = int(home.position.x)
			if moved.end.y > int(home.end.y):
				moved.position.y -= moved.end.y - int(home.end.y)
			if moved.position.y < int(home.position.y):
				moved.position.y = int(home.position.y)
		var button: TouchScreenButton = _buttons[id]
		button.position = Vector2(moved.position)
		var visual: Node2D = _visuals.get(id)
		if visual != null:
			var shift := Vector2(moved.position - rect.position)
			for child: Node in visual.get_children():
				if child is ColorRect:
					(child as ColorRect).position += shift
			var holder := visual.get_node_or_null("Label")
			if holder != null:
				for child: Node in holder.get_children():
					if child is Node2D:
						(child as Node2D).position += shift


func safe_canvas() -> Rect2:
	return _safe_canvas


func button_rect(id: String) -> Rect2:
	var button: TouchScreenButton = _buttons.get(id)
	if button == null:
		return Rect2()
	var shape := button.shape as RectangleShape2D
	var size := shape.size if shape != null else Vector2.ZERO
	return Rect2(button.position, size)


func button_ids() -> Array:
	return _buttons.keys()


# ── 门禁直接调用的入口（免真实触摸事件）──────────────────────
func press(id: String) -> void:
	_on_pressed(id)


func release(id: String) -> void:
	_on_released(id)


## 面板打开时压透明度（不清空 visible：还要能点着关掉）
func set_dimmed(value: bool) -> void:
	_dimmed = value
	if _buttons_root != null:
		_buttons_root.modulate.a = DIM_ALPHA if value else 1.0


func is_dimmed() -> bool:
	return _dimmed
