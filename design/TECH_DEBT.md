# TECH_DEBT · M2a 方案与欠账清单

> 状态：2026-11-24 整理，2026-11-25 更新（D1/D2/D5/D6 已还）。
> **接手先看 [`HANDOFF-STAGE2.md`](HANDOFF-STAGE2.md) 的「附录 A · 未完成清单」**——那份带验收方式，
> 这份解释每条为什么是债。
> 数字都是实测：`corridor.gd` 1900+ 行；断言 `_supplies` 的门禁只有 `corridor_inventory` 两处。

## 进度

| 步骤 | 状态 | 提交/门禁 |
|---|---|---|
| 1. 接入读取（world_state 为真源） | **已完成** | 门禁 `m2a-state` |
| 2. 接入写入（`add_var` 增量） | **已完成** | `changed()` 信号断言 + 两次 +0.05 == 一次 +0.1 |
| 3. 结算写增量（DayCycle 出口） | **已完成** | `DayCycle.settle()` 新增 `supplies_delta`；`day_cycle` 门禁断言 -0.05 / 0 |
| 4. 删旧字段 | **已完成** | `corridor.gd` 里已无 `_supplies` 成员，镜像改成 `RunState.supplies` |

第 1 步的实际做法与方案略有出入，记在这里：**没有立刻删掉 `_supplies` 成员**，而是先把它降级为
「RunState 存档镜像」，并新增 `_get_supplies()/_set_supplies()/_add_supplies()` 三个唯一读写口；
第 4 步再把成员整个删掉，镜像直接落到 `RunState.supplies`。分两步做的好处是每一步门禁都能单独复跑。

**M2a 完成后的状态**：物资只有一个真源（`world_state`），三条写入路径（用药/搜刮/结算）全部走增量，
`RunState.supplies` 只在存档时同步。门禁 `m2a-state` 断言：
`M2A_OK source=world_state mirror=run_state drink=rises settle=in_sync clamp=0..1`。

**2026-11-25 追加**：D3（`actions_left` 真消耗）与 D14（菜单 → 走廊真切换）已还清，
各配一条新门禁 `m2a-actions` / `menu-entry`，详见 [`HANDOFF-STAGE2.md`](HANDOFF-STAGE2.md) §三十六。
A1 剩余：**D7（五楼共用学校美术）**。D4 已按 `routes.json` 的「燃料是门槛不是消耗池」语义还清
（旅程不扣油、到加油站 +1、上限 3，门禁 `travel-fuel`）。

---

# 一、M2a：把 `supplies` 交给 `world_state`

## 1. 为什么是它

现在有**两套状态**：走廊的 `_supplies/_health/_noise` 与 `world_state` 的六组变量互不相识。
后果是「卡牌影响玩法」永远只是口号——卡牌改的是 `world_state.supplies`，玩家在走廊里看不见任何变化。

## 2. 范围（只做这三件）

| # | 做什么 | 不做 |
|---|---|---|
| 1 | `supplies` 改成读写 `world_state.var_of("supplies")` | 不改 `health`、不改 `noise` 语义 |
| 2 | 结算（`DayCycle.settle`）改为**写增量**给 `world_state`，而不是把本地值覆盖回去 | 不动 `variables.json` / R35 白名单 |
| 3 | 走廊 HUD 读 `world_state` 的值 | 不接卡牌触发（那是 M2a 之后） |

**`health` 明确保持运行时状态**（不进六组变量）。理由：`data/variables.json` 只允许六组，
`game/runtime/world_state.gd` 的 `VARIABLE_NAMES` 与 R35 校验都按那六个键走；
把 health 塞进去要连带改 `schema/card.schema.json`、`tools/selftest.py` 的 fixture、
以及 43 条规则里的 R35 —— 那是**改契约**，属于 M2c，本轮明确不做。

## 3. 字段归属（M2a 之后）

| 字段 | 归属 | 说明 |
|---|---|---|
| supplies | **world_state**（0–1，六组之一） | 唯一真源；走廊只经 `var_of/add_var` 访问 |
| health | 场景运行时 | 战斗/状态用；不写盘进世界状态，随 `RunState.health` 过场景 |
| noise | **先保持运行时**，M2a-2 再谈 | 走廊是「本日累计 int + 预算 14」；`world_state.add_noise(node, base, night)` 是「单次动作 → 乘夜倍率 → 加沉积」，语义不同，不能直接换 |
| fuel | `RunState` | 已有 |
| day / sediment | `RunState` + `DayCycle` | 已有 |

## 4. 步骤（每步都能单独跑门禁）

1. **接入读取**：走廊 `_ready` 里初始化 `DataLayer` + `WorldState.init_from()`，
   把 `_supplies` 改成 `_supplies()` 访问器（读 `world_state.var_of("supplies")`）。
   验收：`corridor_inventory` 仍然绿；HUD 数值与 `world_state.snapshot()` 一致。
