extends SceneTree
## HUD 对比度取色证据（需要真实窗口，不能 --headless）。
## 画出与走廊 HUD 同一条代码路径的两行字（#e8e4d8 + 1px #0b1119 描边），存 PNG。
## 之后由 tools/contrast_sample.py 从 PNG 里取色算 WCAG 比值（验收 C 的「取色器实测」）。

const VIEW := Vector2i(384, 216)
const SHOT := "res://design/previews/MOBILE_hud_contrast.png"
const BG := Color("#0b1119")
const WALL := Color("#111a26")
const INK := Color("#e8e4d8")
const OUTLINE := Color("#0b1119")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root2d := Node2D.new()
	root.add_child(root2d)
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = BG
	bg.size = Vector2(VIEW)
	root2d.add_child(bg)
	# 上半：纯视野黑（#0b1119）；下半：墙面色（#111a26）——两种暗底各测一次
	var wall := ColorRect.new()
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall.color = WALL
	wall.position = Vector2(0, VIEW.y / 2)
	wall.size = Vector2(VIEW.x, VIEW.y / 2)
	root2d.add_child(wall)

	_draw_outlined(root2d, "物资 80", Vector2(8, 30))
	_draw_outlined(root2d, "体力 30", Vector2(8, 48))
	_draw_outlined(root2d, "物资 80", Vector2(8, 130))
	_draw_outlined(root2d, "体力 30", Vector2(8, 148))
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		print("CONTRAST_SHOT_FAILED")
		quit(1)
		return
	image.save_png(ProjectSettings.globalize_path(SHOT))
	print("CONTRAST_SHOT %s %s" % [SHOT, str(image.get_size())])
	quit(0)


func _draw_outlined(parent: Node, text: String, at: Vector2) -> void:
	for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		PixelFont.draw(parent, text, at + offset, OUTLINE)
	PixelFont.draw(parent, text, at, INK)
