class_name Tutorial
extends RefCounted

## 首 10 分钟引导（2026-11-26，P0-4）。
##
## 三步：走两步 → 搜一个柜子 → 从出口出门。
## 设计取舍：
## - **不加 UI 层**：只在 HUD 画一行字，省得再写一套排版，也不会被面板/触摸层挤掉；
## - **只由玩法事件推进**（`stepped` / 搜索完成 / 出发成功），不做「点击继续」——
##   手机上多一次点击就多一次流失；
## - **状态住在 RunState**（`tutorial_step`，可选键），跨场景与重启都记得；
## - 老师玩家会被这几步自动走完（走 6 步、搜一次、出一次门），不需要「跳过」按钮。

const STEP_MOVE := 0
const STEP_SEARCH := 1
const STEP_DEPART := 2
const STEP_DONE := 3
## player 每走 16px 发一次 stepped；6 步 ≈ 走出一段路，够让玩家看懂移动。
const MOVE_STEPS := 6

var step := STEP_MOVE
var moved := 0


func sync(step_value: int) -> void:
	step = clampi(step_value, STEP_MOVE, STEP_DONE)


## 返回 true 表示这一步刚刚完成（调用方要落盘 + 重画 HUD）。
func note_moved() -> bool:
	if step != STEP_MOVE:
		return false
	moved += 1
	if moved < MOVE_STEPS:
		return false
	step = STEP_SEARCH
	moved = 0
	return true


func note_search() -> bool:
	if step != STEP_SEARCH:
		return false
	step = STEP_DEPART
	return true


func note_depart() -> bool:
	if step != STEP_DEPART:
		return false
	step = STEP_DONE
	return true


func is_done() -> bool:
	return step >= STEP_DONE


## 当前该显示的一行字；**恒为空**。
## 2026-11-26 按《手机玩家舒适圈》约束改正：不写「走到柜子前点 E 搜索」这类替玩家思考的导航句。
## 教学改为「柜子上方一格极淡微光」（见 corridor.gd:_build_container_glows）——只表达「这个能碰」，
## 不指路、不给方向。流程状态（tutorial_step）保留，用于统计与后续分步解锁，不再驱动文案。
func prompt(_touch: bool) -> String:
	return ""


## 门禁用：三步各推进一次应得的终态。
func step_id() -> String:
	match step:
		STEP_MOVE:
			return "move"
		STEP_SEARCH:
			return "search"
		STEP_DEPART:
			return "depart"
		_:
			return "done"
