extends Node2D

const SHEET_FALLBACK := preload("res://art/generated_candidates/tiles/TL-04_corridor_v2.png")
const THEME_DIR := "res://data/buildings"
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
## 挥击动作时长：0.75s @60fps。这段里不允许再次进入（可重入锁），也不允许被打断。
const ATTACK_FRAMES := 45
## 命中帧白光只亮 2 帧，用来标「这一下打实了」，不做常驻特效。
const ATTACK_HIT_FRAMES := 2
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
## D11：三个区块的灯光档（越靠里越暗；A 区靠窗，C 区最深）。
## 数值是 outside_tint 的乘数：1.15 / 0.85 / 0.62；玩家换区时线性过渡，不硬切。
const ROOM_LIGHT_LEVELS: Array[float] = [1.15, 0.85, 0.62]
const LIGHT_OUTSIDE_BASE := Vector3(0.42, 0.46, 0.58)
## 门：E 开关；关闭时挡路；挂锁可锁；钥匙/近战武器可撬开。
const DOOR_TOP := 80.0
const DOOR_BOTTOM := 216.0
const DOOR_REACH_X := 44.0
## 门的纵深锚点 = 走道中线。门洞横跨整条走道（DOOR_TOP=80 只是门板顶边，
## 玩家脚底永远在 128..216），拿门板 y 当锚点会把 dy 算成 48..136，
## 门就永远选不中——「开门后过不去」的真根因就在这里（ac4ae89）。
const DOOR_ANCHOR_Y := (WALK_TOP + WALK_BOTTOM) * 0.5
## 站在走道里任何一点都算「在门前」：半个走道 + 8px 余量。
const DOOR_DEPTH_TOLERANCE := (WALK_BOTTOM - WALK_TOP) * 0.5 + 8.0
## 战斗：近战/枪械的够到距离与敌人深度容差。
const MELEE_REACH := 36.0
const FIREARM_REACH := 320.0
const ENEMY_DEPTH_TOLERANCE := 30.0
## 初始感染体位置（B 区 / C 区各一只）。
const ENEMY_SPAWNS: Array[Vector2] = [Vector2(300, 168), Vector2(520, 160)]
## D12：卡牌只写这五组非派生变量（time 由 day 派生，卡不许写）。
const CARD_VARIABLE_KEYS: Array[String] = ["trust", "reputation", "supplies", "control", "knowledge"]
## D4：燃料是出行门槛，不是消耗池（见 data/travel/routes.json 注释）。
## 加油站是唯一补给点：到站 +1，上限 3。医院（需 1）/ 军事基地（需 2）按访问次数解锁。
const FUEL_MAX := 3
## D10：噪声 ≥ 这个数才会把感染体引向声源（枪声 3 / 噪声道具 2–3；近战 1 不会）。
const NOISE_HEAR_THRESHOLD := 3

var _world: Node2D
var _player: Player
var _camera: Camera2D
var _light_material: ShaderMaterial
## 光锥当前角度（弧度）：0 = 朝右，PI = 朝左。跟着朝向插值，避免转身硬切。
var _light_angle := 0.0
## D11：当前区块的灯光乘数（平滑过渡用；目标值来自 ROOM_LIGHT_LEVELS）。
var _light_zone := 1.0
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
## 手机触摸层（null = 桌面，整条手机路径都不存在）。见 design/MOBILE.md
var _mobile: TouchControls
## 首 10 分钟引导（P0-4）：三步，由玩法事件推进
var _tutorial: Tutorial
## 门状态：{tile_x, center_x, leaf, shape, handle, open, locked}
var _doors: Array[Dictionary] = []
var _nearest_door := -1
var _door_prompt_layer: CanvasLayer
var _door_prompt_root: Node2D
var _door_prompt_text := ""
var _door_toast_text := ""
var _door_toast_frames := 0
## 玩家状态：物资/体力/噪声/已装备武器/挥击次数（背包与使用系统的落地数据）。
## M2a 第 4 步：不再有本地物资字段。真源是 world_state，`RunState.supplies` 只是存档镜像。
## 初始化失败时退回 RunState 镜像（并在 HUD 报 STATE_OFFLINE）。
var _data: DataLayer
var _state: WorldState
var _supplies_online := false
## 结局判定：定义在 data/endings/<template>.json，解锁写进 RunState 并落盘。
var _book: EndingBook
const ENDING_TEMPLATE := "school"
## D9：倒下后会被拖回的安全屋（data/travel/routes.json 里唯一 safehouse）。
const SAFEHOUSE_ID := "school"
var _health := 1.0
## D9 倒下状态：结算后的天数（同一天不重复结算）、累计次数、重入保护。
var _down_day := -1
var _down_count := 0
var _downing := false
## D12：卡牌引擎 + 「每天一张」的当日去重与文案记录。
var _card: CardEngine
var _card_day := -1
var _cards_fired := 0
var _last_card_id := ""
var _last_card_text := ""
var _noise := 0
var _equipped := ""
var _attacks := 0
var _attack_frames := 0
var _inventory_toast := ""
## 战斗状态：武器伤害/耐久/弹匣/弹药物品；敌人与击杀数。
var _weapon_damage := 0
var _weapon_durability := 0
var _weapon_magazine := 0
var _weapon_ammo := ""
var _magazine := 0
var _enemies: Array[Enemy] = []
var _enemies_killed := 0
var _combat_message := ""
var _combat_message_frames := 0
## 状态系统：伤口/感染/中毒/成瘾（数据在 data/systems/status.json）。
var _status: StatusService
## 一天与出行：结算与「能不能走」（数据在 data/travel/routes.json）。
var _day: DayCycle
var _run: RunState
var _travel: TravelService
var _at_exit := false
## 走到这个 x 就算站在出口（尽头墙在 576，玩家被夹在 ~600）。
const EXIT_HINT_X := 596.0
## 出口选楼：打开旅行图，图上只列相邻且可达的楼。
var _current_building := "school"
## 今天去过哪几栋（地图上用一条短线标出来）。
var _visited: Array[String] = ["school"]
var _fuel := 0
var _map_open := false
var _map_layer: CanvasLayer
var _map: Node2D
## 会成瘾的消耗品（吃污染食物中毒之外再加一层成瘾）。
const ADDICTIVE_ITEMS := ["painkillers", "sleeping_pills"]
## 面板当前内容（测试与调试用，不参与渲染）。
var _panel_title := ""
## 按住 E 搜索：id / 已按秒数 / 需要的秒数（来自 tiers.search_seconds）。
var _search_id := ""
var _search_elapsed := 0.0
var _search_required := 0.0
var _search_ui_root: Node2D
## 状态的危险视觉：四边框，厚度随最重状态走（0 = 干净，看不见）。
var _status_fx_layer: CanvasLayer
var _status_fx_bars: Array[ColorRect] = []
var _status_fx_thickness := 0
## 状态边框配色（像素硬边，不走 alpha 渐变）。
const STATUS_FX_COLORS := {
	"wound": Color("#4a1f24"),
	"infection": Color("#2a2438"),
	"poison": Color("#2f3a24"),
	"addiction": Color("#33302a"),
}
## 搜索时敌人靠到多近算被打断。
const SEARCH_THREAT_RANGE := 40.0
## 命中顿帧：普通命中 3 帧（50ms）、击杀 5 帧；抖屏 1px。
const HITSTOP_FRAMES := 3
const HITSTOP_KILL_FRAMES := 5
const SHAKE_PX := 1
var _hitstop_frames := 0
var _shake_frames := 0
var _flash_frames := 0
var _flash_targets: Array[Enemy] = []
## 主角动作状态（walk/idle/hurt）与计时；受击后 0.22 秒锁在 hurt 帧。
var _player_anim_time := 0.0
var _player_anim_id := "idle"
var _player_hurt_t := 0.0
var _attack_anim_t := 0.0
var _panel_lines: Array = []
## 走廊 demo 的世界日（HUD 写死 DAY 3，等接入 WorldState 后替换）。
var _world_day := 3
## D7：当前楼的主题（data/buildings/<id>.json）与运行时资源。
var _theme: Dictionary = {}
var _theme_id := "school"
var _theme_ambient := 1.0
var _sheet: Texture2D = SHEET_FALLBACK


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_actions()
	# D7：先确定当前楼并换上该楼主题（tile 表 + 道具场景），再搭走廊。
	_run = RunState.ensure()
	_current_building = _run.building
	_apply_theme()
	_build_corridor()
	_build_actor()
	_apply_depth_sort()
	_spawn_enemies()
	_load_inspections()
	_load_loot()
	# 教学改成「不写字」：只在可搜索容器上方留一格极淡微光（见 design/MOBILE.md §教学）
	_build_container_glows()
	_inventory = InventoryService.new(INVENTORY_CAPACITY)
	_status = StatusService.new()
	if not _status.load_all():
		push_error("STATUS_LOAD_FAILED: " + _status.load_error())
	_day = DayCycle.new()
	_day.new_run()
	_visited = _run.visited.duplicate()
	_fuel = _run.fuel
	# M2a：把「物资」接到数据层的六组变量上。失败就退回镜像值，绝不静默变 0。
	_data = DataLayer.new()
	_state = WorldState.new()
	if _data.load_all() and _state.init_from(_data):
		_state.set_var("supplies", _run.supplies)
		# D12：卡牌效果写进 world_state 后要跨场景/重启保留。
		_restore_world_vars()
		_supplies_online = true
	else:
		_state = null
		push_error("STATE_OFFLINE: world_state 初始化失败，物资退回 RunState 镜像")
	_book = EndingBook.new()
	if not _book.load_template(ENDING_TEMPLATE):
		push_error("ENDING_BOOK_FAILED: " + _book.load_error())
		_book = null
	_health = _run.health
	_day.day = _run.day
	_day.sediment = _run.sediment
	# P0-4：首 10 分钟引导，状态住在 RunState.tutorial_step（老档缺键当 0）。
	_tutorial = Tutorial.new()
	_tutorial.sync(_run.tutorial_step)
	# D12：world_state 的世界日与 DayCycle 对齐，事件卡 trigger.day 才读得到正确天数。
	_sync_world_day()
	# D12：卡牌引擎接进走廊；每天开始抽 1 张 L 卡并作用于 world_state。
	_card = CardEngine.new()
	if _state != null and not _card.init_from(_data, _state):
		_card = null
		push_error("CARD_ENGINE_OFFLINE")
	_travel = TravelService.new()
	if not _travel.load_all():
		push_error("TRAVEL_LOAD_FAILED: " + _travel.load_error())
	_build_camera()
	_build_hud()
	_build_search_ui($HUD)
	_build_status_fx()
	_build_travel_map_layer()
	_build_inventory_ui()
	_build_door_prompt()
	_build_attack_visual()
	_build_flashlight()
	# D11：开局按所在区块初始化灯光，避免第一帧从 1.0 渐变造成闪一下。
	_light_zone = ROOM_LIGHT_LEVELS[_current_room_index()] * _theme_ambient
	# 手机：触摸层 + 生命周期；桌面返回 null，行为与之前完全一致（design/MOBILE.md）。
	_mobile = MobileSupport.attach(self)
	_refresh_hud_stats()
	Analytics.track("run_enter", {"mode": "story", "day": int(_run.day), "building": _current_building})


