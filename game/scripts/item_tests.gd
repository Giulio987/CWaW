# Checks for the Bouncing Betty, the Bowie knife and the .357 Magnum (screenshots in
# analysis/preview/item_*.png):
#   -- derriese --item-test betty    wall buy, plant (first-person frames), trigger, blast
#   -- derriese --item-test bowie    wall buy, model in the slash, one-hit kill
#   -- nacht --item-test magnum      box pools, stats, a shot on a zombie
#   -- nacht --item-test boxbetty    box gives the betties on Nacht
extends Node

var game: Game
var fails := 0
var _cam: Camera3D


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/item_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	var i := args.find("--item-test")
	var which := args[i + 1] if i + 1 < args.size() else "betty"
	t._run.call_deferred(which)


func _check(ok: bool, what: String) -> void:
	print("[item] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/item_%s.png" % name))


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 400.0
		_cam.near = 0.02
		game.add_child(_cam)
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	_cam.make_current()
	for k in 3:
		await get_tree().process_frame
	await _snap(name)
	_cam.clear_current(true)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _run(which: String) -> void:
	await game.level.wait_navigation()
	await _wait(2.0)
	game.player.health = 1e6
	game.player.max_health = 1e6
	game.set_process(false)   # no round spawns
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	match which:
		"betty":
			await _betty()
		"bowie":
			await _bowie()
		"magnum":
			await _magnum()
		"boxbetty":
			await _box_betty()
		"savewrite":
			await _save_write()
		"savecheck":
			await _save_check()
	print("[item] done, %d failures" % fails)
	get_tree().quit()


