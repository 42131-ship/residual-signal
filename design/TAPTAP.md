# TapTap 平台入口 / CLI / Skills（发布路线）

> 本文件是「发布与平台操作」的唯一细节来源；README 只放入口与命令，HANDOFF 只记决策与状态。
> 基线：2026-11-25 晚（D7 五楼主题 + TapDB 客户端直连）；2026-11-26 本机实测补上「CLI 已装 / 命令名校正」。

## 1. 入口

| 入口 | 地址 |
|---|---|
| AI 助手入口（纯文本，本文件主要依据） | https://developer.taptap.cn/agents.md |
| 开发者文档索引 | https://developer.taptap.cn/docs/llms.txt |
| CLI 使用文档 | https://developer.taptap.cn/v3/cli/ |
| CLI 命令参考 | https://developer.taptap.cn/v3/cli/command-reference.md |
| CLI AI 能力参考（Skills） | https://developer.taptap.cn/v3/cli/skill-reference.md |
| TapDB 功能/接入 | https://developer.taptap.cn/docs/sdk/tapdb/features/ |
| PC 端接入指南 | https://developer.taptap.cn/docs/sdk/integration-guides/pc-engine-features/ |

> `agents.md` 服务器返回 `Content-Type: application/octet-stream`，浏览器直接打开可能变成下载；
> 用 `curl -sL https://developer.taptap.cn/agents.md` 读取即可。

## 2. 本机现状（2026-11-26 实测，别照抄旧表）

| 项 | 状态 |
|---|---|
| 游戏形态 | Godot 4.7 · PC Windows 包（Godot 导出的 exe/zip） |
| `export_presets.cfg` | **不存在**（还没配置 Windows 导出） |
| Node | **有**：`C:\Program Files\nodejs\node.exe`，v24.19.0 |
| npm / npx / corepack | **没有**：该安装里只有 `node.exe`（`node_modules\` 只有 tripo-cli），无 shim → 不能直接 `npm i -g` |
| 便携 npm | **已装**：`.tools\npm\package`（npm 12.2.3），`.tools/` 不入库 |
| `taptap-cli` | **已装（便携）**：`2026.11.24` / `contract 3`，在 `.tools\npm-global`（含 `taptap-cli.cmd`） |
| `doctor` | `cli_version` / `installation` / `server_health` / `metadata`（150 条命令，set 1.0.82）**pass**；`config` / `credentials` **fail** |
| Skills | **16 个内置**（`skills list`），随 CLI 版本绑定，不需要另装 |
| TapTap 开发者登录 | **未登录**（无 developerId / appId 上下文） |
| TapDB | 客户端直连代码已完成；缺 ClientID、后台事件登记、导出包实测（见 `design/ANALYTICS.md`） |
| 版号/资质 | 未核查；走 `taptap-cli skills read taptap-qualification` 或控制台资质页 |

**怎么跑起来（每个新 shell 先加 PATH，本机没有全局 npm 前缀）**：

```powershell
$env:Path = "D:\Downloads\残余信号\.tools\npm-global;$env:Path"
taptap-cli version     # {"name":"@taptap/cli","version":"2026.11.24","contract":"3"}
taptap-cli doctor
```

升级/重装 CLI 用便携 npm，不要找全局 `npm`：

```powershell
node D:\Downloads\残余信号\.tools\npm\package\bin\npm-cli.js install -g '@taptap/cli' `
  --prefix D:\Downloads\残余信号\.tools\npm-global --registry=https://registry.npmjs.org/
```

**结论**：工具链这段已经通了（Node → 便携 npm → `taptap-cli` → 16 skills → 服务端在线）。
剩下的是**账号与包体**：登录（只有账号持有人能做）→ Windows 导出预设 → 包体自测 →
`upload-pc-package` → 资料 → 测试计划 → 提审三步。

### 2.1 账号与 scope（2026-11-26 登录后实测）

