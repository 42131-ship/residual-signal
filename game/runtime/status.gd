class_name StatusService
extends RefCounted
## 状态系统：伤口 / 感染 / 中毒 / 成瘾。
##
## 只做三件事：记阶段、按游戏小时推进、给玩家算倍率。
## 具体数值全在 data/systems/status.json，代码不写死；这样调平衡不用改脚本。

const DATA_PATH := "res://data/systems/status.json"

var _defs: Dictionary = {}
var _stage: Dictionary = {}
var _hours: Dictionary = {}
var _load_error := ""


func load_all() -> bool:
	_defs.clear()
	_stage.clear()
	_hours.clear()
	_load_error = ""
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not raw is Dictionary:
		_load_error = "STATUS_DATA_UNREADABLE"
		return false
	var data: Dictionary = raw
	if str(data.get("schema", "")) != "status-v1":
		_load_error = "STATUS_SCHEMA_INVALID"
		return false
	var rows: Variant = data.get("statuses")
	if not rows is Array or (rows as Array).is_empty():
		_load_error = "STATUS_LIST_EMPTY"
		return false
	for value: Variant in rows:
		if not value is Dictionary:
			_load_error = "STATUS_ENTRY_INVALID"
			return false
		var entry: Dictionary = value
		var id := str(entry.get("id", ""))
		if id.is_empty() or _defs.has(id):
			_load_error = "STATUS_ID_INVALID: " + id
			return false
		var max_stage := int(entry.get("max_stage", 0))
		var per_stage: Variant = entry.get("per_stage")
		if max_stage <= 0 or not per_stage is Dictionary:
			_load_error = "STATUS_STAGE_INVALID: " + id
			return false
		_defs[id] = entry
	return true


func load_error() -> String:
	return _load_error


func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _defs:
		out.append(id)
	out.sort()
	return out


func has(id: String) -> bool:
	return int(_stage.get(id, 0)) > 0


func stage_of(id: String) -> int:
	return int(_stage.get(id, 0))


func max_stage_of(id: String) -> int:
	return int((_defs.get(id, {}) as Dictionary).get("max_stage", 0))


func label_of(id: String) -> String:
	return str((_defs.get(id, {}) as Dictionary).get("label", id))


## 升一级（默认），返回新阶段。未知 id 返回 0，不抛错——上层只当没发生。
func apply(id: String, amount := 1) -> int:
	if not _defs.has(id) or amount <= 0:
		return stage_of(id)
	var ceiling := max_stage_of(id)
	var next := mini(ceiling, stage_of(id) + amount)
	_stage[id] = next
	_hours[id] = 0.0
	return next


func cure(id: String) -> bool:
	if not _defs.has(id) or not has(id):
		return false
	_stage.erase(id)
	_hours.erase(id)
	return true


## 用一件药：按 status.json 的 cure_items 匹配，返回被治好的状态 id（空 = 这件药不对症）。
func cure_with_item(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	for id: String in _defs:
		if not has(id):
			continue
		var cures: Variant = (_defs[id] as Dictionary).get("cure_items", [])
		if cures is Array and item_id in cures:
			cure(id)
			return id
	return ""


## 推进游戏小时：感染按 stage_hours 恶化，中毒按 decay_hours 消退，伤口/成瘾常驻。
func tick_hours(hours: float) -> void:
	if hours <= 0.0:
		return
	for id: String in _defs.keys():
		if not has(id):
			continue
		var entry: Dictionary = _defs[id]
		var bank := float(_hours.get(id, 0.0)) + hours
		var stage_hours := float(entry.get("stage_hours", 0.0))
		if stage_hours > 0.0 and stage_of(id) < max_stage_of(id):
			# 跨级时把余量留下，别用 apply()——它会清零计时。
			while bank >= stage_hours and stage_of(id) < max_stage_of(id):
				bank -= stage_hours
				_stage[id] = mini(max_stage_of(id), stage_of(id) + 1)
		var decay_hours := float(entry.get("decay_hours", 0.0))
		if decay_hours > 0.0 and bank >= decay_hours:
			cure(id)
			continue
		_hours[id] = bank


func health_drain_per_hour() -> float:
	var total := 0.0
	for id: String in _defs:
		var stage := stage_of(id)
		if stage <= 0:
			continue
		total += float(((_defs[id] as Dictionary).get("per_stage", {}) as Dictionary).get("health_drain_per_hour", 0.0)) * stage
	return total


func speed_multiplier() -> float:
	var mult := 1.0
	for id: String in _defs:
		var stage := stage_of(id)
		if stage <= 0:
			continue
		mult *= pow(float(((_defs[id] as Dictionary).get("per_stage", {}) as Dictionary).get("speed_mult", 1.0)), stage)
	return clampf(mult, 0.35, 1.0)


func noise_multiplier() -> float:
	var mult := 1.0
	for id: String in _defs:
		var stage := stage_of(id)
		if stage <= 0:
			continue
		mult *= pow(float(((_defs[id] as Dictionary).get("per_stage", {}) as Dictionary).get("noise_mult", 1.0)), stage)
	return clampf(mult, 1.0, 3.0)


## HUD 用：[{id, label, stage, max}]，按 id 排序保证同一状态下每帧顺序稳定。
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids():
		if has(id):
			out.append({
				"id": id,
				"label": label_of(id),
				"stage": stage_of(id),
				"max": max_stage_of(id),
			})
	return out


func summary() -> String:
	var parts: PackedStringArray = []
	for row: Dictionary in active():
		parts.append("%s%d" % [str(row["label"]), int(row["stage"])])
	return " ".join(parts)
