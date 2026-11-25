class_name TapDBService
extends Node
## TapDB 客户端直连接口（Autoload 名：TapDB）。
##
## 为什么不是 SDK：TapDB 官方客户端 SDK 只有 Android/iOS/Unity/UE5，Godot PC 没有；
## 这里按「服务端接入」文档走 HTTP 事件接口，匿名 ID + 隐私同意 + 离线队列。
##
## 安全/合规：
##   - 只在导出构建、且用户同意隐私后才会初始化；编辑器 / 门禁 / headless 默认全静默
##   - 客户端只持有公开 ClientID；没有密钥
##   - 不上报路径、存档内容、坐标、用户名等 PII

const CONFIG_PATH := "res://config/analytics.json"
const CONSENT_PATH := "user://analytics_consent.json"
const PROFILE_PATH := "user://analytics_profile.json"
const QUEUE_PATH := "user://analytics_queue.json"
const MAX_QUEUE := 500
const MAX_RETRIES := 5
const BACKOFF_SEC := [5.0, 15.0, 60.0, 180.0, 300.0]
const MODE := "story"

## 门禁用：在 add_child 之前设置这些字段。
var test_mode := false
var test_consent := false
var test_config: Dictionary = {}
var test_queue_path := "user://analytics_test_queue.json"
var test_profile_path := "user://analytics_test_profile.json"
var test_consent_path := "user://analytics_test_consent.json"

var _config: Dictionary = {}
var _consent := false
var _available := false
var _active := false
var _initialized := false
var _ids: Dictionary = {}
var _queue: Array[Dictionary] = []
var _transport: TapDBTransport
var _sending := false
var _retries := 0
var _retry_timer: Timer
var _session_started_ms := 0
var _session_ended := false


func _ready() -> void:
	_config = test_config.duplicate(true) if test_mode else _load_config()
	_consent = test_consent if test_mode else _read_consent()
	_available = _compute_available()
	_setup_transport()
	_load_queue()
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_on_retry_timeout)
	add_child(_retry_timer)
	if _available and _consent:
		_activate()
	_initialized = true


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST and what != NOTIFICATION_EXIT_TREE:
		return
	if _active and not _session_ended:
		_track_session_end()
	_save_queue()


# ------------------------------------------------------------------ 对外接口


func is_available() -> bool:
	return _available


func has_consent() -> bool:
	return _consent


func consent_decided() -> bool:
	if test_mode:
		return true
	return FileAccess.file_exists(CONSENT_PATH)


func should_prompt_consent() -> bool:
	if test_mode or not _available:
		return false
	if OS.has_feature("editor"):
		return false
	return not consent_decided()


func privacy_lines() -> Array:
	return AnalyticsEvents.privacy_lines()


func track(event: String, props: Dictionary = {}) -> bool:
	if not _active or _transport == null:
		return false
	var result := AnalyticsEvents.build(event, props, _ids, _common_fields(), _config)
	if not bool(result.get("ok", false)):
		push_warning("ANALYTICS_EVENT_INVALID: " + str(result.get("error", "")))
		return false
	_enqueue(result["payload"])
	_save_queue()
	_flush()
	return true


func grant_consent() -> void:
	_consent = true
	if not test_mode:
		_write_consent(true)
	if _available and not _active:
		_activate()


func revoke_consent() -> void:
	_consent = false
	if not test_mode:
		_write_consent(false)
	_active = false
	_queue.clear()
	_save_queue()


func queue_size() -> int:
	return _queue.size()


func transport_calls() -> Array[Dictionary]:
	if _transport == null:
		var empty: Array[Dictionary] = []
		return empty
	return _transport.calls


func mock_transport() -> TapDBTransport:
	return _transport


func flush_now() -> void:
	_flush()


func ids() -> Dictionary:
	return _ids.duplicate()


func config() -> Dictionary:
	return _config.duplicate()


func common_fields() -> Dictionary:
	return _common_fields()


# ------------------------------------------------------------------ 初始化


func _compute_available() -> bool:
	if test_mode:
		return true
	var forced := OS.get_environment("RS_ANALYTICS")
	if forced == "0":
		return false
	if OS.has_feature("editor") or OS.has_feature("headless"):
		return forced == "1"
	if not bool(_config.get("enabled", true)):
		return false
	return not str(_config.get("client_id", "")).is_empty()


func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not raw is Dictionary:
		push_warning("ANALYTICS_CONFIG_INVALID: " + CONFIG_PATH)
		return {}
	var data: Dictionary = raw
	if str(data.get("schema", "")) != "analytics-config.v1":
		push_warning("ANALYTICS_CONFIG_SCHEMA: " + CONFIG_PATH)
		return {}
	var registry := AnalyticsEvents.registry()
	var tapdb: Dictionary = registry.get("tapdb", {})
	if str(data.get("endpoint", "")).is_empty():
		data["endpoint"] = str(tapdb.get("endpoint", "https://e.tapdb.net/v2/event"))
	return data


