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

	# ② 真实窗口：桌面够大时必须是 1920×1080 / 5×；
	#    桌面放不下（笔记本、缩放、虚拟机）时按桌面能给的**整数倍**降级，
	#    但「整数倍 + 方形像素 + 原生 384×216」这三条不许破。
	#    之前用窗口尺寸 ÷ 384 反推倍数，桌面一小就误判（1370/384=3.57x3.47）。
	await process_frame
	await process_frame
	var window_size := DisplayServer.window_get_size()
	var screen := DisplayServer.screen_get_size()
	var scale := root.get_final_transform().get_scale()
	_check(scale.x >= 1.0 and is_equal_approx(scale.x, floorf(scale.x)),
		"horizontal upscale must be an integer, got %.3f" % scale.x)
	_check(scale.y >= 1.0 and is_equal_approx(scale.y, floorf(scale.y)),
		"vertical upscale must be an integer, got %.3f" % scale.y)
	_check(is_equal_approx(scale.x, scale.y),
		"pixel aspect must stay square, got %.3fx%.3f" % [scale.x, scale.y])
	if screen.x >= PRESENT.x and screen.y >= PRESENT.y:
		_check(window_size == PRESENT, "window client size must be 1920x1080, got %s" % str(window_size))
		_check(is_equal_approx(scale.x, float(SCALE)),
			"reference desktop must present at exactly 5x, got %.2f" % scale.x)
	else:
		print("DISPLAY_DOWNSCALED desktop=%s window=%s scale=%s" % [str(screen), str(window_size), str(scale)])

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
		print("DISPLAY_OK native=384x216 target=1920x1080 actual=%.0fx stretch=viewport/integer/keep filter=nearest" % root.get_final_transform().get_scale().x)
		quit(0)
		return
	print("DISPLAY_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
