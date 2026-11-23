extends SceneTree
## 结局栏门禁：每模板固定 4 槽、未解锁不剧透、解锁后显示真标题、四结局判定与优先级。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/endings.gd

var _failures: Array[String] = []


func _initialize() -> void:
	var book := EndingBook.new()
	if not book.load_template("school"):
		_fail("load failed: " + book.load_error())
		return

	# ① 固定四槽、id 唯一、顺序 1..4
	_check(book.slot_count("school") == 4, "school must expose 4 slots, got %d" % book.slot_count("school"))
	for id: String in ["military", "lone_wolf", "betrayal", "body_double"]:
		_check(book.has("school", id), "missing ending %s" % id)
	_check(not book.has("school", "echo"), "the old echo ending must be gone")

	# ② 未解锁时绝不剧透：标题是占位，回忆是占位
	var locked := book.entries("school")
	_check(locked.size() == 4, "entries must list 4 slots, got %d" % locked.size())
	for row: Dictionary in locked:
		_check(not bool(row["unlocked"]), "fresh book must be all locked")
		_check(str(row["label"]) == "？？？", "locked slot leaks its title: %s" % str(row["label"]))
		_check(not str(row["summary"]).contains("直升机"), "locked slot leaks its summary")
	_check(book.unlocked_count("school") == 0, "unlocked count must start at 0")
	_check(not book.is_complete("school"), "book must not be complete yet")

	# ③ 解锁后显示真标题，其余仍是灰的
	_check(book.unlock("school", "military"), "unlock must accept a known ending")
	_check(not book.unlock("school", "nonsense"), "unlock must reject an unknown ending")
	var partly := book.entries("school")
	var shown := ""
	var still_hidden := 0
	for row: Dictionary in partly:
		if bool(row["unlocked"]):
			shown = str(row["label"])
		else:
			still_hidden += 1
	_check(shown == "军队到来", "unlocked slot must show its title, got %s" % shown)
	_check(still_hidden == 3, "the other three slots must stay hidden, got %d" % still_hidden)
	_check(book.unlocked_count("school") == 1, "unlocked count should be 1")

	# ④ 四个结局各有一条能命中的上下文；顺序决定优先级
	var military_ctx := {
		"companions_alive": 3, "bond": 0.9, "trust": 0.8, "control": 0.7,
		"knowledge": 0.8, "day": 30, "finale": "hold_broadcast",
	}
	_check(book.match_ending("school", military_ctx) == "military", "military context must resolve to military")

	var lone_ctx := {
		"companions_alive": 0, "control": 0.6, "knowledge": 0.5, "day": 28,
		"items": ["sewer_map"], "trust": 0.4, "bond": 0.4,
	}
	_check(book.match_ending("school", lone_ctx) == "lone_wolf", "lone context must resolve to lone_wolf")

	var betrayal_ctx := {
		"companions_alive": 1, "bond": 0.1, "day": 29, "finale": "hide_in_infirmary",
		"ammo": 3, "trust": 0.3,
	}
	_check(book.match_ending("school", betrayal_ctx) == "betrayal", "betrayal context must resolve to betrayal")

	var decoy_ctx := {
		"companions_alive": 1, "companions_lost": 1, "knowledge": 0.85, "trust": 0.1,
		"day": 29, "finale": "send_decoy",
	}
	_check(book.match_ending("school", decoy_ctx) == "body_double", "decoy context must resolve to body_double")

	# ⑤ 优先级：好结局条件全满足时，即使也满足替身，也不许被替身抢走
	var both := decoy_ctx.duplicate()
	both["companions_alive"] = 3
	both["bond"] = 0.9
	both["trust"] = 0.8
	both["control"] = 0.7
	both["finale"] = "hold_broadcast"
	_check(book.match_ending("school", both) == "military", "military must outrank body_double when both fit")

	# ⑥ 都不满足 → 空（由上层按「未完赛」处理）
	var nothing := {"companions_alive": 1, "bond": 0.5, "trust": 0.5, "control": 0.2, "knowledge": 0.3, "day": 10}
	_check(book.match_ending("school", nothing) == "", "no matching context must return empty")

	# ⑦ 全解锁 = 收齐
	for id: String in ["lone_wolf", "betrayal", "body_double"]:
		book.unlock("school", id)
	_check(book.is_complete("school"), "four unlocks must complete the template")
	_check(book.unlocked_count("school") == 4, "unlocked count should be 4 after full unlock")

	if not _failures.is_empty():
		print("ENDINGS_FAILED count=%d" % _failures.size())
		for failure: String in _failures:
			print("  - " + failure)
		quit(1)
		return
	print("ENDINGS_OK template=school slots=4 mask=no_spoiler match=order first=military")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("ENDINGS_FAIL " + message)


func _fail(detail: String) -> void:
	push_error("ENDINGS_FAIL " + detail)
	print("ENDINGS_FAIL " + detail)
	quit(1)