func _place_tile(tile_name: String, tile_x: int, tile_y: int, from_x := 0, width := TILE_SIZE) -> void:
	var tile_index: int = TILE_INDEX[tile_name]
	var tile := Sprite2D.new()
	tile.texture = _sheet
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
		_build_door(tile_x, index)
		# 区块标签（A 区 / B 区 / C 区），标在下一段墙面上
	# 标签放在每个房间起点：A 区最左，B/C 区在各自门洞后两格
	var label_tiles: Array[int] = [
		2,
		ROOM_PARTITION_TILES[0] + 2,
		ROOM_PARTITION_TILES[1] + 2,
	]
	for index: int in mini(ROOM_LABELS.size(), label_tiles.size()):
		PixelFont.draw(_world, ROOM_LABELS[index], Vector2(label_tiles[index] * TILE_SIZE, 44), Color("#354b60"))


func _build_door(tile_x: int, index: int) -> void:
	var center_x := float(tile_x * TILE_SIZE + ROOM_PARTITION_WIDTH / 2)
	# W1/EntityRegistry：门身份 = 「哪两个区之间的门」，不用数组下标、也不用 tile_x。
	# 存档/回响层以后都引用这个 id（见 game/runtime/entity_registry.gd）。
	var door_id := EntityRegistry.door_id(_current_building, index, index + 1)
	if door_id.is_empty():
		push_error("DOOR_ID_FAILED: index=%d" % index)
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
		"id": door_id,
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
			var door: Dictionary = _doors[index]
			var dx := absf(_player.global_position.x - float(door["center_x"]))
			# 门也要看纵深，但锚点必须是走道中线而不是门板顶边：
			# 门板从 DOOR_TOP=80 一直画到 216，玩家脚底却在 128..216，
			# 用门板 y 判纵深会让 dy 恒 > 24，门一次都选不中（真机「开门后过不去」）。
			var dy := absf(_player.global_position.y - DOOR_ANCHOR_Y)
			if dx <= DOOR_REACH_X and dy <= DOOR_DEPTH_TOLERANCE:
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
			return InputHints.get_hint("door_pry")
		return "锁着"
	if bool(door["open"]):
		return InputHints.get_hint("door_close")
	if _inventory != null and _inventory.has("padlock"):
		return InputHints.get_hint("door_lock")
	return InputHints.get_hint("door_open")


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
	var shape := door["shape"] as CollisionShape2D
	# 直接赋值 + 再补一次 deferred：物理查询刷新期间直接写 disabled 可能被静默丢弃，
	# 症状就是「门板消失了、人还是过不去」。两次写同一个值，幂等，代价为零。
	if shape != null:
		shape.disabled = is_open
		shape.set_deferred("disabled", is_open)
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
	var texture: Texture2D = CharAnim.frame_texture("player", 0)
	if texture == null:
		texture = load(CHAR_PATH) as Texture2D
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
	# P0-4：走路是第一步引导的推进条件
	_tutorial_advance(_tutorial.note_moved() if _tutorial != null else false)


## 引导推进一步：落盘 + 重画 HUD（不做「点击继续」，走完就消失）
func _tutorial_advance(advanced: bool) -> void:
	if not advanced or _tutorial == null:
		return
	_run.tutorial_step = _tutorial.step
	_persist_run()
	_refresh_hud_stats()


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
	# 出口选楼面板复用菜单那套语义动作（与 main_menu 注册同一批，幂等）。
	_add_action("menu_up", [KEY_W, KEY_UP])
	_add_action("menu_down", [KEY_S, KEY_DOWN])
	_add_action("menu_confirm", [KEY_E, KEY_ENTER])
	_add_action("menu_back", [KEY_ESCAPE])
	_add_action("view", [KEY_V])
	_add_action("cancel_inspect", [KEY_ESCAPE])
	_add_action("toggle_light", [KEY_F])
	_add_action("drop", [KEY_Q])
	_add_action("reload", [KEY_R])
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
	if _inspection_order.size() != _inspectable_prop_count():
		push_error("INSPECTION_PROP_COUNT_MISMATCH")
		_inspection_records.clear()
		_inspection_order.clear()
		return
	_inspection_range_x = float(range_value)


