# HANDOFF · Stage 2（2026-11-23）

> 这份是**当前**状态，`design/HANDOFF.md` 是十轮自动推进时期的历史记录（那会儿本机还没有 Godot，所以它写「从未编译」——现在已经编译并跑起来了）。
> 下面每一条都区分「已验证」和「实现了但没验」。

---

## 一、Stage 2 要解决的三件事

用户对 Stage 1 的反馈原文：**「场景物件有些单一，需要丰富细节，目前文本框没有接入，角色速度太快了」**。

| # | 反馈 | 落点 | 状态 |
|---|---|---|---|
| 1 | 物件细节单一 | `tools/prop_build.py` 给 15 件各加内部线索，不动轮廓/摆位 | 已重建、像素门禁自检通过 |
| 2 | 文本框没接入 | `data/prop_inspections.json` + `game/scenes/corridor.gd` 检查流程 + `PixelFont` 中文图集 | 已实现、静态校验通过、**运行时未验** |
| 3 | 角色速度太快 | `game/scenes/player.gd` 常速 48→24、慢走 24→12 px/s | 已改、**回归断言还没同步** |

---

## 二、已验证的事实

```powershell
python tools/validate.py        # 43 条规则 ERROR 0 · WARN 0 · SKIP 0
python tools/prop_build.py      # built=15，逐件 colors=5..11、warm=0
python tools/font_build.py      # PF-01 96x16；PF-02 256x192 cell=16 CJK=186
```

- 15 件道具：32×32、二值 alpha、单件 5–11 色（上限 16）、Day 3 暖色像素 0、c31 只做一像素外描边、四角透明。
  摆位表未改，`corridor_props.tscn` 由构建器重写，节点名与 `prop_inspections.json` 的 `id` 一一对应。
- PF-02 中文图集：186 个字形，alpha 只有 `{0, 255}`（硬边），单字墨迹最大 10×12 px，落在 12px 步进内不重叠；
  颜色只有 `c30_white`，运行时靠 `modulate` 上色。
- `game/scenes/corridor.gd`、`game/ui/pixel_font.gd` 通过 `--check-only`。

## 三、实现了但还没验的

1. **检查交互**：`E` 打开、`E`/`Esc` 关闭、面板期间锁移动、离开范围清提示。
   目标选择按 `interaction_range_x`（28px，含边界）取最近；同距按玩家朝向，再按 id 字典序。
   `locker_bank` / `wall_clock_stopped`（同在 x=80）与 `window_night` / `chair_toppled`（同在 x=288）
   用数据里的 `focus_offset_x = ±8` 拆成两个不同锚点（x=88/72、x=280/296）。
   **没有任何一条在真引擎里按过键。**
2. **中文渲染**：`PixelFont.draw()` 现在按字形表逐字画 Sprite2D，`width_of()` 按 6/12px 混合计宽。
   还没在 384×216 实机上确认最长一句（`trash_bin` 的 12 字）不裁切。

## 四、必须先修的坑（2026-11-23 已修，见文末《七》）

`game/tests/corridor_preview.gd` 的移动断言还是按 24/12 px/s **之前**的数值写的，现在必然失败：

- 第 100 行：`for _frame in range(80)` 只够走约 16px（含加速），断言却要 `23.0..33.0`。
  → 改成 **150 帧**（约 30px），或单独测稳态速度。
- 第 107 行：`_walk_to(15.0, false)` 的 900 帧上限，对 600→15 这段（约 1400+ 帧）不够。
  → 上限按「距离 / 速度 + 余量」推导，或直接给 ~1800 帧。
- 还要补一条**图形化的检查框门禁**：真实 `InputEventKey`（`Input.parse_input_event`，
  带 press/release 与 echo）→ 截图 prompt、打开、关闭三态；断言中文标题与两行正文都有不透明像素。

## 五、边界（别越界）

- Stage 1 的 15 个 id、摆位、32×32 画布、锚点、调色板角色都**冻结**。
- 地面接缝 / 磨损 / 散落物属于 **Stage 3**，本阶段一行没动。
- 新房间、新道具、NPC、感染、动画、卡牌与掉落系统都不在 Stage 2 范围内。
- Stage 2 要**用户看过截图点头**才进 Stage 3。

## 六、文件清单（本阶段新增/改动）

| 文件 | 动作 |
|---|---|
| `tools/prop_build.py` | 15 件加内部细节（柜门暗缝、门扇裂痕、钟面停针、窗格缺口、水线、断格等） |
| `tools/font_build.py` | 新增 PF-02 中文图集生成（透明 RGBA、二值阈值、逐字裁紧、12px 步进） |
| `art/fonts/NotoSansSC-VF.ttf` | 新增，OFL 1.1 构建输入（17.7MB） |
| `art/fonts/NOTOSANS-SC-OFL.txt` | 新增，上游原文 |
| `art/fonts/NOTICE.md` | 补 PF-02 授权说明 |
| `THIRD_PARTY_LICENSES.json` | 补 PF-02 条目 |
| `data/prop_inspections.json` | 新增，15 条检查文本（单一数据源） |
| `game/ui/pixel_font.gd` | 支持中文图集与混合计宽 |
| `game/scenes/corridor.gd` | 检查流程、提示条、面板、移动锁、`inspect`/`cancel_inspect` 动作 |
| `game/scenes/player.gd` | 速度 24/12、朝向 `facing_x`、`_movement_locked` |
| `design/prompts/X-02-dev-player.md` | 速度表同步为 24/12 |

