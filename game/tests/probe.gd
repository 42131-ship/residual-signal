extends SceneTree

func _initialize() -> void:
	var DL = load("res://game/runtime/data_layer.gd")
	var WS = load("res://game/runtime/world_state.gd")
	var CE = load("res://game/runtime/card_engine.gd")
	var data = DL.new()
	data.load_all()
	var world = WS.new()
	world.init_from(data)
	var eng = CE.new()
	eng.init_from(data, world)
	world.day = 5
	world.hour = 9

	var node := "school_corridor_a"
	var cands: Array = eng.eligible(node)
	print("eligible=", cands.size())
	if cands.is_empty():
		quit(1)
		return
	var card: Dictionary = cands[0]
	var fx: Array = card.get("effects", [])
	var whens: Array = []
	for e in fx:
		whens.append(e.get("when"))
	print("card=", card.get("card_id"), "  effects=", fx.size(), "  when=", whens)

	var bind: Dictionary = eng.bind_slots(card, 1)
	print("bind=", bind)
	var before: float = world.var_of("trust")
	var l0: Array = eng.fire(card, bind)
	print("fire -> L0 条目=", l0.size(), "  trust ", before, " -> ", world.var_of("trust"))

	var res: Dictionary = eng.pick_and_fire(node, 2)
	var rl0: Array = res.get("l0", []) if res.get("l0") != null else []
	print("pick_and_fire fired=", res.get("fired"), "  l0=", rl0.size())
	quit(0)