## D7：主题道具场景里会额外挂 4 件「标志物」（metadata/decor = true），
## 它们不参与检查交互，所以计数时排除。
func _inspectable_prop_count() -> int:
	var count := 0
	for child: Node in $Props.get_children():
		var sprite := child as Sprite2D
		if sprite == null or sprite.has_meta("decor"):
			continue
		count += 1
	return count


## HUD 单行：DAY · 地点 · 体力 · 手持 · 伤口（无伤不占位）。整块只有这一行，高度 ≤ 屏高 8%。
func _hud_line() -> String:
	var building := ""
	if _travel != null and _travel.has_building(_current_building):
		building = _travel.label_of(_current_building)
	var text := "DAY %d · %s · 体力 %d" % [int(_run.day) + 1, building, int(round(_health * 100.0))]
	text += " · " + _weapon_label()
	var status_text := _status.summary() if _status != null else ""
	if not status_text.is_empty():
		text += " · " + status_text
	return text


## 手持状态并进单行（不再单独占一行）：空手 / 武器名 + 耐久或弹匣。
func _weapon_label() -> String:
	if _equipped.is_empty() or _loot == null:
		return "空手"
	var label := _loot.item_name(_equipped)
	if _weapon_durability > 0:
		label += " 耐久 %d" % _weapon_durability
	elif _weapon_magazine > 0:
		label += " 弹 %d/%d" % [_magazine, _weapon_magazine]
	return label


## 物资档位词：只在玩家能感知的三档里说话，不报精确百分比。
func _supplies_word() -> String:
	var value := _get_supplies()
	if value >= 0.66:
		return "充足"
	if value >= 0.33:
		return "偏紧"
	return "见底"


## 触屏「搜」只在**当下真有东西可交互**时出现：可检查物（含停摆时钟）、可搜索容器、门、出口。
## 离开就消失，不常驻、不指路——它只是「这一刻这颗键有用」的物理提示。
func _searchable_nearby() -> bool:
	if _at_exit or _nearest_door >= 0:
		return true
	return not _nearest_inspection_id().is_empty()


## 柜子上方一格极淡微光：只表达「这个能碰」，不指路、不导航、不写文案。
## 颜色锁调色板 c07_edge（#354b60），整数像素，不新增资产。
const GLOW_COLOR := Color("#354b60")


func _build_container_glows() -> void:
	var root := Node2D.new()
	root.name = "ContainerGlow"
	add_child(root)
	if _loot == null:
		return
	for id: String in _inspection_order:
		if not _loot.has_container(id):
			continue
		var prop := $Props.get_node_or_null(NodePath(id)) as Sprite2D
		if prop == null or prop.texture == null:
			continue
		var glow := ColorRect.new()
		glow.name = "Glow"
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.color = GLOW_COLOR
		glow.size = Vector2(5, 1)
		glow.position = Vector2(-2.5, -prop.texture.get_height() * 0.5 - 4.0)
		prop.add_child(glow)


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
	# 手游：检查面板在更大画布里居中（桌面 origin 为 0）。
	_inspection_panel_root.position = Vector2(ScreenLayout.origin_of(self))
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
	# 手机上没有 V / E 这两个字母键：提示改成触控键名（搜），别让玩家在屏幕上找键盘。
	if InputHints.touch_mode():
		key_text = ""
		verb = "搜 · " + verb
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
	# 手游：面板在更大画布里居中（桌面 origin 恒为 0）。每次显示重算，避开 _ready 时序。
	_inspection_panel_root.position = Vector2(ScreenLayout.origin_of(self))
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
		Analytics.track("loot_search", {
			"container": id, "day": int(_world_day), "status": "again",
			"items": 0, "rejected": 0,
		})
		_show_panel(_loot.label_of(id), ["已经搜过一次", "剧情模式不会刷新"], id)
		return
	var items: Array = result.get("items", [])
	if items.is_empty():
		Analytics.track("loot_search", {
			"container": id, "day": int(_world_day), "status": "empty",
			"items": 0, "rejected": 0,
		})
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
	Analytics.track("loot_search", {
		"container": id, "day": int(_world_day), "status": "ok",
		"items": added.size(), "rejected": rejected.size(),
	})
	_show_panel(_loot.label_of(id), lines, id)
	_refresh_hud_stats()


## 一次搜索折算多少游戏小时：1 秒 = 1 小时（数值旋钮，调它就能改状态推进速度）。
const SEARCH_SECONDS_PER_GAME_HOUR := 1.0


func _begin_search(id: String) -> void:
	if _loot == null or not _loot.has_container(id):
		return
	var required := _loot.search_seconds_of(id)
	if required <= 0.0:
		_search_container(id)
		return
	_search_id = id
	_search_elapsed = 0.0
	_search_required = required
	_player._movement_locked = true
	_refresh_search_progress()


func _cancel_search(reason: String) -> void:
	if _search_id.is_empty():
		return
	_search_id = ""
	_search_elapsed = 0.0
	_search_required = 0.0
	_player._movement_locked = false
	_refresh_search_progress()
	if not reason.is_empty():
		_toast_combat(reason)


func _finish_search() -> void:
	var id := _search_id
	var seconds := _search_elapsed
	_search_id = ""
	_search_elapsed = 0.0
	_search_required = 0.0
	_player._movement_locked = false
	_refresh_search_progress()
	_search_container(id)
	# P0-4：搜过一个柜子 = 第二步引导完成
	_tutorial_advance(_tutorial.note_search() if _tutorial != null else false)
	# 搜索要花时间：这段时间里伤口在流血、感染在恶化。
	advance_hours(seconds * SEARCH_SECONDS_PER_GAME_HOUR)


## 推进游戏小时：状态按小时恶化/消退，伤口持续掉体力。由搜索等耗时行为调用。
func advance_hours(hours: float) -> void:
	if _status == null or hours <= 0.0:
		return
	_status.tick_hours(hours)
	var drain := _status.health_drain_per_hour() * hours
	if drain > 0.0:
		_health = clampf(_health - drain, 0.0, 1.0)
	_player.status_speed_scale = _status.speed_multiplier()
	_refresh_hud_stats()


func _refresh_search_progress() -> void:
	if _search_ui_root == null:
		return
	for child: Node in _search_ui_root.get_children():
		child.queue_free()
	if _search_id.is_empty():
		return
	var progress := clampf(_search_elapsed / maxf(0.001, _search_required), 0.0, 1.0)
	var bar_x := 8.0
	var bar_y := 146.0
	var bar_w := 120.0
	_add_rect_polygon(_search_ui_root, "SearchBg", Vector2(bar_x, bar_y), Vector2(bar_w, 5), Color("#0b1119"))
	_add_rect_polygon(_search_ui_root, "SearchFill", Vector2(bar_x + 1, bar_y + 1), Vector2(maxf(0.0, (bar_w - 2) * progress), 3), Color("#9fb2bd"))
	PixelFont.draw(_search_ui_root, "搜索中 %d" % int(round(progress * 100.0)), Vector2(bar_x, bar_y - 16), Color("#f6f6f0"))


func _build_search_ui(parent: Node) -> void:
	_search_ui_root = Node2D.new()
	_search_ui_root.name = "SearchProgress"
	parent.add_child(_search_ui_root)


## 受伤/中毒/感染的屏幕边缘警示：纯色硬边，不加渐变、不加发光。
func _build_status_fx() -> void:
	_status_fx_layer = CanvasLayer.new()
	_status_fx_layer.name = "StatusFx"
	_status_fx_layer.layer = 26
	add_child(_status_fx_layer)
	for index in range(4):
		var bar := ColorRect.new()
		bar.name = ["Top", "Bottom", "Left", "Right"][index]
		bar.color = Color.TRANSPARENT
		bar.visible = false
		_status_fx_layer.add_child(bar)
		_status_fx_bars.append(bar)


