给 `data/npcs/npcs.json` **再加 4 个共享 NPC**（`scope: "shared"`），补齐 DEC-20261122-npc-pool 的「8 共享 + 每模板 4 专属」。只输出这 4 张卡的 JSON 数组：

```json
{"npcs": [ ...4 张... ]}
```

## 现有 8 个（不要重复）

| npc_id | scope | role_slot |
|---|---|---|
| npc_lin | shared | 熟人 |
| npc_wei | shared | 熟人 |
| npc_tan | shared | 陌生人 |
| npc_he | shared | 陌生人 |
| npc_zhou | school | 同行的第三个人 |
| npc_xu | school | 同行的第三个人 |
| npc_mo | school | 熟人 |
| npc_gu | school | 陌生人 |

## 新增 4 个（全是 shared，必须能跨 5 个模板复用）

| npc_id | display_role | role_slot | 配件位（semantic 只许用：face / neck / torso_front / back_torso / chest_diagonal / arm_front / head） |
|---|---|---|---|
| npc_qi | 修自行车的 | 陌生人 | back_torso(toolbag) / neck(towel) |
| npc_shen | 便利店店长 | 熟人 | torso_front(apron) / head(visor) |
| npc_luo | 邮局的 | 同行的第三个人 | chest_diagonal(strap) / neck(lanyard) |
| npc_fan | 退休的护士 | 熟人 | face(glasses) / arm_front(papers) |

## 硬约束（会校验，不过就退）

1. **R36**：每条记忆 `slots` 五槽齐全（`who` `what` `where` `manner` `outcome`），`fidelity` 严格 = `3`，`fidelity_trace` 首条 `day` = 记忆的 `day`
2. **R13**：`fidelity_trace` 的 fidelity 只许下降；唯一例外带 `"recalled": true` 可 +1
3. **R12**：`source_event` 只能取下面这串；有 `hops` 则 ≤2
4. `affinity` ∈ [−1,1]，`grief` ∈ [0,1]；每人 1–2 条记忆

## 可引用的 L0 事件

```
evt_w0001 Day 0 爆发开始        evt_w0002 Day 1 街面失控
evt_w0003 Day 3 全城断电        evt_w0005 Day 5 幸存者冒险上街
evt_w0006 Day 7 最后一次官方广播  evt_w0007 Day 14 检查站撤走
evt_0142 Day 1 柜台底下扔来一卷绷带
evt_0150 Day 3 两个人分了一壶剩水
evt_0161 Day 5 传达室门从里面被打开，少了一串铜钥匙
```

## 设计意图

这四个人是**跨模板复用**的：他们不属于学校，属于「这个城市」。所以他们的记忆必须是地点中性的——
可以提「街角」「柜台」「路口」「楼上」，**不许提**：广播室 / 食堂冷库 / 传达室 / 实验室 / 配电间 / 地下车库 / 天台 / 器材室 / 教室。

- **npc_qi**：从外面进来的人，记得 Day 1 街上那次崩溃
- **npc_shen**：有货、有店，但店早就不开了
- **npc_luo**：跑过路的人，知道 Day 14 之后哪条路废了
- **npc_fan**：懂包扎，会救人，但记性开始坏

文案：具体（"半袋米""自行车内胎""一张没盖戳的邮单"），不要抽象，不要情绪词。
