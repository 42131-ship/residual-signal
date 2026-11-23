extends SceneTree
## Run with a graphical renderer. --without-hud captures the native art review.

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const CATALOG := "res://art/generated_candidates/props/stage1/props.json"
const VIEW_SIZE := Vector2i(384, 216)
const PROP_SIZE := Vector2i(32, 32)
const TILE_SIZE := 16
const WORLD_SIZE := Vector2i(640, 224)
const PROP_POSITIONS := {
	"locker_bank": Vector2i(4, 6), "door_broken": Vector2i(14, 6),
	"desk_flipped": Vector2i(11, 9), "window_night": Vector2i(17, 4),
	"light_dead": Vector2i(20, 3), "wall_clock_stopped": Vector2i(4, 3),
	"fire_extinguisher": Vector2i(22, 6), "first_aid_cabinet": Vector2i(25, 4),
	"trash_bin": Vector2i(23, 9), "mop_bucket": Vector2i(29, 9),
	"drinking_fountain": Vector2i(32, 5), "chair_toppled": Vector2i(17, 9),
	"intercom_broken": Vector2i(31, 3), "classroom_plaque": Vector2i(12, 4),
	"notice_board_torn": Vector2i(33, 3),
}
const PROP_NAMES := [
	"locker_bank", "door_broken", "desk_flipped", "window_night", "light_dead",
	"wall_clock_stopped", "fire_extinguisher", "first_aid_cabinet", "trash_bin",
	"mop_bucket", "drinking_fountain", "chair_toppled", "intercom_broken",
	"classroom_plaque", "notice_board_torn",
]

var _corridor: Node2D
var _actor: Player
var _props: Node2D
var _prefix := "CORRIDOR"
var _without_hud := false
var _evidence: Dictionary[String, int] = {}
var _visible_shots: Dictionary[String, int] = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--without-hud":
			_without_hud = true
		elif argument.is_valid_filename() and argument.begins_with("CORRIDOR-"):
			_prefix = argument

	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	_actor = _corridor.get_node_or_null("Player") as Player
	_props = _corridor.get_node_or_null("Props") as Node2D
	var hud := _corridor.get_node_or_null("HUD") as CanvasLayer
	var light := _corridor.get_node_or_null("Flashlight/Mask") as ColorRect
	if _actor == null or _props == null or hud == null or light == null or not light.material is ShaderMaterial:
		_fail("missing player, props, HUD or flashlight")
		return
	if not _verify_props() or not _verify_character() or not _verify_doorway() or not _verify_readability_structures():
		return
	hud.visible = not _without_hud
	(light.material as ShaderMaterial).set_shader_parameter("flicker_speed", 0.0)
	var steps: Array[bool] = []
	_actor.stepped.connect(func(is_running: bool) -> void: steps.append(is_running))

	if _actor.position != Vector2(32, 128):
		_fail("unexpected spawn position")
		return
	if not await _capture("entry", 0):
		return
	# 纵深轴（W/S）：让玩家真的走进下方房间，而不是只有一条地面线。
	var floor_y := _actor.position.y
	Input.action_press("move_down")
	for _frame in range(60):
		await physics_frame
	Input.action_release("move_down")
	await physics_frame
	if _actor.position.y <= floor_y + 12.0:
		_fail("depth movement did not move the player into the room: %.1f" % _actor.position.y)
		return
	if _actor.position.y > 216.0 + 0.1:
		_fail("depth bounds leaked past the room edge: %.1f" % _actor.position.y)
		return
	# 纵深截图证据：玩家真的站在房间区块里，而不是被锁在一条地面线上。
	if not await _capture("depth", 0):
		return
	# 纵深遮挡：脚底 y 直接当 z_index，靠近镜头的道具压在玩家前面。
	if _actor.z_index != int(_actor.position.y):
		_fail("player z_index does not follow depth: %d vs %.1f" % [_actor.z_index, _actor.position.y])
		return
	Input.action_press("move_up")
	for _frame in range(120):
		await physics_frame
	Input.action_release("move_up")
	await physics_frame
	if absf(_actor.position.y - floor_y) > 0.5:
		_fail("player did not return to the floor line: %.1f" % _actor.position.y)
		return
	Input.action_press("move_right")
	if not await _walk_to(184.0, true):
		return
	if steps.is_empty() or steps.has(false):
		_fail("normal movement did not emit normal footsteps")
		return
	if not await _capture("classroom", 56):
		return
	if not await _walk_to(320.0, true) or not await _capture("midpoint", 192):
		return
	if not await _walk_to(368.0, true) or not await _capture("late", 240):
		return
	if not await _walk_to(422.0, true) or not await _capture("far_end", 256):
		return
	for key: String in PROP_NAMES:
		if _evidence.get(key, 0) < 24 or _visible_shots.get(key, 0) < 2:
			_fail("prop lacks isolated pixels or two clear screenshots: %s %s" % [key, str(_visible_shots)])
			return

	if not await _walk_to(600.0, true):
		return
	for _frame in range(20):
		await physics_frame
	Input.action_release("move_right")
	if not _actor.position.x >= 600.0 or not _actor.position.x <= 603.0:
		_fail("terminal wall did not stop the player: %s" % str(_actor.position))
		return

	var walk_start := _actor.position.x
	steps.clear()
	Input.action_press("walk")
	Input.action_press("move_left")
	# 12 px/s → 60Hz 下每帧 0.2px；150 帧约 30px，正好跨过一个 16px 步距。
	for _frame in range(150):
		await physics_frame
	Input.action_release("walk")
	var walk_distance := walk_start - _actor.position.x
	if walk_distance < 27.0 or walk_distance > 33.0 or steps.is_empty() or steps.has(true):
		_fail("slow movement distance=%.1f steps=%s" % [walk_distance, str(steps)])
		return
	if not await _walk_to(15.0, false):
		return
	for _frame in range(20):
		await physics_frame
	Input.action_release("move_left")
	if not _actor.position.x >= 13.0 or not _actor.position.x <= 15.0:
		_fail("left wall did not stop the player: %s" % str(_actor.position))
		return

	print("CORRIDOR_OK size=384x216 props=%d min_changed_pixels=%d slow_walk=%.1f bounds=both" % [
		_evidence.size(), _evidence.values().min(), walk_distance])
	quit(0)


