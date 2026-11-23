class_name LootService
extends RefCounted

const CONTAINERS_PATH := "res://data/loot/containers.json"

var _containers: Dictionary = {}
var _order: Array[String] = []
## id -> {"day": int, "count": int}：当日搜过几次；per_day 刷新按世界日结算。
var _searched: Dictionary = {}
var _load_error := ""


func load_containers(path: String = CONTAINERS_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_load_error = "LOOT_CONTAINERS_MISSING: " + path
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		_load_error = "LOOT_JSON_INVALID: %d %s" % [parser.get_error_line(), parser.get_error_message()]
		return false
	var data: Variant = parser.data
	if not data is Dictionary or str(data.get("schema", "")) != "loot-containers.v1":
		_load_error = "LOOT_SCHEMA_INVALID"
		return false
	var rows: Variant = data.get("containers")
	if not rows is Array:
		_load_error = "LOOT_CONTAINERS_NOT_ARRAY"
		return false

	_containers.clear()
	_order.clear()
	for value: Variant in rows:
		if not value is Dictionary:
			_load_error = "LOOT_CONTAINER_INVALID"
			return false
		var row: Dictionary = value
		var id := str(row.get("id", ""))
		var label := str(row.get("label", ""))
		var table: Variant = row.get("loot_table")
		if id.is_empty() or label.is_empty() or not table is Array or table.is_empty() or _containers.has(id):
			_load_error = "LOOT_CONTAINER_FIELDS_INVALID: " + id
			return false
		var total_weight := 0.0
		for entry: Variant in table:
			if not entry is Dictionary:
				_load_error = "LOOT_ENTRY_INVALID: " + id
				return false
			var candidate: Dictionary = entry
			var weight := float(candidate.get("weight", 0.0))
			if str(candidate.get("item", "")).is_empty() or weight <= 0.0:
				_load_error = "LOOT_ENTRY_FIELDS_INVALID: " + id
				return false
			total_weight += weight
		if total_weight <= 0.0:
			_load_error = "LOOT_WEIGHT_INVALID: " + id
			return false
		_containers[id] = row.duplicate(true)
		_order.append(id)
	return true


func load_error() -> String:
	return _load_error


func has_container(id: String) -> bool:
	return _containers.has(id)


func label_of(id: String) -> String:
	return str(_containers.get(id, {}).get("label", ""))


func container_ids() -> Array[String]:
	return _order.duplicate()


func can_search(id: String, day: int) -> bool:
	if not _containers.has(id):
		return false
	var record: Dictionary = _searched.get(id, {})
	if record.is_empty():
		return true
	var refresh: Dictionary = _containers[id].get("refresh", {})
	var days: int = maxi(1, int(refresh.get("days", 1)))
	return day >= int(record.get("day", 0)) + days


## 返回 {ok, item, kind, empty, day, count}；同一世界日内重复搜索返回 ok=false。
func search(id: String, day: int, salt: int = 0) -> Dictionary:
	if not _containers.has(id):
		return {"ok": false, "reason": "unknown_container"}
	if not can_search(id, day):
		return {"ok": false, "reason": "already_searched_today", "day": day}

	var record: Dictionary = _searched.get(id, {"day": day, "count": 0})
	var count: int = int(record.get("count", 0)) + 1
	_searched[id] = {"day": day, "count": count}

	var definition: Dictionary = _containers[id]
	var table: Array = definition.get("loot_table", [])
	var total := 0.0
	for entry: Dictionary in table:
		total += float(entry.get("weight", 0.0))
	var rng := RandomNumberGenerator.new()
	# 确定性随机：同一 (容器, 世界日, 当日次数, 盐) 永远得到同一结果，便于回放与测试。
	rng.seed = hash("%s|%d|%d|%d" % [id, day, count, salt])
	var roll := rng.randf() * total
	var picked: Dictionary = table[table.size() - 1]
	for entry: Dictionary in table:
		roll -= float(entry.get("weight", 0.0))
		if roll <= 0.0:
			picked = entry
			break
	var kind := str(picked.get("kind", "none"))
	return {
		"ok": true,
		"item": str(picked.get("item", "")),
		"kind": kind,
		"empty": kind == "none",
		"day": day,
		"count": count,
	}


func reset() -> void:
	_searched.clear()