---

## 七、2026-11-23 修复记录（本机 Godot 4.7.2 实跑，全部已提交）

环境：`Godot 4.7.2.stable.official.ed1daf0bf` · Windows 11 · RTX 5080（GL Compatibility）。
提交方式说明：本机到 github.com 的 git/SSH 传输被网络 reset（clone 卡死、HTTPS clone
`Recv failure`），所以提交走 GitHub Git Data API（`create blobs → tree → commit → update ref main`），
仓库内容与普通 push 等价。

### 修了什么

| # | 问题 | 修法 | 提交 |
|---|---|---|---|
| 1 | 检查框真键盘「开一帧就关」：`_unhandled_input` 打开、同帧 `_process` 的 `is_action_just_pressed` 又关掉 | 输入收敛为单一路径：开/关/取消全走 `_unhandled_input`（echo/松开不计），`_process` 只刷新提示条；门禁改为直接投递真实 `InputEventKey`（`--script` SceneTree 里 `Input.parse_input_event` 实测不派发） | `19c184f` |
| 2 | 12 张卡的 24 个效果全部空转：`card_engine.gd` 读 `add_vars`，数据是 `effects[].vars` | 改读 `vars`；`time` 是派生量，按 v0.6 开工盘点「事件卡 +0h」跳过 | `f447071` |
| 3 | `world_state.gd` / `memory.gd` 对 `DataLayer` 调 `data.get("mode_profile"/"nodes"/"npcs")`，恒 null：夜晚倍率、沉积传导、`day_locked_after`、NPC 引用全部失效 | 改 `data.profile("story")` / `data.nodes()` / `data.node()`；NPC 池统一走 `load_npcs()` | `f447071` |
| 4 | `main.gd` 死代码：调 WorldState 不存在的 `new_game/set_day/set_hour`，摘要读 `vars` 且查 `health/morale/risk` | 开局改为 `init_from + spend_time`；`add_noise` 按 `{self,neighbors}` 判；摘要改读 `snapshot.variables` 六组；`_dev_log` 改 `push_warning` | `e38bdfd` |
| 5 | 存档读回恒失败：Godot 4 JSON 往返把整数读成 float，`restore()` 要求 `is int` | `restore()` 按数值校验并取整（day/hour/sediment） | `e38bdfd` |
| 6 | 测试里有同义反复：`replay` ③ 因效果空转空转、`smoke` 存读往返被夹零 | 新增真断言：卡效果必须改动变量、夜间噪声倍率、Day14/15 锁门、shell 闭环 | `f447071` `e38bdfd` |
| 7 | 输入台账缺 3 项（20/23） | 补 `data/weapons/weapons.json`、`data/variables.json`、`schema/card.schema.json` → **23/23** | `cf290af` |

### 当前验收快照（可复跑）

```powershell
$G = ".tools/Godot_v4.7-stable_win64_console.exe"
python tools/validate.py            # 43 条：ERROR 0 · WARN 0 · SKIP 0
python tools/validate.py --inventory# 输入台账 23/23 就位
python tools/selftest.py            # 全部通过
python tools/gd_sanity.py game/runtime/data_layer.gd game/runtime/world_state.gd game/runtime/card_engine.gd game/runtime/memory.gd game/runtime/main.gd  # 结构问题 0 个
& $G --headless --path . --script res://game/tests/smoke.gd       # SMOKE_OK ... changed=9 night=2/3 lock=ok roundtrip=ok
& $G --headless --path . --script res://game/tests/replay_30d.gd  # REPLAY_OK seeds=3 fired=90 oneshot_max=13 changed=27
& $G --headless --path . --script res://game/tests/shell.gd       # SHELL_OK day=0 hour=11 supplies=0.8 ... six_vars_in_0..1=true
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_preview.gd -- CORRIDOR-QA   # CORRIDOR_OK ... props=15 min_changed_pixels=283
& $G --path . --fixed-fps 60 --script res://game/tests/corridor_inspect.gd -- CORRIDOR-INSPECT  # CORRIDOR_INSPECT_OK records=15 ties=8 boundary=28px
```

`corridor_inspect` 的面板墨点门禁：title=121 / body=1112 / esc=82（阈值 80/160/20），
`design/previews/CORRIDOR-INSPECT_panel.png` 现在是真面板（此前只有提示条）。

### 仍未做 / 仍需人

1. **Stage 2 视觉签核**：`design/previews/CORRIDOR-QA_{entry,classroom,midpoint,late,far_end}.png`
   与 `CORRIDOR-INSPECT_panel.png` 需要人看过后点头，才进 Stage 3。
