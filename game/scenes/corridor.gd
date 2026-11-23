extends Node2D

const SHEET := preload("res://art/generated_candidates/tiles/TL-04_corridor_v2.png")
const CHAR_PATH := "res://art/generated_candidates/characters/SPR-player_32x48.png"
const INSPECTION_PATH := "res://data/prop_inspections.json"
const TILE_SIZE := 16
const WORLD_TILES := Vector2i(40, 14)
const VIEW_SIZE := Vector2i(384, 216)
# 可行走区域（玩家脚底坐标）：x 夹在左右墙内，纵深轴 W/S 只在 y=128..216。
const WALK_TOP := 128.0
const WALK_BOTTOM := 216.0
const WALK_LEFT := 14.0
const WALK_RIGHT := 602.0
## 纵深容差：玩家脚底与交互锚点的 y 差超过它就不算「站在道具前面」。
## 水平距离仍是 28px 主判据（同距时按朝向裁决），保持 Stage 2 的 28px 边界语义。
const INTERACT_DEPTH_TOLERANCE := 24.0
## 手电开灯时的光锥半径（关灯 = 归零，画面整体压暗）。
const FLASHLIGHT_RADIUS := 240.0
## 背包容量（拾取上限）。
const INVENTORY_CAPACITY := 10
## 挥击视觉持续帧数。
const ATTACK_FRAMES := 4
const TILE_INDEX := {
	"void": 0, "wall": 1, "dado": 2, "cracked": 3,
	"base": 4, "floor": 5, "wet": 6, "scuff": 7,
}
## 房间分隔：在 tile x=12 / x=26 处做门洞式隔断（上方墙垛 + 门楣 + 地面门槛），
## 下方留出 136px 高的净空让玩家穿过去。三个区块：A 区 / B 区 / C 区。
const ROOM_PARTITION_TILES: Array[int] = [12, 26]
const ROOM_LABELS: Array[String] = ["A 区", "B 区", "C 区"]
## 墙垛高度：门洞净空从 y=80 一直到地面，玩家 40px 身高（脚底 128..216）可以通过。
const ROOM_LINTEL_Y := 80
const ROOM_PARTITION_WIDTH := 32
## 门：E 开关；关闭时挡路；挂锁可锁；钥匙/近战武器可撬开。
const DOOR_TOP := 80.0
const DOOR_BOTTOM := 216.0
const DOOR_REACH_X := 44.0

var _world: Node2D
var _player: Player
var _camera: Camera2D
var _light_material: ShaderMaterial
var _last_step_was_running := false
var _steps := 0
var _flashlight_on := true
var _inspection_range_x := 0.0
var _inspection_records: Dictionary = {}
var _inspection_ui: Dictionary = {}
var _inspection_order: Array[String] = []
var _inspection_target := ""
var _inspection_open := false
var _inspection_ui_enabled := true
var _inspection_prompt_root: Node2D
var _inspection_prompt_layer: CanvasLayer
var _inspection_panel_root: Node2D
var _loot: LootService
var _inventory: InventoryService
var _inventory_open := false
var _inventory_index := 0
var _inventory_layer: CanvasLayer
var _inventory_panel_root: Node2D
var _hud_stats_root: Node2D
var _attack_visual: Polygon2D
## 门状态：{tile_x, center_x, leaf, shape, handle, open, locked}
var _doors: Array[Dictionary] = []
var _nearest_door := -1
var _door_prompt_layer: CanvasLayer
var _door_prompt_root: Node2D
var _door_prompt_text := ""
var _door_toast_text := ""
var _door_toast_frames := 0
## 玩家状态：物资/体力/噪声/已装备武器/挥击次数（背包与使用系统的落地数据）。
var _supplies := 0.8
var _health := 1.0
var _noise := 0
var _equipped := ""
var _attacks := 0
var _attack_frames := 0
var _inventory_toast := ""
## 面板当前内容（测试与调试用，不参与渲染）。
var _panel_title := ""
var _panel_lines: Array = []
## 走廊 demo 的世界日（HUD 写死 DAY 3，等接入 WorldState 后替换）。
var _world_day := 3


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_actions()
	_build_corridor()
	_build_actor()
	_apply_depth_sort()
	_load_inspections()
	_load_loot()
	_inventory = InventoryService.new(INVENTORY_CAPACITY)
	_build_camera()
	_build_hud()
	_build_inventory_ui()
	_build_door_prompt()
	_build_attack_visual()
	_build_flashlight()
	_refresh_hud_stats()


func _place_tile(tile_name: String, tile_x: int, tile_y: int, from_x := 0, width := TILE_SIZE) -> void:
	var tile_index: int = TILE_INDEX[tile_name]
	var tile := Sprite2D.new()
	tile.texture = SHEET
	tile.region_enabled = true
	tile.region_rect = Rect2(tile_index * TILE_SIZE + from_x, 0, width, TILE_SIZE)
	tile.centered = false
	tile.position = Vector2(tile_x * TILE_SIZE + from_x, tile_y * TILE_SIZE)
	_world.add_child(tile)


func _build_corridor() -> void:
	_world = Node2D.new()
	_world.name = "World"
	_world.z_index = -1
	add_child(_world)

	var door: Sprite2D = $Props/door_broken
	var door_top_left := Vector2i(door.position + door.get_rect().position)
	var door_cell := door_top_left / TILE_SIZE
	var recess := Polygon2D.new()
	recess.name = "ClassroomRecess"
	recess.position = Vector2(door_top_left)
	recess.polygon = PackedVector2Array([Vector2.ZERO, Vector2(32, 0), Vector2(32, 32), Vector2(0, 32)])
	recess.color = Color("#0b1119")
	_world.add_child(recess)
	var interior_floor := Polygon2D.new()
	interior_floor.name = "ClassroomInteriorFloor"
	interior_floor.position = Vector2(door_top_left)
	interior_floor.polygon = PackedVector2Array([
		Vector2(3, 24), Vector2(29, 24), Vector2(32, 32), Vector2(0, 32),
	])
	interior_floor.color = Color("#182433")
	_world.add_child(interior_floor)
	var interior_floor_edge := Polygon2D.new()
	interior_floor_edge.name = "ClassroomInteriorFloorEdge"
	interior_floor_edge.position = Vector2(door_top_left + Vector2i(3, 24))
	interior_floor_edge.polygon = PackedVector2Array([Vector2.ZERO, Vector2(26, 0), Vector2(26, 1), Vector2(0, 1)])
	interior_floor_edge.color = Color("#1f2e3f")
	_world.add_child(interior_floor_edge)

	for x in range(WORLD_TILES.x):
		for y in range(8):
			var wall_type := "cracked" if x % 11 == 4 else "wall"
			if y == 6:
				wall_type = "dado"
			elif y == 7:
				wall_type = "base"
			var doorway := x in range(door_cell.x, door_cell.x + 2) and y in range(door_cell.y, door_cell.y + 2)
			if not doorway:
				_place_tile(wall_type, x, y)
		for y in range(8, WORLD_TILES.y):
			var floor_type := "wet" if x % 9 == 3 else ("scuff" if x % 7 == 5 else "floor")
			_place_tile(floor_type, x, y)

	_build_floor_seams()
	_build_exit_cues()
	_build_room_partitions()


