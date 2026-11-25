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

主场景是 `game/scenes/main_menu.tscn`（`新游戏` / `继续` 都会切到 `game/scenes/corridor.tscn`）。走廊分成 **A 区 / B 区 / C 区** 三个房间区块（带可开关/上锁的门）；
玩家实际看到的是 **1920×1080**（原生 384×216 的 5× 整数最近邻放大，见 `game/tests/display.gd`）。
完整键位见 [`design/CONTROLS.md`](design/CONTROLS.md)：

| 键 | 动作 |
|---|---|
| `W` `A` `S` `D` / 方向键 | 移动（`A/D` 横轴，`W/S` 纵深走进下方房间） |
| 不按速度键 | 步行（24 px/s） |
| `Shift`（按住） | 疾跑（44 px/s，逃跑用，噪声最高） |
| `Ctrl`（按住） | 蹲下潜行（12 px/s，最慢，噪声最低） |
| `E` | 拾取 / 搜索（A/B/C 三区各一个容器）；无容器可搜时开关/锁最近的门 |
| `Tab` | 背包：`W/S` 选择、`E` 使用、`Q` 丢弃、`Tab`/`Esc` 关闭 |
| `V` | 查看文本 / 关闭检查框 |
| `Esc` | 关闭 / 取消 |
| `F` | 手电开关 |
| 鼠标左键 | 攻击：近战命中/耐久消耗；枪械需先装填，命中消耗 1 发 |
| `R` | 装填（消耗背包里的对应弹药） |

物资与容器规则见 [`design/LOOT.md`](design/LOOT.md)：**剧情模式下容器搜过一次就永久为空（不刷新）**，
每栋建筑只有一个高珍惜容器（学校 = 急救柜），物品详情不写价值/稀有度，玩家自己判断。

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
# 静态规则（47 条）
python tools/validate.py

# 规则自测
python tools/selftest.py

# 像素门禁（单帧 ≤16 色、二值 alpha、网格对齐）
python tools/pixelpipe.py gate art/generated_candidates/props/stage1/PROP-02_01_locker_bank.png `
  --palette art/palettes/master.gpl --max-colors 16

# 重建 15 件学校道具（会重写 corridor_props.tscn 与 props.json）
python tools/prop_build.py

# 重建点阵字库（PF-01 HUD / PF-02 中文检查文本 + 战利品文案）
python tools/font_build.py
# D15：字体图集覆盖门禁（只读；新增文案缺字会红）
python tools/font_build.py --check
# 从 data/loot/*.json 重新生成物资文档 design/LOOT.md
python tools/build_loot_doc.py

# Godot 侧
$G = ".tools/Godot_v4.7-stable_win64_console.exe"
& $G --headless --path . --check-only --script res://game/scenes/corridor.gd
& $G --headless --path . --script res://game/tests/smoke.gd
& $G --headless --path . --script res://game/tests/replay_30d.gd
& $G --headless --path . --script res://game/tests/shell.gd
& $G --headless --path . --script res://game/tests/loot.gd
& $G --headless --path . --script res://game/tests/inventory.gd
& $G --headless --path . --script res://game/tests/traverse.gd
# 走廊截图回归（需要图形渲染，不能加 --headless）
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_preview.gd -- CORRIDOR-QA
# 检查框门禁（真渲染 + 真实 InputEventKey；同样不能加 --headless）
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_inspect.gd -- CORRIDOR-INSPECT
# 可搜索柜门禁（真渲染；E 搜索 + 同日拒绝 + 截图）
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_loot.gd -- CORRIDOR-LOOT
# 背包与使用门禁（真渲染；Tab 背包 / E 使用 / Q 丢弃 / 左键攻击）
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_inventory.gd -- CORRIDOR-INV
# 门门禁（真渲染；开关门 / 挂锁 / 钥匙）
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_doors.gd -- CORRIDOR-DOOR
# 战斗门禁（真渲染；追击 / 命中 / 耐久 / 弹匣 / 装填）
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_combat.gd -- CORRIDOR-COMBAT
# 呈现尺寸门禁（真窗口：1920×1080 = 5× 整数放大）
& $G --path . --script res://game/tests/display.gd
# 主界面壳 + 结局栏
& $G --path . --fixed-fps 60 --script res://game/tests/main_menu.gd -- MENU
# D14：菜单继续/新游戏真的切到走廊
& $G --path . --fixed-fps 60 --script res://game/tests/menu_entry.gd -- MENU-ENTRY
# D3：一天一次外出的真消耗（同日第二次出发被拒 / 跨天恢复）
& $G --path . --fixed-fps 60 --script res://game/tests/m2a_actions.gd -- ACTIONS
# D4：燃料是门槛不消耗；到加油站 +1、上限 3，医院/军事基地按访问次数解锁
& $G --path . --fixed-fps 60 --script res://game/tests/travel_fuel.gd -- FUEL
# D9：体力归零触发「倒下」结算（沉积 -1 / 翻页 / 回学校）
& $G --path . --fixed-fps 60 --script res://game/tests/down.gd -- DOWN
# D10：≥3 噪声把敌人引向声源 2 秒（小声不惊动 / 听程外不理 / 看见优先）
& $G --path . --fixed-fps 60 --script res://game/tests/enemy_hearing.gd -- HEAR
# D12：每天抽 1 张事件卡写 world_state，效果随存档保留
& $G --path . --fixed-fps 60 --script res://game/tests/card_day.gd -- CARD
# D11：A/B/C 三区独立灯光档与按区容器/敌人
& $G --path . --fixed-fps 60 --script res://game/tests/room_light.gd -- ROOM
# D7：五楼主题（每楼 tileset/道具场景/标志物/环境亮度）
python tools/theme_build.py
& $G --path . --fixed-fps 60 --script res://game/tests/building_theme.gd -- THEME
# TapDB 分析门禁（headless；MockTransport，不联网）
& $G --headless --path . --fixed-fps 60 --script res://game/tests/analytics.gd -- ANALYTICS
```