2. 卡池覆盖仍窄：30 天回放 12 张只触发 6 张（`l_night_encounter` 等常因 `node_tags_any` 与主轴走廊不匹配而不可达），
   这是 trigger 资格面问题，不是 `pick_and_fire` 饥饿（轮转已实现）。
3. `R21` 仍未在真实数据上开火：`art/asset-manifest.json` 32 条全是 `draft`，`approved/` 仍为空。
4. 角色精灵仍是 blockout；Stage 3（地面接缝/磨损/散落物）与 Stage 4/5 未动。

---

## 八、Stage 2.5 · 主角放大 + 纵深轴（2026-11-23 傍晚，已提交）

> 反馈原文：「人物模型有点太小了……如果要这样做，最好 WASD 都能移动，形成房间区块，
> 这样才不显得下面玩家下面些只是展示。」

### 改了什么

| # | 项 | 做法 | 验收 |
|---|---|---|---|
| 1 | 主角放大 | 新增 `tools/player_build.py`：32×48 原生帧（可见 41px，原 24px），不做任何非整数缩放；`pixelpipe gate` 三帧均 11 色 PASS | 门禁输出 + `design/previews/PLAYER-02_x6.png` |
| 2 | 纵深轴 WASD | `player.gd` 增加 `move_up/down`；脚底限制在 `Rect2(14, 128, 588, 88)`；A/D 水平、W/S 纵深（纵深速度 ×0.8） | `CORRIDOR_OK ... slow_walk=29.5` + 新增深度移动断言 |
| 3 | 下方区域可走 | 取消 y=128 的薄地板碰撞，改为矩形夹取；相机 y 最多下移 8px | `CORRIDOR-QA_depth.png` |
| 4 | 纵深遮挡 | 道具与玩家 `z_index = 脚底 y`；贴图按 `facing_x` 翻转 | 门禁断言 z_index 跟随 y |
| 5 | 检查交互适配纵深 | 交互锚点：墙面道具落到房间内缘 y=136，地面道具用自身 y；水平 28px 主判据 + 24px 纵深容差 | `CORRIDOR_INSPECT_OK records=15 ties=8 boundary=28px` |
| 6 | 测试同步 | preview 去掉 camera y=0 假设；inspect 的 `_place` 带 y；新增深度移动/边界/遮挡断言 | 两个图形门禁全绿 |
| 7 | 手电开关 | 新增 `F`（`toggle_light` 动作）：关灯 = 光锥半径/羽化归零，整屏压暗；面板打开时不响应。键位总表落在 `design/CONTROLS.md` | preview 断言 + `CORRIDOR-QA_light_off.png` |

### 还没做（下一轮）

1. **房间区块分隔还没有实体墙与门洞**：下方现在是一整条可走地面带，视觉上还没有「一间间房」。
   下一步：把 3 个区块做出分隔墙 + 门洞 + 地面分区，并让 W/S 只在本区块内活动。
2. 走路帧（`SPR-player_walk1/2_32x48.png`）已生成但**还没接动画**，玩家目前是静态帧；NPC 仍是 32×32。
3. 手电光点已按 41px 身高调到 `-24`，但走路时没有摆动。

---

## 九、Stage 2.6 · 键位 v0.2 + 三档速度 + 可搜索柜子（2026-11-23 晚，已提交）

> 反馈：「战斗键位默认左键，拆开吧，看看别人游戏怎么做的，背包放 tab，速度分为步行/蹲下潜行/疾跑，
> 顺便看看 WASD 是否正常能够探索整个房间所有区块，做两个可以搜索物资的柜子，看看物资是否随机刷新测试。」

| # | 项 | 做法 | 验收 |
|---|---|---|---|
| 1 | 拾取/查看拆键 | `E` = 拾取/搜索（`pickup`），`V` = 查看文本（`view`）；旧的 `inspect` 动作拆成两个 InputMap 动作 | `corridor_inspect`（V 键全流程） |
| 2 | 战斗/背包键位 | 鼠标左键 = `attack`、`Tab` = `inventory`，已注册 InputMap，系统未实现 | 键位表 + 编译 |
| 3 | 三档速度 | 蹲下（Ctrl，12 px/s，潜行/最慢）< 步行（默认 24）< 疾跑（Shift，44，逃跑） | `CORRIDOR_OK ... crouch=29.5 sprint=107.7` |
| 4 | 两个可搜索柜子 | `data/loot/containers.json`：`locker_bank`（储物柜）与 `first_aid_cabinet`（急救柜），E 搜索、同日第二次显示「今天已经翻过」、按世界日刷新 | `CORRIDOR_LOOT_OK containers=2 refresh=per_day panel=ok` + `CORRIDOR-LOOT_panel.png` |
| 5 | 随机战利品 | `game/runtime/loot.gd`：权重表抽取，随机种子 = (容器, 世界日, 当日次数, 盐)，确定性可回放 | `LOOT_OK distinct_locker=5 deterministic=ok refresh=per_day` |
| 6 | 可达性 | `traverse.gd`：不瞬移，只用 WASD 走到可走地面带的四角 + 中心，并验证边界不泄漏 | `TRAVERSE_OK corners=4 center=1 leaks=0` |
| 7 | 字体图集 | `font_build.py` 把战利品文案（柜名/物品/固定提示）与 `V` 键涂进 PF-02（216 字），避免缺字告警 | 三张图形门禁无 PixelFont 告警 |

