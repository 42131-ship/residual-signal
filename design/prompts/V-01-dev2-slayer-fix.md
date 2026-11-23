改写四个 S 层卡文件，使其 `card_id` 与**模板里写死的值**一致。上一位用了错的 id（我给的表是编的），已作废。

**用 `<<<FILE: data/cards/layer_s_<名字>.json >>>` 分隔四个文件**，只输出文件内容，不要解释、不要前缀。

## 权威映射（这四个 id 是从 `data/templates/*.json` 里读出来的，不可改）

| 文件 | template_id | `safehouse_failure.card_id`（必须逐字用） | 模板里写死的表现 |
|---|---|---|---|
| `layer_s_fire_station.json` | fire_station | `fire_station_fire_door_locked` | 后院防火门被人从里面锁死，门外的插销完好，你无法进入 |
| `layer_s_hospital.json` | hospital | `hospital_ward_access_blocked` | 住院楼职工通道被病床堵住，门锁未损坏，通道无法通过 |
| `layer_s_military_base.json` | military_base | `military_base_supply_record_missing` | 军械库出入登记簿缺失，柜门已锁，无法核对剩余弹药 |
| `layer_s_gas_station.json` | gas_station | `gas_station_back_door_open` | 便利店后门被人从外面打开，门锁没有损坏，货架上少了一箱瓶装水 |

**注意**：每张卡的内容必须与它对应的「表现」对得上。门店、电梯、军械库锁这类与表现不符的写法一律不算。

## 结构（严格照抄，多余键不要加）

```json
{
  "cards": [
    {
      "card_id": "fire_station_fire_door_locked",
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
      "text": {"default": "……（≤60 字）"},
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

## 硬约束（机器校验）

- **R39**：每条 `effects[].when` 必须**逐字等于**本卡某个 slot 的某个 option
- **R35**：`vars` 只能用 `trust` `reputation` `supplies` `control` `knowledge` `time`
- **R34**：`trigger` 嵌套 ≤3 层（平铺写）
- **R33**：任何字段里不许出现别的 card_id
- S 层**可以用专名**（防火门、电梯井、军械库、油泵、登记簿）——这一层就是要写本地的东西
- 四张都 `returns_after_days: 0`；`leftover` 必填
- 文案冷、短、不写「你感到……」，不用阿拉伯数字
