写 `game/runtime/main.gd` —— Godot 4.x 的最小游戏壳。**只输出这一个 GDScript 文件**，不要解释、不要多文件。

它把已有的两个类接起来跑一个闭环：
```gdscript
var data: DataLayer      # game/runtime/data_layer.gd
var world: WorldState    # game/runtime/world_state.gd
```

## 接口（名字固定）

```gdscript
extends Node
class_name GameShell

signal loop_done(ok: bool, report: String)

func _ready() -> void
func run_minimal_loop() -> void          # 下面五步
func save_game(path: String = "user://save_01.json") -> bool
func load_game(path: String = "user://save_01.json") -> bool
func new_game(template_id: String = "school", entry_day: int = 0) -> bool
```

## `run_minimal_loop()` 必须做的五步

1. `data.load_all()` → 失败就 `loop_done(false, "load_failed: ...")` 并返回
2. `world.init_from(data)` → 失败同理
3. `new_game("school", 0)` 开局：设 `day = entry_day`、`hour = 8`、六组变量给一个初值（`supplies 0.8`、`trust 0.3`、`knowledge 0.5`、其余 0），并 `world.add_var("time", …)` 不许直接调（time 是派生量）
4. **走一步 + 一次行动**：`spend_time(1)` 表示穿越一段主轴；然后 `spend_time(2)` 表示搜完一个节点，同时 `add_noise("school_corridor_b", 2)`；再 `sediment_of("school_corridor_b")` 读回
5. **存读往返**：`save_game()` → 改一点状态（`world.add_var("supplies", -0.1)`）→ `load_game()` → 断言 `snapshot()` 回到存档时的值。往返不一致就 `loop_done(false, "save_roundtrip_mismatch")`

全部通过 → `loop_done(true, "…")`，report 里带一行摘要（世界日、小时、supplies、corridor_b 沉积、六组变量是否落 0..1）。

## 硬要求

- 允许 `print`，但**只许在 `_dev_log(msg)` 这一个函数里**，别处一律走 signal。
- 存读用 `FileAccess` + `JSON.stringify(world.snapshot())`；读回来先 `world.restore()`，返回 `false` 时不许改动现状。
- 不建场景、不加子节点、不 `@onready`、不引 `res://` 之外的资源。
- 中文注释，短。
- 任何一步失败都要能说清**是哪一步、哪个 id**，不许只返回 false。
