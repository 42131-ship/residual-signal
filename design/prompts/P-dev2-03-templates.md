你的任务：产出 `data/templates/` 下**四个模板** `fire_station.json` / `hospital.json` / `military_base.json` / `gas_station.json`。只输出合法 JSON，每份一个文件，不要围栏、不要解释。**请用 ` <<<FILE: 文件名 >>> ` 分隔四个文件的内容。**

## 背景

模板只决定**入口**：谁、从世界第几天进场、在哪、带什么、能进哪、枪的比例。模板**绝不可**改写时间轴 / 变量定义 / 终局态枚举。

世界日历（已定，不可改）：Day 0 爆发 / Day 1 打砸抢 / Day 3 断电 / Day 5 饥饿冒险 / Day 7 最后广播 / Day 14 检查站撤走 / Day 30 收束。收束日固定 Day 30，`局内天数 = 30 − 进场日`。

## 四个模板

| template_id | 地点 | 进场日候选 | 身份 | 枪 |
|---|---|---|---|---|
| `fire_station` | 消防站 | 0, 1, 3 | 消防员 | 无 |
| `hospital` | 医院 | 3, 4, 5 | 护士 / 值班医生 | 无 |
| `military_base` | 军事基地 | 3, 4, 5 | 军人 | **重**（20–30 发） |
| `gas_station` | 加油站 / 便利店 | 5, 7 | 店员 / 过路的人 | 0–2 发 |

## 字段（照抄结构，多余键不要加）

```json
{
  "template_id": "fire_station",
  "label": "消防站",
  "entry_days": [0, 1, 3],
  "identity": {
    "key_permission": ["器材柜钥匙", "防火门权限"],
    "how_recognized": "一句话：别人怎么认你",
    "initial_knowledge": ["三条具体信息，不要抽象"]
  },
  "weapon_budget": {
    "撬棍": {"rounds": 8, "sediment_per_shot": 0.02}
  },
  "noise_budget": {"cap": 2, "night_multiplier": 1.5},
  "safehouse_failure": {
    "card_id": "fire_station_xxx",
    "trigger_once": true,
    "condition": "必须是六组变量 / 日历 / 节点 tag 能判定的条件",
    "manifestation": "一件具体的事，留痕；参考：门从里面被打开、插销完好、少了一样东西"
  },
  "identity_note": "一句话：这个模板的「起点偏置」是什么"
}
```

## 硬约束（会被机器拒）

- **R18**：顶层**不得**出现 `timeline` / `variables` / `endings` / `end_state_enum` / `world_calendar`
- **R27**：`entry_days` 每个值 ∈ [0, 14]，非空
- **R28**：`noise_budget.cap` 必须是数值；且 `Σ(rounds × sediment_per_shot × 1.0)` **落在 cap 的 40%–65% 之间**（留余量给别的声音）
- **R29**：`safehouse_failure.card_id` 四份之间**不得重复**，且 `trigger_once` 严格为 `true`
- 不加任何伤害 / 血量 / 等级数值

## 设计意图（会被人审）

1. **军事基地是全案唯一允许枪占大篇幅的模板**：20–30 发，但 `sediment_per_shot` 要高（3 左右），意味着"你打得越爽，世界烂得越快"。它的 cap 要够撑住 20 发但明显吃紧。
2. **消防站**：靠门权和器材，不靠枪。噪声极低。它的安全屋失效应该是"防火门被人从里面锁死了"，你进不去。
3. **医院**：药多、尸多、感染压力最大。它的 `initial_knowledge` 应该包含"哪层楼还有人""电梯井能通到哪"。
4. **加油站**：起点最弱、离「找官方」线最近。补给少但通路多。

文案：中文，冷、短、不写抒情句。`initial_knowledge` 每条要是一个**可被系统查询的具体事实**，不是气氛描写。
