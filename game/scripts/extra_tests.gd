# Tests for music/jingles, the perk drink and the teddy-bear box move, started from autotest.gd:
#   tools/run_godot.sh 60 -- nacht --autotest 50 --music-test
#   tools/run_godot.sh 60 -- nacht --autotest 50 --drink-test
#   tools/run_godot.sh 90 -- verruckt --autotest 80 --teddy-test
#   tools/run_godot.sh 120 -- shinonuma --autotest 110 --egg-test   (egg_tests.gd, any map)
#   tools/run_godot.sh 90 -- derriese --autotest 80 --monkey-test
# Prints OK/FAIL lines and saves screenshots to analysis/preview/.
class_name ExtraTests

static var _fails := 0


static func run(at: Node) -> void:
	var game: Game = at.game
	await game.level.wait_navigation()
	var args := OS.get_cmdline_user_args()
	if args.has("--music-test"):
		await _music(at, game)
	elif args.has("--drink-test"):
		await _drink(at, game)
	elif args.has("--teddy-test"):
		await _teddy(at, game)
	elif args.has("--egg-test"):
		await EggTests.eggs(at, game)
	elif args.has("--monkey-test"):
		await EggTests.monkey(at, game)
	print("[extra] %s (%d failures)" % ["OK" if _fails == 0 else "FAIL", _fails])
	at.get_tree().quit()


static func _check(ok: bool, what: String) -> void:
	print("[extra] %s: %s" % ["OK" if ok else "FAIL", what])
	if not ok:
		_fails += 1


static func _snap(at: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	at.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))


static func _music(at: Node, game: Game) -> void:
	var sfx := Sfx.instance
	for k in ["round_start", "game_start", "round_end", "game_over", "box_music", "box_flyaway", "box_fall",
			"teddylaugh", "teddypoof", "teddyland", "jingle_jugga", "jingle_speed", "jingle_dbtap", "jingle_revive",
			"perk_hum", "gameover_start", "dog_end_music"]:
		_check(sfx._stream(k) != null, "sound %s" % k)
	_check(not (sfx._index["sequences"].get(Sfx.iw_hash("perk_drink"), []) as Array).is_empty(), "perk_drink sequence")
	var go: String = sfx._index["levels"].get(sfx.level_name, {}).get(sfx._index["names"]["game_over"], "")
	_check(go != "" and sfx._stream("game_over").resource_path == go, "game over music of %s: %s" % [sfx.level_name, go])
	# round 1 starts after the navmesh: start_game (not on Der Riese)
	var t := 0.0
	while game.round_number < 1 and t < 20.0:
		await at.get_tree().create_timer(0.25).timeout
		t += 0.25
	await at.get_tree().process_frame
	await at.get_tree().process_frame
	var expect := "" if sfx.level_name == "derriese" else "game_start"
	var playing := sfx._music != null and sfx._music.playing
	if expect == "":
		_check(not playing, "round 1: no start music on Der Riese")
	else:
		_check(playing and sfx._music.stream == sfx._stream(expect), "round 1 music %s" % expect)
	game.set_process(false)
	game._next_round()
	await at.get_tree().process_frame
	await at.get_tree().process_frame
	_check(sfx._music.playing and sfx._music.stream == sfx._stream("round_start"), "round 2 music round_start")


static func _drink(at: Node, game: Game) -> void:
	game.set_process(false)
	await at.get_tree().create_timer(0.5).timeout
	var p := game.player
	var vm: Viewmodel = p._viewmodel
	var mag: int = p.weapon()["mag"]
	PerkMachine.drink(p)
	_check(vm.drinking and vm._bottle != null and vm._bottle.visible, "drinking, bottle shown")
	p.fire_held = true
	for t in [0.2, 0.6, 1.0, 1.4, 1.8, 2.2]:
		await at.get_tree().create_timer(0.4 if t > 0.2 else 0.2).timeout
		await _snap(at, "drink_%02d" % int(t * 10))
	_check(p.weapon()["mag"] == mag, "no firing while drinking (mag %d -> %d)" % [mag, p.weapon()["mag"]])
	p.fire_held = false
	await at.get_tree().create_timer(1.0).timeout
	_check(not vm.drinking and not vm._bottle.visible and (vm._weapon == null or vm._weapon.visible), "weapon back")
	await _snap(at, "drink_after")


