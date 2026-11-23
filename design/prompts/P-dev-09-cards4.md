你的任务：给 `data/cards/layer_l.json` **再加 4 张卡**（从 8 张到 12 张），只输出这 4 张的 JSON 数组。不要围栏、不要解释。

格式：`{"cards": [ ...4 张... ]}`

## 已有 8 张（不要重复）

l_night_encounter 夜遇 / l_knock_three_times 敲门三下 / l_search_noise 搜刮噪音 / l_checkpoint_rumor 检查站传闻 / l_someone_lied 有人撒谎 / l_horde_passing 尸群过境 / l_first_dark_night 断电第一夜 / l_water_quarrel 水源争夺

## 新增 4 张

| card_id | 主题 | 这一张要让玩家决定什么 |
|---|---|---|
| `l_stranger_trade` | 陌生人想换东西 | 用物资换情报，还是留着物资 |
| `l_wounded_companion` | 同行的人受伤了 | 背着走（慢、暴露），还是留下（快、亏心） |
| `l_lock_them_out` | 门外有人在拍门 | 开门，还是把插销推上 |
| `l_memory_slip` | 有人把一件旧事记错了 | 纠正他，还是顺着他说 |

## 必须满足（会自动校验）

1. **R26**：正文与所有文本**禁止**出现模板专名：广播室、食堂冷库、传达室、实验室、配电间、地下车库、天台、器材室、教室1、教室2、教室3、办公室、课表、校牌、值日表、疏散铃、消防通道
2. **R39**：每条 `effects[].when` 必须**逐字等于**本卡某个 slot 的某个 option 字符串（含标点）
3. **R35**：`vars` 只能用 `trust` `reputation` `supplies` `control` `knowledge` `time`
4. **R34**：`trigger` 嵌套 ≤3 层（平铺写，不要 all/any 套娃）
5. **R33**：任何字段里不许出现别的 card_id
6. 每张卡 5–6 个 slot，每个 slot 2–4 个 option；`leftover` 必填且 ≤30 字

## 字段结构（和已有卡完全一致）

```json
{
  "card_id": "l_stranger_trade",
  "layer": "L",
  "title": "换东西",
  "trigger": {
    "day": {"min": 1, "max": 30},
    "vars": [{"name": "supplies", "op": ">=", "value": 0.3}],
    "node_tags_any": ["clue_possible"],
    "sediment_min": 0
  },
  "slots": [
    {"slot": "actor", "options": ["陌生人", "同行的第三个人"]},
    {"slot": "offer", "options": ["一条路", "一个名字", "一处没被搜过的地方"]},
    {"slot": "ask", "options": ["半袋粮", "一卷绷带", "你的手电"]},
    {"slot": "choice", "options": ["换", "不换", "先看看他有什么"]},
    {"slot": "outcome", "options": ["你换了", "你没换", "你还在看"]}
  ],
  "text": {"default": "……（≤60 字）", "heard": "……"},
  "effects": [
    {"when": "换", "vars": {"supplies": -0.1, "knowledge": 0.1}, "evidence": "evt_l_stranger_trade_swap"}
  ],
  "noise": null,
  "leftover": "……",
  "returns_after_days": 4
}
```

## `l_memory_slip` 特别说明

这张卡是全案的支点，写法要克制：
- 某个 NPC 把一件 **L0 里真实发生过的事** 记错了一个细节（记错的方向由 slots 决定）
- 玩家知道真相（因为 L0 在），但**游戏不告诉玩家该纠正还是该顺着**
- 效果：纠正 → `knowledge` 涨、`trust` 跌；顺着 → `trust` 涨、`knowledge` 不涨
- `leftover` 必须让这件事留下痕迹
- `returns_after_days`: 0（只发生一次）

文案要求：冷、短、不抒情、不解释情绪。**不写"你感到……"。** 不要出现阿拉伯数字。