func _refresh_status_fx() -> void:
	if _status == null or _status_fx_bars.size() != 4:
		return
	var thickness := 0
	var tint := Color.TRANSPARENT
	for id: String in _status.ids():
		var stage := _status.stage_of(id)
		if stage <= 0:
			continue
		# 每级 2px，最多 6px：够看见，又不至于挡视野。
		var candidate := mini(3, stage) * 2
		if candidate > thickness:
			thickness = candidate
			tint = STATUS_FX_COLORS.get(id, Color("#3a2028"))
	_status_fx_thickness = thickness
	# 状态边框必须贴着**屏幕**四边：手机画布是 555×256，如果还按设计空间 384×216 画，
	# 就会变成「从左上角围出一个大方框」——真机截图里那块红框就是它（伤口 3 时出现）。
	var canvas := ScreenLayout.canvas_of(self)
	var width := float(canvas.x)
	var height := float(canvas.y)
	var t := float(thickness)
	var rects := [
		[Vector2.ZERO, Vector2(width, t)],
		[Vector2(0, height - t), Vector2(width, t)],
		[Vector2.ZERO, Vector2(t, height)],
		[Vector2(width - t, 0), Vector2(t, height)],
	]
	for index in range(4):
		var bar := _status_fx_bars[index]
		bar.position = rects[index][0]
		bar.size = rects[index][1]
		bar.color = tint
		bar.visible = thickness > 0


func _nearest_enemy_distance() -> float:
	var best := -1.0
	for enemy: Enemy in _enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var distance := enemy.global_position.distance_to(_player.global_position)
		if best < 0.0 or distance < best:
			best = distance
	return best


## 按住 E 才继续；松手即中断。进度到点才结算物资。
func _update_search(delta: float) -> void:
	if _search_id.is_empty():
		return
	# 搜索是背对走廊的动作：敌人贴近就打断，并吃一记抓伤。
	var threat := _nearest_enemy_distance()
	if threat >= 0.0 and threat <= SEARCH_THREAT_RANGE:
		_cancel_search("搜索被打断了")
		_on_enemy_attacked(1)
		return
	if not InputMap.has_action("pickup") or not Input.is_action_pressed("pickup"):
		_cancel_search("搜索被打断")
		return
	_search_elapsed += delta
	_refresh_search_progress()
	if _search_elapsed >= _search_required:
		_finish_search()


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
	_draw_hint(_inspection_panel_root, "inspect_close", Vector2(326, 160), Color("#9fb2bd"))
	_inspection_panel_root.set_meta("inspection_id", id)
	_inspection_panel_root.visible = true
	_inspection_open = true
	_dim_touch(true)
	_player._movement_locked = true
	_draw_inspection_prompt("")


## 手机：面板打开时把触摸层压暗，别挡面板文字（桌面 _mobile 是 null，整个函数空转）
func _dim_touch(value: bool) -> void:
	if _mobile != null:
		_mobile.set_dimmed(value)


func _close_inspection() -> void:
	if not _inspection_open:
		return
	_inspection_open = false
	_inspection_panel_root.visible = false
	_dim_touch(false)
	_player._movement_locked = false
	_player._previous_global_position = _player.global_position
	_inspection_target = ""
	_draw_inspection_prompt("")


func set_inspection_ui_enabled(enabled: bool) -> void:
	_inspection_ui_enabled = enabled
	if _inspection_prompt_layer != null:
		_inspection_prompt_layer.visible = enabled


## 门禁/截图场景专用：感染体只当画面元素，不追不打。
## D9 之后抓伤会把体力打到 0 触发「倒下」（锁移动 + 传送回学校），
## 会打断与战斗无关的长流程门禁（门/搜索/背包/走查/灯光）。
func disarm_enemies() -> void:
	for enemy: Enemy in _enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.player = null


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


## HUD 文字：暗底不用纯白（#e8e4d8），关键数字加 1px 深色描边防糊（对比度见 MOBILE.md 验收 C）。
const HUD_INK := Color("#e8e4d8")
const HUD_OUTLINE := Color("#0b1119")


func _draw_hud_outlined(parent: Node, text: String, at: Vector2, tint: Color) -> void:
	for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		PixelFont.draw(parent, text, at + offset, HUD_OUTLINE)
	PixelFont.draw(parent, text, at, tint)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 20
	add_child(layer)

	var ink := Color("#9fb2bd")
	var dim := Color("#354b60")
	var day3_mark := Color("#0b1119")
	var frame_color := Color("#635e57")
	# HUD 压成单行（③-2）：DAY · 地点 · 体力 · 伤口，统一由 _refresh_hud_stats 的 _hud_line() 画。
	_build_hud_stats_root(layer)

	var widths := [44, 36, 28, 44, 24, 40]
	for index in range(widths.size()):
		var bar := ColorRect.new()
		var column_x := 276 if index < 3 else 332
		bar.position = Vector2(column_x, 12 + (index % 3) * 7)
		# 顶部那两组无标签蓝条已从 HUD 撤掉（玩家读不出它们是什么），只留这里的位置占位注释。
		bar.visible = false
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
	# 手游：背包面板在更大画布里居中（桌面 origin 为 0）。
	_inventory_panel_root.position = Vector2(ScreenLayout.origin_of(self))
	_inventory_layer.add_child(_inventory_panel_root)


func _hide_attack_flash() -> void:
	if _attack_visual != null:
		_attack_visual.visible = false


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
	var alive := 0
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			alive += 1
	# 状态一变，移速惩罚立刻生效（不只靠 advance_hours）。
	if _status != null and _player != null:
		_player.status_speed_scale = _status.speed_multiplier()
		_refresh_status_fx()
	# HUD 压成单行（③-2）：DAY · 地点 · 体力 · 伤口；伤口来自状态摘要，无伤则省略。
	_draw_hud_outlined(_hud_stats_root, _hud_line(), Vector2(8, 8), HUD_INK)
	# 手持状态已并进 _hud_line()；这一行不再重复画，HUD 只剩一行文字。
	# 敌人数量不暴露（玩家不该拥有「还剩几只」这种上帝视角仪表）。
	if _at_exit:
		_draw_hint(_hud_stats_root, "leave", Vector2(8, 132), HUD_INK)
	elif _combat_message_frames > 0 and not _combat_message.is_empty():
		_draw_hud_outlined(_hud_stats_root, _combat_message, Vector2(8, 132), HUD_INK)


## 教学不再写字（约束：不写「走到柜子前点 E 搜索」这类替玩家思考的导航句）；
## 只保留「柜子上方一格微光」（_build_container_glows）。这里的函数体故意为空。
func _draw_tutorial_hint() -> void:
	return


func _open_inventory() -> void:
	if _inspection_open:
		return
	_inventory_open = true
	_inventory_index = 0
	_inventory_toast = ""
	_player._movement_locked = true
	_inventory_layer.visible = true
	_dim_touch(true)
	_render_inventory()


func _close_inventory() -> void:
	_inventory_open = false
	_inventory_layer.visible = false
	_dim_touch(false)
	_player._movement_locked = false
	_player._previous_global_position = _player.global_position