func _verify_props() -> bool:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not catalog is Dictionary or catalog.get("schema") != "school-props-stage1.v1":
		return _fail("prop catalog missing or invalid")
	var assets: Array = catalog["assets"]
	if assets.size() != PROP_NAMES.size() or _props.get_child_count() != PROP_NAMES.size():
		return _fail("expected exactly %d props" % PROP_NAMES.size())

	var door_sprite: Sprite2D = _props.get_node_or_null("door_broken") as Sprite2D
	if door_sprite == null or door_sprite.position != Vector2(240, 112):
		return _fail("door placement must preserve the tile (14, 6) spawn-side doorway")
	var bounds := Rect2i(Vector2i.ZERO, WORLD_SIZE)
	var footprints: Array[Rect2i] = []
	var textures: Array[String] = []
	for index in range(PROP_NAMES.size()):
		var key: String = PROP_NAMES[index]
		var entry: Dictionary = assets[index]
		var cell: Array = entry["tile_position"]
		var pivot: Array = entry["pivot"]
		if entry["name"] != key or entry["asset_id"] != "prop_school_" + key or int(entry["index"]) != index:
			return _fail("wrong catalog entry for %s" % key)
		if cell.size() != 2 or pivot.size() != 2 or Vector2i(int(pivot[0]), int(pivot[1])) != PROP_SIZE / 2:
			return _fail("wrong center pivot for %s" % key)
		if Vector2i(int(cell[0]), int(cell[1])) != PROP_POSITIONS[key]:
			return _fail("unexpected placement for %s" % key)
		var top_left := Vector2i(int(cell[0]), int(cell[1])) * TILE_SIZE
		var sprite := _props.get_node_or_null(key) as Sprite2D
		if sprite == null or sprite.texture == null or not sprite.centered or sprite.texture.get_size() != Vector2(PROP_SIZE):
			return _fail("wrong sprite for %s" % key)
		var path := "res://" + str(entry["output_path"])
		if path in textures or sprite.texture.resource_path != path:
			return _fail("wrong or repeated texture for %s" % key)
		if sprite.position != Vector2(top_left + PROP_SIZE / 2) or sprite.scale != Vector2.ONE:
			return _fail("off-grid sprite %s" % key)
		var footprint := Rect2i(top_left, PROP_SIZE)
		if not bounds.encloses(footprint):
			return _fail("out of bounds: %s" % key)
		for other: Rect2i in footprints:
			if other.intersects(footprint):
				return _fail("overlapping prop canvas: %s" % key)
		footprints.append(footprint)
		textures.append(path)
	return true