### 仍未做

1. **背包/拾取落库未做**：搜到的东西只显示文本，没有 inventory 与 supplies 变化（下一步接 `inventory`）。
2. **战斗系统未做**：左键只是注册了键位。
3. **房间分隔墙/门洞仍未做**：当前是一整条可走地面带，`traverse` 验证的是整块区域可达。
4. `data/loot/containers.json` 还没进 `validate.py` 的规则与输入台账（R 规则未覆盖战利品表）。

---

## 十、Stage 2.7 · 物资与容器系统 v1（2026-11-23 深夜，已提交）

> 反馈原文：「剧情模式不刷新物资！……只要一个柜子搜过了，那么接下来不管过了多少个世界日，
> 那个物资用了就再也不刷新……柜子每次物资搜索不能每次都是五个，要有随机性，数量不固定、具体不固定……
> 给每个柜子设一个类似容器珍惜程度，且每个建筑物高珍惜容器只有一个……写物资珍惜程度表……
> 不要把价值高的或程度写在物品详情表里，让玩家自己猜……像黑道圣徒一样写很多恶趣味的道具，
> 每个容器容纳的东西多少根据这个容器的价值程度和开启时间而定。」

| # | 项 | 做法 | 验收 |
|---|---|---|---|
| 1 | 剧情模式不刷新 | `LootService` 剧情模式下容器搜过永久为空（`already_searched`），不再按世界日刷新；`refresh.story = never`，无尽模式保留 `per_day` 位 | `LOOT_OK story=never`；`CORRIDOR_LOOT_OK story=never`（day 28 再搜仍是「已经搜过一次 / 剧情模式不会刷新」） |
| 2 | 容量随机 | 件数按档位 `capacity` 区间均匀随机；同档不同盐件数会变 | `LOOT_OK capacity_random=ok` |
| 3 | 容器珍惜度 + 每建筑唯一高珍惜 | 四档：常见 1–2 件/1s、标准 2–3/2s、贵重 3–4/3s、高珍惜 4–5/5s；加载时校验每建筑 `treasure` 唯一（学校 = 急救柜） | `LOOT_OK containers=2 tiers=4` + 加载校验 |
| 4 | 枪械只能在高珍惜容器 | 分池：常见/标准只抽 household/junk；贵重无 weapon；`firearm`/`high_value` 只挂高珍惜，且高珍惜保底一件高价值物 | `LOOT_OK weapon_only_treasure=ok`（普通容器 64 次无 weapon；高珍惜必出高价值物且 64 次内出过枪械） |
| 5 | 物资表与详情不写价值 | `data/loot/items.json`：104 件物品，只有名称/类别/作用/使用方式；价值信息只在 `containers.json` 的分池里 | `LOOT_OK items=104` + 门禁拒绝 item 出现 tier/rarity/value 字段 |
| 6 | 文档 | `design/LOOT.md`（由 `tools/build_loot_doc.py` 从 JSON 生成）：剧情规则、容器珍惜度表、抽取池（内部）、104 件物品详情表（不含价值）、恶趣味清单 | `python tools/build_loot_doc.py` |
| 7 | 面板 | E 搜索面板：两种档位容器分别显示随机件数的物品名、共 N 件；同柜第二次显示拒绝文案 | `CORRIDOR_LOOT_OK` + `CORRIDOR-LOOT_{locker_bank,first_aid_cabinet}.png` |

### 仍未做

1. **背包/使用未接**：搜到的物品只显示文本，`items.json.usage` 的使用方式已写好但还没有 inventory 与使用系统。
2. **消耗效果未接**：食物/医疗的数值效果（supplies、伤口、感染）还没接到角色状态。
3. **搜索耗时未接**：`search_seconds` 目前只是数据，还没有「按住 E 搜索 N 秒」的交互。
4. **`data/loot/items.json` / `containers.json` 还没进 validate.py 的规则与输入台账**。

---

## 十一、Stage 2.8 · 背包与使用系统（2026-11-23 深夜，已提交）

> 反馈：「1（背包 + 使用）然后再做 2（房间分隔墙 + 门洞）」。

