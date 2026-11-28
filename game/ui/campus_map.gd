class_name CampusMap
extends Node2D
## 校园鸟瞰图：把 data/campus/<id>.json 画成一张俯视图。
##
## 为什么要它：五栋楼以前只是「同一间走廊换一套 tile」，玩家记不住任何一座学校。
## 学校模板现在是一整张图（长条主教学楼 + 操场 + 看台 + 广场 + 宿舍食堂 + L 形角楼 + 校门），
## 这张图同时是开场旁白的「记住布局」略缩图、门禁截图和以后的小地图底图。
##
## 坐标约定：数据里的 rect 就是 384×216 设计空间里的像素矩形，北在上；这里不缩放。

const MAP_DIR := "res://data/campus"
const COLOR_GROUND := Color("#0a0e13")
const COLOR_PAVEMENT := Color("#141c26")
const COLOR_ROAD := Color("#202f3f")
const COLOR_ROAD_LINE := Color("#3d566e")
const COLOR_ROOF := Color("#26333f")
const COLOR_ROOF_EDGE := Color("#4a6076")
const COLOR_WINDOW := Color("#7b93a8")
const COLOR_TRACK := Color("#6d302c")
const COLOR_TRACK_LINE := Color("#a4553f")
const COLOR_FIELD := Color("#2f5233")
const COLOR_TREE := Color("#22381f")
const COLOR_TREE_LIT := Color("#3a5c30")
const COLOR_GLASS := Color("#414a69")
const COLOR_GLASS_LIT := Color("#5e6a9c")
const COLOR_GATE := Color("#c8873a")
const COLOR_INK := Color("#c3d2dc")
const COLOR_LABEL_BG := Color("#070a0e")
const COLOR_LABEL_SHADOW := Color("#000000")

var data: Dictionary = {}
var load_error := ""

var _map_size := Vector2(384, 216)
var _label_root: Node2D


func _ready() -> void:
	_label_root = Node2D.new()
	_label_root.name = "MapLabels"
	add_child(_label_root)


## 读一张校园图。失败时 load_error 里留原因（门禁与开场都靠它判是否可用）。
func load_for(campus_id: String) -> bool:
	load_error = ""
	var path := "%s/%s.json" % [MAP_DIR, campus_id]
	if not FileAccess.file_exists(path):
		load_error = "missing " + path
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		load_error = "not an object: " + path
		return false
	data = parsed as Dictionary
	if str(data.get("schema", "")) != "campus-map.v1":
		load_error = "schema mismatch: " + str(data.get("schema", ""))
		data = {}
		return false
	var canvas: Array = data.get("canvas", [])
	if canvas.size() == 2:
		_map_size = Vector2(float(canvas[0]), float(canvas[1]))
	_draw_labels()
	queue_redraw()
	return true


func map_size() -> Vector2:
	return _map_size


func regions() -> Array:
	var value: Variant = data.get("regions", [])
	return value if value is Array else []


func region_of(region_id: String) -> Dictionary:
	for row: Variant in regions():
		if row is Dictionary and str((row as Dictionary).get("id", "")) == region_id:
			return row as Dictionary
	return {}


func beat_ids() -> Array[String]:
	var out: Array[String] = []
	var intro_value: Variant = data.get("intro", {})
	if not intro_value is Dictionary:
		return out
	for row: Variant in (intro_value as Dictionary).get("beats", []):
		if row is Dictionary:
			out.append(str((row as Dictionary).get("id", "")))
	return out


## 区块标签：只标数据里写了 map_label 的（12px 字在 384 宽里放 10 个会糊成一片）。
func _draw_labels() -> void:
	if _label_root == null:
		return
	for child: Node in _label_root.get_children():
		child.queue_free()
	for row: Variant in regions():
		if not row is Dictionary:
			continue
		var region: Dictionary = row as Dictionary
		var text := str(region.get("map_label", ""))
		if text.is_empty():
			continue
		var rect: Rect2 = _rect_of(region.get("rect", []))
		if rect.size == Vector2.ZERO:
			continue
		var text_w := float(PixelFont.width_of(text))
		var x := clampf(rect.position.x + (rect.size.x - text_w) * 0.5, 2.0, _map_size.x - text_w - 2.0)
		var y := rect.end.y + 2.0
		if y > _map_size.y - 13.0:
			y = rect.position.y - 13.0
		# 底板 + 1px 阴影：压在屋顶或道路上都能读。
		draw_label_backing(x, y, text_w)
		PixelFont.draw(_label_root, text, Vector2(x + 1.0, y + 1.0), COLOR_LABEL_SHADOW)
		PixelFont.draw(_label_root, text, Vector2(x, y), COLOR_INK)


