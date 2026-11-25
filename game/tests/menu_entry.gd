extends SceneTree
## D14 门禁：主菜单「继续」/「新游戏」必须真的切到走廊场景（不是只弹一行提示）。
## 覆盖：继续 → corridor + RunState 读到存档（楼/天）；新游戏 → corridor + 从学校 Day0 重开。
## 运行（要渲染）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/menu_entry.gd -- MENU-ENTRY

const MENU := "res://game/scenes/main_menu.tscn"
const CORRIDOR := "res://game/scenes/corridor.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	RunState.current = null
	if FileAccess.file_exists(RunState.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

	# 造一份「继续」用的存档：加油站 / 第 3 天 / 有燃料
	var seeded := RunState.start_new()
	seeded.day = 3
	seeded.sediment = 2
	seeded.building = "gas_station"
	seeded.fuel = 2
	seeded.visited = ["school", "gas_station"]
	_check(seeded.save(), "seed save must succeed")
	RunState.current = null

	# ① 继续：current_scene 必须真的变成 corridor.tscn，且 RunState 读到存档
	_check(change_scene_to_file(MENU) == OK, "change to main menu must be requested")
	var menu := await _wait_scene(MENU)
	_check(menu != null, "main menu scene must load")
	if menu == null:
		return _finish()
	menu.move(1)  # 光标：新游戏 -> 继续
	_check(menu.current_index() == 1, "cursor must land on 继续")
	menu.confirm()
	var corridor := await _wait_scene(CORRIDOR)
	_check(corridor != null, "继续 must switch to corridor.tscn, current=%s" % _current_path())
	var run := RunState.current
	_check(run != null, "RunState.current must exist after 继续")
	if run != null:
		_check(run.building == "gas_station", "继续 must resume at gas_station, got %s" % run.building)
		_check(run.day == 3, "继续 must resume on day 3, got %d" % run.day)

	# ② 回菜单再「新游戏」：必须同样换场景，并从学校 Day0 开新局
	_check(change_scene_to_file(MENU) == OK, "change back to menu must be requested")
	var menu2 := await _wait_scene(MENU)
	_check(menu2 != null, "main menu must load again")
	if menu2 == null:
		return _finish()
	menu2.confirm()  # 默认 index 0 = 新游戏
	var corridor2 := await _wait_scene(CORRIDOR)
	_check(corridor2 != null, "新游戏 must switch to corridor.tscn, current=%s" % _current_path())
	var run2 := RunState.current
	_check(run2 != null, "RunState.current must exist after 新游戏")
	if run2 != null:
		_check(run2.building == "school", "new game must start at school, got %s" % run2.building)
		_check(run2.day == 0, "new game must start on day 0, got %d" % run2.day)

	_finish()


## 等 current_scene 变成目标场景（change_scene_to_file 是延迟生效的）。
func _wait_scene(path: String) -> Node:
	for _i in range(900):
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			await process_frame
			return current_scene
	return null


func _current_path() -> String:
	if current_scene == null:
		return "<null>"
	return str(current_scene.scene_file_path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("MENU_ENTRY_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("MENU_ENTRY_OK continue=corridor+save new_game=corridor+school")
		quit(0)
		return
	print("MENU_ENTRY_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
