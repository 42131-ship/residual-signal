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

