class_name WorldState
extends RefCounted

signal changed(var_name: String, old_value: float, new_value: float)
signal day_advanced(day: int)
signal sediment_changed(node_id: String, delta: int)

const VARIABLE_NAMES: Array[String] = [
	"trust",
	"reputation",
	"supplies",
	"control",
	"knowledge",
	"time",
]

var data: DataLayer
var variables: Dictionary = {}
var day: int = 0
var hour: int = 0
var sediment: Dictionary = {}
var locked_until: Dictionary = {}


func init_from(d: DataLayer) -> bool:
	if d == null:
		push_error("WorldState 需要有效的 DataLayer")
		return false

	data = d
	variables = {
		"trust": 0.0,
		"reputation": 0.0,
		"supplies": 0.0,
		"control": 0.0,
		"knowledge": 0.0,
		"time": 0.0,
	}
	day = 0
	hour = 0
	sediment = {}
	locked_until = {}
	_refresh_locks()
	return true


func var_of(name: String) -> float:
	if not variables.has(name):
		push_error("未知世界变量: " + name)
		return 0.0
	return float(variables[name])


func add_var(name: String, delta: float) -> float:
	if not variables.has(name):
		push_error("未知世界变量: " + name)
		return 0.0
	if name == "time":
		push_warning("time 是派生变量，不能直接修改")
		return float(variables[name])

	var old_value: float = float(variables[name])
	var new_value: float = clampf(old_value + delta, 0.0, 1.0)
	if not is_equal_approx(old_value, new_value):
		variables[name] = new_value
		changed.emit(name, old_value, new_value)
	return float(variables[name])


func set_var(name: String, value: float) -> void:
	if not variables.has(name):
		push_error("未知世界变量: " + name)
		return
	if name == "time":
		push_warning("time 是派生变量，不能直接修改")
		return

	var old_value: float = float(variables[name])
	var new_value: float = clampf(value, 0.0, 1.0)
	if not is_equal_approx(old_value, new_value):
		variables[name] = new_value
		changed.emit(name, old_value, new_value)


func spend_time(hours: int) -> void:
	if hours <= 0:
		push_error("推进时间的小时数必须大于 0")
		return

	var total_hours: int = hour + hours
	var days_passed: int = total_hours / 24
	hour = total_hours % 24
	for _i: int in range(days_passed):
		advance_day()


func advance_day() -> void:
	var old_value: float = float(variables.get("time", 0.0))
	day = mini(day + 1, 30)
	var new_value: float = clampf(float(day) / 30.0, 0.0, 1.0)
	variables["time"] = new_value
	if not is_equal_approx(old_value, new_value):
		changed.emit("time", old_value, new_value)
	_refresh_locks()
	day_advanced.emit(day)


func add_noise(node_id: String, base: int, night: bool = false) -> Dictionary:
	var sensitivity: float = 1.0
	if data != null:
		sensitivity = float(data.noise_sensitivity(day))

	var multiplier: float = 1.0
	if night and data != null:
		# DataLayer 只有 profile(mode) 方法；旧代码读 data.get("mode_profile") 恒为 null，
		# 夜晚噪声倍率从未生效。
		var story: Dictionary = data.profile("story")
		if not story.is_empty():
			multiplier = float(story.get("night_multiplier", 1.0))

	var self_delta: int = _scaled_noise(base, sensitivity * multiplier)
	_add_sediment(node_id, self_delta)

	var neighbors: Dictionary = {}
	var node_record: Variant = _node_record(node_id)
	var linked: Variant
	if node_record is Dictionary:
		linked = node_record.get("linked_nodes", [])
	elif node_record != null:
		linked = node_record.get("linked_nodes")

	if linked is Array:
		for neighbor_id: Variant in linked:
			var neighbor: String = str(neighbor_id)
			if neighbor.is_empty() or neighbor == node_id:
				continue
			var neighbor_base: int = maxi(1, int(base / 2))
			var neighbor_delta: int = _scaled_noise(neighbor_base, sensitivity * multiplier)
			_add_sediment(neighbor, neighbor_delta)
			neighbors[neighbor] = neighbor_delta

	return {"self": self_delta, "neighbors": neighbors}


func sediment_of(node_id: String) -> int:
	return int(sediment.get(node_id, 0))


func can_enter(node_id: String) -> bool:
	if not locked_until.has(node_id):
		return true
	return day <= int(locked_until[node_id])


func snapshot() -> Dictionary:
	return {
		"day": day,
		"hour": hour,
		"variables": variables.duplicate(true),
		"sediment": sediment.duplicate(true),
	}


func restore(s: Dictionary) -> bool:
	if not s.has("day") or not s.has("hour") or not s.has("variables") or not s.has("sediment"):
		return false
	# JSON 往返会把整数读成 float（Godot 4 JSON 数值统一 float），这里按数值校验后取整。
	var day_value: Variant = s["day"]
	var hour_value: Variant = s["hour"]
	if not (day_value is int or day_value is float) or not (hour_value is int or hour_value is float):
		return false
	var restored_day: int = int(day_value)
	var restored_hour: int = int(hour_value)
	if not is_equal_approx(float(day_value), float(restored_day)) or not is_equal_approx(float(hour_value), float(restored_hour)):
		return false
	if restored_day < 0 or restored_day > 30 or restored_hour < 0 or restored_hour > 23:
		return false

	var restored_variables: Variant = s["variables"]
	if not restored_variables is Dictionary or restored_variables.size() != VARIABLE_NAMES.size():
		return false
	for name: String in VARIABLE_NAMES:
		if not restored_variables.has(name):
			return false
		var value: Variant = restored_variables[name]
		if not (value is int or value is float) or float(value) < 0.0 or float(value) > 1.0:
			return false
	if not is_equal_approx(float(restored_variables["time"]), clampf(float(restored_day) / 30.0, 0.0, 1.0)):
		return false

	var restored_sediment: Variant = s["sediment"]
	if not restored_sediment is Dictionary:
		return false
	for node_id: Variant in restored_sediment:
		var amount: Variant = restored_sediment[node_id]
		if not (amount is int or amount is float):
			return false
		if float(amount) < 0.0 or not is_equal_approx(float(amount), floorf(float(amount))):
			return false
		if int(amount) < sediment_of(str(node_id)):
			return false

	day = restored_day
	hour = restored_hour
	variables = restored_variables.duplicate(true)
	for node_id: Variant in restored_sediment:
		sediment[str(node_id)] = int(restored_sediment[node_id])
	_refresh_locks()
	return true


func day_index() -> int:
	return clampi(day, 0, 30)


func _scaled_noise(amount: int, factor: float) -> int:
	if amount <= 0:
		return 0
	return maxi(1, int(floor(float(amount) * factor)))


func _add_sediment(node_id: String, delta: int) -> void:
	if delta <= 0:
		return
	sediment[node_id] = sediment_of(node_id) + delta
	sediment_changed.emit(node_id, delta)


func _refresh_locks() -> void:
	locked_until.clear()
	if data == null:
		return

	# DataLayer 暴露 nodes() / node(id)；旧代码读 data.get("nodes") 恒为 null，
	# day_locked_after 从未生效。
	for record: Dictionary in data.nodes():
		var node_id: String = str(record.get("node_id", ""))
		if node_id.is_empty():
			continue
		var lock_day: Variant = record.get("day_locked_after")
		if lock_day is int or lock_day is float:
			locked_until[node_id] = int(lock_day)


func _node_record(node_id: String) -> Variant:
	if data == null:
		return null
	return data.node(node_id)