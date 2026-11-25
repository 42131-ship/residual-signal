class_name Analytics
extends RefCounted
## 游戏代码只通过这个静态门面上报；Autoload 不在（脚本门禁/编辑器）就自动 no-op。

static func _service() -> TapDBService:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("TapDB") as TapDBService


static func track(event: String, props: Dictionary = {}) -> void:
	var service := _service()
	if service != null:
		service.track(event, props)


static func is_available() -> bool:
	var service := _service()
	return service != null and service.is_available()


static func has_consent() -> bool:
	var service := _service()
	return service != null and service.has_consent()


static func consent_decided() -> bool:
	var service := _service()
	return service != null and service.consent_decided()


static func should_prompt_consent() -> bool:
	var service := _service()
	return service != null and service.should_prompt_consent()


static func privacy_lines() -> Array:
	var service := _service()
	if service != null:
		return service.privacy_lines()
	return AnalyticsEvents.privacy_lines()


static func grant_consent() -> void:
	var service := _service()
	if service != null:
		service.grant_consent()


static func revoke_consent() -> void:
	var service := _service()
	if service != null:
		service.revoke_consent()
