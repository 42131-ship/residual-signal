改写 `game/tests/smoke.gd` 并新增 `game/tests/replay_30d.gd`。
**你用 `<<<FILE: game/tests/smoke.gd >>>` 和 `<<<FILE: game/tests/replay_30d.gd >>>` 分隔两个文件。**
两个文件的**完整内容**都要给出。不要解释、不要说明句、不要索要任何文件——下面已经把原文贴给你了。

## 现状：smoke.gd 有两个计数 bug（原文在最后）

跑出来是 `fired=66 l0=0`。两句都错：

1. **`l0_count` 读错了地方**（第 78 行）：
   ```gdscript
   var l0_count := data.lexicon("L0").size()
   ```
   lexicon 里没有 "L0" 这个键，永远是 0。
   正确做法：每次 `cards.pick_and_fire(...)` 后取 `result.get("l0", [])` 的 `size()` 累加。

2. **`fired` 统计的是「尝试次数」不是「触发次数」**（第 73–74 行）：
   `pick_and_fire` 没有可触发卡时返回 `{"fired": false}`，也是非空字典。
   正确做法：判 `result.get("fired", false) == true` 才 `fired += 1`。

其余逻辑保持不变，摘要格式不变（`SMOKE_OK …` / `SMOKE_FAIL <原因>`），摘要里保留 `l0=<总数>`。

## 新增 replay_30d.gd 的要求

```gdscript
extends SceneTree
```

三个种子（1000 / 1001 / 1002）各跑一遍完整 30 天，每个种子断言五条不变量：
1. 六组变量全在 `[0,1]`（六组名：`trust` `reputation` `supplies` `control` `knowledge` `time`）
2. 所有节点 `sediment >= 0`，且**只增不减**（每步与上一次比较）
3. `world.day` 单调不减，结束 `>= 30`
4. 每条 L0 条目都有非空 `event_id`（从 `pick_and_fire` 返回的 `l0` 里收集）
5. 存读往返：`snapshot()` → `add_var("supplies", -0.1)` → `restore()` → 回到原值

每个种子的循环（和 smoke 一样）：
```
while world.day < 30:
    spend_time(1); spend_time(2)
    add_noise(当前主轴节点, 2, night)
    result = pick_and_fire(当前节点, day*7+1)
    spend_time(8)
```

输出：
- 全过 → `REPLAY_OK seeds=3 days=30 fired=<N> l0=<N> sediment_max=<N>`，`quit(0)`
- 任一失败 → `REPLAY_FAIL seed=<n> invariant=<编号> detail=<说明>`，`quit(1)`

## 硬要求

- `spend_time` / `add_var` / `set_var` 返回 **void**，不许取返回值
- 只用这四个类：`DataLayer` / `WorldState` / `CardEngine` / `Memory`
- 循环变量显式标类型
- 两个文件都必须能过 `--headless --path . --check-only --script res://game/tests/<名字>.gd`

---

## 现有 `game/tests/smoke.gd` 全文（96 行）

```gdscript
extends SceneTree

func _initialize() -> void:
	var data := DataLayer.new()
	var world := WorldState.new()
	var cards := CardEngine.new()
	var mem := Memory.new()

	if not data.load_all():
		push_error("SMOKE_FAIL data.load_all() 失败")
		print("SMOKE_FAIL data.load_all() 失败")
		quit(1)
		return

	if not world.init_from(data):
		push_error("SMOKE_FAIL world.init_from() 失败")
		print("SMOKE_FAIL world.init_from() 失败")
		quit(1)
		return
	if not cards.init_from(data, world):
		push_error("SMOKE_FAIL cards.init_from() 失败")
		print("SMOKE_FAIL cards.init_from() 失败")
		quit(1)
		return
	if not mem.init_from(data, world):
		push_error("SMOKE_FAIL mem.init_from() 失败")
		print("SMOKE_FAIL mem.init_from() 失败")
		quit(1)
		return
	if not mem.load_npcs():
		push_error("SMOKE_FAIL mem.load_npcs() 失败")
		print("SMOKE_FAIL mem.load_npcs() 失败")
		quit(1)
		return

	var all_nodes: Array[Dictionary] = data.nodes()
	var axis_nodes: Array[Dictionary] = data.axis_nodes()
	var room_nodes: Array[Dictionary] = data.room_nodes()
	var axis_count := 0
	var room_count := 0

	for node_data in all_nodes:
		var node_id := str(node_data.get("node_id", node_data.get("id", "")))
		var node_2d := Node2D.new()
		node_2d.name = node_id
		node_2d.position = Vector2(
			float(node_data.get("axis_x", 0.0)) * 384.0,
			float(node_data.get("depth_layer", 0.0)) * 216.0
		)
		get_root().add_child(node_2d)

		if bool(node_data.get("is_axis", false)) or axis_nodes.any(func(item: Dictionary) -> bool: return str(item.get("node_id", item.get("id", ""))) == node_id):
			axis_count += 1
		if bool(node_data.get("is_room", false)) or room_nodes.any(func(item: Dictionary) -> bool: return str(item.get("node_id", item.get("id", ""))) == node_id):
			room_count += 1

	if all_nodes.is_empty() or axis_nodes.is_empty():
		push_error("SMOKE_FAIL 节点或主轴为空")
		print("SMOKE_FAIL 节点或主轴为空")
		quit(1)
		return

	var fired := 0
	var axis_index := 0
	while world.day < 30:
		var current := axis_nodes[axis_index % axis_nodes.size()]
		var current_id := str(current.get("node_id", current.get("id", "")))

		world.spend_time(1)
		world.spend_time(2)
		world.add_noise(current_id, 2)
		var result := cards.pick_and_fire(current_id, world.day * 7 + 1)
		if not result.is_empty():
			fired += 1
		world.spend_time(8)
		axis_index += 1

	var l0_count := data.lexicon("L0").size()
	var sediment_max := 0
	for node_data in all_nodes:
		var node_id := str(node_data.get("node_id", node_data.get("id", "")))
		sediment_max = maxi(sediment_max, world.sediment_of(node_id))

	var before := world.var_of("supplies")
	var snap := world.snapshot()
	world.add_var("supplies", -0.1)
	if not world.restore(snap) or not is_equal_approx(world.var_of("supplies"), before):
		push_error("SMOKE_FAIL supplies 存读往返失败")
		print("SMOKE_FAIL supplies 存读往返失败")
		quit(1)
		return

	print("SMOKE_OK nodes=%d axis=%d rooms=%d day=%d fired=%d l0=%d sediment_max=%d roundtrip=ok" % [
		all_nodes.size(), axis_count, room_count, world.day, fired, l0_count, sediment_max
	])
	quit(0)
```
