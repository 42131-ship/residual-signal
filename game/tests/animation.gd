extends SceneTree
## 动作库门禁：每个角色都有 idle/walk/hurt/death，帧合规，且运行时真在播。
## 运行（要渲染，抓两张动作证据）：
##   .tools/Godot_v4.7-stable_win64_console.exe --path . --fixed-fps 60 \
##     --script res://game/tests/animation.gd -- ANIM
## 通过输出一行 `ANIMATION_OK ...`。

const SCENE: PackedScene = preload("res://game/scenes/corridor.tscn")
const SRC_DIR := "res://art/generated_candidates/characters"
const PLAYER_BASE := "res://art/generated_candidates/characters/SPR-player_32x48.png"

var _corridor: Node2D
var _actor: Player
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_catalog()
	if _failures.is_empty():
		await _verify_frames()
	if _failures.is_empty():
		await _verify_runtime()
	_finish()


# ── 清单：所有人物都要有四个动作 ────────────────────────────

func _verify_catalog() -> void:
	var expected: Array[String] = []
	var dir := DirAccess.open(SRC_DIR)
	_check(dir != null, "character source folder missing")
	if dir == null:
		return
	for file: String in dir.get_files():
		if not file.begins_with("SPR-") or not file.ends_with(".png"):
			continue
		if file.begins_with("SPR-player_walk"):
			continue  # 动作表的输入，不是角色本体
		expected.append(file.replace("SPR-", "").replace("_32x48", "").replace("_32", "").replace(".png", ""))
	_check(expected.size() >= 30, "expected at least 30 characters, found %d" % expected.size())

	var covered := CharAnim.character_ids()
	_check(covered.size() == expected.size(),
		"animation manifest covers %d of %d characters" % [covered.size(), expected.size()])
	for id: String in expected:
		_check(id in covered, "character %s has no animation sheet" % id)

	var anims := CharAnim.anim_ids()
	_check(anims == ["death", "hurt", "idle", "walk"], "expected four anims, got %s" % str(anims))
	_check(int(CharAnim.anim_meta("idle").get("count", 0)) == 2, "idle needs 2 frames")
	_check(int(CharAnim.anim_meta("walk").get("count", 0)) == 4, "walk needs 4 frames")
	_check(int(CharAnim.anim_meta("hurt").get("count", 0)) == 1, "hurt needs 1 frame")
	_check(int(CharAnim.anim_meta("death").get("count", 0)) == 3, "death needs 3 frames")
	for id: String in covered:
		_check(CharAnim.frame_size(id) != Vector2i.ZERO, "%s has no frame size" % id)
		_check(not CharAnim.parts(id).is_empty(), "%s has no part decomposition" % id)


# ── 帧：尺寸、二值 alpha、≤16 色、第 0 帧与静态帧一致 ────────

func _verify_frames() -> void:
	var checked := 0
	for id: String in CharAnim.character_ids():
		var size := CharAnim.frame_size(id)
		for index in range(10):
			var atlas := CharAnim.frame_texture(id, index)
			_check(atlas != null, "%s frame %d missing" % [id, index])
			if atlas == null:
				continue
			var image := atlas.get_image()
			if image == null:
				_check(false, "%s frame %d unreadable" % [id, index])
				continue
			_check(image.get_size() == size, "%s frame %d size %s != %s" % [id, index, image.get_size(), size])
			var colors := {}
			var semi := false
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					var pixel := image.get_pixel(x, y)
					if pixel.a == 0.0:
						continue
					if pixel.a < 1.0:
						semi = true
					colors[Color(pixel.r, pixel.g, pixel.b)] = true
			_check(not semi, "%s frame %d has semi-transparent pixels" % [id, index])
			_check(colors.size() <= 16, "%s frame %d uses %d colours" % [id, index, colors.size()])
			_check(image.get_used_rect().size != Vector2i.ZERO, "%s frame %d is empty" % [id, index])
			checked += 1
	# 第 0 帧必须与原静态帧逐像素一致 —— 否则等于顺手改了角色美术。
	var base := Image.load_from_file(ProjectSettings.globalize_path(PLAYER_BASE))
	var frame0 := CharAnim.frame_texture("player", 0).get_image()
	_check(base != null and frame0 != null, "could not compare player frame 0")
	if base != null and frame0 != null:
		# 导入后的贴图可能被引擎做色彩空间转换，所以逐像素比、留极小容差；
		# 真正要比的是「美术有没有被改动」，不是编码字节。
		var mismatch := 0
		var first := ""
		for y in range(base.get_height()):
			for x in range(base.get_width()):
				var a := base.get_pixel(x, y)
				var b := frame0.get_pixel(x, y)
				# 全透明像素的 RGB 是导入时 fix_alpha_border 填的，不参与比较。
				if a.a <= 0.02 and b.a <= 0.02:
					continue
				if absf(a.a - b.a) > 0.02 or absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
					mismatch += 1
					if first.is_empty():
						first = "(%d,%d) %s vs %s" % [x, y, str(a), str(b)]
		_check(mismatch == 0, "player frame 0 differs from the static art at %d px, first %s" % [mismatch, first])
	print("ANIM_FRAMES checked=%d" % checked)