| 项 | 值 |
|---|---|
| 登录 | 已登录（`auth status` 认证：已配置） |
| 厂商 | **`starxin的工作室`**，`developerId = 489018`（只有 1 个） |
| 名下游戏 | **只有 1 个**：`感染之夜`，`appId = 991852`，①未发布（`review_status = 0`） |
| 那是不是本项目 | **不是**。`basic-info` 读出来是「1930 年代邮轮上的 5 分钟社交推理小品、Windows 64 位 demo」——和残余信号（像素生存恐怖）无关 |
| 版本 | `感染之夜` 只有 `V-20261021`（draft，2026-10-21 创建） |
| 残余信号 | **还没有 app**：要发就得先 `app create`（写操作，先 `--dry-run`） |

`感染之夜` 提审前的缺口（`app analyze-status` 实测，可当「一个空壳 draft 长什么样」的参照）：

- blockers：`MISSING_REQUIRED` × 8 —— `pc_game_anti_addiction_status`、`promotion_material_type`、
  `banner_4`、`screenshots`、`logo`、`cover`、`cover_vertical`、`library_hero`
- warnings：资质事实未确认（`package_types` / `is_internet_required` / `has_in_app_purchase` /
  `has_text_story_simulation` / `has_ai_content` / `has_ip_authorization`）、`age_grade` 待补、
  图标仍是默认图
- suggestions：`developer_message`、`promotion_text`

> 也就是说：一个刚建好的 PC 游戏 draft，离提审差 **8 个必填素材/字段 + 资质六问 + 适龄分级**。
> 残余信号建完后大概率是同一份清单，可以直接按它准备素材（图标 512×512 方图、cover/banner、
> 至少 3 张截图、Windows 防沉迷状态、推广素材类型）。

## 3. 安装 CLI 与 Skills

环境要求：Node.js。本机 Node 在、npm 缺 → 用第 2 节的便携 npm；换到装好完整 Node 的机器时
官方写法等价（`npm i -g @taptap/cli --registry=https://registry.npmjs.org/`）。

登录是**设备码**流程，链接 5 分钟有效，Agent 可用裸 JSON 契约续跑：

```powershell
taptap-cli auth login --no-wait --json          # 拿 verification_url / device_code / expires_at / interval
taptap-cli auth login --device-code <device_code> --expires-at-unix <expires_at> --interval-seconds <interval>
taptap-cli auth status
taptap-cli doctor                               # 期望 config / credentials 转 pass
```

Skills 是**内置**的（16 个，随 CLI 版本绑定），`npx skills add` 这一步不需要：

```powershell
taptap-cli skills list
taptap-cli skills read taptap-cli                # 共享执行规范：路由 / dry-run / 退出码 / 输出外壳
taptap-cli skills read taptap-app-edit           # 资料与提审 runbook
taptap-cli skills read taptap-app-edit/references/shared-execution.md   # 可读 skill 自带 references
```

`skills list` 的实际输出优先于任何文档；需要强制重新同步用 `taptap-cli update --force`。
Agent 用 CLI 时先 `taptap-cli overview` 定位身份与上下文，不要猜 developerId / appId。

## 3.1 输出与门禁（实测）

- 默认输出就是 JSON 信封：成功看退出码或 `ok === true`，失败看 `error.type` / `subtype` / `message` / `hint`。
- 退出码：0 成功；2 参数；3 认证/配置；4 网络；6 内容安全；10 缺 `--yes`（确认门禁，不是普通失败）。
- 写操作先 `--dry-run`；`prepare-*` 若 schema 标 `effect: read` 本身就是只读预览，**不要**再挂 `--dry-run`。
- `--data` 支持内联 JSON / `-`（stdin）/ `@file`（必须在当前工作目录内）；typed flag 与 `--data` 同名字段必须一致。
- 上传类命令的文件路径也必须在当前工作目录内：绝对路径、`..`、越界符号链接会被拒。
- Agent 的本机 CLI 路径：`D:\Downloads\残余信号\.tools\npm-global\taptap-cli.cmd`（PATH 见 §2）。

## 4. 发布流程（PC 包）

### 4.1 定位身份与游戏

```bash
taptap-cli overview
taptap-cli developer +list
taptap-cli app +list --dev-id <developerId> --kw 残余信号
taptap-cli app +select --dev-id <developerId> --app-id <appId>
```

