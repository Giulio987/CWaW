# Sounds and timings of the guns' CIsAnimStateMachine states (tools/weapon_states.py ->
# weapon_states.json; layout and state indices documented there). Used by player.gd
# (fire / reload sounds and durations) and viewmodel.gd (animations).
#   reload      states 20-22 (rounds left in the magazine), 23-25 (empty), 26-28 / 29-31
#               with Speed Cola: each plays its sound sequence (colt45 -> colt_reload
#               13565bed, garand -> 51e1a653, shotgun / sawnoff with rounds left ->
#               f58d101a, empty -> shotgun_reload 93f646a3...). The trench gun loads shell
#               by shell: start 20 (0.98 s), one 0.444 s loop per shell (21: 96360869
#               trenchgun_reload, "reload 1"; upgraded "reload 2"), end 22 (1.17 s, pump
#               b1f8fa5b trenchgun_rechamber).
#   fire_last   state 17, the shot that empties the magazine: the Garand plays 09664794
#               (shot + clip ping) instead of its fire sound, the Browning another animation.
#   rechamber   state 53 / 54 after every shot (Kar98k, Springfield, Arisaka: bolt;
#               trench gun: pump), with its sound; already part of Weapons "rate".
#   upgrade_sound  playSoundUpgrade 19571fe7 of the fire states: an extra layer on every
#               shot of a Pack-a-Punched gun (kiwi va 0x2070d8 checks the held gun's 0x142,
#               set on "<gun>_upgrade" guns, and 0x143: not the flamethrower).
class_name GunStates

const PATH := "res://assets/characters/ingame/player/weapon_states.json"
const VOLUME_DB := -4.0   # as Sfx.sequence / weapon_fire

static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_data = d
	return _data


# States of a held gun ({name, upgraded?}): its "<name>_upgrade" entry when upgraded.
static func of(w: Dictionary) -> Dictionary:
	var n: String = w["name"]
	if w.get("upgraded", false) and data().has(n + "_upgrade"):
		return data()[n + "_upgrade"]
	return data().get(n, {})


static func reload_key(empty: bool, speed: bool) -> String:
	return "reload" + ("_speed" if speed else "") + ("_empty" if empty else "")


# How the reload goes: {"time": s, "key": phases key, "cycles": shell loops, "k": time scale}.
# Magazine guns: the remake's reload time (Weapons, upgrade values included) for rounds
# left, scaled by the original's ratio for the other states (empty magazine, Speed Cola).
# Shell by shell (a looping middle state): start + one loop per `reload n` rounds + end.
static func reload_plan(w: Dictionary, s: Dictionary, speed: bool) -> Dictionary:
	var g := of(w)
	var empty: bool = w["mag"] <= 0
	var key := reload_key(empty, speed)
	var ph: Array = g.get(key, [])
	var base: Array = g.get("reload", [])
	var fallback := float(s["reload"]) * (Perks.SPEED_RELOAD if speed else 1.0)
	if ph.is_empty() or base.is_empty() or float(base[0]["ms"]) <= 0.0:
		return {"time": fallback, "key": "", "cycles": 0, "k": 1.0}
	if ph.size() == 3 and ph[1]["loop"]:
		var per := 1
		for e in ph[1]["events"]:
			if e[1] == "reload" and int(e[2]) > 0:
				per = int(e[2])
		var need: int = mini(int(s["mag"]) - int(w["mag"]), int(w["reserve"]))
		var cycles: int = maxi(1, ceili(float(need) / per))
		var t := (float(ph[0]["ms"]) + cycles * float(ph[1]["ms"]) + float(ph[2]["ms"])) / 1000.0
		# the "reload n" output of each loop: n rounds in at that time; the loop state is the
		# only one with a shoot transition (the start and end states are not)
		var at := 0.0
		for e in ph[1]["events"]:
			if e[1] == "reload":
				at = float(e[0]) / 1000.0
		var start := float(ph[0]["ms"]) / 1000.0
		var shells := []
		var left := need
		for i in cycles:
			shells.append([start + i * float(ph[1]["ms"]) / 1000.0 + at, mini(per, left)])
			left -= per
		return {"time": t, "key": key, "cycles": cycles, "k": 1.0, "shells": shells,
			"window": [start, start + cycles * float(ph[1]["ms"]) / 1000.0]}
	var orig := 0.0
	for p in ph:
		orig += float(p["ms"])
	var time := float(s["reload"]) * orig / float(base[0]["ms"])
	return {"time": time, "key": key, "cycles": 0, "k": time * 1000.0 / orig}


