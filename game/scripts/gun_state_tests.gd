# Checks for the guns' state sounds and first-person states (gun_states.gd, viewmodel.gd):
#   -- nacht --gun-state-test [--sfx-log]
# Every gun (and its upgrade): the reload states have sounds that exist; reloading plays
# them (the sounds heard are counted), with the original durations (empty magazine /
# Speed Cola variants, the trench gun shell by shell). Kar98k / Springfield / Arisaka /
# trench gun: the rechamber state runs after the shot (arms animation + sound). Garand:
# the last round plays 09664794. Sprint: running arms states. Monkey Bomb: throw sounds,
# cymbals on the ground. Screenshots analysis/preview/gunstate_<what>.png.
extends Node

var game: Game
var fails := 0
var heard := []   # sound keys started by Sfx (through the _stream log below)


static func start(parent: Node, game_: Game, _args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/gun_state_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	t._run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("[gunstate] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, false).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../analysis/preview"))
	img.save_png(ProjectSettings.globalize_path("res://../analysis/preview/gunstate_%s.png" % name))


func _arms(vm: Viewmodel) -> String:
	var ap := vm.get("_arms_anim") as AnimationPlayer
	return ap.current_animation if ap and ap.is_playing() else ""


# the sound keys a state list plays (sequences expanded)
func _keys(phases: Array) -> Array:
	var out := []
	for p in phases:
		for e in p["events"]:
			if e[1] == "playsound":
				out.append(String(e[2]))
			elif e[1] == "playSoundSequence":
				for s in Sfx.instance._index["sequences"].get(String(e[2]), []):
					out.append(String(s[1]))
	return out


