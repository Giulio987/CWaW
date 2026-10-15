# Checks for hit_fx.gd and mustang_bolt.gd, screenshots in analysis/preview (hitfx_*):
#   -- shinonuma --hitfx-test     blood for each damage step (front and side), explosive
#                                 hit, head / arm off, bullet impacts of three gun classes on
#                                 a wall (front and side), muzzle flashes (normal / PaP),
#                                 Mustang & Sally explosive round (4.25 m, 1000)
extends Node

const LifecycleTests := preload("res://scripts/lifecycle_tests.gd")
const TAG := "hitfx"

var game: Game
var fails := 0
var _cam: Camera3D


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/hit_fx_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	if args.has("--hitfx-look"):
		t._look()
	else:
		t._run()


# Effects alone in front of the camera at a few ages: -- shinonuma --hitfx-test --hitfx-look
func _look() -> void:
	await get_tree().create_timer(1.5).timeout
	game.set_process(false)
	var p := game.player
	var c := LifecycleTests._ahead(game, 2.6) + Vector3.UP * 1.2
	var fwd := c - p.global_position
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var eye := p.global_position + Vector3.UP * 1.5
	for h in ["ee72b935", "a03f2a9e", "ef263f8b", "a8e710ae"]:
		HitFx.play(game, HitFx._frame(c, fwd), h)
		for t in [0.1, 0.4, 1.0]:
			await get_tree().create_timer(t - (0.0 if t == 0.1 else (0.1 if t == 0.4 else 0.4))).timeout
			await _shot("look_%s_%.1f" % [h, t], eye, c)
			await _shot("look_%s_%.1f_side" % [h, t], c + side * 1.5 + Vector3.UP * 0.2, c)
		await get_tree().create_timer(3.0).timeout
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [TAG, "OK" if ok else "FAIL", what])
	fails += int(not ok)


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 400.0
		_cam.fov = 60.0
		game.add_child(_cam)
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	_cam.make_current()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/hitfx_%s.png" % name))
	_cam.clear_current(true)


func _zombie(at: Vector3, face: Vector3) -> Zombie:
	var z: Zombie = LifecycleTests._spawn(game)
	z.global_position = at
	z.max_health = 1e6
	z.health = 1e6
	z.state = Zombie.State.CHASE
	z.look_at(at - face, Vector3.UP)
	z.set_physics_process(false)
	return z


# a side direction with nothing solid for 3 m
func _clear_side(at: Vector3, fwd: Vector3) -> Vector3:
	var space := game.get_world_3d().direct_space_state
	for s in [fwd.cross(Vector3.UP).normalized(), -fwd.cross(Vector3.UP).normalized()]:
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + s * 3.0, 1)).is_empty():
			return s
	return fwd.cross(Vector3.UP).normalized()


func _last() -> String:
	return String(HitFx.history[-1][1]) if not HitFx.history.is_empty() else ""


