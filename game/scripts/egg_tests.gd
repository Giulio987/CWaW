# Easter eggs (radio_egg.gd) and Monkey Bomb (monkey_bomb.gd) tests, run by extra_tests.gd:
#   tools/run_godot.sh 120 -- nacht --autotest 110 --egg-test      (any map; --egg-log prints hits)
#   tools/run_godot.sh 90 -- derriese --autotest 80 --monkey-test
# The egg test stands the player where it can see each trigger and fires a real
# shot (Player._fire), then checks the Lua's effect on the sound emitters.
class_name EggTests


static func _check(ok: bool, what: String) -> void:
	ExtraTests._check(ok, what)


static func _wait(at: Node, s: float) -> void:
	await at.get_tree().create_timer(s).timeout


# Stand where the trigger centre is in plain sight, 1.2..3.5 m away, aiming at it.
static func _stand_facing(at: Node, game: Game, c: Vector3) -> bool:
	var p := game.player
	var space := p.get_world_3d().direct_space_state
	for dist in [2.5, 1.8, 3.5, 1.2]:
		for k in 16:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0)
			var probe := c + dir * float(dist)
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * 2.5, 1))
			if down.is_empty():
				continue
			var feet: Vector3 = down["position"]
			var eye := feet + Vector3.UP * 1.6
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.2, eye, 1)).is_empty():
				continue
			var los := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, c, 1))
			if not los.is_empty() and (los["position"] as Vector3).distance_to(c) > 0.4:
				continue
			print("[egg] aim at %s from %s" % [c.snapped(Vector3.ONE * 0.01), feet.snapped(Vector3.ONE * 0.01)])
			p.global_position = feet + Vector3.UP * 0.05
			p.velocity = Vector3.ZERO
			var to := c - eye
			p.rotation.y = atan2(-to.x, -to.z)
			p.get_viewport().get_camera_3d().rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
			await at.get_tree().physics_frame
			await at.get_tree().physics_frame
			# re-aim after the body settled
			eye = p.global_position + Vector3.UP * 1.6
			to = c - eye
			p.rotation.y = atan2(-to.x, -to.z)
			p.get_viewport().get_camera_3d().rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
			await at.get_tree().physics_frame
			return true
	return false


static func _shoot(at: Node, game: Game, eggs: RadioEggs, n: String, snap := true) -> bool:
	var t: RadioEggs.DamageTrigger = eggs.triggers.get(n)
	if t == null:
		_check(false, "trigger %s exists" % n)
		return false
	if not await _stand_facing(at, game, t.centre()):
		_check(false, "found a spot to shoot %s" % n)
		return false
	var p := game.player
	if snap:
		await ExtraTests._snap(at, "egg_%s" % n)
	var before := eggs.log_hits.size()
	p._cooldown = 0.0
	p._reloading = 0.0
	p.weapon()["mag"] = 8
	p._fire(p.weapon(), Weapons.stats_of(p.weapon()))
	await at.get_tree().physics_frame
	var hit: bool = eggs.log_hits.size() > before and eggs.log_hits[-1] == n
	if not hit:
		var cam := p.get_viewport().get_camera_3d()
		var sp := p.get_world_3d().direct_space_state
		var w := sp.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 10.0, 1 | 2, [p.get_rid()]))
		var e := sp.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 10.0, RadioEggs.TRIGGER_LAYER))
		print("[egg] miss: cam %s, world hit %s, trigger hit %s, centre %s" % [cam.global_position, w.get("position"), e.get("position"), t.centre()])
	_check(hit, "shot %s (%s)" % [n, "triggered" if hit else "no hit"])
	return hit


static func _on(eggs: RadioEggs, n: String) -> bool:
	return eggs.emitters.has(n) and eggs.emitters[n].playing()


