extends SceneTree
## 手机触摸层布局截图（需要真实窗口，**不能** --headless）。
##   $env:RS_TOUCH='1'
##   .tools/Godot_v4.7.2-stable_win64_console.exe --path . --script res://game/tests/touch_layout_shot.gd
## 产出 design/previews/MOBILE_corridor_touch.png（走廊 + 触摸层，玩家实际看到的构图）。

const SHOT := "res://design/previews/MOBILE_corridor_touch.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("RS_TOUCH", "1")
	var packed: PackedScene = load("res://game/scenes/corridor.tscn")
	if packed == null:
		print("TOUCH_SHOT_FAILED corridor.tscn missing")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _i in range(4):
		await process_frame
	var layer := scene.get_node_or_null("TouchControls")
	if layer == null:
		print("TOUCH_SHOT_FAILED touch layer not attached")
		quit(1)
		return
	if OS.has_environment("RS_TOUCH") and OS.get_environment("RS_TOUCH") == "1":
		pass
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		print("TOUCH_SHOT_FAILED no frame")
		quit(1)
		return
	var saved := image.save_png(ProjectSettings.globalize_path(SHOT))
	print("TOUCH_SHOT %s %s status=%d" % [SHOT, str(image.get_size()), saved])
	quit(0)
