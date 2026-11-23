# BACKLOG · 常驻队列

> 三个执行模型（dev / aux / dev2）从这里取活。**每一项都写着「谁证明它做完了」**——
> 没有验收命令的条目不许进队列。

## 状态说明

`READY` 可直接开工 · `BLOCKED` 等前置 · `NEEDS-DEC` 需开会拍板

---

## 第一梯队（程序线，dev 主责）

| # | 项 | 产 | 验收 | 状态 |
|---|---|---|---|---|
| P1 | `data_layer.gd` 等 5 个类真编译 | `game/runtime/*.gd` | `godot --headless --check-only` 全过 | **DONE**（Godot 4.7-stable；首跑 4 过 1 挂，`main.gd` 3 处 void 赋值 + 3 个自造变量，已修） |
| P2 | 世界状态仓库 `world_state.gd` | 变量六组 + 节点沉积 + 时间跳格 | `gd_sanity.py --require` 全绿 | **DONE**（253 行 / 0 结构问题；单测待 Godot） |
| P3 | 游戏壳 `main.gd` 最小闭环 | 读节点 → 一次行动 → 存读 | `gd_sanity.py --allow-print` 全绿 | **DONE**（205 行 / 0 结构问题；开窗需 Godot） |
| P4 | 事件卡引擎 `card_engine.gd` | 条件命中 → 绑槽 → 效果 → 返回 L0 条目 | `gd_sanity.py --require` 全绿 + R39 全过 | **DONE**（282 行 / 0 结构问题；R39 抓到 5 条死效果已修） |
| P5 | 记忆层 `memory.gd` | L0/L1/L2 + fidelity 3→0 + L2 渲染 | `gd_sanity` 全绿 + **R40 五组样例** + 负例能抓 | **DONE**（271 行；R40 负例验证通过） |

## 第二梯队（内容线）

| # | 项 | 产 | 验收 | 状态 |
|---|---|---|---|---|
| C1 | NPC 池结构定案 | DEC | 会议结论落 DEC | **DONE**（DEC-20261122-npc-pool：8 共享 + 每模板 4 专属 = 28） |
| C2 | 学校 S 层 2 张卡 | `data/cards/layer_s_school.json` | R29 转 PASS 且 card_id 真实存在 | **DONE**（2 张；R29 已升级为真查存在性） |
| C3 | `data/npcs/npcs.json` 首批 3 张 | 状态卡 + 记忆样例 | R12/R13/R36 转 PASS | **DONE**（3 张：老师/学生/传达室；R36 负例验证 3 个 ERROR） |
| C4 | 模板 T1–T4 | `data/templates/*.json` | R18/R27/R28/R37/R38 转 PASS | **DONE**（4 份；噪声单位已规范为整数） |
| C5 | 六个教学节拍标注校验 | 规则 **R41**（编号顺延，R36 已被记忆满格占用） | 六拍各一次 + 相邻 ≤3 跳 | **DONE**（R41 全绿） |

## 第三梯队（美术线，需人）

| # | 项 | 产 | 验收 | 状态 |
|---|---|---|---|---|
| A1 | 调色板 guide 三张 | 光源角度 / 禁渐变反例 / 分区用途 | 三张都过像素门禁 | **DONE**（`design/guides/` 三张，5/9/30 色，PASS） |
| A2 | 签核第一条资产 | `approved/` 出现第一个文件 | R21 首次触发 | NEEDS-DEC（谁签） |
| A3 | tile 基础集 40 张 | `TL-0x_*.png` | `asset_intake --spec` 全过 | READY |
| A4 | 20 张丧尸化派生 | 从母体派生 | R25 语义校验 | **DONE**（21 张：7 具母体 × 3 帧） |

---

## 2026-11-23 · P0 修复批次（本机 Godot 4.7.2 实跑，DONE）

> 详细记录见 [`HANDOFF-STAGE2.md`](HANDOFF-STAGE2.md) 第七节；每一项都有可复跑的验收命令。

| # | 项 | 验收 | 状态 |
|---|---|---|---|
| P6 | 检查框双输入路径（真键盘开一帧即关） | `corridor_inspect.gd` → `CORRIDOR_INSPECT_OK records=15` | **DONE**（`19c184f`） |
| P7 | 卡效果空转（读 `add_vars`，数据是 `effects[].vars`） | `replay_30d.gd` 不变量 ⑤ + `changed>0` | **DONE**（`f447071`） |
| P8 | `DataLayer` 取数接口用错（夜晚倍率/沉积传导/锁门/NPC 引用恒 null） | `smoke.gd` 夜间倍率 2→3、Day14/15 锁门 | **DONE**（`f447071`） |
| P9 | `main.gd` 死代码 + JSON 存档往返恒失败 | `game/tests/shell.gd` → `SHELL_OK ... six_vars_in_0..1=true` | **DONE**（`e38bdfd`） |
| P10 | 输入台账 20/23 | `validate.py --inventory` → 23/23 | **DONE**（`cf290af`） |
| P11 | 主角放大（32×48 原生帧，可见 41px） | `pixelpipe gate` 三帧 PASS + `corridor_preview` 角色断言 | **DONE**（Stage 2.5） |
| P12 | WASD 纵深移动 + 下方区域可走 | `CORRIDOR_OK` 深度移动断言 + `CORRIDOR-QA_depth.png` | **DONE**（Stage 2.5） |
| A2 | 签核第一条资产让 R21 开火 | `approved/` 出现第一个文件 | **NEEDS-DEC**（需要人签，仍空） |

## 队列纪律（三模型共守）

1. **先看验收命令，再动手。** 做完必须自己跑一遍并把输出贴进当轮汇报。
2. **一次只领一梯队里的一项**，不要并行开三件半成品。
3. **规则改了必须重跑 `tools/selftest.py`** —— 上次 R14 改动让 fixture 静默失效，这个坑踩过。
4. 遇到这两类情况**停下开会**（`tools/council.py`）：
   - 验收命令本身写不出来（说明还没想清楚）
   - 两条路都能过验收，但代价不同（说明是取舍，不是执行）
5. 不许为了过验收而修改验收标准。改标准要单独提，写进 DEC。
