extends Node2D
## 旅行图原型：俯视 + 2.5D 立体块。
##
## 为什么立体块是程序画的、不是生图画的：
##   1) 生图在 384×216 上边缘密度 0.20，细节会埋掉节点标记；
##   2) 节点坐标必须可断言（门禁要查「五块都在视口内、连线与 TravelService 一致」）；
##   3) 2.5D 只需要三条规则就成立 —— 顶面最亮、正面中间、右侧最暗，且块按底边 y 排序。
## 生图只当底纹（压暗 55%），几何一律程序画。

const VIEW := Vector2i(384, 216)
const BG_PATH := "res://art/generated_candidates/maps/map_topdown.png"
const SCRIM := Color(0.043, 0.067, 0.098, 0.6)

# 三档明度：光只从上方来（PIXEL_SPEC §4），所以顶面最亮、右侧最暗。
const TOP_FACE := Color("#3f5366")
const FRONT_FACE := Color("#26323f")
const SIDE_FACE := Color("#151d28")
const ROAD := Color("#182433")
const LABEL := Color("#9fb2bd")

# 每栋楼的落点与体积（宽、进深、高）。坐标是设计值，门禁直接断言它们。
const BLOCKS := {
	"school": {"at": Vector2(46, 150), "size": Vector2(40, 16), "height": 26},
	"gas_station": {"at": Vector2(120, 132), "size": Vector2(30, 14), "height": 12},
	"fire_station": {"at": Vector2(186, 166), "size": Vector2(32, 14), "height": 18},
	"hospital": {"at": Vector2(258, 128), "size": Vector2(34, 15), "height": 30},
	"military_base": {"at": Vector2(320, 172), "size": Vector2(36, 15), "height": 20},
}

var _travel := TravelService.new()
var _blocks: Dictionary = {}
var _edges: Array[Dictionary] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_background()
	if not _travel.load_all():
		push_error("TRAVEL_LOAD_FAILED: " + _travel.load_error())
	_build_roads()
	_build_blocks()
	_build_labels()


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
		var mid := (from + to) * 0.5
		var road := Line2D.new()
		road.name = "Road_%s_%s" % [str(edge["a"]), str(edge["b"])]
		road.points = PackedVector2Array([from, mid, to])
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

		# 正面
		var front := Polygon2D.new()
		front.name = "Front"
		front.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, -height), Vector2(0, -height),
		])
		front.color = FRONT_FACE
		node.add_child(front)
		# 顶面（向右上错开的平行四边形，给出“从斜上方看”的错觉）
		var top := Polygon2D.new()
		top.name = "Top"
		top.polygon = PackedVector2Array([
			Vector2(0, -height), Vector2(size.x, -height),
			Vector2(size.x + size.y * 0.6, -height - size.y),
			Vector2(size.y * 0.6, -height - size.y),
		])
		top.color = TOP_FACE
		node.add_child(top)
		# 右侧面
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
		var label := _travel.label_of(id)
		PixelFont.draw(self, label, Vector2(at.x, at.y + 4), LABEL)


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
