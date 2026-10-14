# Checks for barrels.gd and mystery_maps.gd, screenshots in analysis/preview:
#   -- nacht --barrel-test        25 barrels; shoot one next to zombies: 3 s fire, blast kills
#                                 and makes crawlers, the barrel next to it goes off 3 s later
#   -- shinonuma --maps-test      6 mystery box map boards follow the box
extends Node

var game: Game
var fails := 0
var _cam: Camera3D
const LifecycleTests := preload("res://scripts/lifecycle_tests.gd")


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/barrel_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	if args.has("--barrel-test"):
		t._barrel_test()
	elif args.has("--maps-test"):
		t._maps_test()


func _check(tag: String, ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [tag, "OK" if ok else "FAIL", what])
	fails += int(not ok)


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 400.0
		game.add_child(_cam)
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	_cam.make_current()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))
	_cam.clear_current(true)


# A direction from `c` with nothing solid for `d` metres at 1 m height.
func _clear_dir(c: Vector3, d: float, skip: Array) -> Vector3:
	var space := game.get_world_3d().direct_space_state
	for k in 16:
		var a := TAU * k / 16.0
		var dir := Vector3(sin(a), 0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(c + Vector3.UP, c + Vector3.UP + dir * d, 1)
		q.exclude = skip
		if space.intersect_ray(q).is_empty():
			return dir
	return Vector3(0, 0, 1)


func _views(prefix: String, c: Vector3, dir: Vector3) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	await _shot(prefix + "_front", c + dir * 3.0 + Vector3.UP * 1.4, c + Vector3.UP * 0.7)
	await _shot(prefix + "_side", c + side * 3.0 + Vector3.UP * 1.4, c + Vector3.UP * 0.7)


func _barrel_test() -> void:
	const TAG := "barrel"
	var lv := game.level
	await lv.wait_navigation()
	var x := ExplosiveBarrels.of(game)
	_check(TAG, x != null and x.barrels.size() == 25, "SetUpBarrels: %d barrels" % (x.barrels.size() if x else 0))
	if x == null:
		_finish()
		return
	var a: ExplosiveBarrels.Barrel = x.barrels["BarrelExplosive2"]
	var b: ExplosiveBarrels.Barrel = x.barrels["BarrelExplosive3"]
	var c := a.global_position
	var dir := _clear_dir(c, 6.0, [a.get_rid(), b.get_rid()])
	await _views("barrel_intact", c, dir)
	var p := game.player
	p.health = 1e6
	p.global_position = c + dir * 6.0
	await get_tree().physics_frame
	LifecycleTests._aim(p, c + Vector3.UP * 0.6)
	var w := p.weapon()
	w["mag"] = 5
	p._cooldown = 0.0
	p._fire(w, Weapons.stats_of(w).merged({"range": 60.0}, true))
	await get_tree().physics_frame
	_check(TAG, a.state == ExplosiveBarrels.Barrel.BURNING, "shot barrel burns")
	_check(TAG, b.state == ExplosiveBarrels.Barrel.INTACT, "the other barrel still intact")
	await get_tree().create_timer(0.5).timeout
	await _views("barrel_burning", c, dir)
	# zombies around it just before it goes off: two weak, one tough (crawler)
	while a.left > 0.25:
		await get_tree().physics_frame
	var side := dir.cross(Vector3.UP).normalized()
	var zs := []
	for off in [side * 1.5, -side * 1.6, dir * 2.2]:
		var z: Zombie = LifecycleTests._spawn(game)
		z.global_position = c + off
		z.state = Zombie.State.CHASE
		zs.append(z)
	zs[2].max_health = 1e6   # crawler_health keeps huge test health
	zs[2].health = 1e6
	while is_instance_valid(a) and a.state == ExplosiveBarrels.Barrel.BURNING:
		for z in zs:
			if z.state != Zombie.State.DEAD:
				z.velocity = Vector3.ZERO
		await get_tree().physics_frame
	var t_a := x._clock
	var r := x.last_result
	print("[barrel] blast: ", r)
	_check(TAG, not x.barrels.has("BarrelExplosive2") and "BarrelExplosive2" in x.destroyed_barrels(), "barrel gone after the fuse")
	_check(TAG, int(r.get("killed", 0)) >= 2, "kills: %d" % int(r.get("killed", 0)))
	_check(TAG, zs[2].state != Zombie.State.DEAD and zs[2].crawler, "tough zombie is a crawler")
	_check(TAG, float(r.get("player", 0.0)) == 0.0, "player not hurt")
	_check(TAG, is_instance_valid(b) and b.state == ExplosiveBarrels.Barrel.BURNING, "chain: neighbour burning")
	await get_tree().create_timer(0.3).timeout
	await _shot("barrel_after_blast", c + dir * 4.0 + Vector3.UP * 1.6, c + Vector3.UP * 0.5)
	while is_instance_valid(b) and b.state == ExplosiveBarrels.Barrel.BURNING:
		await get_tree().physics_frame
	var ev := x.log.filter(func(e): return e[1] == "BarrelExplosive3" and e[2] == "explode")
	_check(TAG, not ev.is_empty() and absf(ev[0][0] - t_a - ExplosiveBarrels.FUSE) < 0.2, "chain: neighbour exploded %.2f s later" % ((ev[0][0] - t_a) if not ev.is_empty() else -1.0))
	var s := x.save_state()
	_check(TAG, (s["destroyed"] as Array).size() == 2, "save_state %s" % [s])
	# knife sets one off too
	var k: ExplosiveBarrels.Barrel = x.barrels["BarrelExplosive9"]
	var kd := _clear_dir(k.global_position, 2.0, [k.get_rid()])
	p.global_position = k.global_position + kd * 1.1
	await get_tree().physics_frame
	LifecycleTests._aim(p, k.global_position + Vector3.UP * 0.6)
	p._melee_cooldown = 0.0
	p.melee()
	_check(TAG, k.state == ExplosiveBarrels.Barrel.BURNING, "knife sets it on fire")
	# a frag grenade blast
	var g: ExplosiveBarrels.Barrel = x.barrels["BarrelExplosive19"]
	Explosion.blast(game, g.global_position + Vector3(2.0, 0.2, 0.0), p, Explosion.FRAG)
	_check(TAG, g.state == ExplosiveBarrels.Barrel.BURNING, "grenade blast sets it on fire")
	# resume: destroyed ones gone, burning ones burn on
	x.load_state({"destroyed": ["BarrelExplosive25"], "burning": [["BarrelExplosive24", 1.0]]})
	_check(TAG, not x.barrels.has("BarrelExplosive25") and "BarrelExplosive25" in x.destroyed_barrels(), "load_state removes a destroyed barrel")
	_check(TAG, x.barrels["BarrelExplosive24"].state == ExplosiveBarrels.Barrel.BURNING and absf(x.barrels["BarrelExplosive24"].left - 1.0) < 0.05, "load_state: burning barrel keeps its timer")
	_finish()


func _maps_test() -> void:
	const TAG := "maps"
	var lv := game.level
	await lv.wait_navigation()
	var x := lv.get_node_or_null("MysteryMaps") as ShinonumaMysteryMaps
	_check(TAG, x != null and x.boards.size() == 6, "6 boards (%d)" % (x.boards.size() if x else 0))
	if x == null or lv.boxes.is_empty():
		_finish()
		return
	var box: MysteryBox = lv.boxes[0]
	_check(TAG, x.pose == ShinonumaMysteryMaps.BOX_ANIMS.get(box.entity, "?"), "boards on %s (%s)" % [box.entity, x.pose])
	var n := "MysteryBoxMapDownstairsRoom1"
	var xf := Level.flag_transform(lv.entity(n)["transform"])
	var at := xf.origin
	var fwd := xf.basis.z.normalized()
	await _shot("maps_%s_front" % x.pose, at + fwd * 2.0, at)
	await _shot("maps_%s_back" % x.pose, at - fwd * 2.0, at)
	await _shot("maps_%s_side" % x.pose, at + xf.basis.x.normalized() * 2.0 + fwd * 0.3, at)
	if OS.get_cmdline_user_args().has("--maps-all"):   # every pose of ASM 0b888f83
		for a in ShinonumaMysteryMaps.BOX_ANIMS.values():
			for ap in x.boards:
				DerrieseExtras._pose(ap, a)
			await _shot("maps_pose_%s" % a, at + fwd * 2.0, at)
	for i in 3:
		var before := x.pose
		box._warp()
		_check(TAG, x.pose == ShinonumaMysteryMaps.BOX_ANIMS.get(box.entity, "?") and x.pose != before, "box moved to %s: boards %s" % [box.entity, x.pose])
		await _shot("maps_%s_front" % x.pose, at + fwd * 2.0, at)
	_finish()


func _finish() -> void:
	print("[tests] %s" % ("ALL OK" if fails == 0 else "%d FAIL" % fails))
	get_tree().quit()
