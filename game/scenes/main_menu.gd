extends Node2D
## 主界面壳：新游戏 / 继续 / 结局栏。
##
## 全部用程序画（ColorRect + 像素字），不依赖任何外部贴图 —— 这样任何时候都能过像素门禁，
## 也不会因为「等美术」把流程卡住。将来要换成生图背景，走 tools/quantize_map.py 量化后再替换。

const VIEW := Vector2i(384, 216)
const INK := Color("#9fb2bd")
const BRIGHT := Color("#f6f6f0")
const DIM := Color("#354b60")
const FRAME := Color("#635e57")
const BG := Color("#0b1119")

const ITEMS := ["新游戏", "继续", "结局栏"]
const ENDING_TEMPLATE := "school"
const BG_PATH := "res://art/generated_candidates/maps/menu_bg.png"
## 背景是生图量化来的，压一层暗罩保证文字对比度（这是 UI 罩层，不是资产，允许半透明）。
const SCRIM := Color(0.043, 0.067, 0.098, 0.55)

var _index := 0
var _view := "root"          # root / endings
var _message := ""
var _message_frames := 0
## 菜单与走廊共用同一个 RunState（静态引用），否则「新游戏」会丢掉结局档案。
var _run: RunState = RunState.ensure()
var _book := EndingBook.new()
var _item_root: Node2D
var _body_root: Node2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_actions()
	_build_chrome()
	_item_root = _node("Items")
	_body_root = _node("Body")
	if not _book.load_template(ENDING_TEMPLATE):
		push_error("ENDING_BOOK_FAILED: " + _book.load_error())
	_render()


func _node(node_name: String) -> Node2D:
	var root := Node2D.new()
	root.name = node_name
	add_child(root)
	return root