func _build_room_partitions() -> void:
	for index: int in ROOM_PARTITION_TILES.size():
		var tile_x: int = ROOM_PARTITION_TILES[index]
		var origin := Vector2(tile_x * TILE_SIZE, 0)
		# 墙垛主体（压暗，与普通墙面区分）
		var body := Polygon2D.new()
		body.name = "RoomPartition_%d" % tile_x
		body.position = origin
		body.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(ROOM_PARTITION_WIDTH, 0),
			Vector2(ROOM_PARTITION_WIDTH, ROOM_LINTEL_Y), Vector2(0, ROOM_LINTEL_Y),
		])
		body.color = Color("#0b1119")
		_world.add_child(body)
		# 门楣：底部一条亮线，读出「这是门洞」而不是墙没画完
		var lintel := Polygon2D.new()
		lintel.name = "RoomLintel_%d" % tile_x
		lintel.position = origin + Vector2(0, ROOM_LINTEL_Y - 2)
		lintel.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(ROOM_PARTITION_WIDTH, 0),
			Vector2(ROOM_PARTITION_WIDTH, 2), Vector2(0, 2),
		])
		lintel.color = Color("#635e57")
		_world.add_child(lintel)
		# 左右立柱高光，让 32px 宽的墙垛有体积感
		var edge := Polygon2D.new()
		edge.name = "RoomPartitionEdge_%d" % tile_x
		edge.position = origin + Vector2(ROOM_PARTITION_WIDTH - 1, 0)
		edge.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(1, 0), Vector2(1, ROOM_LINTEL_Y), Vector2(0, ROOM_LINTEL_Y),
		])
		edge.color = Color("#354b60")
		_world.add_child(edge)
		# 地面门槛：门洞下方一条横线，提示房间边界
		var threshold := Polygon2D.new()
		threshold.name = "RoomThreshold_%d" % tile_x
		threshold.position = origin + Vector2(0, TILE_SIZE * 8)
		threshold.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(ROOM_PARTITION_WIDTH, 0),
			Vector2(ROOM_PARTITION_WIDTH, 2), Vector2(0, 2),
		])
		threshold.color = Color("#354b60")
		_world.add_child(threshold)
		_build_door(tile_x)
		# 区块标签（A 区 / B 区 / C 区），标在下一段墙面上
	# 标签放在每个房间起点：A 区最左，B/C 区在各自门洞后两格
	var label_tiles: Array[int] = [
		2,
		ROOM_PARTITION_TILES[0] + 2,
		ROOM_PARTITION_TILES[1] + 2,
	]
	for index: int in mini(ROOM_LABELS.size(), label_tiles.size()):
		PixelFont.draw(_world, ROOM_LABELS[index], Vector2(label_tiles[index] * TILE_SIZE, 44), Color("#354b60"))


func _build_door(tile_x: int) -> void:
	var center_x := float(tile_x * TILE_SIZE + ROOM_PARTITION_WIDTH / 2)
	# 门板（关闭时可见）：整块门洞高度的板子 + 一个暖色门把手
	var leaf := Polygon2D.new()
	leaf.name = "DoorLeaf_%d" % tile_x
	leaf.position = Vector2(tile_x * TILE_SIZE, DOOR_TOP)
	leaf.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(ROOM_PARTITION_WIDTH, 0),
		Vector2(ROOM_PARTITION_WIDTH, DOOR_BOTTOM - DOOR_TOP), Vector2(0, DOOR_BOTTOM - DOOR_TOP),
	])
	leaf.color = Color("#1f2e3f")
	leaf.visible = false
	_world.add_child(leaf)
	var handle := Polygon2D.new()
	handle.name = "DoorHandle_%d" % tile_x
	handle.position = Vector2(tile_x * TILE_SIZE + ROOM_PARTITION_WIDTH - 9, DOOR_TOP + 58)
	handle.polygon = PackedVector2Array([Vector2.ZERO, Vector2(3, 0), Vector2(3, 7), Vector2(0, 7)])
	handle.color = Color("#b0702e")
	handle.visible = false
	_world.add_child(handle)
	# 碰撞体：门关上时挡住整条门洞（玩家高 40px，脚底 128..216 都过不去）
	var body := StaticBody2D.new()
	body.name = "DoorBody_%d" % tile_x
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "DoorShape_%d" % tile_x
	var rect := RectangleShape2D.new()
	rect.size = Vector2(ROOM_PARTITION_WIDTH, DOOR_BOTTOM - DOOR_TOP)
	shape.shape = rect
	shape.position = Vector2(center_x, (DOOR_TOP + DOOR_BOTTOM) / 2.0)
	shape.disabled = true
	body.add_child(shape)
	add_child(body)
	_doors.append({
		"tile_x": tile_x,
		"center_x": center_x,
		"leaf": leaf,
		"handle": handle,
		"shape": shape,
		"open": true,
		"locked": false,
	})


