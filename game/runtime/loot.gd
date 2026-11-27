class_name LootService
extends RefCounted

const CONTAINERS_PATH := "res://data/loot/containers.json"
const ITEMS_PATH := "res://data/loot/items.json"

var _containers: Dictionary = {}
var _order: Array[String] = []
var _tiers: Dictionary = {}
var _pools: Dictionary = {}
var _items: Dictionary = {}
var _refresh: Dictionary = {}
## id -> true：剧情模式下容器搜过就永久为空（不按天刷新）。
var _searched: Dictionary = {}
var _load_error := ""


func load_all(containers_path: String = CONTAINERS_PATH, items_path: String = ITEMS_PATH) -> bool:
	_load_error = ""
	if not _load_items(items_path):
		return false
	return _load_containers(containers_path)


func load_error() -> String:
	return _load_error


func has_container(id: String) -> bool:
	return _containers.has(id)


func label_of(id: String) -> String:
	return str(_containers.get(id, {}).get("label", ""))


func tier_of(id: String) -> String:
	return str(_containers.get(id, {}).get("tier", ""))


## D11：这个容器属于哪个区块（A/B/C）。每区一个容器、档位不同，由数据决定。
func room_of(id: String) -> String:
	return str(_containers.get(id, {}).get("room", ""))


## 搜索这个容器要按住多久（秒）。容器自己的 search_seconds 优先，
## 没写就落回 containers.json 的 tiers[*].search_seconds（数据驱动，不在代码里硬编码）。
func search_seconds_of(id: String) -> float:
	var row: Dictionary = _containers.get(id, {})
	if row.has("search_seconds"):
		return maxf(0.0, float(row["search_seconds"]))
	var tier: Dictionary = _tiers.get(tier_of(id), {})
	return maxf(0.0, float(tier.get("search_seconds", 0.0)))



func container_ids() -> Array[String]:
	return _order.duplicate()


func items_catalog() -> Dictionary:
	return _items


func item_detail(item_id: String) -> Dictionary:
	return _items.get(item_id, {}).duplicate(true)


func item_name(item_id: String) -> String:
	return str(_items.get(item_id, {}).get("name", item_id))


## 物品的使用效果（数据来自 items.json.effect；空字典 = 现在用不上）。
func item_effect(item_id: String) -> Dictionary:
	var detail: Dictionary = _items.get(item_id, {})
	var effect: Variant = detail.get("effect", {})
	return effect.duplicate(true) if effect is Dictionary else {}


func can_search(id: String, mode := "story") -> bool:
	if not _containers.has(id):
		return false
	if bool(_searched.get(id, false)):
		return false
	return true


## 返回 {ok, items:[{id,name,category,description,usage}], count, tier}。
## mode="story"：搜过永久为空（剧情模式，不刷新）；mode="endless"：留待无尽模式接入按日刷新。
func search(id: String, day: int, salt: int = 0, mode := "story") -> Dictionary:
	if not _containers.has(id):
		return {"ok": false, "reason": "unknown_container"}
	if not can_search(id, mode):
		return {"ok": false, "reason": "already_searched"}
	_searched[id] = true

	var tier_id := tier_of(id)
	var tier: Dictionary = _tiers.get(tier_id, {})
	if tier.is_empty():
		return {"ok": false, "reason": "unknown_tier"}

	var rng := RandomNumberGenerator.new()
	# 确定性随机：同一 (容器, 世界日, 盐) 永远得到同一批物资，便于回放与测试。
	rng.seed = hash("%s|%d|%d|%s" % [id, day, salt, tier_id])

	var capacity: Array = tier.get("capacity", [1, 1])
	var capacity_min: int = maxi(1, int(capacity[0]))
	var capacity_max: int = maxi(capacity_min, int(capacity[1]))
	var count: int = rng.randi_range(capacity_min, capacity_max)

	var picked: Array[String] = []
	var guaranteed := str(tier.get("guaranteed", ""))
	if not guaranteed.is_empty():
		var fixed := _pick_from_pool(guaranteed, rng, picked)
		if not fixed.is_empty():
			picked.append(fixed)

	var pool_ids: Array = tier.get("pools", [])
	while picked.size() < count and not pool_ids.is_empty():
		var pool_id := str(pool_ids[rng.randi_range(0, pool_ids.size() - 1)])
		var item_id := _pick_from_pool(pool_id, rng, picked)
		if item_id.is_empty():
			break
		picked.append(item_id)

	var result_items: Array[Dictionary] = []
	for item_id: String in picked:
		var detail: Dictionary = _items.get(item_id, {})
		if detail.is_empty():
			continue
		result_items.append(detail.duplicate(true))
	return {
		"ok": true,
		"count": result_items.size(),
		"items": result_items,
		"tier": tier_id,
		"container": id,
		"day": day,
	}


func reset() -> void:
	_searched.clear()


# ── 内部 ─────────────────────────────────────────────────────

func _pick_from_pool(pool_id: String, rng: RandomNumberGenerator, exclude: Array[String]) -> String:
	var pool: Array = _pools.get(pool_id, [])
	var candidates: Array = []
	var total := 0.0
	for entry: Variant in pool:
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		var item_id := str(row.get("item", ""))
		var weight := float(row.get("weight", 0.0))
		if item_id.is_empty() or weight <= 0.0 or not _items.has(item_id) or item_id in exclude:
			continue
		candidates.append(row)
		total += weight
	if candidates.is_empty() or total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for row: Dictionary in candidates:
		roll -= float(row.get("weight", 0.0))
		if roll <= 0.0:
			return str(row.get("item", ""))
	return str(candidates[candidates.size() - 1].get("item", ""))


