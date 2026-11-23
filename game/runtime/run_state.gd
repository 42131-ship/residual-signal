class_name RunState
extends RefCounted
## 一局游戏的状态（不是存档文件，是内存对象；to_dict/from_dict 负责与存档互转）。
##
## 只放「跨场景要用的东西」：第几天、沉积、当前在哪栋楼、已解锁结局、行动次数。
## 不放进来的：玩家坐标、容器搜过没有（那些属于具体场景，换场景就该重置）。

const MAX_DAY := 30

var day := 0
var sediment := 0
var building := "school"
var actions_left := 1
var supplies := 0.8
var health := 1.0
var unlocked: Dictionary = {}   # template -> { ending_id: true }
var finished := false


func new_run() -> void:
	day = 0
	sediment = 0
	building = "school"
	actions_left = 1
	supplies = 0.8
	health = 1.0
	finished = false
	# 解锁记录跨局保留：结局栏是长期档案，不该被「新游戏」清掉。


func unlock_ending(template: String, ending_id: String) -> void:
	if not unlocked.has(template):
		unlocked[template] = {}
	unlocked[template][ending_id] = true


func unlocked_for(template: String) -> Dictionary:
	return (unlocked.get(template, {}) as Dictionary).duplicate()


func has_any_unlock() -> bool:
	for template: String in unlocked:
		if not (unlocked[template] as Dictionary).is_empty():
			return true
	return false


func to_dict() -> Dictionary:
	return {
		"schema": "run-state.v1",
		"day": day,
		"sediment": sediment,
		"building": building,
		"actions_left": actions_left,
		"supplies": supplies,
		"health": health,
		"finished": finished,
		"unlocked": unlocked.duplicate(true),
	}


func from_dict(data: Dictionary) -> bool:
	if str(data.get("schema", "")) != "run-state.v1":
		return false
	day = clampi(int(data.get("day", 0)), 0, MAX_DAY)
	sediment = clampi(int(data.get("sediment", 0)), 0, 40)
	building = str(data.get("building", "school"))
	actions_left = maxi(0, int(data.get("actions_left", 1)))
	supplies = clampf(float(data.get("supplies", 0.8)), 0.0, 1.0)
	health = clampf(float(data.get("health", 1.0)), 0.0, 1.0)
	finished = bool(data.get("finished", false))
	var raw: Variant = data.get("unlocked", {})
	unlocked = (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	return true
