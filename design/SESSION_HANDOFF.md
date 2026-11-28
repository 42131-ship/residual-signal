# SESSION HANDOFF · 换会话从这里开始

> 交班时间：2026-11-28 00:20（Asia/Shanghai）。本轮 HEAD 见 `git log -1`。
> 进度真源：`../progress.json`；欠账：`TECH_DEBT.md`；方向：`NEXT.md`；手机契约：`MOBILE.md`。
> **本文只讲「接手怎么开工 + 上一轮改了什么 + 下一步做什么」。**

---

## 1. 一句话现状

Godot 4.7 像素横版生存（384×216 设计空间 / 手机画布 555×256），Android 横屏优先、离线。
主线闭环、42 条 Godot 门禁全绿、48 条数据规则 `ERROR 0`、TapTap CLI 已登录（developerId 489018）。
**真机可装可玩**；学校模板已从「一间走廊换五套皮」改成**一整张校园图**（[`CAMPUS_SCHOOL.md`](CAMPUS_SCHOOL.md)），
搜索是有进度有代价的按住动作，感染体各守一段走廊（不再 10 秒围死）。

## 2. 上一轮（2026-11-27 夜 → 11-28 凌晨）实际改了什么

| 提交 | 内容 | 状态 |
|---|---|---|
| `21c8ced` | 黑框根因：手电暗罩只盖 `384×216`，改按画布 `555×256` | ✅ 用户确认 |
| `dfcb205` | 攻击：0.75s 可重入锁 + 命中帧白光只亮 2 帧 | ✅ 门禁按新设计更新 |
| `596fe0f` | 触摸**按下即响应**；奔跑/蹲下改**长按** | ✅ |
| `ac4ae89` | 门交互加纵深判定 | ⚠️ 引入了 §3.1 的 bug |
| `8571dc0` / `043eafe` | HUD 压成单行 `DAY·地点·体力·手持·伤口` | ✅ |
| `08503a8` | **修「开门后过不去」**：纵深锚点改走道中线；开合补 `set_deferred` | ✅ 门禁转绿 |
| `1490b2b` | **②-1 搜索条贴物件 + 按住才算数 + 搜索有噪声**；手机「搜」改按住态 | ✅ 门禁转绿 |
| `8e19d5f` | **感染体区块拴绳 + 受击无敌帧**；倒下不再「一天只放行一次」（回巢脱战） | ✅ 真机复验 |
| `campus` | **学校模板 = 一整张校园图**（10 区块 / 4 条路 / 14 个感染体位 / 开场四拍），数据 + 俯视渲染 + 门禁 + `R48` | ✅ 42/42 门禁 |

### 2.1 「开门后过不去」的真根因（别再猜了）

`ac4ae89` 判纵深时拿**门板顶边** `leaf.global_position.y = DOOR_TOP = 80` 当锚点，
而玩家脚底（`Player.global_position` 就是脚底，碰撞体 `position=(0,-20) size=(40)`）永远在 `128..216`：

```text
dy = |player.y - 80| ∈ [48, 136]  >  INTERACT_DEPTH_TOLERANCE(24)   →  门一次都选不中
```

后果链：门**默认常开** → 玩家按下「搜」→ 因为选不中门，实际什么都没发生；
但门在别处被关过一次之后就再也开不了 → 表现为「我开了门但过不去」。

修法（现行常量）：

```gdscript
const DOOR_ANCHOR_Y := (WALK_TOP + WALK_BOTTOM) * 0.5           # 172 = 走道中线
const DOOR_DEPTH_TOLERANCE := (WALK_BOTTOM - WALK_TOP) * 0.5 + 8.0  # 52
```

外加 `_apply_door_state()` 里 `shape.disabled = is_open` 之后再补一次
`shape.set_deferred("disabled", is_open)`：物理查询刷新期间直接赋值可能被静默丢弃，
症状正是「门板没了、人还是过不去」（幂等，代价为零）。

### 2.2 手机「搜」为什么以前永远搜不完

