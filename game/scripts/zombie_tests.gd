# Zombie tests, started from autotest.gd:
#   tools/run_godot.sh 60 -- nacht --autotest 50 --zombie-test rise|arm|speed
#   tools/run_godot.sh 150 -- verruckt --autotest 140 --zombie-watch [--start-round N]
# rise/arm/speed print OK/FAIL lines and save screenshots to analysis/preview/ztest_*.png.
# --zombie-watch runs alongside the normal autotest bot and reports every zombie that
# takes long to reach its window (spawn, window, distance left, path state).
class_name ZombieTests


static func run(at: Node) -> void:
	var game: Game = at.game
	await game.level.navigation_ready
	await at.get_tree().create_timer(0.5).timeout
	game.set_process(false)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--zombie-test")
	var which: String = args[i + 1] if i + 1 < args.size() else "rise"
	match which:
		"rise":
			await _rise(at, game)
		"arm":
			await _arm(at, game)
		"speed":
			await _speed(at, game)
		"nav":
			await _nav(at, game)
		"spawns":
			await _spawns(at, game)
		"trace":
			await _trace(at, game)
		"drop":
			await _drop(at, game)
		"speedup":
			await _speedup(at, game)
	at.get_tree().quit()


static func _snap(at: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	at.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/ztest_%s.png" % name))


static func _wait(at: Node, t: float) -> void:
	await at.get_tree().create_timer(t).timeout


static func _look(p: Player, target: Vector3) -> void:
	var to := target - (p.global_position + Vector3.UP * 1.6)
	p.rotation.y = atan2(-to.x, -to.z)
	p.get_viewport().get_camera_3d().rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


# A zombie climbs out of the ground in front of the player, then chases.
static func _rise(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var z := Zombie.new()
	z.setup(p.global_position + fwd * 3.5, game.level.windows[0], p, 1e6, false, 5)
	z.rise = true
	z.state = Zombie.State.CHASE
	game.add_child(z)
	z.look_at(p.global_position, Vector3.UP, true)
	var side := p.global_basis.x
	_look(p, z.global_position + Vector3.UP * 0.6)
	for t in [0.5, 2.5, 5.0, 7.5, 9.5]:
		await _wait(at, t - z.life)
		await _snap(at, "rise_%02d" % int(t * 10))
		print("[ztest] rise t=%.1f state=%s anim=%s shape_y=%.2f" % [z.life, Zombie.State.keys()[z.state], z._anim.current_animation, z._shape.position.y])
	# side view of the end of the rise
	var keep := p.global_position
	p.global_position = z.global_position + side * 3.0
	_look(p, z.global_position + Vector3.UP * 0.9)
	await _wait(at, 10.4 - z.life)
	await _snap(at, "rise_side")
	await _wait(at, 1.0)
	print("[ztest] rise end t=%.1f state=%s anim=%s" % [z.life, Zombie.State.keys()[z.state], z._anim.current_animation])
	p.global_position = keep
	print("[ztest] rise %s" % ["OK" if z.state in [Zombie.State.CHASE, Zombie.State.ATTACK] else "FAIL"])


# Hit positions pick the arm: local points on each side/height, then real shots.
static func _arm(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var z := Zombie.new()
	z.setup(p.global_position + fwd * 2.5, game.level.windows[0], p, 1e6, false, 1)
	game.add_child(z)
	z.state = Zombie.State.ATTACK
	z.set_physics_process(false)
	z.look_at(p.global_position, Vector3.UP, true)
	await _wait(at, 0.3)
	var ok := true
	var cases := [
		[Vector3(0.3, 1.3, 0.25), "left"], [Vector3(-0.3, 1.3, 0.25), "right"],
		[Vector3(0.3, 1.25, 0.0), "left"], [Vector3(-0.3, 1.25, -0.05), "right"],
		[Vector3(0.0, 1.2, 0.3), ""], [Vector3(0.15, 0.5, 0.25), ""], [Vector3(0.2, 1.75, 0.1), ""]]
	for c in cases:
		var got := z.arm_at(z.to_global(c[0]))
		print("[ztest] arm_at local %s -> '%s' (want '%s')" % [c[0], got, c[1]])
		ok = ok and got == c[1]
	# real hitscan from the player: aim at the zombie's left arm until it comes off
	_look(p, z.to_global(Vector3(0.2, 1.25, 0.1)))
	await _snap(at, "arm_0")
	var w := p.weapon()
	var shots := 0
	while not z._arms_lost.has("left") and shots < 60:
		w["mag"] = 5
		p._cooldown = 0.0
		p._fire(w, Weapons.stats_of(w).merged({"damage": 60.0, "pellets": 1}, true))
		shots += 1
		await at.get_tree().physics_frame
	await _wait(at, 0.15)
	await _snap(at, "arm_1_left")
	print("[ztest] real shots at left arm: lost=%s after %d shots, health lost %.0f" % [z._arms_lost.keys(), shots, 1e6 - z.health])
	ok = ok and z._arms_lost.has("left") and not z._arms_lost.has("right")
	print("[ztest] arm %s" % ["OK" if ok else "FAIL"])


# Where the player stands vs the navmesh, with outside views of the spot.
static func _nav(at: Node, game: Game) -> void:
	await _no_sky(game)
	var p := game.player
	var fo := OS.get_cmdline_user_args().find("--at")
	if fo >= 0:
		var f := OS.get_cmdline_user_args()[fo + 1].split_floats(",")
		p.global_position = Vector3(f[0], f[1], f[2])
		await _wait(at, 0.3)
	var map := p.get_world_3d().navigation_map
	var pp := p.global_position
	print("[ztest] nav player=%s closest=%s" % [pp, NavigationServer3D.map_get_closest_point(map, pp)])
	var cam := Camera3D.new()
	game.add_child(cam)
	var i := 0
	var focus := pp
	var fi := OS.get_cmdline_user_args().find("--focus")
	if fi >= 0:
		var f := OS.get_cmdline_user_args()[fi + 1].split_floats(",")
		focus = pp + Vector3(f[0], f[1], f[2])
	for off in [Vector3(5, 3, 0), Vector3(-5, 3, 0), Vector3(0, 3, 5), Vector3(0, 3, -5), Vector3(0.1, 9, 0)]:
		cam.global_position = focus + off
		cam.look_at(focus, Vector3.UP if off.x != 0.1 else Vector3.FORWARD)
		cam.make_current()
		await _wait(at, 0.2)
		await _snap(at, "nav_%d" % i)
		i += 1
	for goal in [Vector3(5.5, 0.1, 7.9), Vector3(-3.5, 0.1, 7.9), Vector3(-2.2, 0.1, 4.8)]:
		var path := NavigationServer3D.map_get_path(map, pp, goal, true)
		print("[ztest] nav path to %s: %d pts end=%s" % [goal, path.size(), path[-1] if path.size() > 0 else Vector3.INF])
	# deck extent: scan a grid for floor heights near 2.4 m
	for gz in range(-12, 13, 2):
		var row := ""
		for gx in range(-12, 13, 1):
			var q: Vector3 = pp + Vector3(gx, 0, gz)
			var hit := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 4, q - Vector3.UP * 6, 1))
			var fy: float = hit["position"].y if hit else -99.0
			var c := NavigationServer3D.map_get_closest_point(map, Vector3(q.x, fy, q.z))
			var on_nav := Vector2(c.x - q.x, c.z - q.z).length() < 0.3 and absf(c.y - fy) < 0.4
			row += ("%d" % clampi(int(round(fy)), 0, 9) if hit else "#") + ("." if on_nav else "x")
		print("[ztest] grid z%+3d %s" % [gz, row])
	for dz in [0.0, -7.0, -8.5, -9.5]:
		var q2: Vector3 = pp + Vector3(-1 if dz != 0.0 else 0, 0, dz)
		var rq := PhysicsRayQueryParameters3D.create(Vector3(q2.x, pp.y + 0.3 if dz == 0.0 else 3.2, q2.z), Vector3(q2.x, -2, q2.z), 0xFFFF)
		rq.exclude = [p.get_rid()]
		var h2 := p.get_world_3d().direct_space_state.intersect_ray(rq)
		if h2:
			var o: Node = h2["collider"]
			var chain := ""
			while o and chain.count("/") < 6:
				chain = o.name + "/" + chain
				o = o.get_parent()
			print("[ztest] collider at %s y=%.2f: %s shape=%d layer=%d" % [q2, h2["position"].y, chain, h2["shape"], (h2["collider"] as CollisionObject3D).collision_layer])
	var li := OS.get_cmdline_user_args().find("--line")
	if li >= 0:
		var e := OS.get_cmdline_user_args()[li + 1].split_floats(",")
		var to := Vector3(e[0], e[1], e[2])
		for k in 41:
			var q3: Vector3 = pp.lerp(to, k / 40.0)
			var rq3 := PhysicsRayQueryParameters3D.create(q3 + Vector3.UP * 1.5, q3 + Vector3.DOWN * 4.0, 0xFFFF)
			rq3.exclude = [p.get_rid()]
			var h3 := p.get_world_3d().direct_space_state.intersect_ray(rq3)
			var fy: float = (h3["position"] as Vector3).y if h3 else -99.0
			var c3 := NavigationServer3D.map_get_closest_point(map, Vector3(q3.x, fy, q3.z))
			print("[ztest] line %s floor=%.2f layer=%d nav=%s off=%.2f %s" % [q3.snapped(Vector3(0.1, 0.1, 0.1)), fy, (h3["collider"] as CollisionObject3D).collision_layer if h3 else -1,
				c3.snapped(Vector3(0.1, 0.1, 0.1)), c3.distance_to(Vector3(q3.x, fy, q3.z)), (h3["collider"] as Node).get_parent().name if h3 else ""])
	for gx in [-2.0, -1.0, 0.0]:
		var prof := ""
		for k in range(0, 48):
			var q: Vector3 = pp + Vector3(gx, 0, -4.0 - k * 0.25)
			var hit := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q.x, 3.2, q.z), Vector3(q.x, -2, q.z), 1))
			prof += "%.2f " % (hit["position"].y if hit else -9.0)
		print("[ztest] profile x%+.0f z-4..-16: %s" % [gx, prof])
	# a ring of probes: floor height and closest nav point around the player
	for a in range(0, 360, 45):
		for r in [1.5, 3.0, 4.5]:
			var q: Vector3 = pp + Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * r
			var hit := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 3, q - Vector3.UP * 6, 1))
			var fy: float = hit["position"].y if hit else NAN
			print("[ztest] nav a=%d r=%.1f floor_y=%.2f nav=%s" % [a, r, fy, NavigationServer3D.map_get_closest_point(map, Vector3(q.x, fy if hit else pp.y, q.z)).snapped(Vector3(0.1, 0.1, 0.1))])


