重写 `game/tests/replay_30d.gd`。**只输出这一个 GDScript 文件**，不要解释、不要索要文件。

## 背景：上一版有 3 条「永远成立的假断言」，被评审点名

- 「六组变量在 [0,1]」——clamp 写在赋值里，测的是 clamp 函数本身
- 「sediment ≥ 0 且单调」——代码里只有 `+=`，没有减法分支
- 「L0 条目 event_id 非空」——构造时赋值，除非内存损坏不可能为空

**这一版只保留能失败的断言。**

## 形态

```gdscript
extends SceneTree
```

三个种子（1000 / 1001 / 1002）各跑一遍到 `world.day >= 30`。

## 循环（固定 11 小时一轮）

```
while world.day < 30:
    spend_time(1)      # 穿越一段主轴
    spend_time(2)      # 搜完一个节点
    add_noise(当前主轴节点, 2)
    result = pick_and_fire(当前节点, day*7+1)
    spend_time(8)      # 睡
```

## 四条断言（前三条是新的，都能真失败）

**① 时间算术精确成立**
每轮前记 `before_total = day*24 + hour`，轮后记 `after_total = day*24 + hour`，
断言 `after_total - before_total == 11`。
能失败于：跳日、双倍推进、计数器重置、`spend_time` 内部少算。

**② 一次性卡至多出现一次**
数据里 `returns_after_days == 0` 的卡是「只发生一次」。
统计整局每次 `result.get("fired")` 为真时返回的 `card_id`，
断言：任何 `returns_after_days == 0` 的卡，出现次数 ≤ 1。
能失败于：冷却逻辑失效（这是上一版真实存在的 bug）。

**③ 变量变化必须来自该卡的效果**
每轮 fire 前记下六组变量快照，fire 后对比。
对每一个**发生变化**的变量名 `k`，断言：该卡的 `effects` 里至少有一条 effect 的 `vars` 含键 `k`。
能失败于：引擎写入了卡里没声明的变量（比如硬编码扣物资）。

**④ 存读往返**（保留，它能失败）
`snapshot()` → `add_var("supplies", -0.1)` → `restore()` → 回到原值。

## 输出

- 全过 → `REPLAY_OK seeds=3 fired=<N> oneshot_max=<最大一次性卡出现次数>`，`quit(0)`
- 失败 → `REPLAY_FAIL seed=<n> invariant=<①|②|③|④> detail=<具体说明>`，`quit(1)`

## 硬要求

- `spend_time` / `add_var` / `set_var` 返回 **void**，不许取返回值
- 只用四个类：`DataLayer` / `WorldState` / `CardEngine` / `Memory`
- 循环变量显式标类型
- 必须能过：
  `.tools/Godot_v4.7-stable_win64_console.exe --headless --path . --check-only --script res://game/tests/replay_30d.gd`
- 并且真跑要输出 `REPLAY_OK …`
