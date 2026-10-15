# Gameplay rules from the original code, printed as [rules-test] OK/FAIL:
#   -- shinonuma --rules-test     (any map; the local-spawn, waypoint and killstreak parts
#                                  need Shi No Numa)
# repair quota (repair_quota.gd), heartbeat (heartbeat.gd), headshot streak lines,
# local spawn area choice and boardless swamp windows (game.gd), zombie bleed-out
# (zombie.gd), ambient groans (sfx.gd), per-state strafe speeds (player.gd).
extends Node

var game: Game
var fails := 0


static func start(parent: Node, game_: Game) -> void:
	var t: Node = load("res://scripts/rules_tests.gd").new()
	t.set("game", game_)
	parent.add_child(t)
	t.call("_run")


func _check(ok: bool, what: String) -> void:
	print("[rules-test] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, false).timeout


func _run() -> void:
	await game.level.wait_navigation()
	await _wait(3.0)   # the first round has started
	game.set_process(false)   # no wave spawns from here on
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	var p := game.player
	p.health = 1e9
	p.max_health = 1e9

	# --- repair quota: min(round x 5, 50) paid repairs, then free repairs
	var q := RepairQuota.current()
	_check(q != null and game.round_number >= 1 and q.quota == mini(game.round_number * 5, 50),
		"round %d quota %s" % [game.round_number, q.quota if q else -1])
	q.start_wave(1)
	var paid := 0
	for i in 7:
		paid += q.take()
	_check(paid == 50 and q.quota == 0, "round 1: 7 repairs pay %d (5 x 10)" % paid)
	q.start_wave(12)
	_check(q.quota == 50, "round 12 quota %d (cap 50)" % q.quota)
	_check(q.save_state()["quota"] == 50, "quota saved")
	q.load_state({"quota": 3.0})
	_check(q.quota == 3, "quota loaded")

	# --- heartbeat on every hit, 5 s fading to half volume
	p.take_hit(1.0)
	var hb := p.get_node_or_null("Heartbeat") as Heartbeat
	await _wait(0.3)
	var playing0: bool = hb != null and hb._player != null and hb._player.playing
	var v0: float = hb._player.volume_db if playing0 else 99.0
	await _wait(3.0)
	var v1: float = hb._player.volume_db if hb and hb._player else 99.0
	_check(playing0 and v1 < v0 - 2.0 and v1 > linear_to_db(0.5) - 0.5, "heartbeat fades %.1f -> %.1f dB" % [v0, v1])
	await _wait(2.2)
	_check(hb and hb.left <= 0.0 and not hb._player.playing, "heartbeat stops after 5 s")

	# --- strafe speeds (Max<State>StrafeSpeed)
	_check(absf(p.strafe_speed(Vector2(1, 0)) - 5.0) < 0.01, "walk strafe %.2f m/s (0.5)" % p.strafe_speed(Vector2(1, 0)))
	p.aiming = true
	_check(absf(p.strafe_speed(Vector2(1, 0)) - 2.5) < 0.01, "aim strafe %.2f m/s (0.25)" % p.strafe_speed(Vector2(1, 0)))
	p.aiming = false

	# --- ambient groans: interval multiplier
	_check(Sfx.zombie_gap_mul(0) == 1.0 and Sfx.zombie_gap_mul(1) == 1.0 and absf(Sfx.zombie_gap_mul(4) - 0.25) < 1e-4 and absf(Sfx.zombie_gap_mul(30) - 0.1) < 1e-4,
		"groan gap x %.2f / %.2f / %.2f / %.2f (0, 1, 4, 30 zombies)" % [Sfx.zombie_gap_mul(0), Sfx.zombie_gap_mul(1), Sfx.zombie_gap_mul(4), Sfx.zombie_gap_mul(30)])

	if game.level_name == "shinonuma":
		await _shinonuma()
	await _bleed_out()
	print("[rules-test] done: %d failures %s" % [fails, "OK" if fails == 0 else "FAIL"])
	get_tree().quit()


func _shinonuma() -> void:
	var p := game.player
	# headshot streak lines: the vox table entry of killstreak1 is played at 3 heads
	VoxLines.instance.log_lines.clear()
	p.headshot_streak = 0
	for i in 3:
		p.head_popped()
	var ks := VoxLines.instance.log_lines.filter(func(l): return l[0] == Sfx.iw_hash("killstreak1"))
	_check(ks.size() == 1 and ks[0][1], "3 heads in a row: killstreak1 line %s" % [ks])

	# local spawn: uniform start among the player's area and its open neighbours
	for a in ["commRoomRoom", "storageRoom", "warningRoom", "doctorsRoom", "fishingRoom", "fishingSwamp", "storageSwamp", "commRoomSwamp", "doctorsSwamp"]:
		game.open_area(a)
	p.global_position = game.level.entity_transform("storageRoomZombieWindow1").origin
	var areas := game._local_areas()
	var count := {}
	for i in 3000:
		var c := game._pick_local_spawn()
		count[c["area"]] = count.get(c["area"], 0) + 1
	print("[rules-test] local areas %s picks %s" % [areas, count])
	var expect := {}
	var n := areas.size()
	for s in n:
		for k in n:
			var an: String = areas[(s + k) % n]
			if not game._spawn_candidates([an]).is_empty():
				expect[an] = expect.get(an, 0.0) + 3000.0 / n
				break
	var ok := true
	for an in expect:
		ok = ok and absf(count.get(an, 0) - expect[an]) < 0.25 * expect[an] + 40
	_check(ok and count.size() == expect.size(), "local spawn areas %s vs expected %s" % [count, expect])

	# boardless swamp windows: walk there, then chase
	game._hp = Vector2(1e6, 1e6)
	var z := game.spawn_zombie_at("fishingSwampZombieSpawn1")
	_check(z != null and z.waypoint != Vector3.INF and z.state == Zombie.State.TO_WINDOW,
		"fishingSwampZombieSpawn1 -> waypoint %s" % [z.waypoint if z else null])
	if z:
		z.set_speed_index(10)
		var boards: int = z.window.boards
		var t := 0.0
		while t < 40.0 and is_instance_valid(z) and z.state in [Zombie.State.TO_WINDOW, Zombie.State.RISING]:
			await _wait(0.5)
			t += 0.5
		_check(is_instance_valid(z) and z.state in [Zombie.State.CHASE, Zombie.State.ATTACK] and z.reached_window > 0.0 and z.window.boards == boards,
			"waypoint reached in %.1f s, then %s (no boards torn)" % [z.reached_window if is_instance_valid(z) else -1.0, Zombie.State.keys()[z.state] if is_instance_valid(z) else "freed"])
		if is_instance_valid(z):
			z.queue_free()
		await _wait(0.2)


func _bleed_out() -> void:
	var p := game.player
	game._hp = Vector2(100, 100)
	var sp := ""
	for c in game._spawn_candidates(game.open_areas):
		if game._win_by_name.has(c["window"]):
			sp = c["spawn"]
			break
	var z := game.spawn_zombie_at(sp)
	z.health = 100.0
	await _wait(0.5)
	# the player far away, looking up: the zombie cannot be seen
	p.global_position = z.global_position + Vector3(60, 0, 0)
	p._camera.rotation.x = 1.4
	var spawned := game._spawned
	z._bo_left = 0.2
	await _wait(0.6)
	_check(not is_instance_valid(z) and game._spawned == spawned - 1, "stalled unseen zombie bled out, replaced (spawned %d -> %d)" % [spawned, game._spawned])
