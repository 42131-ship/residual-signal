class_name IntroSequence
extends CanvasLayer
## 开场过场：按 data/campus/<id>.json 的 intro.beats 逐拍播，最后一拍交还控制权。
##
## 为什么做成走廊里的一个覆盖层，而不是独立场景：开场结束时要**无缝**接上已经做好的走廊玩法，
## 中间不能有一次场景切换（切场景会重搭走廊、重抽卡、重读存档，观感全断）。
## 所以它挂在走廊里、盖在 HUD 上，播完自己消失，走廊从头到尾都是同一个实例。
##
## 六拍（数据驱动，R48 与 campus-map 门禁锁顺序）：
##   bell     黑场 + 上课铃（项目里没有音频，用铃形与波纹代替）
##   overview 整张校园图 + 路线虚线，让玩家先记住布局
##   toilet   推近主楼一层，叠一个厕所小景：三个学生、一根被弹进坑位的烟
##   alarm    铃声戛然而止，红色报警脉冲压下来
##   zoom     淡黑 → 掀开到走廊，镜头落在角色身上
##   walkout  玩家先不用操作：角色自动向右走出厕所进走廊，**灯全灭**；走完才交控制权
##
## 门禁用 debug_advance() 直接推时间，不靠真实 60 帧等 27 秒。

signal finished

const MAP_ID := "school"
const CAMPUS_SCRIPT := preload("res://game/ui/campus_map.gd")
const INK := Color("#f6f6f0")
const DIM := Color("#9fb2bd")
const BAR_H := 16.0
const ALARM_RED := Color("#7a1f22")
const EMBER := Color("#d4813a")
const WALK_SPEED := 24.0

## 门禁要能一次推完；这里按 1/60 切片推进，delta 语义与运行时一致。
const TICK := 1.0 / 60.0

var beats: Array = []
var phase := ""
var elapsed := 0.0
var done := false

var _corridor: Node2D
var _player: Player
var _canvas := Vector2(384, 216)
var _origin := Vector2.ZERO

var _map_holder: Node2D
var _map
var _stage: Stage
var _text_root: Node2D
var _fade: ColorRect
var _bars: Array[ColorRect] = []

var _walk_target := 0.0
var _route_step := 0
var _alarm_t := 0.0


## 画原始形状的那个 Node2D（CanvasLayer 自己没有 _draw）。
class Stage:
	extends Node2D
	var host: IntroSequence

	func _draw() -> void:
		if host != null:
			host.draw_stage(self)


func begin(corridor: Node2D, player: Player) -> void:
	_corridor = corridor
	_player = player
	layer = 60
	_canvas = Vector2(ScreenLayout.canvas_of(corridor))
	_origin = Vector2(ScreenLayout.origin_of(corridor))
	beats = _load_beats()
	_build_layers()
	if beats.is_empty():
		push_error("INTRO_NO_BEATS")
		_finish()
		return
	# 过场期间：走廊不吃输入、角色不动。灯先别关——「灯全灭了」要在玩家走出厕所那一下才砸下来。
	if _corridor != null:
		_corridor._intro_active = true
		_corridor.set_hud_visible(false)
	if _player != null:
		_player._movement_locked = true
		_player.velocity = Vector2.ZERO
		_player.facing_x = 1.0
	_enter_beat(0)


func _load_beats() -> Array:
	var loader = CAMPUS_SCRIPT.new()
	if not loader.load_for(MAP_ID):
		push_error("INTRO_CAMPUS_FAILED: " + loader.load_error)
		return []
	var intro: Variant = loader.data.get("intro", {})
	var rows: Array = []
	if intro is Dictionary:
		rows = (intro as Dictionary).get("beats", [])
	return rows


