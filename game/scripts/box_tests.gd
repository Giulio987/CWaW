# Checks for the per-map mystery box lists, the Kar98k / M1 Carbine, the Molotovs and
# Nacht's flamethrower cabinet (screenshots in analysis/preview/boxl_*.png):
#   -- nacht --boxlists-test lists       box pools = console.bin MysteryWeapons<map>, all items usable
#   -- nacht --boxlists-test kar98       wall buy, stats, a shot on a zombie (also: carbine)
#   -- nacht --boxlists-test molotov     box item, selection, lighting/throw frames, splash + fire
#   -- nacht --boxlists-test cabinet     prompt, opening animation, flamethrower, ammo, save state
extends Node

var game: Game
var fails := 0
var _cam: Camera3D


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/box_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	var i := args.find("--boxlists-test")
	var which := args[i + 1] if i + 1 < args.size() else "lists"
	t._run.call_deferred(which)


func _check(ok: bool, what: String) -> void:
	print("[boxl] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/boxl_%s.png" % name))


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
		"lists":
			_lists()
		"kar98", "carbine":
			await _gun(which)
		"molotov":
			await _molotov()
		"cabinet":
			await _cabinet()
	print("[boxl] done, %d failures" % fails)
	get_tree().quit()


func _go_to(target: Vector3) -> void:
	var p := game.player
	var q := PhysicsRayQueryParameters3D.create(target + Vector3.UP, target + Vector3.DOWN * 3.0, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	p.global_position = (hit["position"] if not hit.is_empty() else target) + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	for k in 4:
		await get_tree().physics_frame


# console.bin record: u32 type, name\0, value\0 (string values)
func _console_string(bin: PackedByteArray, name: String) -> String:
	var key := name.to_utf8_buffer()
	key.append(0)
	for i in range(0, bin.size() - key.size()):
		if bin[i] == key[0] and bin.slice(i, i + key.size()) == key:
			var j := i + key.size()
			var e := j
			while e < bin.size() and bin[e] != 0:
				e += 1
			return bin.slice(j, e).get_string_from_ascii()
	return ""


func _lists() -> void:
	var bin := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path("res://../extracted/main/console.bin"))
	_check(bin.size() > 0, "console.bin read (%d bytes)" % bin.size())
	var pairs: Dictionary = Viewmodel.pairs()["weapons"]
	for m in [["nacht", "Nacht"], ["verruckt", "Verruckt"], ["shinonuma", "Shinonuma"], ["derriese", "Derriese"]]:
		var box := MysteryBox.new()
		var lv := Level.new()
		lv.level_name = m[0]
		box.level = lv
		var pool: Array = box.pool()
		var orig := _console_string(bin, "MysteryWeapons" + m[1]).split(",")
		var mapped := Array(orig).map(func(w): return MonkeyBomb.ITEM if w == "monkeybomb" else w)
		_check(pool == mapped, "%s: %d items = console.bin MysteryWeapons%s" % [m[0], pool.size(), m[1]])
		var bad := []
		for w in pool:
			if w in [BettyBelt.ITEM, MolotovBelt.ITEM, MonkeyBomb.ITEM]:
				continue
			if not Weapons.STATS.has(w) or not pairs.has(w) or not Weapons.DISPLAY.has(w) or not Weapons.UPGRADES.has(w):
				bad.append(w)
		_check(bad.is_empty(), "%s: every gun has stats, arms pair, name and Pack-a-Punch %s" % [m[0], bad])
		box.free()
		lv.free()
	var uniq := _console_string(bin, "MysteryUniqueWeaponsDerRiese")
	_check(uniq == "flamethrower,wunderwaffe", "MysteryUniqueWeaponsDerRiese = %s" % uniq)


func _gun(w: String) -> void:
	var p := game.player
	var wall: Array = game.wall_buys.filter(func(b): return String(b.get("weapon", "")) == w)
	_check(not wall.is_empty(), "%s wall buy on %s: %s" % [w, game.level_name, wall.map(func(b): return [b["name"], b["cost"], b["ammo_cost"]])])
	var s := Weapons.stats(w)
	var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../analysis/weapon_stats.json")))
	for k in [w, w + "_upgrade"]:
		var o: Dictionary = js["guns"][k]
		var mine := Weapons.stats_of({"name": w, "upgraded": k.ends_with("_upgrade")})
		_check(int(mine["damage"]) == int(o["damage"]) and int(mine["min"]) == int(o["min_damage"]) and int(mine["mag"]) == int(o["magazine"]) and int(mine["reserve"]) == int(o["reserve"]),
			"%s = CItemGun %s: damage %s/%s, %s + %s" % [k, k, mine["damage"], mine["min"], mine["mag"], mine["reserve"]])
	_check(Weapons.UPGRADES.has(w) and Weapons.DISPLAY.has(w), "%s: %s / Pack-a-Punch %s" % [w, Weapons.display(w), Weapons.UPGRADES.get(w, {}).get("name", "-")])
	_check(Sfx.instance._index["guns"].has(w), "fire sound %s" % Sfx.instance._index["guns"].get(w, "-"))
	p.give_weapon(w)
	await _wait(1.2)
	_check(p.weapon()["name"] == w and int(p.weapon()["mag"]) == int(s["mag"]), "held: %s" % p.weapon())
	await _snap("%s_idle" % w)
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
	var mag := int(p.weapon()["mag"])
	p._fire(p.weapon(), Weapons.stats_of(p.weapon()))
	await _wait(0.06)
	await _snap("%s_fire" % w)
	_check(hp - z.health >= float(s["min"]), "%s one shot: %.0f damage" % [w, hp - z.health])
	_check(int(p.weapon()["mag"]) == mag - 1, "mag %d -> %d" % [mag, int(p.weapon()["mag"])])


