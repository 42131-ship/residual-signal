给 `data/npcs/npcs.json` 补 2 个 NPC，凑到 12。只输出一个 JSON 对象：

```json
{"npcs": [ ...2 个... ]}
```

## 硬性格式（上次就是这里挂的）

- **单行合法 JSON**，不允许尾随 `</|json>`、说明句、注释
- 每个对象内的 `{` `}` 必须成对——上次 `npc_fan` 多了一个 `}`，整批报废
- 输出前自己数一遍括号

## 两个 NPC

| npc_id | display_role | scope | role_slot | 配件位（semantic 只许：face / neck / torso_front / back_torso / chest_diagonal / arm_front / head） |
|---|---|---|---|---|
| npc_fan | 退休的护士 | shared | 熟人 | face(glasses) / arm_front(papers) |
| npc_ying | 送水的 | shared | 陌生人 | back_torso(toolbag) / chest_diagonal(strap) |

## 字段模板（严格照抄结构，一个字段都不许少）

```json
{
  "npc_id": "npc_fan",
  "display_role": "退休的护士",
  "scope": "shared",
  "role_slot": "熟人",
  "accessory_slots": [
    {"id": 0, "semantic": "face", "name": "glasses"},
    {"id": 1, "semantic": "arm_front", "name": "papers"}
  ],
  "affinity": 0.2,
  "alive": true,
  "infected": false,
  "grief": 0.1,
  "memories": [
    {
      "source_event": "evt_0142",
      "day": 1,
      "kind": "direct",
      "via": null,
      "slots": {
        "who": "柜台边的护士",
        "what": "接住一卷绷带并给伤口包扎",
        "where": "柜台",
        "manner": "把绷带撕成窄条后绕了三圈",
        "outcome": "血止住了"
      },
      "fidelity": 3,
      "affect": 0.6,
      "last_recalled_day": 4,
      "provenance_lock": true,
      "fidelity_trace": [
        {"day": 1, "fidelity": 3},
        {"day": 12, "fidelity": 2},
        {"day": 20, "fidelity": 1}
      ]
    }
  ]
}
```

## 必须满足（机器校验）

- **R36**：`slots` 五槽齐全（`who` `what` `where` `manner` `outcome`）；`fidelity` 严格 = `3`；`fidelity_trace` 首条 `day` = 记忆的 `day`
- **R13**：trace 里 fidelity 只许下降（`recalled: true` 可 +1，一次只 +1）
- **R12**：`source_event` 只能取：`evt_w0001` `evt_w0002` `evt_w0003` `evt_w0005` `evt_w0006` `evt_w0007` `evt_0142` `evt_0150` `evt_0161`
- 每人 1–2 条记忆；`affinity` ∈ [−1,1]，`grief` ∈ [0,1]

## 文案

地点中立（这两人要跨 5 个模板复用）：可以写「街角」「柜台」「路口」「楼上」，
**不许写**：广播室 / 食堂冷库 / 传达室 / 实验室 / 配电间 / 地下车库 / 天台 / 器材室 / 教室。

`npc_fan` 懂包扎、会救人，但记性开始坏（trace 降得比别人快）。
`npc_ying` 跑过路，知道哪里还能打到水；他不轻易带人去。
