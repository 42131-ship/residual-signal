class_name RunState
extends RefCounted
## 一局游戏的状态（不是存档文件，是内存对象；to_dict/from_dict 负责与存档互转）。
##
## 只放「跨场景要用的东西」：第几天、沉积、当前在哪栋楼、已解锁结局、行动次数。
## 不放进来的：玩家坐标、容器搜过没有（那些属于具体场景，换场景就该重置）。

const MAX_DAY := 30
## 存档实体在 SaveStore 里（主档 / 备份 / 临时档）。保留 SAVE_PATH 这个名字给测试清档用。
const SAVE_PATH := SaveStore.MAIN
## v2 = W1 起：v0（无 schema）/ v1 老档读入时自动迁移，只补字段不丢数据（D17）。
const SCHEMA := "run-state.v2"

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
## D12：world_state 六组变量的存档镜像（卡牌效果跨场景/重启要保留；旧档没有这个键 → 空字典）。
var world_vars: Dictionary = {}
## 同伴相关（M4 才会真的有人，但结局判定现在就要读它们）。
var companions_alive := 0
var companions_lost := 0
var bond := 0.0
## 终局选择：hold_broadcast / send_decoy / hide_in_infirmary / alone（空 = 还没选）
var finale := ""
var unlocked: Dictionary = {}   # template -> { ending_id: true }
var finished := false
## 首 10 分钟引导走到第几步（0 走 / 1 搜 / 2 出门 / 3 完成）。老档没这个键 → 0。
var tutorial_step := 0
## 这份存档是从哪个旧版本迁移来的（空 = 本来就是当前版本）。只用于诊断，不参与玩法。
var migrated_from := ""


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
	world_vars = {}
	companions_alive = 0
	companions_lost = 0
	bond = 0.0
	finale = ""
	finished = false
	# 引导是「这一局」的事：新游戏重新教一遍（老玩家会很快走完，不打断）。
	tutorial_step = 0
	# 新开一局不是从旧档迁移来的。
	migrated_from = ""
	# 解锁记录跨局保留：结局栏是长期档案，不该被「新游戏」清掉。


## 存档：跨场景要活下来，重启也要活下来。写盘交给 SaveStore 做原子化（主档+备份+临时档）。
func save() -> bool:
	if not SaveStore.write(to_dict()):
		push_error("RUN_SAVE_FAILED: " + SAVE_PATH)
		return false
	return true


## 读档：没有存档/坏档都返回 null，由调用方决定开新局。
## 主档坏了会自动回落备份/临时档，并把那份提升成主档（自愈），见 SaveStore.read()。
static func load_saved() -> RunState:
	var parsed: Variant = SaveStore.read()
	if not parsed is Dictionary:
		return null
	var state := RunState.new()
	if not state.from_dict(parsed):
		return null
	return state


## 三份存档全清（新游戏 / 测试开局用）。只删主档会把备份留下来污染下一次读取。
static func clear_saved() -> void:
	SaveStore.clear()


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
		"schema": SCHEMA,
		"migrated_from": migrated_from,
		"day": day,
		"sediment": sediment,
		"building": building,
		"actions_left": actions_left,
		"supplies": supplies,
		"health": health,
		"fuel": fuel,
		"visited": visited,
		"world_vars": world_vars.duplicate(true),
		"companions_alive": companions_alive,
		"companions_lost": companions_lost,
		"bond": bond,
		"finale": finale,
		"finished": finished,
		"tutorial_step": tutorial_step,
		"unlocked": unlocked.duplicate(true),
	}


func from_dict(data: Dictionary) -> bool:
	if not SaveStore.is_save_dict(data):
		return false
	# D17：老档原地迁移（v0 = 无 schema，v1 = 上一个格式）。只补字段，不覆盖已有值。
	var schema := str(data.get("schema", ""))
	migrated_from = "" if schema == SCHEMA else (schema if schema != "" else "run-state.v0")
	if schema != SCHEMA:
		data = data.duplicate(true)
		data["schema"] = SCHEMA
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
	var raw_vars: Variant = data.get("world_vars", {})
	world_vars = (raw_vars as Dictionary).duplicate(true) if raw_vars is Dictionary else {}
	companions_alive = maxi(0, int(data.get("companions_alive", 0)))
	companions_lost = maxi(0, int(data.get("companions_lost", 0)))
	bond = clampf(float(data.get("bond", 0.0)), 0.0, 1.0)
	finale = str(data.get("finale", ""))
	finished = bool(data.get("finished", false))
	# 老档（v1 早期）没有这个键：当成「没做过引导」，不丢其它数据。
	tutorial_step = clampi(int(data.get("tutorial_step", 0)), 0, 3)
	var raw: Variant = data.get("unlocked", {})
	unlocked = (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	return true
