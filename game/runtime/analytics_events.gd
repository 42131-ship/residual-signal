class_name AnalyticsEvents
extends RefCounted
## TapDB 事件注册表 + 报文构造（纯函数，可离线门禁）。
##
## 规则来自 TapDB 数据规范：
##   - 顶层系统字段：client_id / device_id / user_id / type / name
##   - properties 内系统属性：os / timestamp(ms) / event_uuid ...
##   - 自定义事件、自定义属性必须先在后端登记，类型必须完全一致
##   - 可空参数不能省略；本实现要求调用方把所有登记属性都填上（空串/0 均可）
##   - 不上报路径、存档内容、坐标、用户名等 PII

const REGISTRY_PATH := "res://data/analytics/events.json"

static var _registry: Dictionary = {}


static func registry() -> Dictionary:
	if _registry.is_empty():
		_registry = _load_registry()
	return _registry


static func is_loaded() -> bool:
	return not registry().is_empty()


static func privacy_lines() -> Array:
	return registry().get("privacy", {}).get("lines", [])


static func event_names() -> Array:
	return (registry().get("events", {}) as Dictionary).keys()


static func load_error() -> String:
	if registry().is_empty():
		return "analytics event registry unavailable"
	return ""


static func _load_registry() -> Dictionary:
	if not FileAccess.file_exists(REGISTRY_PATH):
		push_error("ANALYTICS_REGISTRY_MISSING: " + REGISTRY_PATH)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	if not raw is Dictionary:
		push_error("ANALYTICS_REGISTRY_INVALID")
		return {}
	var data: Dictionary = raw
	if str(data.get("schema", "")) != "analytics-events.v1":
		push_error("ANALYTICS_REGISTRY_SCHEMA: " + str(data.get("schema", "")))
		return {}
	return data


## 构造一条 TapDB 事件报文。返回 {"ok", "error", "payload"}，门禁据此断言。
static func build(event: String, props: Dictionary, ids: Dictionary, common: Dictionary, config: Dictionary = {}) -> Dictionary:
	var reg := registry()
	if reg.is_empty():
		return {"ok": false, "error": "registry_unavailable"}
	var events: Dictionary = reg.get("events", {})
	if not events.has(event):
		return {"ok": false, "error": "unknown_event:" + event}
	var spec: Dictionary = events[event]
	var declared: Dictionary = spec.get("props", {})
	var got := props.duplicate()
	for key: String in got.keys():
		if not declared.has(key):
			return {"ok": false, "error": "undeclared_property:%s.%s" % [event, key]}
	for key: String in declared.keys():
		if not got.has(key):
			return {"ok": false, "error": "missing_property:%s.%s" % [event, key]}
		var expected := str(declared[key])
		if expected == "number" and not got[key] is int and not got[key] is float:
			return {"ok": false, "error": "wrong_type:%s.%s expected number" % [event, key]}
		if expected == "string" and not got[key] is String:
			return {"ok": false, "error": "wrong_type:%s.%s expected string" % [event, key]}
	for forbidden: String in reg.get("forbidden_keys", []):
		if got.has(forbidden):
			return {"ok": false, "error": "forbidden_property:" + forbidden}

	var properties: Dictionary = common.duplicate(true)
	properties["timestamp"] = int(Time.get_unix_time_from_system() * 1000.0)
	properties["event_uuid"] = _uuid()
	var prop_prefix := str(config.get("custom_property_prefix", reg.get("custom_property_prefix", "#")))
	var event_prefix := str(config.get("custom_event_prefix", reg.get("custom_event_prefix", "")))
	for key: String in got.keys():
		properties[prop_prefix + key] = got[key]

	var payload := {
		"client_id": str(ids.get("client_id", "")),
		"device_id": str(ids.get("device_id", "")),
		"user_id": str(ids.get("user_id", "")),
		"type": "track",
		"name": event_prefix + event,
		"properties": properties,
	}
	if payload["client_id"].is_empty() or payload["device_id"].is_empty() or payload["user_id"].is_empty():
		return {"ok": false, "error": "missing_ids"}
	return {"ok": true, "error": "", "payload": payload}


static func new_id() -> String:
	return _uuid()


static func _uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := ""
	for i in range(16):
		hex += "%02x" % bytes[i]
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
