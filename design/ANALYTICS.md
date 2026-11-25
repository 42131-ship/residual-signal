# TapDB 接入（客户端直连 HTTP）

> 状态：**代码已接入，待 ClientID + TapDB 后台事件登记 + 导出构建实机验证**（2026-11-25）。
> 依据：TapDB 无 Godot 客户端 SDK（官方只有 Android / iOS / Unity / UE5），
> 本项目按[服务端接入的 HTTP 事件接口](https://developer.taptap.cn/docs/sdk/tapdb/sdk/server-side-integration/)
> 从游戏客户端直接 `POST https://e.tapdb.net/v2/event`。

> 发布/CLI 流程见 `design/TAPTAP.md`。

## 1. 一次性配置（不入库）

1. TapTap 开发者中心开通 TapDB，拿到 **ClientID**（公开标识，无密钥）。
2. 复制 `config/analytics.example.json` 为 `config/analytics.json`，填入 `client_id`。
   `config/analytics.json` 已加入 `.gitignore`，不会提交。
3. TapDB 后台按要求登记（**必须做，否则自定义事件可能被丢弃**）：
   - `配置 → 事件管理`：按 `data/analytics/events.json` 的 `events` 建自定义事件；
   - `配置 → 事件属性管理`：建属性并选对类型（本项目只用 `string` / `number`，布尔值传 0/1）；
   - `配置 → 上报明细`：联调时看实时上报。
4. 隐私政策：`data/analytics/events.json` 的 `privacy.lines` 是游戏内同意文案的占位，
   上线前替换为正式版本；同意前不会初始化、不会发任何请求。

## 2. 运行时行为

| 场景 | 行为 |
|---|---|
| 编辑器 / `--script` 门禁 / `headless` | 默认完全静默（不初始化、不联网）；可用 `RS_ANALYTICS=1` 在编辑器里调试 |
| 导出构建 + 未同意 | 主菜单首次进入显示隐私同意页；拒绝/关闭后不收集 |
| 导出构建 + 已同意 | 启动时先发 `device_login`、`user_login`，再发 `session_start`；之后按事件表上报 |
| 发送失败 | 事件留在 `user://analytics_queue.json`，按 5/15/60/180/300 秒退避重试，最多 5 次；成功才出队 |
| 撤销同意 | 立即停产并清空本地队列；匿名 ID 保留在 `user://analytics_profile.json`（不再使用） |
| 关闭游戏 | `_notification` 里尝试补一条 `session_end` 并入队，下次启动继续尝试 |

匿名 ID：首次激活时生成 `device_id` / `user_id`（UUID v4），分别持久化；不上报系统用户名、文件路径、存档内容、坐标、背包内容。
`event_uuid` + `timestamp` 用于 TapDB 去重；重试不改变 `event_uuid`。

## 3. 事件表（v1）

| 事件 | 触发点 | 属性 |
|---|---|---|
| `device_login` / `user_login` | 同意后启动激活 | TapDB 预置事件（os/设备/版本） |
| `session_start` | 激活时 | mode、day、building |
| `session_end` | 关闭游戏 | mode、day、building、duration_sec |
| `run_start` | 主菜单新游戏/继续 | mode、from_save、day |
| `run_enter` | 走廊加载完成 | mode、day、building |
| `travel_depart` | 出行判定（成功/拒绝都记） | from、to、day、fuel、actions_left、ok、reason |
| `day_end` | 跨天结算 | day、building、sediment、supplies、health、kills、fuel、finished、mode |
| `travel_arrive` | 切楼后 | to、day |
| `card_fire` | 每日事件卡 | card_id、day |
| `loot_search` | 搜容器 | container、day、status、items、rejected |
| `enemy_kill` | 感染体死亡 | enemy、day、kills |
| `player_down` | D9 倒下 | day、building、down_count、mode |
| `ending_unlock` | 首次解锁结局 | ending_id、day、template、mode |
| `endings_view` | 打开结局栏 | unlocked |

自定义属性在 HTTP 报文里带 `#` 前缀（`custom_property_prefix`，见注册表）；事件名默认不带前缀，二者都可在注册表里调整。

## 4. 验证

离线门禁（不联网）：

```powershell
& $G --headless --path . --fixed-fps 60 --script res://game/tests/analytics.gd -- ANALYTICS
# ANALYTICS_OK registry=15 consent=gated retry=stable uuid=yes privacy=ok
```

真实上报（需 ClientID）：

1. 填好 `config/analytics.json`；
2. 导出 Windows 包运行（编辑器默认不启用）；
3. 在 TapDB `配置 → 上报明细` 看是否出现 `device_login` / `user_login` / `run_start`；
4. 断网运行一局，再联网启动，确认队列补发；拒绝同意时确认零上报。

## 5. 已知风险 / 待实测

- **非官方 Godot 路径**：文档只承诺客户端 SDK 支持 Android/iOS/Unity/UE5；HTTP 直连需以「上报明细」实测为准。
- 文档两处不一致：服务端接入示例是 JSON body；数据规范提到“REST API 支持 URLEncode 后的 JSON”。首次实测需确认 body 格式。
- 自定义事件名/属性前缀（`#`）需与后台登记名对齐；`data/analytics/events.json` 可调。
- 暂未做批量接口 `/v2/batch`、广告归因、`play_game` 预置时长事件（用 `session_end` 代替）。
- `app_version` 读 `application/config/version`（当前 `0.1.0`）；发版时修改。
