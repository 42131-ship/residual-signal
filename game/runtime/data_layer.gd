class_name DataLayer extends RefCounted

signal load_failed(rule: String, detail: String)

const ENUM_FIELDS: Array[String] = ["power", "broadcast", "behavior", "pattern"]

var _nodes_by_id: Dictionary = {}
var _node_list: Array[Dictionary] = []
var _card_list: Array[Dictionary] = []
var _calendar: Array[Dictionary] = []
var _profiles: Dictionary = {}
var _lexicon: Dictionary = {}
var _templates: Dictionary = {}
var _exclusive_names: Array = []


func load_all(root: String = "res://data") -> bool:
	_nodes_by_id.clear()
	_node_list.clear()
	_card_list.clear()
	_calendar.clear()
	_profiles.clear()
	_lexicon.clear()
	_templates.clear()
	_exclusive_names.clear()

	var calendar_data: Variant = _read_json(root.path_join("world_calendar.json"))
	if calendar_data == null:
		return false
	var profile_data: Variant = _read_json(root.path_join("mode_profile.json"))
	if profile_data == null:
		return false
	var nodes_data: Variant = _read_json(root.path_join("nodes.json"))
	if nodes_data == null:
		return false
	var lexicon_data: Variant = _read_json(root.path_join("lexicon.json"))
	if lexicon_data == null:
		return false
	var cards_data: Variant = _read_json(root.path_join("cards/layer_l.json"))
	if cards_data == null:
		return false
	var school_data: Variant = _read_json(root.path_join("templates/school.json"))
	if school_data == null:
		return false

	if not _load_calendar(calendar_data):
		return false
	if not _load_profiles(profile_data):
		return false
	if not _load_lexicon(lexicon_data):
		return false
	if not _load_nodes(nodes_data):
		return false
	if not _load_cards(cards_data):
		return false
	if not _load_template("school", school_data):
		return false

	if not _validate_nodes():
		return false
	if _exclusive_names.is_empty():
		push_warning("R26: template_exclusive_names 为空")
	return true


func node(id: String) -> Dictionary:
	return _nodes_by_id.get(id, {}).duplicate(true)


func nodes() -> Array[Dictionary]:
	return _node_list.duplicate(true)


func axis_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _node_list:
		if str(item.get("role", "")) == "axis":
			result.append(item.duplicate(true))
	return result


func room_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _node_list:
		if str(item.get("role", "")) == "room":
			result.append(item.duplicate(true))
	return result


func calendar_at(day: int) -> Dictionary:
	if _calendar.is_empty():
		return {}
	if day <= int(_calendar[0].get("day", 0)):
		return _calendar[0].duplicate(true)
	if day >= int(_calendar[-1].get("day", 0)):
		return _calendar[-1].duplicate(true)

	for index: int in range(_calendar.size() - 1):
		var first: Dictionary = _calendar[index]
		var next: Dictionary = _calendar[index + 1]
		var first_day := int(first.get("day", 0))
		var next_day := int(next.get("day", 0))
		if day >= first_day and day < next_day:
			var result := first.duplicate(true)
			var ratio := float(day - first_day) / float(next_day - first_day)
			for key: Variant in next.keys():
				if key == "day":
					continue
				var value: Variant = first.get(key)
				var next_value: Variant = next[key]
				if key in ENUM_FIELDS:
					result[key] = value
				elif value is int or value is float:
					if next_value is int or next_value is float:
						result[key] = lerp(float(value), float(next_value), ratio)
				elif not result.has(key):
					result[key] = next_value
			result["day"] = day
			return result
	return _calendar[-1].duplicate(true)


func loot_factor(day: int) -> float:
	return float(calendar_at(day).get("loot", 0.0))


func noise_sensitivity(day: int) -> float:
	return float(calendar_at(day).get("noise_sensitivity", 0.0))


func cards() -> Array[Dictionary]:
	return _card_list.duplicate(true)