func _render_inventory() -> void:
	# 手游：背包面板在更大画布里居中（桌面 origin 恒为 0）。
	_inventory_panel_root.position = Vector2(ScreenLayout.origin_of(self))
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
			var row_y := panel_y + 24 + row * 15
			if row == _inventory_index:
				_add_rect_polygon(_inventory_panel_root, "Sel%d" % row,
					Vector2(panel_x + 4, row_y - 2), Vector2(panel_w - 8, 15), Color("#354b60"))
			var text := "%d %s" % [row + 1, _loot.item_name(item_id)]
			var count := _inventory.count_of(item_id)
			if count > 1:
				text += "×%d" % count
			PixelFont.draw(_inventory_panel_root, text, Vector2(panel_x + 10, row_y),
				Color("#f6f6f0" if row == _inventory_index else "#9fb2bd"))
	_draw_hint(_inventory_panel_root, "inventory_actions", Vector2(16, panel_y + 160), Color("#9fb2bd"))
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
		_equip_item(item_id)
		_inventory_toast = "已装备 " + item_name
		_refresh_hud_stats()
		_render_inventory()
		return
	var consumed := false
	# 先判「对症下药」：绷带治伤口、抗生素治感染、消毒水治中毒。
	var cured := _status.cure_with_item(item_id)
	if not cured.is_empty():
		_inventory.remove(item_id, 1)
		_inventory_toast = "用了 %s，%s好了" % [item_name, _status.label_of(cured)]
		_refresh_hud_stats()
		_render_inventory()
		return
	if effect.has("supplies"):
		_add_supplies(float(effect["supplies"]))
		consumed = true
	if effect.has("health"):
		_health = clampf(_health + float(effect["health"]), 0.0, 1.0)
		consumed = true
	if effect.has("noise"):
		_emit_noise(int(effect["noise"]))
		consumed = true
	# 污染食物：吃下去先中毒；止痛/安眠这类还会上瘾。
	if bool(effect.get("contaminate", false)):
		_status.apply("poison")
		if item_id in ADDICTIVE_ITEMS:
			_status.apply("addiction")
		_inventory_toast = "味道不对……"
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
	# 可重入锁：一次挥击的 0.75s 里忽略新输入（不排队、不打断、不重复结算伤害）。
	if _attack_frames > 0:
		return
	_attacks += 1
	_attack_frames = ATTACK_FRAMES
	_attack_anim_t = 0.0
	_update_attack_visual()
	# 白光只标命中帧：亮 2 帧就灭，不再跟着整段动作常驻。
	_attack_visual.visible = true
	get_tree().create_timer(float(ATTACK_HIT_FRAMES) / 60.0).timeout.connect(_hide_attack_flash)
	var damage := 1
	var noise := 0
	var reach := MELEE_REACH
	var melee := true
	if not _equipped.is_empty():
		var effect := _loot.item_effect(_equipped)
		damage = int(effect.get("damage", 1))
		melee = str(effect.get("equip", "melee")) == "melee"
		if melee:
			noise = 1
		else:
			noise = 3
			reach = FIREARM_REACH
			if _magazine <= 0:
				damage = 0
				_toast_combat(InputHints.get_hint("reload_toast"))
			else:
				_magazine -= 1
	_emit_noise(noise)
	var target := _enemy_in_reach(reach)
	if target != null and damage > 0:
		var killed := target.hp - damage <= 0
		target.take_damage(damage)
		# 命中反馈：顿帧 + 闪白 + 1px 抖屏。击杀给更重的反馈。
		_play_hit_feedback(target, killed)
		if melee and not _equipped.is_empty():
			_weapon_durability -= 1
			if _weapon_durability <= 0:
				_break_weapon()
	_refresh_hud_stats()


func _enemy_in_reach(reach: float) -> Enemy:
	var best: Enemy = null
	var best_distance := INF
	for enemy: Enemy in _enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var dx := enemy.global_position.x - _player.global_position.x
		var dy := absf(enemy.global_position.y - _player.global_position.y)
		if dy > ENEMY_DEPTH_TOLERANCE:
			continue
		if dx * _player.facing_x < -4.0:
			continue
		var distance := absf(dx)
		if distance > reach:
			continue
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _equip_item(item_id: String) -> void:
	_equipped = item_id
	var effect := _loot.item_effect(item_id)
	_weapon_damage = int(effect.get("damage", 1))
	_weapon_durability = int(effect.get("durability", 0))
	_weapon_magazine = int(effect.get("magazine", 0))
	_weapon_ammo = str(effect.get("ammo", ""))
	_magazine = 0


func _break_weapon() -> void:
	var broken := _loot.item_name(_equipped)
	_equipped = ""
	_weapon_damage = 0
	_weapon_durability = 0
	_weapon_magazine = 0
	_weapon_ammo = ""
	_magazine = 0
	_toast_combat(broken + " 坏了")


func _reload_weapon() -> void:
	if _equipped.is_empty():
		return
	var effect := _loot.item_effect(_equipped)
	if str(effect.get("equip", "")) != "firearm":
		return
	var ammo_id := str(effect.get("ammo", ""))
	if ammo_id.is_empty() or not _inventory.has(ammo_id):
		_toast_combat("没有子弹")
		return
	_inventory.remove(ammo_id, 1)
	_magazine = int(effect.get("magazine", 6))
	_toast_combat("装填完成 %d 发" % _magazine)
	_refresh_hud_stats()


func _toast_combat(text: String) -> void:
	_combat_message = text
	_combat_message_frames = 120
	_refresh_hud_stats()


func _spawn_enemies() -> void:
	for index: int in ENEMY_SPAWNS.size():
		var enemy := Enemy.new()
		enemy.name = "Enemy_%d" % index
		enemy.position = ENEMY_SPAWNS[index]
		enemy.player = _player
		enemy.attacked.connect(_on_enemy_attacked)
		enemy.died.connect(_on_enemy_died)
		add_child(enemy)
		_enemies.append(enemy)


func _on_enemy_attacked(damage: int) -> void:
	_health = clampf(_health - 0.15 * float(damage), 0.0, 1.0)
	var stage := _status.apply("wound")
	_player_hurt_t = 0.22
	_toast_combat("你被感染体抓伤了（伤口 %d）" % stage)
	_refresh_hud_stats()


func _on_enemy_died(enemy: Enemy) -> void:
	_enemies_killed += 1
	Analytics.track("enemy_kill", {
		"enemy": str(enemy.name), "day": int(_run.day), "kills": int(_enemies_killed),
	})
	_toast_combat("感染体倒下了")
	# 不立刻 queue_free：保留节点（已停物理、停在倒地帧），门禁与调试仍能读到 dead。
	_refresh_hud_stats()


## D9：体力归零的后果——丢 1 沉积、翻到次日、被拖回学校安全屋、体力恢复到 0.3。
## 一天最多触发一次（_down_day 记录结算后的天数），避免同一帧被多次结算。
func _trigger_down() -> void:
	if _downing or _day == null:
		return
	_downing = true
	_down_count += 1
	var result := _day.down(_health)
	_health = float(result["health"])
	_down_day = int(result["next_day"])
	_current_building = SAFEHOUSE_ID
	if not _visited.has(SAFEHOUSE_ID):
		_visited.append(SAFEHOUSE_ID)
	if _map_open:
		_close_travel_map()
	if _inventory_open:
		_close_inventory()
	if _inspection_open:
		_close_inspection()
	if _player != null:
		_player.global_position = Vector2(2 * TILE_SIZE, 8 * TILE_SIZE)
		_player.velocity = Vector2.ZERO
	_run.actions_left = _travel.actions_per_day() if _travel != null else 1
	# D12：倒下也翻到次日，同样抽一张事件卡。
	_sync_world_day()
	_fire_daily_card()
	_persist_run()
	Analytics.track("player_down", {
		"day": int(_run.day), "building": _current_building,
		"down_count": int(_down_count), "mode": "story",
	})
	_show_panel("你倒下了", result["lines"], "down")
	_refresh_hud_stats()
	_downing = false


