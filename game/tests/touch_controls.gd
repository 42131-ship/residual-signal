extends SceneTree
## 手机触摸层门禁（2026-11-26）。headless 可跑：
##   .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://game/tests/touch_controls.gd
## 通过输出一行 `TOUCH_OK ...`。
##
## 这里守的是**可回归的契约**，不是「真机点得准不准」（那是引擎 TouchScreenButton 的事）：
##   ① 布局：每颗按钮都在 384×216 内、不压左侧 HUD、彼此不重叠
##   ② 安全区：给一个收窄的安全矩形，所有按钮必须挪回里面（刘海/挖孔）
##   ③ 按住 = 动作状态（走路/潜行/疾跑），松开就掉
##   ④ 点按 = 合成事件 + 一次性动作；键码必须与走廊/菜单真实绑定的键一致（改名/换键就红）
##   ⑤ 触摸层引用的每个动作，走廊或菜单里真的有对应注册

const VIEW := Vector2i(384, 216)
const HUD_ZONE := Rect2i(0, 0, 130, 140)
const CORRIDOR := "res://game/scenes/corridor.gd"
const MENU := "res://game/scenes/main_menu.gd"
const KEY_NAMES := {
	"KEY_A": KEY_A, "KEY_D": KEY_D, "KEY_W": KEY_W, "KEY_S": KEY_S,
	"KEY_E": KEY_E, "KEY_V": KEY_V, "KEY_F": KEY_F, "KEY_R": KEY_R,
	"KEY_TAB": KEY_TAB, "KEY_ESCAPE": KEY_ESCAPE,
	"KEY_UP": KEY_UP, "KEY_DOWN": KEY_DOWN, "KEY_LEFT": KEY_LEFT, "KEY_RIGHT": KEY_RIGHT,
}

var _failures: Array[String] = []
var _layer: TouchControls


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_layer = TouchControls.new()
	_layer.name = "TouchControls"
	root.add_child(_layer)
	await process_frame

	var specs: Array = TouchControls.SPECS
	_check(_layer.button_ids().size() == specs.size(),
		"button count %d != specs %d" % [_layer.button_ids().size(), specs.size()])

	# ① 布局
	for raw: Dictionary in specs:
		var id := String(raw["id"])
		var rect := _layer.button_rect(id)
		_check(rect.size != Vector2.ZERO, "%s has no hit shape" % id)
		_check(rect.position.x >= 0.0 and rect.position.y >= 0.0
				and rect.end.x <= float(VIEW.x) and rect.end.y <= float(VIEW.y),
			"%s outside 384x216: %s" % [id, str(rect)])
		_check(not rect.intersects(Rect2(HUD_ZONE)),
			"%s covers HUD zone: %s" % [id, str(rect)])
	var ids := _layer.button_ids()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a := _layer.button_rect(String(ids[i]))
			var b := _layer.button_rect(String(ids[j]))
			_check(not a.intersects(b), "%s overlaps %s" % [ids[i], ids[j]])

	# ② 安全区：左右各收 20（横屏刘海）
	_layer._set_safe_rect(Rect2(20, 0, VIEW.x - 40, VIEW.y))
	var safe := Rect2(20, 0, VIEW.x - 40, VIEW.y)
	for raw: Dictionary in specs:
		var id := String(raw["id"])
		var rect := _layer.button_rect(id)
		_check(safe.encloses(rect), "%s still outside safe area: %s" % [id, str(rect)])
	_layer._set_safe_rect(Rect2(0, 0, VIEW.x, VIEW.y))

	_bind_actions(specs)

	# ③ 按住 = 动作状态
	_layer.press("right")
	_check(Input.is_action_pressed("move_right"), "press right did not hold move_right")
	_check(_layer.last_key == KEY_D, "right should synthesise KEY_D, got %d" % _layer.last_key)
	_layer.release("right")
	_check(not Input.is_action_pressed("move_right"), "release right left move_right stuck")

	# ④ 步态循环：走 → 跑 → 蹲 → 走
	_check(_layer.gait_index() == 0, "gait should start at walk")
	_layer.press("gait")
	_check(Input.is_action_pressed("sprint"), "gait 1 must press sprint")
	_layer.press("gait")
	_check(Input.is_action_pressed("crouch") and not Input.is_action_pressed("sprint"),
		"gait 2 must be crouch only")
	_layer.press("gait")
	_check(not Input.is_action_pressed("crouch"), "gait 3 must return to walk")

	# ⑤ 点按：灯 / 交互 / 攻击
	_layer.press("light")
	_check(_layer.last_emitted == "light", "light not emitted")
	_check(_layer.last_key == KEY_F, "light should synthesise KEY_F, got %d" % _layer.last_key)
	_layer.press("pickup")
	_check(_layer.last_key == KEY_E, "pickup should synthesise KEY_E, got %d" % _layer.last_key)
	_layer.press("attack")
	_check(_layer.last_mouse, "attack should synthesise a left mouse press")

	# ⑥ 键码与走廊 / 菜单的真实绑定一致
	_check_keys_match(specs)
	_check_actions_registered(specs)

	_finish()


