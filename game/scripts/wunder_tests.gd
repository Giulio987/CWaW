# Wunderwaffe DG-2 tests (wunderwaffe.gd, wunder_grave.gd), started from autotest.gd:
#   tools/run_godot.sh 120 -- nacht --autotest 100 --wunder-test shot      (sphere kills, cap, fizzle)
#   tools/run_godot.sh 120 -- shinonuma --autotest 100 --wunder-test grave (all areas -> grave -> gun)
# Prints OK/FAIL lines; screenshots analysis/preview/wunder_*.png (front and side views).
extends RefCounted

const WT := preload("res://scripts/weapon_tests.gd")


static func run(at: Node) -> void:
	var game: Game = at.game
	await game.level.wait_navigation()
	await at.get_tree().create_timer(2.5).timeout
	game.set_process(false)   # no rounds: only our zombies
	var args := OS.get_cmdline_user_args()
	var which := args[args.find("--wunder-test") + 1] if args.find("--wunder-test") + 1 < args.size() else "shot"
	match which:
		"shot":
			await _shot(at, game)
		"grave":
			await _grave(at, game)
	at.get_tree().quit()


static func _clear(game: Game) -> void:
	for z in game.get_tree().get_nodes_in_group("zombies"):
		z.queue_free()


static func _fire(p: Player) -> void:
	p._cooldown = 0.0
	p.weapon()["mag"] = 3
	p._fire(p.weapon(), Weapons.stats_of(p.weapon()))


static func _dead(zs: Array) -> int:
	return zs.filter(func(z): return is_instance_valid(z) and z.state == Zombie.State.DEAD).size()


