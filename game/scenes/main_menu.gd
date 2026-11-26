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

const ITEMS := ["新游戏", "继续", "结局栏", "设置"]
const ENDING_TEMPLATE := "school"
const BG_PATH := "res://art/generated_candidates/maps/menu_bg.png"
## 背景是生图量化来的，压一层暗罩保证文字对比度（这是 UI 罩层，不是资产，允许半透明）。
const SCRIM := Color(0.043, 0.067, 0.098, 0.55)

var _index := 0
var _view := "root"          # root / endings / settings / consent
var _message := ""
var _message_frames := 0
## TapDB 首次启动同意界面：导出构建且未决策时才出现；编辑器/门禁不弹。
## 菜单与走廊共用同一个 RunState（静态引用），否则「新游戏」会丢掉结局档案。
var _run: RunState = RunState.ensure()
var _book := EndingBook.new()
var _item_root: Node2D
var _body_root: Node2D
## 手机触摸层（null = 桌面）。见 design/MOBILE.md
var _mobile: TouchControls


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 手游：先切到 expand（画布 555x256）并等一帧让视口生效，再按画布搭界面。
	# 反过来的话界面会按 384x216 搭好、再扩画布，右边会留一块黑。
	MobileSupport.apply_fill_screen(self)
	if MobileSupport.fill_screen_enabled():
		await get_tree().process_frame
	_ensure_actions()
	_build_chrome()
	_item_root = _node("Items")
	_body_root = _node("Body")
	# 手游：内容在更大的画布里居中（桌面/门禁下 origin 恒为 (0,0)，不引入任何偏移）。
	var origin := ScreenLayout.origin_of(self)
	_item_root.position = Vector2(origin)
	_body_root.position = Vector2(origin)
	if not _book.load_template(ENDING_TEMPLATE):
		push_error("ENDING_BOOK_FAILED: " + _book.load_error())
	# TapDB 合规：同意前不初始化收集；首次启动先让玩家选。
	if Analytics.should_prompt_consent():
		_view = "consent"
		_index = 0
	# 手机：菜单同样要能点。触摸层只补「上/下/确认/返回」四个键的事件（见 design/MOBILE.md）。
	_mobile = MobileSupport.attach(self)
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
	var canvas := ScreenLayout.canvas_of(self)
	var origin := ScreenLayout.origin_of(self)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BG
	background.size = Vector2(canvas)
	add_child(background)

	# 生图背景（若已量化入库）。手机 expand 后画布更大：等比拉伸铺满，仍然最近邻
	# （像素不糊，只是格子变粗一点），不再留左右黑边。
	var texture := load(BG_PATH) as Texture2D
	if texture != null:
		var art := Sprite2D.new()
		art.name = "KeyArt"
		art.texture = texture
		art.centered = false
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var tex_size := texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			art.scale = Vector2(float(canvas.x) / tex_size.x, float(canvas.y) / tex_size.y)
		add_child(art)
		var scrim := ColorRect.new()
		scrim.name = "Scrim"
		scrim.color = SCRIM
		scrim.size = Vector2(canvas)
		add_child(scrim)

	# 底部一条暗带 + 顶部一条细线：给标题和菜单分层次，不靠渐变。
	var band := ColorRect.new()
	band.name = "Band"
	band.color = Color(0.067, 0.102, 0.149, 0.85)
	band.position = Vector2(0, origin.y + 150)
	band.size = Vector2(canvas.x, 66)
	add_child(band)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = FRAME
	rule.position = Vector2(origin.x + 16, origin.y + 44)
	rule.size = Vector2(VIEW.x - 32, 1)
	add_child(rule)


## 输入提示统一走 InputHints：桌面是键鼠文案，手机是空/触屏文案（空就不画）。
func _draw_hint(key: String, at: Vector2, color: Color) -> void:
	var text := InputHints.get_hint(key)
	if not text.is_empty():
		PixelFont.draw(_body_root, text, at, color)


func _clear(root: Node2D) -> void:
	for child: Node in root.get_children():
		child.queue_free()


