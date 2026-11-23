写四个文件，每个模板一个 S 层（地点专属）事件卡文件。**用 `<<<FILE: data/cards/layer_s_<名字>.json >>>` 分隔**，只输出文件内容，不要解释、不要前缀废话。

## 各文件只需 1 张卡

| 文件 | template_id | 卡要点 |
|---|---|---|
| `layer_s_fire_station.json` | fire_station | 后院防火门被人从里面锁死，你进不去 |
| `layer_s_hospital.json` | hospital | 停电后果：电梯停在两层之间，里面有人 |
| `layer_s_military_base.json` | military_base | 军械库的锁是好的，但口令换了 |
| `layer_s_gas_station.json` | gas_station | 油泵还通着电，但开关在柜台后面 |

## card_id 必须逐字用这些（模板里的 safehouse_failure.card_id 已经写死了）

```
fire_station_safehouse_door_locked
hospital_safehouse_elevator
military_base_safehouse_armory
gas_station_safehouse_pump_switch
```

**如果拿不准模板里写的是哪个 id，就以本表为准，并且我会去核对 —— 对不上就是废件。**

## 每张卡的结构（严格照抄，多余键不要加）

```json
{
  "cards": [
    {
      "card_id": "fire_station_safehouse_door_locked",
      "layer": "S",
      "template": "fire_station",
      "title": "防火门",
      "trigger": {
        "day": {"min": 3, "max": 30},
        "vars": [{"name": "supplies", "op": "<=", "value": 0.7}],
        "node_ids": [],
        "sediment_min": 0
      },
      "slots": [
        {"slot": "sign", "options": ["门缝里没有光", "插销在里侧", "门把是热的"]},
        {"slot": "action", "options": ["推", "敲", "绕后"]},
        {"slot": "outcome", "options": ["没开", "开了", "你没再试"]}
      ],
      "text": {"default": "……（≤60 字，冷、短、不抒情）"},
      "effects": [
        {"when": "绕后", "vars": {"knowledge": 0.1, "time": -0.05}, "evidence": "evt_fs_door_detour"}
      ],
      "noise": null,
      "leftover": "……（≤30 字，必须能被事件日志证真）",
      "returns_after_days": 0
    }
  ]
}
```

## 硬约束（机器校验，不过就退）

- **R39**：每条 `effects[].when` 必须**逐字等于**本卡某个 slot 的某个 option
- **R35**：`vars` 只能用 `trust` `reputation` `supplies` `control` `knowledge` `time`
- **R34**：`trigger` 嵌套 ≤3 层（平铺写）
- **R33**：任何字段里不许出现别的 card_id
- **S 层可以用专名**（这一层就是要写「只有这个地方才有的东西」）：防火墙、器材柜、电梯井、军械库、油泵、柜台的抽屉——放心用
- `returns_after_days`：四张都写 `0`（安全屋失效/关键事件只发生一次）
- `leftover` 必填

文案要求：冷、短、不写「你感到……」。不要阿拉伯数字。
