写 `game/runtime/world_state.gd` —— Godot 4.x 的世界状态仓库。**只输出这一个 GDScript 文件**，不要解释、不要多文件。

它依赖已经存在的 `DataLayer`（`game/runtime/data_layer.gd`），用 `var data: DataLayer` 持有，不自己读文件。

## 接口（名字固定）

```gdscript
class_name WorldState extends RefCounted

signal changed(var_name: String, old_value: float, new_value: float)
signal day_advanced(day: int)
signal sediment_changed(node_id: String, delta: int)

var data: DataLayer
var variables: Dictionary   # 只有六组：trust / reputation / supplies / control / knowledge / time，值域 0..1
var day: int                # 世界日 0..30
var hour: int               # 0..23
var sediment: Dictionary    # node_id -> int
var locked_until: Dictionary  # node_id -> day（day_locked_after）

func init_from(d: DataLayer) -> bool
func var_of(name: String) -> float
func add_var(name: String, delta: float) -> float           # clamp 0..1，值变了才发 changed
func set_var(name: String, value: float) -> void
func spend_time(hours: int) -> void                          # 推进 hour/day，跨日发 day_advanced
func advance_day() -> void
func add_noise(node_id: String, base: int, night: bool = false) -> Dictionary
func sediment_of(node_id: String) -> int
func can_enter(node_id: String) -> bool                      # 过 day_locked_after
func snapshot() -> Dictionary
func restore(s: Dictionary) -> bool
func day_index() -> int                                      # 0..30
```

## 六条硬规则

1. **`variables` 只许有六组键**。`add_var` 收到别的名字直接 `push_error` 并返回当前值，不写进去。
2. **`time` 是派生量**：`time = clamp(float(day) / 30.0, 0, 1)`，由 `advance_day()` 自动写入；调用方不许直接 `add_var("time", …)`（收到就忽略并 `push_warning`）。
3. **时间由「落地」推进，不由秒**：`spend_time(hours)` 是唯一入口。给 `spend_time` 传 0 或负数要报错。
4. **噪声传导**：`add_noise` 写本节点，同时按 `linked_nodes` 给**相邻节点**写 `base / 2`（整数除法向下取整，最小 1）。系数来自 `data.noise_sensitivity(day)`；`night == true` 再乘 `mode_profile.story.night_multiplier`。返回 `{ "self": delta, "neighbors": {node_id: delta} }`。
5. **沉积只增不减**：任何路径都不许让 `sediment[n]` 变小。`restore` 时若快照里的值更小，取较大者。
6. **`can_enter`**：节点有 `day_locked_after` 且 `day > day_locked_after` 时返回 `false`。

## 快照

`snapshot()` 返回可直接 `JSON.stringify` 的字典：`{"day","hour","variables","sediment"}`。
`restore()` 要能拒绝坏数据（缺键、变量越界、sediment 变小），拒绝时返回 `false` 且**不改动当前状态**（先校验后提交）。

## 硬要求

- 中文注释，短。
- 不写 `print`，只发 signal。
- 所有循环变量显式标类型（`for k: String in …`）。
- 不引任何 `@onready` / 节点路径——这是纯 `RefCounted`。