2. **接入写入**：用药/搜刮等把 `_supplies = x` 改成 `world_state.add_var("supplies", delta)`。
   验收：用一瓶水后 `world_state.var_of("supplies")` 上升，且 `corridor_inventory` 的断言改成读 world_state。
3. **结算写增量**：`DayCycle.settle()` 增加一个「净变化」出口，走廊把 delta 交给 `world_state`；
   `RunState.supplies` 只作为**存档镜像**（退出/换场景时同步）。
   验收：新增门禁 `m2a_state.gd`——搜刮 + 用药 + 出门结算后，
   `world_state.supplies` 与 `RunState.supplies` 一致，且跨场景后不漂移。
4. **删旧字段**：确认没有裸 `_supplies =` 之后，删掉成员变量，全量门禁复跑。

## 5. 风险与回滚

| 风险 | 处理 |
|---|---|
| `world_state` 需要 `DataLayer` 且要 `nodes.json` 里存在的 node_id；走廊没有 node 概念 | M2a 只用「全局变量」那一半，`add_var` 不依赖 node；`add_noise` 才需要 node，故本轮不接 noise |
| `init_from()` 失败会导致 supplies 恒 0 | 失败时 `push_error` + 回落到本地值，并在 HUD 打一条 `STATE_OFFLINE` 便于发现 |
| 存档镜像与真源不一致 | 只在「换场景/退出」两个时刻同步，中间不双写 |

**回滚**：M2a 的三步各自一个提交，任一步门禁红了就 `git revert` 那一步，不影响其它。

---

# 二、欠账清单

按「什么时候必须还」排序。S = 半天内，M = 一轮，L = 多轮。

## 立即该还（影响正确性）

| # | 欠账 | 位置 | 为什么必须还 | 量 |
|---|---|---|---|---|
| ~~D24~~ | ~~走廊门禁失效~~ **已还（2026-11-26 接手当天）**：根因是 6 条门禁被登记成 `--headless`，而这 6 条测试**要真渲染**（`display` 同理）；改回真渲染后 **38/38 全绿、144 秒**。详见 [`TAKEOVER-2026-11-26.md`](TAKEOVER-2026-11-26.md) §三 | `game/tests/*`、`pipeline.json`、`tools/run_gates.ps1` | — | ✅ |
| ~~D1~~ | ~~双状态：`_supplies` 与 `world_state` 并行~~ | — | **已还（M2a）** | ✅ |
| ~~D2~~ | ~~`_noise` 与 `add_noise` 语义不同~~ | — | **已还（M2a-2）**：走廊只报底值，世界层缩放进沉积并传染邻接 | ✅ |
| D3 | `actions_left` 恒为 1、从未消耗 | corridor.gd:1488 | 「一天一次外出」只写在数据里，实际没约束 | S |
| D4 | `fuel` 只减不增，加油站不产燃料 | corridor.gd / routes.json | 地图上的燃料门槛玩两天就死锁 | S |
| ~~D5~~ | ~~结局只有判定函数，没有解锁写入~~ | — | **已还（D5）**：判定 → `RunState.unlocked` → 落盘 → 结局栏解锁 | ✅ |
| ~~D6~~ | ~~校验器不覆盖 `data/travel`、`data/endings`、`data/systems`、`data/loot`~~ | — | **已还（D6）**：新增 R44–R47；`selftest.py` 埋坏数据证明四条都会开火 | ✅ |

**D24 复测（2026-11-26，实测口径）**：

> **2026-11-26 接手当天已还清（38/38 全绿，144 秒）**：下表的「仍挂死 / 未复跑」是**旧机**口径。
> 本机实测根因是登记参数——5 条 `corridor-*` 与 `display` 被写成 `--headless`，而这些测试要真渲染；
> 去掉后每条 1–2 秒通过，`animation` / `corridor-preview` / `corridor-status` 本来就过。
> 完整证据与复跑命令见 [`TAKEOVER-2026-11-26.md`](TAKEOVER-2026-11-26.md) §三。

- `traverse` **已恢复**：`TRAVERSE_OK waypoints=8 bounds=588x88 corners=4 center=1 leaks=0`。
  `ebe33e7` 那笔提交本身就是「修复 traverse 被 D9 打断」，`pipeline.json` 里还写着 `broken` 是**陈旧的**，应改回 `ready`。
- `animation`、`corridor-status` 复跑仍**挂死**：前者 >150s、后者 >5min，都没有任何结论输出
  —— 是「在等一个永不触发的信号」，不是慢。这两条要按「找等待点」的思路查，别再等它自己结束。
- 其余 6 条（corridor-combat / -inspect / -preview / -doors / -inventory / -loot）**本轮没有复跑**，
  状态以 `pipeline.json` 为准，别当成已经好了。

## 手机线的新欠账（2026-11-26）

