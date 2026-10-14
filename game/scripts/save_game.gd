# Game in progress saved and resumed, like the original SaveProgress / LoadProgress
# (kiwi strings; "resumegame" button, LS key "Resume Carnage"; ingame.lua 50-56 calls
# Script.Level.Resume / Script.Mode.Resume instead of Begin, and waves.lua Resume
# recalculates the wave of the saved round and brings the fog back in a dog round).
# One slot, user://savegame.json (tests: user://savegame_test.json), written when
# quitting to the menu, when the app goes to the background or loses focus, when the
# window is closed and at the start of every round; deleted at game over. A resumed
# game restarts the saved round from its beginning (as the original Resume does).
# The file is versioned: anything that does not validate is ignored and deleted.
# Version 2 adds barricade boards, power-up timers and pickups on the ground, mystery
# box counters, teleporter/zipline details, achievement session stats and the save
# providers below; a version 1 save still loads (the new parts keep their defaults).
#
# SAVE PROVIDERS (extension point for new systems): any node inside the game scene in
# the group "savable" (SaveGame.PROVIDER_GROUP) with
#   func save_state() -> Dictionary        # JSON-safe values only (numbers come back as float)
#   func load_state(d: Dictionary) -> void
# and optionally `func save_key() -> String` (default: its node path from the game; give
# a stable key when the node name is not deterministic). Its state is stored under
# "providers"/<key>. On resume load_state is called once per node, as soon as it exists
# before the rounds begin (end of apply_world, apply_player and begin_rounds); a node
# created later can fetch its state with SaveGame.resumed_state(self) / resumed(game, key).
class_name SaveGame
extends RefCounted

const VERSION := 2
const MIN_VERSION := 1     # oldest version still loaded
const PROVIDER_GROUP := "savable"
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
	if not d is Dictionary or int(d.get("version", -1)) < MIN_VERSION or int(d.get("version", -1)) > VERSION:
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
		d["box_used_count"] = box.used_count     # teddy rule counter (whole game)
		d["box_uses"] = box.uses
		# leaving with the teddy: it reappears elsewhere on resume (the 950 were refunded)
		d["box_moving"] = box.state in [MysteryBox.State.TEDDY, MysteryBox.State.LEAVING, MysteryBox.State.GONE]
		# bought but not taken yet: the purchase is given back
		if box.state in [MysteryBox.State.OPENING, MysteryBox.State.CYCLING, MysteryBox.State.OFFERED, MysteryBox.State.LOWERING] and box.get("_buyer") == p:
			d["points"] = int(d["points"]) + MysteryBox.COST
	if lv.teleporters:
		var tp := lv.teleporters
		d["pads_linked"] = tp.pads.filter(func(x): return x.state == "linked").map(func(x): return x.entity)
		d["tele_cooldown"] = tp.cooldown
		d["tele_count"] = tp.teleports
		d["tele_rolls"] = tp.teleports_occured
	if lv.zipline:
		var z := lv.zipline
		d["zipline"] = z.activated
		# the car is saved where it is going (or resting); a rider goes along with it
		var at_bottom := z.car_state in [Zipline.Car.DOWN, Zipline.Car.AT_BOTTOM_WAIT, Zipline.Car.AT_BOTTOM]
		d["zipline_bottom"] = at_bottom
		var riders: Dictionary = z.get("_riders")
		if riders.has(p):
			var a: Transform3D = z.get("_a")
			var b: Transform3D = z.get("_b")
			var dest := Transform3D(a.basis, b.origin if at_bottom else a.origin) * (riders[p] as Vector3)
			d["pos"] = [dest.x, dest.y, dest.z]
	if lv.pack_a_punch:
		# a weapon in the machine (paid): it comes back already upgraded
		var pap := lv.pack_a_punch
		var held: Dictionary = pap.get("_weapon")
		if pap.state != PackAPunch.State.IDLE and not held.is_empty():
			var i := p.weapons.find(held)
			var up := {"name": held["name"], "upgraded": true}
			var s := Weapons.stats_of(up)
			up["mag"] = s["mag"]
			up["reserve"] = s["reserve"]
			if i >= 0:
				weapons[i] = up
			elif weapons.size() >= 2:
				weapons[p.current] = up
			else:
				weapons.append(up)
	# barricades: boards left per window (only the damaged ones)
	var boards := {}
	for w in lv.windows:
		if is_instance_valid(w) and w.boards < Barricade.MAX_BOARDS:
			boards[String(w.name)] = w.boards
	d["boards"] = boards
	# power-ups running (seconds left) and pickups lying on the ground (kind, place, age)
	d["powerup_timers"] = (g.get("_timers") as Dictionary).duplicate()
	var pickups := []
	for n in g.get_children():
		if n is Powerup and not n.is_queued_for_deletion():
			var at: Vector3 = n.global_position
			pickups.append({"kind": n.kind, "pos": [at.x, at.y, at.z], "age": n.get("_age")})
	d["pickups"] = pickups
	d["drop_kills"] = g.get("_drop_kills")
	d["drop_points"] = g.get("_drop_points")
	# achievement statistics of this game (achievements.gd session)
	var ach := Achievements.instance
	if ach and ach.game == g:
		d["ach_session"] = ach.session.duplicate(true)
	d["providers"] = capture_providers(g)
	return d


