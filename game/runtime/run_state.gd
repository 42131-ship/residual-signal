class_name RunState
extends RefCounted
## 一局游戏的状态（不是存档文件，是内存对象；to_dict/from_dict 负责与存档互转）。
##
## 只放「跨场景要用的东西」：第几天、沉积、当前在哪栋楼、已解锁结局、行动次数。
## 不放进来的：玩家坐标、容器搜过没有（那些属于具体场景，换场景就该重置）。

const MAX_DAY := 30
const SAVE_PATH := "user://run.json"

## 跨场景的唯一状态：静态引用，切换场景后仍然存在（不是 Node，所以不会被 free）。
static var current: RunState = null

var day := 0
var sediment := 0
var building := "school"
var actions_left := 1
var supplies := 0.8
var health := 1.0
var fuel := 0
var visited: Array[String] = ["school"]
## 同伴相关（M4 才会真的有人，但结局判定现在就要读它们）。
var companions_alive := 0
var companions_lost := 0
var bond := 0.0
## 终局选择：hold_broadcast / send_decoy / hide_in_infirmary / alone（空 = 还没选）
var finale := ""
var unlocked: Dictionary = {}   # template -> { ending_id: true }
var finished := false


## 取当前局；没有就开一局新的。
static func ensure() -> RunState:
	if current == null:
		current = RunState.new()
		current.new_run()
	return current


## 新开一局：天数/物资归零，但**结局档案要留着**（那是长期收集品）。
static func start_new() -> RunState:
	var previous := current
	var fresh := RunState.new()
	fresh.new_run()
	if previous != null:
		fresh.unlocked = previous.unlocked.duplicate(true)
	current = fresh
	return fresh



func new_run() -> void:
	day = 0
	sediment = 0
	building = "school"
	actions_left = 1
	supplies = 0.8
	health = 1.0
	fuel = 0
	visited = ["school"]
	companions_alive = 0
	companions_lost = 0
	bond = 0.0
	finale = ""
	finished = false
	# 解锁记录跨局保留：结局栏是长期档案，不该被「新游戏」清掉。


## 存档：跨场景要活下来，重启也要活下来。
func save() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("RUN_SAVE_FAILED: " + SAVE_PATH)
		return false
	file.store_string(JSON.stringify(to_dict(), "  "))
	return true


## 读档：没有存档/坏档都返回 null，由调用方决定开新局。
static func load_saved() -> RunState:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		return null
	var state := RunState.new()
	if not state.from_dict(parsed):
		return null
	return state


func visited_label() -> String:
	return ",".join(visited)


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
		"fuel": fuel,
		"visited": visited,
		"companions_alive": companions_alive,
		"companions_lost": companions_lost,
		"bond": bond,
		"finale": finale,
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
	fuel = maxi(0, int(data.get("fuel", 0)))
	visited = []
	for value: Variant in data.get("visited", []):
		visited.append(str(value))
	if visited.is_empty():
		visited.append(building)
	companions_alive = maxi(0, int(data.get("companions_alive", 0)))
	companions_lost = maxi(0, int(data.get("companions_lost", 0)))
	bond = clampf(float(data.get("bond", 0.0)), 0.0, 1.0)
	finale = str(data.get("finale", ""))
	finished = bool(data.get("finished", false))
	var raw: Variant = data.get("unlocked", {})
	unlocked = (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	return true
