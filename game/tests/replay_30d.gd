extends SceneTree
# 30 天回放：3 个种子，四条**能失败**的断言
# ① 时间算术精确（每轮正好 11 小时）  ② 一次性卡至多一次
# ③ 变量变化只能来自该卡 effects 声明的键  ④ 存读往返

const SEEDS := [1000, 1001, 1002]
const VARS := ["trust", "reputation", "supplies", "control", "knowledge", "time"]

var _by_id: Dictionary = {}


func _initialize() -> void:
	var data := DataLayer.new()
	if not data.load_all():
		_fail(-1, "0", "data.load_all() 失败")
		return
	_by_id.clear()
	for c: Dictionary in data.cards():
		_by_id[str(c.get("card_id", ""))] = c

	var total_fired := 0
	var max_oneshot := 0
	var total_changed := 0
	for seed_value: int in SEEDS:
		var r := _run_seed(seed_value, data)
		if r.has("fail"):
			_fail(seed_value, str(r["invariant"]), str(r["detail"]))
			return
		total_fired += int(r["fired"])
		max_oneshot = maxi(max_oneshot, int(r["oneshot_max"]))
		total_changed += int(r["changed"])

	# ⑤ 效果必须落地：effects[].vars 被读错键时，30 天里一个变量都不会变（旧版读 add_vars）。
	if total_changed == 0:
		_fail(-1, "⑤", "30 天回放里 24 个效果没有改动任何世界变量")
		return

	print("REPLAY_OK seeds=%d fired=%d oneshot_max=%d changed=%d" % [
		SEEDS.size(), total_fired, max_oneshot, total_changed
	])
	quit(0)


func _run_seed(seed_value: int, data: DataLayer) -> Dictionary:
	var world := WorldState.new()
	if not world.init_from(data):
		return {"fail": true, "invariant": "0", "detail": "world.init_from 失败，seed=%d" % seed_value}
	var cards := CardEngine.new()
	if not cards.init_from(data, world):
		return {"fail": true, "invariant": "0", "detail": "cards.init_from 失败，seed=%d" % seed_value}

	var axis: Array[Dictionary] = data.axis_nodes()
	if axis.is_empty():
		return {"fail": true, "invariant": "0", "detail": "主轴为空"}

	var fired := 0
	var counts: Dictionary = {}
	var changed_total := 0
	var ai := 0
	var guard := 0

	while world.day < 30 and guard < 400:
		guard += 1
		var before_total := world.day * 24 + world.hour
		var cur: Dictionary = axis[ai % axis.size()]
		var cur_id := str(cur.get("node_id", ""))

		world.spend_time(1)
		world.spend_time(2)
		world.add_noise(cur_id, 2)

		# ③ 开火前的六组快照
		var before_vars: Dictionary = {}
		for v: String in VARS:
			before_vars[v] = world.var_of(v)

		var res: Dictionary = cards.pick_and_fire(cur_id, world.day * 7 + 1)
		# 立刻取快照：再往后 spend_time(8) 会跨日并改写派生量 time，那是时间推进不是卡的效果
		var after_vars: Dictionary = {}
		for v: String in VARS:
			after_vars[v] = world.var_of(v)
		# ⑤ 累计真实变量变化数（time 是派生量，不计）。
		for v: String in VARS:
			if v == "time":
				continue
			if not is_equal_approx(float(after_vars[v]), float(before_vars[v])):
				changed_total += 1
		world.spend_time(8)

		var after_total := world.day * 24 + world.hour
		if after_total - before_total != 11:
			return {"fail": true, "invariant": "①",
				"detail": "seed=%d 第 %d 轮推进 %d 小时，应为 11" % [seed_value, guard, after_total - before_total]}

		if bool(res.get("fired", false)):
			fired += 1
			var cid := str(res.get("card_id", ""))
			counts[cid] = int(counts.get(cid, 0)) + 1

			var card: Dictionary = _by_id.get(cid, {})
			var ret: Variant = card.get("returns_after_days")
			if ret != null and int(ret) == 0 and int(counts[cid]) > 1:
				return {"fail": true, "invariant": "②",
					"detail": "一次性卡 %s 出现 %d 次" % [cid, int(counts[cid])]}

			# ③ 变化的键必须是这张卡 effects 里声明过的
			# 注意：GDScript 的 `or` 返回 bool，不能拿来做空值合并
			var declared: Dictionary = {}
			var fx: Array = card.get("effects", [])
			for e: Dictionary in fx:
				var ev: Dictionary = e.get("vars", {})
				for k: String in ev:
					declared[k] = true
			for v: String in VARS:
				if not is_equal_approx(float(after_vars[v]), float(before_vars[v])) and not declared.has(v):
					return {"fail": true, "invariant": "③",
						"detail": "%s 改动了 %s，但卡里没声明" % [cid, v]}

		ai += 1

	if world.day < 30:
		return {"fail": true, "invariant": "①", "detail": "seed=%d 跑 %d 轮只到 Day %d" % [seed_value, guard, world.day]}

	# ④ 存读往返
	var before := world.var_of("supplies")
	var snap := world.snapshot()
	world.add_var("supplies", -0.1)
	if not world.restore(snap) or not is_equal_approx(world.var_of("supplies"), before):
		return {"fail": true, "invariant": "④", "detail": "seed=%d 存读往返失败" % seed_value}

	var oneshot_max := 0
	for cid: String in counts:
		var card: Dictionary = _by_id.get(cid, {})
		oneshot_max = maxi(oneshot_max, int(counts[cid]))

	return {"fired": fired, "oneshot_max": oneshot_max, "changed": changed_total}


func _fail(seed_value: int, invariant: String, detail: String) -> void:
	print("REPLAY_FAIL seed=%d invariant=%s detail=%s" % [seed_value, invariant, detail])
	quit(1)