| # | 欠账 | 位置 | 为什么算债 | 量 |
|---|---|---|---|---|
| **D25** | **真机没跑过**：APK 只产出了，没在任何安卓设备上装过 | `build/android/*.apk` | 触摸手感、刘海、横屏旋转、发热全没验；`MOBILE.md` §7 的 M1 就是它 | S（有设备的话） |
| **D26** | **双引擎**：跑门禁用 4.7、导出包用 4.7.2（模板只有 4.7.2） | `.tools/Godot_v4.7*`、`pipeline.json` | 两套解释器/导出器会让「门禁绿」与「包能跑」之间出现缝隙 | M |
| **D27** | 触摸层靠**合成键事件**驱动一次性动作 | `game/ui/touch_controls.gd` | 对引擎来说与真键盘无异；如果将来要做手柄/重映射，这层得换成正统的 InputEventAction + 放宽 `_unhandled_input` 的类型判据 | M |
| **D28** | release keystore 只在本机 `.tools/keystore/` | 同上 | `.tools/` 不入库；丢了就发不出更新包 | S（备份一次即可） |


## 接着该还（影响体验/可玩性）

| # | 欠账 | 位置 | 影响 | 量 |
|---|---|---|---|---|
| D7 | 所有楼共用同一套走廊美术 | corridor.tscn | ✅ 美术主题 v1 已还（2026-11-25）：每楼 tileset/道具场景/4 件标志物/环境亮度，门禁 `building_theme`；检查文本与容器池仍共用 | L |
| D8 | 地图没有「我在哪」标记 | travel_map.gd | ✅ 已还（2026-11-25）：`CurrentBuilding` 闪烁角标 + `travel_map` 门禁 ⑭ | S |
| D9 | 体力归零没有后果 | corridor.gd / day_cycle.gd | ✅ 已还（2026-11-25）：`DayCycle.down()` 沉积 -1 + 翻页 + 回学校 + 体力 0.3；门禁 `down` | S |
| D10 | 敌人无寻路、无听觉 | enemy.gd | ✅ 已还（2026-11-25）：≥3 噪声引向声源 2 秒、看见优先；门禁 `enemy_hearing` | M |
| D11 | 房间级状态缺失（灯光/敌人/容器按区） | corridor.gd | ✅ 已还（2026-11-25）：A/B/C 独立灯光档 + 平滑过渡，容器/敌人按区；门禁 `room_light` | M |
| D12 | 卡牌只在 headless 回放里跑 | data/cards | ✅ 已还（2026-11-25）：每天抽 1 张写 world_state，`RunState.world_vars` 持久化；门禁 `card_day` | L |
| D13 | `bond`/同伴未实现 | data/npcs | 「军队」「背弃」「替身」三个结局没有前置 | L |
| D14 | 菜单「继续」只提示、不加载场景 | main_menu.gd | 读档进不去游戏 | S |

## 工程债（不还迟早出事）

| # | 欠账 | 位置 | 影响 | 量 |
|---|---|---|---|---|
| D15 | 字体图集要手动重建 | tools/font_build.py | ✅ 已还（2026-11-25）：`--check` 只读覆盖门禁进 pipeline，卡牌/结局文案已入图集（792 字） | S |
| D22 | 无数据上报（TapDB） | game/runtime/tapdb_service.gd | 客户端直连已接（2026-11-25）；待 ClientID + 后台事件登记 + 导出包实机验证 | M |
| D23 | 发布管线未配置 | 仓库根 | 无 `export_presets.cfg`；本机无 Node/`taptap-cli`、无开发者上下文；流程见 `design/TAPTAP.md` | M |
| D16 | `psd-tools` 未进 CI | requirements-tools.txt | 换机器导不出 PSD | S |
| D17 | 存档只有 schema 字符串，无版本迁移 | run_state.gd | 改字段就废档 | M |
| D18 | 截图证据靠门禁顺手生成，没有 diff 基线 | design/previews | 观感回归只能靠肉眼 | M |

## 原五阶段路线还欠（观感线）

| # | 欠账 | 说明 |
|---|---|---|
| D19 | **Stage 3** 地面接缝/磨损/散落物 | 最初定的五阶段里唯一完全没动的一项 |
| D20 | **Stage 4** 前景遮挡与玩家可读性 | 现在没有前景层，遮挡关系靠 z_index 硬排 |
| D21 | **Stage 5** HUD 重构（参照精品 2D 生存恐怖） | 现在是功能性的，谈不上设计 |

---

# 三、建议顺序

```
M2a（D1+D3+D4） → D5 结局解锁 → D6 校验覆盖 → M2a-2（D2 noise）
→ D14 继续按钮 → D8 我在这 → D9 死亡后果 → D10/D11 → D7 多楼美术 → D19~D21 观感线
```

理由：D1–D6 都是「数据说一套、代码做一套」，不还就会越写越歪；D7 之后是内容量，可以并行做。
`health` 进数据模型（M2c）排到最后——它是改契约，收益远小于成本。
