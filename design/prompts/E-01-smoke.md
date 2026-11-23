写 `game/tests/smoke.gd` —— 无头冒烟测试。**只输出这一个 GDScript 文件**，不要解释、不要索要原文件。

## 形态

```gdscript
extends SceneTree

func _initialize() -> void:
    # 全部逻辑在这里跑完，最后 quit(0) 或 quit(1)
```

用 `godot --headless --path game --script res://tests/smoke.gd` 运行。**不许建窗口、不许要渲染。**

## 已有的类（签名固定，直接用）

```gdscript
class_name DataLayer extends RefCounted
func load_all(root: String = "res://data") -> bool
func nodes() -> Array[Dictionary]
func axis_nodes() -> Array[Dictionary]
func room_nodes() -> Array[Dictionary]
func node(id: String) -> Dictionary
func cards() -> Array[Dictionary]
func template(id: String) -> Dictionary
func profile(mode: String) -> Dictionary
func lexicon(key: String) -> Array
func loot_factor(day: int) -> float
func noise_sensitivity(day: int) -> float

class_name WorldState extends RefCounted
func init_from(d: DataLayer) -> bool
var day: int
var hour: int
func var_of(name: String) -> float
func add_var(name: String, delta: float) -> void      # void！
func set_var(name: String, value: float) -> void      # void！
func spend_time(hours: int) -> void                   # void！
func add_noise(node_id: String, base: int, night: bool = false) -> Dictionary
func sediment_of(node_id: String) -> int
func snapshot() -> Dictionary
func restore(s: Dictionary) -> bool

class_name CardEngine extends RefCounted
func init_from(d: DataLayer, w: WorldState) -> bool
func eligible(node_id: String) -> Array[Dictionary]
func pick_and_fire(node_id: String, seed_value: int) -> Dictionary

class_name Memory extends RefCounted
func init_from(d: DataLayer, w: WorldState) -> bool
func load_npcs(path: String = "res://data/npcs/npcs.json") -> bool
func fidelity_at(mem: Dictionary, day: int) -> int
func render(mem: Dictionary, day: int) -> String
```

## `_initialize()` 必须做的六步

1. 建四个对象，`data.load_all()` → 失败 `push_error` + `quit(1)` 返回
2. `world.init_from(data)` + `cards.init_from(data, world)` + `mem.init_from(data, world)` + `mem.load_npcs()`
3. **建拓扑**：遍历 `data.nodes()`，为每个节点建一个 `Node2D` 挂到根下，`position = Vector2(axis_x * 384, depth_layer * 216)`，`name` 用 node_id。统计主轴数、房间数
4. **跑 30 天**：循环直到 `world.day >= 30`：`spend_time(1)`（穿越一段）→ `spend_time(2)`（搜完一个节点）→ `add_noise(当前主轴节点, 2)` → `cards.pick_and_fire(当前节点, day*7+1)` → `spend_time(8)`（睡）。记录触发了哪些卡、L0 条目数
5. **存读往返**：`world.snapshot()` → `add_var("supplies", -0.1)` → `restore(snap)` → 断言 `var_of("supplies")` 回到原值
6. **打一行摘要并退出**：
   ```
   SMOKE_OK nodes=16 axis=5 rooms=11 day=30 fired=<N> l0=<N> sediment_max=<N> roundtrip=ok
   ```
   任何断言失败 → `push_error(...)` + `quit(1)`，摘要行改成 `SMOKE_FAIL <原因>`

## 硬要求

- **`spend_time` / `add_var` / `set_var` 返回 void，不许取返回值**（上一轮 `main.gd` 就栽在这里）
- 中文注释，短
- 不用 `print`，用 `print` 也行——这是测试脚本，允许（不走运行时规范）
- 必须能过：
  `.tools/Godot_v4.7-stable_win64_console.exe --headless --path game --check-only --script res://tests/smoke.gd`