### 4.2 创建游戏草稿（若尚未创建）

命令名以 `app --help` 为准：`app create`（创建游戏）与 `app create-draft`（草稿版本）是两条；
另有快捷键 `game:create`。`package_type` 不要猜，先 `schema`。

```bash
taptap-cli schema app create
taptap-cli app create --dev-id <developerId> \
  --data '{"title":"残余信号 Residual Signal","category":"<类型>","package_type":"<pc 取值>"}' \
  --idempotency-key <唯一键> --dry-run
# 确认后同参数 + --yes
```

### 4.3 配置 Windows 导出并产包

1. ~~安装导出模板~~ **已装**：本机只有 `4.5.2.stable` / `4.7.2.stable`，所以导出用 `.tools/Godot_v4.7.2-stable_*`
   （跑门禁仍用 4.7，见 `design/MOBILE.md` §1）；
2. `export_presets.cfg` **已入库**（`Windows Desktop` + `Android` 两条预设），导出到 `build/`；
3. 配置版本：`project.godot` 的 `application/config/version`（当前 `0.1.0`）要与预设 `version/name`、
   `upload-*` 的 `--version` 三处一致；
4. 运行自测：主菜单→新游戏→出行→结算→结局栏，确认无白屏/卡死（发布前至少连玩三局）。

### 4.3.1 手机包（Android APK）

手机与 PC 是两条独立通道：**PC 包走 `upload-pc-package`，APK 走 `upload-apk`**。

```bash
# 本机构建（细节与签名说明见 design/MOBILE.md §2）
#   .tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Android" build/android/ResidualSignal-release.apk

taptap-cli upload-apk ./build/android/ResidualSignal-release.apk \
  --dev-id <developerId> --app-id <appId> --dry-run
taptap-cli upload-apk ./build/android/ResidualSignal-release.apk \
  --dev-id <developerId> --app-id <appId> --yes
```

`upload-apk` 报错时用 `taptap-cli upload-apk --help` 核参数，别猜；包体库与自测二维码走
`package-management` / `test-qr-code`。

### 4.4 上传包体

`upload-pc-package` 的必填项（实测 `--help`）：`--launch-exe` + `--version`，另加
`--dev-id` / `--app-id`；可选 `--type`（1 全量 / 2 增量，增量要 `--base-package-id`）、
`--windows-branch`（0 默认 / 1 游戏 / 2 启动器，不传则由 `get-app-module` 决定）、`--launch-arg`。
上传路径（包与 `@file`）必须在当前工作目录内。

```bash
taptap-cli materials +inspect ./build --format pretty
# 写操作：先 --dry-run 预览，确认后再 --yes
taptap-cli upload-pc-package ./build/ResidualSignal.zip \
  --dev-id <developerId> --app-id <appId> \
  --launch-exe <包内 exe 路径> --version 0.1.0 --dry-run
taptap-cli upload-pc-package ./build/ResidualSignal.zip \
  --dev-id <developerId> --app-id <appId> \
  --launch-exe <包内 exe 路径> --version 0.1.0 --yes
```

上传成功 ≠ 资料写入 ≠ 包体绑定；用 `app analyze-status` / `app list-packages` / 自测二维码
（`test-qr-code`）核对。

### 4.5 资料、测试与提审

```bash
taptap-cli materials +inspect ./materials
taptap-cli upload ./materials/icon.png --app-id <appId> --dev-id <developerId> --dry-run   # 先预览
taptap-cli upload ./materials/icon.png --app-id <appId> --dev-id <developerId> --yes
taptap-cli app save-changes --dev-id <developerId> --app-id <appId> --dry-run               # 不是 prepareChanges
# 提审三步（不要跳）：
taptap-cli app prepare-review-snapshot --dev-id <developerId> --app-id <appId>              # 拿 revision + version_id
taptap-cli app precheck-review --dev-id <developerId> --app-id <appId> --data @review-precheck.json
taptap-cli app submit-review --dev-id <developerId> --app-id <appId> \
  --data @review-submit.json --idempotency-key <key> --yes
```

