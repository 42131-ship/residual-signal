extends Node
class_name GameShell

signal loop_done(ok: bool, report: String)

var data: DataLayer
var world: WorldState


func _ready() -> void:
	if data == null:
		data = DataLayer.new()
	if world == null:
		world = WorldState.new()


func run_minimal_loop() -> void:
	if not data.load_all():
		_finish(false, "load_failed: data.load_all()")
		return

	if not world.init_from(data):
		_finish(false, "world_init_failed: world.init_from()")
		return

	if not new_game("school", 0):
		return

	# spend_time / set_var 是 void —— 契约里就写明没有返回值，错误只能靠内部 signal 报
	world.spend_time(1)
	world.spend_time(2)

	# add_noise 返回 {self, neighbors}，不是 {ok}；成功与否看 self 是否存在。
	var noise_result: Dictionary = world.add_noise("school_corridor_b", 2)
	if not noise_result.has("self"):
		_finish(false, "action_failed: add_noise(school_corridor_b)")
		return

	var corridor_sediment: int = world.sediment_of("school_corridor_b")

	if not save_game():
		_finish(false, "save_failed: user://save_01.json")
		return

	var saved_snapshot: Dictionary = world.snapshot()
	world.add_var("supplies", -0.1)
	if is_equal_approx(world.var_of("supplies"), float(saved_snapshot.get("variables", {}).get("supplies", -1.0))):
		_finish(false, "roundtrip_setup_failed: add_var(supplies, -0.1) 未生效")
		return

	if not load_game():
		_finish(false, "roundtrip_load_failed: user://save_01.json")
		return

	if world.snapshot() != saved_snapshot:
		_finish(false, "save_roundtrip_mismatch")
		return

	_finish(true, _make_summary(corridor_sediment))


func save_game(path: String = "user://save_01.json") -> bool:
	if world == null:
		_dev_log("save_game: world is null")
		return false

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_dev_log("save_game: %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false

	file.store_string(JSON.stringify(world.snapshot()))
	if file.get_error() != OK:
		_dev_log("save_game: write failed for %s: %s" % [path, error_string(file.get_error())])
		file.close()
		return false

	file.close()
	return true


func load_game(path: String = "user://save_01.json") -> bool:
	if world == null:
		_dev_log("load_game: world is null")
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_dev_log("load_game: %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false

	var contents := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(contents)
	if parsed == null or not parsed is Dictionary:
		_dev_log("load_game: invalid JSON in %s" % path)
		return false

	# 先验证副本，确保失败时不改动当前世界。
	var candidate = WorldState.new()
	var restore_result = candidate.restore(parsed)
	if not _operation_succeeded(restore_result):
		_dev_log("load_game: restore failed for %s: %s" % [path, _operation_error(restore_result, "world.restore")])
		return false

	restore_result = world.restore(parsed)
	if not _operation_succeeded(restore_result):
		_dev_log("load_game: restore failed for %s: %s" % [path, _operation_error(restore_result, "world.restore")])
		return false

	return true


func new_game(template_id: String = "school", entry_day: int = 0) -> bool:
	if world == null or data == null:
		_finish(false, "new_game_failed: world/data is null")
		return false

	# WorldState 没有 new_game/set_day/set_hour；开局 = init_from + spend_time 到 entry_day 08:00。
	# template 目前只做存在性校验（模板运行时尚未接入）。
	if data.template(template_id).is_empty():
		_finish(false, "new_game_failed: unknown template %s" % template_id)
		return false
	if entry_day < 0 or entry_day > 30:
		_finish(false, "new_game_failed: entry_day %d 超出 0..30" % entry_day)
		return false
	if not world.init_from(data):
		_finish(false, "new_game_failed: world.init_from()")
		return false
	world.spend_time(entry_day * 24 + 8)

	var initial_vars := {
		"trust": 0.3,
		"reputation": 0.0,
		"supplies": 0.8,
		"control": 0.0,
		"knowledge": 0.5,
	}
	# 六组之外的名字 set_var 会拒绝 —— 这里不许自造 health / morale / risk。
	# time 是派生变量（day/30），不写入。
	for variable_id: String in initial_vars:
		world.set_var(variable_id, float(initial_vars[variable_id]))

	return true


func _make_summary(corridor_sediment: Variant) -> String:
	var snapshot: Dictionary = world.snapshot()
	var day_value: Variant = snapshot.get("day", "unknown")
	var hour_value: Variant = snapshot.get("hour", "unknown")
	var variables: Dictionary = snapshot.get("variables", {})
	var supplies: Variant = variables.get("supplies", "unknown")
	var bounded := true
	# 只查六组变量；旧代码查 health/morale/risk 这三个不存在的名字，摘要恒为 false。
	for variable_id: String in WorldState.VARIABLE_NAMES:
		var value: Variant = variables.get(variable_id)
		if not (value is int or value is float) or float(value) < 0.0 or float(value) > 1.0:
			bounded = false
			break

	return "day=%s hour=%s supplies=%s corridor_b_sediment=%s six_vars_in_0..1=%s" % [
		str(day_value),
		str(hour_value),
		str(supplies),
		str(corridor_sediment),
		str(bounded),
	]


func _operation_succeeded(result: Variant) -> bool:
	if result is bool:
		return result
	if result is Dictionary:
		return bool(result.get("ok", false))
	return result != null


func _operation_error(result: Variant, fallback: String) -> String:
	if result is Dictionary:
		return str(result.get("error", result.get("message", fallback)))
	if result is String:
		return result
	return fallback


func _finish(ok: bool, report: String) -> void:
	loop_done.emit(ok, report)


func _dev_log(msg: String) -> void:
	# 项目约定：运行时不 print（gd_sanity 会拦），开发日志走 warning。
	push_warning(msg)