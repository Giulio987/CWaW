# Save / resume, HUD and game over checks (prints OK/FAIL, screenshots in analysis/preview):
#   -- <map> --save-test write            changes the game (points, weapons, perks, a debris,
#                                         power, teleporter pad, box), saves, quits
#   -- <map> --save-test check --resume   resumes that save and compares (save_resume.png)
#   -- <map> --hud-test                   power-up icons, pickup message, damage strips,
#                                         low-ammo blink, proximity arrow (hud_powerups.png)
#   -- <map> --gameover-test              dies: game over screen + leaderboard (game_over.png)
# Saves go to user://savegame_test.json and user://leaderboard_test.cfg (test mode).
class_name SaveTests
extends Node

const EXPECTED := "user://save_test_expected.json"

var game: Game
var fails := 0


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t := SaveTests.new()
	t.game = game_
	parent.add_child(t)
	if args.has("--save-test"):
		var i := args.find("--save-test")
		if i + 1 < args.size() and args[i + 1] == "check":
			t._check_phase()
		else:
			t._write_phase()
	elif args.has("--hud-test"):
		t._hud_test()
	else:
		t._gameover_test()


func _check(ok: bool, what: String) -> void:
	print("[save] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_round() -> void:
	for i in 600:
		if game.round_number >= 1 and game.level.nav_ready:
			break
		await _wait(0.1)
	await _wait(1.0)


func _finish() -> void:
	print("[save] RESULT %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _write_phase() -> void:
	await _wait_round()
	var p := game.player
	var lv := game.level
	p.points = 4321
	p.give_weapon("thompson")
	p.weapon()["mag"] = 7
	p.weapon()["reserve"] = 55
	p.give_perk("jugga")
	game.kills = 17
	game.headshots = 5
	game.score = 9999
	var want := {}
	if not lv.debris.is_empty():
		var d: Debris = lv.debris[0]
		want["debris"] = d.entity
		d.open()
	if not lv.power_on:
		lv.turn_on_power()
	if lv.teleporters and not lv.teleporters.pads.is_empty():
		await _wait(0.2)
		lv.teleporters.pads[0].state = "linked"
		want["pad"] = lv.teleporters.pads[0].entity
		# a pad cooling down and a link in progress (teleporter.gd save_state)
		lv.teleporters.pads[0].cooldown = 15.0
		lv.teleporters.call("_start_link", lv.teleporters.pads[1], game.player)
		want["pad_linking"] = lv.teleporters.pads[1].entity
	if not lv.boxes.is_empty():
		var box: MysteryBox = lv.boxes[0]
		var other: Array = box.locations.filter(func(n): return n != box.entity)
		if not other.is_empty():
			box.call("_place", other[0])
	await _write_extras(want)
	await _wait(3.0)
	_check(SaveGame.save(game), "saved")
	var d := SaveGame.capture(game)
	want.merge(d)
	var f := FileAccess.open(EXPECTED, FileAccess.WRITE)
	f.store_string(JSON.stringify(want))
	f.close()
	print("[save] wrote round %d, areas %s, box %s, power %s" % [d["round"], d["open_areas"], d.get("box", ""), d["power"]])
	_finish()


func _check_phase() -> void:
	await _wait_round()
	var want = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
	if not want is Dictionary:
		_check(false, "expected values from the write phase")
		_finish()
		return
	var p := game.player
	var lv := game.level
	_check(game.round_number == int(want["round"]), "round %d (saved %d)" % [game.round_number, int(want["round"])])
	_check(p.points == int(want["points"]), "points %d" % p.points)
	_check(p.weapons.size() == want["weapons"].size(), "%d weapons" % p.weapons.size())
	for i in mini(p.weapons.size(), want["weapons"].size()):
		var a: Dictionary = p.weapons[i]
		var b: Dictionary = want["weapons"][i]
		_check(a["name"] == b["name"] and int(a["mag"]) == int(b["mag"]) and int(a["reserve"]) == int(b["reserve"]),
			"weapon %s %d/%d" % [a["name"], a["mag"], a["reserve"]])
	_check(p.current == int(want["current"]), "weapon in hand")
	_check(p.has_perk("jugga") and p.max_health > Player.MAX_HEALTH, "Juggernog")
	_check(game.kills == 17 and game.headshots == 5 and game.score >= 9999, "kills/headshots/score %d/%d/%d" % [game.kills, game.headshots, game.score])
	for a in want["open_areas"]:
		_check(a in game.open_areas, "area %s open" % a)
	if want.has("debris"):
		_check(not lv.debris.any(func(d): return is_instance_valid(d) and d.entity == want["debris"]), "debris %s gone" % want["debris"])
	_check(lv.power_on == bool(want["power"]), "power %s" % lv.power_on)
	if want.has("box"):
		_check(lv.boxes[0].entity == want["box"], "box at %s" % lv.boxes[0].entity)
	if want.has("pad"):
		_check(lv.teleporters.pads.any(func(x): return x.entity == want["pad"] and x.state == "linked"), "pad %s linked" % want["pad"])
	if want.has("pad_linking"):
		var tp := lv.teleporters
		_check(tp.log.any(func(e): return e[1] == "link_start " + want["pad_linking"]), "link of %s resumed" % want["pad_linking"])
		_check(tp.pads[0].cooldown > 0.0, "pad %s cooldown restored (%.1f s)" % [tp.pads[0].entity, tp.pads[0].cooldown])
	var pos: Array = want["pos"]
	_check(p.global_position.distance_to(Vector3(pos[0], pos[1], pos[2])) < 1.0, "position")
	_check(not SaveGame.load_save().is_empty(), "save kept while playing")
	_check_extras(want)
	await _shot("save_resume")
	_finish()


# Save version 2 parts: boards, power-ups and pickups, box counters, traps, easter
# eggs, fly trap, teleporter count, zipline, achievement session, providers.
func _write_extras(want: Dictionary) -> void:
	var p := game.player
	var lv := game.level
	if not lv.windows.is_empty():
		var w: Barricade = lv.windows[0]
		w.tear_board()
		w.tear_board()
		want["window"] = String(w.name)
		want["window_boards"] = w.boards
	game._timers["doublepoints"] = 25.0
	game.points_multiplier = 2
	var spot := p.global_position + p.global_transform.basis.x * 6.0
	game.spawn_powerup("maxammo", spot)
	want["pickup"] = [spot.x, spot.y, spot.z]
	if not lv.boxes.is_empty():
		lv.boxes[0].used_count = 7
	if lv.teleporters:
		lv.teleporters.teleports = 3
	var ach := Achievements.instance
	if ach and ach.game == game:
		ach.session["session_shotsfire"] = 42
		want["ach_shots"] = 42
	# traps: one running, one cooling down
	if lv.traps.size() > 0:
		lv.traps[0].activate()
		lv.traps[0]._timer = 28.0
		want["trap_active"] = lv.traps[0].entity
	if lv.traps.size() > 1:
		lv.traps[1].activate()
		lv.traps[1].call("_stop")
		want["trap_cool"] = lv.traps[1].entity
	# easter eggs of the map
	var eggs := game.get_node_or_null("RadioEggs") as RadioEggs
	if eggs:
		var hits := []
		match lv.level_name:
			"nacht":
				hits = ["RadioVolume", "RadioVolume"]
			"verruckt":
				hits = ["DentistChairVolume"]
			"derriese":
				hits = ["Radio1Trigger", "SpinalColumn1Trigger", "SpinalColumn2Trigger"]
			"shinonuma":
				hits = ["StartRadio1Trigger", "MeteorTrigger", "StorageRadioTrigger"]
		for h in hits:
			if eggs.triggers.has(h):
				eggs.trigger(h, p)
		want["eggs"] = eggs.save_state()
	# fly trap: activated, items out, one found (with a Pack-a-Punched gun)
	var ft := game.get_node_or_null("FlyTrap") as FlyTrap
	if ft:
		ft.activated = true
		ft.triggers[FlyTrap.TRIGGER].enabled = false
		ft.call("_set_up")
		var was: bool = p.weapon().get("upgraded", false)
		p.weapon()["upgraded"] = true
		ft.trigger("flyTrapItem2Trigger", p)
		p.weapon()["upgraded"] = was
		want["flytrap"] = ft.save_state()
	if lv.zipline:
		lv.zipline.switch_fired()   # car goes down empty
		want["zip_bottom"] = true
	await _wait(0.2)


# equal once both went through JSON (numbers become floats)
static func _same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify([a])) == JSON.parse_string(JSON.stringify([b]))


func _check_extras(want: Dictionary) -> void:
	var lv := game.level
	if want.has("window"):
		var ws := lv.windows.filter(func(w): return String(w.name) == want["window"])
		var b: int = ws[0].boards if not ws.is_empty() else -1
		# zombies may have torn more since the resume, never repaired
		_check(b >= 0 and b <= int(want["window_boards"]), "window %s boards %d (saved %d)" % [want["window"], b, int(want["window_boards"])])
	_check(game._timers.get("doublepoints", 0.0) > 0.0 and game.points_multiplier == 2,
		"Double Points running (%.1f s left)" % game._timers.get("doublepoints", 0.0))
	var at: Array = want["pickup"]
	var spot := Vector3(at[0], at[1], at[2])
	_check(game.get_children().any(func(n): return n is Powerup and n.kind == "maxammo" \
		and n.global_position.distance_to(spot + Vector3.UP * 0.6) < 0.5 and float(n.get("_age")) > 0.0), "Max Ammo pickup on the ground")
	if not lv.boxes.is_empty():
		_check(lv.boxes[0].used_count == 7, "box used_count %d" % lv.boxes[0].used_count)
	if lv.teleporters:
		_check(lv.teleporters.teleports == 3, "teleports %d" % lv.teleporters.teleports)
	if want.has("ach_shots"):
		var s := float(Achievements.instance.session.get("session_shotsfire", 0))
		_check(s >= 42.0, "achievement session shots %d" % s)
	for k in ["trap_active", "trap_cool"]:
		if want.has(k):
			var ts := lv.traps.filter(func(t): return t.entity == want[k])
			_check(not ts.is_empty() and ts[0].state != Trap.State.IDLE, "%s %s %s" % [k, want[k], Trap.State.keys()[ts[0].state] if not ts.is_empty() else "?"])
	if want.has("eggs"):
		var eggs := game.get_node_or_null("RadioEggs") as RadioEggs
		var now := eggs.save_state() if eggs else {}
		var w: Dictionary = want["eggs"]
		for k in w:
			_check(_same(now.get(k), w[k]), "egg %s = %s" % [k, now.get(k)])
	if want.has("flytrap"):
		var ft := game.get_node_or_null("FlyTrap") as FlyTrap
		var now := ft.save_state() if ft else {}
		_check(_same(now, want["flytrap"]), "fly trap %s" % now)
		_check(ft != null and ft.triggers["flyTrapItem1Trigger"].enabled and not ft.triggers["flyTrapItem2Trigger"].enabled, "fly trap items out, item 2 found")
	var ex := lv.nav_region.get_node_or_null("DerrieseExtras") as DerrieseExtras
	if ex and want.has("pad"):
		# map boards re-synced with the restored teleporters and box
		_check(ex.tele_map_state == "tele1", "teleporter map board %s" % ex.tele_map_state)
		var pose: String = DerrieseExtras.BOX_MAP_ANIMS.get(lv.boxes[0].entity, "")
		_check(pose != "" and ex.mystery_map_pose == pose, "mystery box map board %s" % ex.mystery_map_pose)
	if want.has("zip_bottom"):
		var z := lv.zipline
		_check(z.activated and z.car_state == Zipline.Car.AT_BOTTOM and z.car.global_position.distance_to((z.get("_b") as Transform3D).origin) < 0.1,
			"zipline car at the bottom")
	_check(int(SaveGame.load_save().get("version", 0)) == SaveGame.VERSION, "save version %d" % SaveGame.VERSION)


func _hud_test() -> void:
	await _wait_round()
	var p := game.player
	# a zombie at the player's back, inside the proximity range
	for i in 100:
		if game.get_children().any(func(n): return n is Zombie):
			break
		await _wait(0.2)
	game._timers["doublepoints"] = 21.0
	game._timers["instakill"] = 4.2          # inside PowerupGlowDurationMs: glowing
	game.points_multiplier = 2
	game.insta_kill = true
	game.hud.pickup_message(Powerup.KINDS["instakill"]["label"])
	p.weapon()["mag"] = 2                    # under LowClipPercentage
	p.changed.emit()
	p.take_hit(p.max_health * 0.7)
	var back := p.global_transform.basis.z.normalized()
	for n in game.get_children():
		if n is Zombie:
			n.global_position = p.global_position + back * 2.0 + p.global_transform.basis.x * 0.8
			break
	await _wait(0.6)
	_check(game.hud._powerups._slots["instakill"]["a"] > 0.5, "Insta-Kill icon shown")
	_check(game.hud._damage.level > 0.5, "damage strips")
	await _shot("hud_powerups")
	_finish()


func _gameover_test() -> void:
	await _wait_round()
	game.kills = 23
	game.headshots = 7
	game.score = 2150
	game.player.take_hit(100000.0)
	await _wait(2.5)
	var screen := game.hud.get_children().filter(func(n): return n is GameOverScreen)
	_check(not screen.is_empty(), "game over screen")
	var list := Leaderboard.entries(game.level_name)
	_check(list.any(func(e): return int(e["kills"]) == 23 and int(e["rounds"]) == game.round_number), "leaderboard entry")
	_check(SaveGame.load_save().is_empty(), "save deleted at game over")
	await _shot("game_over")
	_finish()
