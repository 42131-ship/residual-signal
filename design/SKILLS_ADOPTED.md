# 知识库调节记录（awesome-gamedev-agent-skills 接入）

> 这些不是「读过的文章」，是**改了我写法的条目**。每条都注明它落在哪个文件、被什么验证过。

---

## 一、本轮载入的两个 skill

| skill | 来源 | 为什么载 |
|---|---|---|
| `godot-tilemap-mastery` | thedivergentai/gd-agentic-skills | 我们要从 nodes.json 建 tile 地形，TileMapLayer 的 API 与坑不能靠猜 |
| `godot-shaders-basics` | 同上 | 手电光锥 + 真黑屏是气氛的第一根柱子 |

---

## 二、改变了写法的条目（已落地）

### 来自 shaders-basics

| 条目 | 落点 | 验证 |
|---|---|---|
| **不用 if/else 做动态选择，用 mix/smoothstep** | `flashlight.gdshader` 的 `lit = 1.0 - smoothstep(...)` | 编译通过、渲染正常 |
| **颜色 uniform 必须带色彩 hint** | `uniform vec4 outside_tint : source_color` | 见下方修正 |
| **TIME 要配 speed multiplier** | `uniform float flicker_speed` + `sin(TIME * flicker_speed * 6.2831853)` | 同上 |
| **移动不变量的计算到 vertex，fragment 只做插值** | 本 shader 无 vertex 可移（全屏 rect），记为下一批注意项 | — |

### 来自 tilemap-mastery

| 条目 | 落点 | 状态 |
|---|---|---|
| **动态角色绝不放进 TileMap** | 角色用独立 `Sprite2D`，与地形分离 | 已符合 |
| **别把世界坐标和 tile 坐标混用，用 `local_to_map` / `map_to_local`** | 当前用 `Sprite2D + region_rect`，坐标直接按 16 倍数算；转 TileMapLayer 时必须换 | 记为下一步 |
| **别在大循环里无脑 `set_cell`** | 现在 40×14 ≈ 560 个 Sprite；转 TileMapLayer 时改成 pattern/chunk 批 | 记为下一步 |
| **别每帧 `get_cell_tile_data()`** | 本场景不查 tile 元数据 | 已符合 |

---

## 三、被实现证伪的一条（skill 写的是概念名，不是 token）

> skill 原文：`NEVER forget hint_source_color for color uniforms`

我照写 `uniform vec4 x : hint_source_color`，Godot 直接报：

```
SHADER ERROR: Expected valid type hint after ':'.
```

**实际 token 是 `source_color`。** skill 用的是文档里的概念名。

> 记这条不是挑刺——是提醒：**skill 里的「术语」要到编译器那里核一遍再用**。
> 我这一轮就是因为照抄术语多跑了一次编译。

---

## 四、明确不采纳（及其理由）

| skill 建议 | 为什么不采纳 |
|---|---|
| **terrain autotile（地形自动拼接）** | 我们的房间是 16 个叙事节点，地形由 `nodes.json` 生成，没有「手绘有机边界」的需求 |
| **chunk streaming（大世界分块流式）** | 16 节点 / 40 格宽走廊，远不到需要分块 |
| **Y-sort / 等距深度排序** | 横版单轴，用不到 |
| **destructible tiles（可破坏 tile）** | 设计上没有「挖地形」，破坏只发生在**物件**上（门、柜），走交互不走在 tile |
| **ALPHA_SCISSOR 替代 discard** | 我们全是不透明像素图，没有半透边缘（R14 已经禁了） |

**记下来的意义**：这些不是「以后再说」，是**结构上不需要**。写进这里，下一次有人（或模型）提议时能直接引用。

---

## 五、已识别、下一轮该载的（按依赖）

| skill | 什么时候需要 | 触发条件 |
|---|---|---|
| `godot-2d-physics` | 走廊碰撞、门、`CharacterBody2D` | 从 Sprite 切到 TileMapLayer + 碰撞时 |
| `godot-camera-systems` | 相机限位、跟随、`limit_*` | 走廊超过一屏、需要跟随玩家时 |
| `godot-particles` | 枪口烟、灰尘、血 | 出武器系统时 |
| `godot-genre-horror` | 手电/雾/安全屋张力 | 做「90 秒试玩」前 |
| `godot-ui-theming` | HUD 从 ColorRect 升级为真主题 | UI 概念图落地时 |

---

## 六、本轮由 skill 影响而改的三处代码

1. `game/shaders/flashlight.gdshader` —— 全新，全屏乘法遮罩，`smoothstep` 无分支
2. `game/scenes/corridor.gd` —— 加 `_build_flashlight()` / `_update_flashlight()` / `_process()`
3. `game/scenes/corridor.gd` —— **HUD 的 CanvasLayer 提到 20**（遮罩在 10）
   > 这条不是 skill 教的，是渲染出来看到「DAY 3 也变黑了」才发现的

---

## 七、下一步要落进规则的（待编号）

从 skill 里提炼出、值得变成机器校验的两条：

- **声音与光的层级**：任何全屏后处理层必须声明 `layer`，且**不许压住 HUD**。
  （可以做成一条渲染自检：截图后检查 HUD 区域的平均亮度不低于某阈值）
- **术语要到编译器核**：skill / 文档里的 API 名写进代码前，先过 `--check-only`。
  这条已经是流程事实（我因此多跑一次编译），暂不立规则。
