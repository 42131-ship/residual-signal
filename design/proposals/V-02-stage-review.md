## 1. 现在离「能玩 90 秒」还差什么

1. **`main.gd` → 场景搭建**：实例化 `GameLoop`，挂载 UI 容器（日期显示、变量面板、卡牌槽位）
2. **`card_ui.gd`**：卡牌视觉表示（文本/图标 + 可点击区域），接收 `CardEngine` 的 slot 数据
3. **`game_loop.gd` 的 `_process`**：每帧调用 `advance_time`，监听卡牌点击事件，触发 `fire_card`
4. **四张 S 层卡**：补完 `layer_s_cafe/library/dorm/metro.gd`，保证每个模板至少 3 张可抽
5. **`bind_slots` 分布验证**：跑 10000 次采样，chi-square 检验 p > 0.05，或改用 Fisher-Yates
6. **首个可演示房间**：在 `rooms/` 下配一个 5 节点小房间（含 1 个 NPC + 2 个触发点），注册到 `RoomRegistry`

## 2. 哪些「已完成」其实是纸面的

- **33 条资产过像素门禁**：`SMOKE_OK` 和 `REPLAY_OK` 都没加载任何 Sprite/AudioStream，只测了引擎逻辑
- **13 个 NPC**：数据结构存在，但 `GameLoop` 里没有实例化代码，从未被 `fire_card` 的 `npc.modify_var` 调用过
- **5 个运行时类编译通过**：`CardUI` / `RoomRenderer` 还不存在，`GameLoop._ready` 是空的，实际上没有一帧画面被渲染

## 3. 如果只给 5 个工作日

| 天数 | 做什么 | 完成后能演示什么 |
|------|--------|------------------|
| D1 | 补完四张 S 卡 + 修 `bind_slots`（改 FY 或验证通过） | 抽卡池完整，回归测试绿 |
| D2 | `main.gd` 搭场景 + `CardUI` 最小实现（TextureRect + Label + Button） | 点击运行看到三个卡槽 + 日期数字 |
| D3 | `GameLoop._process` 连线 + 一个测试房间（5 节点 blockout） | 能点卡、时间跳、变量变、房间切换 |
| D4 | NPC 实例化 + `fire_card` 真正调 `npc.modify_var` | 点卡后 NPC 好感度变化可见 |
| D5 | 抛光：卡牌 hover 提示 + 变量面板美化 + 一轮内部试玩修 bug | 90 秒完整循环可录屏 |

## 4. 一个你现在就能判定的风险

**`hash(card+slot+seed) % options.size()` 在 options 数量变化时会让存档失效**。现在四个 S 模板还在补卡，等 D2 补完后 `layer_s_cafe.options.size()` 从 2 变 4，旧存档的 `replay_state.seed` 会让同一张卡绑到不同 slot 上，`REPLAY_OK` 的 roundtrip 断言会炸。这会在 D2 合并 S 卡补丁后的第一次回归测试时爆，代价是要么回滚 S 卡、要么放弃所有现存回放数据。

## 5. 一句话判决

**还不可以，先补「第 1 节清单的前 4 项」**——引擎逻辑稳，但 UI 和房间搭建是 0，这个缺口比想象的大，5 天刚好够最小可玩版本。