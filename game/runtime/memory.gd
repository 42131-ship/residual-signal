class_name Memory extends RefCounted

signal degraded(npc_id: String, event_id: String, from_fid: int, to_fid: int)

const NPC_PATH: String = "res://data/npcs/npcs.json"

var data: DataLayer
var world: WorldState
var npcs: Array[Dictionary] = []

var _last_fidelity: Dictionary = {}


func init_from(d: DataLayer, w: WorldState) -> bool:
	if d == null or w == null:
		return false
	var rows: Variant = d.get("npcs")
	if not _replace_npcs(rows) and not load_npcs():
		return false
	data = d
	world = w
	return true


func load_npcs(path: String = NPC_PATH) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false

	var rows: Variant = json.data
	if rows is Dictionary:
		rows = rows.get("npcs")
	return _replace_npcs(rows)


func fidelity_at(mem: Dictionary, day: int) -> int:
	var trace: Array = mem.get("fidelity_trace", [])
	var base: int = int(mem.get("fidelity", 3))
	if trace.is_empty():
		return base

	var index: int = trace.size() - 1
	while index >= 0:
		var entry: Dictionary = trace[index]
		if int(entry.get("day", 0)) <= day:
			return int(entry.get("fidelity", base))
		index -= 1

	var first: Dictionary = trace[0]
	return int(first.get("fidelity", base))


func render(mem: Dictionary, day: int) -> String:
	var fidelity: int = fidelity_at(mem, day)
	_observe(_owner_id(mem), mem, fidelity)

	if fidelity <= 0:
		return _heard_prefix(mem, false) + _affect_line(float(mem.get("affect", 0.0)))

	var slots: Dictionary = mem.get("slots", {})
	var who: String = _slot(slots, "who")
	var what: String = _slot(slots, "what")
	if who.is_empty() or what.is_empty():
		return _heard_prefix(mem, false) + _affect_line(float(mem.get("affect", 0.0)))

	var prefix: String = _heard_prefix(mem, true)
	var where_text: String = _slot(slots, "where")
	if fidelity == 1 or where_text.is_empty():
		var category: String = _what_category(what)
		if category.is_empty():
			return prefix + "似乎有过与%s有关的事。" % who
		return prefix + "%s似乎%s。" % [who, category]

	var manner: String = _slot(slots, "manner")
	var outcome: String = _slot(slots, "outcome")
	if fidelity >= 3 and not manner.is_empty() and not outcome.is_empty():
		return prefix + "%s在%s%s%s，%s。" % [who, where_text, manner, what, outcome]
	return prefix + "%s在%s%s。" % [who, where_text, what]


