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
	var load_result = data.load_all()
	if not _operation_succeeded(load_result):
		_finish(false, "load_failed: %s" % _operation_error(load_result, "data.load_all"))
		return

	var init_result = world.init_from(data)
	if not _operation_succeeded(init_result):
		_finish(false, "world_init_failed: %s" % _operation_error(init_result, "world.init_from"))
		return

	if not new_game("school", 0):
		return

	# spend_time / set_var 是 void —— 契约里就写明没有返回值，错误只能靠内部 signal 报
	world.spend_time(1)
	world.spend_time(2)

	var noise_result = world.add_noise("school_corridor_b", 2)
	if not _operation_succeeded(noise_result):
		_finish(false, "action_failed: add_noise(school_corridor_b): %s" % _operation_error(noise_result, "add_noise(school_corridor_b)"))
		return

	var corridor_sediment = world.sediment_of("school_corridor_b")
	if corridor_sediment == null:
		_finish(false, "action_failed: sediment_of(school_corridor_b) returned null")
		return

	if not save_game():
		_finish(false, "save_failed: user://save_01.json")
		return

	var saved_snapshot = world.snapshot()
	var change_result = world.add_var("supplies", -0.1)
	if not _operation_succeeded(change_result):
		_finish(false, "roundtrip_setup_failed: add_var(supplies, -0.1): %s" % _operation_error(change_result, "add_var(supplies, -0.1)"))
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
	if world == null:
		_finish(false, "new_game_failed: world is null")
		return false

	var template_result = world.new_game(template_id, entry_day)
	if not _operation_succeeded(template_result):
		_finish(false, "new_game_failed: template %s: %s" % [template_id, _operation_error(template_result, "world.new_game")])
		return false

	var state_result = world.set_day(entry_day)
	if not _operation_succeeded(state_result):
		_finish(false, "new_game_failed: set day for template %s: %s" % [template_id, _operation_error(state_result, "set_day")])
		return false

	state_result = world.set_hour(8)
	if not _operation_succeeded(state_result):
		_finish(false, "new_game_failed: set hour for template %s: %s" % [template_id, _operation_error(state_result, "set_hour")])
		return false

	var initial_vars := {
		"trust": 0.3,
		"reputation": 0.0,
		"supplies": 0.8,
		"control": 0.0,
		"knowledge": 0.5,
		"time": 0.0,
	}
	# 六组之外的名字 set_var 会拒绝 —— 这里不许自造 health / morale / risk
	for variable_id in initial_vars:
		world.set_var(variable_id, initial_vars[variable_id])

	return true


func _make_summary(corridor_sediment: Variant) -> String:
	var snapshot = world.snapshot()
	var day = snapshot.get("day", "unknown")
	var hour = snapshot.get("hour", "unknown")
	var supplies = snapshot.get("vars", {}).get("supplies", "unknown")
	var vars: Dictionary = snapshot.get("vars", {})
	var bounded := true
	for variable_id in ["supplies", "trust", "knowledge", "health", "morale", "risk"]:
		var value = vars.get(variable_id)
		if not (value is int or value is float) or value < 0.0 or value > 1.0:
			bounded = false
			break

	return "day=%s hour=%s supplies=%s corridor_b_sediment=%s six_vars_in_0..1=%s" % [
		str(day),
		str(hour),
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
	print(msg)