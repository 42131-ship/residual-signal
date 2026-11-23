写 `game/runtime/card_engine.gd` —— Godot 4.x 事件卡引擎。**只输出这一个 GDScript 文件**，不要解释、不要多文件。

它把已有的两个类接起来：
```gdscript
var data: DataLayer
var world: WorldState
```

## 接口（名字固定）

```gdscript
class_name CardEngine extends RefCounted

signal card_fired(card_id: String, bind: Dictionary)
signal card_rejected(card_id: String, reason: String)

func init_from(d: DataLayer, w: WorldState) -> bool
func eligible(node_id: String) -> Array[Dictionary]
func bind_slots(card: Dictionary, seed_value: int) -> Dictionary
func fire(card: Dictionary, bind: Dictionary) -> Array[Dictionary]
func render(card: Dictionary, bind: Dictionary) -> String
func pick_and_fire(node_id: String, seed_value: int) -> Dictionary
```

## 条件求值（`eligible`）

一张卡命中当且仅当**全部**成立：
- `trigger.day.min` ≤ `world.day` ≤ `trigger.day.max`（字段缺省视为不限）
- `trigger.vars` 里每条：按 `name` 读 `world.var_of(name)`，用 `op`（`<=` `>=` `<` `>` `==`）比 `value`
- `trigger.node_tags_any` 非空时，节点 `tags` 与之有交集
- `trigger.node_ids` 非空时，`node_id` 在其中
- `trigger.sediment_min` 存在时，`world.sediment_of(node_id) >=` 它
- `trigger.requires_npc_alive == true` 时，至少一个 NPC `alive == true`（读 `data` 里已加载的 NPC 也行；没有就视为满足）

**`eligible` 只做筛选，不改任何状态。**

## 绑槽（`bind_slots`）

- 每个 slot 从 `options` 里**确定性地**选一个：用 `hash(card.card_id + "|" + slot.slot + "|" + str(seed_value))` 取模，**不许用 `randi()`**。
- 返回 `{slot_name: option_string}`。
- 同一个 `seed_value` 必须永远得到同一个结果。

## 触发（`fire`）

- 遍历 `effects`，**逐字比对** `effect.when` 与 `bind` 里某个已绑定的 option 值。
- 只对匹配上的执行：按 `effect.vars` 调 `world.add_var(k, v)`。
- 每条执行过的效果**产出一条待写 L0 的条目**，形如：
  ```gdscript
  {"event_id": effect.evidence, "card_id": card.card_id, "day": world.day, "bind": bind}
  ```
- 匹配不上任何绑定的效果**不发 signal 就直接跳过**（R39 已在离线保证它不会发生）。
- 返回这批 L0 条目。**不写文件、不改 world 的 day**——时间由调用方推进。

## 渲染（`render`）

把 `card.text.default` 里的 `{slot_name}` 用 `bind` 的值替换。缺槽就保留原样并 `push_warning`。返回 String。

## 选择并触发（`pick_and_fire`）

- `eligible` 里按 `card_id` 字典序取第一个（**确定性**，不做加权、不做随机）
- 没有可触发的卡 → 返回 `{"fired": false}`
- 有 → `bind_slots` → `fire` → 返回 `{"fired": true, "card_id": …, "text": render(...), "l0": [...]}`，并发 `card_fired`

## 硬要求

- 不写 `print`，只发 signal。
- 不直接读写 `data/` 文件——只通过 `DataLayer`。
- 不改 `world.day` / `world.hour`。
- 中文注释，短。循环变量显式标类型。
