extends SceneTree
## W1 门禁：稳定实体 ID（EntityRegistry）——门 / 容器 / 道具 / 拓扑 / 敌人。
## 运行（要渲染：实例化走廊场景）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/entity_registry.gd -- ENTITY
## 通过输出一行 `ENTITY_OK ...`。
##
## 验四件事：
## ① 每个门/容器/道具/节点都有 `kind:template:local` 形式的 ID；
## ② 同一场景重载两次，ID 集合一致（稳定）；
## ③ 把 `_doors` 数组顺序打乱，ID 仍跟着实体走（说明身份不依赖下标）；
## ④ 门 ID 不含纯数字段（不退回 tile_x / 下标当键）。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	RunState.current = null
	RunState.clear_saved()

	var first: Node2D = SCENE.instantiate() as Node2D
	root.add_child(first)
	await process_frame
	await process_frame
	first.disarm_enemies()

	var template := str(first._current_building)
	_check(template == "school", "a fresh run must be school, got %s" % template)

	# ① 门
	var doors: Array = first._doors
	_check(doors.size() == 2, "expected 2 doors, got %d" % doors.size())
	var door_ids: Array[String] = []
	for door: Dictionary in doors:
		var id := str(door.get("id", ""))
		door_ids.append(id)
		_check(EntityRegistry.is_valid(id), "door id must be valid, got '%s'" % id)
		var parsed := EntityRegistry.parse(id)
		_check(str(parsed.get("kind", "")) == EntityRegistry.KIND_DOOR, "door kind wrong: '%s'" % id)
		_check(str(parsed.get("template", "")) == template, "door template wrong: '%s'" % id)
		# ④ 身份必须是「哪两个区之间的门」，不是 12 / 26 / 0 / 1
		_check(not str(parsed.get("local", "")).is_valid_int(), "door local must not be numeric: '%s'" % id)
	var expected_doors: Array[String] = ["door:%s:a_b" % template, "door:%s:b_c" % template]
	_check(door_ids == expected_doors, "unexpected door ids: %s" % str(door_ids))
	_check(EntityRegistry.all_unique(door_ids), "door ids must be unique: %s" % str(door_ids))

	# ③ 打乱下标：ID 跟着实体走
	doors.reverse()
	_check(str(doors[0].get("id", "")) == expected_doors[1], "door ids must follow the entity, not the index")
	doors.reverse()

	# 容器（自带 id，data/loot/containers.json 是唯一真源）
	var containers_doc: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/loot/containers.json"))
	_check(containers_doc is Dictionary, "containers.json must parse")
	var containers: Array = (containers_doc as Dictionary).get("containers", []) if containers_doc is Dictionary else []
	_check(containers.size() == 3, "expected 3 containers, got %d" % containers.size())
	var container_ids: Array[String] = []
	for container: Dictionary in containers:
		var cid := EntityRegistry.container_id(template, container)
		container_ids.append(cid)
		_check(EntityRegistry.is_valid(cid), "container id must be valid, got '%s'" % cid)
	_check(EntityRegistry.all_unique(container_ids), "container ids must be unique")

	# 道具 / 检查记录（15 条）
	var inspections: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/prop_inspections.json"))
	var records: Array = (inspections as Dictionary).get("records", []) if inspections is Dictionary else []
	_check(records.size() == 15, "expected 15 prop records, got %d" % records.size())
	var prop_ids: Array[String] = []
	for record: Dictionary in records:
		var pid := EntityRegistry.prop_id(template, record)
		prop_ids.append(pid)
		_check(EntityRegistry.is_valid(pid), "prop id must be valid, got '%s'" % pid)
	_check(EntityRegistry.all_unique(prop_ids), "prop ids must be unique")

	# 拓扑节点（16 个，node_id 去掉模板前缀后进 ID）
	var nodes_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/nodes.json"))
	var nodes: Array = (nodes_doc as Dictionary).get("nodes", []) if nodes_doc is Dictionary else []
	_check(nodes.size() == 16, "expected 16 topology nodes, got %d" % nodes.size())
	var node_ids: Array[String] = []
	for node: Dictionary in nodes:
		var nid := EntityRegistry.node_id(template, node)
		node_ids.append(nid)
		_check(EntityRegistry.is_valid(nid), "node id must be valid, got '%s'" % nid)
	_check(EntityRegistry.all_unique(node_ids), "node ids must be unique")
	_check(node_ids.has("node:%s:corridor_a" % template), "node id must strip the template prefix")

	# 敌人槽位按房间
	var enemy_ids: Array[String] = []
	for room: int in 3:
		var eid := EntityRegistry.enemy_id(template, room)
		enemy_ids.append(eid)
		_check(EntityRegistry.is_valid(eid), "enemy id must be valid, got '%s'" % eid)
	_check(enemy_ids == ["enemy:%s:a" % template, "enemy:%s:b" % template, "enemy:%s:c" % template],
		"unexpected enemy ids: %s" % str(enemy_ids))

	# 跨种类不重名
	var all_ids: Array[String] = []
	all_ids.append_array(door_ids)
	all_ids.append_array(container_ids)
	all_ids.append_array(prop_ids)
	all_ids.append_array(node_ids)
	all_ids.append_array(enemy_ids)
	_check(EntityRegistry.all_unique(all_ids), "ids must be unique across kinds")

	# 结构校验：两段/未知 kind/空段都要判无效
	_check(not EntityRegistry.is_valid("door:" + template), "two-part id must be invalid")
	_check(not EntityRegistry.is_valid("weird:" + template + ":x"), "unknown kind must be invalid")
	_check(not EntityRegistry.is_valid("door:" + template + ":"), "empty local must be invalid")

	# ② 重载一次：ID 集合必须完全一致
	first.queue_free()
	await process_frame
	var second: Node2D = SCENE.instantiate() as Node2D
	root.add_child(second)
	await process_frame
	await process_frame
	second.disarm_enemies()
	var reload_ids: Array[String] = []
	for door: Dictionary in second._doors:
		reload_ids.append(str(door.get("id", "")))
	_check(reload_ids == expected_doors, "door ids must be stable across reload, got %s" % str(reload_ids))
	second.queue_free()

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("ENTITY_FAIL " + message)


func _finish() -> void:
	RunState.clear_saved()
	if _failures.is_empty():
		print("ENTITY_OK doors=2 containers=3 props=15 nodes=16 enemies=3 unique=yes stable=yes ordinal_free=yes")
		quit(0)
		return
	print("ENTITY_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
