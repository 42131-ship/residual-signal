extends SceneTree
## W1 门禁：存档原子化 —— 主档/备份/临时档三槽、自愈、v0/v1 → v2 迁移（D17）。
## 运行（headless，纯文件 IO 不需要渲染）：
##   .tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script res://game/tests/save_atomic.gd
## 通过输出一行 `SAVE_ATOMIC_OK ...`。

var _failures: Array[String] = []
var _paths: Dictionary = SaveStore.paths()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	SaveStore.clear()
	_check(not SaveStore.exists_any(), "clear() must remove all three slots")
	_check(RunState.load_saved() == null, "no save -> load_saved() must be null")

	# ① 第一次存档：只有主档，没有备份
	var a := _make(3, "school")
	_check(a.save(), "first save must succeed")
	_check(FileAccess.file_exists(_paths.main), "main slot must exist after save")
	_check(not FileAccess.file_exists(_paths.bak), "no backup before the second save")
	_check(_schema_of(_paths.main) == RunState.SCHEMA, "main must carry the current schema")
	var first := RunState.load_saved()
	_check(first != null and first.day == 3, "round-trip must keep day=3")
	_check(first != null and first.migrated_from == "", "a fresh v2 save is not a migrated one")

	# ② 第二次存档：旧主档必须降级成备份
	var b := _make(7, "gas_station")
	_check(b.save(), "second save must succeed")
	_check(_day_of(_paths.main) == 7, "main must hold the newest state")
	_check(_day_of(_paths.bak) == 3, "backup must hold the previous state")

	# ③ 主档损坏：回落备份，并把备份提升回主档（自愈）
	_write_raw(_paths.main, "{ this is not json")
	var healed := RunState.load_saved()
	_check(healed != null and healed.day == 3, "corrupt main must recover from the backup")
	_check(_day_of(_paths.main) == 3, "recovered state must be promoted back to main")

	# ④ 写完 TMP 就断电：TMP 是最新那份，必须优先于旧主档
	SaveStore.clear()
	_make(11, "school").save()
	var newer := _make(13, "hospital")
	_write_raw(_paths.tmp, JSON.stringify(newer.to_dict(), "  "))
	var from_tmp := RunState.load_saved()
	_check(from_tmp != null and from_tmp.day == 13, "a complete tmp must win over an older main")
	_check(_day_of(_paths.main) == 13, "tmp recovery must be promoted to main")

	# ⑤ TMP 只写了一半：忽略它，回主档
	SaveStore.clear()
	_make(21, "school").save()
	_write_raw(_paths.tmp, "{\"schema\": \"run-state.v2\", \"day\": 2")
	var skewed := RunState.load_saved()
	_check(skewed != null and skewed.day == 21, "a partial tmp must be ignored, main wins")

	# ⑥ 迁移：v1 老档（有 schema，缺 tutorial_step）
	SaveStore.clear()
	_write_raw(_paths.main, JSON.stringify(_legacy(true, 5), "  "))
	var v1 := RunState.load_saved()
	_check(v1 != null and v1.day == 5, "v1 save must load")
	_check(v1 != null and v1.migrated_from == "run-state.v1", "v1 must be recorded as migrated")
	_check(v1 != null and v1.tutorial_step == 0, "missing keys must be filled with defaults")
	_check(v1 != null and v1.supplies > 0.79 and v1.supplies < 0.81, "v1 numeric fields must survive")

	# ⑦ 迁移：v0 老档（连 schema 键都没有）
	SaveStore.clear()
	_write_raw(_paths.main, JSON.stringify(_legacy(false, 9), "  "))
	var v0 := RunState.load_saved()
	_check(v0 != null and v0.day == 9, "schema-less v0 save must load")
	_check(v0 != null and v0.migrated_from == "run-state.v0", "v0 must be recorded as migrated")

	# ⑧ 未知 schema：拒收，不能把别的 JSON 当存档
	SaveStore.clear()
	_write_raw(_paths.main, "{\"schema\": \"something-else.v9\", \"day\": 1}")
	_check(RunState.load_saved() == null, "unknown schema must be rejected")

	SaveStore.clear()
	_finish()


# ── helpers ─────────────────────────────────────────────────────────────

func _make(day: int, building: String) -> RunState:
	var state := RunState.new()
	state.new_run()
	state.day = day
	state.building = building
	state.visited = [building]
	return state


## 造一份老档：with_schema=false 时连 schema 键都没有（v0）。
func _legacy(with_schema: bool, day: int) -> Dictionary:
	var state := RunState.new()
	state.new_run()
	var data := state.to_dict()
	data.erase("migrated_from")
	data.erase("tutorial_step")
	data["day"] = day
	data["building"] = "school"
	data["visited"] = ["school"]
	if with_schema:
		data["schema"] = "run-state.v1"
	else:
		data.erase("schema")
	return data


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "cannot open " + path + " for writing")
		return
	file.store_string(text)
	file.close()


func _parsed(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _day_of(path: String) -> int:
	var parsed: Variant = _parsed(path)
	if not parsed is Dictionary:
		return -1
	return int((parsed as Dictionary).get("day", -1))


func _schema_of(path: String) -> String:
	var parsed: Variant = _parsed(path)
	if not parsed is Dictionary:
		return ""
	return str((parsed as Dictionary).get("schema", ""))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("SAVE_ATOMIC_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("SAVE_ATOMIC_OK slots=3 schema=%s backup=yes self_heal=yes tmp_priority=yes migrate=v0/v1" % RunState.SCHEMA)
		quit(0)
		return
	print("SAVE_ATOMIC_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
