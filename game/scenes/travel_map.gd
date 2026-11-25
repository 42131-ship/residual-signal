extends Node2D
## 旅行图：俯视 + 2.5D 立体块，可当走廊出口的选楼界面用。
##
## 三条 2.5D 规则（PIXEL_SPEC §4 的光照约定）：
##   1) 每栋楼 = 顶面 + 正面 + 右侧面（平行四边形错开，给出斜上方视角）
##   2) 明度 顶面 > 正面 > 右侧面
##   3) 按底边 y 从远到近绘制
##
## 楼位与体积来自 data/travel/map_layout.json —— 生图底图换了只改数据，不碰代码。
## 生图只当底纹（压暗 60%），几何一律程序画：细节与坐标都要能被门禁断言。

signal chosen(building_id: String)
signal cancelled

const VIEW := Vector2i(384, 216)
const BG_PATH := "res://art/generated_candidates/maps/map_topdown.png"
const LAYOUT_PATH := "res://data/travel/map_layout.json"
const SCRIM := Color(0.043, 0.067, 0.098, 0.6)

const TOP_FACE := Color("#3f5366")
const FRONT_FACE := Color("#26323f")
const SIDE_FACE := Color("#151d28")
const ROAD := Color("#182433")
const LABEL := Color("#9fb2bd")
const CURSOR := Color("#f6f6f0")
const WINDOW := Color("#8a6a3a")
const WINDOW_DIM := Color("#4a3a26")
const SIGN := Color("#8a4a3a")
const OPENING := Color("#111a26")
const METAL := Color("#5a6b78")
## D8：当前所在楼的高亮角标（暖色，和灰蓝楼体拉开；每 30 帧闪一次）。
const CURRENT_MARKER := Color("#d9b45a")
const CURRENT_MARKER_BLINK_FRAMES := 30

var current_building := "school"
## 作为走廊的叠加层时由走廊统一转发按键，地图自己不处理输入（避免两边抢键）。
var interactive := true
## 今天去过哪几栋（走廊传进来），用于地图上的「去过」标记。
var _visited: Array[String] = []
## 每栋楼的标记：{fuel, risk, visited, known}
var _marks: Dictionary = {}
## 楼位表：id -> {at, size, height, detail, label_align}
var BLOCKS: Dictionary = {}
var _travel := TravelService.new()
var _edges: Array[Dictionary] = []
var _selectable: Array[String] = []
var _neighbors: Array[String] = []
var _selected := 0
var _cursor: Node2D
var _hint_root: Node2D
var _marks_root: Node2D
## D8：当前楼标记层：四角 3×3 角标，包住当前楼的 2.5D 轮廓，按帧闪烁。
var _current_root: Node2D
var _current_rect := Rect2()
var _current_frames := 0
var _detail_count: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_actions()
	_load_layout()
	_build_background()
	if not _travel.load_all():
		push_error("TRAVEL_LOAD_FAILED: " + _travel.load_error())
	_build_roads()
	_build_blocks()
	_build_street()
	_build_labels()
	_hint_root = _node("Hints")
	_cursor = _node("Cursor")
	_marks_root = _node("Marks")
	_current_root = _node("CurrentBuilding")
	PixelFont.draw(_hint_root, "W/S 选楼 · E 出发 · Esc 留下", Vector2(8, 202), LABEL)
	setup(current_building)


## 地图可以单独跑（门禁），所以自己保证这几个语义动作存在；与走廊/菜单重复注册也无害。
func _ensure_actions() -> void:
	var bindings := {
		"menu_up": [KEY_W, KEY_UP],
		"menu_down": [KEY_S, KEY_DOWN],
		"menu_confirm": [KEY_E, KEY_ENTER],
		"menu_back": [KEY_ESCAPE],
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode: int in bindings[action]:
			var exists := false
			for event: InputEvent in InputMap.action_get_events(action):
				if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
					exists = true
					break
			if exists:
				continue
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)


