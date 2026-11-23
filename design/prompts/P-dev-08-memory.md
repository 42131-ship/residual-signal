写 `game/runtime/memory.gd` —— Godot 4.x 的记忆层读取侧。**只输出这一个 GDScript 文件**，不要解释、不要多文件、不要在正文前写任何说明句。

## 它做什么

数据里的记忆是**满格**的（`slots` 五槽齐全、`fidelity = 3`、`fidelity_trace` 描述衰减，见 R36）。
运行时**不许改记录**，只在**读取时**按当日算出保真度并降级措辞。这是「模糊 ≠ 撒谎」唯一落地点。

```gdscript
class_name Memory extends RefCounted

signal degraded(npc_id: String, event_id: String, from_fid: int, to_fid: int)

var data: DataLayer
var world: WorldState
var npcs: Array[Dictionary]

func init_from(d: DataLayer, w: WorldState) -> bool
func load_npcs(path: String = "res://data/npcs/npcs.json") -> bool
func fidelity_at(mem: Dictionary, day: int) -> int
func render(mem: Dictionary, day: int) -> String
func recallable(npc_id: String, day: int) -> Array[Dictionary]
func cite(mem: Dictionary) -> PackedStringArray
func affect_at(npc_id: String) -> float
```

## `fidelity_at(mem, day)` —— 纯函数，不改状态

走 `fidelity_trace`，取**最后一条 `day <= 当日`** 的 `fidelity`。
若当日早于 trace 首条，返回 trace 首条的 `fidelity`。
若 trace 为空，返回 `mem.fidelity`。
同一 `day` 反复调用必须同值。

## `render(mem, day)` —— 分档，不许造新事实

| fidelity | 允许出现的槽 | 句式 |
|---|---|---|
| 3 | `who` `what` `where` `manner` `outcome` | 一句完整叙述，具体 |
| 2 | `who` `what` `where` | 具体事件仍在，**`manner` 与 `outcome` 必须消失** |
| 1 | `who` + `what` 的概括 | `what` 只许保留**类别词**（如「给了东西」），不许保留具体物件名 |
| 0 | 只有 `affect` | 一句情绪残影，**不许出现任何具体名词** |

硬规则：
1. **不许输出 `slots` 里没有的名词。** 这是一条硬线：多补一个细节（"你当时戴着帽子"）沉浸当场破功。
2. `kind == "heard"` 时，句首必须带传闻标记（如「听人说」），且必须保留 `via` 的痕迹（「听 X 说的」）。
3. fidelity 0 时 `affect > 0` 用「那阵子还有人肯给东西」这类，`affect < 0` 用「有人拿走过什么」这类——**不点名、不指事**。
4. 返回 String，不许返回空串；实在写不出就用最模糊的那一档。

## `recallable(npc_id, day)`

返回该 NPC 当前（day）能想起来、且 `fidelity_at >= 1` 的记忆数组（fidelity 0 的只在被直接问到时才出，不进主动回忆）。
`hops > 2` 的一律不进。

## `cite(mem)`

返回 `PackedStringArray`，内容是这条记忆能指回的 L0 事件 id：至少有 `mem.source_event`；若 `mem.via` 存在且 `data` 里能查到对应 NPC，再加上其 `source_event`（最多一层）。**这是「每句模糊话都能被证真」的机械保证。**

## 硬要求

- 不写 `print`，只发 signal。
- 不改 `mem` 里任何字段（传进来的 Dictionary 只能读）。
- 中文注释，短。循环变量显式标类型。
- 降级时（同一 npc/event 首次算出的 fidelity 低于上一次被问到时）发 `degraded`。
