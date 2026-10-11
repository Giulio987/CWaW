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
	_look(p, z.to_global(Vector3(0.28, 1.25, 0.2)))
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
	print("[ztest] real shots at left arm: lost=%s after %d shots" % [z._arms_lost.keys(), shots])
	ok = ok and z._arms_lost.has("left") and not z._arms_lost.has("right")
	print("[ztest] arm %s" % ["OK" if ok else "FAIL"])


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

static func watch(at: Node) -> void:
	var game: Game = at.game
	await game.level.navigation_ready
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
		if int(t) % 20 == 0 and times.size() > 0:
			var s := times.duplicate()
			s.sort()
			print("[zwatch] t=%.0f round=%d reached=%d median=%.1fs max=%.1fs" % [t, game.round_number, s.size(), s[s.size() / 2], s[-1]])