func recallable(npc_id: String, day: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var index: int = 0
	while index < npcs.size():
		var npc: Dictionary = npcs[index]
		index += 1
		if _npc_id(npc) != npc_id:
			continue

		var memories: Array = npc.get("memories", [])
		var memory_index: int = 0
		while memory_index < memories.size():
			var mem: Dictionary = memories[memory_index]
			memory_index += 1
			if int(mem.get("hops", 0)) > 2 or int(mem.get("day", day)) > day:
				continue
			var fidelity: int = fidelity_at(mem, day)
			_observe(npc_id, mem, fidelity)
			if fidelity >= 1:
				result.append(mem)
		break
	return result


func cite(mem: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var source: String = str(mem.get("source_event", ""))
	if not source.is_empty():
		result.append(source)

	var via: String = _via_id(mem)
	if data == null or via.is_empty():
		return result

	var npc: Dictionary = _data_npc(via)
	var via_source: String = str(npc.get("source_event", ""))
	if not via_source.is_empty() and not result.has(via_source):
		result.append(via_source)
	return result


func affect_at(npc_id: String) -> float:
	var index: int = 0
	while index < npcs.size():
		var npc: Dictionary = npcs[index]
		index += 1
		if _npc_id(npc) != npc_id:
			continue
		if npc.has("affect"):
			return float(npc["affect"])

		# 未设整体情绪时，汇总该 NPC 的记忆情绪。
		var total: float = 0.0
		var memories: Array = npc.get("memories", [])
		var memory_index: int = 0
		while memory_index < memories.size():
			var mem: Dictionary = memories[memory_index]
			total += float(mem.get("affect", 0.0))
			memory_index += 1
		return total
	return 0.0


func _replace_npcs(rows: Variant) -> bool:
	if not (rows is Array or rows is Dictionary):
		return false

	var records: Array = rows.values() if rows is Dictionary else rows
	var loaded: Array[Dictionary] = []
	var index: int = 0
	while index < records.size():
		var row: Variant = records[index]
		if not row is Dictionary:
			return false
		loaded.append(row)
		index += 1

	npcs = loaded
	_last_fidelity.clear()
	return true


func _data_npc(npc_id: String) -> Dictionary:
	if data.has_method("get_npc"):
		var record: Variant = data.call("get_npc", npc_id)
		if record is Dictionary and not record.is_empty():
			return record

	var rows: Variant = data.get("npcs")
	if rows is Dictionary:
		var record: Variant = rows.get(npc_id)
		if record is Dictionary:
			return record
		rows = rows.values()

	if rows is Array:
		var index: int = 0
		while index < rows.size():
			var record: Variant = rows[index]
			if record is Dictionary and _npc_id(record) == npc_id:
				return record
			index += 1
	return {}


func _owner_id(mem: Dictionary) -> String:
	var npc_id: String = str(mem.get("npc_id", ""))
	if not npc_id.is_empty():
		return npc_id

	# 用记录身份找归属，避免把不同 NPC 的同一事件合并。
	var index: int = 0
	while index < npcs.size():
		var npc: Dictionary = npcs[index]
		var memories: Array = npc.get("memories", [])
		var memory_index: int = 0
		while memory_index < memories.size():
			if is_same(memories[memory_index], mem):
				return _npc_id(npc)
			memory_index += 1
		index += 1
	return ""


func _observe(npc_id: String, mem: Dictionary, fidelity: int) -> void:
	var event_id: String = str(mem.get("event_id", mem.get("source_event", "")))
	if npc_id.is_empty() or event_id.is_empty():
		return

	var by_event: Dictionary = _last_fidelity.get(npc_id, {})
	var previous: int = int(by_event.get(event_id, fidelity))
	by_event[event_id] = fidelity
	_last_fidelity[npc_id] = by_event
	if fidelity < previous:
		degraded.emit(npc_id, event_id, previous, fidelity)


func _npc_id(npc: Dictionary) -> String:
	return str(npc.get("id", npc.get("npc_id", "")))


func _via_id(mem: Dictionary) -> String:
	var via: Variant = mem.get("via")
	if via is String or via is StringName:
		return str(via).strip_edges()
	return ""


func _heard_prefix(mem: Dictionary, reveal_via: bool) -> String:
	if mem.get("kind", "") != "heard":
		return ""
	var via: String = _via_id(mem)
	if reveal_via and not via.is_empty():
		return "听%s说，" % via
	# 情绪残影只保留转述痕迹。
	return "听人转述过，"


func _slot(slots: Dictionary, key: String) -> String:
	var value: Variant = slots.get(key)
	if not value is String and not value is StringName:
		return ""
	var text: String = str(value).strip_edges()
	while not text.is_empty() and "。！？；，、.!?;,".contains(text.right(1)):
		text = text.left(text.length() - 1).strip_edges()
	return text


func _what_category(what: String) -> String:
	# 只返回固定的动作概括。
	if what.begins_with("给了") or what.begins_with("递给") or what.begins_with("送了"):
		return "给过什么"
	if what.begins_with("拿走") or what.begins_with("取走"):
		return "拿走过什么"
	if what.begins_with("说了") or what.begins_with("提到"):
		return "说过些什么"
	if what.begins_with("问了") or what.begins_with("询问"):
		return "问过些什么"
	return ""


func _affect_line(affect: float) -> String:
	if affect > 0.0:
		return "那阵子心里还暖过。"
	if affect < 0.0:
		return "那阵子心里沉过。"
	return "那阵子只隐约有点感觉。"