extends SceneTree
## 首 10 分钟引导门禁（2026-11-26，P0-4）。headless 可跑：
##   .tools/Godot_v4.7-stable_win64_console.exe --headless --path . --script res://game/tests/tutorial.gd
## 通过输出一行 `TUTORIAL_OK ...`。
##
## 守的契约：
##   ① 三步顺序（走 → 搜 → 出门），不可跳过、不可重复完成
##   ② 键盘与触摸两套提示文案都不为空，且各自提到对应操作
##   ③ 状态住在 RunState.tutorial_step：往返不丢、老档缺键当 0、越界钳位
##   ④ corridor.gd 真的把三处玩法事件接进引导（静态断言，改名/删hook 就红）

const CORRIDOR := "res://game/scenes/corridor.gd"
const MOVE_STEPS := 6

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tutorial := Tutorial.new()
	_check(tutorial.step == Tutorial.STEP_MOVE, "tutorial must start at move")
	_check(tutorial.step_id() == "move", "step_id at start must be move")
	var pc_text := tutorial.prompt(false)
	var touch_text := tutorial.prompt(true)
	_check(not pc_text.is_empty() and pc_text.find("A") >= 0, "pc prompt must mention A: %s" % pc_text)
	_check(not touch_text.is_empty() and touch_text.find("方向键") >= 0, "touch prompt must mention 方向键: %s" % touch_text)

	# ① 走：前 5 步不推进，第 6 步推进到 search
	for index in range(MOVE_STEPS - 1):
		_check(not tutorial.note_moved(), "move %d must not advance" % (index + 1))
	_check(tutorial.step == Tutorial.STEP_MOVE, "still on move after %d steps" % (MOVE_STEPS - 1))
	_check(tutorial.note_moved(), "move %d must advance" % MOVE_STEPS)
	_check(tutorial.step == Tutorial.STEP_SEARCH, "must be on search after walking")
	_check(tutorial.prompt(false).find("E") >= 0, "search prompt must mention E")

	# 顺序不可跳跃：在 search 阶段走一万步也不会推进
	_check(not tutorial.note_moved(), "walking during search must not advance")
	_check(not tutorial.note_depart(), "depart before searching must not advance")

	# ② 搜 → 出门 → 完成
	_check(tutorial.note_search(), "search must advance")
	_check(tutorial.step == Tutorial.STEP_DEPART, "must be on depart")
	_check(not tutorial.note_search(), "second search must not advance")
	_check(tutorial.note_depart(), "depart must advance")
	_check(tutorial.is_done(), "must be done")
	_check(tutorial.prompt(false).is_empty(), "done must show no prompt")
	_check(not tutorial.note_moved() and not tutorial.note_search() and not tutorial.note_depart(),
		"done must be terminal")

	# ③ 钳位
	var clamped := Tutorial.new()
	clamped.sync(-5)
	_check(clamped.step == Tutorial.STEP_MOVE, "sync lower clamp")
	clamped.sync(99)
	_check(clamped.step == Tutorial.STEP_DONE, "sync upper clamp")

	# ④ RunState 往返
	var run := RunState.new()
	run.tutorial_step = 2
	var reloaded := RunState.new()
	_check(reloaded.from_dict(run.to_dict()), "run state must accept its own dict")
	_check(reloaded.tutorial_step == 2, "tutorial_step must survive roundtrip")

	var legacy := run.to_dict()
	legacy.erase("tutorial_step")
	var old_run := RunState.new()
	old_run.tutorial_step = 3
	_check(old_run.from_dict(legacy), "legacy save must still load")
	_check(old_run.tutorial_step == 0, "legacy save without the key must read as 0")

	var fresh := RunState.new()
	fresh.new_run()
	_check(fresh.tutorial_step == 0, "new run must restart the tutorial")

	# ⑤ corridor 真的接了（静态断言）
	var source := FileAccess.get_file_as_string(CORRIDOR)
	for hook: String in ["_tutorial.note_moved()", "_tutorial.note_search()", "_tutorial.note_depart()"]:
		_check(source.find(hook) >= 0, "corridor.gd missing hook: " + hook)
	_check(source.find("Tutorial.new()") >= 0, "corridor.gd must build a Tutorial")

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("TUTORIAL_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("TUTORIAL_OK steps=3 move=%d order=strict prompts=pc/touch persist=run_state legacy=0 clamp=ok hooks=wired" % MOVE_STEPS)
		quit(0)
		return
	print("TUTORIAL_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