func template(id: String) -> Dictionary:
	return _templates.get(id, {}).duplicate(true)


func profile(mode: String) -> Dictionary:
	if mode != "story" and mode != "endless":
		return {}
	var result: Dictionary = _profiles.get("shared", {}).duplicate(true)
	var selected: Dictionary = _profiles.get(mode, {})
	for key: Variant in selected:
		result[key] = selected[key]
	return result


func lexicon(key: String) -> Array:
	var value: Variant = _lexicon.get(key, [])
	if value is Array:
		return value.duplicate(true)
	return []


func is_template_exclusive(word: String) -> bool:
	return _exclusive_names.has(word)


func template_exclusive_hits(text: String) -> PackedStringArray:
	var hits := PackedStringArray()
	for word: Variant in _exclusive_names:
		var value := str(word)
		if not value.is_empty() and text.contains(value) and not hits.has(value):
			hits.append(value)
	return hits


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_fail("file_missing", "找不到文件: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("file_read", "无法读取文件: %s" % path)
		return null
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		_fail("json_parse", "%s 第 %d 行: %s" % [
			path,
			parser.get_error_line(),
			parser.get_error_message()
		])
		return null
	return parser.data


func _load_calendar(data: Variant) -> bool:
	var rows: Variant = data
	if data is Dictionary:
		rows = data.get("keyframes", data.get("calendar", []))
	if not rows is Array or rows.size() != 7:
		_fail("calendar_frames", "world_calendar.json 必须包含七个关键帧")
		return false
	for row: Variant in rows:
		if not row is Dictionary or not row.has("day"):
			_fail("calendar_frame", "日历关键帧必须是含 day 的对象")
			return false
		_calendar.append(row.duplicate(true))
	_calendar.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("day", 0)) < int(b.get("day", 0))
	)
	return true


func _load_profiles(data: Variant) -> bool:
	if not data is Dictionary:
		_fail("profile_format", "mode_profile.json 必须是对象")
		return false
	for key: String in ["story", "endless", "shared"]:
		var value: Variant = data.get(key)
		if not value is Dictionary:
			_fail("profile_missing", "缺少 %s 配置" % key)
			return false
		_profiles[key] = value.duplicate(true)
	return true


func _load_lexicon(data: Variant) -> bool:
	if not data is Dictionary:
		_fail("lexicon_format", "lexicon.json 必须是对象")
		return false
	_lexicon = data.duplicate(true)
	var names: Variant = data.get("template_exclusive_names", [])
	if names is Array:
		_exclusive_names = names.duplicate()
	return true


func _load_nodes(data: Variant) -> bool:
	var rows: Variant = data
	if data is Dictionary:
		rows = data.get("nodes", [])
	if not rows is Array:
		_fail("nodes_format", "nodes.json 必须是节点数组或包含 nodes 的对象")
		return false
	for row: Variant in rows:
		if not row is Dictionary:
			_fail("node_format", "节点必须是对象")
			return false
		var item: Dictionary = row.duplicate(true)
		var id := str(item.get("node_id", ""))
		if id.is_empty() or not id.is_valid_identifier() or id.to_lower() != id:
			if not _valid_node_id(id):
				_fail("node_id", "节点 id 不符合 ^[a-z0-9_]+$: %s" % id)
				return false
		if not _valid_node_id(id):
			_fail("node_id", "节点 id 不符合 ^[a-z0-9_]+$: %s" % id)
			return false
		if _nodes_by_id.has(id):
			_fail("node_id_duplicate", "节点 id 重复: %s" % id)
			return false
		_nodes_by_id[id] = item
		_node_list.append(item)
	return true