func _molotov() -> void:
	var p := game.player
	var belt := MolotovBelt.of(p)
	var gb := GrenadeBelt.of(p)
	_check(belt != null and belt.count == 0, "molotov belt, empty at the start")
	if belt == null:
		return
	MolotovBelt.give(p)
	_check(belt.count == MolotovBelt.MAX and not belt.selected, "box gives %d (MaxMolotovs), selection unchanged" % belt.count)
	var grenades := gb.count
	belt.cycle()
	_check(belt.selected and belt.active(), "T selects the molotovs")
	# room to throw: face the longest free direction, look a little down
	var best := Vector3.FORWARD
	var best_d := 0.0
	var space := game.get_world_3d().direct_space_state
	for k in 16:
		var a := TAU * k / 16.0
		var dir := Vector3(sin(a), 0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 0.5, p.global_position + Vector3.UP * 0.5 + dir * 15.0, 1)
		var hit := space.intersect_ray(q)
		var d := 15.0 if hit.is_empty() else p.global_position.distance_to(hit["position"])
		if d > best_d:
			best_d = d
			best = dir
	p.rotation.y = atan2(-best.x, -best.z)
	var cam := p.get("_camera") as Camera3D
	cam.rotation.x = -0.35
	await _wait(0.3)
	grenades = gb.count
	gb.set_held(true)
	_check(belt.holding and gb.count == grenades and not gb.cooking, "G lights a molotov (no grenade used: %d)" % gb.count)
	var prev := 0.0
	for t in [0.4, 0.9, 1.6, 2.6]:
		await _wait(t - prev)
		prev = t
		await _snap("molotov_light_%02d" % int(t * 10))
	Molotov.last_result = {}
	gb.set_held(false)
	await _wait(0.2)
	await _snap("molotov_throw")
	await _wait(0.25)
	var flying := game.get_children().any(func(n): return n is Molotov)
	await _snap("molotov_flight")
	var waited := 0.0
	while Molotov.last_result.is_empty() and waited < 4.0:
		await _wait(0.1)
		waited += 0.1
	_check(belt.count == MolotovBelt.MAX - 1 and not Molotov.last_result.is_empty(), "thrown (in flight %s), broke after %.1f s, %d left" % [flying, waited, belt.count])
	await _wait(0.4)
	await _snap("molotov_fire_fp")
	await _wait(2.5)
	# splash on zombies: z1 150 hp at 1 m (dies), z2 1000 hp at 2 m (250 + flames), z3 at 4 m
	var c := WeaponTests._floor(game, p.global_position + best * clampf(best_d * 0.5, 2.5, 5.0))
	var side := Vector3(-best.z, 0, best.x)
	var z1 := WeaponTests._zombie(game, WeaponTests._floor(game, c + side * 1.0), 150.0)
	var z2 := WeaponTests._zombie(game, WeaponTests._floor(game, c - side * 2.0), 1000.0)
	var z3 := WeaponTests._zombie(game, WeaponTests._floor(game, c + best * 4.0), 1000.0)
	for zz in [[z1, 150.0], [z2, 1000.0], [z3, 1000.0]]:
		zz[0].health = zz[1]
		zz[0].max_health = zz[1]
	await _wait(0.3)
	var hp_player := p.health
	var m := Molotov.spawn(game, c + Vector3.UP * 1.0, Vector3.DOWN * 6.0, p)
	_check(m != null, "projectile spawned")
	waited = 0.0
	Molotov.last_result = {}
	while Molotov.last_result.is_empty() and waited < 2.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	var res := Molotov.last_result
	await _wait(0.25)
	var eye0 := c + Vector3.UP * 1.2
	await _shot("molotov_fire_front", eye0 - best * _free(c, -best, 4.5) + Vector3.UP * 0.6, c + Vector3.UP * 0.5)
	var sd := side
	var sdd := 0.0
	for deg in [70.0, -70.0, 90.0, -90.0, 110.0, -110.0, 50.0, -50.0]:
		var dir := (-best).rotated(Vector3.UP, deg_to_rad(deg))
		var fd := _free(c, dir, 4.0)
		if fd > sdd + 0.3:
			sdd = fd
			sd = dir
	# narrow rooms: from above, beside the fire
	await _shot("molotov_fire_side", c + Vector3.UP * 2.2 + sd * minf(sdd, 1.6), c + Vector3.UP * 0.3)
	_check(z1.state == Zombie.State.DEAD, "zombie 150 hp at 1 m killed")
	_check(is_instance_valid(z2) and z2.state != Zombie.State.DEAD and is_equal_approx(z2.health, 750.0), "zombie 1000 hp at 2 m: %.0f left (250 fire damage)" % (z2.health if is_instance_valid(z2) else -1.0))
	_check(is_instance_valid(z2) and z2.get_node_or_null("Burning") != null, "zombie at 2 m on fire (zombieonfires)")
	_check(is_instance_valid(z3) and is_equal_approx(z3.health, 1000.0) and z3.get_node_or_null("Burning") == null, "zombie at 4 m untouched")
	_check(p.health == hp_player, "the player is not hurt (target mask 0x10000)")
	print("[boxl] splash: %s" % res)
	await _wait(0.5)
	var hp2 := z2.health
	await _wait(1.6)
	_check(is_equal_approx(z2.health, hp2), "flames only: no afterburn damage (%.0f -> %.0f)" % [hp2, z2.health])
	await _shot("molotov_burning_zombie", eye0 - best * _free(c, -best, 4.5) + Vector3.UP * 0.6, c + Vector3.UP * 0.6)
	# the last ones: the selection goes back to the grenades
	belt.set_count(1)
	gb.set_held(true)
	await _wait(0.3)
	gb.set_held(false)
	await _wait(0.6)
	_check(belt.count == 0 and not belt.selected and not belt.active(), "out of molotovs: grenade slot again")
	var st := belt.save_state()
	_check(int(st["count"]) == 0 and not bool(st["selected"]), "save state %s" % st)
	MolotovBelt.give(p)
	belt.cycle()
	belt.load_state({"count": 2.0, "selected": true})
	_check(belt.count == 2 and belt.selected, "load state")


