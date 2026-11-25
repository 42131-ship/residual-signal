class_name TapDBTransport
extends Node
## TapDB 传输层：POST JSON 到事件接口；测试时用 mock，绝不联网。
## 服务端接入文档：POST https://e.tapdb.net/v2/event，200 视为接收成功。

signal completed(ok: bool, code: int, body: String)

var endpoint := "https://e.tapdb.net/v2/event"
var timeout_sec := 10.0
var mock := false
var calls: Array[Dictionary] = []
var mock_results: Array[Dictionary] = []

var _http: HTTPRequest


func _ready() -> void:
	if mock:
		return
	_http = HTTPRequest.new()
	_http.timeout = timeout_sec
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)


func send(payload: Dictionary) -> void:
	calls.append(payload.duplicate(true))
	if mock:
		var result := {"ok": true, "code": 200, "body": ""}
		if not mock_results.is_empty():
			result = mock_results.pop_front()
		call_deferred("_emit", bool(result.get("ok", false)), int(result.get("code", 0)), str(result.get("body", "")))
		return
	if _http == null:
		call_deferred("_emit", false, 0, "transport_not_ready")
		return
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := _http.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		call_deferred("_emit", false, 0, "request_error:%d" % error)


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	_emit(ok, response_code, body.get_string_from_utf8())


func _emit(ok: bool, code: int, body: String) -> void:
	completed.emit(ok, code, body)
