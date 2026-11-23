改两个文件。**分别用 `<<<FILE: 路径 >>>` 分隔**，只输出文件内容，不要解释。

## 文件一：`game/tests/smoke.gd`（改写，修一个计数 bug）

现状：`smoke.gd` 能跑通，输出
```
SMOKE_OK nodes=16 axis=5 rooms=11 day=30 fired=66 sediment_max=14 roundtrip=ok
```
但 **`l0=0` 是错的** —— 单独探针证明 `card_engine.fire()` 确实会返回 L0 条目（`不开门` 命中时返回 1 条）。
所以是 smoke 自己的计数写错了：它把 `pick_and_fire()` 返回字典里的某个字段当成了数量，或者累加了一个从未自增的变量。

**修法**：每次 `pick_and_fire` 后取 `res.get("l0", [])` 的 `size()` 累加到 `l0_total`；摘要行加 `l0=<l0_total>`。
其余逻辑与摘要格式保持不变（`SMOKE_OK …` / `SMOKE_FAIL <原因>`）。

## 文件二：`game/tests/replay_30d.gd`（新增）

```gdscript
extends SceneTree
```

用 `godot --headless --path . --script res://game/tests/replay_30d.gd` 跑。
**三个种子各跑一遍完整 30 天**（种子 1000 / 1001 / 1002），每个种子结束后断言五条不变量：

1. 六组变量全部落在 `[0,1]`
2. 所有节点 `sediment >= 0`，且**只增不减**（每步记录上一次的值，变小就报错）
3. `world.day` 单调不减，结束时 `>= 30`
4. 每条 L0 条目都有非空 `event_id`
5. 存读往返：`snapshot()` → `add_var("supplies", -0.1)` → `restore()` → `var_of("supplies")` 回到原值

跑法（每个种子）：
```
while world.day < 30:
    spend_time(1)                       # 穿越一段主轴
    spend_time(2)                       # 搜完一个节点
    add_noise(当前主轴节点, 2, night)
    cards.pick_and_fire(当前节点, day*7+1)
    spend_time(8)                       # 睡
```

输出：
- 全部通过 → `REPLAY_OK seeds=3 days=30 fired=<N> l0=<N> sediment_max=<N>` 然后 `quit(0)`
- 任一条失败 → `REPLAY_FAIL seed=<n> invariant=<编号> detail=<说明>` 然后 `quit(1)`

## 硬要求

- `spend_time` / `add_var` / `set_var` 返回 **void**，不许取返回值
- 只用已存在的四个类：`DataLayer` / `WorldState` / `CardEngine` / `Memory`（`game/runtime/` 下）
- 循环变量显式标类型
- 必须都能过：
  `--headless --path . --check-only --script res://game/tests/smoke.gd`
  `--headless --path . --check-only --script res://game/tests/replay_30d.gd`
