extends SceneTree
## 校园图门禁：学校模板的整张地图必须可读、可判、可截图。
## 覆盖：schema / 区块数 / id 唯一 / 每块都在画布内 / 建筑都有层数与入口 / 主干道 /
##       叙事 route 覆盖全部可玩区块 / 开场四拍顺序（铃 → 鸟瞰 → 厕所 → 报警 → 聚焦）/ 截图。
## 运行（要渲染，出图存 design/previews）：
##   .tools\Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/campus_map.gd -- CAMPUS
## 通过输出一行 `CAMPUS_MAP_OK ...`。

const CAMPUS_ID := "school"
## 新脚本的 class_name 不在 .godot 缓存里时会报「未声明类型」，所以这里 preload 拿脚本本体。
const MAP_SCRIPT := preload("res://game/ui/campus_map.gd")
## 排好的叙事拍子：顺序错一个，开场就不是「铃—鸟瞰—厕所—报警—聚焦—走出厕所」了。
const BEAT_ORDER: Array[String] = ["bell", "overview", "toilet", "alarm", "zoom", "walkout"]
## 地图上必须存在的区块（少一块就不算「整张校园」）。
const REQUIRED: Array[String] = [
	"main_building", "west_wing", "grandstand", "track_field", "plaza",
	"dorm", "canteen", "corner_building", "gate", "parking",
]

var _map
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_map = MAP_SCRIPT.new()
	_map.name = "CampusMap"
	root.add_child(_map)
	_check(_map.load_for(CAMPUS_ID), "campus map failed to load: %s" % _map.load_error)
	if _map.data.is_empty():
		_finish()
		return

	var canvas: Vector2 = _map.map_size()
	_check(canvas == Vector2(384, 216), "campus canvas must be 384x216, got %s" % str(canvas))

	var regions: Array = _map.regions()
	_check(regions.size() >= REQUIRED.size(),
		"campus needs at least %d regions, got %d" % [REQUIRED.size(), regions.size()])

	var seen := {}
	var ids: Array[String] = []
	for row: Variant in regions:
		if not row is Dictionary:
			_check(false, "region entry is not an object")
			continue
		var region: Dictionary = row as Dictionary
		var region_id := str(region.get("id", ""))
		ids.append(region_id)
		_check(not region_id.is_empty(), "region without id")
		_check(not seen.has(region_id), "duplicated region id: %s" % region_id)
		seen[region_id] = true
		var rect: Rect2 = _rect_of(region.get("rect", []))
		_check(rect.size.x > 0.0 and rect.size.y > 0.0, "%s: empty rect" % region_id)
		_check(Rect2(Vector2.ZERO, canvas).encloses(rect), "%s: rect outside canvas %s" % [region_id, str(rect)])
		_check(not str(region.get("story", "")).is_empty(), "%s: region needs a story line" % region_id)
		if str(region.get("kind", "")) == "building":
			_check(int(region.get("floors", 0)) >= 1, "%s: building needs floors >= 1" % region_id)
			var entrance: Variant = region.get("entrance", null)
			_check(entrance is Array and (entrance as Array).size() == 2,
				"%s: building needs an entrance point" % region_id)
			if entrance is Array and (entrance as Array).size() == 2:
				var at := Vector2(float((entrance as Array)[0]), float((entrance as Array)[1]))
				# 入口必须在楼体周围 8px 内（贴着门，而不是画在操场另一头）。
				var near := rect.grow(8.0).has_point(at)
				_check(near, "%s: entrance %s is not on the building edge" % [region_id, str(at)])

	for required: String in REQUIRED:
		_check(seen.has(required), "campus is missing region: " + required)

	var roads: Array = _map.data.get("roads", [])
	_check(roads.size() >= 2, "campus needs at least 2 roads, got %d" % roads.size())
	var trees: Array = _map.data.get("trees", [])
	_check(trees.size() >= 8, "campus needs tree cover, got %d" % trees.size())

	# 叙事顺序：route 必须按顺序覆盖每一个可玩区块（内部有 interior 的楼 + 看台）。
	var route: Array = _map.data.get("route", [])
	_check(route.size() >= 6, "route must walk at least 6 regions, got %d" % route.size())
	for stop: Variant in route:
		_check(seen.has(str(stop)), "route references unknown region: %s" % str(stop))
	for region_id: String in ids:
		var region: Dictionary = _map.region_of(region_id)
		if region.get("interior") is Dictionary:
			_check(route.has(region_id), "%s has an interior but is not on the route" % region_id)

	# 开场四拍：id 顺序固定，拍长 > 0，且必须带旁白。
	var beats: Array = _map.data.get("intro", {}).get("beats", [])
	_check(beats.size() == BEAT_ORDER.size(),
		"intro needs %d beats, got %d" % [BEAT_ORDER.size(), beats.size()])
	for index in mini(beats.size(), BEAT_ORDER.size()):
		var beat: Dictionary = beats[index] as Dictionary
		_check(str(beat.get("id", "")) == BEAT_ORDER[index],
			"beat %d must be %s, got %s" % [index, BEAT_ORDER[index], str(beat.get("id", ""))])
		_check(float(beat.get("seconds", 0.0)) > 0.0, "%s: beat needs duration" % BEAT_ORDER[index])
		_check(not (beat.get("lines", []) as Array).is_empty(), "%s: beat needs narration" % BEAT_ORDER[index])
	_check(_map.beat_ids() == BEAT_ORDER, "beat ids must match the intro order")

	# 敌人与容器：数量按区块分布，不允许只堆在一个区块里。
	var slots: Array = _map.data.get("enemy_slots", [])
	_check(slots.size() >= 4, "enemy slots must spread over >= 4 regions, got %d" % slots.size())
	var total_enemies := 0
	for row: Variant in slots:
		var slot: Dictionary = row as Dictionary
		_check(seen.has(str(slot.get("region", ""))),
			"enemy slot on unknown region: %s" % str(slot.get("region", "")))
		total_enemies += int(slot.get("count", 0))
	_check(total_enemies >= 10, "school should hold at least 10 enemies across the map, got %d" % total_enemies)
	var safehouse := str(_map.data.get("safehouse", ""))
	_check(seen.has(safehouse), "safehouse must be a region: " + safehouse)
	_check(not route.is_empty() and str(route[0]) == safehouse,
		"the route must start at the safehouse (%s), got %s" % [safehouse, str(route[0]) if not route.is_empty() else ""])

	await process_frame
	await process_frame
	# 字图集自检：.godot 里的旧 ctex 会让 region 指错格子，字画成隔壁格子的字（本轮踩过，
	# 「宿舍」被画成一个黑框）。这里直接对尺寸 + 逐字出图数，别指望肉眼发现。
	_check_atlas_matches_json()
	await _capture()
	_finish()