`KEYS["search"]` 原来是 `tap`：`_tap_key()` 在**同一帧**按下又松开 `pickup`，
而 `_update_search()` 要求 `Input.is_action_pressed("pickup")` 才推进 → 下一帧就被判「松手」中断。
现在 `kind: "hold_key"`：按下发一次真按键事件（走廊靠它起手）+ **一直按住** `pickup`（进度靠它推进）。

### 2.3 关键常量（现行）

```gdscript
const ATTACK_FRAMES := 45           # 0.75s @60
const ATTACK_HIT_FRAMES := 2
const DOOR_REACH_X := 44.0
const DOOR_ANCHOR_Y := 172.0        # 走道中线（不是门板顶边！）
const DOOR_DEPTH_TOLERANCE := 52.0
const SEARCH_NOISE_INTERVAL := 0.5  # 搜索每 0.5s 记 1 点噪声
const WALK_TOP := 128.0 / WALK_BOTTOM := 216.0 / WALK_LEFT := 14.0 / WALK_RIGHT := 602.0
```

## 3. 已知未决（下一个会话先处理）

1. **战斗仍缺「威胁线索」**：区块拴绳 + 无敌帧之后不会再被围死，但玩家依旧看不到
   「敌人在哪、朝我来」。MOBILE-REVIEW P0-2 只还了一半（边缘红晕 / 受击方向指示还没做）。
2. **手机检查面板排版**（MOBILE-REVIEW P0-3）：仍是按 384×216 画的大框，555×256 下偏重。
3. 触控键 `hold` 分支的调试打印已删；`_search_noise_acc` 之类新常量记得别在别处再写一份。

## 3.5 本轮（2026-11-28）清掉的两条

- **倒下不再「一天只放行一次」**：判据从「世界日是否已倒过」改成 `_down_lockout`（2s 防同帧重复），
  当天再被打空照样结算（每次抵一天）。倒下时感染体**回巢 + 脱战 4 秒**，
  玩家不会在倒下面板上还没看清就被贴脸再打死。门禁 `down` 断言 `repeat_down=settles` + `enemies=rehomed`。
- **两只感染体不再跨区围杀**：`Enemy.leash` 把每只关在自己那段走廊（A/B/C 按隔断墙切），
  外加 `HURT_IFRAMES = 0.7`（一次抓伤后 0.7s 不吃第二下）。
  门禁 `corridor-combat` ⑤⑥⑦：B 区守卫**证明会追**但进不了 A 区 / 0.7s 内第二下无效 / 倒下后回巢脱战。
  真机复验：在 A 区柜子前站着操作 30 秒以上，体力全程 100。

## 4. 下一步：把校园图接成可玩房间

### 4.1 区块 = 房间（下一步，这是「布置和丧尸不再一样」的真正落点）
- `corridor.gd` 加 `_current_region`：房间的参数（props / 敌人 / 容器 / 灯光档）全从
  `data/campus/school.json` 的区块读，删掉 `ENEMY_SPAWNS`、`ROOM_PARTITION_TILES` 这类硬编码；
- 进出靠区块的 `entrance` 点；`interior.rooms` 决定这间房挂哪些道具；
- 验收：主楼与角楼两张截图的道具/敌人分布**必须不同**（新门禁或扩 `building-theme`）。

### 4.2 开场过场（**已完成** 2026-11-28）
- `game/ui/intro_sequence.gd` 挂在走廊里当覆盖层（不换场景），按 `data/campus/school.json`
  的 `intro.beats` 播六拍：铃 → 鸟瞰（叠路线虚线）→ 厕所小景 → 报警 → 聚焦角色 → **走出厕所**；
- 第六拍：角色被自动向右推 76px 走出厕所，**这一下熄灯**（手电熄掉 + 环境压到 0.34），
  走完交还控制权；灯不会自己回来，玩家的第一件事就是按手电；
