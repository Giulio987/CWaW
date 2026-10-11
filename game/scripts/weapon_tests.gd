# Tests for grenades / Ray Gun / flamethrower, started from autotest.gd:
#   tools/run_godot.sh 120 -- nacht --autotest 100 --weapon-test grenade|raygun|flame|buy
# Prints OK/FAIL lines and saves screenshots to analysis/preview/wfx_*.png.
class_name WeaponTests


static func run(at: Node) -> void:
	var game: Game = at.game
	await game.level.navigation_ready
	await at.get_tree().create_timer(2.5).timeout   # round 1 has started (grenade refill)
	game.set_process(false)
	var args := OS.get_cmdline_user_args()
	var which := args[args.find("--weapon-test") + 1] if args.find("--weapon-test") + 1 < args.size() else "grenade"
	match which:
		"grenade":
			await _grenade(at, game)
		"raygun":
			await _raygun(at, game)
		"flame":
			await _flame(at, game)
		"buy":
			await _buy(at, game)
		"fx":
			await _fx(at, game)
		"fx1":
			await _fx1(at, game)
		"model":
			await _model(at, game)
	at.get_tree().quit()


static func _snap(at: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	at.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/wfx_%s.png" % name))


static func _wait(at: Node, t: float) -> void:
	await at.get_tree().create_timer(t).timeout


static func _zombie(game: Game, pos: Vector3, hp: float) -> Zombie:
	var z := Zombie.new()
	z.setup(pos, game.level.windows[0], game.player, hp, false)
	game.add_child(z)
	z.state = Zombie.State.CHASE
	z.set_physics_process(false)
	z.look_at(Vector3(game.player.global_position.x, pos.y, game.player.global_position.z), Vector3.UP, true)
	return z


static func _floor(game: Game, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p - Vector3.UP * 3.0, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else p


# free distance in front of the player (to place things inside the room)
static func _room_ahead(game: Game, max_d: float) -> float:
	var p := game.player
	var from := p.global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from - p.global_basis.z * max_d, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	return max_d if hit.is_empty() else from.distance_to(hit["position"]) - 0.5


static func _aim(p: Player, target: Vector3) -> void:
	var cam := p.get_viewport().get_camera_3d()
	var to := target - cam.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	cam.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


# side view camera looking at a point
static func _side_cam(at: Node, game: Game, look: Vector3, offset: Vector3) -> Camera3D:
	var c := Camera3D.new()
	c.fov = 70
	game.add_child(c)
	c.global_position = look + offset
	c.look_at(look, Vector3.UP)
	c.make_current()
	return c


static func _grenade(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	var belt := GrenadeBelt.of(p)
	print("[wfx] grenades at round %d: %d %s" % [game.round_number, belt.count, "OK" if belt.count == 2 else "FAIL"])
	var d := minf(_room_ahead(game, 7.0), 5.0)
	var fwd := -p.global_basis.z
	var side := p.global_basis.x
	var c := _floor(game, p.global_position + fwd * d)
	print("[wfx] blast centre %.1f m ahead" % d)
	var zs := {
		"centre": _zombie(game, c + side * 0.4, 150.0),
		"near": _zombie(game, c - side * 1.0, 150.0),
		"mid": _zombie(game, c + side * 2.2, 150.0),
		"tough_a": _zombie(game, c - side * 2.6, 2e5),
		"tough_b": _zombie(game, c + fwd * 0.1 + side * 3.2, 2e5),
		"far": _zombie(game, c - side * 6.5, 150.0),
	}
	await _wait(at, 0.4)
	var g := Grenade.spawn(game, c + Vector3.UP * 0.3, Vector3.ZERO, 0.8, p)
	await _wait(at, 0.3)
	await _snap(at, "grenade_0_before")
	await _wait(at, 0.55)
	await _snap(at, "grenade_1_boom")
	await _wait(at, 0.3)
	await _snap(at, "grenade_2_after")
	var cam := _side_cam(at, game, c + Vector3.UP * 0.8, side * 4.0 + Vector3.UP * 1.5 - fwd * 1.0)
	await _wait(at, 0.8)
	await _snap(at, "grenade_3_side")
	cam.queue_free()
	p.get_children().filter(func(n): return n is Camera3D)[0].make_current()
	var r := Grenade.last_result
	var st := {}
	for k in zs:
		var z: Zombie = zs[k]
		st[k] = "dead" if z.state == Zombie.State.DEAD else ("crawler" if z.crawler else "alive") + "(%.0f)" % z.health
	print("[wfx] grenade result %s states %s" % [r, st])
	var ok: bool = zs["centre"].state == Zombie.State.DEAD and zs["near"].state == Zombie.State.DEAD \
		and zs["far"].state != Zombie.State.DEAD and zs["far"].health == 150.0 \
		and (zs["tough_a"].health < 2e5 or zs["tough_b"].health < 2e5)
	print("[wfx] grenade damage %s" % ("OK" if ok else "FAIL"))
	print("[wfx] player hurt by far grenade: %s" % ("no OK" if r["player"] == 0.0 else "yes FAIL"))

	# a real throw from the belt
	for k in zs:
		if is_instance_valid(zs[k]) and zs[k].state != Zombie.State.DEAD:
			zs[k].take_damage(1e7, false, p)
	var before := belt.count
	_aim(p, c + Vector3.UP * 2.0)
	belt.set_held(true)
	await _wait(at, 0.4)
	await _snap(at, "grenade_4_cook")
	belt.set_held(false)
	await _wait(at, 0.25)
	var flying := game.get_children().filter(func(n): return n is Grenade)
	print("[wfx] throw: count %d -> %d, grenades in flight %d %s" % [before, belt.count, flying.size(), "OK" if belt.count == before - 1 and flying.size() == 1 else "FAIL"])
	await _snap(at, "grenade_5_flight")
	var land: Vector3 = flying[0].global_position if flying.size() > 0 else Vector3.ZERO
	await _wait(at, 1.4)
	if flying.size() > 0 and is_instance_valid(flying[0]):
		land = flying[0].global_position
	print("[wfx] thrown grenade at %.1f m from player before exploding" % land.distance_to(p.global_position))
	await _wait(at, 1.6)
	await _snap(at, "grenade_6_thrown_boom")
	print("[wfx] thrown grenade exploded: %s" % ("OK" if game.get_children().filter(func(n): return n is Grenade).is_empty() else "FAIL"))

	# cooked too long: blows up in hand and hurts the player
	await _wait(at, 1.0)
	p.health = 100.0
	belt.set_count(1)
	belt.set_held(true)
	await _wait(at, Grenade.FUSE + 0.3)
	belt.set_held(false)
	print("[wfx] cooked in hand: player hp %.0f, last %s %s" % [p.health, Grenade.last_result, "OK" if p.health < 100.0 or p.dead else "FAIL"])


static func _raygun(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	p.give_weapon("raygun")
	await _wait(at, 0.3)
	var d := minf(_room_ahead(game, 8.0), 6.0)
	var fwd := -p.global_basis.z
	var side := p.global_basis.x
	var c := _floor(game, p.global_position + fwd * d)
	var target := _zombie(game, c, 900.0)
	var splash := _zombie(game, c + side * 1.0, 200.0)
	var outside := _zombie(game, c - side * 3.0, 200.0)
	await _wait(at, 0.4)
	var h0 := outside.health
	_aim(p, c + Vector3.UP * 1.1)
	p._fire(p.weapon(), Weapons.stats_of(p.weapon()))
	await at.get_tree().physics_frame
	await at.get_tree().physics_frame
	await _snap(at, "raygun_0_flight")
	await _wait(at, 0.03)
	await _snap(at, "raygun_1_impact")
	await _wait(at, 0.4)
	print("[wfx] raygun direct=%s splash=%s outside=%s(%.0f) %s" % [Zombie.State.keys()[target.state], Zombie.State.keys()[splash.state],
		Zombie.State.keys()[outside.state], outside.health,
		"OK" if target.state == Zombie.State.DEAD and splash.state == Zombie.State.DEAD and outside.health == h0 else "FAIL"])
	# wall shots from a side camera
	var cam := _side_cam(at, game, c + Vector3.UP * 1.0, side * 3.0 + Vector3.UP * 0.6 - fwd * 2.0)
	for i in 3:
		p._cooldown = 0.0
		_aim(p, c + side * (i - 1) * 0.6 + fwd * 2.0 + Vector3.UP * 1.0)
		p._fire(p.weapon(), Weapons.stats_of(p.weapon()))
		await _wait(at, 0.06)
	await _snap(at, "raygun_2_side")
	await _wait(at, 0.5)
	cam.queue_free()
	p.get_children().filter(func(n): return n is Camera3D)[0].make_current()
	# self damage: shoot the floor at the player's feet
	p.health = 100.0
	var cam3 := p.get_viewport().get_camera_3d()
	cam3.rotation.x = -1.45
	p._fire(p.weapon(), Weapons.stats_of(p.weapon()))
	await _wait(at, 0.3)
	await _snap(at, "raygun_3_feet")
	print("[wfx] raygun at own feet: hp %.0f %s" % [p.health, "OK" if p.health < 100.0 else "FAIL"])
	cam3.rotation.x = 0.0


static func _flame(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	p.give_weapon("flamethrower")
	await _wait(at, 0.3)
	var d := minf(_room_ahead(game, 6.0), 4.0)
	var fwd := -p.global_basis.z
	var side := p.global_basis.x
	var a := _zombie(game, _floor(game, p.global_position + fwd * d), 600.0)
	var b := _zombie(game, _floor(game, p.global_position + fwd * (d * 0.6) + side * 0.3), 600.0)
	var off := _zombie(game, _floor(game, p.global_position + fwd * 2.0 + side * 3.0), 600.0)
	await _wait(at, 0.3)
	var h0 := off.health
	_aim(p, a.global_position + Vector3.UP * 1.0)
	p.fire_held = true
	await _wait(at, 0.6)
	await _snap(at, "flame_0_jet")
	var cam := _side_cam(at, game, p.global_position + fwd * d * 0.5 + Vector3.UP * 1.2, side * 3.5 + Vector3.UP * 0.8)
	await _wait(at, 0.4)
	await _snap(at, "flame_1_side")
	p.fire_held = false
	print("[wfx] flame: a burning=%s hp=%.0f, b burning=%s hp=%.0f, off-axis burning=%s hp=%.0f" % [a.has_node("Burning"), a.health,
		b.has_node("Burning"), b.health, off.has_node("Burning"), off.health])
	var ok1 := a.has_node("Burning") and b.has_node("Burning") and not off.has_node("Burning") and off.health == h0
	await _wait(at, 1.0)
	await _snap(at, "flame_2_afterburn")
	cam.queue_free()
	p.get_children().filter(func(n): return n is Camera3D)[0].make_current()
	await _wait(at, 2.5)
	print("[wfx] flame afterburn: a %s(%.0f) b %s(%.0f) %s" % [Zombie.State.keys()[a.state], a.health, Zombie.State.keys()[b.state], b.health,
		"OK" if ok1 and a.health < h0 and b.health < h0 else "FAIL"])
	print("[wfx] points %d" % p.points)


static func _buy(at: Node, game: Game) -> void:
	var p := game.player
	var belt := GrenadeBelt.of(p)
	var buys := game.level.interactables.filter(func(o): return o is GrenadeBuy)
	print("[wfx] grenade buys: %d" % buys.size())
	if buys.is_empty():
		print("[wfx] buy FAIL (none)")
		return
	var gb: GrenadeBuy = buys[0]
	belt.set_count(1)
	p.points = 1000
	# stand next to it (step off the wall towards open space)
	var spot := gb.use_point
	var best := spot
	var space := game.get_world_3d().direct_space_state
	for i in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * PI / 4.0)
		var q := PhysicsRayQueryParameters3D.create(spot, spot + dir * 1.2, 1)
		if space.intersect_ray(q).is_empty():
			best = spot + dir * 1.0
			break
	p.global_position = _floor(game, best)
	_aim(p, gb.use_point)
	await _wait(at, 0.3)
	p._update_prompt()
	print("[wfx] prompt '%s' target %s" % [p.prompt, p._interaction_target()])
	await _snap(at, "buy_0")
	var t = p._interaction_target()
	if t is GrenadeBuy:
		t.interact(p)
	await _wait(at, 0.2)
	await _snap(at, "buy_1")
	var icons: Control = belt._icons
	print("[wfx] icons rect %s children %d visible %s tex %s" % [icons.get_global_rect(), icons.get_child_count(), icons.is_visible_in_tree(), belt._icon_tex.get_size()])
	print("[wfx] after buy: grenades %d points %d %s" % [belt.count, p.points, "OK" if belt.count == 4 and p.points == 750 else "FAIL"])
	p._update_prompt()
	print("[wfx] prompt when full '%s' %s" % [p.prompt, "OK" if p.prompt == "" or not "granate" in p.prompt else "FAIL"])


# explosion visuals only, several frames
static func _fx(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	var d := minf(_room_ahead(game, 7.0), 4.0)
	var c := _floor(game, p.global_position - p.global_basis.z * d)
	Explosion.frag_effect(game, c)
	for i in 5:
		await _wait(at, 0.08 + i * 0.1)
		await _snap(at, "fx_frag_%d" % i)
	await _wait(at, 1.0)
	Explosion.raygun_effect(game, c + Vector3.UP, false)
	await _wait(at, 0.05)
	await _snap(at, "fx_ray_0")
	await _wait(at, 0.15)
	await _snap(at, "fx_ray_1")


static func _fx1(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	var c := _floor(game, p.global_position - p.global_basis.z * 3.0) + Vector3.UP * 1.0
	var e := WeaponFx.particles("1d980a04", {"amount": 6, "lifetime": 5.0, "size": 0.12, "speed": 0.0, "one_shot": false, "sphere": 0.5})
	game.add_child(e)
	e.global_position = c - p.global_basis.x * 0.8
	e.emitting = true
	var f := WeaponFx.particles("a03e6a9a", {"amount": 6, "lifetime": 5.0, "size": 0.12, "speed": 0.0, "one_shot": false, "sphere": 0.5, "additive": false})
	game.add_child(f)
	f.global_position = c + p.global_basis.x * 0.8
	f.emitting = true
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3.ONE * 0.12
	mi.mesh = b
	game.add_child(mi)
	mi.global_position = c
	await _wait(at, 1.0)
	await _snap(at, "fx1")


static func _model(at: Node, game: Game) -> void:
	var p := game.player
	var cam := p.get_viewport().get_camera_3d()
	var root := (load("res://assets/models/ingame/player.glb") as PackedScene).instantiate()
	var i := 0
	for n in ["c53574cc", "f54310eb"]:
		var m := root.find_child(n, true, false) as MeshInstance3D
		if m == null:
			print("[wfx] model %s missing" % n)
			continue
		print("[wfx] model %s aabb %s xf %s" % [n, m.get_aabb(), m.transform])
		var d := m.duplicate() as Node3D
		d.transform = Transform3D.IDENTITY
		cam.add_child(d)
		d.position = Vector3(-0.15 + i * 0.3, 0.0, -0.8)
		i += 1
	root.free()
	await _wait(at, 0.3)
	await _snap(at, "model")