## 楼位表是数据驱动的：改位置只改 JSON，代码不动。
func _load_layout() -> void:
	BLOCKS.clear()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not raw is Dictionary:
		push_error("MAP_LAYOUT_UNREADABLE: " + LAYOUT_PATH)
		return
	for value: Variant in (raw as Dictionary).get("buildings", []):
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var id := str(entry.get("id", ""))
		var at: Variant = entry.get("at")
		var size: Variant = entry.get("size")
		if id.is_empty() or not at is Array or not size is Array:
			continue
		BLOCKS[id] = {
			"at": Vector2(float(at[0]), float(at[1])),
			"size": Vector2(float(size[0]), float(size[1])),
			"height": float(entry.get("height", 16.0)),
			"detail": str(entry.get("detail", "")),
			"label_align": str(entry.get("label_align", "center")),
		}


func _node(node_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = node_name
	add_child(node)
	return node


func _build_background() -> void:
	var base := ColorRect.new()
	base.name = "Base"
	base.color = Color("#0b1119")
	base.size = Vector2(VIEW)
	add_child(base)
	var texture := load(BG_PATH) as Texture2D
	if texture == null:
		return
	var art := Sprite2D.new()
	art.name = "MapArt"
	art.texture = texture
	art.centered = false
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(art)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM
	scrim.size = Vector2(VIEW)
	add_child(scrim)


## 连线只画一次：取无向边，按 (a,b) 字典序去重。
func _build_roads() -> void:
	var seen := {}
	for id: String in BLOCKS:
		for other: String in _travel.neighbors(id):
			if not BLOCKS.has(other):
				continue
			var key := "%s|%s" % [id, other] if id < other else "%s|%s" % [other, id]
			if seen.has(key):
				continue
			seen[key] = true
			_edges.append({"a": id, "b": other})
	for edge: Dictionary in _edges:
		var from: Vector2 = (BLOCKS[str(edge["a"])] as Dictionary)["at"]
		var to: Vector2 = (BLOCKS[str(edge["b"])] as Dictionary)["at"]
		var road := Line2D.new()
		road.name = "Road_%s_%s" % [str(edge["a"]), str(edge["b"])]
		road.points = PackedVector2Array([from, (from + to) * 0.5, to])
		road.width = 2.0
		road.default_color = ROAD
		add_child(road)


func _build_blocks() -> void:
	var ordered := BLOCKS.keys()
	ordered.sort_custom(func(a, b): return float(BLOCKS[a]["at"].y) < float(BLOCKS[b]["at"].y))
	for id: String in ordered:
		var spec: Dictionary = BLOCKS[id]
		var at: Vector2 = spec["at"]
		var size: Vector2 = spec["size"]
		var height: float = spec["height"]
		var node := Node2D.new()
		node.name = "Block_%s" % id
		node.position = at
		add_child(node)

		# 接地阴影：先加 = 画在最底下，让楼「坐」在街上而不是浮着。
		var shadow := ColorRect.new()
		shadow.name = "Shadow"
		shadow.position = Vector2(-1, 0)
		shadow.size = Vector2(size.x + size.y * 0.6 + 2, 3)
		shadow.color = Color(0.02, 0.03, 0.05, 1.0)
		node.add_child(shadow)

		var front := Polygon2D.new()
		front.name = "Front"
		front.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, -height), Vector2(0, -height),
		])
		front.color = FRONT_FACE
		node.add_child(front)
		var top := Polygon2D.new()
		top.name = "Top"
		top.polygon = PackedVector2Array([
			Vector2(0, -height), Vector2(size.x, -height),
			Vector2(size.x + size.y * 0.6, -height - size.y),
			Vector2(size.y * 0.6, -height - size.y),
		])
		top.color = TOP_FACE
		node.add_child(top)
		var side := Polygon2D.new()
		side.name = "Side"
		side.polygon = PackedVector2Array([
			Vector2(size.x, 0), Vector2(size.x + size.y * 0.6, -size.y),
			Vector2(size.x + size.y * 0.6, -height - size.y), Vector2(size.x, -height),
		])
		side.color = SIDE_FACE
		node.add_child(side)
		_detail_count[id] = _build_details(id, node, spec)


