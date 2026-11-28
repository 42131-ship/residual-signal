extends SceneTree
## 开场过场门禁：新游戏领票 → 走廊播六拍 → 最后一拍自动向右走出厕所（灯全灭）→ 交还控制权。
## 覆盖：领票才播 / 六拍顺序 / 过场中锁输入 + 熄灯 / walkout 真的把角色往右推 /
##       播完解锁且记住"看过了" / 没票不再重播。
## 运行（要渲染，出图存 design/previews）：
##   .tools\Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/intro.gd -- INTRO

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const BEATS: Array[String] = ["bell", "overview", "toilet", "alarm", "zoom", "walkout"]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	RunState.current = null
	RunState.clear_saved()
	IntroFlag.reset()
	# ① 领了票：走廊必须开播
	IntroFlag.request()
	var corridor := SCENE.instantiate() as Node2D
	root.add_child(corridor)
	await process_frame
	await process_frame

	_check(bool(corridor._intro_active), "corridor must play the intro when the menu handed a ticket")
	_check(not IntroFlag.pending(), "the ticket must be consumed exactly once")
	var player: Player = corridor.get_node_or_null("Player") as Player
	_check(player != null, "player missing")
	if player == null:
		return _finish()
	_check(player._movement_locked, "movement must be locked while the intro plays")
	# 灯先亮着：熄灯是「走出厕所」那一拍才砸下来的（不然开场就是一片黑，什么都看不到）。
	_check(not bool(corridor._lights_out), "the intro must start with the corridor still lit")
	_check(bool(corridor._flashlight_on), "the flashlight starts on, and dies at the walkout")

	var intro = corridor._intro
	_check(intro != null, "intro node must be attached to the corridor")
	if intro == null:
		return _finish()
	var ids: Array[String] = []
	for row: Variant in intro.beats:
		ids.append(str((row as Dictionary).get("id", "")))
	_check(ids == BEATS, "intro beats must be %s, got %s" % [str(BEATS), str(ids)])

	# ② 逐拍推进 + 截图（门禁用 debug_advance 推时间，不等真实 27 秒）
	_check(str(intro.phase) == "bell", "intro must start on the bell, got %s" % str(intro.phase))
	await _capture("INTRO_bell")
	await _advance_to(intro, "overview")
	await _capture("INTRO_overview")
	await _advance_to(intro, "toilet")
	await _capture("INTRO_toilet")
	await _advance_to(intro, "alarm")
	await _advance_to(intro, "zoom")
	_check(not bool(corridor._lights_out), "the corridor must still be lit when the camera lands on the character")

	# ③ walkout：镜头跟着角色往右走出厕所，**这一下灯灭**，玩家不用操作
	await _advance_to(intro, "walkout")
	_check(bool(corridor._lights_out), "stepping out of the toilet must kill the lights")
	_check(not bool(corridor._flashlight_on), "the flashlight must die with the lights")
	var before_x: float = player.global_position.x
	intro.debug_advance(1.0)
	_check(player.global_position.x > before_x + 8.0,
		"walkout must push the character to the right (%.1f -> %.1f)" % [before_x, player.global_position.x])
	_check(player.facing_x > 0.0, "the character must face right while walking out")
	await _capture("INTRO_walkout")

	# ④ 走完 → 交还控制权 + 记住看过
	intro.debug_advance(6.0)
	_check(corridor._intro == null, "the intro must detach itself when finished")
	_check(not bool(corridor._intro_active), "corridor must accept input again after the intro")
	_check(not player._movement_locked, "movement must be unlocked after the intro")
	_check(bool(corridor._lights_out), "the lights stay out: turning the flashlight on is the player's first act")
	_check(IntroFlag.seen(), "the intro must be remembered as seen")

	# ⑤ 没票的走廊（继续 / 门禁）不许重播
	var second := SCENE.instantiate() as Node2D
	root.add_child(second)
	await process_frame
	await process_frame
	_check(second._intro == null, "a corridor without a ticket must not replay the intro")
	_finish()


func _advance_to(intro, phase_name: String) -> void:
	for _step in range(4000):
		if intro == null or not is_instance_valid(intro):
			return
		if str(intro.phase) == phase_name:
			await process_frame
			return
		intro.debug_advance(1.0 / 60.0)
	_check(false, "intro never reached beat %s" % phase_name)


func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		_check(false, "capture failed: " + label)
		return
	var path := "res://design/previews/%s.png" % label
	if rendered.save_png(ProjectSettings.globalize_path(path)) != OK:
		_check(false, "could not save " + path)
		return
	print("INTRO_SHOT %s" % path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("INTRO_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("INTRO_OK beats=%d ticket=once locked=during walkout=auto lights=out replay=no" % BEATS.size())
		quit(0)
		return
	print("INTRO_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
