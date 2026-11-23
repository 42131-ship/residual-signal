class_name TravelService
extends RefCounted
## 出行层：五栋楼 + 路线成本 + 一天一次外出 + 天黑未归加风险。
##
## 数据在 data/travel/routes.json。这里只做「能不能去、去一趟多贵、夜里多险」，
## 不管场景切换（那是 M1 的下一步）。

const DATA_PATH := "res://data/travel/routes.json"

var _buildings: Dictionary = {}
var _order: Array[String] = []
var _routes: Array[Dictionary] = []
var _day: Dictionary = {}
var _load_error := ""


func load_all() -> bool:
	_buildings.clear()
	_order.clear()
	_routes.clear()
	_day.clear()
	_load_error = ""
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not raw is Dictionary:
		_load_error = "TRAVEL_DATA_UNREADABLE"
		return false
	var data: Dictionary = raw
	if str(data.get("schema", "")) != "travel.v1":
		_load_error = "TRAVEL_SCHEMA_INVALID"
		return false
	var buildings: Variant = data.get("buildings")
	if not buildings is Array or (buildings as Array).is_empty():
		_load_error = "TRAVEL_BUILDINGS_EMPTY"
		return false
	var safehouses := 0
	for value: Variant in buildings:
		if not value is Dictionary:
			_load_error = "TRAVEL_BUILDING_INVALID"
			return false
		var record: Dictionary = value
		var id := str(record.get("id", ""))
		if id.is_empty() or _buildings.has(id):
			_load_error = "TRAVEL_BUILDING_ID_INVALID: " + id
			return false
		if bool(record.get("safehouse", false)):
			safehouses += 1
		_buildings[id] = record
		_order.append(id)
	if safehouses != 1:
		_load_error = "TRAVEL_SAFEHOUSE_COUNT: %d" % safehouses
		return false

	var routes: Variant = data.get("routes")
	if not routes is Array:
		_load_error = "TRAVEL_ROUTES_INVALID"
		return false
	for value: Variant in routes:
		if not value is Dictionary:
			_load_error = "TRAVEL_ROUTE_INVALID"
			return false
		var route: Dictionary = value
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if not _buildings.has(a) or not _buildings.has(b) or a == b:
			_load_error = "TRAVEL_ROUTE_ENDPOINT: %s<->%s" % [a, b]
			return false
		if int(route.get("cost", 0)) < 1 or int(route.get("fuel", 0)) < 0 or int(route.get("risk", 0)) < 1:
			_load_error = "TRAVEL_ROUTE_NUMBERS: %s<->%s" % [a, b]
			return false
		_routes.append({"a": a, "b": b, "cost": int(route["cost"]), "fuel": int(route["fuel"]), "risk": int(route["risk"])})
		# 无向：两个方向都要能查到
		_routes.append({"a": b, "b": a, "cost": int(route["cost"]), "fuel": int(route["fuel"]), "risk": int(route["risk"])})

	var day: Variant = data.get("day")
	if not day is Dictionary:
		_load_error = "TRAVEL_DAY_INVALID"
		return false
	_day = day
	if int(_day.get("actions_per_day", 0)) < 1:
		_load_error = "TRAVEL_ACTIONS_INVALID"
		return false
	return true


func load_error() -> String:
	return _load_error


func building_ids() -> Array[String]:
	return _order.duplicate()


func has_building(id: String) -> bool:
	return _buildings.has(id)


func is_safehouse(id: String) -> bool:
	return bool((_buildings.get(id, {}) as Dictionary).get("safehouse", false))


func label_of(id: String) -> String:
	return str((_buildings.get(id, {}) as Dictionary).get("label", id))


func neighbors(id: String) -> Array[String]:
	var out: Array[String] = []
	for route: Dictionary in _routes:
		if str(route["a"]) == id:
			out.append(str(route["b"]))
	out.sort()
	return out


## 返回 {cost, fuel, risk}；没有直达路线时返回空字典。
func route(from: String, to: String) -> Dictionary:
	for route: Dictionary in _routes:
		if str(route["a"]) == from and str(route["b"]) == to:
			return {"cost": int(route["cost"]), "fuel": int(route["fuel"]), "risk": int(route["risk"])}
	return {}


func actions_per_day() -> int:
	return maxi(1, int(_day.get("actions_per_day", 1)))


func night_hour() -> int:
	return int(_day.get("night_hour", 18))


## 夜里的风险按 night_multiplier 放大后向上取整（1 → 2，2 → 4）。
func risk_of(from: String, to: String, hour: int) -> int:
	var base := int(route(from, to).get("risk", 0))
	if base <= 0:
		return 0
	if hour >= night_hour():
		return int(ceil(base * float(_day.get("night_multiplier", 1.0))))
	return base


## context: {"fuel": int, "actions_left": int, "hour": int}
func can_travel(from: String, to: String, context: Dictionary) -> Dictionary:
	if not _buildings.has(from) or not _buildings.has(to):
		return {"ok": false, "reason": "unknown_building"}
	if from == to:
		return {"ok": false, "reason": "same_building"}
	var info := route(from, to)
	if info.is_empty():
		return {"ok": false, "reason": "no_route"}
	if int(context.get("actions_left", 0)) < 1:
		return {"ok": false, "reason": "no_action_left"}
	if int(context.get("fuel", 0)) < int(info["fuel"]):
		return {"ok": false, "reason": "not_enough_fuel"}
	return {
		"ok": true,
		"reason": "",
		"cost": int(info["cost"]),
		"fuel": int(info["fuel"]),
		"risk": risk_of(from, to, int(context.get("hour", 12))),
	}
