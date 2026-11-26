# v0.7.1 执行基线 · 对照与刷新（2026-11-26）

> 对象：[`残余信号_v0.7.1_进度对照版.html`](../../../Downloads/残余信号_v0.7.1_进度对照版.html)（仓库外，单文件）。
> 它是**发给开发 Agent 的执行基线**，不是实时面板；`§01` 里写明「本版未检测到仓库新提交，进度数字沿用该快照，需你用 `progress.json` 刷新」。
> 本文就是那次刷新的记录：**P1–P10 决策一条没动，只把进度数字与证据对齐到仓库实测。**

---

## 一、基线与现状

| 项 | HTML 写的 | 仓库实际 |
|---|---|---|
| 审计基线 | `9758e3c`（2026-11-25） | `9758e3c` 是**祖先**，不是 HEAD |
| 当前 HEAD | — | `d192703`（2026-11-26） |
| 基线之后的提交 | 「未检测到」 | 5 个业务提交 + 3 个接手提交（见下） |
| 门禁 | — | 基线 51 步 / 38 条 / **9 条 broken** → 现在 **38/38 全绿，144 秒** |
| 进度真源 | 本 HTML 表格 | 仓库根 **`progress.json`**（本轮新增） |

基线之后的提交：

```
d192703 docs(takeover): 补 Node 24 + taptap-cli 2026.11.25（已装、未登录）
2c0c505 docs(takeover): 新机器接手记录 + D24 销账（38/38 门禁全绿）
8c95ae9 fix(gates): 还清 D24 -- 6 条门禁改回真渲染 + runner 不再误判 WARNING
75d7348 docs(debt): D24 标题与 2026-11-26 复测口径一致
c7c3b9d docs(handoff): 本轮状态对齐（D24 复测 / 手机线与引导 / 发布管线）
```

---

## 二、13 个模块逐条对照

**判定规则**：只有「代码在 + 门禁/自测在跑 + 能给出 grep 证据」才算 `done`；有数据/素材但没接进玩法算 `partial`；只有计划算 `not_started`。

| # | 模块 | HTML 判定 | **实测判定** | 证据 / 缺口 |
|---|---|---|---|---|
| 1 | 垂直切片 | done | **done 100%** | 38 条 Godot 门禁全绿；学校走廊闭环可玩 |
| 2 | 数据层 + 47 规则 | done | **done 100%** | `validate.py` 47 条 0/0/0；`selftest.py` **25 个夹具全开火** |
| 3 | 像素 + 字体管线 | done（802 字） | **done 100%**（802 字） | `PF-02_cjk_12.json` 的 `characters` 实测 **802**；仓库旧文档写 792，**旧文档错** |
| 4 | 多点触控 / 横屏 | partial | **partial 60%** | `game/ui/touch_controls.gd` **384 行** + `TOUCH_OK buttons=12` 通过；缺统一 InputAction（手柄/自适应）、色盲与震动开关 |
| 5 | 存档 SaveState v1 | not_started | **not_started 0%** | `run_state.gd:save()` 直接 `FileAccess.WRITE`，无 tmp/rename/备份/校验；门/容器/背包/敌人/NPC 记忆不进档 —— **与 HTML 判断完全一致** |
| 6 | 模式内核 | not_started | **not_started 0%** | `data/mode_profile.json` 已有 `story/endless/shared` 三档**数据**；`RunState` 无 `mode` 字段、无 `ModePolicy` 类、菜单无选择 |
| 7 | EntityRegistry | not_started | **not_started 0%** | 全仓库 `EntityRegistry` / `stable_id` 零命中 |
| 8 | L0 Fact / Assertion | not_started | **not_started 0%** | 只有 `L0/events.jsonl`（append-only），无 fact/assertion 分离、无 `branch_id` |
| 9 | 回响层三项 | not_started | **not_started 0%** | `RunState` 无 door 持久化、无 `transfer_log`、时钟未模糊 |
| 10 | 消防站开场切片 | not_started | **partial 20%** | `data/templates/fire_station.json` + `props_fire_station.tscn`（主题美术 v1）已在；**可玩切片没有** |
| 11 | Android arm64 构建 + 真机 | not_started（「无 APK」） | **partial 30%** | `export_presets.cfg` 基线就有 Windows + Android 两条；旧机产出过 49.6MB 已签名 APK；**本机无产物、无真机、无 10 台矩阵** |
| 12 | 设置/隐私页 + 崩溃 opt-in + 6 音效 | not_started | **partial 40%** | 设置页 + 隐私同意**基线就已有**（`main_menu.gd` 25 处命中）；缺崩溃 opt-in（`crash` 零命中）、6 音效（`sounds.json` 有 20 个事件定义、0 播放代码、0 音频文件） |
| 13 | 受邀封测包 | not_started | **not_started 0%** | 本轮刚补 `LICENSE`/`NOTICE`；规则 CI 已绿（2026-11-26 首跑，badge passing）；封测包与 10–20 人流程未开始 |