func down_count() -> int:
	return _down_count


func last_down_day() -> int:
	return _down_day


## 主角动作：受击优先 → 走动播 walk → 静止播 idle。帧由精灵表按 fps 推进。
## 离场：打开旅行图，只列相邻且可达的楼；选完才结算翻页。
## 场景切换还没做，所以选完是把「当前楼」换掉 + 回入口，结算面板上写明这一点。
func _leave_building() -> void:
	if _day == null or _travel == null:
		return
	_open_travel_map()


func _build_travel_map_layer() -> void:
	_map_layer = CanvasLayer.new()
	_map_layer.name = "TravelMapLayer"
	_map_layer.layer = 45
	_map_layer.visible = false
	add_child(_map_layer)


func _reason_text(reason: String) -> String:
	match reason:
		"not_enough_fuel":
			return "燃料不够"
		"no_action_left":
			return "今天已经出去过了"
		"no_route":
			return "没有直达路线"
		"same_building":
			return "已经在这里"
		_:
			return "走不了"


func _open_travel_map() -> void:
	if _map_open:
		return
	var scene := load("res://game/scenes/travel_map.tscn") as PackedScene
	if scene == null:
		push_error("TRAVEL_MAP_SCENE_MISSING")
		return
	_map = scene.instantiate() as Node2D
	_map.name = "TravelMap"
	# 输入由走廊统一转发：地图自己不处理，避免两边抢键。
	_map.interactive = false
	_map_layer.add_child(_map)
	_map.setup(_current_building, _fuel, _visited)
	_map.chosen.connect(_on_map_chosen)
	_map.cancelled.connect(_close_travel_map)
	_map_layer.visible = true
	_map_open = true
	_dim_touch(true)
	_player._movement_locked = true


func _close_travel_map() -> void:
	if not _map_open:
		return
	_map_open = false
	_map_layer.visible = false
	_dim_touch(false)
	if _map != null and is_instance_valid(_map):
		_map.queue_free()
	_map = null
	_player._movement_locked = false
	_refresh_hud_stats()


func _on_map_chosen(target: String) -> void:
	_depart_to(target)


func _depart_to(target: String) -> void:
	if _day == null or _travel == null:
		return
	# D3：行动次数取真源（RunState.actions_left），不再写死 1。
	var from_building := _current_building
	var verdict := _travel.can_travel(_current_building, target, {"fuel": _fuel, "actions_left": _run.actions_left, "hour": 12})
	if not bool(verdict.get("ok", false)):
		Analytics.track("travel_depart", {
			"from": from_building, "to": target, "day": int(_run.day),
			"fuel": int(_fuel), "actions_left": int(_run.actions_left),
			"ok": 0, "reason": str(verdict.get("reason", "")),
		})
		_toast_combat("去不了：%s" % _reason_text(str(verdict.get("reason", ""))))
		return
	var label := _travel.label_of(target)
	# D3：出发即消耗当天这一次行动；结算跨天后在末尾恢复。
	_run.actions_left = maxi(0, _run.actions_left - 1)
	var supplies_before := _get_supplies()
	var result := _day.settle({
		"extracted": true,
		"supplies": supplies_before,
		"health": _health,
		"kills": _enemies_killed,
		"noise": _noise,
	})
	# M2a 第 3 步：结算只交出「增量」，由 _add_supplies 写进真源。
	# 这样即使同一天里别的系统改过物资，也不会被一次覆盖抹掉。
	_add_supplies(float(result.get("supplies_delta", 0.0)))
	_health = float(result["health"])
	_current_building = target
	# D4：燃料不随旅程消耗（门槛语义）；到加油站补给 +1，上限 3。
	if target == "gas_station":
		_fuel = mini(FUEL_MAX, _fuel + 1)
	if not _visited.has(target):
		_visited.append(target)
	_close_travel_map()
	_at_exit = false
	_player.global_position = Vector2(2 * TILE_SIZE, 8 * TILE_SIZE)
	_player.velocity = Vector2.ZERO
	# D3：结算后是新的世界日，恢复当天的行动预算（一天一次外出）。
	_run.actions_left = _travel.actions_per_day()
	# D12：新的一天开始 → 抽 1 张事件卡（作用在 world_state 上，随存档保留）。
	_sync_world_day()
	_fire_daily_card()
	_persist_run()
	# P0-4：第一次成功出门 = 第三步引导完成
	_tutorial_advance(_tutorial.note_depart() if _tutorial != null else false)
	var lines: Array = result["lines"]
	lines.append("明天在%s" % label)
	_show_panel("第 %d 天结束" % (int(result["day"]) + 1), lines.slice(1), "exit")
	if bool(result["finished"]):
		_toast_combat("三十天到了。")
	_refresh_hud_stats()
	# D5：结算之后判定一次结局——够格就写进档案，回主界面的结局栏能看到。
	_evaluate_ending()
	Analytics.track("travel_depart", {
		"from": from_building, "to": target, "day": int(_run.day),
		"fuel": int(_fuel), "actions_left": int(_run.actions_left),
		"ok": 1, "reason": "",
	})
	Analytics.track("day_end", {
		"day": int(_run.day), "building": _current_building,
		"sediment": int(_run.sediment), "supplies": float(_run.supplies),
		"health": float(_health), "kills": int(_enemies_killed),
		"fuel": int(_fuel), "finished": int(bool(result.get("finished", false))),
		"mode": "story",
	})
	Analytics.track("travel_arrive", {"to": target, "day": int(_run.day)})
	# 真切换：同一个走廊场景，但 RunState.building 已经变了，重新加载后读到新楼。
	# 门禁/manual add 场景时 current_scene 为空，这种情况下只更新状态、不换场景。
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		tree.change_scene_to_file("res://game/scenes/corridor.tscn")


## 把走廊的状态写回 RunState 并存盘 —— 切场景/重启都靠它。
func _persist_run() -> void:
	if _run == null:
		return
	_run.day = _day.day
	_run.sediment = _day.sediment
	_run.building = _current_building
	_run.fuel = _fuel
	_run.supplies = _get_supplies()
	_run.health = _health
	_run.visited = _visited.duplicate()
	# D12：卡牌改过的 world_state 六组变量要跟着存档（旧档没有这个键也不影响）。
	if _state != null:
		var vars: Dictionary = {}
		for key: String in CARD_VARIABLE_KEYS:
			vars[key] = _state.var_of(key)
		_run.world_vars = vars
	_run.save()


## D12：world_state 的世界日与 DayCycle 对齐（卡牌 trigger.day 依赖它）。
func _sync_world_day() -> void:
	if _state == null:
		return
	for _i in range(40):
		if _state.day >= _day.day or _state.day >= 30:
			return
		_state.advance_day()


## D12：把存档镜像里的六组变量恢复到 world_state（卡牌效果跨场景/重启保留）。
func _restore_world_vars() -> void:
	if _state == null or _run == null:
		return
	for key: String in CARD_VARIABLE_KEYS:
		if _run.world_vars.has(key):
			_state.set_var(key, float(_run.world_vars[key]))


## D12：每天开始抽 1 张 L 卡并作用于 world_state；同一天只抽一次。
func _fire_daily_card() -> Dictionary:
	if _card == null or _state == null or _day == null or _card_day == _day.day:
		return {"fired": false}
	_card_day = _day.day
	var result := _card.pick_and_fire(_current_room_node(), _day.day * 7 + 1)
	if bool(result.get("fired", false)):
		_cards_fired += 1
		_last_card_id = str(result.get("card_id", ""))
		_last_card_text = str(result.get("text", ""))
		if not _last_card_text.is_empty():
			_toast_combat("事件：" + _last_card_text)
		_refresh_hud_stats()
		Analytics.track("card_fire", {"card_id": _last_card_id, "day": int(_day.day)})
	return result