# Plays the sounds of the reload states; `alive` (Callable -> bool) stops the ones still to
# come when the reload is cut short (weapon switch).
static func reload_sounds(w: Dictionary, plan: Dictionary, alive: Callable) -> void:
	if plan["key"] == "" or Sfx.instance == null:
		return
	var t := 0.0
	var k: float = plan["k"]
	for p in of(w).get(plan["key"], []):
		var times := 1
		if p["loop"]:
			times = int(plan["cycles"])
		for i in times:
			for e in p["events"]:
				if e[1] == "playsound":
					_later(t + float(e[0]) / 1000.0 * k, String(e[2]), alive)
				elif e[1] == "playSoundSequence":
					for st in Sfx.instance._index["sequences"].get(String(e[2]), []):
						_later(t + (float(e[0]) + float(st[0])) / 1000.0 * k, String(st[1]), alive)
			t += float(p["ms"]) / 1000.0 * k


static func _later(t: float, sound: String, alive: Callable) -> void:
	if t <= 0.0:
		Sfx.instance.play(sound, VOLUME_DB)
		return
	Sfx.instance.get_tree().create_timer(t, false).timeout.connect(func():
		if alive.call():
			Sfx.instance.play(sound, VOLUME_DB))


# Fire sounds of one shot: the gun's own (state 16 / 35), or the last round's when it
# differs (state 17: the Garand's ping), plus the Pack-a-Punch layer.
static func fire_sounds(w: Dictionary, last: bool) -> void:
	if Sfx.instance == null:
		return
	var g := of(w)
	var own := _sound(g.get("fire"))
	var other := _sound(g.get("fire_last")) if last else ""
	if other != "" and other != own:
		Sfx.instance.play(other, VOLUME_DB, randf_range(0.97, 1.03))
	else:
		Sfx.instance.weapon_fire(w["name"])
	if w.get("upgraded", false) and String(g.get("upgrade_sound", "")) != "":
		Sfx.instance.play(g["upgrade_sound"], VOLUME_DB)


static func _sound(st) -> String:
	if st is Dictionary:
		for e in st["events"]:
			if e[1] == "playsound":
				return String(e[2])
	return ""


# Rechamber after a shot (bolt / pump): its sound once the fire state is over (the fire
# and rechamber states `rate` x faster with Double Tap, as the remake's cadence).
static func rechamber_sound(w: Dictionary, aiming: bool, rate: float, alive: Callable) -> void:
	var g := of(w)
	var st = g.get("aim_rechamber" if aiming else "rechamber")
	var fire = g.get("aim_fire" if aiming else "fire")
	if not st is Dictionary or not fire is Dictionary or Sfx.instance == null:
		return
	var delay := float(fire["ms"]) / 1000.0 / rate
	for e in st["events"]:
		if e[1] == "playsound":
			_later(delay + float(e[0]) / 1000.0 / rate, String(e[2]), alive)


# The sounds of any state (playsound, playSoundSequence, playSound3 = the name hash
# continued with "1".."3", e.g. the Monkey Bomb throw 42123fa7 -> 845a34b8..ba), 2D, while
# `alive` holds. Used for the Monkey Bomb throw (state 46 "Throwingmonkeybomb").
static func state_sounds(st, alive: Callable) -> void:
	if not st is Dictionary or Sfx.instance == null:
		return
	for e in st["events"]:
		var t := float(e[0]) / 1000.0
		match String(e[1]):
			"playsound":
				_later(t, String(e[2]), alive)
			"playSound3":
				var h := (String(e[2]).hex_to_int() * 33 + "123".unicode_at(randi() % 3)) & 0xFFFFFFFF
				_later(t, "%08x" % h, alive)
			"playSoundSequence":
				for s in Sfx.instance._index["sequences"].get(String(e[2]), []):
					_later(t + float(s[0]) / 1000.0, String(s[1]), alive)
