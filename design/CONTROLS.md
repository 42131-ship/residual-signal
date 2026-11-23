# 操作键位 · v0.2

> 本文是键位的唯一真源。实现位置：`game/scenes/corridor.gd:_ensure_actions()`（InputMap 动作）
> 与 `game/scenes/player.gd`（三档速度 / 纵深移动）。
> 状态：✅ 已实现且有门禁断言 · ⏳ 已注册键位、系统未实现

---

## 一、当前 demo（走廊）可用

| 动作 | 键 | 行为 | 门禁 |
|---|---|---|---|
| 水平移动 | `A` / `D` 或 `←` / `→` | 横轴移动 | `corridor_preview` / `traverse` |
| 纵深移动 | `W` / `S` 或 `↑` / `↓` | 走进下方房间（y=128..216） | `traverse`（四角 + 中心可达） |
| 步行（默认） | 不按速度键 | 24 px/s；纵深 19.2 px/s（×0.8） | `corridor_preview` |
| 蹲下潜行 | 按住 `Ctrl` | 12 px/s，最慢、噪声最低 | `corridor_preview`（crouch=29.5） |
| 疾跑逃跑 | 按住 `Shift` | 44 px/s，最快、噪声最高 | `corridor_preview`（sprint=107.7） |
| 拾取 / 搜索 | `E` | 上下文交互：两个可搜索柜子（储物柜 / 急救柜）；同一天第二次显示「今天已经翻过」 | `corridor_loot` / `loot` |
| 查看文本 | `V` | 打开检查框（28px 水平 + 24px 纵深）并锁移动 | `corridor_inspect` |
| 关闭 / 取消 | `Esc`（或 `E` / `V`） | 关面板；面板打开时 `E`/`V`/`Esc` 都关 | `corridor_inspect` |
| 手电开关 | `F` | 光锥半径 240→0，整屏压暗 | `corridor_preview`（`CORRIDOR-QA_light_off.png`） |

## 二、已注册键位、系统未实现（⏳）

| 动作 | 键 | 说明 |
|---|---|---|
| 攻击 / 射击 | **鼠标左键** | 按你的拍板定左键；战斗系统未实现，InputMap 已注册 `attack` |
| 装填 | `R` | 枪械系统未实现 |
| 背包 | `Tab` | 按你的拍板定 Tab；库存系统未实现，InputMap 已注册 `inventory` |
| 丢弃 | `Q` | 库存系统未实现 |
| 暂停 | `Esc`（无面板时） | 存档只在剧情模式（R17） |

## 三、为什么这么定（参考了同类游戏）

- **E = 交互 / 拾取**、**F = 手电**、**Tab = 背包** 是三件套的常见做法：
  [Silver Pines](https://www.magicgameworld.com/silver-pines-controls-guide-all-pc-keyboard-and-mouse-controls/)
  （Run=Shift、Crouch=Ctrl、Interact=E、Inventory=Tab/I、Flashlight=F）与
  [Slender: The Haunt](https://www.speedrun.com/ko-KR/slender_haunt/guides/3nh0r)
  （Shift 疾跑、F 手电、E 交互、Tab 背包）一致。
- **查看/检查拆成独立键**：Crow Country 用单独的 examine 键（J），
  [Darkwood](https://www.magicgameworld.com/darkwood-pc-controls/) 则是鼠标指到物体后出现
  Examine / Search 上下文命令。我们把「查看文本」放 `V`（view），`E` 留给拾取/搜索，
  避免「想捡东西却弹出说明文本」。
- **左键战斗**：Crow Country 的鼠标布局把射击/装填都放在鼠标键上，
  与 [Crow Country 控制表](https://strategywiki.org/w/index.php?title=Crow_Country/Controls) 一致。

> 备注：现在 `V` 是查看键（Stage 2 时查看是 `E`）；`E` 已改作拾取/搜索。旧的 `inspect`
  动作名已拆成 `view` 与 `pickup` 两个 InputMap 动作，重绑键位时不会互相牵连。

## 四、待定 / 已知缺口

1. **背包系统未实现**，所以搜到的东西只显示文本、不落库存（下一步接 `inventory`）。
2. **战斗系统未实现**，左键目前只是注册了键位。
3. `Q`（丢弃）、`R`（装填）、`T`（时间跳格）仍是提案，等对应系统落地时启用。
4. 房间目前是**一整条可走地面带**，还没有分隔墙/门洞；`traverse` 只验证了整块区域的四角与中心可达。
