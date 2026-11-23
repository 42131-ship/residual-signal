extends SceneTree
## 呈现门禁：玩家实际看到的是 1920×1080（原生 384×216 的 5× 整数最近邻放大）。
## 运行（需要真实窗口，不能 --headless）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --script res://game/tests/display.gd
## 通过输出一行 `DISPLAY_OK ...`，并生成两张呈现证据：
##   design/previews/DISPLAY_native_384x216.png   （原生帧）
##   design/previews/DISPLAY_1920x1080.png        （玩家实际看到的 5× 画面）

const NATIVE := Vector2i(384, 216)
const PRESENT := Vector2i(1920, 1080)
const SCALE := 5

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# ① 工程设置：原生 384×216、窗口 1920×1080、整数倍缩放、最近邻。
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == NATIVE.x, "viewport_width must be 384")
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_height")) == NATIVE.y, "viewport_height must be 216")
	_check(int(ProjectSettings.get_setting("display/window/size/window_width_override")) == PRESENT.x,
		"window_width_override must be 1920")
	_check(int(ProjectSettings.get_setting("display/window/size/window_height_override")) == PRESENT.y,
		"window_height_override must be 1080")
	_check(str(ProjectSettings.get_setting("display/window/stretch/mode")) == "viewport", "stretch mode must be viewport")
	_check(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep", "stretch aspect must be keep")
	_check(str(ProjectSettings.get_setting("display/window/stretch/scale_mode")) == "integer", "stretch scale_mode must be integer")
	_check(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")) == 0,
		"default texture filter must be nearest (0)")

	if not _failures.is_empty():
		_finish()
		return

	# ② 真实窗口：客户区必须是 1920×1080，且放大倍数是整数 5×。
	await process_frame
	var window_size := DisplayServer.window_get_size()
	_check(window_size == PRESENT, "window client size must be 1920x1080, got %s" % str(window_size))
	var factor := Vector2(window_size) / Vector2(NATIVE)
	_check(is_equal_approx(factor.x, float(SCALE)) and is_equal_approx(factor.y, float(SCALE)),
		"presentation scale must be exactly 5x, got %.2fx%.2f" % [factor.x, factor.y])

	# ③ 证据：原生帧 + 玩家实际看到的 5× 最近邻放大帧。
	await RenderingServer.frame_post_draw
	var native_image := root.get_texture().get_image()
	if native_image == null or native_image.get_size() != NATIVE:
		_check(false, "native frame is not 384x216")
		_finish()
		return
	_save(native_image, "res://design/previews/DISPLAY_native_384x216.png")
	var presented := native_image.duplicate()
	presented.resize(PRESENT.x, PRESENT.y, Image.INTERPOLATE_NEAREST)
	_save(presented, "res://design/previews/DISPLAY_1920x1080.png")
	_finish()


func _save(image: Image, path: String) -> void:
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		_check(false, "could not save " + path)
		return
	print("DISPLAY_SHOT %s  %s" % [path, str(image.get_size())])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("DISPLAY_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("DISPLAY_OK native=384x216 present=1920x1080 scale=5x stretch=viewport/integer/keep filter=nearest")
		quit(0)
		return
	print("DISPLAY_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