func last_card_id() -> String:
	return _last_card_id


func last_card_text() -> String:
	return _last_card_text


func cards_fired() -> int:
	return _cards_fired


## D7：按当前楼载入主题（tileset + 道具场景 + 环境亮度）。
## 主题缺失时退回学校资产，绝不空白启动。
func _apply_theme() -> void:
	_theme_id = _current_building if not _current_building.is_empty() else "school"
	var path := "%s/%s.json" % [THEME_DIR, _theme_id]
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not raw is Dictionary:
		push_error("THEME_MISSING: " + path)
		_theme = {}
		_theme_ambient = 1.0
		_sheet = SHEET_FALLBACK
		return
	_theme = raw
	_theme_ambient = clampf(float(_theme.get("ambient", 1.0)), 0.5, 1.5)
	var tileset_path := str(_theme.get("tileset", ""))
	_sheet = SHEET_FALLBACK
	if not tileset_path.is_empty() and ResourceLoader.exists(tileset_path):
		_sheet = load(tileset_path) as Texture2D
	var props_path := str(_theme.get("props_scene", ""))
	if props_path.is_empty() or not ResourceLoader.exists(props_path):
		return
	var packed := load(props_path) as PackedScene
	if packed == null:
		push_error("THEME_PROPS_SCENE_INVALID: " + props_path)
		return
	var themed := packed.instantiate()
	themed.name = "Props"
	var old := get_node_or_null("Props")
	if old != null:
		remove_child(old)
		old.queue_free()
	add_child(themed)


func theme_id() -> String:
	return _theme_id


func theme_ambient() -> float:
	return _theme_ambient


func theme_tileset() -> Texture2D:
	return _sheet


func current_building_id() -> String:
	return _current_building



## M2a 的唯一物资读口：在线走 world_state，离线退回 RunState 镜像。
func _get_supplies() -> float:
	if _state != null:
		return _state.var_of("supplies")
	return _run.supplies


