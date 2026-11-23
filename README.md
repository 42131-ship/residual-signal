# 残余信号 · Residual Signal

横版 2D 生存恐怖原型。原生分辨率 **384×216**（×5 = 1920×1080），16px 栅格，最近邻缩放，32 色调色板按角色分配。

Godot **4.7**（GL Compatibility 渲染器）+ GDScript；数据与资产管线是 Python。

---

## 快速开始

```powershell
# 1) 引擎：把 Godot 4.7 放到仓库根的 .tools/（该目录不入库）
#    .tools/Godot_v4.7-stable_win64.exe
#    .tools/Godot_v4.7-stable_win64_console.exe

# 2) 导入资源（首次或新增 PNG 之后必须先跑，否则报 No loader found）
.tools/Godot_v4.7-stable_win64_console.exe --headless --path . --import

# 3) 打开工程
.tools/Godot_v4.7-stable_win64.exe --path .
```

主场景是 `game/scenes/corridor.tscn`。走廊里 `A/D` 或方向键移动，`Shift` 慢走，靠近道具按 `E` 查看，`Esc` / `E` 关闭。

---

## 目录结构

| 路径 | 内容 |
|---|---|
| `game/scenes/` | 走廊场景、玩家控制器、道具场景 |
| `game/runtime/` | 数据层、世界状态、卡牌引擎、记忆、主壳 |
| `game/ui/` | 点阵字体渲染类 `PixelFont` |
| `game/tests/` | 场景/冒烟/回放测试（`*_OK` 行即通过） |
| `game/shaders/` | 手电遮罩等着色器 |
| `data/` | 拓扑、模板、卡池、NPC、日历、道具检查文本（JSON，单一数据源） |
| `art/` | 调色板、参考图、字体构建素材、`generated_candidates/` 运行资源 |
| `design/` | 规格、决策（DEC）、提案、派单、交接文档 |
| `tools/` | 资产构建、像素门禁、规则校验、批量脚本 |
| `schema/` | 存档 schema 与迁移样例 |

`art/generated_candidates/` 是**运行必需**资源（名字里的 generated 指的是由 `tools/` 重建），不要删除。

---

## 校验与构建

```powershell
# 静态规则（43 条）
python tools/validate.py

# 规则自测
python tools/selftest.py

# 像素门禁（单帧 ≤16 色、二值 alpha、网格对齐）
python tools/pixelpipe.py gate art/generated_candidates/props/stage1/PROP-02_01_locker_bank.png `
  --palette art/palettes/master.gpl --max-colors 16

# 重建 15 件学校道具（会重写 corridor_props.tscn 与 props.json）
python tools/prop_build.py

# 重建点阵字库（PF-01 HUD / PF-02 中文检查文本）
python tools/font_build.py

# Godot 侧
$G = ".tools/Godot_v4.7-stable_win64_console.exe"
& $G --headless --path . --check-only --script res://game/scenes/corridor.gd
& $G --headless --path . --script res://game/tests/smoke.gd
& $G --headless --path . --script res://game/tests/replay_30d.gd
# 走廊截图回归（需要图形渲染，不能加 --headless）
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_preview.gd -- CORRIDOR-QA
```

---

## 当前进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| — | 数据层 / 43 条规则 / 资产管线 | 已通过 |
| Stage 1 | 15 件学校环境物件、走廊几何、相机与手电 | 已签核 |
| Stage 2 | 道具细节、24px 角色可读、检查文本框、移动速度 | 进行中（待视觉签核） |
| Stage 3 | 地面接缝 / 磨损 / 散落物 | 未开始 |
| Stage 4 | 前景遮挡与玩家可读性 | 未开始 |
| Stage 5 | 参照精品 2D 生存恐怖重构 HUD | 未开始 |

逐阶段验收记录与已知欠账见 [`design/HANDOFF.md`](design/HANDOFF.md) 与 [`design/HANDOFF-STAGE2.md`](design/HANDOFF-STAGE2.md)。

---

## 字体与第三方授权

- `art/fonts/NotoSansSC-VF.ttf`：Noto Sans SC，**SIL OFL 1.1**，原文见 [`art/fonts/NOTOSANS-SC-OFL.txt`](art/fonts/NOTOSANS-SC-OFL.txt)。
  它只作为 `tools/font_build.py` 的**构建输入**，游戏运行时只读生成的 PNG 图集。
- 说明与待办见 [`art/fonts/NOTICE.md`](art/fonts/NOTICE.md)，机读账本见 [`THIRD_PARTY_LICENSES.json`](THIRD_PARTY_LICENSES.json)。

## 不入库的东西

`.tools/`（引擎本体）、`.godot/`（导入缓存）、`logs/`、`config/agents.json`（本机 API 配置）、
`.gdskills/`、`.tmp_vision/`、`_crops/`（视觉分析临时产物）。完整规则见 [`.gitignore`](.gitignore)。