func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	var p := game.player
	game.set_process(false)   # no round spawns
	var d: Dictionary = HitFx.data()
	_check(not d.is_empty(), "hit_fx.json loaded (%d entities)" % d.get("entities", {}).size())
	# ---------------------------------------------------------------- blood
	var c := LifecycleTests._ahead(game, 2.6)
	var fwd := (c - p.global_position)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var expect := {20.0: "a8e710ae", 100.0: "b73b0896", 200.0: "a8621840", 300.0: "a03f2a9e", 600.0: "a03f2a9e"}
	var z := _zombie(c, -fwd)
	for amount in expect:
		var hit := z.global_position + Vector3.UP * 1.25 - fwd * 0.2
		z.take_damage(amount, false, p, false, hit)
		_check(_last() == expect[amount], "damage %d -> %s (got %s)" % [amount, expect[amount], _last()])
		var fx := z.get_node_or_null("HitFx_" + String(expect[amount])) as Node3D
		_check(fx != null and fx.global_basis.z.dot(fwd) > 0.9, "frame z along the shot")
		await get_tree().create_timer(0.25).timeout
		var eye := p.global_position + Vector3.UP * 1.5
		await _shot("blood_%d_front" % amount, eye, hit)
		await _shot("blood_%d_side" % amount, hit + side * 2.0 + Vector3.UP * 0.2, hit)
		await get_tree().create_timer(1.2).timeout
	# no position (splash): nothing
	var n := HitFx.history.size()
	z.take_damage(10.0, false, p)
	_check(HitFx.history.size() == n, "no effect without a hit position")
	# explosive: ef263f8b at the origin
	Explosion.blast(game, z.global_position + fwd * 0.5, p, Betty.BLAST)
	_check(_last() == "ef263f8b", "explosive hit -> ef263f8b (got %s)" % _last())
	await get_tree().create_timer(0.3).timeout
	await _shot("blood_explosive_side", z.global_position + side * 1.4 + Vector3.UP * 1.0, z.global_position + Vector3.UP * 0.5)
	await _shot("blood_explosive_front", p.global_position + Vector3.UP * 1.5, z.global_position + Vector3.UP * 0.5)
	await get_tree().create_timer(1.0).timeout
	# limbs
	var z2 := _zombie(c + side * 1.2, -fwd)
	z2.lose_head()
	z2.lose_arm("left")
	var tags := HitFx.history.slice(-2).map(func(e): return e[1])
	_check(tags == ["limb_head", "limb_left"], "limb effects %s" % [tags])
	await get_tree().create_timer(0.4).timeout
	await _shot("limbs_front", p.global_position + Vector3.UP * 1.5, z2.global_position + Vector3.UP * 1.3)
	await _shot("limbs_side", z2.global_position - side * 1.0 + fwd * -0.6 + Vector3.UP * 1.6, z2.global_position + Vector3.UP * 1.3)
	z.queue_free()
	z2.queue_free()
	await get_tree().create_timer(2.5).timeout
	_check(get_tree().get_nodes_in_group("zombies").all(func(x): return x.find_children("HitFx_*", "", true, false).is_empty()), "effects freed when over")
	# ---------------------------------------------------------------- impacts
	var space := game.get_world_3d().direct_space_state
	var eye2 := p.global_position + Vector3.UP * 1.5
	var wall := {}
	for k in 16:
		var a := TAU * k / 16.0
		var dir := Vector3(sin(a), -0.1, cos(a)).normalized()
		var q := PhysicsRayQueryParameters3D.create(eye2, eye2 + dir * 20.0, 1)
		q.exclude = [p.get_rid()]
		var h := space.intersect_ray(q)
		if not h.is_empty() and absf((h["normal"] as Vector3).y) < 0.5 and eye2.distance_to(h["position"]) > 1.5:
			wall = h
			break
	_check(not wall.is_empty(), "a wall to shoot")
	if not wall.is_empty():
		var at: Vector3 = wall["position"]
		var nrm: Vector3 = wall["normal"]
		var wside := nrm.cross(Vector3.UP).normalized()
		var guns := {"thompson": "249fa16c", "kar98": "aa05b114", "shotgun": "241aa8fe"}
		var i := 0
		for g in guns:
			p.give_weapon(g)
			var spot := at + wside * (i - 1) * 0.6
			game.spawn_impact(spot, nrm)
			_check(game.level_name in Game.IMPACT_EFFECTS and _last() == guns[g], "%s impact -> %s (got %s)" % [g, guns[g], _last()])
			i += 1
		await get_tree().create_timer(0.15).timeout
		await _shot("impact_front", at + nrm * 1.6 + Vector3.UP * 0.1, at)
		await _shot("impact_side", at + nrm * 0.9 + wside * 1.3 + Vector3.UP * 0.2, at)
		await get_tree().create_timer(0.3).timeout
		await _shot("impact_late_side", at + nrm * 0.9 + wside * 1.3 + Vector3.UP * 0.2, at)
	# ---------------------------------------------------------------- flashes
	p.give_weapon("thompson")
	var w := p.weapon()
	w["upgraded"] = false
	_check(String(HitFx.flash_spec(w).get("tex", "")) == "943ed6eb", "thompson flash 943ed6eb")
	w["upgraded"] = true
	_check(String(HitFx.flash_spec(w).get("tex", "")) == "b48c55cb", "Gibs-O-Matic flash b48c55cb (pink)")
	for up in [false, true]:
		w["upgraded"] = up
		p._viewmodel.muzzle_flash()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/hitfx_flash_%s.png" % ("pap" if up else "normal")))
		await get_tree().create_timer(0.2).timeout
	# ---------------------------------------------------------------- sounds, dog, betty
	var zs := _zombie(c, -fwd)
	var mark := HitFx.history.size()
	zs.take_damage(30.0, false, p, false, zs.global_position + Vector3.UP * 1.2)
	zs.take_damage(30.0, false, p, true)
	Explosion.blast(game, zs.global_position, p, Explosion.RAYGUN)
	Explosion.blast(game, zs.global_position, p, Molotov.SPLASH)
	var snds := HitFx.history.slice(mark).map(func(e): return e[1]).filter(func(e): return String(e).begins_with("snd_"))
	_check(snds == ["snd_f889c48a", "snd_f889c48a", "snd_f889c48b"], "hit sounds bullet, knife, splash, none for fire: %s" % [snds])
	zs.queue_free()
	c = LifecycleTests._ahead(game, 2.6)
	fwd = c - p.global_position
	fwd.y = 0.0
	fwd = fwd.normalized()
	side = _clear_side(c + Vector3.UP * 0.8, fwd)
	print("[%s] look spot %s from %s" % [TAG, c, p.global_position])
	var dog := Dog.new()
	dog.setup_dog(c + Vector3.UP * 0.1, p, 1e6, game.level.windows[0])
	game.add_child(dog)
	await get_tree().physics_frame
	dog.set_physics_process(false)
	dog.take_damage(200.0, false, p, false, dog.global_position + Vector3.UP * 0.5)
	_check(_last() == "a8621840" and dog.get_node_or_null("HitFx_a8621840") != null, "dog blood (template 1d1ca339): %s" % _last())
	await get_tree().create_timer(0.3).timeout
	await _shot("dog_front", p.global_position + Vector3.UP * 1.5, dog.global_position + Vector3.UP * 0.5)
	await _shot("dog_side", dog.global_position + side * 1.5 + Vector3.UP * 0.6, dog.global_position + Vector3.UP * 0.5)
	dog.queue_free()
	var bt := Betty.plant(game, c, 0.0, p)
	if bt:
		bt.global_position = c + Vector3.UP * 1.45   # risen (RISE_HEIGHT 1.6 from the planted depth)
		bt.explode()
		_check(_last() == HitFx.EXPLOSION, "betty explosion ee72b935 (%s)" % _last())
		for k in 2:
			await get_tree().create_timer([0.15, 0.6][k]).timeout
			await _shot("betty_%d" % k, p.global_position + Vector3.UP * 1.6, c + Vector3.UP * 0.5)
			await _shot("betty_%d_side" % k, c + side * 3.0 + Vector3.UP * 1.0, c + Vector3.UP * 0.5)
	else:
		_check(false, "betty planted")
	await get_tree().create_timer(2.0).timeout
	# ---------------------------------------------------------------- Mustang & Sally
	p.give_weapon("colt45")
	var m := p.weapon()
	m["upgraded"] = true
	m["mag"] = 6
	var target := _zombie(LifecycleTests._ahead(game, 5.0), -fwd)
	var near := _zombie(target.global_position + side * 2.0, -fwd)
	var far := _zombie(target.global_position - side * 5.5, -fwd)
	for zz in [target, near, far]:
		zz.max_health = 500.0
		zz.health = 500.0
	LifecycleTests._aim(p, target.global_position + Vector3.UP * 1.2)
	await get_tree().physics_frame
	p._fire(m, Weapons.stats_of(m))
	var t := 0.0
	while MustangBolt.last_result.is_empty() and t < 2.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(not MustangBolt.last_result.is_empty(), "mustang round exploded (%.2f s)" % t)
	for k in 3:
		await get_tree().create_timer([0.05, 0.25, 0.6][k]).timeout
		await _shot("mustang_%d" % k, p.global_position + Vector3.UP * 1.6, target.global_position + Vector3.UP * 0.8)
	_check(target.state == Zombie.State.DEAD and near.state == Zombie.State.DEAD, "target and the zombie 2 m away killed")
	_check(far.state != Zombie.State.DEAD, "zombie 5.5 m away untouched (%.0f)" % far.health)
	print("[%s] mustang: %s" % [TAG, MustangBolt.last_result])
	print("[%s] done, %d fails" % [TAG, fails])
	get_tree().quit()