func _build_layers() -> void:
	# 图层顺序（手机画布 555×256 上尤其重要）：
	#   底色黑场（盖住走廊与触控键）→ 地图（384×216 居中，两边留黑）→ 形状 → 文字 → 信箱条。
	# 之前把地图放在黑场下面，结果黑场一透明（地图拍）四周就把走廊和按钮漏出来了。
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 1)
	_fade.position = Vector2.ZERO
	_fade.size = _canvas
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	_map_holder = Node2D.new()
	_map_holder.name = "MapHolder"
	add_child(_map_holder)
	_map = CAMPUS_SCRIPT.new()
	# 先入树再读图：CampusMap 的标签层是在 _ready 里建的，先 load_for 会拿不到标签（画出来是空图）。
	_map_holder.add_child(_map)
	_map.load_for(MAP_ID)
	_map_holder.position = _origin

	_stage = Stage.new()
	_stage.name = "Stage"
	_stage.host = self
	add_child(_stage)

	_text_root = Node2D.new()
	_text_root.name = "IntroText"
	add_child(_text_root)

	for side in range(2):
		var bar := ColorRect.new()
		bar.color = Color("#05070a")
		bar.position = Vector2(0, 0 if side == 0 else _canvas.y - BAR_H)
		bar.size = Vector2(_canvas.x, BAR_H)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	# 跳过提示：小字贴在信箱条右端，不抢旁白的位。
	PixelFont.draw(self, "任意键跳过", Vector2(_canvas.x - 62.0, _canvas.y - BAR_H - 14.0),
		Color(0.62, 0.68, 0.73, 0.75))


func _enter_beat(index: int) -> void:
	if index >= beats.size():
		_finish()
		return
	var beat: Dictionary = beats[index] as Dictionary
	phase = str(beat.get("id", ""))
	elapsed = 0.0
	_draw_beat_text(beat)
	_configure_camera(beat)
	if phase == "walkout":
		_start_walkout(beat)
	_stage.queue_redraw()


func _configure_camera(beat: Dictionary) -> void:
	var mode := str(beat.get("camera", "black"))
	match mode:
		"map_fit":
			_map_holder.visible = true
			_map_holder.scale = Vector2.ONE
			_map_holder.position = _origin
			# 底色保持不透明：地图只有 384 宽，手机画布 555 宽，四周必须被黑吃掉。
			_fade.color.a = 1.0
		"map_zoom":
			_map_holder.visible = true
			var focus: Array = beat.get("focus", [110, 58])
			var focus_point := Vector2(float(focus[0]), float(focus[1]))
			var zoom := 2.6
			_map_holder.scale = Vector2(zoom, zoom)
			# 让 focus 点落在画布中心：pos = 中心 - focus*zoom（再扣掉居中偏移）。
			_map_holder.position = _origin + (_canvas * 0.5 - focus_point * zoom)
			_fade.color.a = 1.0
		"corridor_push":
			_map_holder.visible = false
			_fade.color.a = 0.0
		_:
			_map_holder.visible = false
			_fade.color.a = 1.0


func _start_walkout(beat: Dictionary) -> void:
	_map_holder.visible = false
	_fade.color.a = 0.0
	# 「往右一拐，灯全灭了」——这一下必须看得见：手电熄掉、环境压到 1/3。
	if _corridor != null and _corridor.has_method("set_lights_out"):
		_corridor.set_lights_out(true)
	if _player != null:
		_walk_target = _player.global_position.x + float(beat.get("autowalk", 76.0))
		_player.facing_x = 1.0


func _draw_beat_text(beat: Dictionary) -> void:
	for child: Node in _text_root.get_children():
		child.queue_free()
	var lines: Array = beat.get("lines", [])
	if lines.is_empty():
		return
	# 文字压在图上会糊：先铺一条半透明底板，再写字（底板也进 _text_root，一起清）。
	var block_h := 12.0 * float(mini(lines.size(), 2))
	var y := _canvas.y - BAR_H - 8.0 - block_h
	var widest := 0.0
	for index in mini(lines.size(), 2):
		widest = maxf(widest, float(PixelFont.width_of(str(lines[index]))))
	var backing := ColorRect.new()
	backing.name = "TextBg"
	backing.color = Color(0.02, 0.03, 0.045, 0.78)
	backing.position = Vector2(_origin.x + (384.0 - widest) * 0.5 - 4.0, y - 3.0)
	backing.size = Vector2(widest + 8.0, block_h + 5.0)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_root.add_child(backing)
	for index in mini(lines.size(), 2):
		var text := str(lines[index])
		var width := float(PixelFont.width_of(text))
		var x := clampf(_origin.x + (384.0 - width) * 0.5, 6.0, _canvas.x - width - 6.0)
		var tint := INK if index == 0 else DIM
		PixelFont.draw(_text_root, text, Vector2(x, y + 12.0 * float(index)), tint)


func _process(delta: float) -> void:
	if done:
		return
	_tick(delta)


## 任意键/点一下 → 跳过整段（玩家不想看就该能不看；门禁用 skip_all 同一条路）。
func _unhandled_input(event: InputEvent) -> void:
	if done:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed:
		skip_all()


