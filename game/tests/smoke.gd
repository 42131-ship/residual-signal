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
	while world.day < 30:
		var current := axis_nodes[axis_index % axis_nodes.size()]
		var current_id := str(current.get("node_id", current.get("id", "")))

		world.spend_time(1)
		world.spend_time(2)
		world.add_noise(current_id, 2)
		var result := cards.pick_and_fire(current_id, world.day * 7 + 1)
		if result.get("fired", false) == true:
			fired += 1
		var l0_entries: Array = result.get("l0", [])
		l0_count += l0_entries.size()
		world.spend_time(8)
		axis_index += 1

	var sediment_max := 0
	for node_data in all_nodes:
		var node_id := str(node_data.get("node_id", node_data.get("id", "")))
		sediment_max = maxi(sediment_max, world.sediment_of(node_id))

	var before := world.var_of("supplies")
	var snap := world.snapshot()
	world.add_var("supplies", -0.1)
	if not world.restore(snap) or not is_equal_approx(world.var_of("supplies"), before):
		push_error("SMOKE_FAIL supplies 存读往返失败")
		print("SMOKE_FAIL supplies 存读往返失败")
		quit(1)
		return

	print("SMOKE_OK nodes=%d axis=%d rooms=%d day=%d fired=%d l0=%d sediment_max=%d roundtrip=ok" % [
		all_nodes.size(), axis_count, room_count, world.day, fired, l0_count, sediment_max
	])
	quit(0)