func _build_door_prompt() -> void:
	_door_prompt_layer = CanvasLayer.new()
	_door_prompt_layer.name = "DoorPrompt"
	_door_prompt_layer.layer = 31
	add_child(_door_prompt_layer)
	_door_prompt_root = Node2D.new()
	_door_prompt_root.name = "DoorPromptRoot"
	_door_prompt_layer.add_child(_door_prompt_root)


func _update_doors() -> void:
	var previous := _nearest_door
	_nearest_door = -1
	if _player != null:
		for index: int in _doors.size():
			if absf(_player.global_position.x - float(_doors[index]["center_x"])) <= DOOR_REACH_X:
				_nearest_door = index
				break
	if _nearest_door != previous:
		_draw_door_prompt()
	if _door_toast_frames > 0:
		_door_toast_frames -= 1
		if _door_toast_frames == 0:
			_door_toast_text = ""
			_draw_door_prompt()


func _draw_door_prompt() -> void:
	if _door_prompt_root == null:
		return
	for child: Node in _door_prompt_root.get_children():
		child.queue_free()
	_door_prompt_root.visible = false
	_door_prompt_text = ""
	if _inspection_ui_enabled and not _inspection_open and not _inventory_open and _nearest_door >= 0:
		var door: Dictionary = _doors[_nearest_door]
		_door_prompt_text = _door_action_text(door)
		if not _door_prompt_text.is_empty():
			_door_prompt_root.visible = true
			var width := 44 + PixelFont.width_of(_door_prompt_text)
			var screen_x := float(door["center_x"]) - _camera.position.x + VIEW_SIZE.x / 2.0
			var x := clampf(screen_x - width / 2.0, 4.0, VIEW_SIZE.x - width - 4.0)
			var y := 20.0
			_add_rect_polygon(_door_prompt_root, "DoorBg", Vector2(x, y), Vector2(width, 20), Color("#0b1119"))
			_add_ui_frame(_door_prompt_root, Vector2(x, y), Vector2(width, 20), Color("#354b60"))
			PixelFont.draw(_door_prompt_root, _door_prompt_text, Vector2(x + 6, y + 4), Color("#f6f6f0"))
	if _door_toast_frames > 0 and not _door_toast_text.is_empty():
		PixelFont.draw(_door_prompt_root, _door_toast_text, Vector2(16, 44), Color("#f6f6f0"))


func _door_action_text(door: Dictionary) -> String:
	if bool(door["locked"]):
		if _inventory != null and (_inventory.has("keys") or _is_melee_equipped()):
			return "E 撬开"
		return "锁着"
	if bool(door["open"]):
		return "E 关门"
	if _inventory != null and _inventory.has("padlock"):
		return "E 锁门"
	return "E 开门"


func _is_melee_equipped() -> bool:
	if _equipped.is_empty():
		return false
	return str(_loot.item_effect(_equipped).get("equip", "")) == "melee"


func _toggle_door(index: int) -> void:
	if index < 0 or index >= _doors.size():
		return
	var door: Dictionary = _doors[index]
	if bool(door["locked"]):
		if _inventory.has("keys") or _is_melee_equipped():
			door["locked"] = false
			door["open"] = true
			_apply_door_state(index)
			_door_toast("撬开了锁")
		else:
			_door_toast("锁着，需要钥匙或撬棍")
		return
	if bool(door["open"]):
		door["open"] = false
		_apply_door_state(index)
		_door_toast("关上了门")
	elif _inventory.has("padlock"):
		_inventory.remove("padlock", 1)
		door["locked"] = true
		door["open"] = false
		_apply_door_state(index)
		_door_toast("挂锁锁上了")
	else:
		door["open"] = true
		_apply_door_state(index)
		_door_toast("打开了门")


func _apply_door_state(index: int) -> void:
	var door: Dictionary = _doors[index]
	var is_open := bool(door["open"])
	(door["shape"] as CollisionShape2D).disabled = is_open
	(door["leaf"] as Polygon2D).visible = not is_open
	(door["handle"] as Polygon2D).visible = not is_open
	_draw_door_prompt()


func _door_toast(text: String) -> void:
	_door_toast_text = text
	_door_toast_frames = 90
	_draw_door_prompt()