| # | 项 | 做法 | 验收 |
|---|---|---|---|
| 1 | 背包 | 新增 `game/runtime/inventory.gd`：容量 10、堆叠、`add_many` 一批拾取、装不下返回 rejected；搜索后物品自动进包，满了提示「背包满了，剩 N 件没拿」 | `INVENTORY_OK capacity=3 stack=2` + `corridor_inventory` 搜索入包断言 |
| 2 | 使用效果 | `items.json` 增加机器可读 `effect`（41 件）：食物 supplies、医疗 health、噪声类 noise、武器 equip；`tools/apply_item_effects.py` 写入 | `INVENTORY_OK effects=41 equip=melee/firearm` |
| 3 | 背包界面 | `Tab` 打开（锁移动），`W/S` 选择、`E` 使用、`Q` 丢弃、`Tab/Esc/V` 关闭；标题显示 `背包 n/10  装备 xx`，选中行高亮，底部提示与 toast | `CORRIDOR_INVENTORY_OK` + `CORRIDOR-INV_panel.png` |
| 4 | 左键攻击 | 装备近战/枪械后左键挥击：计数 +1、按武器类型抬噪声、画 4 帧挥击条；空手也能挥；面板打开时不响应 | `CORRIDOR_INVENTORY_OK ... attack=left_click` |
| 5 | 玩家状态 | 新增 `_supplies` / `_health` / `_noise`；HUD 左上显示「物资 / 体力」数值并在使用后刷新 | 门禁断言使用瓶装水后 supplies 上升 |
| 6 | 文档 | `design/CONTROLS.md` v0.3（Tab/左键/使用流程）、`design/LOOT.md` 增加「使用效果」表（由 `tools/build_loot_doc.py` 生成） | `python tools/build_loot_doc.py` |

### 仍未做

1. **状态细化**：伤口/流血/感染/中毒/成瘾没有；`contaminate` 字段先只记录。
2. **战斗**：挥击没有敌人、命中、耐久、弹匣；左键目前是占位。
3. **丢弃落回世界**：Q 只是移除，没有地面掉落物。
4. **搜索耗时**：`search_seconds` 仍未接「按住 E 搜索 N 秒」。
5. **房间分隔墙 + 门洞**：下一步（排队中）。

---

## 十二、Stage 2.9 · 房间分隔墙 + 门洞（2026-11-23 深夜，已提交）

> 反馈：「1 然后再做 2」——第 2 项。

| # | 项 | 做法 | 验收 |
|---|---|---|---|
| 1 | 三个房间区块 | `corridor.gd` 新增 `ROOM_PARTITION_TILES = [12, 26]`：tile x=12 / x=26 处做隔断，A 区（0–11）/ B 区（12–25）/ C 区（26–39） | 截图 `CORRIDOR-QA_midpoint.png` 可见「B 区 / C 区」 |
| 2 | 门洞净空 | 墙垛只到 y=80，门洞下方全空；玩家 40px 身高（脚底最高 216 → 头顶 176）从门洞穿过，不会撞头 | `corridor_preview` 新增 `_verify_rooms()`：墙垛 y=0..80、门楣 y=78、门槛 y=128、净空校验 |
| 3 | 可读性 | 墙垛压暗 + 右侧立柱高光 + 门楣亮线 + 地面门槛线 + 区块标签（A 区/B 区/C 区，PF-02 字体） | 同上 + 截图 |
| 4 | 可达性 | 不瞬移，WASD 走遍三个区块（A/B/C 各一个点 + 四角 + 中心） | `TRAVERSE_OK waypoints=8 corners=4 center=1 leaks=0` |

### 仍未做

1. 门是**常开门洞**，没有可交互的开关门/锁门（`padlock` 等道具还没有落点）。
2. 区块目前只是视觉与空间分隔：还没有房间级状态（灯光、可搜索容器、敌人刷新）。
3. 下一步：给每个区块放各自的容器与叙事物件（B 区已经有一个急救柜，A/C 区还没有）。

---

## 十三、Stage 2.10 · 呈现尺寸 1920×1080 + A/B/C 区容器 + 可交互门（2026-11-23 深夜，已提交）

| # | 项 | 做法 | 验收 |
|---|---|---|---|
| 1 | 玩家视角 1920×1080 | `project.godot` 窗口客户区改为 **1920×1080**，保持 viewport stretch = `viewport` / `integer` / `keep`、最近邻；1920/384 = 1080/216 = 5× 整数 | 新门禁 `display.gd`：工程设置 + 真实窗口 1920×1080 + 5× + 最近邻；证据 `DISPLAY_native_384x216.png` / `DISPLAY_1920x1080.png` |
| 2 | A/B/C 各区容器 | 三个房间各一个可搜容器、档位不同：A 区 储物柜（常见）、B 区 垃圾桶（标准）、C 区 急救柜（高珍惜，唯一 treasure）；容器表加 `room` 字段 | `LOOT_OK containers=3` + `CORRIDOR_LOOT_OK containers=3`（三张各容器的截图） |
| 3 | 可交互门 | 两个门洞各有一扇门：初始常开；`E` 开关（关上有碰撞、挡路）；挂锁可上锁（消耗 padlock）；钥匙/已装备近战武器可撬开；带门板/把手/提示/提示语 | 新门禁 `corridor_doors.gd`：开→关→挡路→开→锁→挡路→钥匙撬开；三张截图 |

### 门交互优先级

`E` 先判定可搜索容器，再判定门：站在急救柜旁边按 E 会先搜柜子，想关门需错开一步。
这是已知设计取舍，写进 `design/CONTROLS.md` v0.4。

### 仍未做