func _bind_actions(specs: Array) -> void:
	for raw: Dictionary in specs:
		var action := String(raw.get("action", ""))
		if action.is_empty():
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(StringName(action))
	# 步态按钮压的是这两个（不在按钮表里直接出现）
	for action: String in ["sprint", "crouch"]:
		if not InputMap.has_action(action):
			InputMap.add_action(StringName(action))


## 触摸层合成的键码，必须就是游戏里给这个动作绑的那个键（改键就红）。
func _check_keys_match(specs: Array) -> void:
	var corridor := FileAccess.get_file_as_string(CORRIDOR)
	var menu := FileAccess.get_file_as_string(MENU)
	for raw: Dictionary in specs:
		var action := String(raw.get("action", ""))
		var key := int(raw.get("key", -1))
		if action.is_empty() or key < 0:
			continue
		if action == "attack":
			continue
		var expected := _bound_key(corridor, action)
		if expected == -1:
			expected = _bound_key(menu, action)
		_check(expected == key,
			"%s: touch key %d != game binding %d" % [action, key, expected])


## 拿取第一个键名（正则取最长 token：直接 find("KEY_D") 会命中 KEY_DOWN 里的 KEY_D）。
func _bound_key(source: String, action: String) -> int:
	var needle := "_add_action(\"%s\", [" % action
	var at := source.find(needle)
	if at < 0:
		return -1
	var line_end := source.find("]", at)
	if line_end < 0:
		return -1
	var snippet := source.substr(at, line_end - at)
	var regex := RegEx.new()
	regex.compile("KEY_[A-Z0-9_]+")
	var found := regex.search(snippet)
	if found == null:
		return -1
	var token := found.get_string()
	return int(KEY_NAMES.get(token, -1))


func _check_actions_registered(specs: Array) -> void:
	var corridor := FileAccess.get_file_as_string(CORRIDOR)
	var menu := FileAccess.get_file_as_string(MENU)
	for raw: Dictionary in specs:
		var action := String(raw.get("action", ""))
		if action.is_empty():
			continue
		var ok := corridor.find("_add_action(\"%s\"" % action) >= 0 \
			or corridor.find("_add_mouse_action(\"%s\"" % action) >= 0 \
			or menu.find("_add_key(\"%s\"" % action) >= 0 \
			or menu.find("InputMap.add_action(action)") >= 0 and action.begins_with("menu_")
		_check(ok, "action %s is not registered by corridor.gd / main_menu.gd" % action)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("TOUCH_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("TOUCH_OK buttons=%d layout=in_bounds hud=clear safe_area=clamped hold=state tap=event keys=matched" % _layer.button_ids().size())
		quit(0)
		return
	print("TOUCH_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
