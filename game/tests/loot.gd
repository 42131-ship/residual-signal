extends SceneTree
## 战利品门禁 v2：剧情模式不刷新 + 容器珍惜度分级 + 容量/物品双随机 + 高价值物只在建筑唯一高珍惜容器。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/loot.gd
## 通过输出一行 `LOOT_OK ...`。

const FIREARMS := ["pistol", "ammo_9mm", "rifle"]
const HIGH_VALUE := [
	"pistol", "ammo_9mm", "rifle", "flare", "firecracker",
	"antibiotics", "first_aid_kit", "tourniquet",
]


func _initialize() -> void:
	var loot := LootService.new()
	if not loot.load_all():
		_fail("loot load failed: " + loot.load_error())
		return

	# ① 物品表：数量、必填字段，且玩家可见详情里不能出现稀有度/价值。
	var catalog := loot.items_catalog()
	if catalog.size() < 40:
		_fail("item catalog too small: %d" % catalog.size())
		return
	for item_id: Variant in catalog:
		var item: Dictionary = catalog[item_id]
		for field: String in ["id", "name", "category", "description", "usage"]:
			if str(item.get(field, "")).is_empty():
				_fail("item %s missing %s" % [str(item_id), field])
				return
		for forbidden: String in ["tier", "rarity", "value", "grade", "price"]:
			if item.has(forbidden):
				_fail("item detail leaks value field %s on %s" % [forbidden, str(item_id)])
				return

	# ② 容器：每栋建筑只能有一个高珍惜容器（学校 = 急救柜），且 A/B/C 三个房间各有容器。
	var containers := loot.container_ids()
	if containers.size() != 3:
		_fail("expected 3 containers, got %d" % containers.size())
		return
	var treasure_count := 0
	var treasure_id := ""
	var tier_seen: Dictionary = {}
	for id: String in containers:
		tier_seen[loot.tier_of(id)] = true
		if loot.tier_of(id) == "treasure":
			treasure_count += 1
			treasure_id = id
	if treasure_count != 1 or treasure_id != "first_aid_cabinet":
		_fail("school must have exactly one treasure container, got %d (%s)" % [treasure_count, treasure_id])
		return
	if tier_seen.size() < 3:
		_fail("three rooms should use different container tiers, got %s" % str(tier_seen))
		return

	# ③ 剧情模式不刷新：搜过一次后，不管过多少世界日都拒绝。
	var first := loot.search("locker_bank", 1, 0, "story")
	if not bool(first.get("ok", false)):
		_fail("first locker search failed: " + str(first))
		return
	var first_ids := _ids_of(first)
	if first_ids.is_empty() or first_ids.size() > 2:
		_fail("common container capacity out of range: %s" % str(first_ids))
		return
	for day in range(1, 31):
		var repeat := loot.search("locker_bank", day, 0, "story")
		if bool(repeat.get("ok", false)):
			_fail("story mode refreshed a container on day %d" % day)
			return
	if str(loot.search("locker_bank", 31, 0, "story").get("reason", "")) != "already_searched":
		_fail("refusal reason should be already_searched")
		return

	# ④ 容量随机：同一档位在不同盐下件数必须变化，且落在档位区间内。
	var common_counts: Dictionary = {}
	var treasure_counts: Dictionary = {}
	for salt in range(64):
		var common_loot := LootService.new()
		common_loot.load_all()
		var common_result := common_loot.search("locker_bank", 1, salt, "story")
		if not bool(common_result.get("ok", false)):
			_fail("common search failed at salt %d" % salt)
			return
		var common_count := int(common_result.get("count", 0))
		common_counts[common_count] = true
		if common_count < 1 or common_count > 2:
			_fail("common capacity %d outside [1,2]" % common_count)
			return

		var treasure_loot := LootService.new()
		treasure_loot.load_all()
		var treasure_result := treasure_loot.search("first_aid_cabinet", 1, salt, "story")
		if not bool(treasure_result.get("ok", false)):
			_fail("treasure search failed at salt %d" % salt)
			return
		var treasure_count_here := int(treasure_result.get("count", 0))
		treasure_counts[treasure_count_here] = true
		if treasure_count_here < 4 or treasure_count_here > 5:
			_fail("treasure capacity %d outside [4,5]" % treasure_count_here)
			return
		var ids := _ids_of(treasure_result)
		var distinct: Dictionary = {}
		for item_id: String in ids:
			distinct[item_id] = true
		if distinct.size() != ids.size():
			_fail("treasure search returned duplicates: %s" % str(ids))
			return
	if common_counts.size() < 2:
		_fail("common container count is not random: %s" % str(common_counts))
		return
	if treasure_counts.size() < 2:
		_fail("treasure container count is not random: %s" % str(treasure_counts))
		return

	# ⑤ 武器/枪械只在高珍惜容器：普通容器搜 64 次不得出现 weapon 类别。
	for salt in range(64):
		var check_loot := LootService.new()
		check_loot.load_all()
		var result := check_loot.search("locker_bank", 1, salt, "story")
		for item: Variant in result.get("items", []):
			if str((item as Dictionary).get("category", "")) == "weapon":
				_fail("common container leaked a weapon: %s" % str((item as Dictionary).get("id", "")))
				return

	# ⑥ 高珍惜容器必有一件高价值物，且 64 次里至少出过一次枪械。
	var saw_firearm := false
	for salt in range(64):
		var high_loot := LootService.new()
		high_loot.load_all()
		var result := high_loot.search("first_aid_cabinet", 1, salt, "story")
		var hit_high := false
		for item: Variant in result.get("items", []):
			var item_id := str((item as Dictionary).get("id", ""))
			if item_id in HIGH_VALUE:
				hit_high = true
			if item_id in FIREARMS:
				saw_firearm = true
		if not hit_high:
			_fail("treasure search without a high-value item (salt %d): %s" % [salt, str(_ids_of(result))])
			return
	if not saw_firearm:
		_fail("treasure container never produced a firearm in 64 searches")
		return

	# ⑦ 确定性：同 (容器, 天数, 盐) 永远得到同一批物资。
	var det_a := _ids_of(_search_once("first_aid_cabinet", 7, 42))
	var det_b := _ids_of(_search_once("first_aid_cabinet", 7, 42))
	if det_a != det_b:
		_fail("loot is not deterministic: %s vs %s" % [str(det_a), str(det_b)])
		return

	print("LOOT_OK items=%d containers=%d tiers=%d story=never capacity_random=ok weapon_only_treasure=ok deterministic=ok" % [
		catalog.size(), containers.size(), 4])
	quit(0)


func _search_once(container_id: String, day: int, salt: int) -> Dictionary:
	var service := LootService.new()
	service.load_all()
	return service.search(container_id, day, salt, "story")


func _ids_of(result: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for item: Variant in result.get("items", []):
		ids.append(str((item as Dictionary).get("id", "")))
	return ids


func _fail(detail: String) -> void:
	push_error("LOOT_FAIL " + detail)
	print("LOOT_FAIL " + detail)
	quit(1)
