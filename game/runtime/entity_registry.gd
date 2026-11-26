class_name EntityRegistry
extends RefCounted
## 稳定实体 ID（W1 · EntityRegistry）。
##
## 为什么要有这个：存档、回响层、断点续玩都要能说清「哪个门 / 哪个容器 / 哪个敌人」。
## 现状问题：门用 `_doors` 数组下标（0/1）与 `tile_x` 数字做身份，加一扇门就整体错位；
## 中文标签更不能当键——改文案就断档。
##
## 约定：`kind:template:local`，三段全 ASCII（统一小写），**不含下标、不含坐标**。
##   door:school:a_b               A 区与 B 区之间的那扇门
##   container:school:locker_bank  容器自带 id（data/loot/containers.json）
##   prop:school:first_aid_cabinet 道具/检查记录 id（data/prop_inspections.json）
##   node:school:corridor_a       拓扑 node_id 去掉模板前缀（data/nodes.json）
##   enemy:school:b               按房间的敌人槽位
##
## 本类只做「生成 / 解析 / 校验」，不持有运行时对象：
## 对象 -> ID 的绑定由场景自己挂（见 corridor.gd 的 `_doors[i]["id"]`）。

const SEP := ":"
const KIND_DOOR := "door"
const KIND_CONTAINER := "container"
const KIND_PROP := "prop"
const KIND_NODE := "node"
const KIND_ENEMY := "enemy"
const KINDS: Array[String] = [KIND_DOOR, KIND_CONTAINER, KIND_PROP, KIND_NODE, KIND_ENEMY]
## 房间字母表：下标只在「挑哪个字母」这一步用，字母本身才进 ID。
const ROOM_KEYS: Array[String] = ["a", "b", "c", "d", "e"]


static func make(kind: String, template: String, local: String) -> String:
	var k := kind.strip_edges().to_lower()
	var t := template.strip_edges().to_lower()
	var l := local.strip_edges().to_lower()
	if not KINDS.has(k):
		push_error("ENTITY_ID_BAD_KIND: " + kind)
		return ""
	if t.is_empty() or l.is_empty():
		push_error("ENTITY_ID_EMPTY: %s:%s:%s" % [kind, template, local])
		return ""
	# 纯数字的 local 说明又退回了「下标/坐标当键」，直接拒绝。
	if l.is_valid_int():
		push_error("ENTITY_ID_ORDINAL: " + l)
		return ""
	return k + SEP + t + SEP + l


static func parse(id: String) -> Dictionary:
	var parts := id.split(SEP)
	if parts.size() != 3:
		return {}
	if not KINDS.has(parts[0]):
		return {}
	if parts[1].is_empty() or parts[2].is_empty():
		return {}
	return {"kind": parts[0], "template": parts[1], "local": parts[2]}


static func is_valid(id: String) -> bool:
	return not parse(id).is_empty()


static func room_key(index: int) -> String:
	if index < 0 or index >= ROOM_KEYS.size():
		push_error("ENTITY_ID_BAD_ROOM: %d" % index)
		return ""
	return ROOM_KEYS[index]


## 分区下标 -> 门 ID。顺序变了 ID 不变（下标只用来取房间字母）。
static func door_id(template: String, from_index: int, to_index: int) -> String:
	var from_key := room_key(from_index)
	var to_key := room_key(to_index)
	if from_key.is_empty() or to_key.is_empty():
		return ""
	return make(KIND_DOOR, template, "%s_%s" % [from_key, to_key])


static func container_id(template: String, container: Dictionary) -> String:
	return make(KIND_CONTAINER, template, str(container.get("id", "")))


static func prop_id(template: String, record: Dictionary) -> String:
	return make(KIND_PROP, template, str(record.get("id", "")))


static func node_id(template: String, node: Dictionary) -> String:
	var raw := str(node.get("node_id", ""))
	# node_id 自带模板前缀（school_corridor_a）；去掉它，让 ID 保持 kind:template:local。
	if not template.is_empty() and raw.begins_with(template + "_"):
		raw = raw.substr(template.length() + 1)
	return make(KIND_NODE, template, raw)


static func enemy_id(template: String, room_index: int) -> String:
	return make(KIND_ENEMY, template, room_key(room_index))


## 一组 ID 是否两两不同（空 ID 也算不合格）。门禁与场景启动自检都用它。
static func all_unique(ids: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in ids:
		var id := str(value)
		if id.is_empty() or seen.has(id):
			return false
		seen[id] = true
	return true