func _build_floor_seams() -> void:
	var image := Image.create(WORLD_TILES.x * TILE_SIZE, 6 * TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var seam := Color("#182433")
	for y in range(32, image.get_height(), 32):
		for x in range(image.get_width()):
			image.set_pixel(x, y, seam)
	for row in range(3):
		var row_top := row * 32
		var seam_offset := 32 if row % 2 == 0 else 16
		for x in range(seam_offset, image.get_width(), 32):
			for y in range(row_top + 1, row_top + 32):
				image.set_pixel(x, y, seam)
	var seams := Sprite2D.new()
	seams.name = "FloorPanelSeams"
	seams.texture = ImageTexture.create_from_image(image)
	seams.centered = false
	seams.position = Vector2(0, 8 * TILE_SIZE)
	seams.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world.add_child(seams)


func _build_exit_cues() -> void:
	var sign := Node2D.new()
	sign.name = "ExitDirectionSign"
	sign.position = Vector2(384, 108)
	_world.add_child(sign)
	_add_rect_polygon(sign, "Backing", Vector2.ZERO, Vector2(20, 10), Color("#0b1119"))
	_add_rect_polygon(sign, "ColdField", Vector2(1, 1), Vector2(18, 8), Color("#245c58"))
	var arrow := Polygon2D.new()
	arrow.name = "ArrowRight"
	arrow.polygon = PackedVector2Array([
		Vector2(4, 3), Vector2(12, 3), Vector2(12, 1), Vector2(16, 5),
		Vector2(12, 9), Vector2(12, 7), Vector2(4, 7),
	])
	arrow.color = Color("#4fbfae")
	sign.add_child(arrow)

	var end_wall := Node2D.new()
	end_wall.name = "CorridorEndWall"
	end_wall.position = Vector2(576, 48)
	_world.add_child(end_wall)
	_add_rect_polygon(end_wall, "WallFace", Vector2.ZERO, Vector2(32, 80), Color("#0b1119"))
	_add_rect_polygon(end_wall, "LeftPillar", Vector2(0, 0), Vector2(4, 80), Color("#111a26"))
	_add_rect_polygon(end_wall, "RightPillar", Vector2(28, 0), Vector2(4, 80), Color("#111a26"))
	_add_rect_polygon(end_wall, "DoorRecess", Vector2(5, 17), Vector2(22, 63), Color("#060a12"))
	_add_rect_polygon(end_wall, "DoorLeaf", Vector2(8, 21), Vector2(16, 59), Color("#0b1119"))
	_add_rect_polygon(end_wall, "DoorHighlight", Vector2(8, 21), Vector2(2, 58), Color("#111a26"))
	_add_rect_polygon(end_wall, "DoorHandle", Vector2(23, 47), Vector2(2, 4), Color("#354b60"))
	_add_rect_polygon(end_wall, "Threshold", Vector2(4, 78), Vector2(24, 2), Color("#354b60"))
	_add_rect_polygon(end_wall, "ExitLampFrame", Vector2(12, 5), Vector2(8, 6), Color("#0b1119"))
	_add_rect_polygon(end_wall, "ExitLamp", Vector2(13, 6), Vector2(6, 3), Color("#4fbfae"))
	var terminal_wall := Node2D.new()
	terminal_wall.name = "TerminalWallFace"
	terminal_wall.position = Vector2(608, 0)
	_world.add_child(terminal_wall)
	_add_rect_polygon(terminal_wall, "Face", Vector2.ZERO, Vector2(32, 128), Color("#354b60"))
	_add_rect_polygon(terminal_wall, "LeadingEdge", Vector2.ZERO, Vector2(4, 128), Color("#0b1119"))
	_add_rect_polygon(terminal_wall, "RightCorner", Vector2(28, 0), Vector2(4, 128), Color("#060a12"))
	_add_rect_polygon(terminal_wall, "WallFloorContact", Vector2(0, 127), Vector2(32, 3), Color("#060a12"))
	_add_rect_polygon(terminal_wall, "FloorContactShade", Vector2(0, 130), Vector2(32, 6), Color("#111a26"))


func _add_rect_polygon(parent: Node, node_name: String, at: Vector2, size: Vector2, tint: Color) -> Polygon2D:
	var shape := Polygon2D.new()
	shape.name = node_name
	shape.position = at
	shape.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y),
	])
	shape.color = tint
	parent.add_child(shape)
	return shape


func _apply_depth_sort() -> void:
	# 纵深轴：y 越大越靠近镜头。用 z_index 做前后遮挡，玩家每帧更新自己的值。
	for child: Node in $Props.get_children():
		var prop := child as Sprite2D
		if prop != null:
			prop.z_index = int(prop.position.y)


func _add_box_collision(parent: Node2D, at: Vector2, dimensions: Vector2, node_name: String) -> void:
	var collision := CollisionShape2D.new()
	collision.name = node_name
	var rectangle := RectangleShape2D.new()
	rectangle.size = dimensions
	collision.shape = rectangle
	collision.position = at
	parent.add_child(collision)


func _build_actor() -> void:
	_player = Player.new()
	_player.name = "Player"
	_player.position = Vector2(2 * TILE_SIZE, 8 * TILE_SIZE)
	_player.walk_bounds = Rect2(WALK_LEFT, WALK_TOP, WALK_RIGHT - WALK_LEFT, WALK_BOTTOM - WALK_TOP)
	var texture := load(CHAR_PATH) as Texture2D
	if texture == null:
		push_error("Could not load player character texture: %s" % CHAR_PATH)
	else:
		var sprite := Sprite2D.new()
		sprite.name = "BodySprite"
		sprite.texture = texture
		sprite.centered = false
		# 32×48 原生帧：脚底在第 46 行、水平居中（±16），所以左上角相对脚底是 (-16,-46)。
		sprite.position = Vector2(-16, -46)
		_player.add_child(sprite)
	add_child(_player)
	for child in _player.get_children():
		if child is Camera2D:
			(child as Camera2D).enabled = false
	_player.stepped.connect(_on_player_stepped)


func _on_player_stepped(is_running: bool) -> void:
	_last_step_was_running = is_running
	_steps += 1


func _ensure_actions() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	# 纵深轴：W/S（与 A/D 正交，见 design/PIXEL_SPEC.md §2）
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	# 三档速度：默认步行；Shift 疾跑；Ctrl 蹲下潜行（最慢）。
	_add_action("sprint", [KEY_SHIFT])
	_add_action("crouch", [KEY_CTRL])
	# E = 上下文交互（搜索/拾取），V = 查看文本，F = 手电。
	_add_action("pickup", [KEY_E])
	_add_action("view", [KEY_V])
	_add_action("cancel_inspect", [KEY_ESCAPE])
	_add_action("toggle_light", [KEY_F])
	_add_action("drop", [KEY_Q])
	# 战斗与背包键位已按 v0.2 定下，系统未实现，先注册 InputMap。
	_add_mouse_action("attack", MOUSE_BUTTON_LEFT)
	_add_action("inventory", [KEY_TAB])


func _add_mouse_action(action_name: String, button: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event: InputEvent in InputMap.action_get_events(action_name):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == button:
			return
	var button_event := InputEventMouseButton.new()
	button_event.button_index = button
	InputMap.action_add_event(action_name, button_event)


func _add_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for keycode: int in keys:
		var already_bound := false
		for event: InputEvent in InputMap.action_get_events(action_name):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
				already_bound = true
				break
		if already_bound:
			continue
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action_name, key_event)


