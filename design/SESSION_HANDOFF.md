# SESSION HANDOFF · 换会话从这里开始

> 上一会话结束：2026-11-26。远端 `main` = `ebe33e7`（本文件所在提交在其之上）。
> 项目长文档：[`HANDOFF-STAGE2.md`](HANDOFF-STAGE2.md)；欠账论证：[`TECH_DEBT.md`](TECH_DEBT.md)。
> **本文只讲「怎么立刻开工」。**

---

## 1. 一句话现状

384×216 像素风 30 天生存叙事（Godot 4.7 / GL Compatibility）。
主线已通：**主界面 → 走廊搜刮·战斗·状态 → 出口旅行图选楼 → 结算 → 真场景切换 → 结局判定写档案**。
最近一轮还接上了：逐区灯光（D11）、事件卡进玩法（D12）、敌人听觉（D10）、死亡倒下（D9）、
五楼主题美术（D7 v1）、字体图集覆盖门禁（D15）、TapDB 上报。

**先看第 5 节「文档会滞后」**：`TECH_DEBT.md` 里有几条已做完但没打勾（D3/D4/D14 我已按代码实测确认完成）。
**别信表格，信代码与门禁。**

---

## 2. 三十秒验一遍（先确认没坏）

```powershell
python tools/validate.py     # 期望：共 47 条规则：ERROR 0 · WARN 0 · SKIP 0
python tools/selftest.py     # 期望：全部通过（含 R44-R47 的坏夹具）

# 门禁（36 条已登记；渲染/无头参数由脚本从 pipeline.json 读，别手抄）
powershell -NoProfile -File tools\run_gates.ps1
powershell -NoProfile -File tools\run_gates.ps1 -Only corridor   # 只跑名字含 corridor 的
```

**当前不全绿，这是已知状态**：上次实测 6 条新登记的直接通过（display / inventory / loot /
replay-30d / shell / status），9 条失效（见 3.0 的 D24），其余上游已登记项本轮未逐条复跑。
所以先看 `pipeline.json` 里 `status` 字段：`ready` 表示该条最近验证过，`broken` 表示已知失效。

- `.tools/register_gates.py` 可自动补登记缺失的门禁；新门禁必须登记，否则跑不全还看着绿
- 带「需渲染」的门禁**不能加 `--headless`**，否则截图/光照断言拿不到
- 跑全量大约 30 分钟；用 `-Only` 分批更实际

---

## 3. 下一批活（按大小排）

### 3.0 先修安全网：D24（第一步就该做）

上一轮我把 15 条没登记的门禁补进 `pipeline.json` 后**实测**，发现旧门禁在 `ebe33e7` 上已经失效：

| 门禁 | 症状 |
|---|---|
| `animation` | `ANIMATION_FAILED count=1` |
| `corridor-combat` | `CORRIDOR_COMBAT_FAILED count=1` |
| `corridor-inspect` | `CORRIDOR_INSPECT_FAILED count=1` |
| `corridor-status` | `CORRIDOR_STATUS_FAILED count=1` |
| `traverse` | `TRAVERSE_FAIL player missing` |
| `corridor-preview` / `-doors` / `-inventory` / `-loot` | **卡死 >300s 无任何结论**（不是慢，是真的不退出） |

这几条守着搜刮/战斗/状态/走廊渲染 —— 它们坏了就等于**没有安全网**。
`pipeline.json` 里已把这 9 条标成 `"status": "broken"`（跑 `run_gates.ps1` 仍会跑到，方便边修边验）。

**怀疑方向**（未证实，别当结论）：`traverse` 的 `player missing` 与卡死都指向
「场景里 `Player` 节点的生命周期/名字被上游改动动过」（D9 倒下、D11 逐区灯光的改动都碰过 corridor）。
先看 `corridor.tscn` 的节点名与 `corridor.gd` 的 `_ready()` 顺序，再看卡死门禁是不是在等一个永不触发的信号。

### 3.1 小（每条半天内）

| 项 | 位置 | 现状 | 验收 |
|---|---|---|---|
| **D16** `psd-tools` 未进 CI | `requirements-tools.txt`、`pipeline.json` | 只在 requirements 里声明，CI 不装 | pipeline 加一步安装 + 导出 PSD 成功 |
| **D17** 存档无版本迁移 | `game/runtime/run_state.gd` | 只有 `schema: "run-state.v1"` 字符串 | 老档（v0/缺字段）读入后字段补齐且不丢数据 |
| **D18** 截图无基线 | `design/previews`、门禁 | 门禁顺手生成，没有 diff | 预览图存 hash，变了必须显式更新 |

### 3.2 中（一轮）

