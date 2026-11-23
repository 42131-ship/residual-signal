写 `game/runtime/card_engine.gd` —— Godot 4.x 事件卡引擎。**只输出完整 GDScript 文件**，不要解释、不要说明句、不要在开头写任何废话。**你有足够信息直接写，不要索要原文件。**

## 依赖（已存在，签名如下）

```gdscript
class_name DataLayer extends RefCounted
func cards() -> Array[Dictionary]
func node(id: String) -> Dictionary
func nodes() -> Array[Dictionary]

class_name WorldState extends RefCounted
var day: int
func var_of(name: String) -> float
func add_var(name: String, delta: float) -> void      # 返回 void！不许取返回值
func sediment_of(node_id: String) -> int
```

## 接口（名字固定）

```gdscript
class_name CardEngine extends RefCounted

signal card_fired(card_id: String, bind: Dictionary)
signal card_rejected(card_id: String, reason: String)

var data: DataLayer
var world: WorldState
var last_fired_day: Dictionary = {}
var fire_count: Dictionary = {}

func init_from(d: DataLayer, w: WorldState) -> bool
func eligible(node_id: String) -> Array[Dictionary]
func bind_slots(card: Dictionary, seed_value: int) -> Dictionary
func fire(card: Dictionary, bind: Dictionary) -> Array[Dictionary]
func render(card: Dictionary, bind: Dictionary) -> String
func pick_and_fire(node_id: String, seed_value: int) -> Dictionary
```

## 条件求值（`eligible`）

一张卡命中当且仅当**全部**成立（缺省字段视为不限）：
- `trigger.day.min` ≤ `world.day` ≤ `trigger.day.max`
- `trigger.vars` 每条：按 `name` 读 `world.var_of(name)`，用 `op`（`<=` `>=` `<` `>` `==`）比 `value`
- `trigger.node_tags_any` 非空时，节点 `tags` 与之有交集
- `trigger.node_ids` 非空时，`node_id` 在其中
- `trigger.sediment_min` 存在时，`world.sediment_of(node_id) >=` 它
- `trigger.requires_npc_alive == true` 时放行（NPC 存活由上层保证）

**再加一条冷却过滤（本次新增，很重要）：**

```
var cid: String = str(card.get("card_id",""))
if last_fired_day.has(cid):
    var ret: Variant = card.get("returns_after_days")
    if ret != null:
        if int(ret) == 0:
            continue                                   # 一次性卡：永不再来
        if world.day - int(last_fired_day[cid]) < int(ret):
            continue
```

`eligible` 只筛选，**不改任何状态**。

## 绑槽（`bind_slots`）

每个 slot 从 `options` 确定性选一个：`hash(card.card_id + "|" + slot.slot + "|" + str(seed_value))` 对 `options.size()` 取模。**禁止 `randi()`。** 返回 `{slot_name: option_string}`。

## 触发（`fire`）

- 遍历 `effects`，**逐字比对** `effect.when` 与 `bind` 里任意已绑定的值
- 命中才执行：`world.add_var(k, float(v))`（**不要取返回值**）
- 每条执行过的效果产出一条：`{"event_id": effect.evidence, "card_id": card.card_id, "day": world.day, "bind": bind}`
- 末尾记录 `last_fired_day[cid] = world.day`，`fire_count[cid] = int(fire_count.get(cid,0)) + 1`
- 返回这批 L0 条目。**不写文件、不改 world.day**

## 渲染（`render`）

`card.text.default` 里的 `{slot}` 用 `bind` 的值替换；缺槽保留原样并 `push_warning`。返回 String。

## 选择并触发（`pick_and_fire`）

三档，全程确定性：
1. 优先**从未触发过**的卡（`not last_fired_day.has(cid)`），按 `card_id` 字典序取第一个
2. 都触发过 → 取 `last_fired_day` **最早**的那张
3. 仍并列 → `card_id` 字典序

无可触发 → 返回 `{"fired": false}`；否则 `bind_slots` → `fire` → 返回 `{"fired": true, "card_id": ..., "text": render(...), "l0": [...]}` 并发 `card_fired`。

## 硬要求

- 不写 `print`，只发 signal
- 不直接读写 `data/` 文件，只通过 `DataLayer`
- 不改 `world.day` / `world.hour`
- 中文注释，短；循环变量显式标类型（`for s: Dictionary in ...`）
- 必须能过：
  `.tools/Godot_v4.7-stable_win64_console.exe --headless --path game --check-only --script res://runtime/card_engine.gd`