func _ensure_actions() -> void:
	for action: String in ["menu_up", "menu_down", "menu_confirm", "menu_back"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_add_key("menu_up", KEY_W)
	_add_key("menu_up", KEY_UP)
	_add_key("menu_down", KEY_S)
	_add_key("menu_down", KEY_DOWN)
	_add_key("menu_confirm", KEY_E)
	_add_key("menu_confirm", KEY_ENTER)
	_add_key("menu_back", KEY_ESCAPE)


func _add_key(action: String, keycode: Key) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	InputMap.action_add_event(action, key)


func _build_chrome() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BG
	background.size = Vector2(VIEW)
	add_child(background)

	# 生图背景（若已量化入库）。没有就保持纯色底 —— 任何时候都能启动，不等美术。
	var texture := load(BG_PATH) as Texture2D
	if texture != null:
		var art := Sprite2D.new()
		art.name = "KeyArt"
		art.texture = texture
		art.centered = false
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(art)
		var scrim := ColorRect.new()
		scrim.name = "Scrim"
		scrim.color = SCRIM
		scrim.size = Vector2(VIEW)
		add_child(scrim)

	# 底部一条暗带 + 顶部一条细线：给标题和菜单分层次，不靠渐变。
	var band := ColorRect.new()
	band.name = "Band"
	band.color = Color(0.067, 0.102, 0.149, 0.85)
	band.position = Vector2(0, 150)
	band.size = Vector2(VIEW.x, 66)
	add_child(band)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = FRAME
	rule.position = Vector2(16, 44)
	rule.size = Vector2(VIEW.x - 32, 1)
	add_child(rule)


func _clear(root: Node2D) -> void:
	for child: Node in root.get_children():
		child.queue_free()


func _render() -> void:
	_clear(_item_root)
	_clear(_body_root)
	if _view == "endings":
		_render_endings()
		return
	_render_root()


func _render_root() -> void:
	PixelFont.draw(_body_root, "残余信号", Vector2(16, 12), BRIGHT)
	PixelFont.draw(_body_root, "RESIDUAL SIGNAL", Vector2(16, 30), DIM)
	for index in range(ITEMS.size()):
		var y := 62 + index * 22
		if index == _index:
			_add_rect(Vector2(12, y - 4), Vector2(140, 20), DIM)
		PixelFont.draw(_item_root, ITEMS[index], Vector2(20, y), BRIGHT if index == _index else INK)
	PixelFont.draw(_body_root, "W/S 选择   E 确认", Vector2(16, 158), INK)
	PixelFont.draw(_body_root, "第 %d / %d 天 · 沉积 %d" % [_run.day + 1, RunState.MAX_DAY, _run.sediment],
		Vector2(16, 176), DIM)
	if _message_frames > 0:
		PixelFont.draw(_body_root, _message, Vector2(16, 194), BRIGHT)


func _render_endings() -> void:
	# 结局栏必须先把存档里的解锁记录并进来，否则永远显示全灰。
	_book.adopt(_run.unlocked)
	PixelFont.draw(_body_root, "结局 · 学校", Vector2(16, 12), BRIGHT)
	var rows := _book.entries(ENDING_TEMPLATE)
	PixelFont.draw(_body_root, "已解锁 %d / %d" % [_book.unlocked_count(ENDING_TEMPLATE), _book.slot_count(ENDING_TEMPLATE)],
		Vector2(250, 12), INK)
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var y := 40 + index * 30
		_add_frame(Vector2(16, y - 4), Vector2(VIEW.x - 32, 26), DIM if bool(row["unlocked"]) else FRAME)
		var label := str(row["label"])
		PixelFont.draw(_item_root, label, Vector2(24, y), BRIGHT if bool(row["unlocked"]) else INK)
		PixelFont.draw(_body_root, str(row["summary"]), Vector2(24, y + 14), INK if bool(row["unlocked"]) else DIM)
	PixelFont.draw(_body_root, "Esc 返回", Vector2(16, 194), INK)


func _add_rect(at: Vector2, size: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = size
	rect.color = color
	_item_root.add_child(rect)


func _add_frame(at: Vector2, size: Vector2, color: Color) -> void:
	for rect: Array in [
		[at, Vector2(size.x, 1)], [at + Vector2(0, size.y - 1), Vector2(size.x, 1)],
		[at, Vector2(1, size.y)], [at + Vector2(size.x - 1, 0), Vector2(1, size.y)],
	]:
		_add_rect(rect[0], rect[1], color)


func _process(delta: float) -> void:
	if _message_frames > 0:
		_message_frames -= 1
		if _message_frames == 0:
			_message = ""
			_render()
	if delta > 0.0:
		pass


# ── 输入（供门禁直接调用的同时，也接受真按键）─────────────

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.is_echo() or not event.is_pressed():
		return
	if event.is_action_pressed("menu_back"):
		if _view == "endings":
			_view = "root"
			_render()
		get_viewport().set_input_as_handled()
		return
	if _view != "root":
		if event.is_action_pressed("menu_confirm"):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu_up"):
		move(-1)
	elif event.is_action_pressed("menu_down"):
		move(1)
	elif event.is_action_pressed("menu_confirm"):
		confirm()
	get_viewport().set_input_as_handled()


func move(delta: int) -> void:
	_index = wrapi(_index + delta, 0, ITEMS.size())
	_render()


func confirm() -> void:
	match _index:
		0:
			_run = RunState.start_new()
			_flash("新的一天。")
			_enter_game()
		1:
			var saved := RunState.load_saved()
			if saved == null:
				_flash("没有可继续的进度。")
			else:
				# 继续时把菜单持有的引用也换成读回来的那局，否则后续解锁会写到旧对象上。
				_run = saved
				RunState.current = saved
				_flash("从第 %d 天继续。" % (saved.day + 1))
				_enter_game()
		2:
			_view = "endings"
			_render()


## D14：菜单 → 走廊的真切换。
## 门禁/手动 add 的实例里 current_scene 不是自己（测试用 root.add_child），
## 这种情况下只让状态生效、不换场景，保证既有门禁可直接调 confirm() 做断言。
func _enter_game() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene != self:
		return
	tree.change_scene_to_file("res://game/scenes/corridor.tscn")


func _flash(text: String) -> void:
	_message = text
	_message_frames = 90
	_render()


func view_name() -> String:
	return _view


func current_index() -> int:
	return _index


func run_state() -> RunState:
	return _run


func ending_book() -> EndingBook:
	return _book