# free distance from c (1.2 m up) along dir, up to d
func _free(c: Vector3, dir: Vector3, d: float) -> float:
	var from := c + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * d, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	return d if hit.is_empty() else maxf(from.distance_to(hit["position"]) - 0.4, 0.8)


func _cabinet() -> void:
	var p := game.player
	var cab: FlameCabinet = null
	for o in game.level.interactables:
		if o is FlameCabinet:
			cab = o
	_check(cab != null and cab.cost == 2000 and cab.ammo_cost == 380 and cab.weapon == "flamethrower", "cabinet 41870615: %s" % str([cab.cost, cab.ammo_cost, cab.weapon] if cab else "missing"))
	_check(not game.wall_buys.any(func(b): return String(b.get("weapon", "")) == "flamethrower"), "not a plain wall buy")
	if cab == null:
		return
	var front := cab.global_transform.basis.z.normalized()
	var to_use := cab.use_point - cab.global_position
	to_use.y = 0
	if front.dot(to_use) < 0:
		front = -front
	var centre := cab.global_position + Vector3.UP * 1.3
	var side := Vector3(-front.z, 0, front.x)
	await _shot("cabinet_closed_front", centre + front * 2.6 + Vector3.UP * 0.3, centre)
	await _shot("cabinet_closed_side", centre + (front * 2.0 + side * 1.6) + Vector3.UP * 0.3, centre)
	await _go_to(cab.use_point + front * 0.6)
	var aim := centre - (p.global_position + Vector3.UP * 1.6)
	p.rotation.y = atan2(-aim.x, -aim.z)
	await get_tree().physics_frame
	_check(cab.usable_from(p.global_position), "usable from %s (use point %s)" % [p.global_position, cab.use_point])
	p.points = 1000
	cab.interact(p)
	_check(not cab.is_open and p.points == 1000, "not enough points: stays closed")
	p.points = 5000
	print("[boxl] prompt closed: %s" % cab.prompt(p))
	_check(cab.prompt(p).contains("2000"), "closed prompt")
	cab.interact(p)
	_check(cab.is_open and p.points == 3000 and p.weapons.any(func(w): return w["name"] == "flamethrower"), "opened: flamethrower bought, %d points" % p.points)
	await _wait(0.35)
	await _shot("cabinet_opening", centre + front * 2.6 + Vector3.UP * 0.3, centre)
	await _wait(0.8)
	await _shot("cabinet_open_front", centre + front * 2.6 + Vector3.UP * 0.3, centre)
	await _shot("cabinet_open_side", centre + (front * 2.0 + side * 1.6) + Vector3.UP * 0.3, centre)
	await _shot("cabinet_open_side2", centre + (front * 2.0 - side * 1.6) + Vector3.UP * 0.3, centre)
	print("[boxl] prompt open: %s" % cab.prompt(p))
	_check(cab.prompt(p).contains("munizioni") and cab.prompt(p).contains("380"), "open prompt: ammo 380")
	cab.interact(p)
	_check(p.points == 2620 and cab.is_open, "ammo bought for 380 (%d points)" % p.points)
	_check(bool(cab.save_state()["open"]), "save state %s" % cab.save_state())
	# through the player: prompt and interaction
	p.call("_update_prompt")
	print("[boxl] player prompt: %s" % p.get("prompt"))