func _render() -> void:
	_clear(_item_root)
	_clear(_body_root)
	if _view == "endings":
		_render_endings()
		return
	if _view == "settings":
		_render_settings()
		return
	if _view == "consent":
		_render_consent()
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
	_draw_hint("menu_list", Vector2(16, 158), INK)
	PixelFont.draw(_body_root, "第 %d / %d 天 · 沉积 %d" % [_run.day + 1, RunState.MAX_DAY, _run.sediment],
		Vector2(16, 176), DIM)
	if _message_frames > 0:
		PixelFont.draw(_body_root, _message, Vector2(16, 194), BRIGHT)


func _render_settings() -> void:
	PixelFont.draw(_body_root, "设置 · 隐私", Vector2(16, 12), BRIGHT)
	var status := "开启" if Analytics.has_consent() else "关闭"
	var state_text := "分析数据：%s" % status
	if not Analytics.is_available():
		state_text += "（未配置）"
	PixelFont.draw(_body_root, state_text, Vector2(16, 44), BRIGHT)
	var y := 70.0
	for line: String in Analytics.privacy_lines():
		y = _draw_wrapped(_body_root, line, Vector2(16, y), INK, 25, 14.0)
	_draw_hint("menu_toggle", Vector2(16, 194), INK)


func _render_consent() -> void:
	PixelFont.draw(_body_root, "隐私与数据", Vector2(16, 12), BRIGHT)
	var y := 40.0
	for line: String in Analytics.privacy_lines():
		y = _draw_wrapped(_body_root, line, Vector2(16, y), INK, 25, 14.0)
	var options := ["允许并继续", "不允许"]
	for index in range(options.size()):
		var option_y := 154 + index * 20
		if index == _index:
			_add_rect(Vector2(12, option_y - 4), Vector2(160, 18), DIM)
		PixelFont.draw(_item_root, options[index], Vector2(20, option_y),
			BRIGHT if index == _index else INK)
	_draw_hint("menu_list", Vector2(16, 194), INK)


## 按固定字宽折行（中文等宽，简单可靠；不做词边界）。
func _draw_wrapped(canvas: Node2D, text: String, at: Vector2, color: Color,
		max_chars: int, line_height: float) -> float:
	var line := ""
	var y := at.y
	for index in range(text.length()):
		line += text[index]
		if line.length() >= max_chars or index == text.length() - 1:
			PixelFont.draw(canvas, line, Vector2(at.x, y), color)
			line = ""
			y += line_height
	return y


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
	_draw_hint("menu_back", Vector2(16, 194), INK)


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
		if _view != "root":
			# 同意界面按 Esc 视为「这次先不选」：不收集，下次启动再问。
			_view = "root"
			_index = 0
			_render()
		get_viewport().set_input_as_handled()
		return
	if _view == "consent":
		if event.is_action_pressed("menu_up"):
			move(-1)
		elif event.is_action_pressed("menu_down"):
			move(1)
		elif event.is_action_pressed("menu_confirm"):
			confirm()
		get_viewport().set_input_as_handled()
		return
	if _view == "settings":
		if event.is_action_pressed("menu_confirm"):
			if Analytics.has_consent():
				Analytics.revoke_consent()
			else:
				Analytics.grant_consent()
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
	if _view == "consent":
		_index = clampi(_index + delta, 0, 1)
		_render()
		return
	_index = wrapi(_index + delta, 0, ITEMS.size())
	_render()


func confirm() -> void:
	if _view == "consent":
		if _index == 0:
			Analytics.grant_consent()
		else:
			Analytics.revoke_consent()
		_view = "root"
		_index = 0
		_render()
		return
	if _view == "settings":
		if Analytics.has_consent():
			Analytics.revoke_consent()
		else:
			Analytics.grant_consent()
		_render()
		return
	if _view != "root":
		return
	match _index:
		0:
			_run = RunState.start_new()
			Analytics.track("run_start", {"mode": "story", "from_save": 0, "day": 0})
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
				Analytics.track("run_start", {"mode": "story", "from_save": 1, "day": int(saved.day)})
				_flash("从第 %d 天继续。" % (saved.day + 1))
				_enter_game()
		2:
			Analytics.track("endings_view", {"unlocked": _book.unlocked_count(ENDING_TEMPLATE)})
			_view = "endings"
			_render()
		3:
			_view = "settings"
			_index = 0
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