func _load_inspections() -> void:
	var file := FileAccess.open(INSPECTION_PATH, FileAccess.READ)
	if file == null:
		push_error("INSPECTION_DATA_MISSING: " + INSPECTION_PATH)
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		push_error("INSPECTION_JSON:%d: %s" % [parser.get_error_line(), parser.get_error_message()])
		return
	var data: Variant = parser.data
	if not data is Dictionary or data.get("schema") != "corridor-inspections.v1":
		push_error("INSPECTION_SCHEMA_INVALID")
		return
	var range_value: Variant = data.get("interaction_range_x")
	var records_value: Variant = data.get("records")
	if not range_value is int and not range_value is float:
		push_error("INSPECTION_RANGE_INVALID")
		return
	if float(range_value) <= 0.0 or not is_finite(float(range_value)) or not records_value is Array:
		push_error("INSPECTION_DATA_INVALID")
		return

	var seen := {}
	var ui_value: Variant = data.get("ui", {})
	if ui_value is Dictionary:
		_inspection_ui = ui_value.duplicate(true)
	for value: Variant in records_value:
		if not value is Dictionary:
			push_error("INSPECTION_RECORD_INVALID")
			return
		var record: Dictionary = value
		var id := str(record.get("id", ""))
		var title := str(record.get("title", ""))
		var lines_value: Variant = record.get("lines")
		if id.is_empty() or title.is_empty() or seen.has(id) or not lines_value is Array or lines_value.is_empty():
			push_error("INSPECTION_RECORD_FIELDS_INVALID: " + id)
			return
		for line: Variant in lines_value:
			if not line is String or str(line).is_empty():
				push_error("INSPECTION_LINE_INVALID: " + id)
				return
		var prop := $Props.get_node_or_null(NodePath(id)) as Sprite2D
		if prop == null:
			push_error("INSPECTION_PROP_MISSING: " + id)
			return
		seen[id] = true
		_inspection_records[id] = record.duplicate(true)
		_inspection_order.append(id)
	if _inspection_order.size() != $Props.get_child_count():
		push_error("INSPECTION_PROP_COUNT_MISMATCH")
		_inspection_records.clear()
		_inspection_order.clear()
		return
	_inspection_range_x = float(range_value)


func _nearest_inspection_id() -> String:
	if _player == null or _inspection_records.is_empty():
		return ""
	var best_id := ""
	var best_distance := INF
	var ties: Array[String] = []
	for id: String in _inspection_order:
		var prop := $Props.get_node_or_null(NodePath(id)) as Sprite2D
		if not is_instance_valid(prop):
			continue
		var record: Dictionary = _inspection_records[id]
		var anchor := _inspection_anchor(prop, record)
		# 先过纵深容差（W/S 走进房间后才有意义），再按水平距离取最近。
		if absf(_player.global_position.y - anchor.y) > INTERACT_DEPTH_TOLERANCE:
			continue
		var distance := absf(anchor.x - _player.global_position.x)
		if distance > _inspection_range_x:
			continue
		if distance < best_distance and not is_equal_approx(distance, best_distance):
			best_distance = distance
			ties = [id]
		elif is_equal_approx(distance, best_distance):
			ties.append(id)
	if ties.is_empty():
		return ""
	if ties.size() == 1:
		return ties[0]
	ties.sort()
	var facing := _player.facing_x
	for id: String in ties:
		var prop := $Props.get_node_or_null(NodePath(id)) as Sprite2D
		var anchor := _inspection_anchor(prop, _inspection_records[id])
		if signf(anchor.x - _player.global_position.x) == facing:
			return id
	return ties[0]


func _inspection_anchor(prop: Sprite2D, record: Dictionary) -> Vector2:
	# 墙面道具（y < 128）落到房间内缘的锚点；地面道具用自己的 y。
	# 这样「走到柜子前面」是按二维距离判定的，不再是旧的只看 x。
	var anchor_x := prop.global_position.x + float(record.get("focus_offset_x", 0.0))
	var anchor_y := clampf(prop.global_position.y, WALK_TOP + 8.0, WALK_BOTTOM)
	return Vector2(anchor_x, anchor_y)


func _build_inspection_ui(_parent: Node) -> void:
	_inspection_prompt_layer = CanvasLayer.new()
	_inspection_prompt_layer.name = "InspectionUI"
	_inspection_prompt_layer.layer = 30
	add_child(_inspection_prompt_layer)
	_inspection_prompt_root = Node2D.new()
	_inspection_prompt_root.name = "InspectPrompt"
	_inspection_prompt_root.visible = false
	_inspection_prompt_layer.add_child(_inspection_prompt_root)
	_inspection_panel_root = Node2D.new()
	_inspection_panel_root.name = "InspectPanel"
	_inspection_panel_root.visible = false
	_inspection_prompt_layer.add_child(_inspection_panel_root)


func _draw_inspection_prompt(id: String) -> void:
	if _inspection_prompt_root == null:
		return
	for child: Node in _inspection_prompt_root.get_children():
		child.queue_free()
	_inspection_prompt_root.visible = not id.is_empty() and not _inspection_open
	if id.is_empty():
		return
	var record: Dictionary = _inspection_records.get(id, {})
	var title := str(record.get("title", ""))
	var key_text := "V"
	var verb := str(_inspection_ui.get("inspect", "查看"))
	if _loot != null and _loot.has_container(id):
		# E = 上下文搜索；容器名字来自 data/loot/containers.json。
		title = _loot.label_of(id)
		key_text = "E"
		verb = "搜索"
	var width := 44 + PixelFont.width_of(title) + maxi(0, PixelFont.width_of(verb) - 12)
	var x := clampf(_player.position.x - _camera.position.x + VIEW_SIZE.x / 2.0 - width / 2.0, 4.0, VIEW_SIZE.x - width - 4.0)
	var y := 20.0
	_inspection_prompt_root.set_meta("target_id", id)
	_add_rect_polygon(_inspection_prompt_root, "PromptBg", Vector2(x, y), Vector2(width, 20), Color("#0b1119"))
	_add_ui_frame(_inspection_prompt_root, Vector2(x, y), Vector2(width, 20), Color("#354b60"))
	PixelFont.draw(_inspection_prompt_root, key_text, Vector2(x + 6, y + 6), Color("#9fb2bd"))
	PixelFont.draw(_inspection_prompt_root, verb, Vector2(x + 14, y + 4), Color("#9fb2bd"))
	PixelFont.draw(_inspection_prompt_root, title, Vector2(x + 14 + PixelFont.width_of(verb), y + 4), Color("#f6f6f0"))


func _show_inspection(id: String) -> void:
	var record: Dictionary = _inspection_records.get(id, {})
	if record.is_empty():
		return
	_show_panel(str(record.get("title", "")), record.get("lines", []), id)