func _go_to(target: Vector3) -> void:
	var p := game.player
	var q := PhysicsRayQueryParameters3D.create(target + Vector3.UP, target + Vector3.DOWN * 3.0, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	p.global_position = (hit["position"] if not hit.is_empty() else target) + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	for k in 4:
		await get_tree().physics_frame


func _betty() -> void:
	var p := game.player
	var belt := BettyBelt.of(p)
	_check(belt != null and belt.count == 0 and not belt.unlocked, "no betties at the start")
	var buy: BettyBuy = null
	for o in game.level.interactables:
		if o is BettyBuy:
			buy = o
	_check(buy != null and buy.cost == 1000, "CActionBuyBettySpec wall buy, cost %s" % (buy.cost if buy else -1))
	if buy == null:
		return
	await _go_to(buy.use_point)
	p.points = 5000
	_check(buy.usable_from(p.global_position) and buy.prompt(p) != "", "prompt: %s" % buy.prompt(p))
	buy.interact(p)
	_check(belt.count == 2 and belt.unlocked and p.points == 4000, "bought: %d betties, %d points" % [belt.count, p.points])
	# walk away from the wall a bit, look slightly down and plant
	var fwd := Vector3(-p.global_basis.z.x, 0, -p.global_basis.z.z).normalized()
	p.rotation.y += PI   # face away from the wall
	await _wait(0.2)
	p.get("_camera").rotation.x = -0.6
	_check(belt.start_plant(), "planting started")
	await _wait(0.45)
	await _snap("betty_fp_raise")
	await _wait(0.9)
	await _snap("betty_fp_prime")
	await _wait(0.85)
	await _snap("betty_fp_plant")
	await _wait(0.9)
	var betties := get_tree().get_nodes_in_group("betties")
	_check(betties.size() == 1 and belt.count == 1, "planted: %d in the world, %d left" % [betties.size(), belt.count])
	if betties.is_empty():
		return
	var b: Betty = betties[0]
	var g := b._ground
	_check(absf(b.global_position.y - (g.y - Betty.PLANTED_DEPTH)) < 0.01, "planted %.3f m into the ground" % (g.y - b.global_position.y))
	await _snap("betty_fp_after")
	var icons: HBoxContainer = belt.get("_icons")
	print("[item] hud icons: %d, rect %s, visible %s" % [icons.get_child_count(), icons.get_global_rect(), icons.is_visible_in_tree()])
	# look at the betty from the front and the side
	var side := Vector3(-fwd.z, 0, fwd.x)
	await _shot("betty_planted_front", g + fwd * 1.2 + Vector3.UP * 0.5, g + Vector3.UP * 0.1)
	await _shot("betty_planted_side", g + side * 1.2 + Vector3.UP * 0.5, g + Vector3.UP * 0.1)
	# zombies: z1 at 1.4 m then 1.1 m, z2 at 3.5 m (inside 4.25), z3 at 5.5 m (outside)
	var d2 := _free_dir(g, 6.0)
	var z1 := WeaponTests._zombie(game, WeaponTests._floor(game, g + d2 * 1.4), 900.0)
	var z2 := WeaponTests._zombie(game, WeaponTests._floor(game, g + d2 * 3.5), 900.0)
	var z3 := WeaponTests._zombie(game, WeaponTests._floor(game, g + d2 * 5.5), 900.0)
	await _wait(0.3)
	_check(not b.triggered, "not triggered with a zombie 1.4 m away (radii 300 + 180 units = 1.2 m)")
	z1.global_position = WeaponTests._floor(game, g + d2 * 1.1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(b.triggered, "triggered by a zombie at 1.1 m")
	await _wait(0.15)
	if is_instance_valid(b):
		await _shot("betty_bounce_side", g + side * 3.5 + Vector3.UP * 1.2, g + Vector3.UP * 0.9)
	await _wait(0.5)
	_check(not is_instance_valid(b) or b.exploded, "exploded after rising %.2f m" % Betty.RISE_HEIGHT)
	var res := Betty.last_result
	_check(z1.state == Zombie.State.DEAD and z2.state == Zombie.State.DEAD, "zombies within 4.25 m killed (1000 > 900): %s" % res)
	_check(is_instance_valid(z3) and z3.state != Zombie.State.DEAD, "zombie at 5.5 m untouched")
	_check(Achievements.instance == null or Game.no_achievements() or Achievements.instance.unlocked.has(Betty.ACH_TWO_AT_ONCE), "achievement 56 (2 kills with one betty)")
	# round refill: SetPlayerBetties(2)
	belt.set_count(0)
	belt._round_seen = game.round_number - 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(belt.count == 2, "refilled to 2 at the next round")
	var st := belt.save_state()
	_check(bool(st["unlocked"]) and int(st["count"]) == 2, "save state %s" % st)


func _free_dir(c: Vector3, d: float) -> Vector3:
	var space := game.get_world_3d().direct_space_state
	for k in 16:
		var a := TAU * k / 16.0
		var dir := Vector3(sin(a), 0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(c + Vector3.UP, c + Vector3.UP + dir * d, 1)
		if space.intersect_ray(q).is_empty():
			return dir
	return Vector3(0, 0, 1)


func _bowie() -> void:
	var p := game.player
	var bk := BowieKnife.of(p)
	var buy: BowieBuy = null
	for o in game.level.interactables:
		if o is BowieBuy:
			buy = o
	var still_generic := game.wall_buys.any(func(w): return String(w.get("weapon", "")) == BowieKnife.WEAPON_HASH)
	_check(buy != null and buy.cost == 3000 and not still_generic, "BuyWeaponBowie wall buy, cost %s" % (buy.cost if buy else -1))
	_check(is_equal_approx(p.knife_damage(null), 150.0), "knife 150 before")
	# base knife slash frame for comparison
	p.get("_camera").rotation.x = -0.1
	p.melee()
	await _wait(0.3)
	await _snap("knife_slash")
	await _wait(1.0)
	if buy == null:
		return
	await _go_to(buy.use_point)
	p.points = 5000
	_check(buy.usable_from(p.global_position) and buy.prompt(p) != "", "prompt: %s" % buy.prompt(p))
	buy.interact(p)
	_check(bk.owned and p.points == 2000 and buy.prompt(p) == "", "bought (points %d)" % p.points)
	_check(is_equal_approx(p.knife_damage(null), 1000.0), "bowie damage 1000")
	p.rotation.y += PI
	await _wait(0.2)
	p.get("_camera").rotation.x = -0.1
	for f in 5:
		p.set("_melee_cooldown", 0.0)
		if f == 0:
			p.melee()   # nothing in reach: the slash (state 40, 0.633 s)
		await _wait(0.1)
		await _snap("bowie_slash_%d" % f)
	await _wait(1.0)
	# one stab kills a 900 hp zombie in front
	var fwd := -p.global_basis.z
	fwd.y = 0
	var z := WeaponTests._zombie(game, WeaponTests._floor(game, p.global_position + fwd.normalized() * 1.0), 900.0)
	await _wait(0.2)
	p.set("_melee_cooldown", 0.0)
	p.melee()
	await _wait(0.3)
	_check(z.state == Zombie.State.DEAD, "bowie kills a 900 hp zombie in one stab")
	_check(bool(bk.save_state()["owned"]), "save state %s" % bk.save_state())


func _magnum() -> void:
	var p := game.player
	for m in ["nacht", "verruckt", "shinonuma", "derriese"]:
		var box := MysteryBox.new()
		var lv := Level.new()
		lv.level_name = m
		box.level = lv
		var pool := box.pool()
		_check("magnum" in pool and (("betty" in pool) == (m == "nacht")), "%s box: magnum %s, betty %s" % [m, "magnum" in pool, "betty" in pool])
		box.free()
		lv.free()
	var s := Weapons.stats("magnum")
	_check(s["damage"] == 1060 and s["mag"] == 6 and s["reserve"] == 80, "stats %s" % s)
	_check(Viewmodel.pairs()["weapons"].has("magnum"), "arms pair %s" % Viewmodel.pairs()["weapons"].get("magnum", {}).get("model", "-"))
	p.give_weapon("magnum")
	await _wait(1.0)
	_check(p.weapon()["name"] == "magnum" and p.weapon()["mag"] == 6, "held: %s" % p.weapon())
	var fwd := -p.global_basis.z
	fwd.y = 0
	var z := WeaponTests._zombie(game, WeaponTests._floor(game, p.global_position + fwd.normalized() * 3.0), 3000.0)
	await _wait(0.3)
	var cam := p.get("_camera") as Camera3D
	var aim: Vector3 = z.global_position + Vector3.UP * 1.3 - cam.global_position
	p.rotation.y = atan2(-aim.x, -aim.z)
	cam.rotation.x = atan2(aim.y, Vector2(aim.x, aim.z).length())
	await get_tree().physics_frame
	var hp := z.health
	p._fire(p.weapon(), Weapons.stats_of(p.weapon()))
	await get_tree().physics_frame
	_check(hp - z.health >= 300.0, "one shot: %.0f damage (1060 x location, min 300)" % (hp - z.health))
	_check(Sfx.instance._index["guns"].get("magnum", "") == "d1cfc72f", "fire sound %s" % Sfx.instance._index["guns"].get("magnum", ""))


func _box_betty() -> void:
	var p := game.player
	BettyBelt.give(p)
	var belt := BettyBelt.of(p)
	_check(belt.unlocked and belt.count == 2, "box: betties unlocked, %d" % belt.count)
	var b := Betty.model()
	_check(b != null and b.find_children("*", "AnimationPlayer").size() > 0, "in-hand betty model with its animations")
	b.free()


# -- derriese --item-test savewrite, then -- derriese --item-test savecheck --resume
func _save_write() -> void:
	var p := game.player
	BettyBelt.give(p)
	var fwd := -p.global_basis.z
	fwd.y = 0
	var b := Betty.plant(game, p.global_position + fwd.normalized() * 2.0, 0.3, p)
	_check(b != null, "betty planted for the save")
	BowieKnife.of(p).give()
	p.give_weapon("magnum")
	await _wait(0.5)
	_check(SaveGame.save(game), "saved")
	var d := SaveGame.load_save()
	var prov: Dictionary = d.get("providers", {})
	print("[item] providers: %s / %s" % [prov.get("betty_belt"), prov.get("bowie_knife")])


func _save_check() -> void:
	var p := game.player
	var belt := BettyBelt.of(p)
	_check(belt.unlocked and belt.count == 2, "betties after resume: unlocked %s, %d" % [belt.unlocked, belt.count])
	_check(get_tree().get_nodes_in_group("betties").size() == 1, "planted betty restored (%d)" % get_tree().get_nodes_in_group("betties").size())
	_check(BowieKnife.of(p).owned and is_equal_approx(p.knife_damage(null), 1000.0), "bowie restored")
	_check(p.weapons.any(func(w): return w["name"] == "magnum"), "magnum restored: %s" % [p.weapons])
