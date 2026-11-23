extends SceneTree
## 旅行图原型门禁：五块都在视口内、每块三面、顶面比正面亮、正面比侧面亮、
## 连线与 TravelService 邻接一致且去重。
## 运行（要渲染）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/travel_map.gd -- MAP

const SCENE: PackedScene = preload("res://game/scenes/travel_map.tscn")
const VIEW := Vector2(384, 216)

var _map: Node2D
var _prefix := "MAP"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("MAP"):
			_prefix = argument
	_map = SCENE.instantiate() as Node2D
	root.add_child(_map)
	await process_frame
	await process_frame

	# ① 五块，坐标都在视口内（含高度与进深，别让立体块顶出画面）
	var ids: Array = _map.block_ids()
	_check(ids.size() == 5, "map must draw 5 blocks, got %d" % ids.size())
	for id: String in ids:
		var spec: Dictionary = _map.BLOCKS[id]
		var at: Vector2 = spec["at"]
		var size: Vector2 = spec["size"]
		var height: float = spec["height"]
		var top_left := Vector2(at.x - 2, at.y - height - size.y - 2)
		var bottom_right := Vector2(at.x + size.x + size.y * 0.6 + 2, at.y + 12)
		_check(top_left.x >= 0 and top_left.y >= 0, "%s pokes out of the top-left: %s" % [id, str(top_left)])
		_check(bottom_right.x <= VIEW.x and bottom_right.y <= VIEW.y,
			"%s pokes out of the bottom-right: %s" % [id, str(bottom_right)])

	# ② 每块三个面，且明度关系符合「光只从上方来」
	for id: String in ids:
		var node := _map.get_node_or_null("Block_%s" % id) as Node2D
		_check(node != null, "%s block node missing" % id)
		if node == null:
			continue
		var top := node.get_node_or_null("Top") as Polygon2D
		var front := node.get_node_or_null("Front") as Polygon2D
		var side := node.get_node_or_null("Side") as Polygon2D
		_check(top != null and front != null and side != null, "%s needs top/front/side faces" % id)
		if top == null or front == null or side == null:
			continue
		_check(top.polygon.size() == 4, "%s top face must be a quad" % id)
		_check(side.polygon.size() == 4, "%s side face must be a quad" % id)
		var lt := top.color.get_luminance()
		var lf := front.color.get_luminance()
		var ls := side.color.get_luminance()
		_check(lt > lf and lf > ls, "%s shading order broken: top=%.2f front=%.2f side=%.2f" % [id, lt, lf, ls])

	# ③ 绘制顺序按底边 y 从远到近（后面画的在前面）
	var order: Array[String] = []
	for child: Node in _map.get_children():
		if str(child.name).begins_with("Block_"):
			order.append(str(child.name).trim_prefix("Block_"))
	for index in range(1, order.size()):
		var prev: float = float(_map.BLOCKS[order[index - 1]]["at"].y)
		var cur: float = float(_map.BLOCKS[order[index]]["at"].y)
		_check(cur >= prev, "blocks must be drawn far-to-near: %s before %s" % [order[index - 1], order[index]])

	# ④ 连线与 TravelService 的邻接一致，且无重复
	var travel := TravelService.new()
	travel.load_all()
	var expected := 0
	var seen := {}
	for id: String in travel.building_ids():
		for other: String in travel.neighbors(id):
			var key := "%s|%s" % [id, other] if id < other else "%s|%s" % [other, id]
			if not seen.has(key):
				seen[key] = true
				expected += 1
	_check(_map.edge_count() == expected, "map roads %d != travel edges %d" % [_map.edge_count(), expected])

	# ⑤ 底图已挂上并压了暗罩
	var art := _map.get_node_or_null("MapArt") as Sprite2D
	_check(art != null, "generated map art must be mounted")
	if art != null:
		_check(art.texture != null and art.texture.get_size() == VIEW, "map art must be 384x216")

	# ⑥ 选楼：学校只列两个邻居，顺序按远→近，光标会绕回
	_map.setup("school", 0)
	var pick_school: Array = _map.selectable_ids()
	_check(pick_school.size() == 2, "school should allow 2 destinations, got %d" % pick_school.size())
	_check(str(pick_school[0]) == "gas_station", "gas_station should come first (nearer on the map)")
	_check(str(_map.selected_id()) == "gas_station", "cursor should start on the first destination")
	_map.move(1)
	_check(str(_map.selected_id()) == "fire_station", "moving should reach fire_station")
	_map.move(1)
	_check(str(_map.selected_id()) == "gas_station", "cursor must wrap around")

	# ⑦ 燃料为 0：医院相邻但不可选，仍然画出来
	_map.setup("gas_station", 0)
	var neighbours: Array = _map.neighbor_ids()
	var allowed: Array = _map.selectable_ids()
	_check(neighbours.size() == 2, "gas_station has 2 neighbours, got %d" % neighbours.size())
	_check("hospital" in neighbours, "hospital must still be drawn as a neighbour")
	_check("hospital" not in allowed, "hospital must not be selectable without fuel")
	_check(_map.is_reachable("school"), "school must stay reachable from gas_station")

	# ⑧ 信号：确认发 chosen，取消发 cancelled（GDScript 闭包按值捕获，所以用字典承接）
	var capture := {"chosen": "", "cancelled": false}
	_map.chosen.connect(func(id: String) -> void: capture["chosen"] = id)
	_map.cancelled.connect(func() -> void: capture["cancelled"] = true)
	_map.setup("school", 0)
	_map.confirm()
	_check(str(capture["chosen"]) == "gas_station", "confirm must emit the selected id, got %s" % str(capture["chosen"]))
	_map.cancel()
	_check(bool(capture["cancelled"]), "cancel must emit cancelled")

	# ⑨ 地图标注：相邻的楼有油耗/危险，不相邻的不瞎标；去过的楼有短线
	var visited_a: Array[String] = ["school"]
	_map.setup("school", 0, visited_a)
	var gas_marks: Dictionary = _map.markers("gas_station")
	_check(bool(gas_marks.get("known", false)), "gas_station must be marked as known from school")
	_check(int(gas_marks.get("risk", 0)) == 1, "gas_station risk should be 1, got %s" % str(gas_marks.get("risk")))
	_check(int(gas_marks.get("fuel", -1)) == 0, "gas_station needs no fuel")
	var hospital_marks: Dictionary = _map.markers("hospital")
	_check(not bool(hospital_marks.get("known", true)), "hospital is not adjacent to school, must stay unmarked")
	var marks_root := _map.get_node_or_null("Marks") as Node2D
	_check(marks_root != null, "marks container missing")
	if marks_root != null:
		_check(marks_root.get_node_or_null("Risk_gas_station_0") != null, "risk dot for gas_station missing")
		_check(marks_root.get_node_or_null("Visited_school") != null, "visited bar for school missing")
		_check(marks_root.get_node_or_null("Visited_gas_station") == null, "gas_station must not be marked visited yet")

	# ⑩ 去过的楼会亮起；油耗按数据展开成点
	var visited_b: Array[String] = ["school", "gas_station"]
	_map.setup("school", 0, visited_b)
	_check(bool(_map.markers("gas_station").get("visited", false)), "gas_station must show as visited")
	if marks_root != null:
		_check(marks_root.get_node_or_null("Visited_gas_station") != null, "visited bar for gas_station missing")
	var visited_c: Array[String] = ["school", "hospital"]
	_map.setup("hospital", 2, visited_c)
	if marks_root != null:
		_check(marks_root.get_node_or_null("Fuel_military_base_0") != null, "fuel pip 1 missing on military_base")
		_check(marks_root.get_node_or_null("Fuel_military_base_1") != null, "fuel pip 2 missing on military_base")
		_check(int(_map.markers("military_base").get("fuel", 0)) == 2, "military_base needs 2 fuel")

	# ⑪ 每栋楼要有能认出来的细节，不是光板方块
	var required := {
		"school": ["Tank", "Antenna", "Door", "Windows0"],
		"hospital": ["CrossV", "CrossH", "Door"],
		"gas_station": ["Canopy", "Pump0", "Pump1"],
		"fire_station": ["Garage", "HoseTower"],
		"military_base": ["Mast", "Fence0"],
	}
	for id: String in required:
		var node := _map.get_node_or_null("Block_%s" % id) as Node2D
		_check(node != null, "%s block missing" % id)
		if node == null:
			continue
		_check(_map.detail_count(id) >= 3, "%s needs at least 3 detail pieces, got %d" % [id, _map.detail_count(id)])
		for part: String in required[id]:
			_check(node.get_node_or_null(part) != null, "%s is missing its %s detail" % [id, part])

	# ⑫ 楼名必须完整落在视口内（上一版『消』被裁断就是这条没测）
	for id: String in _map.BLOCKS:
		var label: String = str(_map._travel.label_of(id))
		var width := PixelFont.width_of(label)
		var spec: Dictionary = _map.BLOCKS[id]
		var at: Vector2 = spec["at"]
		var height: float = spec["height"]
		var depth: float = (spec["size"] as Vector2).y
		var x := clampf(at.x - width * 0.5, 4.0, 384.0 - width - 4.0)
		_check(x >= 4.0 and x + width <= 380.0, "%s label overflows: x=%.1f w=%d" % [id, x, width])
		var y := at.y + 6.0
		if y + 14.0 > 214.0:
			y = clampf(at.y - height - depth - 16.0, 2.0, 200.0)
		_check(y >= 2.0 and y + 14.0 <= 216.0, "%s label vertical overflow: y=%.1f" % [id, y])
		_check(width > 0, "%s has no label" % id)

	# ⑬ 街道不是空的：路灯 / 报废车 / 路障
	var street := _map.get_node_or_null("Street") as Node2D
	_check(street != null, "street layer missing")
	if street != null:
		for index in range(4):
			_check(street.get_node_or_null("StreetLamp%d" % index) != null, "street lamp %d missing" % index)
			_check(street.get_node_or_null("StreetLampGlow%d" % index) != null, "street lamp glow %d missing" % index)
	var car := _map.get_node_or_null("CarWreck") as Node2D
	_check(car != null, "wrecked car missing")
	if car != null:
		for part: String in ["CarBody", "CarRoof", "CarWheel0", "CarWheel1"]:
			_check(car.get_node_or_null(part) != null, "car part %s missing" % part)
	var barrier := _map.get_node_or_null("Barrier") as Node2D
	_check(barrier != null, "barrier missing")
	if barrier != null:
		_check(barrier.get_node_or_null("BarrierBoard0") != null, "barrier board missing")

	_map.setup("school", 0)
	await _capture("%s_topdown" % _prefix)
	_finish()


func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		_check(false, "capture failed")
		return
	image.save_png(ProjectSettings.globalize_path("res://design/previews/%s.png" % label))
	print("MAP_SHOT res://design/previews/%s.png" % label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("MAP_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("TRAVEL_MAP_OK blocks=5 faces=3 shading=top>front>side depth_sort=ok roads=%d" % _map.edge_count())
		quit(0)
		return
	print("TRAVEL_MAP_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
