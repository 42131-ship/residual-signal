extends Node2D
## DEC-20261123-D1：本工具只读。若能写入 data/nodes.json，
## 就会成为第二个权威，使 D1 的决策前提失效。
## 无头运行请加载挂载本脚本的场景；--script 入口需要 MainLoop。

const DataLayerScript = preload("res://game/runtime/data_layer.gd")

const GRID_STEP := Vector2(384.0, 216.0)
const GRID_SIZE := Vector2(64.0, 64.0)
const AXIS_SIZE := Vector2(96.0, 24.0)
const ROOM_SIZE := Vector2(48.0, 48.0)
const PAN_STEP := 32.0
const ZOOM_STEP := 1.15

var _nodes: Array[Dictionary] = []
var _cells: Dictionary[Vector2i, bool] = {}
var _centers: Dictionary[String, Vector2] = {}
var _axis_ids: Dictionary[String, bool] = {}


func _ready() -> void:
	var data := DataLayerScript.new()
	if not data.load_all():
		push_error("节点拓扑：数据加载失败。")
		return

	_nodes = data.nodes()
	for node in _nodes:
		var node_id := str(node["node_id"])
		var cell := Vector2i(int(node["axis_x"]), int(node["depth_layer"]))
		_cells[cell] = true
		_centers[node_id] = _cell_center(cell)
		if node["role"] == "axis":
			_axis_ids[node_id] = true

	if DisplayServer.get_name() != "headless":
		queue_redraw()


func _draw() -> void:
	if _nodes.is_empty() or DisplayServer.get_name() == "headless":
		return

	for cell: Vector2i in _cells:
		var rect := Rect2(_cell_center(cell) - GRID_SIZE * 0.5, GRID_SIZE)
		draw_rect(rect, _grid_color(cell.y), false, 1.0)

	# 连线先画，避免盖住节点和标签。
	for node in _nodes:
		var source_id := str(node["node_id"])
		var source: Vector2 = _centers[source_id]
		for target in node["linked_nodes"]:
			var target_id := str(target)
			if not _centers.has(target_id):
				continue
			var color := Color("#59636f")
			if _axis_ids.has(source_id) and _axis_ids.has(target_id):
				color = Color("#a5aeb9")
			draw_line(source, _centers[target_id], color, 1.0)

	var font := ThemeDB.fallback_font
	for node in _nodes:
		var node_id := str(node["node_id"])
		var is_axis := _axis_ids.has(node_id)
		var box_size := AXIS_SIZE if is_axis else ROOM_SIZE
		var rect := Rect2(_centers[node_id] - box_size * 0.5, box_size)
		draw_rect(rect, Color("#bd7846") if is_axis else Color("#526779"))

		if node["lockable"] == true:
			draw_rect(rect.grow(2.0), Color("#fff1ab"), false, 1.0)

		for tag in node["tags"]:
			if str(tag).begins_with("teaching_"):
				var dot := Vector2(rect.end.x - 5.0, rect.position.y + 5.0)
				draw_circle(dot, 2.5, Color("#a9f3da"))
				break

		if font != null:
			var label_pos := Vector2(rect.position.x, rect.end.y + 10.0)
			draw_string(font, label_pos, node_id, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * GRID_STEP


func _grid_color(depth_layer: int) -> Color:
	match depth_layer:
		1:
			return Color("#687989")
		-1:
			return Color("#363a42")
		_:
			return Color("#55575c")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return

	# 只改视图变换。
	match key.keycode:
		KEY_LEFT:
			position.x -= PAN_STEP
		KEY_RIGHT:
			position.x += PAN_STEP
		KEY_UP:
			position.y -= PAN_STEP
		KEY_DOWN:
			position.y += PAN_STEP
		KEY_PLUS, KEY_KP_ADD:
			_zoom_by(ZOOM_STEP)
		KEY_EQUAL:
			if not key.shift_pressed:
				return
			_zoom_by(ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_by(1.0 / ZOOM_STEP)
		_:
			return
	get_viewport().set_input_as_handled()


func _zoom_by(factor: float) -> void:
	var zoom := clampf(scale.x * factor, 0.25, 4.0)
	scale = Vector2(zoom, zoom)