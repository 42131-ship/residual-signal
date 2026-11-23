class_name PixelFont
extends RefCounted
# 5×7 点阵字体的绘制帮助类。图集由 tools/font_build.py 生成。
#
# 为什么要有它：378×216 下只有 8px 字高可读，而 Godot 默认矢量字抗锯齿后
# 实际占 18–20px。为了「残响栅格」那三条硬规矩（4 的倍数 / 无抗锯齿 / 无发光），
# 字体必须逐像素画，不能用 Label。

const ATLAS_PATH := "res://art/generated_candidates/fonts/PF-01_5x7.png"
const CJK_ATLAS_PATH := "res://art/generated_candidates/fonts/PF-02_cjk_12.png"
const CJK_MAP_PATH := "res://art/generated_candidates/fonts/PF-02_cjk_12.json"
const CELL_W := 6
const GLYPH_H := 8
const ORDER := "DAY0123456789  "
const ADVANCE := 6
const CJK_ADVANCE_FALLBACK := 14

static var _tex: Texture2D = null
static var _cjk_tex: Texture2D = null
static var _cjk_map: Dictionary = {}
static var _cjk_advance := CJK_ADVANCE_FALLBACK


static func _texture() -> Texture2D:
	if _tex == null:
		_tex = load(ATLAS_PATH)
	return _tex


static func _load_cjk() -> void:
	if _cjk_tex != null and not _cjk_map.is_empty():
		return
	_cjk_tex = load(CJK_ATLAS_PATH) as Texture2D
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CJK_MAP_PATH))
	if parsed is Dictionary and parsed.get("schema") == "pixel-font-atlas.v1":
		_cjk_map = parsed.get("characters", {})
		# 步进以图集元数据为准：字号变过两次（12 → 14），写死在代码里就会串行。
		_cjk_advance = maxi(1, int(parsed.get("advance", CJK_ADVANCE_FALLBACK)))


static func width_of(text: String) -> int:
	_load_cjk()
	var width := 0
	for index in text.length():
		width += ADVANCE if ORDER.contains(text[index]) else _cjk_advance
	return width


static func draw(parent: Node, text: String, pos: Vector2, tint: Color) -> int:
	var n := 0
	var x := 0
	_load_cjk()
	for index in text.length():
		var char := text[index]
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.modulate = tint
		if ORDER.contains(char):
			var idx := ORDER.find(char)
			sprite.texture = _texture()
			sprite.region_enabled = true
			sprite.region_rect = Rect2(idx * CELL_W, 0, CELL_W, GLYPH_H)
			sprite.position = pos + Vector2(x, 0)
			x += ADVANCE
		else:
			var entry: Variant = _cjk_map.get(char)
			if not entry is Dictionary or _cjk_tex == null:
				push_warning("PixelFont 缺少中文字形: " + char)
				continue
			var region: Array = entry.get("region", [])
			var offset: Array = entry.get("offset", [0, 0])
			if region.size() != 4 or offset.size() != 2:
				continue
			sprite.texture = _cjk_tex
			sprite.region_enabled = true
			sprite.region_rect = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
			sprite.position = pos + Vector2(x + int(offset[0]), int(offset[1]))
			x += _cjk_advance
		parent.add_child(sprite)
		n += 1
	return n