> **TapDB（可选，客户端直连）**：复制 `config/analytics.example.json` 为 `config/analytics.json` 并填 ClientID；
> 事件/属性需先在 TapDB 后台登记；仅在导出构建且用户同意后上报。细节见 `design/ANALYTICS.md`。

> **发布到 TapTap**：入口、CLI 安装、skills、PC 包上传/提审流程见 [`design/TAPTAP.md`](design/TAPTAP.md)；
> 本机目前未安装 Node/CLI、没有 Windows 导出预设，也不具备开发者登录上下文。

---

## 当前进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| — | 数据层 / 47 条规则 / 资产管线 | 已通过 |
| Stage 1 | 15 件学校环境物件、走廊几何、相机与手电 | 已签核 |
| Stage 2 | 道具细节、24px 角色可读、检查文本框、移动速度 | 已实现并通过门禁（角色已放大到 32×48 / W/S 纵深） |
| Stage 2.5–2.16 | 主角放大/纵深轴、三档速度、容器/背包/战斗/状态、20 帧动画、打击感、PSD 双向 | 已实现并通过门禁 |
| Stage 3.0–3.7 | 五楼战役、出口结算、主界面壳+结局栏、旅行图、真场景切换、RunState 持久化 | 已实现并通过门禁 |
| M2a / D5 / D6 | 物资真源=world_state、噪声唯一出口、结局解锁链路、校验器 47 条 | 已实现并通过门禁 |
| D14 / D3 / D4 | 菜单 → 走廊真切换；`actions_left` 一天一次真消耗；燃料门槛 + 加油站补给 | 已实现并通过门禁（`menu_entry` / `m2a_actions` / `travel_fuel`） |
| D8 | 旅行图「我在哪」闪烁角标 | 已实现并通过 `travel_map` 门禁 ⑭ |
| D9 | 体力归零「倒下」结算（丢沉积 + 回学校 + 翻页） | 已实现并通过 `down` 门禁 |
| D10 | 敌人听声（≥3 噪声引向声源 2 秒，看见优先） | 已实现并通过 `enemy_hearing` 门禁 |
| D12 | 事件卡接玩法（每天 1 张写 world_state，效果随存档保留） | 已实现并通过 `card_day` 门禁 |
| D11 | 房间级状态（A/B/C 独立灯光、容器与敌人按区） | 已实现并通过 `room_light` 门禁 |
| D7 | 五楼主题美术 v1（每楼独立 tileset/道具/标志物/环境亮度） | 已实现并通过 `building_theme` 门禁 |
| TapDB | 客户端直连分析（同意门控 + 离线队列 + analytics 门禁） | 代码完成，待 ClientID/后台登记/导出实机验证 |
| TapTap 发布 | PC 包路线 + CLI/Skills 文档收束（`design/TAPTAP.md`） | 文档完成；待 Node/CLI/导出预设/开发者登录 |
| D15 | 字体图集覆盖门禁（792 字，卡牌/结局文案 + 结算标点入图集） | 已实现并通过 `font_build.py --check` |
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