func _search_container(id: String) -> void:
	if _loot == null:
		return
	# 剧情模式：容器搜过一次就永久为空（不按天刷新）。
	var result: Dictionary = _loot.search(id, _world_day, 0, "story")
	if not bool(result.get("ok", false)):
		_show_panel(_loot.label_of(id), ["已经搜过一次", "剧情模式不会刷新"], id)
		return
	var items: Array = result.get("items", [])
	if items.is_empty():
		_show_panel(_loot.label_of(id), ["里面是空的", "连灰都没有"], id)
		return
	var ids: Array = []
	for item: Dictionary in items:
		ids.append(str(item.get("id", "")))
	var bulk: Dictionary = _inventory.add_many(ids)
	var added: Array = bulk.get("added", [])
	var rejected: Array = bulk.get("rejected", [])
	var lines := _loot_lines(added)
	if rejected.is_empty():
		lines[1] = "已放入背包（%d/%d）" % [_inventory.total(), _inventory.capacity]
	else:
		lines[1] = "背包满了，剩 %d 件没拿" % rejected.size()
	_show_panel(_loot.label_of(id), lines, id)
	_refresh_hud_stats()


func _loot_lines(item_ids: Array) -> Array[String]:
	var names := PackedStringArray()
	for value: Variant in item_ids:
		names.append(_loot.item_name(str(value)))
	var joined := "、".join(names)
	var first := "找到：" + joined.substr(0, 16)
	return [first, "共 %d 件" % item_ids.size()]


func _load_loot() -> void:
	_loot = LootService.new()
	if not _loot.load_all():
		push_error("LOOT_LOAD_FAILED: " + _loot.load_error())


func _show_panel(title: String, lines: Array, id: String) -> void:
	for child: Node in _inspection_panel_root.get_children():
		child.queue_free()
	_panel_title = title
	_panel_lines = lines.duplicate()
	var panel_x := 8.0
	var panel_y := 154.0
	var panel_w := 368.0
	var panel_h := 54.0
	_add_rect_polygon(_inspection_panel_root, "PanelBg", Vector2(panel_x, panel_y), Vector2(panel_w, panel_h), Color("#0b1119"))
	_add_ui_frame(_inspection_panel_root, Vector2(panel_x, panel_y), Vector2(panel_w, panel_h), Color("#635e57"))
	PixelFont.draw(_inspection_panel_root, title, Vector2(16, 160), Color("#f6f6f0"))
	for index: int in mini(2, lines.size()):
		PixelFont.draw(_inspection_panel_root, str(lines[index]), Vector2(16, 176 + index * 14), Color("#9fb2bd"))
	PixelFont.draw(_inspection_panel_root, "ESC", Vector2(326, 160), Color("#9fb2bd"))
	_inspection_panel_root.set_meta("inspection_id", id)
	_inspection_panel_root.visible = true
	_inspection_open = true
	_player._movement_locked = true
	_draw_inspection_prompt("")


func _close_inspection() -> void:
	if not _inspection_open:
		return
	_inspection_open = false
	_inspection_panel_root.visible = false
	_player._movement_locked = false
	_player._previous_global_position = _player.global_position
	_inspection_target = ""
	_draw_inspection_prompt("")


func set_inspection_ui_enabled(enabled: bool) -> void:
	_inspection_ui_enabled = enabled
	if _inspection_prompt_layer != null:
		_inspection_prompt_layer.visible = enabled


func _add_ui_frame(parent: Node, at: Vector2, size: Vector2, color: Color) -> void:
	var x := int(at.x)
	var y := int(at.y)
	var width := int(size.x)
	var height := int(size.y)
	for rect: Array in [
		[Vector2(x, y), Vector2(width, 1)],
		[Vector2(x, y + height - 1), Vector2(width, 1)],
		[Vector2(x, y), Vector2(1, height)],
		[Vector2(x + width - 1, y), Vector2(1, height)],
	]:
		var edge := ColorRect.new()
		edge.position = rect[0]
		edge.size = rect[1]
		edge.color = color
		parent.add_child(edge)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.position_smoothing_enabled = false
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = WORLD_TILES.x * TILE_SIZE
	_camera.limit_bottom = WORLD_TILES.y * TILE_SIZE
	_camera.position = VIEW_SIZE / 2
	add_child(_camera)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 20
	add_child(layer)

	var ink := Color("#9fb2bd")
	var dim := Color("#354b60")
	var day3_mark := Color("#0b1119")
	var frame_color := Color("#635e57")
	PixelFont.draw(layer, "DAY 3", Vector2(8, 8), ink)
	_build_hud_stats_root(layer)

	var widths := [44, 36, 28, 44, 24, 40]
	for index in range(widths.size()):
		var bar := ColorRect.new()
		var column_x := 276 if index < 3 else 332
		bar.position = Vector2(column_x, 12 + (index % 3) * 7)
		bar.size = Vector2(widths[index], 3)
		bar.color = day3_mark if index == 2 else dim
		layer.add_child(bar)

	var slot_size := 12
	var slot_gap := 4
	var total_width := slot_size * 3 + slot_gap * 2
	var slot_x := int((VIEW_SIZE.x - total_width) / 2.0)
	for index in range(3):
		_frame(layer, slot_x + index * (slot_size + slot_gap), VIEW_SIZE.y - 28, slot_size, slot_size, frame_color)

	_build_inspection_ui(layer)
	var envelope_x := VIEW_SIZE.x - 15
	var envelope_y := VIEW_SIZE.y - 21
	_frame(layer, envelope_x, envelope_y, 7, 5, frame_color)
	var notification := ColorRect.new()
	notification.position = Vector2(envelope_x + 6, envelope_y - 1)
	notification.size = Vector2(2, 2)
	notification.color = day3_mark
	layer.add_child(notification)


func _build_inventory_ui() -> void:
	_inventory_layer = CanvasLayer.new()
	_inventory_layer.name = "InventoryUI"
	_inventory_layer.layer = 40
	_inventory_layer.visible = false
	add_child(_inventory_layer)
	_inventory_panel_root = Node2D.new()
	_inventory_panel_root.name = "InventoryPanel"
	_inventory_layer.add_child(_inventory_panel_root)


