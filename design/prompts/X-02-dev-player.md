写 `game/scenes/player.gd` —— 玩家角色控制器。**只输出这一个 GDScript 文件**，不要解释、不要索要文件。

## 形态

```gdscript
extends CharacterBody2D
class_name Player

signal stepped(is_running: bool)   # 每迈一步发一次，给噪声系统用
```

它自己建碰撞体，**不依赖任何场景文件**（`_ready` 里用代码加 `CollisionShape2D`）。

## 移动规格（Stage 2 手感复调）

| 项 | 值 |
|---|---|
| 慢走速度（按住 Shift） | `12.0` 像素/秒 |
| 正常速度（默认） | `24.0` 像素/秒 |
| 加速度 | `600.0`，减速度 `900.0` |
| 重力 | `0`（横版单轴，不做跳跃） |
| 碰撞体 | `RectangleShape2D` 12×28，中心偏移 `Vector2(0, -14)`（脚在原点） |
| 像素完美 | 停止时把 `position` 吸附到整数像素 |

输入用 `Input.is_action_pressed`，动作名 `move_left` / `move_right` / `walk`。
**如果这些 action 在项目里不存在，不要报错**——用 `Input.is_key_pressed(KEY_A / KEY_D / KEY_LEFT / KEY_RIGHT / KEY_SHIFT)` 作为后备。

## `stepped` 信号

每移动 **16 像素**发一次（累计位移跨过 16 的倍数）。
一次短促的 tween 或直接 `emit` 都行，但**不许每帧都发**。
慢走时 `is_running = false`，正常速度时 `true`——噪声系统靠它区分「静」和「响」。

## 相机

`_ready` 里建一个 `Camera2D` 子节点：
- `position_smoothing_enabled = false`（像素完美，不做亚像素平滑）
- `limit_left = 0`、`limit_top = 0`
- 不设 right/bottom（由调用方决定）

## 硬要求

- 中文注释，短
- 不写 `print`
- 不用 `class_name` 之外的全局单例
- 必须能过：
  `.tools/Godot_v4.7-stable_win64_console.exe --headless --path . --check-only --script res://game/scenes/player.gd`
- 注意：本项目的 `world_state.gd` 里 `spend_time` / `add_var` / `set_var` 都返回 **void**，你这个文件不碰世界状态，别引入依赖