## 每栋楼按职能长不同的东西 —— 玩家要能一眼认出「这是医院、那是加油站」。
func _build_details(id: String, node: Node2D, spec: Dictionary) -> int:
	var size: Vector2 = spec["size"]
	var height: float = spec["height"]
	var detail := str(spec.get("detail", ""))
	var made := 0
	match detail:
		"school":
			# 三排教室窗 + 大门 + 屋顶水塔 + 天线 + 校牌
			for row in range(3):
				var y := -height + 6.0 + row * 7.0
				_rect(node, "Windows%d" % row, Vector2(4, y), Vector2(size.x - 8, 3), WINDOW if row == 1 else WINDOW_DIM)
				made += 1
			_rect(node, "Door", Vector2(size.x * 0.5 - 4, -8), Vector2(8, 8), OPENING)
			_rect(node, "Tank", Vector2(size.x * 0.18, -height - size.y * 0.7), Vector2(8, 7), METAL)
			_rect(node, "Antenna", Vector2(size.x * 0.72, -height - size.y * 0.7 - 10), Vector2(1, 12), METAL)
			_rect(node, "Plaque", Vector2(size.x * 0.5 + 6, -9), Vector2(12, 4), METAL)
			made += 4
		"hospital":
			# 四排窗 + 红十字 + 大门 + 急诊灯箱
			for row in range(4):
				var y := -height + 5.0 + row * 6.0
				_rect(node, "Windows%d" % row, Vector2(3, y), Vector2(size.x - 6, 2), WINDOW_DIM if row % 2 else WINDOW)
				made += 1
			_rect(node, "CrossV", Vector2(size.x * 0.5 - 1, -height + 8), Vector2(2, 7), SIGN)
			_rect(node, "CrossH", Vector2(size.x * 0.5 - 3, -height + 10), Vector2(6, 2), SIGN)
			_rect(node, "Door", Vector2(size.x * 0.5 - 5, -9), Vector2(10, 9), OPENING)
			_rect(node, "EmergencyLight", Vector2(3, -height + 2), Vector2(4, 3), WINDOW)
			made += 4
		"gas_station":
			# 低矮雨棚 + 两个加油岛 + 顶灯 + 价格牌
			_rect(node, "Canopy", Vector2(2, -height - 1), Vector2(size.x - 4, 4), METAL)
			_rect(node, "Pump0", Vector2(6, -height + 2), Vector2(3, 5), SIGN)
			_rect(node, "Pump1", Vector2(size.x - 10, -height + 2), Vector2(3, 5), SIGN)
			_rect(node, "RoofLight", Vector2(size.x * 0.5 - 1, -height - size.y * 0.5), Vector2(2, 2), WINDOW)
			_rect(node, "PriceBoard", Vector2(size.x - 6, -height - 8), Vector2(8, 5), SIGN)
			made += 5
		"fire_station":
			# 宽卷帘门 + 晾水塔 + 门号 01
			_rect(node, "Garage", Vector2(4, -11), Vector2(size.x - 8, 11), OPENING)
			for bar in range(3):
				_rect(node, "GarageBar%d" % bar, Vector2(6, -10 + bar * 3), Vector2(size.x - 12, 1), SIDE_FACE)
				made += 1
			_rect(node, "HoseTower", Vector2(size.x * 0.72, -height - size.y * 0.6 - 8), Vector2(5, 9), METAL)
			_rect(node, "Number0", Vector2(size.x * 0.5 - 3, -height + 5), Vector2(2, 4), WINDOW)
			_rect(node, "Number1", Vector2(size.x * 0.5 + 1, -height + 5), Vector2(1, 4), WINDOW)
			made += 4
		"military_base":
			# 围栏 + 天线杆 + 两排窄窗 + 旗杆
			for post in range(4):
				_rect(node, "Fence%d" % post, Vector2(2 + post * 10, -5), Vector2(1, 6), METAL)
				made += 1
			_rect(node, "Mast", Vector2(size.x * 0.8, -height - size.y * 0.6 - 14), Vector2(1, 16), METAL)
			for row in range(2):
				_rect(node, "Windows%d" % row, Vector2(6, -height + 6 + row * 5), Vector2(size.x - 14, 2), WINDOW_DIM)
				made += 1
			_rect(node, "FlagPole", Vector2(4, -height - 8), Vector2(1, 10), METAL)
			_rect(node, "Flag", Vector2(5, -height - 8), Vector2(4, 3), SIGN)
			made += 2
		_:
			return 0
	return made


