extends SceneTree
## W1 门禁：断电 / 杀进程模拟 —— 50 次中断点，每次都必须恢复到「最后一份完整状态」。
## 运行（headless）：
##   .tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script res://game/tests/save_interrupt.gd
## 通过输出一行 `SAVE_INTERRUPT_OK ...`。
##
## 为什么要 7 种相位而不是「真的 kill 进程」：kill 的落点不可复现（跑十次十次不同），
## 而断电对存档的伤害只取决于「死在哪个写步骤」，所以把 7 个步骤做成确定性故障态，
## 跑 50 轮覆盖每种 7 次。真 kill 由 plan 里的手工烟测补（见 design/BASELINE-v0.7.1-COMPARE.md）。

const RUNS := 50
const PHASES := 7

var _failures: Array[String] = []
var _paths: Dictionary = SaveStore.paths()
var _phase_hits: Dictionary = {}
var _recovered := 0
var _empty := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for i in RUNS:
		var phase := i % PHASES
		_phase_hits[phase] = int(_phase_hits.get(phase, 0)) + 1
		# 每一轮先造出「老档 + 上一份备份」：MAIN=12、BAK=10
		SaveStore.clear()
		_make(10).save()
		_make(12).save()

		match phase:
			0:  # 正常写：主档换成 20，旧主档降级成备份
				_make(20).save()
				_expect(20, "normal save")
			1:  # TMP 写完、还没提升：TMP 是最新那份
				_write_raw(_paths.tmp, _json(20))
				_expect(20, "crash after tmp write")
			2:  # TMP 只写了一半：忽略 TMP，回主档 12
				_write_raw(_paths.tmp, _json(20).substr(0, 24))
				_expect(12, "crash during tmp write")
			3:  # 主档已降级、TMP 还在：TMP 最新
				_rename(_paths.main, _paths.bak)
				_write_raw(_paths.tmp, _json(20))
				_expect(20, "crash between demote and promote")
			4:  # 主档损坏、TMP 不在：回备份 10
				_write_raw(_paths.main, "@@@ not a save @@@")
				_expect(10, "corrupt main, backup intact")
			5:  # 主档与 TMP 都没了，只剩备份 10
				_remove(_paths.main)
				_remove(_paths.tmp)
				_expect(10, "main and tmp gone, backup only")
			6:  # 三份全没：只能开新局
				SaveStore.clear()
				var none := RunState.load_saved()
				_check(none == null, "all slots gone must load null")
				_empty += 1

		# 自愈不变量：只要恢复成功，主档必须可解析且就是那份恢复出来的状态
		if phase != 6:
			var main_day := _day_of(_paths.main)
			_check(main_day >= 0, "main slot must be readable after recovery (phase %d)" % phase)

	_finish()


func _expect(expected_day: int, label: String) -> void:
	var loaded := RunState.load_saved()
	if loaded == null:
		_check(false, "%s: load returned null, expected day=%d" % [label, expected_day])
		return
	_recovered += 1
	_check(loaded.day == expected_day, "%s: recovered day=%d, expected %d" % [label, loaded.day, expected_day])
	_check(_day_of(_paths.main) == expected_day,
		"%s: main must self-heal to day=%d, got %d" % [label, expected_day, _day_of(_paths.main)])


func _make(day: int) -> RunState:
	var state := RunState.new()
	state.new_run()
	state.day = day
	state.building = "school"
	state.visited = ["school"]
	return state


func _json(day: int) -> String:
	return JSON.stringify(_make(day).to_dict(), "  ")


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "cannot open " + path + " for writing")
		return
	file.store_string(text)
	file.close()


func _rename(from_path: String, to_path: String) -> void:
	_remove(to_path)
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path)
	)


func _remove(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)


func _day_of(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return -1
	return int((parsed as Dictionary).get("day", -1))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("SAVE_INTERRUPT_FAIL " + message)


func _finish() -> void:
	SaveStore.clear()
	if _failures.is_empty():
		print("SAVE_INTERRUPT_OK runs=%d phases=%d recovered=%d empty=%d lost=0" % [RUNS, PHASES, _recovered, _empty])
		quit(0)
		return
	print("SAVE_INTERRUPT_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