## M2a 的唯一物资写口（绝对值）：真源 + 存档镜像一起写。
func _set_supplies(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if _state != null:
		_state.set_var("supplies", clamped)
	_run.supplies = clamped


## M2a 第 2 步：增量写。所有「涨/掉一点」都走这里，不再读出来加完再写回去。
func _add_supplies(delta: float) -> float:
	if _state != null:
		var value := _state.add_var("supplies", delta)
		_run.supplies = value
		return value
	_run.supplies = clampf(_run.supplies + delta, 0.0, 1.0)
	return _run.supplies


## D5：把「判定结局 → 记进档案 → 落盘」这条路打通。
## 条件数据在 data/endings/school.json；这里只负责把当前局势喂进去。
func _ending_context() -> Dictionary:
	var ctx := {
		"day": _day.day,
		"companions_alive": _run.companions_alive,
		"companions_lost": _run.companions_lost,
		"bond": _run.bond,
		"finale": _run.finale,
		"ammo": _magazine,
		"items": _inventory.ids(),
	}
	if _state != null:
		ctx["trust"] = _state.var_of("trust")
		ctx["control"] = _state.var_of("control")
		ctx["knowledge"] = _state.var_of("knowledge")
		ctx["supplies"] = _state.var_of("supplies")
	else:
		ctx["trust"] = 0.0
		ctx["control"] = 0.0
		ctx["knowledge"] = 0.0
		ctx["supplies"] = _get_supplies()
	return ctx


## 返回命中的结局 id（空 = 还没走到任何结局）。命中即写进档案并保存。
func _evaluate_ending() -> String:
	if _book == null or _run == null:
		return ""
	var ending_id := _book.match_ending(ENDING_TEMPLATE, _ending_context())
	if ending_id.is_empty():
		return ""
	if not _book.is_unlocked(ENDING_TEMPLATE, ending_id):
		_book.unlock(ENDING_TEMPLATE, ending_id)
		_run.unlock_ending(ENDING_TEMPLATE, ending_id)
		_run.save()
		Analytics.track("ending_unlock", {
			"ending_id": ending_id, "day": int(_run.day),
			"template": ENDING_TEMPLATE, "mode": "story",
		})
		_toast_combat("结局已记入档案")
	return ending_id


func supplies_online() -> bool:
	return _supplies_online


## M2a-2：噪声唯一出口。走廊的三段对应学校主轴的三节，别处（d/e 及其他楼层）还没接。
## 世界层负责「按当天敏感度缩放 + 传染给相邻节点 + 加沉积」，走廊只负责「报一个底值」。
const ROOM_NODE_IDS: Array[String] = ["school_corridor_a", "school_corridor_b", "school_corridor_c"]


func _current_room_node() -> String:
	if _player == null:
		return ROOM_NODE_IDS[0]
	return ROOM_NODE_IDS[_current_room_index()]


## D11：玩家所在区块索引（0=A / 1=B / 2=C），和 ROOM_PARTITION_TILES 同一判据。
func _current_room_index() -> int:
	if _player == null:
		return 0
	var tile_x := _player.global_position.x / float(TILE_SIZE)
	if tile_x < float(ROOM_PARTITION_TILES[0]):
		return 0
	if tile_x < float(ROOM_PARTITION_TILES[1]):
		return 1
	return 2


## D11 门禁口：当前平滑后的灯光乘数 / 区块索引。
func room_light_factor() -> float:
	return _light_zone


func current_room_index() -> int:
	return _current_room_index()


func _emit_noise(base: int) -> int:
	if base <= 0:
		return _noise
	if _state != null:
		# night=false：走廊现在没有时刻概念（搜索按游戏小时推进但不区分昼夜），
		# 等 M3 的时间层接上再传真实昼夜，别在这里假装有。
		var result := _state.add_noise(_current_room_node(), base, false)
		_noise += int(result.get("self", base))
	else:
		_noise += base
	# D10：≥阈值的噪声把听程内的感染体引向声源（2 秒）；近战 1 不触发。
	if base >= NOISE_HEAR_THRESHOLD:
		var source := _player.global_position if _player != null else Vector2.ZERO
		for enemy: Enemy in _enemies:
			if enemy != null and is_instance_valid(enemy) and not enemy.dead:
				enemy.hear(source)
	return _noise


func _update_player_anim(delta: float) -> void:
	if _player == null or not CharAnim.has("player"):
		return
	var sprite := _player.get_node_or_null("BodySprite") as Sprite2D
	if sprite == null:
		return
	_player_anim_time += delta
	_player_hurt_t = maxf(0.0, _player_hurt_t - delta)
	var anim_id := "idle"
	var anim_time := _player_anim_time
	if _player_hurt_t > 0.0:
		anim_id = "hurt"
	elif _attack_frames > 0:
		# 挥击：独立时间轴，按下左键那一帧从头播，不跟走路相位混。
		_attack_anim_t += delta
		anim_id = "attack"
		anim_time = _attack_anim_t
	elif absf(_player.velocity.x) + absf(_player.velocity.y) > 1.0:
		anim_id = "walk"
	_player_anim_id = anim_id
	var frame := CharAnim.frame_at("player", anim_id, anim_time)
	sprite.texture = CharAnim.frame_texture("player", frame)
	sprite.flip_h = _player.facing_x < 0.0


## 命中反馈：顿帧（短暂冻结）+ 受击者闪白 + 1px 抖屏。
## 击杀比普通命中多冻 2 帧、多抖 1 次，读起来更“重”。
func _play_hit_feedback(target: Enemy, killed: bool) -> void:
	_hitstop_frames = HITSTOP_KILL_FRAMES if killed else HITSTOP_FRAMES
	_shake_frames = 4 if killed else 2
	_set_actors_frozen(true)
	var sprite := target.get_node_or_null("BodySprite") as Sprite2D
	if sprite != null:
		sprite.modulate = Color(2.2, 2.2, 2.2)
		_flash_targets = [target]
		# 至少留 2 帧：输入处理发生在 _process 之前，只给 1 帧会被同一帧就清掉。
		_flash_frames = 3 if killed else 2


func _set_actors_frozen(frozen: bool) -> void:
	if _player != null:
		_player.set_physics_process(not frozen)
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.set_physics_process(not frozen)


func _update_hit_feedback() -> void:
	if _shake_frames > 0:
		_shake_frames -= 1
		if _camera != null:
			_camera.offset = Vector2(SHAKE_PX if _shake_frames % 2 == 0 else -SHAKE_PX, 0.0)
	elif _camera != null and _camera.offset != Vector2.ZERO:
		_camera.offset = Vector2.ZERO
	if _hitstop_frames > 0:
		_hitstop_frames -= 1
		if _hitstop_frames == 0:
			_set_actors_frozen(false)
	if _flash_frames > 0:
		_flash_frames -= 1
		if _flash_frames == 0:
			for enemy: Enemy in _flash_targets:
				if is_instance_valid(enemy):
					var sprite := enemy.get_node_or_null("BodySprite") as Sprite2D
					if sprite != null:
						sprite.modulate = Color.WHITE
			_flash_targets.clear()


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
	# 暗罩必须盖满**画布**：手机画布是 555×256，只按 384×216 盖会露出未压暗的一圈，
	# 表现为「屏幕上一个方框」（真机反复出现的那圈就是它，不是状态边框）。
	mask.size = Vector2(ScreenLayout.canvas_of(self))
	mask.material = _light_material
	layer.add_child(mask)


func _process(delta: float) -> void:
	_update_hit_feedback()
	# D9：体力归零 → 倒下结算。放在顿帧 return 之前，免得被顿帧拖到无敌窗口。
	if not _downing and _health <= 0.0 and _day != null and int(_day.day) != _down_day:
		_trigger_down()
	if _hitstop_frames > 0:
		# 顿帧：世界停住，只有反馈在动。镜头也刻意不跟，让这一下“钉”在屏幕上。
		return
	_follow_player()
	_update_flashlight()
	_update_depth_order()
	_update_doors()
	_update_search(delta)
	_update_player_anim(delta)
	# 触屏上下文键：贴近可搜索容器、或站在出口时出现「搜」，离开即消失。
	if _mobile != null:
		_mobile.set_search_available(_searchable_nearby() or _at_exit)
	var near_exit := _player != null and _player.position.x >= EXIT_HINT_X
	if near_exit != _at_exit:
		_at_exit = near_exit
		_refresh_hud_stats()
	if _combat_message_frames > 0:
		_combat_message_frames -= 1
		if _combat_message_frames == 0:
			_combat_message = ""
			_refresh_hud_stats()
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
	# 旅行图是模态的：按键由走廊统一转发给地图，别让下面搜索/门/攻击抢走。
	if _map_open:
		if event is InputEventKey and not event.is_echo() and event.is_pressed():
			if event.is_action_pressed("menu_up"):
				_map.move(-1)
			elif event.is_action_pressed("menu_down"):
				_map.move(1)
			elif event.is_action_pressed("menu_confirm"):
				_map.confirm()
			elif event.is_action_pressed("menu_back"):
				_close_travel_map()
			_consume_input()
		return
	# 左键攻击：背包/检查面板打开时不响应。
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed and not _inventory_open and not _inspection_open:
			_perform_attack()
			_consume_input()
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
		_consume_input()
		return
	# 手电开关（F）：面板打开时不响应，避免和交互抢键。
	if event.is_action_pressed("toggle_light") and not _inspection_open:
		_set_flashlight(not _flashlight_on)
		_consume_input()
		return
	if event.is_action_pressed("inventory") and not _inspection_open:
		_open_inventory()
		_consume_input()
		return
	# R = 装填（当前装备是枪械时）。
	if event.is_action_pressed("reload") and not _inspection_open and not _inventory_open:
		_reload_weapon()
		_consume_input()
		return
	if _inspection_open:
		# 面板打开时：V/E/Esc 都关掉（E 是上下文交互键，顺手关面板）。
		if event.is_action("view") or event.is_action("pickup") or event.is_action("cancel_inspect"):
			_close_inspection()
			_consume_input()
		return
	if event.is_action("cancel_inspect"):
		return
	# E = 上下文交互：优先搜索容器；否则开关/锁最近的门。
	if event.is_action_pressed("pickup"):
		var pickup_target := _nearest_inspection_id()
		if not pickup_target.is_empty() and _loot != null and _loot.has_container(pickup_target):
			_begin_search(pickup_target)
			_consume_input()
			return
		if _at_exit:
			_leave_building()
			_consume_input()
			return
		if _nearest_door >= 0:
			_toggle_door(_nearest_door)
			_consume_input()
		return
	# V = 查看文本（检查框）。
	if event.is_action_pressed("view"):
		var target := _nearest_inspection_id()
		if target.is_empty():
			return
		_inspection_target = target
		_draw_inspection_prompt(target)
		_show_inspection(target)
		_consume_input()


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
	var facing := 1.0 if _player.facing_x >= 0.0 else -1.0
	# 灯位跟着朝向镜像：朝左时灯在身体左侧，否则光会从身体右边冒出去。
	var screen_origin := _player.get_global_transform_with_canvas().origin.round()
	_light_material.set_shader_parameter("light_pos_px", screen_origin + Vector2(9.0 * facing, -13))
	# 光锥方向：0 = 朝右，PI = 朝左。之前这里从来没写过 cone_dir，
	# 所以朝左走时光锥还一直朝右——这是可见的 bug，不是观感问题。
	var target_angle := 0.0 if facing > 0.0 else PI
	_light_angle = lerp_angle(_light_angle, target_angle, 0.35)
	if absf(_angle_delta(_light_angle, target_angle)) < 0.02:
		_light_angle = target_angle
	# 归一化到 [0, 2π)：-PI 与 PI 指向同一个方向，但写进着色器前统一成正值更好读。
	_light_material.set_shader_parameter("cone_dir", fposmod(_light_angle, TAU))
	# D11：区块灯光。A 区靠窗更亮、C 区最深；16 帧左右平滑过渡，不硬切。
	# D7：再乘上当前楼的整体环境亮度（加油站开阔更亮、军事基地更暗）。
	var zone_target: float = ROOM_LIGHT_LEVELS[_current_room_index()] * _theme_ambient
	_light_zone = lerpf(_light_zone, zone_target, 0.15)
	var tint := LIGHT_OUTSIDE_BASE * _light_zone
	_light_material.set_shader_parameter("outside_tint", Vector4(tint.x, tint.y, tint.z, 1.0))


## 两个角度之间的最短夹角（弧度，取绝对值）。
func _angle_delta(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))


## 门禁用：当前光锥角度（0 = 朝右，PI = 朝左）。
func light_angle() -> float:
	return _light_angle

## 输入提示统一走 InputHints：桌面是键鼠文案，手机是触屏文案（空则整行不画）。
func _draw_hint(parent: Node, key: String, at: Vector2, color: Color) -> void:
	var text := InputHints.get_hint(key)
	if text.is_empty():
		return
	PixelFont.draw(parent, text, at, color)

## 输入消费的安全包装：切场景/节点已出树时 get_viewport() 会是 null，
## 直接调用会抛「Cannot call method 'set_input_as_handled' on a null value」并中断该次输入处理
## （真机 logcat 抓到过）。所有 _unhandled_input 里都改走这里。
func _consume_input() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