static func _face_box(at: Node, game: Game, box: MysteryBox) -> void:
	var p := game.player
	var front := box.global_transform * Vector3(0, 0, 1.6)
	var probe := box.global_transform * Vector3(0, 0, -1.6)
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(box.global_position + Vector3.UP, front + Vector3.UP)
	var down := PhysicsRayQueryParameters3D.create(front + Vector3.UP, front + Vector3.DOWN * 2.0)
	if not space.intersect_ray(q).is_empty() or space.intersect_ray(down).is_empty():
		front = probe
	p.global_position = front
	p.velocity = Vector3.ZERO
	var to := box.global_position - front
	p.rotation.y = atan2(-to.x, -to.z)
	p.get_viewport().get_camera_3d().rotation.x = -0.2
	await at.get_tree().physics_frame


static func _teddy(at: Node, game: Game) -> void:
	game.set_process(false)
	var box: MysteryBox = game.level.boxes[0]
	var p := game.player
	p.health = 1e9
	_check(box.locations.size() > 1, "%d box locations %s" % [box.locations.size(), box.locations])
	var first := box.entity
	await _face_box(at, game, box)
	p.points = 5000
	box._teddy_next = true
	box.interact(p)
	_check(p.points == 5000 - MysteryBox.COST, "paid")
	await at.get_tree().create_timer(MysteryBox.CYCLE_TIME + 0.4).timeout
	_check(box.state == MysteryBox.State.TEDDY and p.points == 5000, "teddy, refunded (points %d)" % p.points)
	await _box_shot(at, box, "teddy_0_bear", 1.3)
	await at.get_tree().create_timer(MysteryBox.TEDDY_WAIT + MysteryBox.TEDDY_RISE + 0.5).timeout
	_check(box.state == MysteryBox.State.LEAVING, "box rising")
	p.get_viewport().get_camera_3d().rotation.x = 0.3
	await _box_shot(at, box, "teddy_1_rising", 2.2)
	var t := 0.0
	while box.state != MysteryBox.State.CLOSED and t < 20.0:
		await at.get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(box.state == MysteryBox.State.CLOSED and box.entity != first, "moved %s -> %s" % [first, box.entity])
	await _face_box(at, game, box)
	await _box_shot(at, box, "teddy_2_new_place", 1.3)
	# the box works at its new place
	box.interact(p)
	await at.get_tree().create_timer(MysteryBox.CYCLE_TIME + 0.4).timeout
	_check(box.state == MysteryBox.State.OFFERED, "new place gives a weapon (%s)" % box.offered)
	await _box_shot(at, box, "teddy_3_offer", 1.3)
	# never back to the last two locations
	var seen := [box.entity]
	for i in 4:
		box._timer = 0.0
		box.state = MysteryBox.State.CLOSED
		var before := box._memory.duplicate()
		box._warp()
		_check(not box.entity in before, "warp %d -> %s (memory %s)" % [i, box.entity, before])
		seen.append(box.entity)
		await at.get_tree().create_timer(MysteryBox.FALL_TIME + 0.2).timeout


# screenshot from a free camera 2.4 m in front of the box (the open side)
static func _box_shot(at: Node, box: MysteryBox, name: String, look_y: float) -> void:
	var space := box.get_world_3d().direct_space_state
	var eye := Vector3.ZERO
	for side in [1.0, -1.0]:
		eye = box.global_transform * Vector3(0, 0, 2.4 * side) + Vector3.UP * 1.7
		var q := PhysicsRayQueryParameters3D.create(box.global_position + Vector3.UP * 1.0, eye)
		if space.intersect_ray(q).is_empty():
			break
	var cam := Camera3D.new()
	box.add_child(cam)
	var old := at.get_viewport().get_camera_3d()
	cam.look_at_from_position(eye, box.global_position + Vector3.UP * look_y)
	cam.make_current()
	await at.get_tree().process_frame
	await _snap(at, name)
	cam.queue_free()
	if old:
		old.make_current()