func _load_cards(data: Variant) -> bool:
	var rows: Variant = data
	if data is Dictionary:
		rows = data.get("cards", [])
	if not rows is Array:
		_fail("cards_format", "layer_l.json 必须是卡牌数组或包含 cards 的对象")
		return false
	for row: Variant in rows:
		if row is Dictionary:
			_card_list.append(row.duplicate(true))
		else:
			_fail("card_format", "卡牌必须是对象")
			return false
	return true


func _load_template(id: String, data: Variant) -> bool:
	if not data is Dictionary:
		_fail("template_format", "%s 模板必须是对象" % id)
		return false
	_templates[id] = data.duplicate(true)
	return true


func _validate_nodes() -> bool:
	var axes_by_x: Dictionary = {}
	for item: Dictionary in _node_list:
		if str(item.get("role", "")) == "axis":
			if not item.has("axis_x") or not (item["axis_x"] is int or item["axis_x"] is float):
				_fail("axis_x", "主轴节点缺少有效 axis_x: %s" % item.get("node_id", ""))
				return false
			var x := int(item["axis_x"])
			if axes_by_x.has(x):
				_fail("axis_duplicate", "axis_x %d 不止一个主轴节点" % x)
				return false
			axes_by_x[x] = item
	if axes_by_x.is_empty():
		_fail("axis_missing", "至少需要一个主轴节点")
		return false
	var axis_keys: Array = axes_by_x.keys()
	axis_keys.sort()
	for index: int in range(axis_keys.size()):
		if int(axis_keys[index]) != index:
			_fail("axis_gap", "axis_x 必须从 0 连续")
			return false

	var has_lockable := false
	for item: Dictionary in _node_list:
		if bool(item.get("lockable", false)):
			has_lockable = true
		if not _validate_references(item):
			return false
		var linked: Variant = item.get("linked_nodes", [])
		if not linked is Array:
			_fail("links_format", "linked_nodes 必须是数组: %s" % item.get("node_id", ""))
			return false
		var linked_axes: Dictionary = {}
		for target_value: Variant in linked:
			var target_id := str(target_value)
			if not _nodes_by_id.has(target_id):
				_fail("link_missing", "节点 %s 链接了不存在的节点 %s" % [item.get("node_id", ""), target_id])
				return false
			var target: Dictionary = _nodes_by_id[target_id]
			var reverse: Variant = target.get("linked_nodes", [])
			if not reverse is Array or not reverse.has(item.get("node_id")):
				_fail("link_asymmetric", "%s → %s 缺少反向链接" % [item.get("node_id", ""), target_id])
				return false
			if str(item.get("role", "")) == "room" and target.get("role") == "axis":
				linked_axes[int(target.get("axis_x", -1))] = true
		if str(item.get("role", "")) == "room" and linked_axes.size() != 1:
			_fail("room_axis_links", "房间必须连接到且仅连接一个不同的主轴段: %s" % item.get("node_id", ""))
			return false
	if not has_lockable:
		_fail("lockable_missing", "至少需要一个 lockable 节点")
		return false
	return true


func _validate_references(item: Dictionary) -> bool:
	for key: String in ["loot_table", "tags", "noise_events"]:
		if not item.has(key):
			continue
		var values: Array = item[key] if item[key] is Array else [item[key]]
		# 节点字段是单数 loot_table，词表是复数 loot_tables —— 两处命名不统一，这里对齐
		var lex_key: String = "loot_tables" if key == "loot_table" else key
		var allowed: Variant = _lexicon.get(lex_key, [])
		if not allowed is Array:
			_fail("lexicon_key", "lexicon 缺少数组字段: %s" % key)
			return false
		for value: Variant in values:
			if not allowed.has(value):
				_fail("lexicon_reference", "%s 引用了未知 %s: %s" % [
					item.get("node_id", ""),
					key,
					value
				])
				return false
	return true


func _valid_node_id(id: String) -> bool:
	if id.is_empty():
		return false
	for index: int in range(id.length()):
		var code := id.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


func _fail(rule: String, detail: String) -> void:
	load_failed.emit(rule, detail)