func _verify_character() -> bool:
	var sprite := _actor.get_node_or_null("BodySprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return _fail("player sprite is missing")
	# 2026-11-23：主角放大为 32×48 原生帧（可见 41px）。清单同步见 tools/player_build.py。
	if sprite.texture.resource_path != "res://art/generated_candidates/characters/SPR-player_32x48.png":
		return _fail("player is not using the Stage 2 player asset")
	if sprite.texture.get_size() != Vector2(32, 48) or sprite.centered or sprite.scale != Vector2.ONE:
		return _fail("player sprite canvas, centered mode or scale is off-spec")
	var image := sprite.texture.get_image()
	if image == null or image.get_size() != Vector2i(32, 48):
		return _fail("could not inspect player sprite alpha bounds")
	var silhouette := image.get_used_rect()
	if silhouette != Rect2i(5, 6, 19, 41):
		return _fail("player sprite silhouette changed: %s" % str(silhouette))
	var foot_row := silhouette.end.y - 1
	var shoe_spans := PackedInt32Array()
	var run := 0
	for x in range(image.get_width()):
		if image.get_pixel(x, foot_row).a > 0.0:
			run += 1
		elif run > 0:
			shoe_spans.append(run)
			run = 0
	if run > 0:
		shoe_spans.append(run)
	if shoe_spans.size() != 2 or shoe_spans[0] < 4 or shoe_spans[1] < 4:
		return _fail("player sprite needs two separated shoes: %s" % str(shoe_spans))
	var source_corner := sprite.get_rect().position
	var foot_left := sprite.to_global(source_corner + Vector2(silhouette.position.x, foot_row))
	var foot_right := sprite.to_global(source_corner + Vector2(silhouette.end.x - 1, foot_row))
	if not is_equal_approx(foot_left.y, 128.0) or not is_equal_approx(foot_right.y, 128.0):
		return _fail("player sprite feet do not align with floor y=128: %.1f / %.1f" % [foot_left.y, foot_right.y])
	return true


func _verify_doorway() -> bool:
	var world: Node2D = _corridor.get_node_or_null("World") as Node2D
	var recess: Polygon2D = null
	if world != null:
		recess = world.get_node_or_null("ClassroomRecess") as Polygon2D
	if world == null or recess == null or recess.position != Vector2(224, 96):
		return _fail("doorway recess does not align with the door's two tile cells")
	if recess.polygon.size() != 4 or recess.polygon[2] != Vector2(32, 32):
		return _fail("doorway recess must remain an exact 32px grid opening")
	for child: Node in world.get_children():
		if child is not Sprite2D:
			continue
		var tile := child as Sprite2D
		if tile.position.x >= 224 and tile.position.x < 256 and tile.position.y >= 96 and tile.position.y < 128:
			return _fail("corridor wall tile still fills the doorway")
	return true


func _verify_readability_structures() -> bool:
	var world := _corridor.get_node_or_null("World") as Node2D
	if world == null:
		return _fail("missing world readability structures")

	var seams := world.get_node_or_null("FloorPanelSeams") as Sprite2D
	if seams == null or seams.position != Vector2(0, 128) or seams.texture == null:
		return _fail("floor seam overlay is missing or off-grid")
	var seam_image := seams.texture.get_image()
	if seam_image == null or seam_image.get_size() != Vector2i(640, 96):
		return _fail("floor seam image must cover all six floor rows")
	if seam_image.get_pixel(32, 1).a < 1.0 or seam_image.get_pixel(16, 33).a < 1.0 or seam_image.get_pixel(32, 65).a < 1.0:
		return _fail("floor seams lost their staggered 32px cadence")
	if seam_image.get_pixel(16, 1).a > 0.0 or seam_image.get_pixel(32, 33).a > 0.0:
		return _fail("floor seams reverted to a repeating 16px grid")

	var tile_image := Image.new()
	var tile_error := tile_image.load(ProjectSettings.globalize_path("res://art/generated_candidates/tiles/TL-04_corridor_v2.png"))
	if tile_error != OK or tile_image.is_empty():
		return _fail("could not inspect corridor tile palette: %s" % error_string(tile_error))
	var wall_luminance := tile_image.get_pixel(24, 8).get_luminance()
	var floor_luminance := tile_image.get_pixel(88, 8).get_luminance()
	if floor_luminance - wall_luminance < 0.07:
		return _fail("wall/floor luminance gap is too small: %.3f" % (floor_luminance - wall_luminance))
	if seam_image.get_pixel(624, 33).a < 1.0 or seam_image.get_pixel(608, 65).a < 1.0:
		return _fail("floor pattern must continue below the terminal wall-contact line")

	var sign := world.get_node_or_null("ExitDirectionSign") as Node2D
	var arrow := world.get_node_or_null("ExitDirectionSign/ArrowRight") as Polygon2D
	if sign == null or sign.position != Vector2(384, 108) or arrow == null:
		return _fail("entrance flashlight landing cue is missing or off-grid")
	if sign.get_node_or_null("Backing") == null or (sign.get_node("Backing") as Polygon2D).polygon[2] != Vector2(20, 10):
		return _fail("exit sign must retain its readable 20x10px silhouette")
	var light := _corridor.get_node_or_null("Flashlight/Mask") as ColorRect
	if light == null or not light.material is ShaderMaterial:
		return _fail("missing flashlight material for direction cue")
	var shader_material := light.material as ShaderMaterial
	var radius_value: Variant = shader_material.get_shader_parameter("radius_px")
	var cone_half_value: Variant = shader_material.get_shader_parameter("cone_half")
	var cone_feather_value: Variant = shader_material.get_shader_parameter("cone_feather")
	if not radius_value is float or not cone_half_value is float or not cone_feather_value is float:
		return _fail("flashlight radius and cone parameters must be explicitly configured")
	var radius := float(radius_value)
	var cone_half := float(cone_half_value)
	var cone_feather := float(cone_feather_value)
	var classroom_light := Vector2(184.0 - 56.0 + 9.0, 128.0 - 13.0)
	var sign_center := sign.position + Vector2(10.0, 5.0) - Vector2(56.0, 0.0)
	var cue_delta := sign_center - classroom_light
	if radius < 232.0 or cue_delta.length() >= radius or absf(atan2(cue_delta.y, cue_delta.x)) > cone_half:
		return _fail("exit cue falls outside the classroom flashlight cone: delta=%s radius=%.1f angle=%.3f half=%.3f" % [str(cue_delta), radius, absf(atan2(cue_delta.y, cue_delta.x)), cone_half])
	if absf(atan2(cue_delta.y, cue_delta.x)) > cone_half - cone_feather:
		return _fail("exit cue sits only in the feathered flashlight edge")
	var end_wall := world.get_node_or_null("CorridorEndWall") as Node2D
	var exit_door := world.get_node_or_null("CorridorEndWall/DoorLeaf") as Polygon2D
	var exit_lamp := world.get_node_or_null("CorridorEndWall/ExitLamp") as Polygon2D
	if end_wall == null or end_wall.position != Vector2(576, 48) or exit_door == null or exit_lamp == null:
		return _fail("far-end side door does not preserve the terminal scale cue")
	var terminal_wall := world.get_node_or_null("TerminalWallFace") as Node2D
	var terminal_face := world.get_node_or_null("TerminalWallFace/Face") as Polygon2D
	var floor_contact := world.get_node_or_null("TerminalWallFace/WallFloorContact") as Polygon2D
	var floor_contact_shade := world.get_node_or_null("TerminalWallFace/FloorContactShade") as Polygon2D
	var terminal_corner := world.get_node_or_null("TerminalWallFace/RightCorner") as Polygon2D
	if terminal_wall == null or terminal_wall.position != Vector2(608, 0) or terminal_face == null or floor_contact == null or floor_contact_shade == null or terminal_corner == null:
		return _fail("far-end frontal wall must close the corridor from x=608 to 640")
	var notice := _props.get_node_or_null("notice_board_torn") as Sprite2D
	if notice == null or notice.position != Vector2(544, 64) or notice.position.x + 16 > end_wall.position.x:
		return _fail("notice board must keep clear of the terminal door frame")
	if terminal_face.polygon[2] != Vector2(32, 128) or terminal_corner.position != Vector2(28, 0):
		return _fail("terminal wall requires a full-height face and visible corner return")
	for node: Node in world.get_children():
		if not node is Sprite2D:
			continue
		var tile := node as Sprite2D
		if tile.position.y == 0 and tile.position.x == 0 and tile.region_rect.position.x != 16:
			return _fail("top viewport strip is not filled with the wall tile")
		if tile.position.y == 208 and tile.position.x == 0 and tile.region_rect.position.x != 80:
			return _fail("bottom viewport strip is not filled with the floor tile")
	return true


func _walk_to(target: float, right: bool) -> bool:
	# 24 px/s 下每帧约 0.4px；按距离推帧数上限（6 倍余量 + 缓冲），
	# 免得「600→15」这种远距离回程撞上固定上限被误判成走不到。
	var budget := int(absf(target - _actor.position.x) * 6.0) + 300
	for _frame in range(budget):
		# Floating-point collision recovery can move the body within its safe margin.
		if absf(_actor.position.y - 128.0) > 0.25:
			return _fail("player changed floor height: %s" % str(_actor.position))
		if (_actor.position.x >= target if right else _actor.position.x <= target):
			return true
		await physics_frame
	return _fail("player did not reach x=%.0f" % target)


func _capture(label: String, expected_left: int) -> bool:
	_actor.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var offset := Vector2i(root.get_canvas_transform().origin.round())
	# 纵深轴加入后相机会轻微下移（y 108..116），这里只锁水平取景。
	if offset.x != -expected_left:
		return _fail("%s camera expected world left=%d, canvas offset=%s" % [label, expected_left, offset])
	var rendered := root.get_texture().get_image()
	if rendered == null or rendered.is_empty() or rendered.get_size() != VIEW_SIZE:
		return _fail("expected native 384x216 pixels at %s" % label)
	var directory := ProjectSettings.globalize_path("res://design/previews")
	var file := directory.path_join("%s_%s.png" % [_prefix, label])
	if rendered.save_png(file) != OK:
		return _fail("could not save %s" % file)

	var canvas := Rect2i(Vector2i.ZERO, VIEW_SIZE)
	var fully_visible := PackedStringArray()
	for child: Node in _props.get_children():
		var sprite := child as Sprite2D
		var top_left := sprite.get_global_transform_with_canvas() * sprite.get_rect().position
		var footprint := Rect2i(Vector2i(top_left.round()), PROP_SIZE)
		if not canvas.encloses(footprint):
			continue
		var key := str(sprite.name)
		fully_visible.append(key)
		var covered := false
		for other_node: Node in _props.get_children():
			if other_node == sprite:
				continue
			var other := other_node as Sprite2D
			var other_origin := other.get_global_transform_with_canvas() * other.get_rect().position
			if footprint.intersects(Rect2i(Vector2i(other_origin.round()), PROP_SIZE)):
				covered = true
				break
		if covered:
			continue
		sprite.hide()
		await RenderingServer.frame_post_draw
		var without_prop := root.get_texture().get_image()
		sprite.show()
		var changed := _changed_pixels(rendered, without_prop, footprint)
		if changed < 24 or changed > 1000:
			_actor.set_physics_process(true)
			return _fail("weak isolated sprite pixels for %s: %d" % [key, changed])
		_evidence[key] = maxi(_evidence.get(key, 0), changed)
		_visible_shots[key] = _visible_shots.get(key, 0) + 1
	_actor.set_physics_process(true)
	print("RENDER_OK %s camera_x=%d player_x=%.1f fully_visible=%s" % [
		file, expected_left + VIEW_SIZE.x / 2, _actor.position.x, ",".join(fully_visible)])
	return true


func _changed_pixels(before: Image, after: Image, area: Rect2i) -> int:
	var changed := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) >= 3.0 / 255.0:
				changed += 1
	return changed


func _fail(detail: String) -> bool:
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.action_release("walk")
	push_error("CORRIDOR_FAIL %s" % detail)
	quit(1)
	return false
