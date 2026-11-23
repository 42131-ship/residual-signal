你的任务：产出 `data/cards/layer_s_school.json` —— **S 层（地点专属）事件卡 2 张**，只有学校模板用。只输出合法 JSON，不要围栏、不要解释。

## 和 L 层的区别

L 层 8 张卡跨 5 个模板共用，正文禁止出现模板专名。
**S 层相反：必须写只有学校才有的东西**——广播室、传达室、课表、校牌、疏散铃、器材室，这些词在这一层是合法的，而且越多越好。

## 两张卡

### 1. `school_broadcast_last` —— 广播室最后一次播音

- 地点：`school_f2_broadcast`
- 时间窗：Day 6 ~ Day 8（最后一次广播在 Day 7）
- 这张卡要让玩家做一个决定：**听完 vs 记下来 vs 走开**。听完花时间（世界继续烂），走开省时间但丢失信息。
- leftover 必须能被事件日志证真：广播停掉之后，广播室里的东西要留下痕迹。
- `returns_after_days`: 0（只发生一次）

### 2. `school_transmission_office_breach` —— 传达室失效

**这张卡的 card_id 不能改**：`data/templates/school.json` 里 `safehouse_failure.card_id` 已经把它写死了，改了就过不了 R29。

- 地点：`school_f1_guard`（唯一能上锁的安全屋）
- 触发：`day >= 3`，且玩家此刻在传达室里锁门休息
- 表现：**门是从里面被打开的，插销完好；屋里少了一件东西，没少别的**（少什么由你定，但必须是具体物件）
- 后果：玩家失去安全屋的确定性，但**不能失去安全屋本身**——传达室仍然能锁，只是玩家不再确定它管用
- 全局只触发一次
- `returns_after_days`: 0

## 字段（严格照这个写，和 L 层同构）

```json
{
  "cards": [
    {
      "card_id": "school_broadcast_last",
      "layer": "S",
      "template": "school",
      "title": "最后一次播音",
      "trigger": {
        "day": {"min": 6, "max": 8},
        "vars": [{"name": "supplies", "op": "<=", "value": 0.6}],
        "node_ids": ["school_f2_broadcast"],
        "sediment_min": 0
      },
      "slots": [
        {"slot": "voice", "options": ["半句循环的女声", "电流声", "一句规程"]},
        {"slot": "action", "options": ["听", "记下来", "走开"]},
        {"slot": "cost", "options": ["时间", "暴露"]},
        {"slot": "outcome", "options": ["你听完了", "你只记住一半", "你没听完"]}
      ],
      "text": {
        "default": "……（≤60 字，出现“频率”“底噪”“半句”这类词，不要解释）",
        "heard": "……"
      },
      "effects": [
        {"when": "听完", "vars": {"knowledge": 0.1, "time": -0.05}, "evidence": "evt_school_broadcast_last_heard"}
      ],
      "noise": null,
      "leftover": "……（≤30 字）",
      "returns_after_days": 0
    }
  ]
}
```

## 硬约束（会被机器拒）

- **R33**：effects / leftover / text / trigger 里不许出现另一张卡的 card_id
- **R34**：`trigger` 嵌套 ≤ 3 层（不要写 `all`/`any` 套娃，用上面那种平铺结构）
- **R35**：`vars` 只能用六组：`trust` `reputation` `supplies` `control` `knowledge` `time`
- 每张卡 `slots` 3–6 个，每个 slot 2–4 个 option
- `leftover` 不许为空

## 文案要求

冷、短、不抒情、不解释情绪。**不写「你感到……」，只写看得见听得见的东西。**
不要出现数字（"三下"可以，"3 分钟"不要）。