1. 门没有「从里面锁」/门缝窥视/破门动作；`padlock`、`keys` 之外的道具（撬棍当工具）还没接门。
2. 房间级状态（灯光、敌人刷新、区块专属事件）未接。
3. 下一步按用户顺序：**战斗（敌人/命中/耐久/弹匣）→ 状态系统 → 搜索耗时**。

---

## 十四、Stage 2.11 · 战斗（2026-11-23 深夜，已提交）

| # | 项 | 做法 | 验收 |
|---|---|---|---|
| 1 | 敌人 | 新增 `game/scenes/enemy.gd`：感染体（追击 240px、贴身 22px 每 1.2s 抓伤、受击掉血、死亡隐藏）；B 区/C 区各一只 | `CORRIDOR_COMBAT_OK enemies=2` |
| 2 | 命中判定 | 左键：近战 36px / 枪械 320px 内、按朝向与纵深容差取最近敌人；空手伤害 1 | 近战两下杀 4 血敌人；手枪两枪杀 |
| 3 | 耐久 | 武器效果加 `damage/durability`；近战每次命中 -1，归零自动卸下并提示「xx 坏了」 | `melee=damage2 durability=8 broken=unequip` |
| 4 | 弹匣/装填 | 枪械效果加 `magazine/ammo`；`R` 消耗背包弹药装满弹匣，射击消耗 1 发；没子弹有提示 | `firearm=magazine6 reload=ammo` |
| 5 | 敌人反击 | 抓伤扣体力（0.15/次）并在 HUD 显示「你被感染体抓伤了」 | 抓伤断言体力 < 1.0 |
| 6 | 新物品 | `ammo_rifle`（7.62 子弹）进高珍惜/枪械池；LOOT.md 效果列补伤害/耐久/弹匣 | `LOOT_OK items=105` |

### 仍未做

1. 敌人没有寻路/碰撞/死亡动画；也没有被声音吸引（噪声只是数值）。
2. 玩家死亡没有后果（体力到 0 只是数值）。
3. 下一步：**状态系统（伤口/感染/中毒/成瘾）→ 搜索耗时**。

---

## 十五、本机同步（2026-11-23 晚，拉取 5a08898 后）

从 GitHub 拉下 14 个提交（`3d41cf2 → 5a08898`）到本机（GTX 1060 / 1366×768 / Godot 4.7.0），
跑全套门禁，**发现远端 HEAD 有两条门禁本来就是红的**，都不是玩法问题，是测试常量没跟上战斗提交：

| # | 门禁 | 现象 | 根因 | 修法 |
|---|---|---|---|---|
| 1 | `loot.gd` | `treasure search without a high-value item (salt 3)` | 测试里手抄的 `HIGH_VALUE` 少了 `ammo_rifle`；数据 `pools.high_value` 已经有它 | 改成**从 `containers.json` 的池子推导** `HIGH_VALUE` / `FIREARMS`，不再手抄 |
| 2 | `inventory.gd` | `unknown effect key damage on screwdriver` | `VALID_EFFECT_KEYS` 还是 Stage 2.8 的 5 个键，战斗提交新增了 `damage/durability/magazine/ammo` | 白名单补齐到 9 个键 |
| 3 | `display.gd` | `window client size must be 1920x1080, got (1370, 749)` + `3.57x3.47` | 门禁用「窗口尺寸 ÷ 384」反推倍数；本机桌面只有 1366×768，窗口被系统夹小 | 改读 `root.get_final_transform()` 的实际缩放：断言**整数倍 + 方形像素 + 原生 384×216**；桌面 ≥1920×1080 时仍强制 1920×1080 / 5× |

本机实测：引擎在 1366×768 上自动选了 **3×** 整数放大（`DISPLAY_OK ... actual=3x`），
像素完整性没破，此前那个 3.57× 是测试自己的算法错。

### 本机全绿快照（2026-11-23 21:0x）

```text
python tools/validate.py                 # 43 条 ERROR 0 · WARN 0 · SKIP 0
python tools/selftest.py                 # 全部通过
SMOKE_OK / REPLAY_OK / SHELL_OK
LOOT_OK items=105 containers=3 tiers=4 story=never
INVENTORY_OK capacity=3 effects=41
TRAVERSE_OK waypoints=8 leaks=0
CORRIDOR_OK / CORRIDOR_INSPECT_OK / CORRIDOR_LOOT_OK
CORRIDOR_INVENTORY_OK / CORRIDOR_DOORS_OK / CORRIDOR_COMBAT_OK
DISPLAY_OK actual=3x
```

### 本机与参考机的差异（不影响结论）

- Godot 4.7.0（本机）vs 4.7.2（远端记录），同一 stable 分支。
- 桌面 1366×768，只能 3× 呈现；参考机 5×。
- 本机到 GitHub 的 HTTPS 在 HTTP/2 下会被重置，仓库已设 `http.version=HTTP/1.1`。

---

## 十六、Stage 2.12 · 字形重做 + 状态系统 + 搜索耗时（2026-11-23 深夜）

