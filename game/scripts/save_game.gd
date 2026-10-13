# Game in progress saved and resumed, like the original SaveProgress / LoadProgress
# (kiwi strings; "resumegame" button, LS key "Resume Carnage"; ingame.lua 50-56 calls
# Script.Level.Resume / Script.Mode.Resume instead of Begin, and waves.lua Resume
# recalculates the wave of the saved round and brings the fog back in a dog round).
# One slot, user://savegame.json (tests: user://savegame_test.json), written when
# quitting to the menu, when the app goes to the background or loses focus, when the
# window is closed and at the start of every round; deleted at game over. A resumed
# game restarts the saved round from its beginning (as the original Resume does).
# The file is versioned: anything that does not validate is ignored and deleted.
class_name SaveGame
extends RefCounted

const VERSION := 1
const SAVE := "user://savegame.json"
const SAVE_TEST := "user://savegame_test.json"

static var pending := {}   # set by the menu's Riprendi button, read by Game.start


static func path() -> String:
	var a := Achievements.instance
	return SAVE_TEST if a and a.test_mode else SAVE


# ------------------------------------------------------------------ file

static func load_save() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path()))
	if not _valid(d):
		print("[save] ignoring an incompatible save")
		clear()
		return {}
	return d


static func has_save() -> bool:
	return not load_save().is_empty()


static func clear() -> void:
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path()))


static func _valid(d) -> bool:
	if not d is Dictionary or int(d.get("version", -1)) != VERSION:
		return false
	for k in ["map", "round", "points", "weapons", "current", "perks", "open_areas", "debris_closed"]:
		if not d.has(k):
			return false
	if not DirAccess.dir_exists_absolute("res://assets/levels/" + String(d["map"])) or int(d["round"]) < 1:
		return false
	if not d["weapons"] is Array or (d["weapons"] as Array).is_empty():
		return false
	for w in d["weapons"]:
		if not w is Dictionary or not Weapons.STATS.has(String(w.get("name", ""))):
			return false
	return true


# Debug starts and games already over are not saved (Recruit games are).
static func can_save(g: Game) -> bool:
	return g != null and g.is_inside_tree() and g.player != null and not g.player.dead \
		and g.round_number >= 1 and not Game.debug_start and g.level != null and g.level.nav_ready


static func save(g: Game) -> bool:
	if not can_save(g):
		return false
	var d := capture(g)
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	print("[save] round %d, %d points saved to %s" % [d["round"], d["points"], path()])
	return true


# ------------------------------------------------------------------ capture

static func capture(g: Game) -> Dictionary:
	var p := g.player
	var lv := g.level
	var weapons := []
	for w in p.weapons:
		weapons.append((w as Dictionary).duplicate(true))
	var d := {
		"version": VERSION,
		"map": g.level_name,
		"saved_at": Time.get_datetime_string_from_system(),
		"difficulty": Game.difficulty,
		"round": g.round_number,
		# a finished round resumes with the next one
		"round_done": g.get("_between_rounds") == true,
		"dog_round": g.dog_round,
		"dog_wave_counter": g.dog_wave_counter,
		"waves_since_dog": g.waves_since_dog,
		"points": p.points,
		"weapons": weapons,
		"current": p.current,
		"perks": p.perks.duplicate(),
		"kills": g.kills,
		"headshots": g.headshots,
		"score": g.score,
		"open_areas": g.open_areas.duplicate(),
		"debris_closed": lv.debris.filter(func(x): return is_instance_valid(x)).map(func(x): return x.entity),
		"power": lv.power_on,
		"perk_order": lv.perk_order.duplicate(),
		"pos": [p.global_position.x, p.global_position.y, p.global_position.z],
		"yaw": p.rotation.y,
	}
	var gb := GrenadeBelt.of(p)
	if gb:
		d["grenades"] = gb.count
	var mb := MonkeyBelt.of(p)
	if mb:
		d["monkeys"] = mb.count
	if not lv.boxes.is_empty():
		var box: MysteryBox = lv.boxes[0]
		d["box"] = box.entity
		d["box_memory"] = box.get("_memory")
	if lv.teleporters:
		d["pads_linked"] = lv.teleporters.pads.filter(func(x): return x.state == "linked").map(func(x): return x.entity)
	if lv.zipline:
		d["zipline"] = lv.zipline.activated
	return d


# ------------------------------------------------------------------ restore

