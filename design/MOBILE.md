# MOBILE · 手机版（Android APK）与手机游玩体验

> 状态：**2026-11-26 首次打通**。产出可安装的 arm64 debug/release APK，触摸操控覆盖走廊与主菜单，
> 安全区/横屏/省电/贴图压缩四项手机约束已落地，门禁 `touch-controls` 已进 `pipeline.json`。
> 真机尚未实测（本机没有连接设备）—— 这是本文件里唯一还没被验证的环节，别当成已完成。

---

## 1. 本机工具链（实测）

| 件 | 位置 / 值 |
|---|---|
| 导出用引擎 | `.tools/Godot_v4.7.2-stable_win64_console.exe`（从 `D:\extension\tools\godot` 复制） |
| 跑门禁用引擎 | `.tools/Godot_v4.7-stable_win64_console.exe`（**没换**，全部 41 条门禁仍在 4.7 上跑） |
| 导出模板 | `%APPDATA%\Godot\export_templates\4.7.2.stable`（本机只有 4.5.2 / 4.7.2，**没有 4.7.0**） |
| JDK | `.tools\jdk17\jdk-17.0.21.1+2`（Temurin 17，便携解压，无需管理员） |
| Android SDK | `C:\Users\Administrator\AppData\Local\Android\Sdk`（build-tools 34.0.0 / 35.0.0，platforms 34/35，platform-tools） |
| 编辑器设置 | `editor_settings-4.7.tres`：`export/android/java_sdk_path` 已指向上面的 JDK（**空着会直接报「需要有效的 Java SDK 路径」**） |
| 签名 | debug 用 `%APPDATA%\Godot\keystores\debug.keystore`；release 用 `.tools\keystore\residual-release.keystore`（口令在同目录 `signing.txt`，两者都不入库） |

> 为什么导出要用 4.7.2：模板只有 4.7.2。引擎与模板大版本必须一致，否则导出直接失败。
> 代价是「跑门禁用 4.7、打包用 4.7.2」两套引擎；**新门禁一律用 4.7 跑**（保持既有基线），
> 只有导出走 4.7.2。

## 2. 产出的包

| 件 | 值 |
|---|---|
| 包名 | `com.starxin.residualsignal` |
| 显示名 | 残余信号 |
| versionName / versionCode | `0.1.0` / `1`（发版时改 `export_presets.cfg` 的 `version/*`，同时改 `project.godot` 的 `config/version`） |
| minSdk / targetSdk | 24 / 36（模板默认） |
| ABI | **arm64-v8a**（32 位关掉了：一来 APK 少一半，二来 2026 年的手机没有 32 位需求） |
| debug APK | `build/android/ResidualSignal-debug.apk`（51.4 MB） |
| release APK | `build/android/ResidualSignal-release.apk`（49.6 MB），已签名，证书 `CN=starxin`，SHA-256 `971977…b580e` |
| 构建方式 | **模板 APK**（`gradle_build/use_gradle_build=false`）——不用装 Gradle，只要 JDK + SDK |

构建命令（本机，PowerShell）：

```powershell
$env:JAVA_HOME = 'D:\Downloads\残余信号\.tools\jdk17\jdk-17.0.21.1+2'
$G = '.tools\Godot_v4.7.2-stable_win64_console.exe'

# 第一次或新增资源后
& $G --headless --path . --import

# debug（自测用，debug keystore 自动签）
& $G --headless --path . --export-debug   "Android" 'build/android/ResidualSignal-debug.apk'

# release（release keystore 走环境变量，**不要**写进 export_presets.cfg）
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = 'D:\Downloads\残余信号\.tools\keystore\residual-release.keystore'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'residualsignal'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = '<见 .tools\keystore\signing.txt>'
& $G --headless --path . --export-release "Android" 'build/android/ResidualSignal-release.apk'

# 校验
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\34.0.0\apksigner.bat" verify --print-certs 'build\android\ResidualSignal-release.apk'
```

上线到 TapTap 走 `taptap-cli upload-apk`（见 `design/TAPTAP.md` §4）；TapTap 的手机包与 PC 包是两条独立通道，
**PC 包用 `upload-pc-package`，APK 用 `upload-apk`**。

## 3. 触摸操控怎么接的

代码：`game/ui/touch_controls.gd`（触摸层）+ `game/runtime/mobile_support.gd`（判定与生命周期）。
挂载点只有两处：`corridor.gd:_ready()` 与 `main_menu.gd:_ready()` 各一句 `MobileSupport.attach(self)`。
不是手机时返回 `null`，桌面与所有既有门禁的行为完全不变。