func _setup_transport() -> void:
	_transport = TapDBTransport.new()
	_transport.mock = test_mode
	_transport.endpoint = str(_config.get("endpoint", "https://e.tapdb.net/v2/event"))
	_transport.name = "Transport"
	_transport.completed.connect(_on_transport_completed)
	add_child(_transport)


func _activate() -> void:
	if _active or not _available:
		return
	_ids = _ensure_profile()
	if str(_ids.get("device_id", "")).is_empty() or str(_ids.get("user_id", "")).is_empty():
		push_warning("ANALYTICS_PROFILE_FAILED")
		return
	_active = true
	_session_started_ms = Time.get_ticks_msec()
	# TapDB 预置事件：每次启动报 device_login；单机匿名档案报一次 user_login。
	_enqueue_built("device_login", {})
	_enqueue_built("user_login", {})
	_enqueue_built("session_start", _session_start_props())
	_save_queue()
	_flush()


func _session_start_props() -> Dictionary:
	var run := RunState.current
	return {
		"mode": MODE,
		"day": int(run.day) if run != null else 0,
		"building": str(run.building) if run != null else "school",
	}


func _track_session_end() -> void:
	var duration := int(maxf(0.0, (Time.get_ticks_msec() - _session_started_ms) / 1000.0))
	var props := _session_start_props()
	props["duration_sec"] = duration
	var result := AnalyticsEvents.build("session_end", props, _ids, _common_fields(), _config)
	if bool(result.get("ok", false)):
		_enqueue(result["payload"])
		_session_ended = true


func _enqueue_built(event: String, props: Dictionary) -> void:
	var result := AnalyticsEvents.build(event, props, _ids, _common_fields(), _config)
	if not bool(result.get("ok", false)):
		push_warning("ANALYTICS_EVENT_INVALID: " + str(result.get("error", "")))
		return
	_enqueue(result["payload"])


func _common_fields() -> Dictionary:
	var registry := AnalyticsEvents.registry()
	var tapdb: Dictionary = registry.get("tapdb", {})
	var size := DisplayServer.window_get_size()
	if size.x <= 0 or size.y <= 0:
		size = Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 384)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", 216)))
	return {
		"os": str(tapdb.get("os", "Windows")),
		"device_model": "PC",
		"os_version": OS.get_version(),
		"width": int(size.x),
		"height": int(size.y),
		"network": str(tapdb.get("network_unknown", "3")),
		"channel": str(_config.get("channel", "dev")),
		"app_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"sdk_version": str(tapdb.get("sdk_version", "tapdb-http-1.0")),
	}


# ------------------------------------------------------------------ 队列 / 发送


func _enqueue(payload: Dictionary) -> void:
	_queue.append(payload)
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()


func _flush() -> void:
	if not _active or _sending or _queue.is_empty() or _transport == null:
		return
	_sending = true
	_transport.send(_queue[0])


func _on_transport_completed(ok: bool, code: int, body: String) -> void:
	_sending = false
	if ok:
		if not _queue.is_empty():
			_queue.pop_front()
		_retries = 0
		_save_queue()
		call_deferred("_flush")
		return
	_retries += 1
	push_warning("ANALYTICS_SEND_FAILED code=%d retry=%d body=%s" % [code, _retries, body.substr(0, 120)])
	if _retries > MAX_RETRIES:
		if not _queue.is_empty():
			_queue.pop_front()
		_retries = 0
		_save_queue()
		call_deferred("_flush")
		return
	_save_queue()
	_retry_timer.start(float(BACKOFF_SEC[mini(_retries - 1, BACKOFF_SEC.size() - 1)]))


func _on_retry_timeout() -> void:
	_flush()


func _load_queue() -> void:
	var path := test_queue_path if test_mode else QUEUE_PATH
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Array:
		return
	for item: Variant in raw:
		if item is Dictionary:
			_queue.append(item)
			if _queue.size() >= MAX_QUEUE:
				break


func _save_queue() -> void:
	var path := test_queue_path if test_mode else QUEUE_PATH
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_queue))


# ------------------------------------------------------------------ 档案 / 同意


func _ensure_profile() -> Dictionary:
	var path := test_profile_path if test_mode else PROFILE_PATH
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if raw is Dictionary:
			data = raw
	if str(data.get("device_id", "")).is_empty():
		data["device_id"] = AnalyticsEvents.new_id()
	if str(data.get("user_id", "")).is_empty():
		data["user_id"] = AnalyticsEvents.new_id()
	if not data.has("created_at"):
		data["created_at"] = int(Time.get_unix_time_from_system())
	data["client_id"] = str(_config.get("client_id", ""))
	if not test_mode:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(data))
	return data


func _read_consent() -> bool:
	if not FileAccess.file_exists(CONSENT_PATH):
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONSENT_PATH))
	if not raw is Dictionary:
		return false
	return bool((raw as Dictionary).get("granted", false))


func _write_consent(granted: bool) -> void:
	var file := FileAccess.open(CONSENT_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema": "analytics-consent.v1",
		"granted": granted,
		"notice_version": int((AnalyticsEvents.registry().get("privacy", {}) as Dictionary).get("notice_version", 1)),
		"decided_at": int(Time.get_unix_time_from_system()),
	}))
