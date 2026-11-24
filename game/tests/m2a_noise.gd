extends SceneTree
## M2a-2 门禁：噪声只有一条出口 —— 走廊报底值，世界层缩放进沉积并传染邻接。
## 运行（要渲染）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/m2a_noise.gd -- NOISE

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _corridor: Node2D
var _prefix := "NOISE"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("NOISE"):
			_prefix = argument
	RunState.current = null
	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	await process_frame
	await process_frame

	var actor := _corridor.get_node_or_null("Player") as Player
	var state: WorldState = _corridor._state
	_check(actor != null, "player missing")
	_check(state != null, "world_state must be online")
	if actor == null or state == null:
		return _finish()

	# ① 三段映射：走廊 x -> 学校主轴三节
	var cases := [[64.0, "school_corridor_a"], [300.0, "school_corridor_b"], [560.0, "school_corridor_c"]]
	for pair in cases:
		actor.global_position = Vector2(float(pair[0]), 128.0)
		await process_frame
		var got: String = _corridor._current_room_node()
		_check(got == str(pair[1]), "x=%.0f should map to %s, got %s" % [float(pair[0]), str(pair[1]), got])

	# ② 一次噪声：走廊计数与世界层沉积必须同步，且邻接节点被传染
	actor.global_position = Vector2(64.0, 128.0)
	await process_frame
	var noise_before: int = _corridor._noise
	var self_before: int = state.sediment_of("school_corridor_a")
	var neighbour_before: int = state.sediment_of("school_corridor_b")
	_corridor._emit_noise(4)
	var noise_after: int = _corridor._noise
	var self_after: int = state.sediment_of("school_corridor_a")
	var neighbour_after: int = state.sediment_of("school_corridor_b")
	var delta_self := self_after - self_before
	var delta_noise := noise_after - noise_before
	_check(delta_self > 0, "noise must reach world_state sediment, delta=%d" % delta_self)
	_check(delta_noise == delta_self,
		"corridor counter must equal the world's scaled delta (counter +%d vs world +%d)" % [delta_noise, delta_self])
	_check(neighbour_after > neighbour_before,
		"neighbour node must be infected too (before %d, after %d)" % [neighbour_before, neighbour_after])

	# ③ 在别的房间出声，沉积要记到那一节，不许串到 A
	var c_before: int = state.sediment_of("school_corridor_c")
	actor.global_position = Vector2(560.0, 128.0)
	await process_frame
	_corridor._emit_noise(3)
	_check(state.sediment_of("school_corridor_c") > c_before, "noise in room C must land on corridor_c")

	# ④ 零/负噪声什么都不改
	var guard_noise: int = _corridor._noise
	_corridor._emit_noise(0)
	_corridor._emit_noise(-5)
	_check(_corridor._noise == guard_noise, "zero or negative noise must be ignored")

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("NOISE_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("M2A_NOISE_OK rooms=a/b/c self=matched neighbour=infected guard=0")
		quit(0)
		return
	print("M2A_NOISE_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
