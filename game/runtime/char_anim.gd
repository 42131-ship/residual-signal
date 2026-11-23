class_name CharAnim
extends RefCounted
## 人物动作库：读 tools/char_anim_build.py 生成的精灵表与元数据。
##
## 一帧 = 表上一列；动作只是「起始列 + 帧数 + fps + 是否循环」。
## 画面仍然是一张 AtlasTexture，不额外分配整张贴图。

const MANIFEST_PATH := "res://art/generated_candidates/characters/anim/anims.json"

static var _loaded := false
static var _characters: Dictionary = {}
static var _anims: Dictionary = {}
static var _order: Array[String] = []
static var _sheets: Dictionary = {}
static var _cache: Dictionary = {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not raw is Dictionary:
		push_error("CHAR_ANIM_MANIFEST_UNREADABLE")
		return
	var data: Dictionary = raw
	for entry: Variant in data.get("anims", []):
		if entry is Dictionary:
			_anims[str((entry as Dictionary).get("id", ""))] = entry
	for entry: Variant in data.get("characters", []):
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		var id := str(record.get("id", ""))
		if id.is_empty():
			continue
		_characters[id] = record
		_order.append(id)


static func has(id: String) -> bool:
	_ensure()
	return _characters.has(id)


static func character_ids() -> Array[String]:
	_ensure()
	return _order.duplicate()


static func anim_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for id: String in _anims:
		out.append(id)
	out.sort()
	return out


static func anim_meta(anim_id: String) -> Dictionary:
	_ensure()
	return (_anims.get(anim_id, {}) as Dictionary).duplicate()


static func frame_size(id: String) -> Vector2i:
	_ensure()
	var size: Variant = (_characters.get(id, {}) as Dictionary).get("frame_size", [0, 0])
	if size is Array and (size as Array).size() == 2:
		return Vector2i(int(size[0]), int(size[1]))
	return Vector2i.ZERO


static func parts(id: String) -> Array:
	_ensure()
	return (_characters.get(id, {}) as Dictionary).get("parts", [])


static func _sheet(id: String) -> Texture2D:
	if _sheets.has(id):
		return _sheets[id]
	var path := str((_characters.get(id, {}) as Dictionary).get("sheet", ""))
	if path.is_empty():
		return null
	var texture := load(path) as Texture2D
	_sheets[id] = texture
	return texture


## 取某一列的画面。同一 (角色, 列) 只建一次 AtlasTexture。
static func frame_texture(id: String, index: int) -> AtlasTexture:
	_ensure()
	var key := "%s#%d" % [id, index]
	if _cache.has(key):
		return _cache[key]
	var texture := _sheet(id)
	if texture == null:
		return null
	var size := frame_size(id)
	if size == Vector2i.ZERO:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2(index * size.x, 0), Vector2(size))
	_cache[key] = atlas
	return atlas


## 按时间取列号：loop 的动作取模，一次性动作夹在最后一帧。
static func frame_at(id: String, anim_id: String, seconds: float) -> int:
	var meta := anim_meta(anim_id)
	if meta.is_empty():
		return 0
	var start := int(meta.get("start", 0))
	var count := maxi(1, int(meta.get("count", 1)))
	var fps := maxf(0.1, float(meta.get("fps", 8.0)))
	var step := int(floor(seconds * fps))
	if bool(meta.get("loop", true)):
		return start + step % count
	return start + mini(count - 1, step)


static func frame_for_state(id: String, anim_id: String, seconds: float) -> AtlasTexture:
	return frame_texture(id, frame_at(id, anim_id, seconds))