| 决定 | 为什么 |
|---|---|
| 命中用 `TouchScreenButton`，不用 `Control` 按钮 | Control 走「触摸→鼠标仿真」，多指会被合并成单指针；这游戏必须能「左手走 + 右手攻击」 |
| 按钮外观自己画（ColorRect + 点阵字 + 点阵箭头） | 项目风格：程序绘制、不引外部贴图，天然过像素门禁；顺带避免图集缺字（箭头 ←↑↓ 图集里没有） |
| 一次性动作**合成键事件**（`Input.parse_input_event`） | 走廊/菜单的输入走事件而不是状态；这样**不用改** `corridor.gd` / `main_menu.gd` 的热路径（那两处一改，D24 那批失效门禁会更难查） |
| 按住用 `Input.action_press/release` | `player.gd` 读的是动作状态，按住即走 |
| 十字键「按住 + 补一次按键事件」 | 旅行图/背包/主菜单只认事件；没有这一下，手机上能走但打不开地图、选不了菜单 |
| 步态改成**循环切换**（走→跑→蹲） | 手机上没法「按住 Shift 再按 Ctrl」；一键循环比并列两个修饰键可靠 |
| 安全区用 `DisplayServer.get_display_safe_area()` 反算到 384 空间 | 横屏刘海会吃掉边缘；算出安全矩形后把越界按钮挪回去 |
| 面板打开时触摸层压到 0.35 透明度（`set_dimmed`） | 检查/背包/旅行图是满宽的，按钮直接盖上去会挡字；压暗但保持可点，否则关不掉面板 |
| 图标由 `tools/icon_build.py` 生成 | 手排 32×32（黑暗里的发光门 + 人影），整数倍放大，颜色只取 `master.gpl`，过像素门禁 |

布局（384×216 原生坐标，全部避开左侧 HUD `x<130 & y<140`）：

```
左上 HUD                                 [包][看][退]
                                                    [填][走][灯]
   ▲                                                        (走=步态)
 ◀   ▶                                                         [打][E]
   ▼
```

`RS_TOUCH=1` 可在桌面强制显示触摸层（调手感用，不需要真机）：`$env:RS_TOUCH='1'` 后再启动游戏。

## 4. 手机专有约束（都做了，逐条对应）

| 约束 | 做法 | 位置 |
|---|---|---|
| 横屏 | `display/window/handheld/orientation=4`（SENSOR_LANDSCAPE，左右都能转） | `project.godot` |
| 安全区 | 触摸层按真实安全矩形收边 | `touch_controls.gd:apply_safe_area()` |
| 省电 | 切后台 `Engine.max_fps = 1`，回前台恢复 | `mobile_support.gd:Lifecycle` |
| 安卓返回键 | 当 Esc 用（关面板/收地图），不直接退进程 | 同上 |
| 贴图压缩 | `rendering/textures/vram_compression/import_etc2_astc=true` + 预设里 `texture_format/etc2_astc=true` | `project.godot` / `export_presets.cfg` |
| 渲染器 | 仍是 GL Compatibility（手机最稳的低配路径） | `project.godot` |
| 整数缩放 | 原生 384×216，`stretch=viewport` + `integer` | 未改（沿用桌面规格） |

## 5. 门禁

```powershell
python tools/validate.py        # 47 条规则：ERROR 0 · WARN 0 · SKIP 0
python tools/font_build.py --check   # 字体图集覆盖（真源已换成 Fusion 12px：1308 字、0 缺字）
.tools/Godot_v4.7-stable_win64_console.exe --headless --path . --script res://game/tests/touch_controls.gd
# TOUCH_OK buttons=12 layout=in_bounds hud=clear safe_area=clamped hold=state tap=event keys=matched panel=dim
```

> 2026-11-26 真机复跑后，全量 `run_gates.ps1` 是 **ALL PASS (41)**、148 秒；
> `pipeline.json` 现在 54 步、没有 `broken`。

`touch-controls` 已登记进 `pipeline.json`（`gate: hard`，headless 可跑）。它守的是**契约**，不是「真机点得准」：

