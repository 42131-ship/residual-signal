class_name MobileSupport
extends RefCounted

## 手机支持的统一入口（2026-11-26）。
##
## 不用 autoload：`--script` 门禁里 autoload 不一定在，静态类永不缺席。
## 挂载点只有一处 —— 场景 `_ready()` 里调 `MobileSupport.attach(self)`；
## 不是手机就是一个 null，桌面与所有既有门禁的行为完全不变。
##
## RS_TOUCH=1 可在桌面强制开触摸层（做手感调试用，不需要真机）。

const TOUCH_ENV := "RS_TOUCH"
const TOUCH_NODE := "TouchControls"
const LIFECYCLE_NODE := "MobileLifecycle"
const DESKTOP_FPS := 60


static func enabled() -> bool:
	if OS.has_environment(TOUCH_ENV) and OS.get_environment(TOUCH_ENV) == "1":
		return true
	if OS.has_feature("android") or OS.has_feature("ios"):
		return true
	return DisplayServer.is_touchscreen_available()


static func attach(host: Node) -> TouchControls:
	if host == null or not host.is_inside_tree():
		return null
	var existing := host.get_node_or_null(TOUCH_NODE)
	if existing is TouchControls:
		return existing as TouchControls
	if not enabled():
		return null
	apply_fill_screen(host)
	var layer := TouchControls.new()
	layer.name = TOUCH_NODE
	host.add_child(layer)
	if host.get_node_or_null(LIFECYCLE_NODE) == null:
		var lifecycle := Lifecycle.new()
		lifecycle.name = LIFECYCLE_NODE
		host.add_child(lifecycle)
	return layer


## 19.5:9 手机要「填满屏幕」：把内容缩放从 keep（左右黑边）改成 expand。
## expand 会把视口从 384×216 变成 555×256，所以触控层要按视口贴边（见 TouchControls）。
## 只在手机上调用：桌面与全部 384×216 门禁的呈现链路一个字节都不变。
##
## 现状态（2026-11-26 真机验证）：视口扩展与按钮贴边都成立，但**游戏内容仍按 384×216 绘制**，
## 结果是「内容靠左 + 右侧/底部留黑」。所以默认关闭，用 RS_EXPAND=1 打开做实验；
## 等内容层（菜单居中 / 背景铺满 555×256 / 走廊相机取景）重排完，再把默认值改成 true。
static func fill_screen_enabled() -> bool:
	# 默认跟随平台：真机（Android/iOS）填满屏幕；桌面保持 16:9 整数放大，门禁基线不变。
	# RS_EXPAND=0 强制关闭（排查对齐问题用），RS_EXPAND=1 可在桌面模拟。
	if OS.has_environment("RS_EXPAND"):
		return OS.get_environment("RS_EXPAND") == "1"
	return OS.has_feature("android") or OS.has_feature("ios")


static func apply_fill_screen(host: Node) -> void:
	if not fill_screen_enabled():
		return
	var win := host.get_window()
	if win == null:
		return
	# 不能用「expand + 整数缩放」：Godot 会把视口锁在 384×216 / 按高度算，
	# 结果 2772×1280 上只剩 467×216，左右各 218px 黑边（真机日志实证）。
	# 自己算：scale = floor(min(w/384, h/216))，视口 = ceil(窗口/scale)。
	# 于是视口变成 555×256（设计空间仍是 384×216，内容居中），
	# 纵向正好 5.0×、横向 4.995×（差 0.1%，肉眼不可见），屏幕填满不裁剪。
	var window_size := DisplayServer.window_get_size()
	var base := Vector2i(384, 216)
	var scale := maxi(1, mini(int(window_size.x / base.x), int(window_size.y / base.y)))
	var viewport := Vector2i(
		int(ceili(float(window_size.x) / float(scale))),
		int(ceili(float(window_size.y) / float(scale))))
	win.content_scale_size = viewport
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	# 分数缩放：视口已经等于「窗口/整数倍」，缩放比只差零点几个百分点，像素不糊。
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


## 手机生命周期：切后台把帧率压到 1（省电、别让 SoC 烤手），回前台恢复；
## 安卓返回键当 Esc 用（走廊里就是关面板 / 收起，不直接杀进程）。
class Lifecycle:
	extends Node

	var _fps := DESKTOP_FPS

	func _ready() -> void:
		if Engine.max_fps > 0:
			_fps = Engine.max_fps

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
				Engine.max_fps = 1
			NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
				Engine.max_fps = _fps
			NOTIFICATION_WM_GO_BACK_REQUEST:
				_back_as_escape()

	func _back_as_escape() -> void:
		for pressed: bool in [true, false]:
			var event := InputEventKey.new()
			event.physical_keycode = KEY_ESCAPE
			event.pressed = pressed
			Input.parse_input_event(event)