# ------------------------------------------------------------------ providers

static func _provider_key(g: Game, n: Node) -> String:
	if n.has_method("save_key"):
		return String(n.call("save_key"))
	return String(g.get_path_to(n))


static func _providers(g: Game) -> Array:
	if not g.is_inside_tree():
		return []
	return g.get_tree().get_nodes_in_group(PROVIDER_GROUP).filter(func(n):
		return is_instance_valid(n) and g.is_ancestor_of(n) and n.has_method("save_state") and not n.is_queued_for_deletion())


static func capture_providers(g: Game) -> Dictionary:
	var out := {}
	for n in _providers(g):
		var s = n.call("save_state")
		if s is Dictionary:
			out[_provider_key(g, n)] = s
	return out


# load_state on every provider that has a saved state and was not loaded yet
static func load_providers(g: Game, d: Dictionary) -> void:
	var saved = d.get("providers", {})
	if not saved is Dictionary:
		return
	for n in _providers(g):
		if n.has_meta("save_loaded") or not n.has_method("load_state"):
			continue
		var k := _provider_key(g, n)
		if saved.has(k) and saved[k] is Dictionary:
			n.set_meta("save_loaded", true)
			n.call("load_state", saved[k])


# State saved for `key` in the game being resumed ({} when not resuming).
static func resumed(g: Game, key: String) -> Dictionary:
	if g == null:
		return {}
	var r: Dictionary = g.get("_resume") if g.get("_resume") is Dictionary else {}
	var s = r.get("providers", {}).get(key, {}) if r.get("providers", {}) is Dictionary else {}
	return s if s is Dictionary else {}