- **D7 收尾**：`HANDOFF-STAGE2.md` 末尾「已知后续（D7 未完成部分）」列了剩余项（各楼专属 props/容器差异未全覆盖）
- **D22 TapDB 文档对齐**：提交里有 TapDB 客户端直连，但欠账表仍标 TODO —— 先核对再决定是否打勾
- **D23 发布管线**：TapTap CLI 文档已收束，实际打包/上传还没验证

### 3.3 大（多轮）

- **D13 `bond` / 同伴**：`RunState` 有 `companions_alive/lost/bond` 字段但没人写；
  **「军队」结局因此不可达**（要 `companions_alive ≥ 2`）。这是唯一还缺的主线系统。
- **D19–D21 观感线**：Stage 3 地面接缝/磨损、Stage 4 前景遮挡、Stage 5 HUD 重构（原五阶段里未动的三项）

---

## 4. 六个坑与规矩（都真踩过）

| 坑 | 规矩 |
|---|---|
| `git fetch` 失败后 `git reset --hard origin/main` 删本地提交（2 次） | 只跑 `.tools/sync_local.ps1`：fetch 不成功就什么都不动 |
| PowerShell 整文件重写把中文读成乱码（3 次，最近是 `.ps1` 脚本本身） | 改 UTF-8 只用 `edit`/`write`；**`.ps1` 保持纯 ASCII**；`Get-Content` 查看看必须 `-Encoding utf8` |
| git 传输被 reset（频繁） | 远端已前进时先 `fetch` 再 `rebase`；推不上去用 `.tools/push_files.py --parent <远端sha> --files ...` |
| 判断「远端有没有我的提交」 | 比**树哈希**（`git rev-parse HEAD^{tree}` vs API `commit.tree.sha`），不信 `origin/main` |
| 未类型化数组传给 `Array[String]` 参数 | 运行时抛错会中断协程 → 进程挂着像卡死；门禁里显式声明类型 |
| 门禁写了没登记 | `run_gates.ps1` 只跑登记过的；新增门禁必须登记并确认条数 |

两条工程纪律：

- **新数据/新样式先写规则再写数据**，并用 `tools/selftest.py` 的坏夹具证明规则**会开火**——
  只看「0 报错」分不清“数据干净”和“规则读错字段、静默跳过”。
- GDScript 闭包**按值捕获**，要回传用字典承接（`capture["x"] = v`）。

---

## 5. 文档会滞后（这次实测到的）

按代码核对，**以下三条在 `TECH_DEBT.md` 里仍标 TODO，但代码已经做了**：

| 项 | 证据 |
|---|---|
| D3 `actions_left` 消耗 | `corridor.gd`：`_run.actions_left = maxi(0, _run.actions_left - 1)`，结算后重置为 `actions_per_day`；门禁 `m2a-actions` |
| D4 燃料产出 | `corridor.gd`：`_fuel = mini(FUEL_MAX, _fuel + 1)`；门禁 `travel-fuel` |
| D14 菜单继续加载场景 | `main_menu.gd`：`tree.change_scene_to_file("res://game/scenes/corridor.tscn")` |

所以接手第一件事：**跑全量门禁 → 用 grep 核对欠账表 → 更新表格**，再决定做什么。

---

## 6. 文件地图

| 想改什么 | 去哪 |
|---|---|
| 走廊玩法（搜刮/战斗/状态/出口/手电/逐区灯光） | `game/scenes/corridor.gd`（2000+ 行，唯一玩法大文件） |
| 旅行图（2.5D 楼块、标注、选楼、我在这） | `game/scenes/travel_map.gd` + `data/travel/map_layout.json` |
| 建筑/路线/一天几次/燃料 | `data/travel/routes.json` |
| 跨场景状态与存档 | `game/runtime/run_state.gd`（`user://run.json`） |
| 六组世界变量、沉积、噪声 | `game/runtime/world_state.gd` |
| 一天结算 | `game/runtime/day_cycle.gd`（返回 `supplies_delta`） |
| 事件卡 | `game/runtime/card_engine.gd` + `data/cards/*.json` |
| 结局判定与档案 | `game/runtime/ending_book.gd` + `data/endings/*.json` |
| 物品/容器/掉落 | `data/loot/items.json`、`containers.json` |
| 状态（伤口/感染/中毒/成瘾） | `data/systems/status.json` |
| 字体图集（加新文案会缺字） | `tools/font_build.py` → 重建 atlas → 跑 `--import`；已有覆盖门禁 |
| 校验规则 | `tools/validate.py`（R44–R47 最近加的）+ `tools/selftest.py` |
| 一键跑门禁 | `tools/run_gates.ps1`（纯 ASCII） |
