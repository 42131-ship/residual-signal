extends SceneTree
## TapDB 门禁（不联网、不渲染）：
##   - 事件注册表可加载、事件/属性/类型校验生效
##   - 报文包含 TapDB 必需字段（client_id/device_id/user_id/type/name/os/timestamp/event_uuid）
##   - 同意前零上报；同意后预置事件顺序正确
##   - 发送失败保留队列并重发同一条（event_uuid 不变），成功后出队
##   - 撤销同意清空队列
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##   --script res://game/tests/analytics.gd -- ANALYTICS

const QUEUE_PATH := "user://analytics_gate_queue.json"
const PROFILE_PATH := "user://analytics_gate_profile.json"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_check(AnalyticsEvents.is_loaded(), "analytics event registry must load")
	_check(AnalyticsEvents.event_names().size() >= 12,
		"registry must declare the v1 event set, got %d" % AnalyticsEvents.event_names().size())
	_check(AnalyticsEvents.privacy_lines().size() >= 2, "privacy notice lines missing")

	var ids := {"client_id": "test-client", "device_id": "device-1", "user_id": "user-1"}
	var common := {
		"os": "Windows", "device_model": "PC", "os_version": "test",
		"width": 1920, "height": 1080, "network": "3", "channel": "ci",
		"app_version": "0.1.0", "sdk_version": "tapdb-http-1.0",
	}
	var built := AnalyticsEvents.build("run_start", {"mode": "story", "from_save": 0, "day": 0}, ids, common, {})
	_check(bool(built.get("ok", false)), "run_start payload must build: " + str(built.get("error", "")))
	if bool(built.get("ok", false)):
		var payload: Dictionary = built["payload"]
		var props: Dictionary = payload["properties"]
		_check(payload["client_id"] == "test-client" and payload["type"] == "track" and payload["name"] == "run_start",
			"payload system fields wrong")
		_check(props["os"] == "Windows", "os must be Windows")
		_check(int(props["timestamp"]) > 1_600_000_000_000, "timestamp must be milliseconds")
		_check(str(props["event_uuid"]).length() == 36, "event_uuid must be a uuid")
		_check(props.has("#mode") and props["#mode"] == "story", "custom props must use the registered prefix")

	var bad_event := AnalyticsEvents.build("nope", {}, ids, common, {})
	_check(not bool(bad_event.get("ok", true)), "unknown events must be rejected")
	var bad_prop := AnalyticsEvents.build("run_start", {"mode": "story", "from_save": 0, "day": 0, "save": "x"}, ids, common, {})
	_check(not bool(bad_prop.get("ok", true)), "forbidden/undeclared props must be rejected")
	var bad_type := AnalyticsEvents.build("run_start", {"mode": 1, "from_save": 0, "day": 0}, ids, common, {})
	_check(not bool(bad_type.get("ok", true)), "wrong property types must be rejected")

	var service := TapDBService.new()
	service.test_mode = true
	service.test_config = {"client_id": "gate-client", "endpoint": "https://example.invalid/v2/event", "channel": "ci"}
	service.test_consent = false
	service.test_queue_path = QUEUE_PATH
	service.test_profile_path = PROFILE_PATH
	service.test_consent_path = "user://analytics_gate_consent.json"
	root.add_child(service)
	await process_frame
	await process_frame
	_check(service.is_available(), "test service must be available")
	_check(not service.has_consent(), "consent must start off in the gate")
	_check(not service.track("run_start", {"mode": "story", "from_save": 0, "day": 0}),
		"tracking before consent must be refused")
	_check(service.queue_size() == 0 and service.transport_calls().is_empty(),
		"tracking before consent must not send anything")

	service.grant_consent()
	await _drain(service, 12)
	var calls := service.transport_calls()
	_check(calls.size() >= 3, "consent activation must send device_login/user_login/session_start, got %d" % calls.size())
	var names: Array[String] = []
	for payload: Dictionary in calls:
		names.append(str(payload.get("name", "")))
	_check(names.has("device_login"), "device_login missing: %s" % str(names))
	_check(names.has("user_login"), "user_login missing: %s" % str(names))
	_check(names.has("session_start"), "session_start missing: %s" % str(names))
	_check(service.queue_size() == 0, "queue must drain after mock success")

	_check(service.track("run_start", {"mode": "story", "from_save": 0, "day": 0}),
		"tracking after consent must be accepted")
	await _drain(service, 4)
	_check(_last_named(service, "run_start") != null, "run_start must reach the transport")

	# 失败保留队列，重发同一条（uuid 稳定），再成功后出队。
	service.mock_transport().mock_results.append({"ok": false, "code": 500, "body": "boom"})
	service.mock_transport().mock_results.append({"ok": true, "code": 200, "body": ""})
	_check(service.track("endings_view", {"unlocked": 0}), "endings_view must be accepted")
	await process_frame
	await process_frame
	var failed := _named(service, "endings_view")
	_check(failed.size() >= 1, "failed event must be attempted")
	var first_uuid := str((failed[0]["properties"] as Dictionary).get("event_uuid", ""))
	service.flush_now()
	await process_frame
	await process_frame
	var attempts := _named(service, "endings_view")
	_check(attempts.size() >= 2, "failed event must be retried")
	if attempts.size() >= 2:
		var second_uuid := str((attempts[1]["properties"] as Dictionary).get("event_uuid", ""))
		_check(first_uuid == second_uuid, "retries must keep the same event_uuid")
	_check(service.queue_size() == 0, "successful retry must clear the queue")

	service.revoke_consent()
	_check(not service.has_consent(), "revoke must clear consent")
	_check(service.queue_size() == 0, "revoke must clear pending queue")

	service.queue_free()
	await process_frame
	_cleanup()
	if _failures.is_empty():
		print("ANALYTICS_OK registry=%d consent=gated retry=stable uuid=%s privacy=ok" % [
			AnalyticsEvents.event_names().size(), "yes"])
		quit(0)
		return
	print("ANALYTICS_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)


func _drain(service: TapDBService, frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _named(service: TapDBService, event: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for payload: Dictionary in service.transport_calls():
		if str(payload.get("name", "")) == event:
			out.append(payload)
	return out


func _last_named(service: TapDBService, event: String) -> Dictionary:
	var found := _named(service, event)
	return found[found.size() - 1] if not found.is_empty() else {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("ANALYTICS_FAIL " + message)


func _cleanup() -> void:
	for path: String in [QUEUE_PATH, PROFILE_PATH, "user://analytics_gate_consent.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
