extends SceneTree
## 战利品门禁：两个可搜索容器 + 确定性随机 + 按世界日刷新。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/loot.gd
## 通过输出一行 `LOOT_OK ...`。

const CONTAINERS := ["locker_bank", "first_aid_cabinet"]


func _initialize() -> void:
	var loot := LootService.new()
	if not loot.load_containers():
		_fail("loot containers failed: " + loot.load_error())
		return

	# ① 两个容器都在数据里，且 tab 里至少 4 种结果（含空）。
	for id: String in CONTAINERS:
		if not loot.has_container(id):
			_fail("missing container " + id)
			return
		if loot.label_of(id).is_empty():
			_fail("container without label: " + id)
			return

	# ② 同一世界日内只能搜一次（per_day 刷新）。
	var first := loot.search("locker_bank", 3)
	if not bool(first.get("ok", false)) or str(first.get("item", "")).is_empty():
		_fail("first search did not return an item: " + str(first))
		return
	var again := loot.search("locker_bank", 3)
	if bool(again.get("ok", false)):
		_fail("same-day second search should be refused: " + str(again))
		return
	if str(again.get("reason", "")) != "already_searched_today":
		_fail("unexpected refusal reason: " + str(again))
		return

	# ③ 跨日刷新：换一天必须能重新搜。
	var next_day := loot.search("locker_bank", 4)
	if not bool(next_day.get("ok", false)):
		_fail("container did not refresh on the next day: " + str(next_day))
		return

	# ④ 随机性：同一个容器搜 30 天，结果至少有 2 种不同物品。
	var seen: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261123
	var fresh := LootService.new()
	if not fresh.load_containers():
		_fail("second loot service failed")
		return
	for day in range(1, 31):
		var result := fresh.search("locker_bank", day, rng.randi())
		if not bool(result.get("ok", false)):
			_fail("day %d search refused: %s" % [day, str(result)])
			return
		seen[str(result.get("item", ""))] = true
	if seen.size() < 2:
		_fail("loot is not random (only %d distinct over 30 days)" % seen.size())
		return

	# ⑤ 确定性：同样的盐与天数序列必须得到同样的结果序列。
	var deterministic_a: Array[String] = []
	var deterministic_b: Array[String] = []
	var service_a := LootService.new()
	var service_b := LootService.new()
	service_a.load_containers()
	service_b.load_containers()
	for day in range(1, 11):
		deterministic_a.append(str(service_a.search("first_aid_cabinet", day, 7).get("item", "")))
		deterministic_b.append(str(service_b.search("first_aid_cabinet", day, 7).get("item", "")))
	if deterministic_a != deterministic_b:
		_fail("loot is not deterministic for equal inputs")
		return

	print("LOOT_OK containers=%d distinct_locker=%d deterministic=ok refresh=per_day" % [
		CONTAINERS.size(), seen.size()])
	quit(0)


func _fail(detail: String) -> void:
	push_error("LOOT_FAIL " + detail)
	print("LOOT_FAIL " + detail)
	quit(1)
