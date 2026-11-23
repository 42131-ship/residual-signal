# 操作键位 · v0.4

> 本文是键位的唯一真源。实现位置：`game/scenes/corridor.gd:_ensure_actions()`（InputMap 动作）
> 与 `game/scenes/player.gd`（三档速度 / 纵深移动）。
> 呈现尺寸：玩家实际看到 **1920×1080**（原生 384×216 的 5× 整数最近邻放大，见 `game/tests/display.gd`）。
> 状态：✅ 已实现且有门禁断言 · ⏳ 已注册键位、系统未实现

---

## 一、当前 demo（走廊）可用

| 动作 | 键 | 行为 | 门禁 |
|---|---|---|---|
| 水平移动 | `A` / `D` 或 `←` / `→` | 横轴移动 | `corridor_preview` / `traverse` |
| 纵深移动 | `W` / `S` 或 `↑` / `↓` | 走进下方房间（y=128..216） | `traverse`（四角 + 中心 + A/B/C 区） |
| 步行（默认） | 不按速度键 | 24 px/s；纵深 19.2 px/s（×0.8） | `corridor_preview` |
| 蹲下潜行 | 按住 `Ctrl` | 12 px/s，最慢、噪声最低 | `corridor_preview`（crouch=29.5） |
| 疾跑逃跑 | 按住 `Shift` | 44 px/s，最快、噪声最高 | `corridor_preview`（sprint=107.7） |
| 拾取 / 搜索 | `E` | 上下文交互：搜索 A/B/C 区三个柜子，物品**自动进背包**（容量 10）；满了提示剩几件没拿 | `corridor_loot` / `corridor_inventory` |
| 开关 / 锁门 | `E`（无容器可搜时） | 靠近门：开着的门 → 关；关着的门 → 开；有挂锁时关着的门 → 上锁（消耗挂锁）；锁着的门 → 有钥匙或装备近战武器可撬开 | `corridor_doors` |
| 背包 | `Tab` | 打开/关闭背包；`W/S` 选择、`E` 使用、`Q` 丢弃、`Tab`/`Esc`/`V` 关闭；打开时锁移动 | `corridor_inventory` |
| 查看文本 | `V` | 打开检查框（28px 水平 + 24px 纵深）并锁移动 | `corridor_inspect` |
| 关闭 / 取消 | `Esc`（或 `E` / `V`） | 关面板；面板打开时 `E`/`V`/`Esc` 都关 | `corridor_inspect` |
| 攻击 / 挥击 | **鼠标左键** | 近战：命中前方 36px 内敌人、按武器伤害结算、消耗耐久；枪械：需先 `R` 装填，命中 320px 内敌人、消耗 1 发、噪声大；空手伤害 1；面板打开时不响应 | `corridor_combat` |
| 装填 | `R` | 已装备枪械且背包有对应弹药：消耗 1 件弹药、装满弹匣 | `corridor_combat`（reload=ammo） |
| 手电开关 | `F` | 光锥半径 240→0，整屏压暗 | `corridor_preview`（`CORRIDOR-QA_light_off.png`） |

## 二、门（v0.4 新增）

- 两个隔断各有一扇门，**初始常开**；门洞里没有门时可以直接穿过去。
- `E` 交互优先级：**可搜索容器 > 门**。站在急救柜旁边按 E 会先搜柜子，想关门要错开一步。
- 关门：门板出现、碰撞开启，挡住玩家。
- 上锁：门关着且背包里有 `padlock` 时按 E → 消耗挂锁、门锁死。
- 开锁：锁着的门按 E，背包里有 `keys` 或已装备近战武器 → 撬开；否则提示「锁着，需要钥匙或撬棍」。

## 三、已注册键位、系统未实现（⏳）

| 动作 | 键 | 说明 |
|---|---|---|
| 时间跳格 / 等待 | `T` | 日历跳格未接 |
| 暂停 | `Esc`（无面板时） | 存档只在剧情模式（R17） |

## 四、背包与使用

- 容量 10；同种物品堆叠显示 `×N`。
- 使用消耗品：食物 → 物资、医疗 → 体力、噪声类 → 噪声；没有 `effect` 的物品提示「这件东西现在用不上」且不消耗。
- 武器：使用 = 装备（不消耗），标题显示「装备 xx」；左键挥击按近战/枪械抬不同噪声。
- 丢弃 `Q`：从背包移除 1 件（不落回世界，后续再接地面掉落）。

## 五、为什么这么定（参考了同类游戏）

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

## 六、待定 / 已知缺口

1. 战斗只有挥击占位：没有敌人、命中、耐久、弹匣（下一步）。
2. 状态系统（伤口/感染/中毒/成瘾）未接。
3. 搜索耗时 `search_seconds` 未接「按住 E 搜 N 秒」。
4. `Q` 丢弃不落回世界；`R` 装填待枪械系统。