- 主菜单「新游戏」领票（`IntroFlag.request()`），走廊 `consume()` 决定播不播；任意键可跳过；
- 门禁 `intro`（pipeline 第 56 步）：六拍顺序、过场锁输入、`zoom` 时灯还亮、`walkout` 灯灭且角色真位移、
  播完解锁、没票不重播；出图 `design/previews/INTRO_{bell,overview,toilet,walkout}.png`。

### 4.3 ②-2 容器面板（原计划，顺延）
- 左容器 / 右背包、≤40% 屏宽、不暂停世界；空容器给「咔哒 + 一格空槽」。

### ②-2 容器面板（下一个做）
- 新建 `game/ui/container_panel.gd`：左容器 / 右背包、≤40% 屏宽、居中偏右、暗底 + 1px 描边、**不暂停世界**；
- 空容器给「咔哒 + 一格空槽」，不许静默；
- 验收：截图量占屏 ≤40%；打开时敌人仍在靠近（`_corridor._enemies[i].global_position` 有位移）。

### ④ 死亡三态 + 尸体掉落
- 倒地（独立 death_pose）→ 可搜索（30–45s）→ 消失；
- 掉落走同一张全局 loot 表，空手率 ≥70%，高价值权重 ×0.5；
- 每笔产出追一条 `transfer_log`（丧尸 → 玩家 / node / Day / cause）；
- 验收：100 具统计 ≤30 件、高价值 ≤15%、零凭空生成。

## 5. 坑（都真踩过，别再踩）

| 坑 | 规矩 |
|---|---|
| PowerShell 拼 GDScript 字符串把 `""` 写成反引号 → 连续三次改坏 | **只用 `edit`/`write` 工具改 `.gd`**；PowerShell 只用来跑命令 |
| `edit` 的 `old_string` 少写/多写一个换行 → 代码粘成一行 `func _place(...):	_actor...`，报 `Unexpected "Indent"` | 改完立刻单跑那条门禁；看到 Parse Error 先搜 `):\t` 这种粘连 |
| 字库缺字静默跳过（「攻」变成只剩「击」） | 新文案先 `python tools/font_build.py --check`，缺字就重建 + **再让 Godot 重新导入** |
| **字库改了但 `.godot` 里还是旧 ctex**（本轮踩到：磁盘 1344 高、导入缓存 1312 高）→ `region` 全指错格子，字会画成**隔壁格子的字**（「宿舍」被画成一个黑框） | 删 `.godot/imported/PF-02_cjk_12*` 再 `Godot --headless --path . --editor --quit` 重新导入；`campus-map` 门禁已加尺寸自检 |
| 新脚本用 `class_name` 后直接跑 `--script` 会报「未声明类型」 | 门禁里 `preload("res://…/x.gd").new()`，别等 `.godot` 缓存 |
| UI 按 `VIEW_SIZE(384×216)` 画 | 手机画布是 `555×256`：一律用 `ScreenLayout.canvas_of(self)`；世界坐标投屏幕用 `get_viewport().get_canvas_transform()` |
| 拿「交互锚点」当「物件位置」画 UI | `_inspection_anchor()` 会把 y 夹进走道（柜子在墙上），贴条要用道具自身位置 ± 贴图高度 |
| adb 通过 PowerShell 管道会挂着 | 一律 `cmd /c "adb … > file 2>&1"` 再读文件 |
| 换签名装机报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 先 `adb uninstall com.starxin.residualsignal`（会丢设备存档） |
| `git push` 到 github.com 直连会 reset | 加 `-c http.proxy=http://127.0.0.1:65532` |
| GitHub REST API 走同一个代理会 403 | 同步状态用 `git fetch` + `git rev-list --left-right --count` 判断，别去求 API |

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
python tools/validate.py ; python tools/selftest.py ; python tools/font_build.py --check
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
| 搜（上下文，**按住**） | 贴近可搜索物按住 1.6~5s 搜完；中途走动/松手 = 归零零产出 |
| 背包 / ≡ | 背包 / 菜单（继续·暂停·装填·查看·蹲下·退出） |

