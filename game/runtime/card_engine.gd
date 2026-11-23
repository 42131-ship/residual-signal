class_name CardEngine extends RefCounted

signal card_fired(card_id: String, bind: Dictionary)
signal card_rejected(card_id: String, reason: String)

var data: DataLayer
var world: WorldState
var last_fired_day: Dictionary = {}
var fire_count: Dictionary = {}
var bound_choices: Dictionary = {}   # card_id -> {slot: option}，第一次绑完就固化


func init_from(d: DataLayer, w: WorldState) -> bool:
	if d == null or w == null:
		return false
	data = d
	world = w
	return true


func eligible(node_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data == null or world == null:
		return result

	var node_data: Dictionary = data.node(node_id)
	var node_tags: Array = node_data.get("tags", [])

	for card: Dictionary in data.cards():
		var cid: String = str(card.get("card_id", ""))
		if last_fired_day.has(cid):
			var ret: Variant = card.get("returns_after_days")
			if ret != null:
				if int(ret) == 0:
					continue
				if world.day - int(last_fired_day[cid]) < int(ret):
					continue

		var trigger: Dictionary = card.get("trigger", {})
		var day_range: Dictionary = trigger.get("day", {})
		if day_range.has("min") and world.day < int(day_range["min"]):
			continue
		if day_range.has("max") and world.day > int(day_range["max"]):
			continue

		var vars_match: bool = true
		for condition: Dictionary in trigger.get("vars", []):
			var current_value: float = world.var_of(str(condition.get("name", "")))
			var expected_value: float = float(condition.get("value", 0.0))
			var op: String = str(condition.get("op", ""))
			match op:
				"<=":
					if not current_value <= expected_value:
						vars_match = false
						break
				">=":
					if not current_value >= expected_value:
						vars_match = false
						break
				"<":
					if not current_value < expected_value:
						vars_match = false
						break
				">":
					if not current_value > expected_value:
						vars_match = false
						break
				"==":
					if not is_equal_approx(current_value, expected_value):
						vars_match = false
						break
				_:
					vars_match = false
					break
		if not vars_match:
			continue

		var required_tags: Array = trigger.get("node_tags_any", [])
		if not required_tags.is_empty():
			var tag_match: bool = false
			for tag: Variant in required_tags:
				if node_tags.has(tag):
					tag_match = true
					break
			if not tag_match:
				continue

		var required_node_ids: Array = trigger.get("node_ids", [])
		if not required_node_ids.is_empty() and not required_node_ids.has(node_id):
			continue

		if trigger.has("sediment_min"):
			if world.sediment_of(node_id) < int(trigger["sediment_min"]):
				continue

		result.append(card)

	return result


func bind_slots(card: Dictionary, seed_value: int) -> Dictionary:
	var result: Dictionary = {}
	var card_id: String = str(card.get("card_id", ""))
	for slot: Dictionary in card.get("slots", []):
		var slot_name: String = str(slot.get("slot", ""))
		var options: Array = slot.get("options", [])
		if options.is_empty():
			continue
		var selection_hash: int = hash(card_id + "|" + slot_name + "|" + str(seed_value))
		var index: int = posmod(selection_hash, options.size())
		result[slot_name] = str(options[index])
	return result


func fire(card: Dictionary, bind: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if world == null:
		return entries

	var cid: String = str(card.get("card_id", ""))
	for effect: Dictionary in card.get("effects", []):
		var when_value: String = str(effect.get("when", ""))
		var matched: bool = false
		for bound_value: Variant in bind.values():
			if str(bound_value) == when_value:
				matched = true
				break
		if not matched:
			continue

		var changes: Dictionary = effect.get("add_vars", {})
		for key: Variant in changes.keys():
			world.add_var(str(key), float(changes[key]))

		entries.append({
			"event_id": effect.get("evidence", ""),
			"card_id": cid,
			"day": world.day,
			"bind": bind
		})

	last_fired_day[cid] = world.day
	fire_count[cid] = int(fire_count.get(cid, 0)) + 1
	return entries


func render(card: Dictionary, bind: Dictionary) -> String:
	var text_data: Dictionary = card.get("text", {})
	var rendered: String = str(text_data.get("default", ""))

	for slot_name: Variant in bind.keys():
		rendered = rendered.replace("{" + str(slot_name) + "}", str(bind[slot_name]))

	var slot_names: Array[String] = []
	for slot: Dictionary in card.get("slots", []):
		slot_names.append(str(slot.get("slot", "")))
	for slot_name: String in slot_names:
		if not bind.has(slot_name) and rendered.contains("{" + slot_name + "}"):
			push_warning("卡片缺少槽位绑定: " + slot_name)

	return rendered


func pick_and_fire(node_id: String, seed_value: int) -> Dictionary:
	var candidates: Array[Dictionary] = eligible(node_id)
	if candidates.is_empty():
		return {"fired": false}

	var selected: Dictionary = {}
	var selected_id: String = ""
	var selected_is_new: bool = false
	var selected_day: int = 0

	for card: Dictionary in candidates:
		var cid: String = str(card.get("card_id", ""))
		var is_new: bool = not last_fired_day.has(cid)
		var fired_day: int = int(last_fired_day.get(cid, 0))

		if selected.is_empty():
			selected = card
			selected_id = cid
			selected_is_new = is_new
			selected_day = fired_day
			continue

		if is_new and not selected_is_new:
			selected = card
			selected_id = cid
			selected_is_new = true
			selected_day = fired_day
		elif is_new == selected_is_new:
			if is_new:
				if cid < selected_id:
					selected = card
					selected_id = cid
					selected_day = fired_day
			elif fired_day < selected_day or (fired_day == selected_day and cid < selected_id):
				selected = card
				selected_id = cid
				selected_day = fired_day

	# 绑槽结果一经确定就记下来。理由：`hash(...) % options.size()` 的确定性只是
	# **给定数据版本**的确定性 —— 哪天这张卡多了一个 option，同一个 seed 就会绑到
	# 另一个选项上，历史回放全部对不上。所以第一次绑完就存着，之后只读缓存。
	var bind: Dictionary = bound_choices.get(selected_id, {})
	if bind.is_empty():
		bind = bind_slots(selected, seed_value)
		bound_choices[selected_id] = bind.duplicate(true)
	var entries: Array[Dictionary] = fire(selected, bind)
	var rendered_text: String = render(selected, bind)
	card_fired.emit(selected_id, bind)

	return {
		"fired": true,
		"card_id": selected_id,
		"text": rendered_text,
		"l0": entries
	}


## 绑槽结果写进存档，回放才跨版本稳定。
## 不存它的话，改一次卡池就让所有历史回放对不上号。
func snapshot_binds() -> Dictionary:
	return bound_choices.duplicate(true)


func restore_binds(saved: Dictionary) -> bool:
	if saved == null or not saved is Dictionary:
		return false
	bound_choices = saved.duplicate(true)
	return true