func _build_attack_visual() -> void:
	_attack_visual = Polygon2D.new()
	_attack_visual.name = "AttackArc"
	_attack_visual.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(16, 2), Vector2(12, 28), Vector2(4, 26),
	])
	_attack_visual.color = Color("#f6f6f0")
	_attack_visual.visible = false
	add_child(_attack_visual)


func _build_hud_stats_root(parent: Node) -> void:
	_hud_stats_root = Node2D.new()
	_hud_stats_root.name = "HudStats"
	parent.add_child(_hud_stats_root)


func _refresh_hud_stats() -> void:
	if _hud_stats_root == null:
		return
	for child: Node in _hud_stats_root.get_children():
		child.queue_free()
	PixelFont.draw(_hud_stats_root, "物资 %d" % int(round(_supplies * 100.0)), Vector2(8, 20), Color("#9fb2bd"))
	PixelFont.draw(_hud_stats_root, "体力 %d" % int(round(_health * 100.0)), Vector2(8, 30), Color("#9fb2bd"))


func _open_inventory() -> void:
	if _inspection_open:
		return
	_inventory_open = true
	_inventory_index = 0
	_inventory_toast = ""
	_player._movement_locked = true
	_inventory_layer.visible = true
	_render_inventory()


func _close_inventory() -> void:
	_inventory_open = false
	_inventory_layer.visible = false
	_player._movement_locked = false
	_player._previous_global_position = _player.global_position


func _render_inventory() -> void:
	if _inventory_panel_root == null or not _inventory_open:
		return
	for child: Node in _inventory_panel_root.get_children():
		child.queue_free()
	var panel_x := 8.0
	var panel_y := 24.0
	var panel_w := 368.0
	var panel_h := 190.0
	_add_rect_polygon(_inventory_panel_root, "InvBg", Vector2(panel_x, panel_y), Vector2(panel_w, panel_h), Color("#0b1119"))
	_add_ui_frame(_inventory_panel_root, Vector2(panel_x, panel_y), Vector2(panel_w, panel_h), Color("#635e57"))
	var ids := _inventory.ids()
	var title := "背包 %d/%d" % [_inventory.total(), _inventory.capacity]
	if not _equipped.is_empty():
		title += "  装备 " + _loot.item_name(_equipped)
	PixelFont.draw(_inventory_panel_root, title, Vector2(16, panel_y + 4), Color("#f6f6f0"))
	if ids.is_empty():
		PixelFont.draw(_inventory_panel_root, "背包是空的", Vector2(16, panel_y + 26), Color("#9fb2bd"))
		PixelFont.draw(_inventory_panel_root, "搜柜子会拿到东西", Vector2(16, panel_y + 42), Color("#9fb2bd"))
	else:
		_inventory_index = clampi(_inventory_index, 0, ids.size() - 1)
		for row: int in mini(9, ids.size()):
			var item_id: String = ids[row]
			var row_y := panel_y + 22 + row * 13
			if row == _inventory_index:
				_add_rect_polygon(_inventory_panel_root, "Sel%d" % row,
					Vector2(panel_x + 4, row_y - 2), Vector2(panel_w - 8, 13), Color("#354b60"))
			var text := "%d %s" % [row + 1, _loot.item_name(item_id)]
			var count := _inventory.count_of(item_id)
			if count > 1:
				text += "×%d" % count
			PixelFont.draw(_inventory_panel_root, text, Vector2(panel_x + 10, row_y),
				Color("#f6f6f0" if row == _inventory_index else "#9fb2bd"))
	PixelFont.draw(_inventory_panel_root, "E 使用 Q 丢弃 TAB 关闭", Vector2(16, panel_y + 160), Color("#9fb2bd"))
	if not _inventory_toast.is_empty():
		PixelFont.draw(_inventory_panel_root, _inventory_toast, Vector2(16, panel_y + 174), Color("#f6f6f0"))


func _selected_inventory_item() -> String:
	var ids := _inventory.ids()
	if ids.is_empty():
		return ""
	_inventory_index = clampi(_inventory_index, 0, ids.size() - 1)
	return ids[_inventory_index]


func _move_inventory(delta: int) -> void:
	var ids := _inventory.ids()
	if ids.is_empty():
		return
	_inventory_index = posmod(_inventory_index + delta, ids.size())
	_render_inventory()


func _use_selected_item() -> void:
	var item_id := _selected_inventory_item()
	if item_id.is_empty():
		return
	var effect := _loot.item_effect(item_id)
	var item_name := _loot.item_name(item_id)
	if effect.has("equip"):
		_equipped = item_id
		_inventory_toast = "已装备 " + item_name
		_refresh_hud_stats()
		_render_inventory()
		return
	var consumed := false
	if effect.has("supplies"):
		_supplies = clampf(_supplies + float(effect["supplies"]), 0.0, 1.0)
		consumed = true
	if effect.has("health"):
		_health = clampf(_health + float(effect["health"]), 0.0, 1.0)
		consumed = true
	if effect.has("noise"):
		_noise += int(effect["noise"])
		consumed = true
	if consumed:
		_inventory.remove(item_id, 1)
		_inventory_toast = "用了 " + item_name
		_inventory_index = clampi(_inventory_index, 0, maxi(0, _inventory.ids().size() - 1))
	else:
		_inventory_toast = "这件东西现在用不上"
	_refresh_hud_stats()
	_render_inventory()


func _drop_selected_item() -> void:
	var item_id := _selected_inventory_item()
	if item_id.is_empty():
		return
	_inventory.remove(item_id, 1)
	_inventory_toast = "丢掉 " + _loot.item_name(item_id)
	_inventory_index = clampi(_inventory_index, 0, maxi(0, _inventory.ids().size() - 1))
	_render_inventory()


func _perform_attack() -> void:
	_attacks += 1
	_attack_frames = ATTACK_FRAMES
	var noise := 0
	if not _equipped.is_empty():
		var effect := _loot.item_effect(_equipped)
		noise = 1 if str(effect.get("equip", "")) == "melee" else 3
	_noise += noise
	_attack_visual.visible = true
	_update_attack_visual()
	_refresh_hud_stats()