static func eggs(at: Node, game: Game) -> void:
	game.set_process(false)
	var p := game.player
	p.health = 1e9
	var eggs := game.get_node_or_null("RadioEggs") as RadioEggs
	_check(eggs != null, "RadioEggs node")
	if eggs == null:
		return
	print("[egg] triggers %s, emitters %s" % [eggs.triggers.keys(), eggs.emitters.keys()])
	match game.level_name:
		"nacht":
			_check(eggs.triggers.size() == 1 and eggs.emitters.size() == 3, "radio + 3 tracks")
			for step in [1, 2, 3, 4]:
				await _shoot(at, game, eggs, "RadioVolume", step == 1)
				await _wait(at, 0.3)
				for k in [1, 2, 3]:
					var want: bool = k == step
					_check(_on(eggs, "RadioTrack%d" % k) == want, "hit %d: RadioTrack%d %s" % [step, k, "on" if want else "off"])
				if step == 1:
					await _wait(at, 2.0)   # static (1.3 s) then the song
					_check(_on(eggs, "RadioTrack1") and eggs.emitters["RadioTrack1"]._step == 1, "track 1 past the static")
		"derriese":
			_check(eggs.triggers.size() == 8 and eggs.emitters.size() == 8, "8 radios")
			for i in range(1, 9):
				await _shoot(at, game, eggs, "Radio%dTrigger" % i)
				await _wait(at, 0.2)
				_check(_on(eggs, "Radio%dSound" % i), "Radio%dSound playing" % i)
				_check(not eggs.triggers["Radio%dTrigger" % i].enabled, "Radio%dTrigger disabled" % i)
		"shinonuma":
			_check(eggs.triggers.size() == 7, "7 triggers")
			_check(eggs.emitters["TelephoneOffHookEmitter"].enabled and eggs.emitters["TelephoneNoiseEmitter1"].enabled, "phone off-hook and meteor hum at start")
			await _shoot(at, game, eggs, "MeteorTrigger")
			_check(eggs.meteor_shot, "meteor shot")
			for r in ["StartRadio1", "StartRadio2", "StartRadio3"]:
				await _shoot(at, game, eggs, r + "Trigger")
				await _wait(at, 0.2)
			_check(not _on(eggs, "StartRadio1Static1") and not _on(eggs, "StartRadio2Static2") and _on(eggs, "StartRadio3Message"),
				"start radios: statics off, third plays the message")
			await _shoot(at, game, eggs, "StorageRadioTrigger")
			await _shoot(at, game, eggs, "DoctorsRadioTrigger")
			await _wait(at, 0.2)
			_check(_on(eggs, "StorageRadioMessage") and _on(eggs, "DoctorsRadioMessage"), "storage and doctors messages")
			await _shoot(at, game, eggs, "TelephoneNoiseTrigger")
			await _wait(at, 0.2)
			_check(_on(eggs, "TelephoneNoiseEmitter") and not _on(eggs, "TelephoneOffHookEmitter") and not eggs.triggers["TelephoneNoiseTrigger"].enabled,
				"phone rings, trigger off")
			await _wait(at, 8.2)
			_check(_on(eggs, "TelephoneMusicEmitter") and not _on(eggs, "TelephoneNoiseEmitter"), "phone song after 8 s")
			await _wait(at, 12.2)
			_check(eggs.telephone_state == "On" and eggs.triggers["TelephoneNoiseTrigger"].enabled, "phone shootable again after 12 s")
			await _shoot(at, game, eggs, "TelephoneNoiseTrigger", false)
			_check(not _on(eggs, "TelephoneMusicEmitter") and eggs.telephone_state == "Off", "song off")
			await _shoot(at, game, eggs, "TelephoneNoiseTrigger", false)
			await _wait(at, 0.2)
			_check(_on(eggs, "TelephoneMusicEmitter") and eggs.telephone_state == "On", "song on again")
		"verruckt":
			await _shoot(at, game, eggs, "DentistChairVolume")
			await _wait(at, 0.2)
			_check(_on(eggs, "DentistWhizz") and not eggs.triggers["DentistChairVolume"].enabled, "dentist whizz")
			await _wait(at, 5.6)
			_check(not _on(eggs, "DentistWhizz"), "whizz stopped by endDentist")


