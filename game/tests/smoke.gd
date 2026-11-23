extends SceneTree

func _initialize() -> void:
	var data := DataLayer.new()
	var world := WorldState.new()
	var cards := CardEngine.new()
	var mem := Memory.new()

	if not data.load_all():
		push_error("SMOKE_FAIL data.load_all() 失败")
		print("SMOKE_FAIL data.load_all() 失败")
		quit(1)
		return

	if not world.init_from(data):
		push_error("SMOKE_FAIL world.init_from() 失败")
		print("SMOKE_FAIL world.init_from() 失败")
		quit(1)
		return
	if not cards.init_from(data, world):
		push_error("SMOKE_FAIL cards.init_from() 失败")
		print("SMOKE_FAIL cards.init_from() 失败")
		quit(1)
		return
	if not mem.init_from(data, world):
		push_error("SMOKE_FAIL mem.init_from() 失败")
		print("SMOKE_FAIL mem.init_from() 失败")
		quit(1)
		return
	if not mem.load_npcs():
		push_error("SMOKE_FAIL mem.load_npcs() 失败")
		print("SMOKE_FAIL mem.load_npcs() 失败")
		quit(1)
		return

	var all_nodes: Array[Dictionary] = data.nodes()
	var axis_nodes: Array[Dictionary] = data.axis_nodes()
	var room_nodes: Array[Dictionary] = data.room_nodes()
	var axis_count := 0
	var room_count := 0

	for node_data in all_nodes:
		var node_id := str(node_data.get("node_id", node_data.get("id", "")))
		var node_2d := Node2D.new()
		node_2d.name = node_id
		node_2d.position = Vector2(
			float(node_data.get("axis_x", 0.0)) * 384.0,
			float(node_data.get("depth_layer", 0.0)) * 216.0
		)
		get_root().add_child(node_2d)

		if bool(node_data.get("is_axis", false)) or axis_nodes.any(func(item: Dictionary) -> bool: return str(item.get("node_id", item.get("id", ""))) == node_id):
			axis_count += 1
		if bool(node_data.get("is_room", false)) or room_nodes.any(func(item: Dictionary) -> bool: return str(item.get("node_id", item.get("id", ""))) == node_id):
			room_count += 1

	if all_nodes.is_empty() or axis_nodes.is_empty():
		push_error("SMOKE_FAIL 节点或主轴为空")
		print("SMOKE_FAIL 节点或主轴为空")
		quit(1)
		return

	var fired := 0
	var l0_count := 0
	var axis_index := 0
	var changed_vars := 0
	while world.day < 30:
		var current := axis_nodes[axis_index % axis_nodes.size()]
		var current_id := str(current.get("node_id", current.get("id", "")))

		world.spend_time(1)
		world.spend_time(2)
		world.add_noise(current_id, 2)
		var before_vars: Dictionary = {}
		for variable_name: String in WorldState.VARIABLE_NAMES:
			before_vars[variable_name] = world.var_of(variable_name)
		var result := cards.pick_and_fire(current_id, world.day * 7 + 1)
		for variable_name: String in WorldState.VARIABLE_NAMES:
			if variable_name == "time":
				continue
			if not is_equal_approx(world.var_of(variable_name), float(before_vars[variable_name])):
				changed_vars += 1
		if result.get("fired", false) == true:
			fired += 1
		var l0_entries: Array = result.get("l0", [])
		l0_count += l0_entries.size()
		world.spend_time(8)
		axis_index += 1

	# 卡效果必须真的落地：effects[].vars 若读错键，这里会一直是 0（旧版读过 add_vars）。
	if changed_vars == 0:
		push_error("SMOKE_FAIL 卡效果没有改动任何世界变量（effects[].vars 未被应用）")
		print("SMOKE_FAIL 卡效果没有改动任何世界变量")
		quit(1)
		return

	# 夜晚噪声倍率：mode_profile.story.night_multiplier = 1.5，夜间应比白天大。
	var day_world := WorldState.new()
	day_world.init_from(data)
	var day_result: Dictionary = day_world.add_noise("school_corridor_b", 10, false)
	var day_self := int(day_result.get("self", 0))
	var night_world := WorldState.new()
	night_world.init_from(data)
	var night_result: Dictionary = night_world.add_noise("school_corridor_b", 10, true)
	var night_self := int(night_result.get("self", 0))
	if night_self <= day_self:
		push_error("SMOKE_FAIL 夜间噪声倍率未生效 day=%d night=%d" % [day_self, night_self])
		print("SMOKE_FAIL 夜间噪声倍率未生效 day=%d night=%d" % [day_self, night_self])
		quit(1)
		return

	# 锁门：nodes.json 里 school_b1_garage.day_locked_after = 14（Day 14 可进，Day 15 起不可进）。
	var lock_world := WorldState.new()
	lock_world.init_from(data)
	if not lock_world.can_enter("school_b1_garage"):
		push_error("SMOKE_FAIL Day 0 应可进入 school_b1_garage")
		print("SMOKE_FAIL Day 0 应可进入 school_b1_garage")
		quit(1)
		return
	lock_world.spend_time(14 * 24)
	if not lock_world.can_enter("school_b1_garage"):
		push_error("SMOKE_FAIL Day 14 应可进入 school_b1_garage")
		print("SMOKE_FAIL Day 14 应可进入 school_b1_garage")
		quit(1)
		return
	lock_world.spend_time(24)
	if lock_world.can_enter("school_b1_garage"):
		push_error("SMOKE_FAIL Day 15 起不应可进入 school_b1_garage")
		print("SMOKE_FAIL Day 15 起不应可进入 school_b1_garage")
		quit(1)
		return

	var sediment_max := 0
	for node_data in all_nodes:
		var node_id := str(node_data.get("node_id", node_data.get("id", "")))
		sediment_max = maxi(sediment_max, world.sediment_of(node_id))

	# 存读往返：先把 supplies 设成非零，否则 -0.1 会被夹回 0，断言空转。
	world.set_var("supplies", 0.5)
	var before := world.var_of("supplies")
	var snap := world.snapshot()
	world.add_var("supplies", -0.1)
	if is_equal_approx(world.var_of("supplies"), before):
		push_error("SMOKE_FAIL 存读往返前置：add_var 没有生效")
		print("SMOKE_FAIL 存读往返前置：add_var 没有生效")
		quit(1)
		return
	if not world.restore(snap) or not is_equal_approx(world.var_of("supplies"), before):
		push_error("SMOKE_FAIL supplies 存读往返失败")
		print("SMOKE_FAIL supplies 存读往返失败")
		quit(1)
		return

	print("SMOKE_OK nodes=%d axis=%d rooms=%d day=%d fired=%d l0=%d sediment_max=%d changed=%d night=%d/%d lock=ok roundtrip=ok" % [
		all_nodes.size(), axis_count, room_count, world.day, fired, l0_count, sediment_max,
		changed_vars, day_self, night_self
	])
	quit(0)