---

## 三、HTML 里需要修正的 6 处（否则下一个 Agent 会重复劳动）

1. **设置/隐私页已存在**（基线 `9758e3c:game/scenes/main_menu.gd` 就含设置页与隐私同意，`MENU_OK settings=yes`）。
   本轮只需补「崩溃 opt-in」，不要重做设置页。
2. **触控不是"原型"**：`touch_controls.gd` 384 行 + 门禁通过；W3 要做的是「统一 InputAction / 自适应 / 手柄」，不是从零做触控。
3. **Android 预设已存在**：`export_presets.cfg` 在基线就有两条；「不可复现」是本机环境问题（引擎/模板不在库），不是从零建链。
4. **卡牌 18 张（12 L + 6 S），不是 12 张**：`data/cards/layer_l.json`=12、5 个 `layer_s_*.json` 合计 6。卡片数已超 HTML 目标，别再排"补卡"。
5. **NPC 实测 13 个**（`data/npcs/npcs.json` → `npcs` 长度 13），HTML 的「20 NPC」是目标不是现状；W2 内容活里应写「13 → 20」。
6. **「16 节点全内容未开始」要拆开看**：拓扑 16 节点**已实现并在运行**（`smoke.gd` → `nodes=16`）；未开始的是「每楼独立检查文本与容器池」。写成"16 节点未开始"会让 Agent 去重建已有拓扑。

> 另有两处文档级陈旧（非 HTML 的错，是仓库自己的）：
> - `README.md` / `TECH_DEBT.md` 的 D15 写「792 字」，实测图集 **802 字**；
> - `THIRD_PARTY_LICENSES.json` 声明的 Vonwaon / Fusion 两款点阵字体**并未被 `tools/font_build.py` 使用**
>   （PF-01 程序生成、PF-02 用 NotoSansSC）——发行前要么真接入、要么从台账移除，见 `NOTICE` §5。

---

## 四、复跑命令（改任何数字前后都跑这两条）

```powershell
$PY = "C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"

& $PY tools/validate.py     # 期望：共 47 条规则：ERROR 0 · WARN 0 · SKIP 0
& $PY tools/selftest.py     # 期望：25 个 [PASS]，0 个 [FAIL]
powershell -NoProfile -File tools\run_gates.ps1   # 期望：ALL PASS (38)，约 144 秒
```

改模块状态时**只改 `progress.json`**，不要改这份对照表（它是 2026-11-26 的快照 + 证据）。
`status` 只许取 `done / partial / not_started / deferred`；标 `done` 的前提是「对应门禁/自测全绿 + 有 grep 证据」。

---

## 五、下一步（与 HTML §05 对齐）

**W1（先做）**：`SaveState v1`（原子双槽 + `.bak` + schema 迁移 + 50 次杀进程/断电门禁）→ `EntityRegistry`（stable ID）
→ `mode` 字段 + `ModePolicy`（数据档案已有）→ `L0` Fact/Assertion 分离 + `branch_id`。

**W2**：回响层三项（门状态/物品轨迹/时间可见度）→ 消防站开场切片 → Android arm64 可复现构建 + 10 台烟测。
**W3**：统一 InputAction / 自适应触控 → 6 音效 → 崩溃 opt-in → 两开场教学漏斗。
**W4**：LICENSE/NOTICE/AI 台账（本轮已起头）→ CI（**本轮已绿**：validate + selftest + gd_sanity）→ 内容评审 → TapTap 材料 → 受邀小测。

> TapTap 现状：**CLI 已装、未登录；无 app、无包体上传、资质四项未办**。
> 这符合 P3（先离线受邀 Android 小测，TapTap 封测为下一步），不要提前做。
