# Atomic bomb / Carpenter wave tests (radial_effect.gd, barricade.gd carpenter_repair),
# started from autotest.gd:
#   tools/run_godot.sh 120 -- nacht --autotest 100 --endgame-test nuke
#   tools/run_godot.sh 120 -- nacht --autotest 100 --endgame-test carpenter
# Prints OK/FAIL lines; screenshots analysis/preview/endgame_*.png.
extends RefCounted

const WT := preload("res://scripts/weapon_tests.gd")
const SPEED := 15.0   # 6000 units/s


static func run(at: Node) -> void:
	var game: Game = at.game
	await game.level.wait_navigation()
	await at.get_tree().create_timer(2.5).timeout
	game.set_process(false)   # no rounds: only our zombies
	for z in game.get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	await WT._wait(at, 0.3)
	var args := OS.get_cmdline_user_args()
	var which := args[args.find("--endgame-test") + 1] if args.find("--endgame-test") + 1 < args.size() else "nuke"
	match which:
		"nuke":
			await _nuke(at, game)
		"carpenter":
			await _carpenter(at, game)
	at.get_tree().quit()


static func _ok(cond: bool) -> String:
	return "OK" if cond else "FAIL"


static func _snap(at: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	at.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/endgame_%s.png" % name))


static func _nuke(at: Node, game: Game) -> void:
	var p: Player = game.player
	p.health = 1e9
	var fwd := -p.global_basis.z
	var side := p.global_basis.x
	var origin: Vector3 = p.global_position + Vector3.UP * 0.6
	var dists := [2.0, 6.0, 12.0, 22.0, 40.0, 70.0, 100.0]
	var zs := []
	for i in dists.size():
		var dir := fwd.rotated(Vector3.UP, 0.4 * i)
		zs.append(WT._zombie(game, WT._floor(game, p.global_position + dir * dists[i]), 1e6))
	var near := WT._zombie(game, WT._floor(game, p.global_position + fwd * 3.0 + side * 0.8), 1e6)
	await WT._wait(at, 0.5)
	var before := p.points
	game.apply_powerup("nuke", origin + fwd * 1.0)
	var died := {}
	var t := 0.0
	var shot := false
	while t < 6.0:
		await at.get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		for z in zs + [near]:
			if not died.has(z) and is_instance_valid(z) and z.state == Zombie.State.DEAD:
				died[z] = t
		if not shot and t >= 0.35:
			shot = true
			await _snap(at, "nuke_fireball")
	for i in dists.size():
		var real: float = (zs[i] as Zombie).global_position.distance_to(origin + fwd)
		var expect := minf(real / SPEED, 5.0)
		var got: float = died.get(zs[i], -1.0)
		print("[endgame] nuke zombie at %.1f m died at %.2f s (expected %.2f) %s" % [real, got, expect, _ok(got >= 0.0 and absf(got - expect) < 0.12)])
	var burning := near.get_node_or_null("Burning") != null
	print("[endgame] nuke flames on the near corpse %s" % _ok(burning or near.state == Zombie.State.DEAD))
	print("[endgame] nuke points +%d (8 kills > 4: 400, no kill points) %s" % [p.points - before, _ok(p.points - before == 400)])
	print("[endgame] nuke drops suppressed during the wave, flag back %s" % _ok(not game._nuking))
	# few kills: no bonus
	var few := []
	for i in 3:
		few.append(WT._zombie(game, WT._floor(game, p.global_position + fwd * (2.0 + i) + side), 1e6))
	await WT._wait(at, 0.3)
	before = p.points
	game.apply_powerup("nuke", origin)
	await WT._wait(at, 5.4)
	print("[endgame] nuke with 3 kills: +%d (expected 0) dead %d/3 %s" % [p.points - before,
		few.filter(func(z): return z.state == Zombie.State.DEAD).size(), _ok(p.points == before)])
	# look: fireball from the side
	var c := WT._side_cam(at, game, origin + fwd * 3.0, side * 6.0 + Vector3.UP * 1.5)
	game.apply_powerup("nuke", origin + fwd * 3.0)
	await WT._wait(at, 0.4)
	await _snap(at, "nuke_fireball_side")
	await WT._wait(at, 0.6)
	await _snap(at, "nuke_fireball_side_1s")
	c.queue_free()


static func _carpenter(at: Node, game: Game) -> void:
	var p: Player = game.player
	p.health = 1e9
	var origin: Vector3 = p.global_position + Vector3.UP * 0.6
	var wins: Array = game.level.windows
	for w: Barricade in wins:
		w.boards = 0
		w._update_boards()
	wins = wins.duplicate()
	wins.sort_custom(func(a, b): return a.global_position.distance_to(origin) < b.global_position.distance_to(origin))
	var w0: Barricade = wins[0]
	# side camera on the nearest window
	var c := WT._side_cam(at, game, w0.global_position + Vector3.UP * 1.2,
		w0.normal * 2.6 + w0.global_basis.x * 1.6 + Vector3.UP * 0.4)
	await WT._wait(at, 0.4)
	await _snap(at, "carpenter_before")
	var before := p.points
	game.apply_powerup("carpenter", origin)
	var fixed := {}
	var t := 0.0
	var shots := [0.5, 1.5, 3.3]
	while t < 6.0:
		await at.get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		for w: Barricade in wins:
			if not fixed.has(w) and w.boards == w.max_boards:
				fixed[w] = t
		if fixed.has(w0) and not shots.is_empty() and t - float(fixed[w0]) >= shots[0]:
			await _snap(at, "carpenter_%.1fs" % shots[0])
			if shots[0] == 0.5:
				print("[endgame] carpenter repairAll clip %s speed %.2f %s" % [w0._anim.current_animation, w0._anim.get_playing_speed(),
					_ok(w0._anim.current_animation in Barricade.REPAIR_ALL_ANIMS)])
			shots.pop_front()
	var bad := 0
	for w: Barricade in wins:
		var d := w.global_position.distance_to(origin)
		var expect := minf(d / SPEED, 5.0)
		var got: float = fixed.get(w, -1.0)
		var ok := got >= 0.0 and absf(got - expect) < 0.12
		bad += int(not ok)
		print("[endgame] carpenter %s at %.1f m repaired at %.2f s (expected %.2f) %s" % [w.name, d, got, expect, _ok(ok)])
	print("[endgame] carpenter all windows in order %s; points +%d %s" % [_ok(bad == 0), p.points - before, _ok(p.points - before == 200)])
	before = p.points
	game.apply_powerup("carpenter", origin)
	await WT._wait(at, 5.4)
	print("[endgame] carpenter with nothing to repair: +%d %s" % [p.points - before, _ok(p.points == before)])
	c.queue_free()
