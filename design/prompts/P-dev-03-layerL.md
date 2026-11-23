你的任务：产出 `data/cards/layer_l.json` —— **L 层（地点无关）事件卡 8 张**。只输出合法 JSON，不要围栏、不要解释。

## 这一层为什么特殊

《残余信号》有 5 个角色模板（学校 / 消防站 / 医院 / 军事基地 / 加油站），共享同一套 L 层卡。
所以 L 层卡的正文**绝不能出现任何一个模板专属的地名或物件名**，否则它只能在一个模板里用，另外四个模板会当场出戏。

禁用词（出现即被 R26 拒收）：
广播室、食堂冷库、传达室、实验室、配电间、地下车库、天台、器材室、教室1、教室2、教室3、办公室、课表、校牌、值日表、疏散铃、消防通道

可用的空间说法：「走廊」「门另一侧」「楼上」「楼梯口」「储藏间」「柜台」「窗」「地下那层」「外面」。

## 人物只能用占位，不能有名字

L 层跨模板，具名 NPC 是模板专属资产。所以角色一律用关系占位：
`熟人`（好感度高的那个）、`陌生人`、`同行的第三个人`、`屋里的人`、`楼上的人`、`你救过的那个`

## 八张卡的主题（顺序即节奏，不许换）

| # | card_id | 主题 | 这一张要让玩家做什么决定 |
|---|---|---|---|
| 1 | l_night_encounter | 夜遇 | 要不要为一个人停下（时间 vs 人） |
| 2 | l_knock_three_times | 有人敲门，敲了三下 | 开不开门（信息不足下的判断） |
| 3 | l_search_noise | 搜刮时的声音 | 继续搜完 vs 立刻撤（物资 vs 沉积） |
| 4 | l_checkpoint_rumor | 检查站前 | 信不信一条传闻（知情度 vs 时间） |
| 5 | l_someone_lied | 有人撒谎 | 拆穿 vs 装不知道（信任 vs 真相） |
| 6 | l_horde_passing | 尸群过境 | 躲着不动 vs 趁乱走（时间 vs 风险） |
| 7 | l_first_dark_night | 断电后第一夜 | 点不点灯（看见 vs 被看见） |
| 8 | l_water_quarrel | 水源争夺 | 分 vs 抢（声望 vs 物资） |

## 每张卡的字段（严格照这个写）

```json
{
  "card_id": "l_night_encounter",
  "layer": "L",
  "title": "夜遇",
  "trigger": {
    "day": {"min": 1, "max": 30},
    "vars": [{"name": "supplies", "op": "<=", "value": 0.6}],
    "node_tags_any": ["clue_possible"],
    "sediment_min": 0,
    "requires_npc_alive": true
  },
  "slots": [
    {"slot": "actor", "options": ["熟人", "陌生人", "同行的第三个人"]},
    {"slot": "manner", "options": ["从阴影里走出来", "一直站在那儿", "边走边回头看"]},
    {"slot": "want", "options": ["一口水", "一个能锁门的地方", "一句话"]},
    {"slot": "cost", "options": ["时间", "物资", "暴露"]},
    {"slot": "outcome", "options": ["你给了", "你没给", "你还没决定"]}
  ],
  "text": {
    "default": "……（≤60 字）",
    "heard": "……（当 actor 的信息来自传闻时用）"
  },
  "effects": [
    {"when": "你想给的表达", "vars": {"trust": 0.1}, "evidence": "evt_xxx"}
  ],
  "noise": null,
  "leftover": "事后的痕迹（≤30 字，必须能被事件日志证真）",
  "returns_after_days": 3
}
```

规则：
- `slots` 必须 5–8 个，每个 slot 2–4 个 option。
- `trigger.vars` 只能用六组变量：`trust` / `reputation` / `supplies` / `control` / `knowledge` / `time`，值域 0–1。
- `trigger.node_tags_any` 只能从：`spawn` `shelter` `clue_possible` `power_node` `audio_source` `noise_sink` `clue_endpoint`
- `effects[].evidence` 必须是 `evt_` 开头的占位 id（真实 id 由 L0 运行时生成，这里只声明「必须写一条证据」）。
- `leftover` 是这张卡过去之后，世界留下什么。**没有 leftover 的卡不许存在**——那就成了纯文本演出。
- `returns_after_days`：这张卡多久后可以再触发（0 = 一次性）。第 1、3、5、8 张设 0（只发生一次），其余设 2–5。

## 文案要求

- 正文 ≤60 字，中文，冷、短、不抒情、不解释情绪。
- **不写「你感到……」，只写看得见听得见的东西。**
- 每张卡的 default 必须留一个空——玩家得自己补完发生了什么。
- 不要出现数字（"三"这种量词可以有，"3 个"不要）。
