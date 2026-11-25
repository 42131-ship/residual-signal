extends SceneTree
## D7 门禁：五楼主题——每栋楼有自己的 tile 表、道具场景、环境亮度与专属标志物。
## 覆盖：主题 id / tileset 尺寸与色集互异 / 道具场景按楼替换 / 专属标志物存在 /
##       环境亮度按楼不同 / 开局灯光已按主题初始化 / 截图存证。
## 运行（要渲染）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/building_theme.gd -- THEME

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const IDS: Array[String] = ["school", "gas_station", "hospital", "fire_station", "military_base"]
const AMBIENT := {
	"school": 1.0, "gas_station": 1.1, "hospital": 0.95,
	"fire_station": 0.88, "military_base": 0.8,
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sheets := {}
	var ambients := {}
	var sheet_colors := {}
	for building: String in IDS:
		RunState.current = null
		var run := RunState.start_new()
		run.building = building
		run.visited = [building]
		run.fuel = 3
		var corridor := SCENE.instantiate() as Node2D
		root.add_child(corridor)
		await process_frame
		await process_frame

		_check(corridor.theme_id() == building,
			"theme id must follow building: expected %s got %s" % [building, corridor.theme_id()])
		var sheet: Texture2D = corridor.theme_tileset()
		_check(sheet != null, "%s: tileset missing" % building)
		if sheet == null:
			corridor.queue_free()
			await process_frame
			continue
		var path := str(sheet.resource_path)
		_check(path.contains(building) or building == "school",
			"%s: tileset path must reference the building, got %s" % [building, path])
		_check(sheet.get_width() == 128 and sheet.get_height() in [16, 32],
			"%s: tileset must be 8 tiles wide (128 x 16/32), got %s" % [building, str(sheet.get_size())])
		sheets[building] = path
		ambients[building] = float(corridor.theme_ambient())
		_check(absf(float(AMBIENT[building]) - float(ambients[building])) < 0.001,
			"%s: ambient expected %.2f got %.2f" % [building, AMBIENT[building], ambients[building]])

		# 开局灯光已按 主题环境 × 区块档 初始化（A 区档 1.15）
		var light_factor: float = float(corridor.room_light_factor())
		_check(absf(light_factor - 1.15 * float(AMBIENT[building])) < 0.02,
			"%s: initial room light must include theme ambient, got %.3f" % [building, light_factor])

		# 色集：tile 表按楼不同
		var image: Image = sheet.get_image()
		var colors := {}
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var c: Color = image.get_pixel(x, y)
				colors[c.to_html(false)] = true
		sheet_colors[building] = colors
		var expected_props := 15 if building == "school" else 19
		var props := corridor.get_node_or_null("Props")
		_check(props != null, "%s: Props node missing" % building)
		if props != null:
			_check(props.get_child_count() == expected_props,
				"%s: props scene must mount %d sprites, got %d" % [building, expected_props, props.get_child_count()])
			if building != "school":
				var theme_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
					"res://data/buildings/%s.json" % building))
				var signatures: Array = (theme_doc as Dictionary).get("signature", []) if theme_doc is Dictionary else []
				_check(signatures.size() == 4, "%s: theme must declare 4 signature props" % building)
				for signature: Variant in signatures:
					var id := str((signature as Dictionary).get("id", ""))
					var node := props.get_node_or_null(NodePath(id)) as Sprite2D
					_check(node != null, "%s: signature prop %s missing" % [building, id])
					if node != null:
						_check(node.has_meta("decor"), "%s: signature %s must be decor (non-inspectable)" % [building, id])
				# 主题换色确实生效：道具纹理路径指向该楼主题目录
				var sample := props.get_child(0) as Sprite2D
				if sample != null and sample.texture != null:
					_check(str(sample.texture.resource_path).contains("/themes/%s/" % building),
						"%s: themed prop texture path wrong: %s" % [building, sample.texture.resource_path])

		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		if shot != null:
			shot.save_png(ProjectSettings.globalize_path("res://design/previews/THEME_%s.png" % building))
		else:
			_check(false, "%s: screenshot failed" % building)
		corridor.queue_free()
		await process_frame

	# 五套主题必须互不相同
	var paths := {}
	for building: String in sheets:
		paths[sheets[building]] = true
	_check(paths.size() == IDS.size(), "five buildings must use five distinct tilesets, got %d" % paths.size())
	var color_keys := {}
	for building: String in sheet_colors:
		var key := str((sheet_colors[building] as Dictionary).keys())
		color_keys[key] = true
	_check(color_keys.size() == IDS.size(), "five buildings must use five distinct tile color sets, got %d" % color_keys.size())
	_check(ambients.size() == IDS.size(), "ambient map incomplete")

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("THEME_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("BUILDING_THEME_OK buildings=5 sheets=5 distinct props=76 signature=16 ambient=per_building")
		quit(0)
		return
	print("BUILDING_THEME_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