# One chasing zombie from --from x,y,z: prints its track (debug snags).
static func _trace(at: Node, game: Game) -> void:
	await _no_sky(game)
	var p := game.player
	p.health = 1e9
	var args := OS.get_cmdline_user_args()
	var z := Zombie.new()
	var spd := int(args[args.find("--speed") + 1]) if args.has("--speed") else 5
	if args.has("--spawn"):
		# a real spawn entity and its window: --spawn StartRoomZombieSpawn1
		var sp: String = args[args.find("--spawn") + 1]
		var win: Barricade = game._win_by_name.get(sp.to_lower().replace("zombiespawn", "zombiewindow"), game.level.windows[0])
		z.setup(game.level.entity_transform(sp).origin, win, p, 1e6, false, spd)
		print("[ztest] trace %s -> %s outside=%s" % [sp, win.name, win.outside])
	else:
		var f := args[args.find("--from") + 1].split_floats(",")
		z.setup(Vector3(f[0], f[1], f[2]), game.level.windows[0], p, 1e6, false, spd)
		z.state = Zombie.State.CHASE
	game.add_child(z)
	var cam := Camera3D.new()
	game.add_child(cam)
	for i in 60:
		await _wait(at, 0.25)
		if i % 4 == 0:
			print("[ztest] trace t=%.2f %s pos=%s vel=%.2f next=%s unstuck=%d unsticking=%s floor=%s dist=%.1f" % [z.life, Zombie.State.keys()[z.state], z.global_position.snapped(Vector3(0.01, 0.01, 0.01)),
				Vector2(z.velocity.x, z.velocity.z).length(), z._agent.get_next_path_position().snapped(Vector3(0.1, 0.1, 0.1)), z.unstuck_count, z._unsticking, z.is_on_floor(),
				z.global_position.distance_to(p.global_position)])
		if z._dropping and not at.has_meta("drop_shot"):
			at.set_meta("drop_shot", true)
			await _wait(at, 0.3)
			cam.global_position = z.global_position + z.global_basis.x * 4.0 + Vector3.UP * 0.5
			cam.look_at(z.global_position + Vector3.DOWN * 0.5, Vector3.UP)
			cam.make_current()
			await _snap(at, "drop_mid")
			await _wait(at, 0.4)
			await _snap(at, "drop_end")
			cam.clear_current()
		if i == 6:
			cam.global_position = z.global_position + Vector3(2.5, 2.5, 2.5)
			cam.look_at(z.global_position + Vector3.UP, Vector3.UP)
			cam.make_current()
			await _snap(at, "trace_a")
			cam.global_position = z.global_position + Vector3(-2.5, 2.0, -2.5)
			cam.look_at(z.global_position + Vector3.UP, Vector3.UP)
			await _snap(at, "trace_b")
			p.get_viewport().get_camera_3d()
			cam.clear_current()


