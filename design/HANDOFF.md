# HANDOFF · 残余信号 数据层与工具链

> 写给下一个接手的人（或下一个模型）。**十轮自动推进的产物全在这里，包括没做到的。**
>
> ⚠️ **时效说明（2026-11-23）**：本文写于本机还没有 Godot 的时候，所以「从未编译」「无 Godot」
> 之类的判断**已经过期**。当前状态请先看 [`HANDOFF-STAGE2.md`](HANDOFF-STAGE2.md)。

---

## 一、现在是什么状态

| 层 | 能跑 | 不能跑 |
|---|---|---|
| 校验器 | `validate.py` 43 条规则，SKIP 归零 | — |
| 数据 | 全部 JSON 通过静态校验；Python 镜像跑到 Day 30 不变量成立 | — |
| 运行时 | 5 个 GDScript 类，**结构检查全过** | **从未编译**（本机无 Godot） |
| 美术 | 32 条资产全部过像素门禁 | `approved/` 是空的，**R21 从未触发** |

一句话：**数据是真的，代码是没验过的，美术是没签过的。**

---

## 二、两个卡点，各自的解法

### 卡点 1 · P1 编译（阻塞整条程序线）

1479 行 GDScript 一行都没被编译器看过。`gd_sanity.py` 只查括号、缩进、API 是否存在。

```powershell
# 解卡：装好 Godot 4 之后
godot --headless --check-only --script game/runtime/data_layer.gd
godot --headless --check-only --script game/runtime/world_state.gd
godot --headless --check-only --script game/runtime/card_engine.gd
godot --headless --check-only --script game/runtime/memory.gd
godot --headless --check-only --script game/runtime/main.gd
```

**最可能出错的地方**（我写的时候就存疑）：
- `Array[Dictionary]` 的显式类型在 `duplicate(true)` 之后是否保型
- `world_state.gd` 里 `float` 与 `int` 混算的隐式转换
- `card_engine.gd` 的 `hash()` 取模是否稳定跨平台

### 卡点 2 · A2 签核（阻塞 R21 的可信度）

`art/asset-manifest.json` 里 32 条全是 `status: draft`。R21 的逻辑写了、自测过了，但**从没在真实数据上触发过**。

```json
// 签一条的样子
"status": "approved",
"reviewer": "<你的名字>",
"approved_at": "2026-11-23"
```

**R21 会查三件事**：pixel gate 通过 + reviewer/approved_at 存在 + AI_LEDGER 有对应条目。手工跳过任何一项都会被拦——但它到底拦不拦得住，只有真跑一次才知道。

---

## 三、43 条规则速查

| 组 | 编号 | 管什么 |
|---|---|---|
| 拓扑 | R01–R09 | node_id 唯一 / 主轴连续 / 房间只挂一段 / 链接对称 / 至少一个安全屋 / BFS 可达 / 模板 sediment=0 / 词表引用 / 时间轴冲突 |
| 预算与传导 | R10–R13 | 预算 + loot 潮汐 / 噪声传导声明 / 记忆指回 L0 / fidelity 单调 |
| 像素 | R14 | 16 网格 / 整数倍 / 色集在板内 / 无半透边缘 / **逐格 ≤16 色** |
| 动画音频 | R15–R16 | 武器 tag 契约 / 每个事件有 asset_key |
| 模式与存档 | R17–R19 | 无尽无存档 / 模板不改写 / **v1→v2 语义等价** |
| 美术治理 | R20–R25 | provenance / 人审 / 漂移只报警 / 授权 / 背景视差 / **派生体配件位** |
| 卡池 | R26–R28 | L 层禁专名 / 进场日 / 噪声预算 |
| 安全屋 | R29 | 每模板恰好一次失效，且卡真实存在 |
| 拓扑防守 | R30 | 房间不得旁路主轴 |
| 归属标记 | R31 | 3×5、五档、Day3 褪尽、不许常驻 |
| 音频定位 | R32 | 无音乐/无循环层；direction_cue 必须可定位；文件须单声道 |
| 依赖爆炸 | R33–R35 | 卡间禁引用 / trigger 嵌套 ≤3 / 只碰六组变量 |
| 记忆满格 | R36 | 五槽齐全、fidelity=3、trace 起点对齐 |
| 噪声单位 | R37–R38 | 必须是整数 / 每模板要有安静选项 |
| 效果可达 | R39 | `when` 必须逐字等于某个 slot option |
| 渲染验收 | R40 | 分档不许漏槽 + 反例自检 |
| 教学节拍 | R41 | 六拍各一次，相邻 ≤3 跳 |
| 卡池规模 | R42 | 宽窗口卡必须显式签核 |
| 数据↔美术 | R43 | NPC 卡的配件位必须与精灵逐位一致 |