func _update_attack_visual() -> void:
	if _attack_visual == null or _player == null:
		return
	_attack_visual.position = Vector2(
		_player.global_position.x + _player.facing_x * 12.0 - 6.0,
		_player.global_position.y - 36.0,
	)
	_attack_visual.scale = Vector2(_player.facing_x, 1.0)
	_attack_visual.z_index = int(_player.global_position.y) + 1


func _frame(parent: Node, x: int, y: int, width: int, height: int, color: Color) -> void:
	var pieces := [
		Vector2(x, y), Vector2(width, 1),
		Vector2(x, y + height - 1), Vector2(width, 1),
		Vector2(x, y), Vector2(1, height),
		Vector2(x + width - 1, y), Vector2(1, height),
	]
	for index in range(0, pieces.size(), 2):
		var edge := ColorRect.new()
		edge.position = pieces[index]
		edge.size = pieces[index + 1]
		edge.color = color
		parent.add_child(edge)


func _build_flashlight() -> void:
	var shader := load("res://game/shaders/flashlight.gdshader") as Shader
	if shader == null:
		push_error("FLASHLIGHT_SHADER_MISSING")
		return
	_light_material = ShaderMaterial.new()
	_light_material.shader = shader
	_light_material.set_shader_parameter("radius_px", FLASHLIGHT_RADIUS)
	_light_material.set_shader_parameter("softness_px", 48.0)
	_light_material.set_shader_parameter("cone_half", 0.42)
	_light_material.set_shader_parameter("cone_feather", 0.16)

	var layer := CanvasLayer.new()
	layer.name = "Flashlight"
	layer.layer = 10
	add_child(layer)
	var mask := ColorRect.new()
	mask.name = "Mask"
	mask.color = Color.WHITE
	mask.size = Vector2(VIEW_SIZE)
	mask.material = _light_material
	layer.add_child(mask)


func _process(_delta: float) -> void:
	_follow_player()
	_update_flashlight()
	_update_depth_order()
	_update_doors()
	if _attack_frames > 0:
		_attack_frames -= 1
		if _attack_frames <= 0:
			_attack_visual.visible = false
		else:
			_update_attack_visual()
	# 只有提示条需要每帧刷新；开/关面板全部走 _unhandled_input。
	# 之前这里也处理 inspect，导致真键盘同一帧先开后关（面板只闪一帧）。
	if not _inspection_ui_enabled:
		return
	var target := _nearest_inspection_id()
	if target != _inspection_target:
		_inspection_target = target
		_draw_inspection_prompt(target)


func _update_depth_order() -> void:
	if _player == null:
		return
	# 纵深遮挡：脚底 y 越大越靠前，直接当 z_index 用。
	_player.z_index = int(_player.global_position.y)
	var sprite := _player.get_node_or_null("BodySprite") as Sprite2D
	if sprite != null:
		sprite.flip_h = _player.facing_x < 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not _inspection_ui_enabled:
		return
	# 左键攻击：背包/检查面板打开时不响应。
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed and not _inventory_open and not _inspection_open:
			_perform_attack()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or event.is_echo() or not event.is_pressed():
		return
	# 背包打开时：W/S 选、E 使用、Q 丢弃、Tab/Esc/V 关闭。
	if _inventory_open:
		if event.is_action_pressed("move_up"):
			_move_inventory(-1)
		elif event.is_action_pressed("move_down"):
			_move_inventory(1)
		elif event.is_action_pressed("pickup"):
			_use_selected_item()
		elif event.is_action_pressed("drop"):
			_drop_selected_item()
		elif event.is_action_pressed("inventory") or event.is_action_pressed("cancel_inspect") or event.is_action_pressed("view"):
			_close_inventory()
		get_viewport().set_input_as_handled()
		return
	# 手电开关（F）：面板打开时不响应，避免和交互抢键。
	if event.is_action_pressed("toggle_light") and not _inspection_open:
		_set_flashlight(not _flashlight_on)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory") and not _inspection_open:
		_open_inventory()
		get_viewport().set_input_as_handled()
		return
	if _inspection_open:
		# 面板打开时：V/E/Esc 都关掉（E 是上下文交互键，顺手关面板）。
		if event.is_action("view") or event.is_action("pickup") or event.is_action("cancel_inspect"):
			_close_inspection()
			get_viewport().set_input_as_handled()
		return
	if event.is_action("cancel_inspect"):
		return
	# E = 上下文交互：优先搜索容器；否则开关/锁最近的门。
	if event.is_action_pressed("pickup"):
		var pickup_target := _nearest_inspection_id()
		if not pickup_target.is_empty() and _loot != null and _loot.has_container(pickup_target):
			_search_container(pickup_target)
			get_viewport().set_input_as_handled()
			return
		if _nearest_door >= 0:
			_toggle_door(_nearest_door)
			get_viewport().set_input_as_handled()
		return
	# V = 查看文本（检查框）。
	if event.is_action_pressed("view"):
		var target := _nearest_inspection_id()
		if target.is_empty():
			return
		_inspection_target = target
		_draw_inspection_prompt(target)
		_show_inspection(target)
		get_viewport().set_input_as_handled()


func _follow_player() -> void:
	if _player == null or _camera == null:
		return
	var half_view := float(VIEW_SIZE.x) / 2.0
	var rightmost_center := WORLD_TILES.x * TILE_SIZE - half_view
	_camera.position.x = roundf(clampf(_player.position.x + 64.0, half_view, rightmost_center))
	# 玩家走进房间下缘时相机轻微下移（最多 8px），保证脚底不出画；世界只有 14 行，不能露空。
	_camera.position.y = clampf(_player.position.y - 56.0, 108.0, 116.0)


func _set_flashlight(on: bool) -> void:
	_flashlight_on = on
	if _light_material == null:
		return
	# 关灯不是隐藏遮罩（那是反的），而是把光锥半径与羽化归零：整屏落到 outside_tint。
	_light_material.set_shader_parameter("radius_px", FLASHLIGHT_RADIUS if on else 0.0)
	_light_material.set_shader_parameter("softness_px", 48.0 if on else 0.0)


func _update_flashlight() -> void:
	if _light_material == null or _player == null:
		return
	var screen_origin := _player.get_global_transform_with_canvas().origin.round()
	_light_material.set_shader_parameter("light_pos_px", screen_origin + Vector2(9, -13))