# Jump down: a zombie at the end of a raised walkway whose (fake) window is on the
# ground below: -- shinonuma --zombie-test drop
static func _drop(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	var win: Barricade = game.level.windows[0]
	var keep := win.outside
	win.outside = Vector3(31.5, -0.2, 7.3)
	var z := Zombie.new()
	z.setup(Vector3(36.6, 5.0, 6.1), win, p, 1e6, false, 5)
	game.add_child(z)
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.global_position = Vector3(33.0, 3.0, 12.0)
	cam.look_at(Vector3(35.0, 2.5, 6.0), Vector3.UP)
	cam.make_current()
	var shots := 0
	var was := false
	for i in 80:
		await _wait(at, 0.1)
		if z._dropping and shots < 4:
			await _snap(at, "drop_%d" % shots)
			shots += 1
		if was and not z._dropping:
			await _snap(at, "drop_landed")
		was = z._dropping
		if i % 10 == 0:
			print("[ztest] drop t=%.1f %s pos=%s dropping=%s anim=%s" % [z.life, Zombie.State.keys()[z.state], z.global_position.snapped(Vector3(0.01, 0.01, 0.01)), z._dropping, z._anim.current_animation])
	print("[ztest] drop %s (y=%.2f)" % ["OK" if z.global_position.y < 1.0 else "FAIL", z.global_position.y])
	win.outside = keep


# ZombieSpeedUp: wave > 4 fully spawned, a zombie alive 180 s steps up 5 -> 8 -> 12 -> 14.
static func _speedup(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	game.round_number = 5
	game._between_rounds = false
	game._to_spawn = 10
	game._spawned = 10
	var z := Zombie.new()
	z.setup(p.global_position - p.global_basis.z * 30.0, game.level.windows[0], p, 1e6, false, 2)
	z.state = Zombie.State.CHASE
	game.add_child(z)
	var seen := [z.speed_index]
	for i in 4:
		z._speed_up_t = Zombie.SPEED_UP_TIME - 0.05
		await _wait(at, 0.2)
		seen.append(z.speed_index)
	print("[ztest] speedup indices %s anim=%s speed=%.2f %s" % [seen, z.move_anim, z.speed, "OK" if seen == [2, 5, 8, 12, 14] else "FAIL"])


# Every zombie spawn of the map: on the navmesh? path length to its window / the player.
static func _spawns(at: Node, game: Game) -> void:
	await _no_sky(game)
	var map := game.player.get_world_3d().navigation_map
	var lv := game.level
	for n in lv.entities_matching(""):
		if not ("zombiespawn" in String(n).to_lower()):
			continue
		var o: Vector3 = lv.entity_transform(n).origin
		var c := NavigationServer3D.map_get_closest_point(map, o)
		var wn: String = String(n).to_lower().replace("zombiespawn", "zombiewindow")
		var win: Barricade = game._win_by_name.get(wn)
		var info := "window=%s" % ("-" if win == null else win.name)
		if win:
			var path := NavigationServer3D.map_get_path(map, c, win.outside, true)
			info += " path=%.1fm end_off=%.1f dy=%.1f" % [_plen(path), path[-1].distance_to(win.outside) if path.size() > 0 else -1.0, win.outside.y - o.y]
		var pp := NavigationServer3D.map_get_path(map, c, game.player.global_position, true)
		print("[ztest] spawn %s at %s nav_off=%.2f %s to_player=%.1fm end_off=%.1f" % [n, o.snapped(Vector3(0.1, 0.1, 0.1)), c.distance_to(o), info, _plen(pp),
			pp[-1].distance_to(game.player.global_position) if pp.size() > 0 else -1.0])


static func _plen(path: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, path.size()):
		l += path[i].distance_to(path[i - 1])
	return l


# Each original speed index: measured ground speed vs the table.
static func _speed(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var ok := true
	for i in range(1, Zombie.MAX_SPEED_INDEX + 1):
		var z := Zombie.new()
		z.setup(p.global_position + fwd * 9.0, game.level.windows[0], p, 1e6, false, i)
		z.state = Zombie.State.CHASE
		game.add_child(z)
		await _wait(at, 0.6)
		var a := z.global_position
		await _wait(at, 1.2)
		var v := Vector2(z.global_position.x - a.x, z.global_position.z - a.z).length() / 1.2
		var ap: AnimationPlayer = z._anim
		print("[ztest] speed %2d anim=%s rate=%.2f table=%.2f m/s measured=%.2f m/s playing=%s scale=%.2f" % [i, z.move_anim, z.move_rate, z.speed, v, ap.current_animation, ap.get_playing_speed()])
		ok = ok and (absf(v - z.speed) < 0.25 or z.state == Zombie.State.ATTACK)
		z.queue_free()
		await _wait(at, 0.1)
	print("[ztest] speed %s" % ["OK" if ok else "FAIL"])


# ------------------------------------------------------------------ stuck watch

static func _no_sky(game: Game) -> void:
	if not OS.get_cmdline_user_args().has("--no-sky"):
		return
	# test-only workaround: the sky dome (mesh 9a8734e1, at the origin on Der Riese
	# and Shi No Numa) gets a collider in level.gd and cuts the navmesh
	var n := 0
	for mi in game.level.find_children("9a8734e1", "MeshInstance3D", true, false):
		for b in mi.find_children("*", "StaticBody3D", true, false):
			b.free()
			n += 1
	print("[zwatch] removed %d sky colliders, rebaking" % n)
	game.level.bake_navigation()
	await game.level.navigation_ready


static func watch(at: Node) -> void:
	var game: Game = at.game
	await game.level.navigation_ready
	await _no_sky(game)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--start-round")
	if i >= 0 and i + 1 < args.size():
		game.round_number = int(args[i + 1]) - 1
	var reported := {}
	var times: Array[float] = []
	var t := 0.0
	while true:
		await at.get_tree().create_timer(1.0).timeout
		t += 1.0
		for z in game.get_children():
			if not (z is Zombie) or z is Dog or z.state == Zombie.State.DEAD:
				continue
			var zz: Zombie = z
			if zz.reached_window >= 0.0 and not reported.has(zz.get_instance_id()):
				reported[zz.get_instance_id()] = true
				times.append(zz.reached_window)
			if zz.state == Zombie.State.TO_WINDOW and zz.life > 25.0 and not reported.has(-zz.get_instance_id()):
				reported[-zz.get_instance_id()] = true
				print("[zwatch] SLOW t=%.0f life=%.0f pos=%s window=%s(%s) dist=%.1f nav_finished=%s next=%s" % [t, zz.life,
					zz.global_position.snapped(Vector3(0.1, 0.1, 0.1)), zz.window.name, zz.window.outside.snapped(Vector3(0.1, 0.1, 0.1)),
					zz.global_position.distance_to(zz.window.outside), zz._agent.is_navigation_finished(),
					zz._agent.get_next_path_position().snapped(Vector3(0.1, 0.1, 0.1))])
		if int(t) % 20 == 0:
			var n := 0
			for z in game.get_children():
				if z is Zombie and not z is Dog and z.state == Zombie.State.CHASE and n < 4:
					var zz: Zombie = z
					n += 1
					print("[zwatch] chase unstuck=%d pos=%s player=%s dist=%.1f vel=%.2f next=%s reachable=%s final=%s" % [zz.unstuck_count, zz.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
						game.player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), zz.global_position.distance_to(game.player.global_position),
						Vector2(zz.velocity.x, zz.velocity.z).length(), zz._agent.get_next_path_position().snapped(Vector3(0.1, 0.1, 0.1)),
						zz._agent.is_target_reachable(), zz._agent.get_final_position().snapped(Vector3(0.1, 0.1, 0.1))])
		if int(t) % 20 == 0 and times.size() > 0:
			var s := times.duplicate()
			s.sort()
			print("[zwatch] t=%.0f round=%d reached=%d median=%.1fs max=%.1fs" % [t, game.round_number, s.size(), s[s.size() / 2], s[-1]])