## 街道不是空的：路灯、报废车、路障。全部程序画，坐标固定可断言。
func _build_street() -> void:
	var street := _node("Street")
	# 路灯：1px 杆 + 2×2 暖光（灯本身是暖色，和窗户同一个调子）
	var lamps := [Vector2(150, 112), Vector2(214, 152), Vector2(272, 120), Vector2(330, 168)]
	for index in range(lamps.size()):
		var at: Vector2 = lamps[index]
		_rect(street, "StreetLamp%d" % index, at, Vector2(1, 6), METAL)
		_rect(street, "StreetLampGlow%d" % index, at + Vector2(-1, -2), Vector2(3, 2), WINDOW)
	# 报废车：车身 + 车顶 + 两个轮子
	var car := _node("CarWreck")
	car.position = Vector2(196, 168)
	_rect(car, "CarBody", Vector2.ZERO, Vector2(12, 5), Color("#3a4652"))
	_rect(car, "CarRoof", Vector2(4, -3), Vector2(5, 3), Color("#26323f"))
	_rect(car, "CarWheel0", Vector2(1, 5), Vector2(2, 2), OPENING)
	_rect(car, "CarWheel1", Vector2(9, 5), Vector2(2, 2), OPENING)
	# 路障：两块斜挡板
	var barrier := _node("Barrier")
	barrier.position = Vector2(120, 150)
	_rect(barrier, "BarrierBoard0", Vector2.ZERO, Vector2(10, 2), SIGN)
	_rect(barrier, "BarrierBoard1", Vector2(2, 2), Vector2(10, 2), SIGN)
	_rect(barrier, "BarrierLeg0", Vector2(1, 4), Vector2(1, 3), METAL)
	_rect(barrier, "BarrierLeg1", Vector2(10, 4), Vector2(1, 3), METAL)