static func resumed_state(n: Node) -> Dictionary:
	var g: Game = null
	var x := n
	while x and g == null:
		g = x as Game
		x = x.get_parent()
	return resumed(g, _provider_key(g, n)) if g else {}


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
		if d.get("box_moving", false):
			# saved while leaving with the teddy: at once where WarpMysteryBox would put it
			var mem: Array = box.get("_memory")
			var choices := box.locations.filter(func(n): return not n in mem and n != box.entity)
			if choices.is_empty():
				choices = box.locations.filter(func(n): return n != box.entity)
			if not choices.is_empty():
				box.call("_place", choices.pick_random())
		box.used_count = int(d.get("box_used_count", box.used_count))
		box.uses = int(d.get("box_uses", box.uses))
		box.moved.emit(box.entity)   # Der Riese map boards (derriese_extras.gd)
	if lv.teleporters:
		var tp := lv.teleporters
		tp.cooldown = float(d.get("tele_cooldown", 0.0))
		tp.teleports = int(d.get("tele_count", 0))
		tp.teleports_occured = int(d.get("tele_rolls", 0))
	if lv.teleporters and d.get("pads_linked") is Array:
		var linked: Array = d["pads_linked"]
		for pad in lv.teleporters.pads:
			if pad.entity in linked:
				pad.state = "linked"
		if not linked.is_empty():
			lv.teleporters.call("_update_door")
			if lv.pack_a_punch:
				lv.pack_a_punch.call("_refresh")
			lv.teleporters.peer_state_changed.emit()   # Der Riese teleporter map boards
	if lv.zipline and d.get("zipline", false) and not lv.zipline.activated:
		lv.zipline.activated = true
		g.open_area("ledge")
		lv.zipline.gate.open()
	if lv.zipline and lv.zipline.activated:
		# car resting at the end it was at or going to; the doctor's switch as the Lua leaves
		# it (on while the car is down, "call" once it is back at the top)
		var z := lv.zipline
		var bottom: bool = d.get("zipline_bottom", false)
		var a: Transform3D = z.get("_a")
		var b: Transform3D = z.get("_b")
		z.set("_t", 1.0 if bottom else 0.0)
		z.car.global_transform = Transform3D(a.basis, b.origin if bottom else a.origin)
		z.car_state = Zipline.Car.AT_BOTTOM if bottom else Zipline.Car.AT_TOP
		z.switch.state = Zipline.ZipSwitch.S.ON if bottom else Zipline.ZipSwitch.S.IDLE
		Zipline._pose(z.switch.get("_lever"), Zipline.LEVER_ON if bottom else Zipline.LEVER_OFF)
	# barricades: boards left (finalize() poses them once the level collision exists)
	var boards = d.get("boards", {})
	if boards is Dictionary:
		for w in lv.windows:
			if boards.has(String(w.name)):
				w.boards = clampi(int(boards[String(w.name)]), 0, Barricade.MAX_BOARDS)
				w.call("_update_boards")
	load_providers(g, d)


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
	load_providers(g, d)   # player items (belts, betties...) given above or at spawn


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
	# power-ups still running, with the seconds they had left
	var timers = d.get("powerup_timers", {})
	if timers is Dictionary:
		for k in timers:
			if not k in ["instakill", "doublepoints"] or float(timers[k]) <= 0.0:
				continue
			g._timers[k] = float(timers[k])
			if k == "instakill":
				g.insta_kill = true
			else:
				g.points_multiplier = 2
	# pickups on the ground keep the life they had left
	var pickups = d.get("pickups", [])
	if pickups is Array:
		for e in pickups:
			if not e is Dictionary or not Powerup.KINDS.has(String(e.get("kind", ""))):
				continue
			var at: Array = e.get("pos", [])
			if at.size() != 3:
				continue
			var pu := Powerup.new()
			pu.setup(g, String(e["kind"]), Vector3(at[0], at[1], at[2]) - Vector3.UP * 0.6)
			pu.set("_age", clampf(float(e.get("age", 0.0)), 0.0, Powerup.LIFETIME - 1.0))
			g.add_child(pu)
	g.set("_drop_kills", int(d.get("drop_kills", 0)))
	g.set("_drop_points", int(d.get("drop_points", 0)))
	# achievement statistics of this game; the round observer counts the restarted round
	# again, so its no-damage streak goes back by the round being replayed
	var ach := Achievements.instance
	var sess = d.get("ach_session", null)
	if ach and ach.game == g and sess is Dictionary:
		ach.session = (sess as Dictionary).duplicate(true)
		if not ach.session.get("weapons_used") is Dictionary:
			ach.session["weapons_used"] = {}
		if not d.get("round_done", false) and ach.session.has("session_wavenodamage"):
			ach.session["session_wavenodamage"] = maxf(float(ach.session["session_wavenodamage"]) - 1.0, 0.0)
		ach.set("_last_round", g.round_number)
		if g.level.teleporters:
			ach.set("_tele_used", g.level.teleporters.teleports)
	load_providers(g, d)


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
				if game.hud and Settings.get_value("auto_pause"):   # option "Auto-Pause"
					game.hud.open_pause()
			NOTIFICATION_WM_CLOSE_REQUEST:
				SaveGame.save(game)
