# 发行可行性 · TapTap（2026-11-26 实测）

> 本文只回答一个问题：**这款游戏现在能不能发，卡在哪。**
> 所有数字与结论都来自本机 CLI 的真实返回，命令附在后面可以复跑。
> 细节流程见 [`TAPTAP.md`](TAPTAP.md)，手机包见 [`MOBILE.md`](MOBILE.md)。

---

## 1. 结论（先看这段）

1. **能发。** 账号通了、包体有了、CLI 能建 draft、资质接口能算账。真正的门槛不是技术，是**资质 + 内容量**。
2. 在「**离线单机 + 免费 + 无内购**」这组事实下，服务端把 **版号（game-license）判为 `optional`**，不是必须。
   这是把游戏做成「近期可发」的**关键设计约束**——不是运气。
3. 必交的四项是：**隐私合规、防沉迷、AI 生成内容声明、适龄分级**。
   其中隐私/防沉迷的具体办理域服务端仍标 `unknown`（`read_state=partial`），要到正式草稿里逐个核对。
4. 一旦加**内购**或改成**必须联网**，版号与 ICP 备案大概率从 `optional` 变硬门槛。
   这是产品决策，不是工程问题——写在这里是为了以后别为了一笔小额付费把发行窗口关掉。

## 2. 事实（本作按什么申报）

| 事实字段 | 取值 | 依据 |
|---|---|---|
| `package_types` | `["windows", "apk"]` | 两条导出预设都已产出包体（PC exe + arm64 APK） |
| `is_internet_required` | `false` | 核心循环不联网；TapDB 埋点是**可选、同意后才发**（见 `ANALYTICS.md`），关掉不影响游玩 |
| `has_in_app_purchase` | `false` | 目前没有任何付费 |
| `has_text_story_simulation` | `false` | 按「生存 + 事件卡」申报，不是文字剧情模拟；若平台改判，需要重算 |
| `has_ai_content` | **`true`** | 背景图/地图走生图模型 + 量化（`design/prompts/*`、`tools/quantize_map.py`），必须如实申报 |
| `has_ip_authorization` | `false` | 无外部 IP |

## 3. 服务端算出来的资质清单

`qualification preview-assessment`（只读试算，不写任何资料）在 `testing` 与 `launch` 两种发布意图下返回**同一份结果**：

| 资质 | 要求 | 当前状态 |
|---|---|---|
| `game-license` 版号 | **optional** | 待上传（可选，不阻断） |
| `icp-filing` 备案 | optional | 无法确认（`unknown`） |
| `privacy-compliance` 隐私 | **required** | 无法确认 → 需补隐私政策 |
| `anti-addiction` 防沉迷 | **required** | 无法确认 → 需配置 |
| `ai-declaration` AI 声明 | **required** | 待上传 |
| `software-copyright` 软著 | optional | 待上传 |
| `authorization-letters` 授权书 | optional | 待上传 |
| `security-assessment` 安全评估 | optional | 待上传 |
| `age_grade` 适龄分级 | **required** | 待上传（8 / 12 / 16 三档，本作填 16） |

> `read_state = partial`：因为隐私/备案/防沉迷的办理域依赖包体事实，服务端这一次没给全。
> **不能**据此说「资质已齐全」；也不能说「一定过不了」。准确说法是：四项必交已明确，两项办理域待核对。

## 4. 现在能做什么，逐关解锁

| 关卡 | 需要什么 | 现在状态 |
|---|---|---|
| 建 app draft | `title` + `category` + `package_type` + `age_rating`（另加 `developer_role`） | **已 dry-run 通过**，真建只差你点头 |
| 上传包体 | `upload-apk`（手机）/ `upload-pc-package`（PC）+ 版本号 | 包体已就绪，尚未上传 |
| 补资料 | 8 个必填项（图标、cover、banner、≥3 张截图、`pc_game_anti_addiction_status`、`promotion_material_type`…） | **一项都没有**（图标还是 Godot 默认图） |
| 资质 | 隐私政策、防沉迷配置、AI 声明、适龄 16 | 全部未办 |
| 开测试 | `test-plan`（CBT）+ `test-qr-code` 自测二维码 | 可用，但要先有 app |
| 提审 | `prepare-review-snapshot` → `precheck-review` → `submit-review`（`release_schedule` 三次必须一致） | 未到 |

## 5. 风险（按可能拖时间的顺序）

1. **AI 声明**：`has_ai_content=true` 是必答项，申报后可能触发额外材料/人工审。**别瞒**——审核会看素材风格一致性。
2. **防沉迷**：服务端判「必交」，而本项目是纯离线单机，通常要配实名/未成年人模式说明。它的办理域这次返回 `unknown`，**最可能拖时间的一环**。
3. **版号 optional 的前提是无内购**。加内购 = 版号硬门槛 + 数月起。
4. **`感染之夜` 那个 draft 还在**（`appId 991852`）。CLI **没有删除命令**（`app --help` 只有 `reset-draft` / `clear-package` / `withdraw-review`），删除只能去开发者中心网页操作。留着不影响，但别把两个 `appId` 搞混。
5. **`is_level` 字段**：建 draft 时 CLI 自动带 `is_level: false`。如果将来走「关卡/试玩」通道，这个字段会变，资质算法也随之变。

## 6. 三条发行路径（按成本排）

| 路径 | 需要 | 周期 | 建议 |
|---|---|---|---|
| **A. TapTap 免费试玩 → 正式上线** | 隐私政策 + AI 声明 + 适龄 + 防沉迷配置；不内购、离线可玩 | 数周 | **推荐**，唯一能在近期走完的路 |
| B. Steam 抢先体验（PC） | 无版号要求，但要商店页、英文、愿望单运营 | 1–2 月 | 作为副线，等 TapTap 数据出来再定 |
| C. 付费买断（手机/PC） | **版号** + 更长审核 | 数月 | 现阶段不建议；1.0 先把用户拿到手 |

## 7. 复跑命令（全部只读或 dry-run）

```powershell
$env:Path = "D:\Downloads\残余信号\.tools\npm-global;$env:Path"

taptap-cli overview                                     # 厂商 489018 / 游戏列表
taptap-cli qualification get-assessment --dev-id 489018 --app-id 991852
taptap-cli qualification preview-assessment --dev-id 489018 --app-id 991852 \
  --data '{"app_id":991852,"developer_id":489018,"app_features":{"package_types":["windows","apk"],"is_internet_required":false,"has_in_app_purchase":false,"has_text_story_simulation":false,"has_ai_content":true,"has_ip_authorization":false,"release_intent":"launch"}}'
taptap-cli app create --dev-id 489018 --data '@.tools/create-dryrun.json' \
  --idempotency-key rs-create-dryrun-001 --dry-run      # 建 draft 的请求体预览
```

> `preview-assessment` 是 `effect: read`，不要给它加 `--dry-run`；`app create` 是写操作，真建时同参数 + `--yes`。