> 反馈原文：「跟上新系统，把新系统给补完，并且我发现放大后所有字体都很糊，你需要检查是什么导致的」。

### 一、字为什么糊（已定位，不是缩放问题）

先排除显示链：本机 `screen_scale=1.0`、`get_final_transform()` 的缩放**正好是整数 3.0**，
渲染截图里文字区域 `distinct_colors=2`（只有底色与字色）——没有抗锯齿、没有重采样模糊。

真正原因在字形本身：`PF-02` 为了让 12px 步进不重叠，把 **14px 栅格的字形用最近邻压到 10×10**。
汉字的撇捺钩在 10px 内直接粘连：墨迹中位数 10×10、横向笔画段中位数 18。

| 项 | 之前 | 现在 |
|---|---|---|
| 步进 | 12px | **14px** |
| 栅格字号 | 14px | **13px** |
| 降采样 | 每字压到 ≤10px | **零降采样**（546 字里只剩 1 个极宽字被缩） |
| 墨迹中位数 | 10×10 | **12×12** |
| 横向笔画段 | 18 | **24** |
| 阈值 | 96 | 110（笔画更实） |
| 字形来源 | JSON 文案 | JSON + `data/systems/status.json` + **`game/*.gd` 字符串字面量** |

顺带修掉的三件事：
- 「搜索」的『索』只写在 `corridor.gd` 里，原本不在图集 → 现在扫脚本字符串，缺字归零；
- `PixelFont` 步进改为**读图集元数据**（`advance` 字段），字号再变也不用改代码；
- HUD 四行与背包行距 10/13 → 15/15，避免 14px 字高叠字。

证据：`design/previews/FONT-PF02_compare.png`（新旧字形并排 6×）。

### 二、新补的系统

| 系统 | 落点 | 验收 |
|---|---|---|
| 状态：伤口 / 感染 / 中毒 / 成瘾 | `data/systems/status.json` + `game/runtime/status.gd` | `STATUS_OK states=4 wound_cap=3 infection=4h poison_decay=6h cures=ok` |
| 状态接入战斗与食物 | 抓伤 → 伤口；污染食物 → 中毒；止痛片/安眠药 → 成瘾；绷带/抗生素/消毒水对症 | `CORRIDOR_STATUS_OK states=4 wound=scratch poison=food addiction=pills cure=bandage hud=ok` |
| 状态影响玩法 | 移速倍率进 `player.status_speed_scale`；噪音倍率；按小时掉体力 | 同上 |
| 搜索耗时 | `LootService.search_seconds_of()`；按住 E 读条，松手中断，完成才结算 | `CORRIDOR_LOOT_OK containers=3`（门禁改成按住搜索） |
| 时间推进 | 搜索 1 秒 = 1 游戏小时（`SEARCH_SECONDS_PER_GAME_HOUR`），驱动流血与感染恶化 | `advance_hours()` 断言 |

### 三、当前全绿（2026-11-23 21:3x，本机 1366×768 / 3× 呈现）

```text
SMOKE_OK / REPLAY_OK / SHELL_OK
LOOT_OK items=105  INVENTORY_OK effects=41  TRAVERSE_OK leaks=0
STATUS_OK states=4
CORRIDOR_OK（crouch=29.5 sprint=107.7）/ CORRIDOR_INSPECT_OK
CORRIDOR_LOOT_OK / CORRIDOR_INVENTORY_OK / CORRIDOR_DOORS_OK
CORRIDOR_COMBAT_OK / CORRIDOR_STATUS_OK
DISPLAY_OK actual=3x
```

### 四、下一步（按优先级）

1. **状态的可视化反馈**：目前只有 HUD 一行字，缺屏幕边缘、喘息、脚步等体感线索。
2. **搜索时的风险**：搜索现在只推进状态，还没做「搜索中不能移动 / 会被抓」。
3. 房间级状态（各区灯光、敌人刷新）；敌人被噪声吸引（噪声目前只是数值）。
4. 玩家体力归零的后果（现在只是数值到 0）。
5. 原定 Stage 3（地面接缝/磨损/散落物）仍排队——是否插队由你定。

---

## 十七、Stage 2.13 · 全人物动作 + 部件拆解（2026-11-23 深夜）

> 反馈原文：「现在接入 see-through，这是个帧动画图像拆解工具，也是做 2D 骨骼动画的开源项目，开始给我们游戏所有人物添加相应动作」。

**关于 `see-through`**：按这个名字没搜到对应项目（搜到的是 Stretchy Studio / FrameBaker /
PuppetLoom / Pixelbolt 一类）。所以这轮先交付**动作本身 + 部件拆解数据**，任何 2D 骨骼工具都能直接吃；
拿到仓库链接后再补它的格式导出/导入。

### 做法

`tools/char_anim_build.py` 对 `art/generated_candidates/characters/SPR-*.png` 的**每个角色**出 10 帧：