func _load_items(path: String) -> bool:
	var data: Variant = _read_json(path)
	if not data is Dictionary or str(data.get("schema", "")) != "loot-items.v1":
		_load_error = "LOOT_ITEMS_SCHEMA_INVALID"
		return false
	var rows: Variant = data.get("items")
	if not rows is Array or rows.is_empty():
		_load_error = "LOOT_ITEMS_NOT_ARRAY"
		return false
	_items.clear()
	for value: Variant in rows:
		if not value is Dictionary:
			_load_error = "LOOT_ITEM_INVALID"
			return false
		var row: Dictionary = value
		var item_id := str(row.get("id", ""))
		var name := str(row.get("name", ""))
		var description := str(row.get("description", ""))
		var usage := str(row.get("usage", ""))
		if item_id.is_empty() or name.is_empty() or description.is_empty() or usage.is_empty():
			_load_error = "LOOT_ITEM_FIELDS_INVALID: " + item_id
			return false
		if _items.has(item_id):
			_load_error = "LOOT_ITEM_DUPLICATE: " + item_id
			return false
		var effect: Variant = row.get("effect", {})
		if effect != null and not effect is Dictionary:
			_load_error = "LOOT_ITEM_EFFECT_INVALID: " + item_id
			return false
		var effect_row: Dictionary = effect if effect is Dictionary else {}
		for key: Variant in effect_row:
			var effect_key := str(key)
			if effect_key not in ["supplies", "health", "noise", "equip", "contaminate",
					"damage", "durability", "magazine", "ammo",
					"wound", "poison", "infection", "addiction", "heal_wound"]:
				_load_error = "LOOT_ITEM_EFFECT_UNKNOWN: %s.%s" % [item_id, effect_key]
				return false
		if effect_row.has("equip"):
			var kind := str(effect_row["equip"])
			if kind != "melee" and kind != "firearm":
				_load_error = "LOOT_ITEM_EQUIP_INVALID: " + item_id
				return false
		for numeric_key: String in ["damage", "durability", "magazine"]:
			if effect_row.has(numeric_key):
				var numeric_value: Variant = effect_row[numeric_key]
				if not (numeric_value is int or numeric_value is float) or int(numeric_value) < 0:
					_load_error = "LOOT_ITEM_EFFECT_NUMBER_INVALID: %s.%s" % [item_id, numeric_key]
					return false
		if effect_row.has("ammo") and str(effect_row["ammo"]).is_empty():
			_load_error = "LOOT_ITEM_AMMO_EMPTY: " + item_id
			return false
		_items[item_id] = {
			"id": item_id,
			"name": name,
			"category": str(row.get("category", "")),
			"description": description,
			"usage": usage,
			"effect": effect_row.duplicate(true),
		}
	# 装填引用的弹药必须是真实物品。
	for item_id: String in _items:
		var effect: Dictionary = _items[item_id].get("effect", {})
		if effect.has("ammo") and not _items.has(str(effect["ammo"])):
			_load_error = "LOOT_ITEM_AMMO_UNKNOWN: " + item_id
			return false
	return true


func _load_containers(path: String) -> bool:
	var data: Variant = _read_json(path)
	if not data is Dictionary or str(data.get("schema", "")) != "loot-containers.v2":
		_load_error = "LOOT_CONTAINERS_SCHEMA_INVALID"
		return false

	var tiers_value: Variant = data.get("tiers")
	var pools_value: Variant = data.get("pools")
	var rows: Variant = data.get("containers")
	var refresh_value: Variant = data.get("refresh")
	if not tiers_value is Dictionary or not pools_value is Dictionary or not rows is Array:
		_load_error = "LOOT_CONTAINERS_SHAPE_INVALID"
		return false
	_refresh = refresh_value if refresh_value is Dictionary else {}
	_tiers = tiers_value
	_pools = pools_value

	# 池里的物品必须全部在物品表里（不让容器引用不存在的东西）。
	for pool_id: Variant in _pools:
		var pool: Variant = _pools[pool_id]
		if not pool is Array or pool.is_empty():
			_load_error = "LOOT_POOL_INVALID: " + str(pool_id)
			return false
		for entry: Variant in pool:
			if not entry is Dictionary or not _items.has(str((entry as Dictionary).get("item", ""))):
				_load_error = "LOOT_POOL_ITEM_UNKNOWN: " + str(pool_id)
				return false

	_containers.clear()
	_order.clear()
	var treasure_per_building: Dictionary = {}
	for value: Variant in rows:
		if not value is Dictionary:
			_load_error = "LOOT_CONTAINER_INVALID"
			return false
		var row: Dictionary = value
		var id := str(row.get("id", ""))
		var label := str(row.get("label", ""))
		var tier_id := str(row.get("tier", ""))
		var building := str(row.get("building", ""))
		if id.is_empty() or label.is_empty() or building.is_empty() or not _tiers.has(tier_id):
			_load_error = "LOOT_CONTAINER_FIELDS_INVALID: " + id
			return false
		if _containers.has(id):
			_load_error = "LOOT_CONTAINER_DUPLICATE: " + id
			return false
		_containers[id] = row.duplicate(true)
		_order.append(id)
		if tier_id == "treasure":
			treasure_per_building[building] = int(treasure_per_building.get(building, 0)) + 1
	for building: Variant in treasure_per_building:
		if int(treasure_per_building[building]) > 1:
			_load_error = "LOOT_TREASURE_NOT_UNIQUE: " + str(building)
			return false
	return true


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_load_error = "LOOT_MISSING: " + path
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		_load_error = "LOOT_JSON_INVALID: %d %s" % [parser.get_error_line(), parser.get_error_message()]
		return null
	return parser.data
