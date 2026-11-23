写 `game/tools/node_view.gd` —— **只读**节点拓扑可视化（DEC-20261123-D1 的附加条件）。

**只输出这一个 GDScript 文件**，不要解释、不要索要文件。你可以直接写，因为下面给了全部 API。

## 它不是编辑器

它只**看**，不改 `data/nodes.json`。一旦它能写，它就变成第二个权威，D1 决策的前提当场消失。
这条要写进文件头注释。

## 形态

```gdscript
extends Node2D
```

挂在一个 `Node2D` 场景根上，用 `_draw()` 画。用 `godot --path . --headless` 跑不通（没有渲染），
但要求它在 `--headless` 下**不报错**（`_draw` 不会被调用，`_ready` 要能安全执行）。

## 数据来源

```gdscript
var data := DataLayer.new()      # res://game/runtime/data_layer.gd
data.load_all()                  # 返回 bool

data.nodes() -> Array[Dictionary]     # 每项含 node_id / role / axis_x / depth_layer / lockable / tags / linked_nodes
data.axis_nodes() -> Array[Dictionary]
data.room_nodes() -> Array[Dictionary]
```

## 画什么

**网格**：`axis_x * 384` 横，`depth_layer * 216` 纵（和 smoke.gd 建的坐标系一致）。
每个格子画一个 64×64 的方框，颜色按 `depth_layer` 分：`+1` 冷灰、`0` 中性、`-1` 更暗。

**节点方块**：
- `role == "axis"` → 宽 96 高 24 的横条，颜色偏橙
- `role == "room"` → 48×48 方块
- `lockable == true` → 额外画一圈亮框
- 有 `teaching_*` tag → 在角上画一个小点

**连线**：遍历 `linked_nodes`，从该节点中心画一条 1px 线到目标节点中心；`role == "axis"` 之间的连线画亮一点。

**文字**：在每个方块下方 `draw_string` 打 `node_id`（用 `ThemeDB.fallback_font`，字号 8）。

## 交互（可选，做了更好）

- `_unhandled_input`：方向键平移 `position`，`+`/`-` 缩放（`scale`）
- 不许写文件、不许改任何数据

## 硬要求

- 中文注释，短
- 不写 `print`
- 必须能过：
  `.tools/Godot_v4.7-stable_win64_console.exe --headless --path . --check-only --script res://game/tools/node_view.gd`
- 并且 `--headless --path . --script` 方式加载时不能崩（`_ready` 里加保护：`data.load_all()` 失败就 `push_error` 后直接返回）