| 动作 | 帧数 | fps | 循环 | 生成方式 |
|---|---|---|---|---|
| idle 待机 | 2 | 4 | 是 | 上半身 1px 呼吸起伏，脚不动 |
| walk 行走 | 4 | 10 | 是 | 下半身左右两半反相错步 + 轻微上下 |
| hurt 受击 | 1 | 12 | 否 | 整帧后仰 1px |
| death 倒地 | 3 | 8 | 否 | 逐帧下沉（1/3/6px）贴地 |

只做整数像素平移、不换色，所以调色板与二值 alpha 天然保持；每个角色一张横排精灵表
（32×32×10 或 32×48×10），外加 `anims.json`：

- 帧表（起列/帧数/fps/循环）
- **部件拆解**（head / torso / arm / legs 的矩形 + 底边中点枢轴）← 骨骼工具直接可切件

### 接入

- `game/runtime/char_anim.gd`：读清单，按 (角色, 列) 缓存 `AtlasTexture`，按 fps 取帧
- 主角：`BodySprite` 改用动作表第 0 帧起播；受击 0.22 秒锁 hurt 帧；走动 walk、静止 idle；按朝向翻转
- 感染体：追人播 walk、站着播 idle；被打死停在**倒地帧**（此前是直接隐藏）

### 验收

```text
ANIMATION_OK characters=31 anims=4 frames=10      # 310 帧逐帧检查尺寸/二值 alpha/≤16 色/非空
ANIM_FRAMES checked=310
```

另加了三条硬断言：清单必须覆盖全部角色 PNG；**第 0 帧必须与原静态帧逐像素一致**（防止顺手改美术）；
运行时主角与感染体都必须真的切到 ≥2 个不同帧；死亡必须停在 death 段。

证据：`design/previews/ANIM-<角色>_x4.png`（精灵表审阅）、`design/previews/ANIMATION_walk.png`（实机走动）。

### 下一步

1. 拿到 `see-through` 仓库链接后，加它的骨骼/JSON 导入导出适配（现有 parts 数据可直接映射）。
2. 攻击动作（挥击/开枪）需要单独出帧，目前左键只有挥击条，没有角色动作。
3. NPC 目前没有 AI，帧已备好，接入要等 NPC 行为。

---

## 十八、Stage 2.14 · 接入 see-through 的层结构（2026-11-23 深夜）

> 上游：**shitagaki-lab/see-through** —《Single-image Layer Decomposition for Anime Characters》
> （ACM SIGGRAPH 2026 Conference Papers，Apache-2.0，PyTorch）。

### 它是什么 / 我们能接什么

它是**研究管线**：LayerDiff3D 生成透明层 + Marigold 估深度 + SAM 分割 + LaMa 补洞，
把一张动漫立绘拆成**最多 23 个语义层**，导出**分层 PSD**；下游 Stretchy Studio / Anime2.5DRig 按层名认。
官方运行门槛是 Python 3.12 + torch 2.8 + 8–16GB 显存 —— 本机 GTX 1060 **跑不动它的模型**。

所以接的是**契约层**（这也是生态真正消费的部分），不是复现模型：

| 接入点 | 做法 |
|---|---|
| 层名表 | `tools/see_through_sync.py` 从上游 `common/assets/bodytags_v3.json` 同步 **23 个层名**到 `data/see_through/bodytags_v3.json`，不凭记忆写 |
| 分层导出 | `tools/see_through_export.py`：每个角色按这套层名拆层，出分层 PNG + 层表 JSON + **ORA**（OpenRaster，Krita/GIMP 可开） |
| 无损门禁 | 导出时把层按顺序合回去，必须与原图**逐像素一致**，否则构建失败 |

23 个层名（顺序即绘制顺序，自下而上）：
`front hair, back hair, headwear, face, irides, eyebrow, eyewhite, eyelash, eyewear, ears, earwear, nose, mouth, neck, neckwear, topwear, handwear, bottomwear, legwear, footwear, tail, wings, objects`

**诚实标注**：我们的角色是 32×32 blockout，用的是**几何分带**（行带 → 层名，`decomposition: "band"`），
不是 ML 语义分割。分带是行的严格划分，所以「合回无损」是像素级成立的——门禁查的就是这条。
将来用真模型跑出 PSD，层名结构一致，同一个导出/消费链路可以直接替换。

### 结果

```text
python tools/see_through_sync.py     # layers=23 -> data/see_through/bodytags_v3.json
python tools/see_through_export.py   # characters=31 layers_written=217
                                     # verify=lossless (every sprite reassembles pixel-perfect)
```

产物：`art/generated_candidates/characters/layers/<角色>/<NN>_<层名>.png`、`<角色>.json`、`<角色>.ora`。
两份工具已进 `pipeline.json`（`char-anim`、`see-through-layers`，都是 hard gate）。

### 仍未做

1. **反向导入**：读 see-through 导出的 PSD → 回填我们的层表与精灵表。需要 `psd-tools`/`pytoshop`（本机未装），
   装好后可加 `tools/see_through_import.py`。
2. **PSD 直出**：目前导 ORA；直接写 PSD 需要上面的 PSD 库。
3. **真模型跑图**：需要 8GB+ 显存的机器；跑完把 PSD 丢进同一条链路即可。