1. 12 颗按钮都在 384×216 内、不压 HUD、彼此不重叠；
2. 给一个收窄的安全矩形后，所有按钮必须挪回里面；
3. 按住 = 动作状态，松开就掉；
4. 点按 = 合成事件（灯 → `KEY_F`、交互 → `KEY_E`、攻击 → 鼠标左键）；
5. 触摸层合成的键码 **必须等于** `corridor.gd` / `main_menu.gd` 里给该动作绑的键（改键不更新触摸层就红）；
6. 触摸层引用的每个动作，走廊/菜单里真的有注册。

另外新增了一个纯证据脚本（**需真实窗口，不进 pipeline**）：
`game/tests/touch_layout_shot.gd` → `design/previews/MOBILE_corridor_touch.png`（走廊 + 触摸层的实际构图）。

## 6. 字体

触摸层用了 `走 / 跑 / 蹲 / 灯 / 填 / 打 / 包 / 看 / 退` 九个字，其中 **蹲** 当时不在图集里（791 → 792 时漏的）。
后来字体真源换成了 **Fusion 12px（OFL-1.1）**，图集重建到 **1308 字、0 缺字、0 降采样**（见 `progress.json` 的 `pixel_font_pipeline`），
这九个字全在覆盖范围内。以后加按钮文案，先跑 `--check` 再重建，别等运行时静默缺字。

> **踩过的坑**：重建图集之后必须再跑一次 `--import`。否则 Godot 用的还是旧 PNG 的导入结果，
> 区域坐标与新 JSON 对不上——运行时表现不是「缺字」而是**整屏乱码**（每个字都画成别的字）。
> 2026-11-26 加引导文案时就撞了一次。

## 7. 还没做（诚实清单）

| # | 项 | 为什么重要 | 怎么验 |
|---|---|---|---|
| M1 | ~~真机实跑~~ **已做（2026-11-26）** | 设备 `2602BRT18C` / Android 17 / 2772×1280；走通 主菜单→走廊→搜索→门→出口→旅行图→到达→背包→手电，修掉「按住方向键不动」P0 | 评审与待改善项见 [`MOBILE-REVIEW.md`](MOBILE-REVIEW.md)；复跑 `tools/deploy_android.ps1` |
| M2 | ~~应用图标~~ **已做（2026-11-26）** | `tools/icon_build.py` 生成 32×32 手排图标（×6/×8 + 自适应 432 三件套），`pixelpipe` 6 色 PASS | `project.godot:config/icon` + `export_presets.cfg:launcher_icons/*` 已接；导出不再报 `No project icon specified` |
| M3 | 刘海/挖孔的实际收边 | 安全区只在门禁里用**注入的矩形**验过；真机已实测满屏（555×256 视口），但刘海区未单独核对 | 真机开游戏，看右上「包/看/退」是否被吃掉 |
| M4 | ~~19.5:9 的黑边~~ **已做（2026-11-26）** | 改成自算视口 `ceil(窗口/整数倍)` = 555×256 + 分数缩放，真机满屏无黑边 | 见 `mobile_support.gd:apply_fill_screen`；`RS_EXPAND` 开关见 TAKEOVER |
| M5 | 面板遮挡 | 检查面板/背包面板是满宽的，触摸按钮会压在上面 | 真机看「E 使用 Q 丢弃 TAB 关闭」那行是否被挡；必要时开面板时把右上按钮淡出 |
| M6 | 性能与发热 | GL Compatibility 本就是低配路径，但没测帧率/温度 | 真机抓 `adb shell dumpsys gfxinfo`，或在 HUD 加临时 FPS |
| M7 | ETC2/ASTC 重新导入 | 打开开关后没有重新导入纹理（`--import` 跑过，但压缩率未核） | 真机看显存与加载时间；必要时 `--import` 全量重跑 |
| M8 | 后台音频 | 切后台只压了帧率，音频没停 | 真机切后台听是否还在响 |
| M9 | iOS | 本次只做 Android | 需要 macOS + Xcode，另开一条线 |

## 8. 与 D23（发布管线）的关系

`design/TAPTAP.md` 的 PC 路线不变；本条线**补上了手机包**：

- `export_presets.cfg` 现在有两条预设（`Windows Desktop` / `Android`），都在仓库里、可 diff；
- `build/` 与 `*.keystore` 已进 `.gitignore`（本轮补的），签名文件不会误提交；
- release keystore 的口令只在本机 `.tools\keystore\signing.txt`，通过环境变量注入导出命令。

> 提醒：`.tools/` 整个目录不入库，keystore 丢失 = 无法给已上架的应用发更新包。
> **第一次上传 TapTap 之前先把 `.tools\keystore\` 备份到仓库外**。
