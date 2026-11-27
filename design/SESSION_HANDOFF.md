# SESSION HANDOFF · 换会话从这里开始

> 交班时间：2026-11-27 23:40（Asia/Shanghai）。本轮 HEAD 见 `git log -1`。
> 进度真源：`../progress.json`；欠账：`TECH_DEBT.md`；方向：`NEXT.md`；手机契约：`MOBILE.md`。
> **本文只讲「接手怎么开工 + 上一轮改了什么 + 下一步做什么」。**

---

## 1. 一句话现状

Godot 4.7 像素横版生存（384×216 设计空间 / 手机画布 555×256），Android 横屏优先、离线。
主线闭环、41 条 Godot 门禁全绿、47 条数据规则 `ERROR 0`、TapTap CLI 已登录（developerId 489018）。
**真机（2602BRT18C / 1272×2772@520dpi）可装可玩**，本轮把手机 UI 从「能点」调到「够得着」。

## 2. 上一轮（2026-11-27）实际改了什么

| 提交 | 内容 | 真机状态 |
|---|---|---|
| `21c8ced` | **黑框根因**：手电暗罩只盖 `384×216`，改按画布 `555×256` | ✅ 用户确认消失 |
| `dfcb205` | 攻击：0.75s 可重入锁 + 命中帧白光只亮 2 帧 | 待手感确认 |
| `596fe0f` | 触摸**按下即响应**（矩形直接派发，不再依赖 TouchScreenButton 拾取）；奔跑/蹲下改**长按** | ✅ 连点有反应、奔跑变快 |
| `ac4ae89` | 门交互加**纵深判定**（原来只比 x，远处也能开门） | 待复验 |
| `8571dc0` | HUD 单行 `DAY·地点·体力·手持`；主界面不再挂游戏触控层 | ✅ 截图确认 |
| `043eafe` | 手持状态并进单行，HUD 只剩一行 | ✅ |

关键常量（现行）：

```gdscript
const ATTACK_FRAMES := 45        # 0.75s @60
const ATTACK_HIT_FRAMES := 2
const DOOR_REACH_X := 44.0       # 门交互横向范围
const WALK_TOP := 128.0 / WALK_BOTTOM := 216.0 / WALK_LEFT := 14.0 / WALK_RIGHT := 602.0
```

## 3. 已知未决（下一个会话先处理）

1. **开门后过不去**（用户报告，未复现定位）。
   已排除：隔断墙没有碰撞体（`_build_room_partitions()` 纯 Polygon2D）；门在 `_apply_door_state()` 里确实 `shape.disabled = is_open`。
   **待确认**：卡住时**门板还在不在**。门板消失仍过不去 → 补一次 `set_deferred("disabled", true)`；门板还在 → 开门状态没走到 `_apply_door_state`。
2. **天空（空）**：无。
3. 触控键 `hold` 分支留着调试打印 `[TOUCH] hold <id>`，确认完毕可删。

## 4. 下一步：补丁 v1.0 的 ② 与 ④（①③ 已基本完成）

### ②-1 搜索条（最小，先做）
- `_refresh_search_progress()` 现有条在屏幕左下 (8,146)，要改成**贴在被搜物件上方**；
- 时长从 `data/loot/containers.json` 新字段 `search_seconds` 读（柜子 1.6 / 尸体 1.0），不硬编码；
- 移动或受击立刻中断且**进度归零、零产出**；
- 验收：0.1s 内出条；打断 10 次零产出。

### ②-2 容器面板
- 新建 `game/ui/container_panel.gd`：左容器 / 右背包、≤40% 屏宽、居中偏右、暗底 + 1px 描边、**不暂停世界**；
- 空容器给「咔哒 + 一格空槽」，不许静默；
- 验收：截图量占屏 ≤40%；打开时敌人仍在靠近。

### ②-3 搜索的代价
- 搜索全程 `_emit_noise(1)`；被贴近打断并吃一抓（`_update_search` 已有分支，确认走同一出口）。

### ④ 死亡三态 + 尸体掉落
- 倒地（独立 death_pose）→ 可搜索（30–45s）→ 消失；
- 掉落走同一张全局 loot 表，空手率 ≥70%，高价值权重 ×0.5；
- 每笔产出追一条 `transfer_log`（丧尸 → 玩家 / node / Day / cause）；
- 验收：100 具统计 ≤30 件、高价值 ≤15%、零凭空生成。

## 5. 坑（都真踩过，别再踩）

| 坑 | 规矩 |
|---|---|
| PowerShell 拼 GDScript 字符串把 `""` 写成反引号 → 连续三次改坏 | **只用 `edit`/`write` 工具改 `.gd`**；PowerShell 只用来跑命令 |
| 字库缺字静默跳过（「攻」变成只剩「击」） | 新文案先 `python tools/font_build.py --check`，缺字就 `font_build.py` 重建 + **再 `--import`**（否则整屏乱码） |
| UI 按 `VIEW_SIZE(384×216)` 画 | 手机画布是 `555×256`：一律用 `ScreenLayout.canvas_of(self)`，否则出现「不压暗的一圈」「围成方框」 |
| adb 通过 PowerShell 管道会挂着 | 一律 `cmd /c "adb … > file 2>&1"` 再读文件 |
| 换签名装机报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 先 `adb uninstall com.starxin.residualsignal`（会丢设备存档） |
| `git push` 到 github.com 直连会 reset | 加 `-c http.proxy=http://127.0.0.1:65532` |

## 6. 命令速查

```powershell
$env:JAVA_HOME='D:\Downloads\残余信号\.tools\jdk17\jdk-17.0.21.1+2'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH='D:\Downloads\残余信号\.tools\keystore\residual-release.keystore'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER='residualsignal'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='RS-mobile-2026-7f3c'

# 导出 + 装机 + 启动 + 截图
& '.tools\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --export-release "Android" 'build/android/ResidualSignal-release.apk'
cmd /c "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe install -r build\android\ResidualSignal-release.apk"
cmd /c "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe shell monkey -p com.starxin.residualsignal -c android.intent.category.LAUNCHER 1"
cmd /c "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe exec-out screencap -p > build\android\shot.png"

# 门禁
& '.tools\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://game/tests/touch_controls.gd
python tools/validate.py ; python tools/font_build.py --check
powershell -NoProfile -File tools\run_gates.ps1
```

## 7. 触控键 → 作用（当前）

| 键 | 行为 |
|---|---|
| 摇杆（左半屏按下浮现） | 走 / 纵深 |
| 手电筒 | 开关手电 |
| 奔跑（长按） | 疾跑，松手回走 |
| 蹲下（长按） | 潜行，松手起身 |
| 攻击（≥11mm） | 挥击，0.75s 内不可打断 |
| 搜（上下文） | 贴近可交互物/门/出口才出现 |
| 背包 / ≡ | 背包 / 菜单（继续·暂停·装填·查看·蹲下·退出） |
