extends SceneTree
## 背包与使用效果门禁：容量、堆叠、使用/装备/用不上、效果数据合法性。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/inventory.gd
## 通过输出一行 `INVENTORY_OK ...`。

const VALID_EFFECT_KEYS := [
	"supplies", "health", "noise", "equip", "contaminate",
	# 战斗提交（Stage 2.11）新增：武器伤害 / 耐久 / 弹匣容量 / 装填的弹药 id。
	"damage", "durability", "magazine", "ammo",
]


func _initialize() -> void:
	# ① 背包容量与堆叠。
	var inventory := InventoryService.new(3)
	if not inventory.add("bottled_water"):
		_fail("add bottled_water failed")
		return
	if not inventory.add("bottled_water"):
		_fail("stacking the same item failed")
		return
	if inventory.count_of("bottled_water") != 2 or inventory.total() != 2:
		_fail("count/stack wrong: %s" % str(inventory.entries()))
		return
	if not inventory.add("bandage") or inventory.total() != 3 or not inventory.is_full():
		_fail("inventory did not fill to capacity 3")
		return
	if inventory.add("crowbar"):
		_fail("inventory accepted an item beyond capacity")
		return
	if not inventory.remove("bottled_water", 2) or inventory.total() != 1:
		_fail("remove did not work")
		return
	var bulk := inventory.add_many(["crowbar", "coins", "tape"])
	if int(bulk.get("added", []).size()) != 2 or int(bulk.get("rejected", []).size()) != 1:
		_fail("add_many should accept 2 and reject 1: %s" % str(bulk))
		return

	# ② 使用效果数据：41 件带效果；键与值合法；武器只能装到装备槽。
	var loot := LootService.new()
	if not loot.load_all():
		_fail("loot load failed: " + loot.load_error())
		return
	var catalog := loot.items_catalog()
	var with_effect := 0
	for item_id: Variant in catalog:
		var effect := loot.item_effect(str(item_id))
		if effect.is_empty():
			continue
		with_effect += 1
		for key: Variant in effect:
			if str(key) not in VALID_EFFECT_KEYS:
				_fail("unknown effect key %s on %s" % [str(key), str(item_id)])
				return
		if effect.has("equip"):
			var equip := str(effect["equip"])
			if equip != "melee" and equip != "firearm":
				_fail("invalid equip kind %s on %s" % [equip, str(item_id)])
				return
	if with_effect != 41:
		_fail("expected 41 items with effects, got %d" % with_effect)
		return
	if float(loot.item_effect("bottled_water").get("supplies", 0.0)) <= 0.0:
		_fail("bottled_water should restore supplies")
		return
	if float(loot.item_effect("bandage").get("health", 0.0)) <= 0.0:
		_fail("bandage should restore health")
		return
	if str(loot.item_effect("crowbar").get("equip", "")) != "melee":
		_fail("crowbar should be a melee equip")
		return
	if str(loot.item_effect("pistol").get("equip", "")) != "firearm":
		_fail("pistol should be a firearm equip")
		return
	if not loot.item_effect("coins").is_empty():
		_fail("coins should have no use effect")
		return

	print("INVENTORY_OK capacity=3 stack=2 effects=%d equip=melee/firearm junk=no_effect" % with_effect)
	quit(0)


func _fail(detail: String) -> void:
	push_error("INVENTORY_FAIL " + detail)
	print("INVENTORY_FAIL " + detail)
	quit(1)
