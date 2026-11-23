你的任务：产出 `data/npcs/npcs.json` —— NPC 状态卡**首批 3 张**。只输出合法 JSON，不要围栏、不要解释。

## 背景

NPC 池已定为「8 个共享（关系占位）+ 每模板 4 个专属」。本批：**1 个共享 + 2 个学校专属**。

记忆三层：
- **L0** 世界事实日志（append-only，已存在，见下）
- **L1** NPC 情景记忆（带 owner，`source_event` 必须指向 L0 的 `event_id`）
- **L2** 措辞渲染（不许自己造事实）

fidelity：3 = 精确 / 2 = 概括 / 1 = 印象 / 0 = 情绪残影。
降级顺序写死：`manner → where → what 细节 → 只留 who + affect`。
被谈起只 +1，且不还原细节。

## L0 里可引用的事件（`source_event` 只能从中选）

```
evt_w0001  Day 0  爆发开始
evt_w0002  Day 1  街面失控
evt_w0003  Day 3  全城断电
evt_w0004  Day 3  学校应急灯转电池
evt_w0005  Day 5  幸存者冒险上街
evt_w0006  Day 7  最后一次官方广播
evt_w0007  Day 14 检查站撤走
evt_w0008  Day 30 尸群迁移完成
evt_0142   Day 1  有人从柜台底下扔来一卷绷带
evt_0150   Day 3  两个人分了一壶剩水
evt_0161   Day 5  传达室门从里面被打开，少了一串铜钥匙
evt_0177   Day 7  广播室那半句女声停了
```

## 三张卡

| npc_id | 归属 | 关系位 | 配件位（语义必须照抄） |
|---|---|---|---|
| `npc_lin` | shared | 熟人 | `[{"id":0,"semantic":"face","name":"glasses"},{"id":1,"semantic":"neck","name":"lanyard"},{"id":2,"semantic":"arm_front","name":"papers"}]` |
| `npc_zhou` | school | 同行的第三个人 | `[{"id":0,"semantic":"torso_front","name":"badge"},{"id":1,"semantic":"back_torso","name":"backpack"},{"id":2,"semantic":"chest_diagonal","name":"strap"}]` |
| `npc_gu` | school | 陌生人 | `[{"id":0,"semantic":"neck","name":"keys"}]` |

## 字段（严格照这个）

```json
{
  "npcs": [
    {
      "npc_id": "npc_lin",
      "display_role": "老师",
      "scope": "shared",
      "role_slot": "熟人",
      "accessory_slots": [ ... 照上表抄 ... ],
      "affinity": 0.6,
      "alive": true,
      "infected": false,
      "grief": 0.2,
      "memories": [
        {
          "source_event": "evt_0142",
          "day": 1,
          "kind": "direct",
          "via": null,
          "slots": {"who": "player", "what": "给了绷带", "where": "柜台底下", "manner": "没说话，从底下扔过来", "outcome": "伤口包上了"},
          "fidelity": 3,
          "affect": 0.8,
          "last_recalled_day": 3,
          "provenance_lock": true,
          "fidelity_trace": [
            {"day": 3, "fidelity": 3},
            {"day": 9, "fidelity": 3, "recalled": true}
          ]
        }
      ]
    }
  ]
}
```

## 硬约束（会被机器拒）

- **R12**：每个 `memories[].source_event` 必须出现在上面那份 L0 清单里；`hops`（若有）≤ 2
- **R13**：`fidelity_trace` 里的 fidelity **只许下降**；唯一例外是带 `"recalled": true` 的那一步可以 +1，且一次只能 +1
- **R25**：`accessory_slots` 的 `semantic` 必须和上表逐字一致（丧尸化派生要靠它认人）

## 设计意图（写进 memories，会被人审）

1. **npc_lin（老师）** 记得 `evt_0142` 那卷绷带，且 Day 9 之后开始模糊。这是全案最关键的一个人：**她会在 Day 16 之后忘掉你是怎么进来的**。
2. **npc_zhou（学生）** 只在 `evt_0150` 和 `evt_0161` 里出现过。他应该是「传闻型」记忆：`kind: "heard"`，`hops: 1`，`via` 写他听谁说的。
3. **npc_gu（传达室的人）** 记得钥匙不见那件事，但他**不相信是自己人干的**，affect 应为负。

每人 1–2 条记忆即可，不要写满。**留白比写满重要。**

## 文案

`slots` 里的句子要具体（"柜台底下""铜钥匙""半壶水"），不要抽象（"帮过我""发生了事"）。
不要写情绪词（"他很感激""她很难过"）——情绪走 `affect` 字段，不走文字。
