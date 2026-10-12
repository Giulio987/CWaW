# Achievement and footstep checks (prints OK/FAIL, screenshots in analysis/preview):
#   -- nacht --achievement-test       Lua achievement (radio), map limits, counted stats,
#                                     kills (knife streak, distance, heads), rounds,
#                                     popup, save file, list screen
#   -- nacht --footstep-test          walking: step sounds and their timing
#   -- shinonuma --footstep-test      wading: water steps at half speed
# Both use user://achievements_test.cfg (any *-test option does), never the real save.
class_name AchievementTests
extends Node

var game: Game
var fails := 0


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t := AchievementTests.new()
	t.game = game_
	parent.add_child(t)
	if args.has("--achievement-test"):
		t._achievement_test()
	else:
		t._footstep_test()


func _check(tag: String, ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [tag, "OK" if ok else "FAIL", what])
	fails += int(not ok)


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _zombie(at: Vector3) -> Zombie:
	var z := Zombie.new()
	z.setup(at, game.level.windows[0], game.player, 100.0, false, 1)
	z.state = Zombie.State.CHASE
	game.add_child(z)
	return z


func _achievement_test() -> void:
	const TAG := "achievement"
	await game.level.wait_navigation()
	game.set_process(false)   # no rounds/spawns of its own
	var a := Achievements.instance
	var p := game.player
	p.health = 1e9
	_check(TAG, a != null and a.entries.size() == 106, "106 achievements from the original data (%d)" % (a.entries.size() if a else 0))
	_check(TAG, a.test_mode and a.unlocked.is_empty(), "test save file, empty at start")
	# Lua: nacht.lua RadioVolume -> Game.SetAchievement("radioSilence")
	var eggs := game.get_node_or_null("RadioEggs") as RadioEggs
	if eggs:
		eggs.trigger("RadioVolume", p)
	_check(TAG, a.is_unlocked(1), "radio hit unlocks \"%s\"" % a.by_num[1]["it_name"])
	await _wait(0.6)
	await _shot("achievement_popup")
	# a map group only counts on its map; Der Riese's generator does not give Verrückt's
	Achievements.unlock("ver_openwide")
	Achievements.unlock("der_ElevateYourSenses")
	_check(TAG, not a.is_unlocked(48) and not a.is_unlocked(89), "Verrückt/Der Riese achievements locked on Nacht")
	# counted stats: shots (Munitions Expert I, overall), points spent (Eternal Investments)
	for i in 1000:
		Achievements.fired("colt45")
	p.add_points(60000)
	p.add_points(-50000)
	await _wait(0.1)
	_check(TAG, a.is_unlocked(18) and not a.is_unlocked(19), "1000 shots: Munitions Expert I (not II)")
	_check(TAG, a.is_unlocked(44), "50,000 points spent: Eternal Investments")
	_check(TAG, a.is_unlocked(72), "20,000 points in one game: Big Baller")
	# knife streak: 15 knife kills in a row
	var front := p.global_position - p.global_basis.z * 1.0
	for i in 15:
		var z := _zombie(front + Vector3(0, 0.1, 0))
		await get_tree().physics_frame
		z.take_damage(1e7, false, p, true)
	await _wait(0.1)
	_check(TAG, a.is_unlocked(64) and not a.is_unlocked(65), "15 knife kills in a row: Feel My Blade (%d)" % a.session.get("knife.killsinarow", 0))
	_check(TAG, a.stats.get("knife.totalzombiekilled", 0) == 15, "knife kills counted (%d)" % a.stats.get("knife.totalzombiekilled", 0))
	# a gun kill 16 m away: Eagle Eye (and the knife streak is broken)
	var far := _zombie(p.global_position - p.global_basis.z * 16.0 + Vector3.UP * 0.1)
	await get_tree().physics_frame
	far.take_damage(1e7, false, p)
	await _wait(0.1)
	_check(TAG, a.is_unlocked(29) and a.session.get("knife.killsinarow", 0) == 0, "kill from %.1f m: Eagle Eye" % a.session.get("global.maxkilldistance", 0.0))
	# two heads popped in the same frame: Severance; arms then legs: Hung, Drawn...
	var z1 := _zombie(front + Vector3(1, 0.1, 0))
	var z2 := _zombie(front + Vector3(-1, 0.1, 0))
	await _wait(0.3)
	z1.lose_head()
	z2.lose_head()
	await _wait(0.1)
	_check(TAG, a.is_unlocked(11), "two heads at once: Severance (%d)" % a.session.get("global.zombieheadoffsimu", 0))
	var z3 := _zombie(front + Vector3(0, 0.1, 1))
	await _wait(0.3)
	z3.lose_arm("left")
	await get_tree().process_frame
	z3.lose_arm("right")
	await get_tree().process_frame
	z3.become_crawler()
	await get_tree().process_frame
	z3.lose_head()
	await _wait(0.1)
	_check(TAG, a.is_unlocked(87) and a.is_unlocked(88), "arms, legs, head: Hung, Drawn... and Quartered")
	_check(TAG, int(a.stats.get("global.gibs", 0)) == 3 and int(a.stats.get("global.headlesszombie", 0)) == 3, "gibs %d, heads %d" % [a.stats.get("global.gibs", 0), a.stats.get("global.headlesszombie", 0)])
	for z in [z1, z2, z3]:
		z.take_damage(1e7, false, p)
	# rounds: Nacht wave 5
	game.round_number = 5
	await _wait(0.1)
	_check(TAG, a.is_unlocked(45) and not a.is_unlocked(46), "round 5 on Nacht: OK, I think I can do this...")
	# saved, and read back
	a.save()
	var cfg := ConfigFile.new()
	var ok_load := cfg.load(Achievements.SAVE_TEST) == OK
	_check(TAG, ok_load and cfg.has_section_key("unlocked", "radioSilence") and cfg.get_value("stats", "global.totalshotsfire", 0) >= 1000,
		"saved to %s" % ProjectSettings.globalize_path(Achievements.SAVE_TEST))
	var before := a.unlocked.size()
	a.load_progress()
	_check(TAG, a.unlocked.size() == before and a.is_unlocked(1), "read back: %d unlocked" % a.unlocked.size())
	print("[%s] unlocked: %s" % [TAG, ", ".join(a.unlocked.keys().map(func(k): return "%d %s" % [a.by_id[k.to_lower()]["num"], a.by_id[k.to_lower()]["name"]]))])
	# list screen
	await _wait(5.5)   # popups gone
	get_tree().paused = true
	var scr := AchievementsScreen.new()
	get_parent().add_child(scr)
	await _shot("achievement_list")
	scr._select("nacht_achievements")
	await _shot("achievement_list_nacht")
	scr.close()
	get_tree().paused = false
	# from the pause menu
	game.hud.open_pause()
	await get_tree().process_frame
	var btn: Button = null
	for b in game.hud.find_children("*", "Button", true, false):
		if (b as Button).text == "Obiettivi":
			btn = b
	if btn:
		btn.pressed.emit()
	await get_tree().process_frame
	var from_pause := get_tree().root.find_children("*", "", true, false).filter(func(n): return n is AchievementsScreen).size()
	_check(TAG, btn != null and from_pause > 0, "pause menu \"Obiettivi\" opens the list")
	await _shot("achievement_list_pause")
	for n in get_tree().root.find_children("*", "", true, false):
		if n is AchievementsScreen:
			n.close()
	game.hud.get("_pause").close()
	print("[%s] %s (%d failures)" % [TAG, "OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


# Walk (or wade on Shi No Numa) and log the step sounds: the interval follows
# FOOTSTEP_STRIDE / (|vx|+|vz|), alternating the two sounds of the list.
func _footstep_test() -> void:
	const TAG := "footstep"
	await game.level.wait_navigation()
	game.set_process(false)
	var p := game.player
	p.health = 1e9
	var water := game.level_name == "shinonuma"
	if water:
		p.global_position = Vector3(29.0, 0.5, 38.0)   # storage swamp (swamp_tests.gd wade)
		p.rotation.y = 0.0
	await _wait(1.0)
	_check(TAG, not water or game.level.in_water(p.global_position), "player in the water" if water else "player on dry floor")
	# the interval uses |vx| + |vz| in the player's frame: walk forward, then with the
	# stick on the diagonal (towards the most open direction)
	var dirs := []
	for k in 8:
		dirs.append(Vector3.FORWARD.rotated(Vector3.UP, k * PI / 4))
	var start := p.global_position
	for run in ([["straight", Vector2(0, -1)]] if water else [["straight", Vector2(0, -1)], ["diagonal", Vector2(0.7071, -0.7071)]]):
		p.global_position = start
		p.velocity = Vector3.ZERO
		await _wait(0.3)
		var d: Vector3 = Vector3.FORWARD if water else _open_direction(dirs)   # the swamp test's wade stays in the water
		var stick: Vector2 = run[1]
		p.rotation.y = atan2(-d.x, -d.z) + (PI / 4 if stick.x > 0.0 else 0.0)
		p.footsteps_log.clear()
		p.move_input = stick
		await _wait(3.0)
		p.move_input = Vector2.ZERO
		var log: Array = p.footsteps_log.duplicate()
		var gaps := []
		for i in range(1, log.size()):
			gaps.append(log[i][0] - log[i - 1][0])
		var mean := 0.0
		for g in gaps:
			mean += g / gaps.size()
		var speed := Player.SPEED * (Level.WATER_MOVE_SPEED if water else 1.0)
		var expect := Player.FOOTSTEP_STRIDE / (speed * (absf(stick.x) + absf(stick.y)))
		var names := log.map(func(e): return e[1])
		var alternating := true
		for i in range(1, names.size()):
			alternating = alternating and names[i] != names[i - 1]
		var want := "water_walk" if water else "player_footstep_walk"
		_check(TAG, log.size() >= 3 and names.all(func(n): return String(n).begins_with(want)) and alternating,
			"%s: %d steps %s" % [run[0], log.size(), names])
		_check(TAG, gaps.size() > 0 and absf(mean - expect) < 0.06, "%s: mean interval %.3f s (expected %.3f)" % [run[0], mean, expect])
		await _wait(0.6)
	# standing still: no steps
	p.footsteps_log.clear()
	await _wait(1.0)
	_check(TAG, p.footsteps_log.is_empty(), "no steps standing still")
	print("[%s] %s (%d failures)" % [TAG, "OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


# the direction (of the given ones) with the most free floor in front of the player
func _open_direction(dirs: Array) -> Vector3:
	var space := game.get_world_3d().direct_space_state
	var best: Vector3 = dirs[0]
	var best_d := -1.0
	var from := game.player.global_position + Vector3.UP * 0.9
	for d: Vector3 in dirs:
		var q := PhysicsRayQueryParameters3D.create(from, from + d * 20.0, 1)
		q.exclude = [game.player.get_rid()]
		var h := space.intersect_ray(q)
		var dist := 20.0 if h.is_empty() else from.distance_to(h["position"])
		if dist > best_d:
			best_d = dist
			best = d
	return best
