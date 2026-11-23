extends Node2D
## 旅行图：俯视 + 2.5D 立体块，可当走廊出口的选楼界面用。
##
## 为什么立体块是程序画的、不是生图画的：
##   1) 生图在 384×216 上边缘密度 0.198，细节会埋掉节点标记；
##   2) 节点坐标必须可断言（门禁要查「五块都在视口内、连线与 TravelService 一致」）；
##   3) 2.5D 只需要三条规则就成立 —— 顶面最亮、正面中间、右侧最暗，且块按底边 y 排序。
## 生图只当底纹（压暗 60%），几何一律程序画。

signal chosen(building_id: String)
signal cancelled

const VIEW := Vector2i(384, 216)
const BG_PATH := "res://art/generated_candidates/maps/map_topdown.png"
const SCRIM := Color(0.043, 0.067, 0.098, 0.6)

# 三档明度：光只从上方来（PIXEL_SPEC §4），所以顶面最亮、右侧最暗。
const TOP_FACE := Color("#3f5366")
const FRONT_FACE := Color("#26323f")
const SIDE_FACE := Color("#151d28")
const ROAD := Color("#182433")
const LABEL := Color("#9fb2bd")
const CURSOR := Color("#f6f6f0")

# 每栋楼的落点与体积（宽、进深、高）。坐标是设计值，门禁直接断言它们。
const BLOCKS := {
	"school": {"at": Vector2(46, 150), "size": Vector2(40, 16), "height": 26},
	"gas_station": {"at": Vector2(120, 132), "size": Vector2(30, 14), "height": 12},
	"fire_station": {"at": Vector2(186, 166), "size": Vector2(32, 14), "height": 18},
	"hospital": {"at": Vector2(258, 128), "size": Vector2(34, 15), "height": 30},
	"military_base": {"at": Vector2(320, 172), "size": Vector2(36, 15), "height": 20},
}

var current_building := "school"
## 作为走廊的叠加层时由走廊统一转发按键，地图自己不处理输入（避免两边抢键）。
var interactive := true
## 今天去过哪几栋（走廊传进来），用于地图上的「去过」标记。
var _visited: Array[String] = []
## 每栋楼的标记：{fuel, risk, visited, known}
## known = 是否相邻：不相邻的楼你不知道去一趟多贵，所以不标油耗与危险。
var _marks: Dictionary = {}
var _travel := TravelService.new()
var _blocks: Dictionary = {}
var _edges: Array[Dictionary] = []
var _selectable: Array[String] = []
var _neighbors: Array[String] = []
var _selected := 0
var _cursor: Node2D
var _hint_root: Node2D
var _marks_root: Node2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_actions()
	_build_background()
	if not _travel.load_all():
		push_error("TRAVEL_LOAD_FAILED: " + _travel.load_error())
	_build_roads()
	_build_blocks()
	_build_labels()
	_hint_root = _node("Hints")
	_cursor = _node("Cursor")
	_marks_root = _node("Marks")
	PixelFont.draw(_hint_root, "W/S 选楼 · E 出发 · Esc 留下", Vector2(8, 200), LABEL)
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
	# 2.5D 的关键：按底边 y 从远到近画，后面的块才不会压住前面的块。
	var ordered := BLOCKS.keys()
	ordered.sort_custom(func(a, b): return int(BLOCKS[a]["at"].y) < int(BLOCKS[b]["at"].y))
	for id: String in ordered:
		var spec: Dictionary = BLOCKS[id]
		var at: Vector2 = spec["at"]
		var size: Vector2 = spec["size"]
		var height: float = spec["height"]
		var node := Node2D.new()
		node.name = "Block_%s" % id
		node.position = at
		add_child(node)

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
		_blocks[id] = {"node": node, "height": height, "size": size, "at": at}


func _build_labels() -> void:
	for id: String in BLOCKS:
		var spec: Dictionary = BLOCKS[id]
		var at: Vector2 = spec["at"]
		PixelFont.draw(self, _travel.label_of(id), Vector2(at.x, at.y + 4), LABEL)


## 走廊把「现在在哪栋、还有多少燃料、今天去过哪」告诉地图；地图自己算可去哪几栋。
## 相邻但不可达的楼仍然画出来（灰着），玩家能看见"那里有医院，但没燃料去"。
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


func _refresh_reachability() -> void:
	for id: String in _blocks:
		var node: Node2D = (_blocks[id] as Dictionary)["node"]
		var factor := 1.0 if id in _selectable else 0.45
		for face_name: String in ["Top", "Front", "Side"]:
			var face := node.get_node_or_null(face_name) as Polygon2D
			if face == null:
				continue
			var base: Color = {"Top": TOP_FACE, "Front": FRONT_FACE, "Side": SIDE_FACE}[face_name]
			face.color = Color(base.r * factor, base.g * factor, base.b * factor)


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
		# 燃料需求：每个点 = 1 燃料，点在块顶正上方
		for index in range(int(mark.get("fuel", 0))):
			_add_mark_rect("Fuel_%s_%d" % [id, index], Vector2(at.x + index * 4, top_y - 6), Vector2(2, 2), Color("#9fb2bd"))
		# 危险度：右上方 1~3 个点，越亮越危险
		var risk := int(mark.get("risk", 0))
		for index in range(mini(3, risk)):
			var tint := Color("#635e57") if index < 1 else Color("#8a4a3a")
			_add_mark_rect("Risk_%s_%d" % [id, index], Vector2(at.x + size.x + 2 + index * 3, top_y - 4), Vector2(2, 3), tint)
		# 去过：标签下面一条短横
		if bool(mark.get("visited", false)):
			_add_mark_rect("Visited_%s" % id, Vector2(at.x, at.y + 14), Vector2(8, 2), Color("#f6f6f0"))


func _add_mark_rect(mark_name: String, at: Vector2, size: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.name = mark_name
	rect.position = at
	rect.size = size
	rect.color = color
	_marks_root.add_child(rect)


## 供门禁读：这栋楼在地图上被标了什么。
func markers(id: String) -> Dictionary:
	return (_marks.get(id, {}) as Dictionary).duplicate()


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
	# 选中框：把「正面 + 顶面」的外轮廓描一圈，比只框正面更容易看出前后关系。
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


## 相邻的全部楼（含灰着的），用于绘制与「你知道那里有东西」的信息量。
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
	for id: String in _blocks:
		out.append(id)
	out.sort()
	return out


func block_info(id: String) -> Dictionary:
	return (_blocks.get(id, {}) as Dictionary).duplicate()


func edge_count() -> int:
	return _edges.size()


func edges() -> Array[Dictionary]:
	return _edges.duplicate()