预检与提交必须传**完全相同**的 `release_schedule`，并核对返回的 `version_id` 与快照一致；
上传成功 ≠ 资料写入 ≠ 包体绑定 ≠ 审核通过。

测试计划、预约、公告、评价回复等能力见第 5 节 Skills；自测在补资料之前、测试在提审之前（顺序见 agents.md）。

## 5. Skills 清单（实测 16 个）

以 `taptap-cli skills list` 为准（内置，随 CLI 版本绑定）：

| Skill | 用途 |
|---|---|
| `taptap-cli` | 入口与路由、命令发现、dry-run/退出码/输出外壳纪律 |
| `taptap-identity` | 登录、developerId / appId 候选发现 |
| `taptap-publish-game` | 创建游戏草稿 |
| `taptap-app-edit` | 资料字段、素材规格、包体槽位、提审/撤审/发布 |
| `taptap-qualification` | 上架资质识别与增量提审 |
| `taptap-package-management` | 包体库诊断与自测入口 |
| `taptap-test-plan` | CBT/OBT、招募、资格、激活码 |
| `taptap-dashboard-stats` | 下载/曝光/转化/预约/订单/评分/论坛数据 |
| `taptap-player-feedback` | 玩家评价正文与回复 |
| `taptap-community-management` | 论坛帖子与回复、帖子配图/视频 |
| `taptap-materials` | 本地物料盘点与上传编排（图片/视频/APK/Windows/H5/小游戏） |
| `taptap-asset-library` | 素材库检索、生图、收录 |
| `taptap-reserve-milestone` | 预约里程碑与奖励档位 |
| `taptap-whats-new` | 活动/公告位、排期、置顶 |
| `taptap-official-message-push` | 官方消息推送额度与发送 |
| `taptap-game-sign` | 签到活动、每日奖励、兑换码导入 |

## 6. 常用参数与纪律

- 写操作先 `--dry-run`，确认后追加 `--yes`；不要在未确认前批量写。
- `--data` 支持内联 JSON、`-`（stdin）、`@file`；`@file` 必须在当前工作目录内。
- 脚本判断用 JSON 的 `ok` + 退出码（0 成功；2 参数；3 认证/配置；4 网络；6 内容安全；10 缺 `--yes`）。
- 上下文缺省会报 `context_missing`：先 `developer +enter` / `app +select`。
- 高风险动作（上传、提审、发布）必须由用户明确确认后再执行。
- 客户端只放公开标识（TapDB ClientID 可公开），密钥不入库、不进前端。

## 7. 当前项目待办（按顺序，2026-11-26 现状）

1. ~~安装 CLI~~ **已完成**：便携 npm（`.tools\npm`）+ `@taptap/cli 2026.11.24`（`.tools\npm-global`），
   `doctor` 只剩 `config` / `credentials` 两项红。
2. ~~登录~~ **已完成**（2026-11-26）：厂商 `starxin的工作室` / `developerId 489018`；名下只有
   `感染之夜`（`appId 991852`，未发布，与本项目无关）→ **残余信号还没有 app**。
   要么 `app create` 建新 draft（写操作，先 `--dry-run`，字段见 `schema app create`），
   要么先确认要在哪个厂商/游戏下发。登录态见 §2.1。
3. ~~给 Godot 配 Windows 导出预设~~ **已完成**：`export_presets.cfg` 有 Windows + Android 两条；
   手机包已产出（`build/android/ResidualSignal-release.apk`，见 `design/MOBILE.md`）。
   **剩**：真机自测三局（本机无设备）、应用图标（现在还是 Godot 默认图）。
4. 填 `config/analytics.json` 的 TapDB ClientID，在 TapDB 后台登记 `data/analytics/events.json` 的事件与属性。
5. 导出包实机验证埋点（同意/拒绝/离线补发），再看 TapDB「上报明细」。
6. 按第 4 节上传包体、补资料（`app save-changes`）、开测试计划，最后走提审三步。
7. 正式上线前替换 `data/analytics/events.json` 里的隐私文案为法务确认版本，并核对资质。