**规则改了必须重跑 `python tools/selftest.py`。** 这条踩过两次：改动 R14 和 R20 之后 fixture 静默失效，规则不再开火而自测报"未开火"，才发现。

---

## 四、四个已拍板决策（`design/decisions/`）

| DEC | 结论 |
|---|---|
| art-budget | 美术 60% 压在三个宣传帧；像素规格首周冻结 |
| marker | 归属标记暖橙 3×5，**只在 Day 0–2**，Day 3 断电当夜褪尽 |
| audio | 7 人日全押「声音定位」，无音乐、无环境循环层 |
| npc-pool | 8 共享（关系占位）+ 每模板 4 专属 = 28 池 |

---

## 五、工具清单

| 工具 | 用途 | 验收命令 |
|---|---|---|
| `validate.py` | 43 条规则 | `python tools/validate.py` |
| `selftest.py` | 规则能不能开火 | `python tools/selftest.py` |
| `gd_sanity.py` | GDScript 结构（不是编译） | `python tools/gd_sanity.py game/runtime/*.gd` |
| `headless_30d.py` | **数据语义 30 天回放** | `python tools/headless_30d.py --seeds 3` |
| `pixelpipe.py` | 门禁 / 转换 / tile 构造 | `... gate <png> --palette ... --max-colors 16` |
| `asset_intake.py` | 门禁→manifest | `... --spec <candidates.json>` |
| `char_build.py` | 角色与派生构造 | `python tools/char_build.py` |
| `sync_npc_slots.py` | 代码→数据的配件位同步 | `python tools/sync_npc_slots.py` |
| `council.py` | 三方对齐会 | `... --topic <md> --roles dev,aux,dev2` |
| `agents.py` | 三角色模型客户端 | `python tools/agents.py ping` |

---

## 六、已知欠账（不粉饰）

> **2026-11-23 更新**：下面第 1、2 条已不成立 —— `returns_after_days` 已实现
> （`card_engine.gd:31-37`，值为 0 时永久跳过），`pick_and_fire` 已改为
> 「新卡 → 最久未触发 → id」三档轮转（`:164-200`），不会饥饿。
> 当前真实缺口与修复记录见 [`HANDOFF-STAGE2.md`](HANDOFF-STAGE2.md) 第七节。

1. **`returns_after_days` 从未被实现**。`card_engine.gd` 的契约里没写，`headless_30d.py` 里是我第 10 轮才补的。**运行时必须补上**，否则标着「只发生一次」的卡会天天触发。
2. **`pick_and_fire` 按字典序取第一个**，会导致卡池饥饿（同一张卡反复触发，别的永远轮不上）。需要冷却或轮转。
3. **R40 只抓「漏出来的」，抓不住「补进去的」**。「戴眼镜」是黑名单兜的，不是白名单。严格做法要中文分词 + 词表。
4. **R42 被改过三次口径**，最终只能「点名 + 要签核」，做不到自动判断对错。这个上限写在代码注释里。
5. **12 张卡里 8 张要求节点带 tag**，而主轴走廊没有那些 tag —— 玩家必须进房间才看得到大部分卡。设计上可能是对的，但**没试玩过不能确认**。
6. **所有角色精灵是 blockout**。配件只有 1–2 像素，32×32 下能区分人，离「一眼认出这是谁」差人手。
7. **`tile` 每格最深 6 色**，spec 的软目标是 ≤4。硬上限 16 没破。

---

## 七、接手第一天做三件事

1. **装 Godot，跑那五条 `--check-only`** —— 这是唯一能证明 1479 行不是废纸的办法。
2. **签一条资产，看 R21 是不是真拦得住** —— 故意漏填 `reviewer` 试一次，它应该报错。
3. **补 `returns_after_days` 到 `card_engine.gd`** —— 这是目前唯一已知的、会直接表现为「玩法不对」的缺口。