# ── 运行时：主角与感染体都真的在切帧 ────────────────────────

func _verify_runtime() -> void:
	_corridor = SCENE.instantiate() as Node2D
	root.add_child(_corridor)
	_actor = _corridor.get_node_or_null("Player") as Player
	await process_frame
	await process_frame
	_check(_actor != null, "player missing")
	if _actor == null:
		return

	# 帧号推进：walk 每秒 10 帧，0.25 秒应当跨 2 帧。
	var fps := float(CharAnim.anim_meta("walk").get("fps", 0.0))
	_check(fps > 0.0, "walk fps must come from the manifest")
	var start := CharAnim.frame_at("player", "walk", 0.0)
	var later := CharAnim.frame_at("player", "walk", 0.25)
	_check(start != later, "walk frame did not advance over time (%d == %d)" % [start, later])

	var sprite := _actor.get_node_or_null("BodySprite") as Sprite2D
	_check(sprite != null, "player body sprite missing")
	if sprite == null:
		return
	var seen := {}
	Input.action_press("move_right")
	for _frame in range(40):
		await process_frame
		if sprite.texture is AtlasTexture:
			seen[(sprite.texture as AtlasTexture).region.position.x] = true
	Input.action_release("move_right")
	_check(seen.size() >= 2, "player sprite did not cycle frames while walking (%d unique)" % seen.size())
	_check(_corridor._player_anim_id == "walk", "player should report walk while moving, got %s" % _corridor._player_anim_id)

	# 受击帧优先。
	_corridor._on_enemy_attacked(1)
	_check(_corridor._player_hurt_t > 0.0, "taking damage must arm the hurt frame")
	await process_frame
	_check(_corridor._player_anim_id == "hurt", "hurt must win over walk for its window")

	# 感染体也在切帧。
	var enemy: Enemy = null
	for candidate: Enemy in _corridor._enemies:
		if is_instance_valid(candidate):
			enemy = candidate
			break
	_check(enemy != null, "no enemy to animate")
	if enemy != null:
		var enemy_sprite := enemy.get_node_or_null("BodySprite") as Sprite2D
		_check(enemy_sprite != null, "enemy sprite missing")
		if enemy_sprite != null:
			var enemy_seen := {}
			for _frame in range(40):
				await process_frame
				if enemy_sprite.texture is AtlasTexture:
					enemy_seen[(enemy_sprite.texture as AtlasTexture).region.position.x] = true
			_check(enemy_seen.size() >= 2, "enemy did not cycle frames (%d unique)" % enemy_seen.size())
			# 死亡停在倒地帧。
			enemy.take_damage(99)
			await process_frame
			_check(enemy.dead, "enemy should be dead")
			_check(enemy_sprite.texture is AtlasTexture, "dead enemy must keep an animation frame")
			if enemy_sprite.texture is AtlasTexture:
				var region := (enemy_sprite.texture as AtlasTexture).region.position.x
				var death_start := int(CharAnim.anim_meta("death").get("start", 7))
				_check(region >= death_start * 32, "dead enemy should sit on a death frame, got x=%d" % region)

	# 证据截图：走起来的主角 + 动作表审阅图已在设计目录。
	_actor.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	if shot != null:
		shot.save_png(ProjectSettings.globalize_path("res://design/previews/ANIMATION_walk.png"))
		print("ANIM_SHOT res://design/previews/ANIMATION_walk.png")
	_actor.set_physics_process(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("ANIM_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("ANIMATION_OK characters=%d anims=4 frames=10" % CharAnim.character_ids().size())
		quit(0)
		return
	print("ANIMATION_FAILED count=%d" % _failures.size())
	for failure: String in _failures:
		print("  - " + failure)
	quit(1)
