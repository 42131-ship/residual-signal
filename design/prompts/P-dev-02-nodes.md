你的任务：产出 `data/nodes.json`（学校模板 T0 的 16 个可进入节点）。只输出合法 JSON，不要 markdown 围栏、不要解释。

## 结构

地图不是平面图，是「一条轴 + 挂上去的房间」：
- `role: "axis"` = 主轴走廊，共 5 个，`axis_x` 必须从 0 连续到 4，`depth_layer` 全为 0
- `role: "room"` = 挂上去的房间，共 11 个
  - 地面层房间（`depth_layer: 0`）：从走廊侧向进入
  - 楼上（`depth_layer: 1`）：天台、广播室、办公室、教室3
  - 地下（`depth_layer: -1`）：冷库、地下车库、配电间
- 每个 room 的 `linked_nodes` **只能连到它所在的那一段主轴**（一个 `axis_x`），否则玩家能绕过主轴威胁（R30 会拒）
- 链接必须对称：A→B 则 B→A

## 16 个节点（node_id 与坐标已定死，不许改）

| # | node_id | role | axis_x | depth | 关键 |
|---|---|---|---|---|---|
| 01 | school_corridor_a | axis | 0 | 0 | `tags` 含 `spawn`、`teaching_1` |
| 02 | school_corridor_b | axis | 1 | 0 | `teaching_2` |
| 03 | school_corridor_c | axis | 2 | 0 | `teaching_5`（邻接安全屋） |
| 04 | school_corridor_d | axis | 3 | 0 | |
| 05 | school_corridor_e | axis | 4 | 0 | 末端 |
| 06 | school_f2_roof | room | 0 | 1 | `tags` 含 `noise_sink` |
| 07 | school_f2_broadcast | room | 1 | 1 | `tags` 含 `audio_source` |
| 08 | school_f2_office | room | 3 | 1 | `loot_table`: `keys` |
| 09 | school_f2_class3 | room | 4 | 1 | 可清空据点候选 |
| 10 | school_f1_class1 | room | 0 | 0 | 初始人群（tier_2 crowd）所在地；`teaching_3` |
| 11 | school_f1_lab | room | 1 | 0 | `loot_table`: `chem`；`noise_events` 含 `glass_break_01`；`teaching_4` |
| 12 | school_f1_guard | room | 2 | 0 | **唯一** `lockable: true`；`teaching_6` |
| 13 | school_f1_class2 | room | 4 | 0 | 传闻高发 |
| 14 | school_b1_coldstorage | room | 0 | -1 | `loot_table`: `food`；夜间高风险 |
| 15 | school_b1_garage | room | 1 | -1 | `clue_endpoint: true`；`day_locked_after: 14` |
| 16 | school_b1_power | room | 3 | -1 | `tags` 含 `power_node`；`light` 必须是 `"flashlight_only"` |

主轴之间的相邻关系：a-b-c-d-e 依次相连。房间挂在自己那一段：`school_f2_roof` 与 `school_f1_class1` 与 `school_b1_coldstorage` 挂 a（x=0）……以此类推。注意 `school_f1_lab`(x=1) 与 `school_f2_broadcast`(x=1) 与 `school_b1_garage`(x=1) 都挂 b。

## 每条节点必须带的字段

```
node_id         string
role            "axis" | "room"
template        "school"
axis_x          int
depth_layer     -1 | 0 | 1
segment         string   "corridor_a" … "corridor_e"
lockable        bool
sediment        0        ← 剧情模板初始必须为 0（R07）
loot_table      string   取自词表：office_med|food|chem|keys|roster|gear|ammo_scarce|empty
linked_nodes    string[]
light           "on" | "off" | "flashlight_only"
noise_events    string[] 取自词表：door_creak_02|glass_break_01|chair_scrape_01|footsteps_hall_01|gunshot_loud_01|crowbar_hit_01|vending_hum_01|broadcast_hum_01|locker_slam_01|drip_01
tags            string[] 取自词表：spawn|shelter|clue_possible|power_node|audio_source|noise_sink|clue_endpoint|teaching_1..teaching_6
background_key  string   必填，每间房都要有（缺失会导致切镜头黑屏，R24 拒）
parallax_layers [{"asset_key": string, "ratio": int}]  ratio 必须是整数倍
day_locked_after int|null
clue_endpoint   bool
```

## 设计要求（会被人审）

1. **教学节拍是线性可走的**：teaching_1..6 依次落在 a → b → b(class1) → lab → c → guard。玩家必须能在不弹任何提示的情况下，靠环境和声音走完这六步。
2. **暗得合理**：Day 0 有电，`light: "on"` 只给有灯的房间；地下层与广播室在 Day 3 后全黑。
3. **噪声有源头**：`noise_events` 只填这个房间真的会发出的声音。实验室是玻璃，走廊是脚步，车库是滴水。
4. **背景键要有语义**：`bg_corridor_*` / `bg_room_class` / `bg_room_lab` / `bg_room_guard` / `bg_room_broadcast` / `bg_roof` / `bg_b1_parking` / `bg_b1_cold` / `bg_b1_power` 之类，别用 `bg1/bg2`。
5. 视差层：室外（天台）至少 2 层，室内 1 层即可，ratio 用 1/2/3。
6. 不要写任何剧情文本、不要写 NPC 名字、不要写数值伤害。这是拓扑文件。