func _rect(parent: Node2D, node_name: String, at: Vector2, size: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.position = at
	rect.size = size
	rect.color = color
	parent.add_child(rect)


## 楼名：水平居中并按文字宽度夹进视口；垂直方向若放不下就翻到楼顶上，绝不被裁断。
func _build_labels() -> void:
	for id: String in BLOCKS:
		var spec: Dictionary = BLOCKS[id]
		var at: Vector2 = spec["at"]
		var height: float = spec["height"]
		var depth: float = (spec["size"] as Vector2).y
		var text := _travel.label_of(id)
		var width := PixelFont.width_of(text)
		var x := clampf(at.x - width * 0.5, 4.0, float(VIEW.x) - width - 4.0)
		var y := at.y + 6.0
		if y + 14.0 > float(VIEW.y) - 2.0:
			# 底下放不下就翻到楼顶上方（这一段永远在视口上半部，不会再溢出）
			y = clampf(at.y - height - depth - 16.0, 2.0, float(VIEW.y) - 16.0)
		PixelFont.draw(self, text, Vector2(x, y), LABEL)


## 走廊把「现在在哪栋、还有多少燃料、今天去过哪」告诉地图；地图自己算可去哪几栋。
func setup(from: String, fuel := 0, visited: Array[String] = []) -> void:
	current_building = from if BLOCKS.has(from) else "school"
	_visited = visited.duplicate()
	_neighbors.clear()
	_selectable.clear()
	_marks.clear()
	for id: String in BLOCKS:
		_marks[id] = {"fuel": 0, "risk": 0, "visited": id in _visited, "known": false}
	for id: String in _travel.neighbors(current_building):
		if not BLOCKS.has(id):
			continue
		_neighbors.append(id)
		var route := _travel.route(current_building, id)
		_marks[id] = {
			"fuel": int(route.get("fuel", 0)),
			"risk": int(route.get("risk", 0)),
			"visited": id in _visited,
			"known": true,
		}
		var verdict := _travel.can_travel(current_building, id, {"fuel": fuel, "actions_left": 1, "hour": 12})
		if bool(verdict.get("ok", false)):
			_selectable.append(id)
	var by_depth := func(a, b):
		var ay: float = float(BLOCKS[a]["at"].y)
		var by: float = float(BLOCKS[b]["at"].y)
		if is_equal_approx(ay, by):
			return float(BLOCKS[a]["at"].x) < float(BLOCKS[b]["at"].x)
		return ay < by
	_neighbors.sort_custom(by_depth)
	_selectable.sort_custom(by_depth)
	_selected = clampi(_selected, 0, maxi(0, _selectable.size() - 1))
	_refresh_reachability()
	_refresh_cursor()
	_refresh_marks()
	_refresh_current_marker()


func _refresh_reachability() -> void:
	for id: String in BLOCKS:
		var node: Node2D = get_node_or_null("Block_%s" % id) as Node2D
		if node == null:
			continue
		var factor := 1.0 if id in _selectable else 0.45
		node.modulate = Color(factor, factor, factor)


func _refresh_cursor() -> void:
	if _cursor == null:
		return
	for child: Node in _cursor.get_children():
		child.queue_free()
	if _selectable.is_empty():
		return
	var spec: Dictionary = BLOCKS[selected_id()]
	var at: Vector2 = spec["at"]
	var size: Vector2 = spec["size"]
	var height: float = spec["height"]
	var outline := Line2D.new()
	outline.name = "Bracket"
	outline.points = PackedVector2Array([
		Vector2(at.x - 2, at.y + 2),
		Vector2(at.x + size.x + size.y * 0.6 + 2, at.y + 2),
		Vector2(at.x + size.x + size.y * 0.6 + 2, at.y - height - size.y - 2),
		Vector2(at.x - 2, at.y - height - size.y - 2),
		Vector2(at.x - 2, at.y + 2),
	])
	outline.width = 1.0
	outline.default_color = CURSOR
	_cursor.add_child(outline)


func _refresh_marks() -> void:
	if _marks_root == null:
		return
	for child: Node in _marks_root.get_children():
		child.queue_free()
	for id: String in BLOCKS:
		var mark: Dictionary = _marks.get(id, {})
		if mark.is_empty():
			continue
		var spec: Dictionary = BLOCKS[id]
		var at: Vector2 = spec["at"]
		var size: Vector2 = spec["size"]
		var height: float = spec["height"]
		var top_y := at.y - height - size.y
		for index in range(int(mark.get("fuel", 0))):
			_mark_rect("Fuel_%s_%d" % [id, index], Vector2(at.x + index * 4, top_y - 6), Vector2(2, 2), Color("#9fb2bd"))
		var risk := int(mark.get("risk", 0))
		for index in range(mini(3, risk)):
			var tint := Color("#635e57") if index < 1 else Color("#8a4a3a")
			_mark_rect("Risk_%s_%d" % [id, index], Vector2(at.x + size.x + 2 + index * 3, top_y - 4), Vector2(2, 3), tint)
		if bool(mark.get("visited", false)):
			_mark_rect("Visited_%s" % id, Vector2(at.x, at.y + 20), Vector2(8, 2), CURSOR)


func _mark_rect(mark_name: String, at: Vector2, size: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.name = mark_name
	rect.position = at
	rect.size = size
	rect.color = color
	_marks_root.add_child(rect)


## D8：当前所在楼 —— 四个 3×3 角标包住整栋楼的 2.5D 轮廓，并闪烁提示「你在这里」。
func _refresh_current_marker() -> void:
	if _current_root == null:
		return
	for child: Node in _current_root.get_children():
		child.queue_free()
	_current_rect = Rect2()
	if not BLOCKS.has(current_building):
		return
	var spec: Dictionary = BLOCKS[current_building]
	var at: Vector2 = spec["at"]
	var size: Vector2 = spec["size"]
	var height: float = spec["height"]
	var top_left := Vector2(at.x - 3, at.y - height - size.y - 3)
	var bottom_right := Vector2(at.x + size.x + size.y * 0.6 + 3, at.y + 3)
	_current_rect = Rect2(top_left, bottom_right - top_left)
	var corners := [
		{"h": top_left, "v": top_left},
		{"h": Vector2(bottom_right.x - 3, top_left.y), "v": Vector2(bottom_right.x - 1, top_left.y)},
		{"h": Vector2(top_left.x, bottom_right.y - 1), "v": Vector2(top_left.x, bottom_right.y - 3)},
		{"h": Vector2(bottom_right.x - 3, bottom_right.y - 1), "v": Vector2(bottom_right.x - 1, bottom_right.y - 3)},
	]
	for index in range(corners.size()):
		var horizontal := ColorRect.new()
		horizontal.name = "CurrentCorner%d_h" % index
		horizontal.position = corners[index]["h"]
		horizontal.size = Vector2(3, 1)
		horizontal.color = CURRENT_MARKER
		_current_root.add_child(horizontal)
		var vertical := ColorRect.new()
		vertical.name = "CurrentCorner%d_v" % index
		vertical.position = corners[index]["v"]
		vertical.size = Vector2(1, 3)
		vertical.color = CURRENT_MARKER
		_current_root.add_child(vertical)
	_current_frames = 0
	_current_root.visible = true


## 闪烁：不靠透明度（像素风），整层可见性每 30 帧切换一次 15/15。
func _process(delta: float) -> void:
	if delta <= 0.0 or _current_root == null:
		return
	_current_frames += 1
	_current_root.visible = (_current_frames % CURRENT_MARKER_BLINK_FRAMES) < CURRENT_MARKER_BLINK_FRAMES / 2


## D8 门禁口。
func current_marker_visible() -> bool:
	return _current_root != null and _current_root.visible and _current_root.get_child_count() > 0


func current_marker_rect() -> Rect2:
	return _current_rect


func current_marker_phase() -> int:
	return _current_frames % CURRENT_MARKER_BLINK_FRAMES


func current_building_id() -> String:
	return current_building


## 供门禁读：这栋楼在地图上被标了什么。
func markers(id: String) -> Dictionary:
	return (_marks.get(id, {}) as Dictionary).duplicate()


func detail_count(id: String) -> int:
	return int(_detail_count.get(id, 0))


func move(delta: int) -> void:
	if _selectable.is_empty():
		return
	_selected = wrapi(_selected + delta, 0, _selectable.size())
	_refresh_cursor()


func selected_id() -> String:
	if _selectable.is_empty():
		return ""
	return _selectable[_selected]


func selectable_ids() -> Array[String]:
	return _selectable.duplicate()


func neighbor_ids() -> Array[String]:
	return _neighbors.duplicate()


func is_reachable(id: String) -> bool:
	return id in _selectable


func confirm() -> void:
	var id := selected_id()
	if id.is_empty():
		return
	chosen.emit(id)


func cancel() -> void:
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not interactive:
		return
	if not event is InputEventKey or event.is_echo() or not event.is_pressed():
		return
	if event.is_action_pressed("menu_up"):
		move(-1)
	elif event.is_action_pressed("menu_down"):
		move(1)
	elif event.is_action_pressed("menu_confirm"):
		confirm()
	elif event.is_action_pressed("menu_back"):
		cancel()
	get_viewport().set_input_as_handled()


func block_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in BLOCKS:
		out.append(id)
	out.sort()
	return out


func block_info(id: String) -> Dictionary:
	return (BLOCKS.get(id, {}) as Dictionary).duplicate()


func edge_count() -> int:
	return _edges.size()


func edges() -> Array[Dictionary]:
	return _edges.duplicate()