## 标签底板用 Polygon2D 画在标签层里（_draw 的画笔和 PixelFont 的节点不在同一层）。
func draw_label_backing(x: float, y: float, text_w: float) -> void:
	var backing := Polygon2D.new()
	backing.name = "LabelBg"
	backing.position = Vector2(x - 1.0, y - 1.0)
	backing.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(text_w + 2.0, 0),
		Vector2(text_w + 2.0, 13.0), Vector2(0, 13.0),
	])
	backing.color = COLOR_LABEL_BG
	backing.modulate.a = 0.86
	_label_root.add_child(backing)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _map_size), COLOR_GROUND, true)
	if data.is_empty():
		return
	# 铺装：建筑与道路之外的整块地先铺一层比草地亮的深色，读起来像操场外的水泥地。
	draw_rect(Rect2(0, 60, 356, 136), COLOR_PAVEMENT, true)
	_draw_roads()
	_draw_trees()
	for row: Variant in regions():
		if row is Dictionary:
			_draw_region(row as Dictionary)
	_draw_border()


func _draw_border() -> void:
	# 1px 外框：门禁截图上能一眼看出「这是一张图」，不靠背景猜边界。
	draw_rect(Rect2(Vector2.ZERO, _map_size), COLOR_ROOF_EDGE, false, 1.0)


func _draw_roads() -> void:
	for row: Variant in data.get("roads", []):
		if not row is Dictionary:
			continue
		var rect: Rect2 = _rect_of((row as Dictionary).get("rect", []))
		if rect.size == Vector2.ZERO:
			continue
		draw_rect(rect, COLOR_ROAD, true)
		# 中线虚线：横路画横线、竖路画竖线，间距 8px，和像素网格对齐。
		if rect.size.x >= rect.size.y:
			var y := floorf(rect.position.y + rect.size.y * 0.5)
			var x := rect.position.x + 2.0
			while x < rect.end.x - 2.0:
				draw_rect(Rect2(x, y, 3, 1), COLOR_ROAD_LINE, true)
				x += 8.0
		else:
			var line_x := floorf(rect.position.x + rect.size.x * 0.5)
			var line_y := rect.position.y + 2.0
			while line_y < rect.end.y - 2.0:
				draw_rect(Rect2(line_x, line_y, 1, 3), COLOR_ROAD_LINE, true)
				line_y += 8.0


func _draw_trees() -> void:
	for row: Variant in data.get("trees", []):
		if not row is Array or (row as Array).size() < 3:
			continue
		var items: Array = row as Array
		var center := Vector2(float(items[0]), float(items[1]))
		var size := float(items[2])
		draw_rect(Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)), COLOR_TREE, true)
		draw_rect(Rect2(center - Vector2(size, size) * 0.5 + Vector2(1, 1), Vector2(size - 2, 1)),
			COLOR_TREE_LIT, true)


func _draw_region(row: Dictionary) -> void:
	var kind := str(row.get("kind", ""))
	match kind:
		"field":
			_draw_field(row)
		"plaza":
			_draw_plaza(row)
		"lot":
			_draw_lot(row)
		"gate":
			_draw_building(row)
			_draw_gate(row)
		_:
			_draw_building(row)


## 楼体：屋顶 + 上沿高光 + 窗格。parts 用来拼 L 形（角楼），没有就画 rect。
func _draw_building(row: Dictionary) -> void:
	var tint := Color(str(row.get("tone", "#1b2734")))
	for part: Variant in _parts_of(row):
		var rect: Rect2 = part
		draw_rect(rect, tint, true)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), COLOR_ROOF_EDGE, true)
		draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), COLOR_ROOF_EDGE, true)
		_draw_windows(rect)
		draw_rect(rect, COLOR_ROOF_EDGE, false, 1.0)
	var tower: Variant = row.get("tower", null)
	if tower is Array:
		var t: Rect2 = _rect_of(tower)
		draw_rect(t, COLOR_GLASS, true)
		# 玻璃转角：斜向亮线，俯视下也能认出「那个转角的幕墙」。
		var step := 0.0
		while step < t.size.x and step < t.size.y:
			draw_line(t.position + Vector2(step, 0), t.position + Vector2(0, step), COLOR_GLASS_LIT, 1.0)
			step += 4.0
		draw_rect(t, COLOR_ROOF_EDGE, false, 1.0)


func _draw_windows(rect: Rect2) -> void:
	# 窗格起点避开 1px 边：每 6px 一个 2×1 的点，读起来是「一排排教室窗」。
	var y := rect.position.y + 4.0
	while y < rect.end.y - 2.0:
		var x := rect.position.x + 3.0
		while x < rect.end.x - 3.0:
			draw_rect(Rect2(x, y, 2, 1), COLOR_WINDOW, true)
			x += 6.0
		y += 6.0