func _run() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	var p := game.player
	p.health = 1e9
	var vm := p.get("_viewmodel") as Viewmodel
	var data := GunStates.data()
	_check(not data.is_empty(), "weapon_states.json loaded (%d entries)" % data.size())
	# ---- every gun: the reload sounds exist (flamethrower: heat, no reload states)
	for n in Weapons.STATS:
		for up in [false, true]:
			var w := {"name": n, "mag": 0, "reserve": 100, "upgraded": up}
			var g := GunStates.of(w)
			if g.is_empty():
				continue
			for key in ["reload", "reload_empty", "reload_speed", "reload_speed_empty"]:
				var ks := _keys(g.get(key, []))
				if n == "flamethrower":
					continue
				var missing := ks.filter(func(k): return Sfx.instance._stream(k) == null)
				_check(not ks.is_empty() and missing.is_empty(), "%s%s %s: %d sounds %s" % [n, "+" if up else "", key, ks.size(), missing])
	# ---- reload in game: timing and sounds heard
	var cases := [["colt45", 3, false, 2.275], ["colt45", 0, true, 1.137], ["garand", 0, false, 1.631],
		["sawnoff", 1, false, 2.638], ["sawnoff", 0, false, 3.083], ["shotgun", 0, true, 1.849],
		["trenchgun", 4, false, 0.984 + 2 * 0.444 + 1.174], ["trenchgun", 0, false, 0.984 + 6 * 0.444 + 0.860],
		["kar98", 2, false, 2.424], ["browning", 0, false, 7.305], ["stg44", 0, false, 1.910],
		["springfield", 0, false, 2.583], ["arisaka", 0, false, 2.272]]
	for c in cases:
		p.give_weapon(c[0])
		var w := p.weapon()
		w["mag"] = c[1]
		w["reserve"] = 100
		p.perks = ["speed"] if c[2] else []
		await _wait(0.3)
		heard.clear()
		var plan := GunStates.reload_plan(w, Weapons.stats_of(w), c[2])
		var expect := _keys(GunStates.of(w).get(plan["key"], []))
		if plan["cycles"] > 0:
			expect = []
			for ph in GunStates.of(w)[plan["key"]]:
				for i in (plan["cycles"] if ph["loop"] else 1):
					expect.append_array(_keys([ph]))
		Sfx.instance.set_meta("log", heard)
		p.reload()
		var t: float = p.get("_reloading")
		_check(absf(t - c[3]) < 0.01, "%s mag %d%s: reload %.3f s (expected %.3f)" % [c[0], c[1], " speed" if c[2] else "", t, c[3]])
		await _wait(0.5)
		if c[0] == "trenchgun" and c[1] == 0:
			await _shot("trench_reload")
		await _wait(t + 1.6)
		# (ambience, footsteps and music run meanwhile: only the gun's own sounds count)
		var own := heard.filter(func(k): return k in expect)
		_check(own == expect, "%s sounds %s (expected %s)" % [c[0], own, expect])
		Sfx.instance.set_meta("log", null)
	p.perks = []
	# ---- trench gun: one round per loop, a shot cuts the loop short
	p.give_weapon("trenchgun")
	var tw := p.weapon()
	tw["mag"] = 0
	tw["reserve"] = 100
	await _wait(0.5)
	p.reload()
	await _wait(0.984 + 0.41 + 0.05)
	_check(tw["mag"] == 1, "trench gun: 1 round in after the first loop (%d)" % tw["mag"])
	await _wait(0.444)
	_check(tw["mag"] == 2, "trench gun: 2 rounds after the second loop (%d)" % tw["mag"])
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")
	await _wait(0.05)
	_check(float(p.get("_reloading")) <= 0.0 and tw["mag"] == 1, "trench gun: the shot ends the reload (mag %d, reloading %.2f)" % [tw["mag"], p.get("_reloading")])
	await _wait(2.0)
	_check(tw["mag"] == 1, "trench gun: no rounds from the cut reload (%d)" % tw["mag"])
	# ---- aiming waits for the bolt (state 53)
	p.give_weapon("kar98")
	await _wait(0.8)
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")
	p.aim_wanted = true
	await _wait(0.6)
	_check(not p.aiming, "kar98: no sights during the bolt")
	await _wait(1.1)
	_check(p.aiming, "kar98: sights after the bolt")
	p.aim_wanted = false
	await _wait(0.6)
	# ---- rechamber after the shot
	for n in ["kar98", "springfield", "arisaka", "trenchgun"]:
		p.give_weapon(n)
		await _wait(0.6)
		var g := GunStates.of(p.weapon())
		heard.clear()
		Sfx.instance.set_meta("log", heard)
		Input.action_press("fire")
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release("fire")
		await _wait(float(g["fire"]["ms"]) / 1000.0 + 0.15)
		_check(_arms(vm) == g["rechamber"]["arms"], "%s rechamber arms %s (now %s)" % [n, g["rechamber"]["arms"], _arms(vm)])
		if n == "kar98":
			await _wait(0.2)
			await _shot("kar98_bolt")
		await _wait(1.2)
		var rk: String = g["rechamber"]["events"][0][2]
		_check(heard.has(rk), "%s rechamber sound %s heard %s" % [n, rk, heard])
		Sfx.instance.set_meta("log", null)
	# ---- Garand: the last round
	p.give_weapon("garand")
	await _wait(0.6)
	p.weapon()["mag"] = 1
	heard.clear()
	Sfx.instance.set_meta("log", heard)
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")
	await _wait(0.1)
	_check(heard.has("09664794") and not heard.has("8429e322"), "garand last round ping %s" % [heard])
	_check(_arms(vm) == "dd952d84", "garand last round arms %s" % _arms(vm))
	await _wait(0.4)
	_check(float(p.get("_reloading")) > 0.0, "garand reloads after the last shot")
	await _wait(2.0)
	Sfx.instance.set_meta("log", null)
	# ---- Pack-a-Punch layer
	p.weapon()["upgraded"] = true
	heard.clear()
	Sfx.instance.set_meta("log", heard)
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")
	await _wait(0.1)
	_check(heard.has("19571fe7"), "upgraded gun fire layer %s" % [heard])
	p.weapon()["upgraded"] = false
	Sfx.instance.set_meta("log", null)
	await _wait(0.5)
	# ---- sprint
	p.give_weapon("thompson")
	await _wait(0.8)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _wait(0.5)
	var run: Array = GunStates.data()["thompson"]["run"]
	_check(_arms(vm) == run[1]["arms"], "running arms %s (now %s)" % [run[1]["arms"], _arms(vm)])
	await _shot("run")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_arms(vm) == run[2]["arms"], "run out arms %s (now %s)" % [run[2]["arms"], _arms(vm)])
	await _wait(0.5)
	_check(_arms(vm) == Viewmodel.pairs()["weapons"]["thompson"]["anims"]["idle"][1], "back to idle %s" % _arms(vm))
	# ---- Monkey Bomb
	var mb := preload("res://scripts/monkey_bomb.gd").spawn(game, p.global_position + Vector3(0, 0.5, -2), Vector3.ZERO, p)
	await _wait(3.0)
	_check(mb.landed and mb.claps >= 6, "monkey on the ground: %d cymbals in ~2.7 s" % mb.claps)
	mb.queue_free()
	await _wait(0.1)
	heard.clear()
	Sfx.instance.set_meta("log", heard)
	GunStates.state_sounds(GunStates.data().get("monkey_throw"), func(): return true)
	await _wait(3.0)
	heard = heard.filter(func(k): return k in ["fccecde2", "9104e68f", "4d952d27"] or k.begins_with("845a34b"))
	_check(heard.size() == 6 and heard.has("4d952d27") and heard.filter(func(k): return k.begins_with("845a34b")).size() == 1, "monkey throw sounds %s" % [heard])
	Sfx.instance.set_meta("log", null)
	print("[gunstate] done, %d failures" % fails)
	get_tree().quit()
