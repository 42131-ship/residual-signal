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

# 门禁（51 条已登记；渲染/无头参数由脚本从 pipeline.json 读，别手抄）
powershell -NoProfile -File tools\run_gates.ps1
powershell -NoProfile -File tools\run_gates.ps1 -Only corridor   # 只跑名字含 corridor 的
```

**当前不全绿，这是已知状态**：2026-11-26 复测到的是 —— `traverse` **已恢复**（`TRAVERSE_OK`），
`animation` 与 `corridor-status` **仍然挂死**（>2.5min / >5min 无任何结论），其余 6 条未复跑（见 3.0 的 D24）。
所以先看 `pipeline.json` 里 `status`：`ready` = 最近验证过，`broken` = 已知失效。**但 `traverse` 那条的 `broken` 是陈旧的**。

- `.tools/register_gates.py` 可自动补登记缺失的门禁；新门禁必须登记，否则跑不全还看着绿
- 带「需渲染」的门禁**不能加 `--headless`**，否则截图/光照断言拿不到
- 跑全量大约 30 分钟；用 `-Only` 分批更实际

发布侧（2026-11-26 已装好并**已登录**，细节见 `design/TAPTAP.md` §2/§2.1）：本机 Node 24.19.0 在但**没有 npm**，
所以用便携 npm（`.tools\npm\package\bin\npm-cli.js`）装了 `@taptap/cli 2026.11.24` 到 `.tools\npm-global`。
每个新 shell 先 `$env:Path = "D:\Downloads\残余信号\.tools\npm-global;$env:Path"`，再 `taptap-cli doctor`（应全绿）。
厂商 `starxin的工作室` = `developerId 489018`；名下唯一游戏是 `感染之夜`（`appId 991852`，与本项目无关），
**残余信号还没有 app**，要发就得先 `app create`（写操作，先 `--dry-run`）。

手机侧（2026-11-26，细节见 [`MOBILE.md`](MOBILE.md)）：`export_presets.cfg` 已建（Windows + Android），
模板 APK 路线打通，产出 `build/android/ResidualSignal-{debug,release}.apk`（arm64 / 已签名 / 51.4 & 49.6 MB）。
触摸层 `game/ui/touch_controls.gd` + `game/runtime/mobile_support.gd` 已挂进走廊与主菜单，
门禁 `touch-controls` 已登记（现在共 51 条）。导出用 **4.7.2** 引擎（模板只有 4.7.2），**跑门禁仍用 4.7**。
**真机还没测过**（本机没有设备）；未做项与验收方式见 `MOBILE.md` §7。

引导（2026-11-26）：`game/runtime/tutorial.gd` 三步（走 → 搜 → 出门），只由玩法事件推进，
状态存 `RunState.tutorial_step`（老档缺键当 0）；门禁 `tutorial`。
新档第一次进走廊会在 HUD 顶部显示一行提示，走完 6 步 → 搜一次 → 出一次门后自动消失。

发行与方向（2026-11-26 新增两份文档，先看它们再排活）：
[`RELEASE_FEASIBILITY.md`](RELEASE_FEASIBILITY.md) —— 服务端实测：在「离线单机 + 免费 + 无内购」这组事实下
**版号被判 optional**，必交的是隐私/防沉迷/AI 声明/适龄；`app create` 的 dry-run 已通过。
[`NEXT.md`](NEXT.md) —— 结论是**手机优先**（5–10 分钟一局、离线、免费），PC 作为同内容第二平台；
P0 真机手感 → P1 内容扩容（D13 同伴 / 每楼文本池 / 卡 18→40 / 结局 4→6）→ P2 工程安全（D24）。

---

## 3. 下一批活（按大小排）

### 3.0 先修安全网：D24（第一步就该做）

上一轮把 15 条没登记的门禁补进 `pipeline.json` 后实测，发现旧门禁在 `ebe33e7` 上失效。
**2026-11-26 复测后的真实状态**（别照抄老表）：

| 门禁 | 2026-11-26 实测 | 下一步 |
|---|---|---|
| `traverse` | **已恢复**：`TRAVERSE_OK waypoints=8 bounds=588x88 corners=4 center=1 leaks=0` | 把 `pipeline.json` 的 `status` 从 `broken` 改回 `ready` |
| `animation` | 复跑**挂死** >150s，无任何结论 | 找等待点：不是断言失败，是永不触发的信号 |
| `corridor-status` | 复跑**挂死** >5min，无任何结论 | 同上；先看它 `await` 了什么 |
| `corridor-combat` / `-inspect` | 未复跑（上轮记 `CORRIDOR_*_FAILED count=1`） | 真跑一次再判断 |
| `corridor-preview` / `-doors` / `-inventory` / `-loot` | 未复跑（上轮记卡死 >300s） | 真跑一次再判断 |

这几条守着搜刮/战斗/状态/走廊渲染 —— 坏了就等于**没有安全网**。
`pipeline.json` 里仍是 `"status": "broken"`（`run_gates.ps1` 照跑，方便边修边验），但**`traverse` 那条已经过期**。

**怀疑方向**（部分已被推翻）：`traverse` 不是节点改名问题——它现在直接过。
剩下两条挂死的更像「协程在等一个不会发生的信号」：D9 倒下会打断长流程，
`disarm_enemies()` 只解决了「敌人打死玩家」这一路，不解决「等结算面板/等翻页」这一路。

### 3.1 小（每条半天内）

| 项 | 位置 | 现状 | 验收 |
|---|---|---|---|
| **D16** `psd-tools` 未进 CI | `requirements-tools.txt`、`pipeline.json` | 只在 requirements 里声明，CI 不装 | pipeline 加一步安装 + 导出 PSD 成功 |
| **D17** 存档无版本迁移 | `game/runtime/run_state.gd` | 只有 `schema: "run-state.v1"` 字符串 | 老档（v0/缺字段）读入后字段补齐且不丢数据 |
| **D18** 截图无基线 | `design/previews`、门禁 | 门禁顺手生成，没有 diff | 预览图存 hash，变了必须显式更新 |

### 3.2 中（一轮）

- **D7 收尾**：`HANDOFF-STAGE2.md` 末尾「已知后续（D7 未完成部分）」列了剩余项（各楼专属 props/容器差异未全覆盖）
- **D22 TapDB 文档对齐**：提交里有 TapDB 客户端直连，但欠账表仍标 TODO —— 先核对再决定是否打勾
- **D23 发布管线**：CLI 已装并**已登录**（`developerId 489018`）；`export_presets.cfg` 有 Windows + Android 两条，
  两类包体都已产出（PC exe 132MB / APK 49.6MB，release 已签名）；图标已做（`tools/icon_build.py`）。
  **还没做的只有**：给「残余信号」建 app draft（要账号持有人点头）、上传包体、补资料、提审。
  命令名已按真实 `--help` 校正（`app create` / `app save-changes` / `upload-apk`），见 `design/TAPTAP.md`

### 3.3 大（多轮）

- **D13 `bond` / 同伴**：`RunState` 有 `companions_alive/lost/bond` 字段但没人写；
  **「军队」结局因此不可达**（要 `companions_alive ≥ 2`）。这是唯一还缺的主线系统。
- **D19–D21 观感线**：Stage 3 地面接缝/磨损、Stage 4 前景遮挡、Stage 5 HUD 重构（原五阶段里未动的三项）

---

## 4. 七个坑与规矩（都真踩过）

| 坑 | 规矩 |
|---|---|
| `git fetch` 失败后 `git reset --hard origin/main` 删本地提交（2 次） | 只跑 `.tools/sync_local.ps1`：fetch 不成功就什么都不动 |
| PowerShell 整文件重写把中文读成乱码（3 次，最近是 `.ps1` 脚本本身） | 改 UTF-8 只用 `edit`/`write`；**`.ps1` 保持纯 ASCII**；`Get-Content` 查看看必须 `-Encoding utf8` |
| git 传输被 reset（频繁） | 远端已前进时先 `fetch` 再 `rebase`；推不上去用 `.tools/push_files.py --parent <远端sha> --files ...` |
| 判断「远端有没有我的提交」 | 比**树哈希**（`git rev-parse HEAD^{tree}` vs API `commit.tree.sha`），不信 `origin/main` |
| 未类型化数组传给 `Array[String]` 参数 | 运行时抛错会中断协程 → 进程挂着像卡死；门禁里显式声明类型 |
| 门禁写了没登记 | `run_gates.ps1` 只跑登记过的；新增门禁必须登记并确认条数 |
| `font_build.py` 重建图集后没重新导入 | 表现**不是缺字而是整屏乱码**（区域坐标与旧 PNG 对不上）；重建后必须再跑一次 `--import` |

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

**推送状态（2026-11-26）**：本机到 `github.com:443` 间歇性 reset，`git push` 连试多次都失败，
最后走的是 `.tools/push_files.py`（GitHub API）。所以**本地 HEAD 的 sha 与远端 `main` 不一样，但树哈希一致**
（核对方式见 §4 的「比树哈希」）。下次开工先 `git fetch`；确认树一致后再决定要不要对齐引用，
**不要**直接 `reset --hard`。
