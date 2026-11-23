class_name EndingBook
extends RefCounted
## 结局栏：每个模板固定 4 个结局槽。定义在 data/endings/<template>.json，
## 解锁状态由外部（存档）喂进来，不写回数据表。
##
## 关键约束：**未解锁时不能剧透**——标题只给「？？？」，回忆文本只给占位。
## 这不是 UI 层的礼貌，是数据层就得挡住，免得哪天 HUD 直接读字段把标题漏出去。

const DIR := "res://data/endings"

var _defs: Dictionary = {}        # template -> Array[Dictionary]
var _slot_count: Dictionary = {}  # template -> int
var _unlocked: Dictionary = {}    # template -> { ending_id: true }
var _load_error := ""


func load_template(template: String) -> bool:
	_load_error = ""
	var path := "%s/%s.json" % [DIR, template]
	if not FileAccess.file_exists(path):
		_load_error = "ENDINGS_MISSING: " + path
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary:
		_load_error = "ENDINGS_UNREADABLE: " + template
		return false
	var data: Dictionary = raw
	if str(data.get("schema", "")) != "endings.v1":
		_load_error = "ENDINGS_SCHEMA: " + template
		return false
	if str(data.get("template", "")) != template:
		_load_error = "ENDINGS_TEMPLATE_MISMATCH: " + template
		return false
	var rows: Variant = data.get("endings")
	if not rows is Array or (rows as Array).size() != 4:
		_load_error = "ENDINGS_SLOT_COUNT: " + template
		return false
	var seen := {}
	for value: Variant in rows:
		if not value is Dictionary:
			_load_error = "ENDINGS_ENTRY_INVALID"
			return false
		var entry: Dictionary = value
		var id := str(entry.get("id", ""))
		if id.is_empty() or seen.has(id):
			_load_error = "ENDINGS_ID_INVALID: " + id
			return false
		seen[id] = true
	_defs[template] = (rows as Array).duplicate(true)
	_slot_count[template] = int(data.get("slots", 4))
	if not _unlocked.has(template):
		_unlocked[template] = {}
	return true


func load_error() -> String:
	return _load_error


func templates() -> Array[String]:
	var out: Array[String] = []
	for id: String in _defs:
		out.append(id)
	out.sort()
	return out


func slot_count(template: String) -> int:
	return int(_slot_count.get(template, 0))


func has(template: String, ending_id: String) -> bool:
	for entry: Dictionary in _defs.get(template, []):
		if str(entry.get("id", "")) == ending_id:
			return true
	return false


func unlock(template: String, ending_id: String) -> bool:
	if not has(template, ending_id):
		return false
	if not _unlocked.has(template):
		_unlocked[template] = {}
	_unlocked[template][ending_id] = true
	return true


func is_unlocked(template: String, ending_id: String) -> bool:
	return bool((_unlocked.get(template, {}) as Dictionary).has(ending_id))


## 把存档里的解锁记录并进来（RunState.unlocked 的结构：{template: {ending_id: true}}）。
## 只认已知 id，脏数据直接丢掉，避免界面显示一个不存在的结局。
func adopt(unlocked: Dictionary) -> int:
	var applied := 0
	for template: String in unlocked:
		var rows: Variant = unlocked[template]
		if not rows is Dictionary:
			continue
		for ending_id: String in (rows as Dictionary):
			if unlock(template, ending_id):
				applied += 1
	return applied


func unlocked_count(template: String) -> int:
	return (_unlocked.get(template, {}) as Dictionary).size()


func is_complete(template: String) -> bool:
	return unlocked_count(template) >= int(_slot_count.get(template, 4))


## 结局栏要显示的行：未解锁时把标题与回忆都换成占位，绝不漏。
func entries(template: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rows: Array = _defs.get(template, [])
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for entry: Dictionary in sorted:
		var id := str(entry.get("id", ""))
		var open := is_unlocked(template, id)
		out.append({
			"id": id,
			"order": int(entry.get("order", 0)),
			"grade": str(entry.get("grade", "")),
			"unlocked": open,
			"label": str(entry.get("label", "")) if open else str(entry.get("locked_label", "？？？")),
			"summary": str(entry.get("summary", "")) if open else str(entry.get("locked_summary", "")),
		})
	return out


func _num(context: Dictionary, key: String, fallback: float) -> float:
	return float(context.get(key, fallback))


func _passes(conditions: Dictionary, context: Dictionary) -> bool:
	for key: String in conditions:
		var want: Variant = conditions[key]
		match key:
			"day_min":
				if int(context.get("day", 0)) < int(want):
					return false
			"companions_alive_min":
				if int(context.get("companions_alive", 0)) < int(want):
					return false
			"companions_alive_max":
				if int(context.get("companions_alive", 0)) > int(want):
					return false
			"companions_lost_min":
				if int(context.get("companions_lost", 0)) < int(want):
					return false
			"ammo_at_end":
				if int(context.get("ammo", -1)) != int(want):
					return false
			"requires_finale":
				if str(context.get("finale", "")) != str(want):
					return false
			"requires_item_any":
				var owned: Array = context.get("items", [])
				var hit := false
				for item_id: Variant in (want as Array):
					if str(item_id) in owned:
						hit = true
						break
				if not hit:
					return false
			"trust_min", "reputation_min", "supplies_min", "control_min", "knowledge_min", "bond_min":
				var var_name := key.trim_suffix("_min")
				if _num(context, var_name, 0.0) < float(want):
					return false
			"trust_max", "reputation_max", "supplies_max", "control_max", "knowledge_max", "bond_max":
				var var_name_max := key.trim_suffix("_max")
				if _num(context, var_name_max, 1.0) > float(want):
					return false
			_:
				return false
	return true


## 按 order 顺序取第一个满足的结局；都不满足返回空字符串。
func match_ending(template: String, context: Dictionary) -> String:
	var rows: Array = _defs.get(template, [])
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for entry: Dictionary in sorted:
		var conditions: Variant = entry.get("conditions", {})
		if conditions is Dictionary and _passes(conditions, context):
			return str(entry.get("id", ""))
	return ""
