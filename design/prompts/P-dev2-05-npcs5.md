你的任务：把 `data/npcs/npcs.json` 从 3 张扩到 **8 张**，只输出这 5 张新增卡的 JSON 数组。不要围栏、不要解释。

格式：`{"npcs": [ ...5 张... ]}`

## 已有的 3 张（不要重复，但可以引用它们的 npc_id 作为 `via`）

| npc_id | 归属 | 关系位 | 配件位语义 |
|---|---|---|---|
| npc_lin | shared | 熟人 | face(glasses) / neck(lanyard) / arm_front(papers) |
| npc_zhou | school | 同行的第三个人 | torso_front(badge) / back_torso(backpack) / chest_diagonal(strap) |
| npc_gu | school | 陌生人 | neck(keys) |

## 新增 5 张

| npc_id | display_role | scope | role_slot | 配件位（semantic 只许用这七个之一：face / neck / torso_front / back_torso / chest_diagonal / arm_front / head） |
|---|---|---|---|---|
| npc_wei | 教务处的干事 | shared | 熟人 | head(visor) / torso_front(badge) |
| npc_tan | 食堂的厨工 | shared | 陌生人 | torso_front(apron) / neck(towel) |
| npc_xu | 班长 | school | 同行的第三个人 | chest_diagonal(strap) / torso_front(badge) |
| npc_he | 修车铺的学徒 | shared | 陌生人 | back_torso(toolbag) / neck(goggles) |
| npc_mo | 广播站的老师 | school | 熟人 | neck(lanyard) / arm_front(script) |

## L0 里可引用的事件（`source_event` 只能从中选）

```
evt_w0001 Day 0 爆发开始        evt_w0002 Day 1 街面失控
evt_w0003 Day 3 全城断电        evt_w0004 Day 3 学校应急灯转电池
evt_w0005 Day 5 幸存者冒险上街  evt_w0006 Day 7 最后一次官方广播
evt_w0007 Day 14 检查站撤走     evt_w0008 Day 30 尸群迁移完成
evt_0142 Day 1 柜台底下扔来一卷绷带
evt_0150 Day 3 两个人分了一壶剩水
evt_0161 Day 5 传达室门从里面被打开，少了一串铜钥匙
evt_0177 Day 7 广播室那半句女声停了
```

## 每张卡必须满足（会自动校验，不过就废）

1. **R36**：每条记忆 `slots` 必须**五槽齐全**（`who` `what` `where` `manner` `outcome`），`fidelity` 必须严格等于 `3`，`fidelity_trace` 第一条的 `day` 必须等于记忆的 `day`。
2. **R13**：`fidelity_trace` 里的 fidelity **只许下降**；唯一例外是带 `"recalled": true` 那一步可以 +1（一次只 +1）。
3. **R12**：`source_event` 必须在上表里；若有 `hops` 则 ≤ 2。
4. `affinity` 范围 −1..1，`grief` 0..1。
5. 每人 **1–2 条**记忆，不要写满。

## 设计意图（会被人审）

- **npc_wei（教务处干事）**：手里有钥匙和名单，但**只肯跟"还有身份的人"说话**。affinity 低但可涨。
- **npc_tan（厨工）**：知道哪里有吃的，但**不会告诉陌生人**。他的记忆里应该有 `evt_w0005`。
- **npc_xu（班长）**：年纪小、跟着你走，记得的都是**别人的事**（`kind: "heard"`）。
- **npc_he（修车铺学徒）**：不是学校里的人，是**从外面进来的**。他记得 `evt_w0002` 那天街上的事。
- **npc_mo（广播站老师）**：`evt_w0006` 和 `evt_0177` 的当事人。**她不该记得自己说了什么，只记得"说过"**——她的 fidelity_trace 应该降得比别人快。

文案：`slots` 里写具体的东西（"二楼窗台""半袋米""铜钥匙"），不要写抽象（"帮过我""发生了事"）。不要写情绪词。
