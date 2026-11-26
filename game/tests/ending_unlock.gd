extends SceneTree
## D5 门禁：结局判定 -> 写进 RunState -> 落盘 -> 结局栏真能显示。
## 运行（要渲染，抓一张结局栏）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/ending_unlock.gd -- ENDING

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _prefix := "ENDING"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("ENDING"):
			_prefix = argument
	RunState.current = null
	RunState.clear_saved()

	var corridor := SCENE.instantiate() as Node2D
	root.add_child(corridor)
	await process_frame
	await process_frame

	var state: WorldState = corridor._state
	_check(state != null, "world_state must be online")
	var run: RunState = RunState.current
	_check(run != null, "RunState.current must exist")
	if state == null or run == null:
		return _finish()
	_check(run.unlocked_for("school").is_empty(), "a fresh run must have no ending unlocked")

	# ① 孤狼条件：没同伴 + control/knowledge 够 + 有下水道图纸 + 第 26 天后
	corridor._day.day = 28
	run.companions_alive = 0
	run.finale = "alone"
	state.set_var("control", 0.6)
	state.set_var("knowledge", 0.5)
	state.set_var("trust", 0.4)
	corridor._inventory.add("sewer_map")
	var first: String = corridor._evaluate_ending()
	_check(first == "lone_wolf", "lone-wolf conditions must resolve, got %s" % first)
	_check(run.unlocked_for("school").has("lone_wolf"), "RunState must record the unlocked ending")
	var reloaded := RunState.load_saved()
	_check(reloaded != null and reloaded.unlocked_for("school").has("lone_wolf"),
		"the unlock must survive a save/reload")

	# ② 替身条件：knowledge 高 + trust 极低 + 丢过同伴 + 选了送替身
	run.finale = "send_decoy"
	run.companions_alive = 1
	run.companions_lost = 1
	state.set_var("knowledge", 0.9)
	state.set_var("trust", 0.1)
	var second: String = corridor._evaluate_ending()
	_check(second == "body_double", "decoy conditions must resolve to body_double, got %s" % second)
	_check(run.unlocked_for("school").has("body_double"), "body_double must be recorded")

	# ③ 结局栏：两个已解锁显示真名，另两个仍是问号
	var book := EndingBook.new()
	_check(book.load_template("school"), "ending book must load")
	book.adopt(run.unlocked)
	var rows := book.entries("school")
	var shown: Array[String] = []
	var masked := 0
	for row: Dictionary in rows:
		if bool(row["unlocked"]):
			shown.append(str(row["label"]))
		else:
			masked += 1
			_check(str(row["label"]) == "？？？", "locked row leaks its title")
	_check(shown.size() == 2, "exactly two endings should be unlocked, got %d" % shown.size())
	_check("孤狼" in shown, "lone wolf must show its real title, got %s" % str(shown))
	_check("替身" in shown, "body double must show its real title, got %s" % str(shown))
	_check(masked == 2, "the other two must stay hidden, got %d" % masked)

	# ④ 条件不足时不许乱记
	run.finale = ""
	corridor._day.day = 3
	state.set_var("knowledge", 0.2)
	state.set_var("control", 0.1)
	var third: String = corridor._evaluate_ending()
	_check(third == "", "an early run must not unlock any ending, got %s" % third)

	# ⑤ 重载后档案还在（模拟回主界面看结局栏）
	var again := RunState.load_saved()
	_check(again != null and again.unlocked_for("school").size() >= 2,
		"archive must keep both endings after reload")

	await RenderingServer.frame_post_draw
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("ENDING_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("ENDING_UNLOCK_OK lone_wolf=yes body_double=yes masked=2 persist=yes early_run=none")
		quit(0)
		return
	print("ENDING_UNLOCK_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