# World state, from Game.start before the first navigation bake.
static func apply_world(g: Game, d: Dictionary) -> void:
	var lv := g.level
	# debris bought in the saved game: removed without the opening animation
	var closed: Array = d["debris_closed"]
	for x in lv.debris.duplicate():
		if is_instance_valid(x) and not x.entity in closed:
			lv.debris.erase(x)
			x.queue_free()
	g.open_areas.clear()
	for a in d["open_areas"]:
		g.open_areas.append(String(a))
	if d.get("power", true) and not lv.power_on:
		var bridge := lv.nav_region.get_node_or_null("Bridge")
		if bridge:
			bridge.lower(true)
		# as turn_on_power, without the announcer and the machines' jingles
		lv.power_on = true
		lv.power_changed.emit(true)
	if d.has("box") and not lv.boxes.is_empty() and lv.has_entity(String(d["box"])):
		var box: MysteryBox = lv.boxes[0]
		if box.entity != String(d["box"]):
			box.call("_place", String(d["box"]))
		if d.get("box_memory") is Array:
			box.set("_memory", (d["box_memory"] as Array).duplicate())
	if lv.teleporters and d.get("pads_linked") is Array:
		var linked: Array = d["pads_linked"]
		for pad in lv.teleporters.pads:
			if pad.entity in linked:
				pad.state = "linked"
		if not linked.is_empty():
			lv.teleporters.call("_update_door")
			if lv.pack_a_punch:
				lv.pack_a_punch.call("_refresh")
	if lv.zipline and d.get("zipline", false) and not lv.zipline.activated:
		lv.zipline.activated = true
		g.open_area("ledge")
		lv.zipline.gate.open()


# Player state (points, weapons with their ammo, perks, grenades, position).
static func apply_player(g: Game, d: Dictionary) -> void:
	var p := g.player
	p.points = int(d["points"])
	p.weapons.clear()
	for w in d["weapons"]:
		var wd: Dictionary = (w as Dictionary).duplicate(true)
		wd["mag"] = int(wd.get("mag", 0))
		wd["reserve"] = int(wd.get("reserve", 0))
		p.weapons.append(wd)
	p.current = clampi(int(d["current"]), 0, p.weapons.size() - 1)
	for k in d["perks"]:
		if Perks.INFO.has(String(k)):
			p.give_perk(String(k))
	g.kills = int(d.get("kills", 0))
	g.headshots = int(d.get("headshots", 0))
	g.score = int(d.get("score", 0))
	var gb := GrenadeBelt.of(p)
	if gb and d.has("grenades"):
		gb.set("_round_seen", int(d["round"]))   # no extra round refill on resume
		gb.set_count(int(d["grenades"]))
	if d.has("monkeys") and int(d["monkeys"]) > 0:
		var mb := MonkeyBelt.give(p)
		mb.count = int(d["monkeys"])
	# the achievement observer must not count the restored perks/weapons as new drinks
	# or purchases (achievements.gd _observe_player)
	var ach := Achievements.instance
	if ach:
		ach.set("_perks_seen", p.perks.duplicate())
		var seen := {}
		for w in p.weapons:
			seen[String(w["name"]) + ("+" if w.get("upgraded", false) else "")] = true
		ach.set("_weapon_seen", seen)
	var pos: Array = d.get("pos", [])
	if pos.size() == 3:
		p.global_position = Vector3(pos[0], pos[1], pos[2])
		p.rotation.y = float(d.get("yaw", 0.0))
	p.changed.emit()


# Rounds (from Game._begin): waves.lua Resume recalculates the saved wave, a dog
# round brings back the fog (StartDogWave does it here).
static func begin_rounds(g: Game, d: Dictionary) -> void:
	g.dog_wave_counter = int(d.get("dog_wave_counter", 0))
	g.waves_since_dog = int(d.get("waves_since_dog", 0))
	var r := int(d["round"])
	if d.get("round_done", false):
		g.round_number = r
		g.get_tree().create_timer(2.0, false).timeout.connect(g._next_round)
	elif d.get("dog_round", false) and g.dog_rounds:
		g.round_number = r - 1
		g.dog_wave_counter -= 1      # _start_dog_round counts it again
		g.get_tree().create_timer(2.0, false).timeout.connect(g._start_dog_round)
	else:
		g.round_number = r - 1
		g.get_tree().create_timer(2.0, false).timeout.connect(g._next_round)
	g.hud.round_changed(r)


# ------------------------------------------------------------------ app lifecycle

# Child of the game: saves at the start of every round and when the app is left
# (iOS: NOTIFICATION_APPLICATION_PAUSED before going to the background; focus lost
# on a desktop; window closed), and pauses the game when it loses focus.
class Watcher:
	extends Node
	var game: Game
	var _round := -1

	func _init(g: Game) -> void:
		game = g
		name = "SaveWatcher"
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_d: float) -> void:
		# other tests and debug captures do not write the test save behind the save test
		if Achievements.instance and Achievements.instance.test_mode and not OS.get_cmdline_user_args().has("--save-test"):
			return
		if game.round_number != _round and not game.get("_between_rounds"):
			_round = game.round_number
			SaveGame.save(game)

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
				# tests and debug captures keep running when the window is not in front
				if Achievements.instance and Achievements.instance.test_mode:
					return
				SaveGame.save(game)
				if game.hud:
					game.hud.open_pause()
			NOTIFICATION_WM_CLOSE_REQUEST:
				SaveGame.save(game)
