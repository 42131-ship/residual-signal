写 `game/runtime/data_layer.gd` —— Godot 4.x 的纯数据层。**只输出这一个 GDScript 文件**，不要解释、不要多文件。

## 它是什么

运行时唯一的读盘点。它不碰渲染、不碰输入、不碰存档写入。继承 `RefCounted`，可在 `--headless` 下单测。

## 必须加载的文件

```
res://data/world_calendar.json     七关键帧 × 九字段（day/loot/noise_sensitivity/power/broadcast…）
res://data/mode_profile.json       story / endless / shared 三段
res://data/nodes.json              {"template":"school","nodes":[...]}（也可能直接是数组，两种都要吃）
res://data/lexicon.json            node_names / tags / loot_tables / noise_events / template_exclusive_names
res://data/cards/layer_l.json      {"cards":[...]}（也可能直接是数组）
res://data/templates/school.json   entry_days / weapon_budget / noise_budget / safehouse_failure
```

## 接口（名字固定，别改）

```gdscript
class_name DataLayer extends RefCounted

signal load_failed(rule: String, detail: String)

func load_all(root: String = "res://data") -> bool
func node(id: String) -> Dictionary                 # 不存在返回 {}
func nodes() -> Array[Dictionary]
func axis_nodes() -> Array[Dictionary]              # role == "axis"
func room_nodes() -> Array[Dictionary]              # role == "room"
func calendar_at(day: int) -> Dictionary            # 返回插值后的当日状态
func loot_factor(day: int) -> float                 # 当日物资系数
func noise_sensitivity(day: int) -> float
func cards() -> Array[Dictionary]
func template(id: String) -> Dictionary
func profile(mode: String) -> Dictionary            # "story" | "endless"
func lexicon(key: String) -> Array                  # "tags" / "loot_tables" / ...
func is_template_exclusive(word: String) -> bool    # R26 用
func template_exclusive_hits(text: String) -> PackedStringArray
```

## 运行时要做的七条检查（不通过就 load_failed 并返回 false）

1. 节点 id 全局唯一，且匹配 `^[a-z0-9_]+$`
2. `role == "axis"` 的节点 `axis_x` 从 0 连续，且每段只有一个
3. 每个 `role == "room"` 的节点，`linked_nodes` 里只能有一个不同的 `axis_x`（否则可绕过主轴威胁）
4. 链接对称：A→B 则 B→A
5. 至少一个 `lockable`
6. 所有 `loot_table` / `tags` / `noise_events` 的引用都在 lexicon 里
7. `template_exclusive_names` 非空（为空则 R26 形同虚设，报 warn 但继续）

## 日历插值

关键帧之间**数值线性插值**，枚举字段（`power` / `broadcast` / `behavior` / `pattern`）**保持前一帧直到下一帧**。`calendar_at(4)` 必须能同时给出 4 日的数值与 3 日的枚举。

## 硬要求

- 中文注释，短。
- 不写 `print`，只发信号。
- 不用 `class_name` 之外的全局单例。
- JSON 解析失败要给出行号提示，不要只抛异常。
- 数组类型用 `Array[Dictionary]` 显式标注。
