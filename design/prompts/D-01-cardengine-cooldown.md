改动 `game/runtime/card_engine.gd`。**只输出完整文件**，不要解释、不要说明句、不要在开头写任何废话。

## 要修的两个已知缺陷

### ① `returns_after_days` 从未实现

卡片数据里有 `returns_after_days`：
- `0` = 只发生一次，之后永不触发
- `N` = 距上次触发至少 N 天

现在引擎完全忽略它，标着「只发生一次」的卡会天天触发。这是目前唯一会直接让玩法不对的缺口。

### ② `pick_and_fire` 按 `card_id` 字典序取第一个 → 卡池饥饿

同一张卡反复触发，别的永远轮不上。无头仿真里 12 张卡只触发了 4 张。

## 实现要求

```gdscript
var last_fired_day: Dictionary = {}   # card_id -> 上次触发的 world.day
var fire_count: Dictionary = {}       # card_id -> 累计次数
```

**`eligible(node_id)`** 增加过滤：
```
cid = card.card_id
if last_fired_day.has(cid):
    var ret = card.get("returns_after_days")
    if ret != null:
        if int(ret) == 0: continue                      # 一次性，永不再来
        if world.day - int(last_fired_day[cid]) < int(ret): continue
```

**`fire(card, bind)`** 末尾记录：
```
last_fired_day[card.card_id] = world.day
fire_count[card.card_id] = int(fire_count.get(card.card_id, 0)) + 1
```

**`pick_and_fire(node_id, seed_value)`** 选卡改成三档，全程确定性：
1. 优先**从未触发过**的卡（`not last_fired_day.has(cid)`），按 card_id 字典序取第一个
2. 都触发过 → 取 `last_fired_day` **最早**的那张（最久没出现）
3. 仍并列 → card_id 字典序

**不许用 `randi()`。** 同一个输入必须永远同结果。

其余接口、信号、条件求值、绑槽哈希、L0 条目结构**一律不许改**。

## 环境

Godot 4.7 已装：`.tools/Godot_v4.7-stable_win64_console.exe`
改完必须能过：
```
.tools/Godot_v4.7-stable_win64_console.exe --headless --path game --check-only --script res://runtime/card_engine.gd
```
注意 `world.spend_time()` / `world.set_var()` 返回 **void**，不许把它们的返回值赋给变量（上一轮 `main.gd` 就栽在这里）。
