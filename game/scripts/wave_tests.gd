# Round flow checks against waves.lua / ingame.lua (game.gd), printed as [wave-test]:
#   -- nacht --wave-test [--wave-log]   spawn timing, max-alive skip, end_wave delay,
#       difficulty columns, rounds after 40, no repeated spawn, box/teddy rules
extends Node

var game: Game
var fails := 0


static func start(parent: Node, game_: Game) -> void:
	var t: Node = load("res://scripts/wave_tests.gd").new()
	t.set("game", game_)
	parent.add_child(t)
	t.call("_run")


func _check(ok: bool, what: String) -> void:
	print("[wave-test] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, false).timeout


func _alive() -> Array:
	return get_tree().get_nodes_in_group("zombies").filter(func(z): return z.state != Zombie.State.DEAD)


func _run() -> void:
	await game.level.wait_navigation()
	var p := game.player
	p.health = 1e9
	p.max_health = 1e9
	# tables: Regular = column 2, Recruit = column 1, rounds after 40 from the equation
	var cols := []
	for d in [Game.RECRUIT, Game.REGULAR]:
		Game.difficulty = d
		var row := []
		for r in [1, 2, 5, 40, 41, 75]:
			row.append(Game._wave_counts(game.wave_info(r)).reduce(func(a, c): return a + int(c[0]), 0))
		cols.append(row)
	Game.difficulty = Game.REGULAR
	print("[wave-test] totals rounds 1,2,5,40,41,75: recruit %s regular %s" % cols)
	var w75 := game.wave_info(75)
	_check(w75["SpawnSpeed"] == game.wave_info(40)["SpawnSpeed"] and float(w75["ZombieHealth"][1]) == 75 * 75 * 10 - 150,
		"round 75: spawn speed %s, health %s" % [w75["SpawnSpeed"], w75["ZombieHealth"]])
	_check(Game._dog_number(1, 2) == 6 and Game._dog_number(3, 2) == 8 and Game._dog_number(1, 4) == 6, "dog counts 6 then 8")
	var hi := 0
	var lo := 99
	for i in 2000:
		var r := Game.lua_random(1, 17)
		hi = maxi(hi, r)
		lo = mini(lo, r)
	_check(lo == 1 and hi == 16, "RandomNumber(1, 17) in %d..%d" % [lo, hi])
	# PickRandomSpawnNumber: never the same spawn twice in a row
	var cands := game._spawn_candidates(game.open_areas)
	var repeats := 0
	var prev := ""
	for i in 500:
		var k := Game._cand_key(game._pick_random_spawn(cands))
		repeats += int(k == prev)
		prev = k
	_check(cands.size() < 2 or repeats == 0, "%d spawn candidates, %d repeats in 500 picks" % [cands.size(), repeats])
	game._last_spawn_key = ""
	# box: first location and teddy odds
	if not game.level.boxes.is_empty():
		var box: MysteryBox = game.level.boxes[0]
		print("[wave-test] box at %s (%d locations)" % [box.entity, box.locations.size()])
		_check(box.entity == Level.FIRST_BOX.get(game.level_name, box.entity), "first box location %s" % box.entity)
		var rule: Array = MysteryBox.TEDDY_RULES[game.level_name]
		var bears := 0
		for i in 4000:
			box.used_count = int(rule[0]) + 1
			bears += int(box._teddy_roll())
		box.used_count = int(rule[0])
		var none := box._teddy_roll()
		box.used_count = int(rule[0]) + 1
		while not box._teddy_roll():
			box.used_count = int(rule[0]) + 1
		var after := box.used_count
		box.used_count = 0
		if box.locations.size() > 1:
			_check(absf(bears / 40.0 - float(rule[2])) < 3.0 and not none and after == int(rule[0]) - int(rule[1]),
				"teddy %.1f%% (expected %d%%) after more than %d uses, counter back to %d" % [bears / 40.0, rule[2], rule[0], after])
		else:
			_check(bears == 0, "single box location: no teddy")
	# round 1: initial spawns at i x InitialSpawnSpeed, chain from (InitialSpawns + 3) x InitialSpawnSpeed
	while game.round_number < 1 or game._between_rounds:
		await _wait(0.05)
	var w := game.wave_info(1)
	var iss: float = w["InitialSpawnSpeed"] / 1000.0
	var ss: float = w["SpawnSpeed"] / 1000.0
	var times := []
	game.max_alive = 1   # population limit: the chain skips while one is alive
	var spawned := game._spawned
	var killed_at := -1.0
	while game._spawned < game._to_spawn and game._round_time < 120.0:
		await get_tree().process_frame
		if game._spawned > spawned:
			spawned = game._spawned
			times.append(snappedf(game._round_time, 0.01))
		# kill the first zombie just after the chain's first tick: the next spawn must
		# wait for the following tick, not come at once
		var first_tick := (int(w["InitialSpawns"]) + 3) * iss
		if killed_at < 0.0 and game._round_time > first_tick + 0.5:
			for z in _alive():
				game.kill_without_points(z)
			killed_at = game._round_time
		elif killed_at >= 0.0 and game._round_time > first_tick + 0.5:
			for z in _alive():
				game.kill_without_points(z)
	print("[wave-test] round 1 spawn times %s (initial every %.1f s, chain from %.1f s every %.1f s, cap 1)" % [
		times, iss, (int(w["InitialSpawns"]) + 3) * iss, ss])
	var first_tick := (int(w["InitialSpawns"]) + 3) * iss
	_check(times.size() >= 2 and absf(times[0] - iss) < 0.1, "first zombie at %.2f s" % (times[0] if times.size() else -1.0))
	var after_kill: Array = times.filter(func(t): return t > first_tick + 0.4)
	_check(not after_kill.is_empty() and absf(after_kill[0] - (first_tick + ss)) < 0.1,
		"after the kill at %.2f the next spawn waits for the tick: %s (tick %.2f)" % [killed_at, after_kill.slice(0, 1), first_tick + ss])
	game.max_alive = 24
	# end_wave: 2 s after the last kill (0.5 s with FastWaves), next round 6 s / 5 s later
	while not game._between_rounds:
		for z in _alive():
			game.kill_without_points(z)
		await get_tree().process_frame
	var cleared := Time.get_ticks_msec()
	var round_before := game.round_number
	while game.round_number == round_before:
		await get_tree().process_frame
	var next := (Time.get_ticks_msec() - cleared) / 1000.0
	var expect := (0.5 if game.level_name in Game.FAST_WAVES else 2.0) + (5.0 if game.dog_rounds else 6.0)
	_check(absf(next - expect) < 0.2, "next round %.2f s after the last kill (expected %.1f)" % [next, expect])
	print("[wave-test] %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()