## 推进一拍的时间。delta 累积到本拍时长就换下一拍；walkout 里同时推角色。
func _tick(delta: float) -> void:
	if done or beats.is_empty():
		return
	elapsed += delta
	if phase == "walkout":
		_advance_walkout(delta)
	if phase == "alarm":
		_alarm_t += delta
	if phase == "overview":
		_route_step += 1
	var current: Dictionary = beats[_beat_index()] as Dictionary
	if elapsed >= float(current.get("seconds", 1.0)):
		_enter_beat(_beat_index() + 1)
		return
	_stage.queue_redraw()


func _advance_walkout(delta: float) -> void:
	if _player == null:
		return
	var step := WALK_SPEED * delta
	if _player.global_position.x >= _walk_target - 0.5:
		return
	# 直接推坐标（不走 move_and_slide：过场里没有碰撞要处理，走廊纵深也被夹住了）。
	_player.global_position = Vector2(minf(_player.global_position.x + step, _walk_target), _player.global_position.y)
	_player.facing_x = 1.0


func _beat_index() -> int:
	for index in beats.size():
		if str((beats[index] as Dictionary).get("id", "")) == phase:
			return index
	return beats.size() - 1


## 门禁用：把时间整段推过去（不靠真实帧）。
func debug_advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0 and not done:
		var step := minf(TICK, remaining)
		_tick(step)
		remaining -= step


## 门禁用：跳过全部剩余，直接交还控制权。
func skip_all() -> void:
	while not done:
		_tick(1.0)


func _finish() -> void:
	if done:
		return
	done = true
	IntroFlag.mark_seen()
	if _fade != null:
		_fade.color = Color(0, 0, 0, 0)
	if _text_root != null:
		for child: Node in _text_root.get_children():
			child.queue_free()
	for bar: ColorRect in _bars:
		bar.visible = false
	if _corridor != null:
		_corridor._intro_active = false
		_corridor.set_hud_visible(true)
		if _corridor.has_method("set_lights_out"):
			# 灯不会自己回来：玩家得自己按手电（这正是"灯全灭了"要玩家做的第一件事）。
			_corridor.set_lights_out(true)
	if _player != null:
		_player._movement_locked = false
	finished.emit()
	queue_free()


# ── 原始形状 ───────────────────────────────────────────────

func draw_stage(canvas: CanvasItem) -> void:
	match phase:
		"bell":
			_draw_bell(canvas)
		"toilet":
			_draw_toilet(canvas)
		"alarm":
			_draw_alarm(canvas)
		"overview":
			_draw_route(canvas)


func _draw_bell(canvas: CanvasItem) -> void:
	var center := _origin + Vector2(192, 96)
	var ring := fmod(elapsed, 1.2) / 1.2
	# 铃身：梯形 + 一条横梁
	canvas.draw_colored_polygon(PackedVector2Array([
		center + Vector2(-10, 10), center + Vector2(10, 10),
		center + Vector2(14, -10), center + Vector2(-14, -10),
	]), DIM)
	canvas.draw_rect(Rect2(center + Vector2(-16, -14), Vector2(32, 3)), INK, true)
	canvas.draw_rect(Rect2(center + Vector2(-3, 10), Vector2(6, 4)), INK, true)
	# 三圈波纹：铃声在响（没有音频资产，只能靠它）
	for index in range(3):
		var t := fmod(ring + float(index) / 3.0, 1.0)
		var radius := 22.0 + 46.0 * t
		var alpha := (1.0 - t) * 0.55
		canvas.draw_arc(center, radius, -0.9, 0.9, 20, Color(INK.r, INK.g, INK.b, alpha), 1.0)
		canvas.draw_arc(center, radius, PI - 0.9, PI + 0.9, 20, Color(INK.r, INK.g, INK.b, alpha), 1.0)