## 图集尺寸必须与磁盘上的 PNG 一致，且每个地图标签都能真的画出字来。
func _check_atlas_matches_json() -> void:
	var tex: Texture2D = PixelFont._cjk_tex
	_check(tex != null, "CJK atlas texture is missing")
	if tex == null:
		return
	var on_disk := Image.load_from_file(ProjectSettings.globalize_path(PixelFont.CJK_ATLAS_PATH))
	_check(on_disk != null, "CJK atlas png is unreadable")
	if on_disk != null:
		_check(tex.get_size() == Vector2(on_disk.get_size()),
			"stale atlas import: texture %s vs png %s (delete .godot/imported/PF-02_cjk_12* and reimport)"
			% [str(tex.get_size()), str(on_disk.get_size())])
	var holder := Node2D.new()
	root.add_child(holder)
	for row: Variant in _map.regions():
		if not row is Dictionary:
			continue
		var region: Dictionary = row as Dictionary
		var text := str(region.get("map_label", ""))
		if text.is_empty():
			continue
		for index in text.length():
			var entry: Variant = PixelFont._cjk_map.get(text[index], {})
			_check(entry is Dictionary and int((entry as Dictionary).get("region", []).size()) == 4,
				"glyph missing for %s in map_label of %s" % [text[index], str(region.get("id", ""))])
		var drawn := PixelFont.draw(holder, text, Vector2.ZERO, Color.WHITE)
		_check(drawn == text.length(), "label %s drew %d/%d glyphs" % [text, drawn, text.length()])
	holder.queue_free()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		_check(false, "capture failed")
		return
	var path := "res://design/previews/CAMPUS_%s_map.png" % CAMPUS_ID
	if rendered.save_png(ProjectSettings.globalize_path(path)) != OK:
		_check(false, "could not save " + path)
		return
	print("CAMPUS_SHOT %s" % path)


func _rect_of(value: Variant) -> Rect2:
	if not value is Array or (value as Array).size() != 4:
		return Rect2()
	var items: Array = value as Array
	return Rect2(float(items[0]), float(items[1]), float(items[2]), float(items[3]))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("CAMPUS_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CAMPUS_MAP_OK id=%s regions=%d roads=%d beats=%d enemies=%d size=384x216" % [
			CAMPUS_ID, _map.regions().size(),
			(_map.data.get("roads", []) as Array).size(),
			(_map.data.get("intro", {}).get("beats", []) as Array).size(),
			_total_enemies()])
		quit(0)
		return
	print("CAMPUS_MAP_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)


func _total_enemies() -> int:
	var total := 0
	for row: Variant in _map.data.get("enemy_slots", []):
		total += int((row as Dictionary).get("count", 0))
	return total