func _draw_field(row: Dictionary) -> void:
	var field: Dictionary = row.get("field", {}) if row.get("field") is Dictionary else {}
	var center_arr: Array = field.get("center", [])
	var outer: Array = field.get("outer", [])
	var inner: Array = field.get("inner", [])
	if center_arr.size() != 2 or outer.size() != 2 or inner.size() != 2:
		return
	var center := Vector2(float(center_arr[0]), float(center_arr[1]))
	var outer_r := Vector2(float(outer[0]), float(outer[1]))
	var inner_r := Vector2(float(inner[0]), float(inner[1]))
	_fill_ellipse(center, outer_r, COLOR_TRACK)
	_fill_ellipse(center, inner_r, COLOR_FIELD)
	# 跑道分道线：内外各一圈，1px 亮线。
	_stroke_ellipse(center, outer_r - Vector2(4, 4), COLOR_TRACK_LINE)
	_stroke_ellipse(center, inner_r + Vector2(2, 2), COLOR_TRACK_LINE)
	# 球场中线 + 中圈，让「这是操场」不用靠标签。
	draw_rect(Rect2(center.x - inner_r.x, center.y, inner_r.x * 2.0, 1), COLOR_TRACK_LINE, true)
	_stroke_ellipse(center, Vector2(8, 6), COLOR_TRACK_LINE)


func _draw_plaza(row: Dictionary) -> void:
	var rect: Rect2 = _rect_of(row.get("rect", []))
	if rect.size == Vector2.ZERO:
		return
	# 铺装：隔行错缝的浅色砖，和道路区分开。
	var y := rect.position.y
	var row_index := 0
	while y < rect.end.y:
		var x := rect.position.x + (0.0 if row_index % 2 == 0 else 4.0)
		while x < rect.end.x:
			draw_rect(Rect2(x, y, 3, 1), COLOR_ROAD_LINE, true)
			x += 8.0
		y += 6.0
		row_index += 1
	for planter: Variant in row.get("planters", []):
		var p: Rect2 = _rect_of(planter)
		if p.size == Vector2.ZERO:
			continue
		draw_rect(p, COLOR_FIELD, true)
		draw_rect(p, COLOR_ROOF_EDGE, false, 1.0)


func _draw_lot(row: Dictionary) -> void:
	var rect: Rect2 = _rect_of(row.get("rect", []))
	if rect.size == Vector2.ZERO:
		return
	draw_rect(rect, Color("#151d27"), true)
	for slot: Variant in row.get("slots", []):
		var s: Rect2 = _rect_of(slot)
		if s.size == Vector2.ZERO:
			continue
		draw_rect(s, COLOR_ROOF, true)
		draw_rect(s, COLOR_ROOF_EDGE, false, 1.0)
		draw_rect(Rect2(s.position + Vector2(2, 2), Vector2(s.size.x - 4, 2)), COLOR_WINDOW, true)


func _draw_gate(row: Dictionary) -> void:
	var entrance: Variant = row.get("entrance", null)
	if not entrance is Array or (entrance as Array).size() != 2:
		return
	var at := Vector2(float((entrance as Array)[0]), float((entrance as Array)[1]))
	# 门口那道橙线 + 一个小方章：校门在整张图上唯一带暖色的东西。
	draw_rect(Rect2(at.x - 10.0, at.y, 20, 2), COLOR_GATE, true)
	draw_rect(Rect2(at.x - 3.0, at.y - 4.0, 6, 5), COLOR_GATE, true)


func _parts_of(row: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var parts: Variant = row.get("parts", null)
	if parts is Array and not (parts as Array).is_empty():
		for part: Variant in parts as Array:
			var rect: Rect2 = _rect_of(part)
			if rect.size != Vector2.ZERO:
				out.append(rect)
		return out
	var single: Rect2 = _rect_of(row.get("rect", []))
	if single.size != Vector2.ZERO:
		out.append(single)
	return out


func _rect_of(value: Variant) -> Rect2:
	if not value is Array or (value as Array).size() != 4:
		return Rect2()
	var items: Array = value as Array
	return Rect2(float(items[0]), float(items[1]), float(items[2]), float(items[3]))


func _ellipse_points(center: Vector2, radius: Vector2, segments := 28) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y).round())
	return points


func _fill_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_colored_polygon(_ellipse_points(center, radius), color)


func _stroke_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := _ellipse_points(center, radius)
	points.append(points[0])
	draw_polyline(points, color, 1.0)