static func _shot(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	p.give_weapon("wunderwaffe")
	var w := p.weapon()
	var s := Weapons.stats_of(w)
	print("[wunder] stats mag %d reserve %d rate %.3f reload %.2f name %s %s" % [s["mag"], s["reserve"], s["rate"], s["reload"],
		Weapons.display_of(w), "OK" if s["mag"] == 3 and s["reserve"] == 24 and is_equal_approx(s["reload"], 5.5) else "FAIL"])
	await WT._wait(at, 0.5)
	var d := minf(WT._room_ahead(game, 9.0) - 1.0, 6.0)
	var fwd := -p.global_basis.z
	var side := p.global_basis.x
	var c := WT._floor(game, p.global_position + fwd * d)
	print("[wunder] room ahead %.1f m" % d)
	# 1) a cluster around the target (high-round health: instant kills), one beyond 4 m
	var hp := 6000.0
	var cluster := [WT._zombie(game, c, hp)]
	for o in [side * 0.9, -side * 0.9, side * 1.8, -side * 1.8, -fwd * 0.9]:
		cluster.append(WT._zombie(game, WT._floor(game, c + o), hp))
	var far := WT._zombie(game, WT._floor(game, c - side * 4.6), hp)
	await WT._wait(at, 0.4)
	var pts0 := p.points
	WT._aim(p, c + Vector3.UP * 1.1)
	_fire(p)
	await at.get_tree().physics_frame
	await at.get_tree().physics_frame
	await WT._snap(at, "wunder_0_flight")
	await WT._wait(at, 0.12)
	await WT._snap(at, "wunder_1_arcs")
	await WT._wait(at, 0.3)
	await WT._snap(at, "wunder_2_arcs")
	await WT._wait(at, 1.0)
	var dc := _dead(cluster)
	print("[wunder] cluster dead %d/%d far(4.6 m) %s points +%d %s" % [dc, cluster.size(), Zombie.State.keys()[far.state],
		p.points - pts0, "OK" if dc == cluster.size() and far.state != Zombie.State.DEAD else "FAIL"])
	if Achievements.instance:
		print("[wunder] zombieskillssimu %s" % Achievements.instance._s("wunderwaffe.zombieskillssimu"))
	_clear(game)
	await WT._wait(at, 0.3)
	# 2) at most 10 kills: 12 zombies packed around the target
	var pack := []
	for i in 12:
		pack.append(WT._zombie(game, WT._floor(game, c + side * ((i % 4) - 1.5) * 0.6 + fwd * (int(i / 4) - 1) * 0.6), hp))
	await WT._wait(at, 0.3)
	WT._aim(p, c + side * 0.3 + Vector3.UP * 1.1)   # columns at +-0.3 / +-0.9 m: aim at one
	_fire(p)
	# side view of the arcs
	var cam := WT._side_cam(at, game, c + Vector3.UP * 1.0, side * 3.5 + Vector3.UP * 0.4 + fwd * 1.5)
	await WT._wait(at, 0.45)
	await WT._snap(at, "wunder_3_side")
	await WT._wait(at, 0.25)
	await WT._snap(at, "wunder_3_side_b")
	await WT._wait(at, 0.9)
	cam.queue_free()
	p.get_children().filter(func(n): return n is Camera3D)[0].make_current()
	var dp := _dead(pack)
	print("[wunder] packed 12: dead %d %s" % [dp, "OK" if dp == 10 else "FAIL"])
	_clear(game)
	await WT._wait(at, 0.3)
	# 3) fizzle: nothing within 1.5 m of the impact -> the sphere stops (zombie at 2.2 m lives)
	var z2 := WT._zombie(game, WT._floor(game, c + side * 2.2), hp)
	await WT._wait(at, 0.3)
	WT._aim(p, c)
	_fire(p)
	await WT._wait(at, 1.5)
	print("[wunder] fizzle: zombie at 2.2 m %s %s" % [Zombie.State.keys()[z2.state], "OK" if z2.state != Zombie.State.DEAD else "FAIL"])
	# 4) upgraded (DG-3 JZ): fizzle radius 5 m, reach 7.5 m -> the same zombie dies
	w["upgraded"] = true
	s = Weapons.stats_of(w)
	print("[wunder] upgraded %s mag %d reserve %d %s" % [Weapons.display_of(w), s["mag"], s["reserve"],
		"OK" if s["mag"] == 6 and s["reserve"] == 30 else "FAIL"])
	WT._aim(p, c)
	_fire(p)
	await WT._wait(at, 0.3)
	await WT._snap(at, "wunder_4_upgraded")
	await WT._wait(at, 1.5)
	print("[wunder] upgraded: zombie at 2.2 m %s %s" % [Zombie.State.keys()[z2.state], "OK" if z2.state == Zombie.State.DEAD else "FAIL"])


static func _grave(at: Node, game: Game) -> void:
	var p := game.player
	p.health = 1e9
	var g = game.level.wunder_grave
	if g == null:
		print("[wunder] grave: no controller FAIL")
		return
	var shown := 0
	for n in range(1, 10):
		for k in ["Open", "Closed"]:
			var e := "WunderwaffeGrave%s%d" % [k, n]
			var node: Node3D = g.model(e)
			if node == null:
				print("[wunder] grave node %s missing" % e)
			elif node.visible:
				shown += 1
	print("[wunder] graves hidden at start: %d shown %s" % [shown, "OK" if shown == 0 else "FAIL"])
	await WT._wait(at, 3.0)
	print("[wunder] before all areas: started %s %s" % [g.started, "OK" if not g.started else "FAIL"])
	var areas: Dictionary = game.get("_areas")
	for a in areas:
		if a != "ledge":
			game.open_area(a)
	await WT._wait(at, 1.0)
	print("[wunder] 1 s after all areas: started %s (Timeout 2000) %s" % [g.started, "OK" if not g.started else "FAIL"])
	await WT._wait(at, 1.5)
	print("[wunder] grave %d started %s message '%s' %s" % [g.number, g.started, game.hud.get("_msg").text,
		"OK" if g.started and g.number >= 1 and g.number <= 9 else "FAIL"])
	# walk to the grave (teleport) and dig
	var t: Transform3D = game.level.entity_transform("WunderwaffeGameTrigger%d" % g.number)
	p.global_position = t.origin + Vector3.UP * 0.2 + t.basis.z * 1.0
	await WT._wait(at, 0.3)
	WT._aim(p, t.origin + Vector3.UP * 0.3)
	await WT._wait(at, 0.3)
	print("[wunder] prompt '%s'" % p.prompt)
	await _grave_views(at, game, t.origin, "closed")
	g.interact(p)
	await WT._wait(at, 0.3)
	await _grave_views(at, game, t.origin, "open")
	var has := p.weapons.any(func(w): return w["name"] == "wunderwaffe")
	print("[wunder] dug: found %s has gun %s %s" % [g.found, has, "OK" if g.found and has else "FAIL"])
	var st: Dictionary = g.save_state()
	print("[wunder] save_state %s" % st)
	# resume (WunderwaffeReload): a fresh state, then the saved one
	g.load_state({"number": st["number"], "started": true, "found": false})
	var closed_ok: bool = g.model("WunderwaffeGraveClosed%d" % g.number).visible and not g.model("WunderwaffeGraveOpen%d" % g.number).visible
	print("[wunder] resume not found: closed shown, diggable %s %s" % [g.usable_from(g.global_position), "OK" if closed_ok and g.usable_from(g.global_position) else "FAIL"])
	g.load_state(st)
	var open_ok: bool = g.model("WunderwaffeGraveOpen%d" % g.number).visible and not g.model("WunderwaffeGraveClosed%d" % g.number).visible
	print("[wunder] resume found: open shown, diggable %s %s" % [g.usable_from(g.global_position), "OK" if open_ok and not g.usable_from(g.global_position) else "FAIL"])
	# the box: Wunderwaffe in the pool here (and on Der Riese), not on Nacht / Verrueckt
	var box: MysteryBox = game.level.boxes[0]
	print("[wunder] box pool has wunderwaffe: %s %s" % ["wunderwaffe" in box.pool(), "OK" if "wunderwaffe" in box.pool() else "FAIL"])


# two views of the grave (side angles: rotation errors hide in front views)
static func _grave_views(at: Node, game: Game, o: Vector3, tag: String) -> void:
	var i := 0
	for off in [Vector3(2.6, 1.8, 0.4), Vector3(-0.4, 1.8, 2.6)]:
		var cam := WT._side_cam(at, game, o + Vector3.UP * 0.3, off)
		await WT._wait(at, 0.1)
		await WT._snap(at, "wunder_grave_%s_%d" % [tag, i])
		cam.queue_free()
		i += 1
	game.player.get_children().filter(func(n): return n is Camera3D)[0].make_current()