static func monkey(at: Node, game: Game) -> void:
	game.set_process(false)
	var p := game.player
	p.health = 1e9
	var box: MysteryBox = game.level.boxes[0]
	_check((MonkeyBomb.ITEM in box.pool()) == (game.level_name == "derriese"), "monkey in the box pool only on Der Riese")
	await ExtraTests._face_box(at, game, box)
	p.points = 5000
	box.set("_teddy_next", false)
	box.interact(p)
	await _wait(at, MysteryBox.CYCLE_TIME + 0.4)
	if box.state == MysteryBox.State.TEDDY:
		_check(true, "teddy rolled; skipping box hand-over")
	else:
		box.offered = MonkeyBomb.ITEM   # force the offer
		box._show_weapon(MonkeyBomb.ITEM)
		await ExtraTests._box_shot(at, box, "monkey_box", 1.3)
		_check(box.prompt(p).contains("Monkey"), "prompt: %s" % box.prompt(p))
		box.interact(p)
	if MonkeyBelt.of(p) == null:
		MonkeyBelt.give(p)
	var belt := MonkeyBelt.of(p)
	var frags := GrenadeBelt.of(p).count
	_check(belt.count == 3, "3 monkeys (%d)" % belt.count)
	# throw in the open, away from the box
	p.global_transform = game.level.player_spawn
	await at.get_tree().physics_frame
	# a free stretch in front of the player
	var space := p.get_world_3d().direct_space_state
	var best_dir := Vector3.ZERO
	var best_len := 0.0
	for k in 16:
		var d := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0)
		var o := p.global_position + Vector3.UP * 1.0
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + d * 15.0, 1))
		var l := 15.0 if h.is_empty() else o.distance_to(h["position"])
		if l > best_len:
			best_len = l
			best_dir = d
	p.rotation.y = atan2(-best_dir.x, -best_dir.z)
	p.get_viewport().get_camera_3d().rotation.x = 0.15
	await at.get_tree().physics_frame
	var map := p.get_world_3d().navigation_map
	await _wait(at, 0.3)
	var gb := GrenadeBelt.of(p)
	gb.set_held(true)
	await _wait(at, 1.7)   # Throwingmonkeybomb: the arms wind the monkey, then throw it (viewmodel.gd)
	await ExtraTests._snap(at, "monkey_hand")
	gb.set_held(false)
	var bombs := []
	for i in 40:
		bombs = at.get_tree().get_nodes_in_group("monkey_bombs")
		if not bombs.is_empty():
			break
		await _wait(at, 0.1)
	_check(bombs.size() == 1 and belt.count == 2 and gb.count == frags, "G threw a monkey (monkeys %d, frags %d->%d)" % [belt.count, frags, gb.count])
	if bombs.is_empty():
		return
	var bomb: MonkeyBomb = bombs[0]
	await _wait(at, 1.8)
	_check(bomb.landed and bomb._song.playing, "landed, song playing")
	# zombies chasing the player, around where the monkey landed (same floor)
	var zs := []
	for off in [Vector3(5, 0, 0), Vector3(-4, 0, 3), Vector3(1, 0, -6), Vector3(-3, 0, -3), Vector3(3, 0, 4)]:
		if zs.size() == 3:
			break
		var at_pos := NavigationServer3D.map_get_closest_point(map, bomb.global_position + off)
		if absf(at_pos.y - bomb.global_position.y) > 0.8 or at_pos.distance_to(bomb.global_position) < 3.0:
			continue
		var z := Zombie.new()
		z.setup(at_pos, game.level.windows[0], p, 400.0, false)
		game.add_child(z)
		z.state = Zombie.State.CHASE
		zs.append(z)
	_check(zs.size() == 3, "3 zombies around the monkey")
	await _wait(at, 0.4)
	var bnav := NavigationServer3D.map_get_closest_point(map, bomb.global_position)
	print("[monkey] player %s bomb %s (navmesh %.2f m away), zombies %s" % [p.global_position, bomb.global_position, bnav.distance_to(bomb.global_position), zs.map(func(z): return z.global_position)])
	var lured := zs.filter(func(z): return is_instance_valid(z) and z.lure == bomb)
	_check(lured.size() == zs.size(), "%d/%d zombies lured" % [lured.size(), zs.size()])
	var d0 := zs.map(func(z): return z.global_position.distance_to(bomb.global_position))
	# walk away from the bomb: the zombies must not follow the player
	p.global_position = NavigationServer3D.map_get_closest_point(map, p.global_position - best_dir * 4.0)
	await _wait(at, 4.0)
	var d1 := zs.map(func(z): return z.global_position.distance_to(bomb.global_position))
	print("[monkey] distances to the bomb %s -> %s, states %s" % [d0, d1, zs.map(func(z): return Zombie.State.keys()[z.state])])
	var closer := 0
	for i in zs.size():
		if d1[i] < d0[i] - 0.5 or d1[i] < 1.6:
			closer += 1
	_check(closer == zs.size(), "zombies walked to the monkey (%d/%d)" % [closer, zs.size()])
	# look at the monkey with the zombies around it
	var cam := Camera3D.new()
	game.add_child(cam)
	var old := at.get_viewport().get_camera_3d()
	var eye := bomb.global_position - best_dir * 4.0 + Vector3.UP * 2.6
	cam.look_at_from_position(eye, bomb.global_position + Vector3.UP * 0.3)
	cam.make_current()
	await at.get_tree().process_frame
	await ExtraTests._snap(at, "monkey_lure")
	cam.queue_free()
	old.make_current()
	var t := 0.0
	while is_instance_valid(bomb) and t < 6.0:
		await _wait(at, 0.25)
		t += 0.25
	_check(not is_instance_valid(bomb), "exploded after %.1f s total" % MonkeyBomb.LIFETIME)
	var res := MonkeyBomb.last_result
	print("[monkey] blast %s" % res)
	_check(int(res.get("hit", 0)) > 0, "blast hit %d zombies, killed %d" % [int(res.get("hit", 0)), int(res.get("killed", 0))])
	await at.get_tree().physics_frame
	var alive := zs.filter(func(z): return is_instance_valid(z) and z.state != Zombie.State.DEAD)
	_check(alive.all(func(z): return not is_instance_valid(z.lure)), "survivors back on the player")
