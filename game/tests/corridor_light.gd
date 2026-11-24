extends SceneTree
## 手电筒方向门禁：朝左走时光锥必须朝左，灯位也要镜像。
## 这是用户报的 bug（朝左走、光朝右射）——曾经 cone_dir 参数从没被写过。
## 运行（要渲染）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/corridor_light.gd -- LIGHT

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _prefix := "LIGHT"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("LIGHT"):
			_prefix = argument
	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	await process_frame
	await process_frame

	var material: ShaderMaterial = _corridor._light_material
	var actor := _corridor.get_node_or_null("Player") as Player
	_check(material != null, "flashlight material missing")
	_check(actor != null, "player missing")
	if material == null or actor == null:
		return _finish()

	# ① 朝右：光锥角度≈0，灯位在身体右边
	actor.facing_x = 1.0
	for _i in range(12):
		_corridor._update_flashlight()
	var right_angle := float(material.get_shader_parameter("cone_dir"))
	_check(absf(right_angle) < 0.02, "facing right must aim the cone at 0 rad, got %.3f" % right_angle)
	var right_pos: Vector2 = material.get_shader_parameter("light_pos_px")
	var right_origin := actor.get_global_transform_with_canvas().origin
	_check(right_pos.x > right_origin.x, "facing right must put the lamp right of the body")

	# ② 朝左：光锥必须翻到 PI，灯位翻到左边（这就是用户看到的那条 bug）
	actor.facing_x = -1.0
	for _i in range(24):
		_corridor._update_flashlight()
	var left_angle := float(material.get_shader_parameter("cone_dir"))
	_check(absf(_angle_delta(left_angle, PI)) < 0.05,
		"facing left must aim the cone at PI, got %.3f" % left_angle)
	var left_pos: Vector2 = material.get_shader_parameter("light_pos_px")
	var left_origin := actor.get_global_transform_with_canvas().origin
	_check(left_pos.x < left_origin.x, "facing left must put the lamp left of the body")

	# ③ 用真实输入再走一遍：按 A 之后朝向与光锥都要朝左
	Input.action_press("move_left")
	await physics_frame
	await physics_frame
	await process_frame
	Input.action_release("move_left")
	actor.velocity = Vector2.ZERO
	for _i in range(24):
		_corridor._update_flashlight()
	var input_angle := float(material.get_shader_parameter("cone_dir"))
	_check(actor.facing_x < 0.0, "holding A must flip the player facing")
	_check(absf(_angle_delta(input_angle, PI)) < 0.05,
		"holding A must aim the cone left, got %.3f" % input_angle)

	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	if shot != null:
		shot.save_png(ProjectSettings.globalize_path("res://design/previews/%s_left.png" % _prefix))
		print("LIGHT_SHOT res://design/previews/%s_left.png" % _prefix)
	_finish()


## 最短夹角（-PI..PI）：-PI 与 PI 指向同一方向，比较方向必须用它。
func _angle_delta(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("LIGHT_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CORRIDOR_LIGHT_OK right=0rad left=PI lamp=mirrored input=A")
		quit(0)
		return
	print("CORRIDOR_LIGHT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