func _draw_toilet(canvas: CanvasItem) -> void:
	# 小景压在画布右下：三个隔间门 + 两个站在湿地上的人 + 一个蹲在最后一格的人 + 一根被弹进去的烟。
	var panel := Rect2(_origin + Vector2(196, 58), Vector2(180, 96))
	canvas.draw_rect(panel, Color(0.03, 0.04, 0.06, 0.94), true)
	canvas.draw_rect(panel, DIM, false, 1.0)
	for index in range(3):
		var door := Rect2(panel.position + Vector2(12 + index * 46, 10), Vector2(34, 46))
		canvas.draw_rect(door, Color("#141c26"), true)
		canvas.draw_rect(door, Color("#2b3b4a"), false, 1.0)
		canvas.draw_rect(Rect2(door.position + Vector2(28, 24), Vector2(3, 3)), DIM, true)
	# 湿地线在 y=78：人站在它上面，不跟隔间门叠在一起
	canvas.draw_rect(Rect2(panel.position + Vector2(6, 78), Vector2(168, 3)), Color("#1b2734"), true)
	canvas.draw_rect(Rect2(panel.position + Vector2(38, 79), Vector2(18, 1)), Color("#3d566e"), true)
	canvas.draw_rect(Rect2(panel.position + Vector2(108, 79), Vector2(26, 1)), Color("#3d566e"), true)
	# 两个人站在湿地左边，一个蹲在最后一格里（门开着）
	_silhouette(canvas, panel.position + Vector2(24, 76), 1.0)
	_silhouette(canvas, panel.position + Vector2(44, 77), 1.0)
	_silhouette(canvas, panel.position + Vector2(132, 70), 0.8)
	# 烟头：从右边那个人手里抛进最后一格，0.9 秒一个来回
	var toss := fmod(elapsed, 0.9) / 0.9
	var from := panel.position + Vector2(50, 62)
	var to := panel.position + Vector2(132, 34)
	var at := from.lerp(to, toss) + Vector2(0, -22.0 * sin(PI * toss))
	canvas.draw_rect(Rect2(at, Vector2(2, 2)), Color(EMBER.r, EMBER.g, EMBER.b, 1.0 - toss * 0.4), true)


func _silhouette(canvas: CanvasItem, at: Vector2, scale: float) -> void:
	var body := Rect2(at + Vector2(-4, -18) * scale, Vector2(8, 18) * scale)
	canvas.draw_rect(body, Color("#0a0f14"), true)
	canvas.draw_rect(body, Color("#2b3b4a"), false, 1.0)
	canvas.draw_circle(at + Vector2(0, -22) * scale, 3.5 * scale, Color("#0a0f14"))


func _draw_alarm(canvas: CanvasItem) -> void:
	# 报警铃：没有"铃声"，只有压下来的红。频率 0.6s 一次，和文本一拍一拍地走。
	var pulse := 0.5 + 0.5 * sin(_alarm_t * TAU / 0.6)
	canvas.draw_rect(Rect2(Vector2.ZERO, _canvas), Color(ALARM_RED.r, ALARM_RED.g, ALARM_RED.b, 0.10 + 0.16 * pulse), true)
	for index in range(3):
		var t := fmod(_alarm_t / 0.6 + float(index) / 3.0, 1.0)
		var radius := 16.0 + 60.0 * t
		canvas.draw_arc(_origin + Vector2(192, 92), radius, -2.6, -0.5, 16,
			Color(ALARM_RED.r + 0.4, ALARM_RED.g + 0.2, ALARM_RED.b + 0.2, (1.0 - t) * 0.8), 1.0)


func _draw_route(canvas: CanvasItem) -> void:
	if _map == null or _map.data.is_empty():
		return
	var route: Array = _map.data.get("route", [])
	if route.size() < 2:
		return
	var points := PackedVector2Array()
	for stop: Variant in route:
		var region: Dictionary = _map.region_of(str(stop))
		var rect: Array = region.get("rect", [])
		if rect.size() != 4:
			continue
		points.append(_origin + Vector2(float(rect[0]) + float(rect[2]) * 0.5, float(rect[1]) + float(rect[3]) * 0.5))
	if points.size() < 2:
		return
	# 虚线：一段一段画，读起来像"路线"而不是"墙"
	for index in range(points.size() - 1):
		var from := points[index]
		var to := points[index + 1]
		var length := from.distance_to(to)
		var travelled := 0.0
		while travelled < length:
			var seg_end := minf(travelled + 4.0, length)
			canvas.draw_line(from.lerp(to, travelled / length), from.lerp(to, seg_end / length),
				Color(INK.r, INK.g, INK.b, 0.45), 1.0)
			travelled += 7.0
	# 一颗沿路线走的点：一眼看出"这条路是往哪边推进的"
	var march := fmod(elapsed * 0.25, 1.0) * float(points.size() - 1)
	var leg := clampi(int(march), 0, points.size() - 2)
	var dot := points[leg].lerp(points[leg + 1], march - float(leg))
	canvas.draw_rect(Rect2(dot - Vector2(1.5, 1.5), Vector2(3, 3)), INK, true)
