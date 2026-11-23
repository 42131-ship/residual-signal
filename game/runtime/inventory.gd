class_name InventoryService
extends RefCounted

const DEFAULT_CAPACITY := 10

var capacity := DEFAULT_CAPACITY
var _counts: Dictionary = {}
var _order: Array[String] = []


func _init(cap: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(1, cap)


func total() -> int:
	var count := 0
	for item_id: String in _counts:
		count += int(_counts[item_id])
	return count


func is_full() -> bool:
	return total() >= capacity


func count_of(item_id: String) -> int:
	return int(_counts.get(item_id, 0))


func has(item_id: String, amount := 1) -> bool:
	return count_of(item_id) >= amount


func add(item_id: String, amount := 1) -> bool:
	if item_id.is_empty() or amount <= 0:
		return false
	if total() + amount > capacity:
		return false
	if not _counts.has(item_id):
		_order.append(item_id)
	_counts[item_id] = count_of(item_id) + amount
	return true


## 一次加入多件；装不下的返回在 rejected 里，不静默丢弃。
func add_many(item_ids: Array) -> Dictionary:
	var added: Array[String] = []
	var rejected: Array[String] = []
	for value: Variant in item_ids:
		var item_id := str(value)
		if add(item_id, 1):
			added.append(item_id)
		else:
			rejected.append(item_id)
	return {"added": added, "rejected": rejected}


func remove(item_id: String, amount := 1) -> bool:
	if amount <= 0 or count_of(item_id) < amount:
		return false
	_counts[item_id] = count_of(item_id) - amount
	if int(_counts[item_id]) <= 0:
		_counts.erase(item_id)
		_order.erase(item_id)
	return true


func ids() -> Array[String]:
	return _order.duplicate()


func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_id: String in _order:
		result.append({"id": item_id, "count": count_of(item_id)})
	return result


func clear() -> void:
	_counts.clear()
	_order.clear()
