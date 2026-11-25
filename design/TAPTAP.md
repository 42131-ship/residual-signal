# TapTap 平台入口 / CLI / Skills（发布路线）

> 本文件是「发布与平台操作」的唯一细节来源；README 只放入口与命令，HANDOFF 只记决策与状态。
> 基线：2026-11-25 晚，D7 五楼主题 + TapDB 客户端直连之后。

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

## 2. 本机现状（先看清再动手）

| 项 | 状态 |
|---|---|
| 游戏形态 | Godot 4.7 · PC Windows 包（Godot 导出的 exe/zip） |
| `export_presets.cfg` | **不存在**（还没配置 Windows 导出） |
| Node / npm / npx | **未安装** → `taptap-cli` 无法安装 |
| `taptap-cli` | **未安装**，`skills` 不可用 |
| TapTap 开发者登录 | 未登录（无 developerId / appId 上下文） |
| TapDB | 客户端直连代码已完成；缺 ClientID、后台事件登记、导出包实测（见 `design/ANALYTICS.md`） |
| 版号/资质 | 未核查；按发行地区与包体形态走 `taptap-cli skills read taptap-qualification` 或控制台资质页 |

**结论**：今晚已经把「代码 + 埋点 + 发布入口/CLI/skills 文档」收束到仓库；真正上传/提审还差
Node → CLI → 登录 → Windows 导出预设 → 包体自测五步，其中登录与资质必须由账号持有人完成。

## 3. 安装 CLI 与 Skills

环境要求：Node.js LTS（本机没有，先装 Node 再执行）。

```bash
# 1) 安装 CLI（官方 npm registry；国內网络可换 npmmirror 镜像）
npm i -g @taptap/cli --registry=https://registry.npmjs.org/

# 2) 登录（会打开 TapTap 授权链接；Agent 可用 --no-wait --json 取续跑参数）
taptap-cli auth login
taptap-cli auth status
taptap-cli doctor

# 3) 安装/同步 AI 能力说明（随 CLI 版本绑定）
npx skills add taptap/cli
taptap-cli skills list
taptap-cli skills read taptap-cli
taptap-cli skills status
```

Skills 随 CLI 版本同步；`skills list` 的实际输出优先于任何文档。
Agent 用 CLI 时先 `taptap-cli overview --json` 定位身份与上下文，不要猜 developerId / appId。

## 4. 发布流程（PC 包）

### 4.1 定位身份与游戏

```bash
taptap-cli overview
taptap-cli developer +list
taptap-cli app +list --dev-id <developerId> --kw 残余信号
taptap-cli app +select --dev-id <developerId> --app-id <appId>
```

### 4.2 创建游戏草稿（若尚未创建）

```bash
# 先查 schema，package_type 不要猜
taptap-cli schema app create-app
taptap-cli app create-app --dev-id <developerId> \
  --data '{"title":"残余信号 Residual Signal","category":"<类型>","package_type":"<pc 取值>"}' \
  --idempotency-key <唯一键> --dry-run
# 确认后同参数 + --yes
```

### 4.3 配置 Windows 导出并产包

1. 在 Godot 编辑器安装 4.7 导出模板；
2. 新建 Windows Desktop 预设，导出到 `build/`；
3. 配置版本：`project.godot` 的 `application/config/version`（当前 `0.1.0`）要与 `--version` 一致；
4. 运行自测：主菜单→新游戏→出行→结算→结局栏，确认无白屏/卡死（发布前至少连玩三局）。

### 4.4 上传包体

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

上传成功 ≠ 资料写入 ≠ 包体绑定；用 `app analyze-status` / 包体列表核对。

### 4.5 资料、测试与提审

```bash
taptap-cli materials +inspect ./materials
taptap-cli upload ./materials/icon.png --dev-id <developerId> --app-id <appId> --idempotency-key <key> --yes
taptap-cli app prepareChanges --dev-id <developerId> --app-id <appId> --dry-run
# 提审三步（不要跳）：
taptap-cli app prepare-review-snapshot --dev-id <developerId> --app-id <appId>
taptap-cli app precheck-review --dev-id <developerId> --app-id <appId> --data @review-precheck.json
taptap-cli app submit-review --dev-id <developerId> --app-id <appId> --data @review-submit.json --idempotency-key <key> --yes
```

测试计划、预约、公告、评价回复等能力见第 5 节 Skills；自测在补资料之前、测试在提审之前（顺序见 agents.md）。

## 5. Skills 清单（核心业务）

以 `taptap-cli skills list` 为准；官方能力参考列出：

| Skill | 用途 |
|---|---|
| `taptap-cli` | 入口与路由、命令发现 |
| `taptap-identity` | 登录与开发者/游戏定位 |
| `taptap-publish-game` | 创建游戏草稿 |
| `taptap-app-edit` | 资料编辑与版本发布 |
| `taptap-qualification` | 上架资质核查 |
| `taptap-package-management` | 包体管理与自测 |
| `taptap-test-plan` | 测试计划、招募、激活码 |
| `taptap-dashboard-stats` | 数据表现（下载/转化/评价/销售） |
| `taptap-asset-library` | 图片/视频素材库 |
| 其他（预约里程碑/签到活动/公告/推送/论坛/评价回复） | 见 `skill-reference.md` |

## 6. 常用参数与纪律

- 写操作先 `--dry-run`，确认后追加 `--yes`；不要在未确认前批量写。
- `--data` 支持内联 JSON、`-`（stdin）、`@file`；`@file` 必须在当前工作目录内。
- 脚本判断用 JSON 的 `ok` + 退出码（0 成功；2 参数；3 认证/配置；4 网络；6 内容安全；10 缺 `--yes`）。
- 上下文缺省会报 `context_missing`：先 `developer +enter` / `app +select`。
- 高风险动作（上传、提审、发布）必须由用户明确确认后再执行。
- 客户端只放公开标识（TapDB ClientID 可公开），密钥不入库、不进前端。

## 7. 当前项目待办（按顺序）

1. 安装 Node.js LTS，再装 `@taptap/cli` 并 `auth login`、`skills list`。
2. 在 TapTap 控制台创建/确认游戏与包体形态，拿到 `developerId` / `appId`。
3. 给 Godot 配 Windows 导出预设，产出包体并自测三局。
4. 填 `config/analytics.json` 的 TapDB ClientID，在 TapDB 后台登记 `data/analytics/events.json` 的事件与属性。
5. 导出包实机验证埋点（同意/拒绝/离线补发），再看 TapDB「上报明细」。
6. 按第 4 节上传包体、补资料、开测试计划，最后走提审三步。
7. 正式上线前替换 `data/analytics/events.json` 里的隐私文案为法务确认版本，并核对资质。
