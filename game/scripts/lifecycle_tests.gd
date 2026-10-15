# Zombie life cycle and round bookkeeping tests.
#   tools/run_godot.sh 120 -- nacht --autotest 110 --zombie-test lifecycle
#     kills real (spawner) zombies in every state (CHASE, ATTACK, TEARING, CLIMBING,
#     RISING, unstick tween, TO_WINDOW) in every way (gun, headshot, knife, crawler
#     then kill, grenade, Ray Gun, flamethrower, trap/zipline, insta-kill, nuke) and
#     dogs; checks that every body stays DEAD and still, is counted once and freed,
#     and that the round cannot end while one is alive. Prints "[life] ... OK/FAIL".
#   tools/run_godot.sh 320 -- shinonuma --autotest 300 --life-watch
#     alongside the normal bot: forces kills of random zombies in random states with
#     random methods, and checks every frame that the living zombies match the round
#     counters, that no round ends with a zombie alive and that no corpse gets up.

extends Node

const METHODS := ["gun", "headshot", "knife", "crawler", "grenade", "raygun", "flame", "trap", "instakill"]

static var fails := 0
static var checks := 0


static func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print("[life] %s %s" % [what, "OK" if ok else "FAIL"])


static func _wait(at: Node, t: float) -> void:
	await at.get_tree().create_timer(t).timeout


static func _aim(p: Player, target: Vector3) -> void:
	var cam := p.get_viewport().get_camera_3d()
	var to := target - cam.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	cam.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


# A point d metres in front of the player (less if a wall is closer), on the floor.
static func _ahead(game: Game, d: float) -> Vector3:
	var p := game.player
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var space := game.get_world_3d().direct_space_state
	var from := p.global_position + Vector3.UP
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + fwd * (d + 0.6), 1))
	if not hit.is_empty():
		d = maxf(0.9, from.distance_to(hit["position"]) - 0.6)
	return p.global_position + fwd * d


# A tracked zombie from the spawner (the round counts it), its window known.
static func _spawn(game: Game) -> Zombie:
	var cands := game._spawn_candidates(game.open_areas).filter(func(c): return c["window"] != "" and c["spawn"] != "COURTYARD" and game._win_by_name.has(c["window"]))
	var c: Dictionary = cands[0] if not cands.is_empty() else game._spawn_candidates(game._areas.keys())[0]
	return game._make_zombie(c, game.level.entity_transform(c["spawn"]).origin if c["spawn"] != "COURTYARD" else game.player.global_position + Vector3(4, 0, 0))


# Put a zombie in the given state (the way the game gets it there).
static func _prep(at: Node, game: Game, z: Zombie, st: String) -> bool:
	var p := game.player
	match st:
		"CHASE":
			z.global_position = _ahead(game, 2.6)
			z.state = Zombie.State.CHASE
			await _wait(at, 0.2)
		"ATTACK":
			z.global_position = _ahead(game, 1.0)
			z.state = Zombie.State.CHASE
			var t := 0.0
			while z.state != Zombie.State.ATTACK and t < 2.0:
				await at.get_tree().physics_frame
				t += 1.0 / 60.0
		"TEARING":
			var w := z.window
			while w.repair_board():
				pass
			w.occupied_by = null
			z.global_position = w.outside
			z._start_tearing()
			await _wait(at, 0.6)
		"CLIMBING":
			var w := z.window
			while w.tear_board():
				pass
			w.occupied_by = z
			z.global_position = w.outside
			z._start_climb()
			await _wait(at, 1.2)   # mid-climb (4.07 s animation)
		"RISING":
			z.global_position = _ahead(game, 3.0)
			z.state = Zombie.State.CHASE
			z._start_rise()
			await _wait(at, 2.0)
		"UNSTICK":
			# the snag watchdog carrying it to the next path point, collision off
			z.global_position = _ahead(game, 3.0)
			z.state = Zombie.State.CHASE
			z._unsticking = true
			z.collision_mask = 0
			z._unstick_tw = z.create_tween()
			z._unstick_tw.tween_property(z, "global_position", z.global_position + p.global_basis.x * 2.0, 2.0)
			z._unstick_tw.finished.connect(z._end_unstick)
			await _wait(at, 0.4)
		"TO_WINDOW":
			await _wait(at, 0.4)
	var want: int = Zombie.State.get(st, Zombie.State.CHASE) if st != "UNSTICK" else Zombie.State.CHASE
	return z.state == want


# Kill with a weapon / effect; returns when it is dead (or gives up).
static func _kill(at: Node, game: Game, z: Zombie, how: String) -> void:
	var p := game.player
	var chest := z.global_position + Vector3.UP * (0.4 if z.crawler else 1.1)
	match how:
		"gun", "headshot":
			_aim(p, z.global_position + Vector3.UP * (1.6 if how == "headshot" else 1.1))
			var w := p.weapon()
			for i in 3:
				if z.state == Zombie.State.DEAD:
					break
				w["mag"] = 5
				p._cooldown = 0.0
				p._fire(w, Weapons.stats_of(w).merged({"damage": 1e5, "pellets": 1, "range": 60.0}, true))
				await at.get_tree().physics_frame
			if z.state != Zombie.State.DEAD:   # the shot cannot reach (window, ground): same call
				z.take_damage(1e5, how == "headshot", p, false, chest)
		"knife":
			z.health = 1.0
			if z.global_position.distance_to(p.global_position) < 1.7:
				_aim(p, chest)
				p._melee_cooldown = 0.0
				p.melee()
				await _wait(at, Player.KNIFE_HIT_TIME + 0.05)   # knifeDamage at 199 ms
			if z.state != Zombie.State.DEAD:
				z.take_damage(150.0, false, p, true)
		"crawler":
			z.become_crawler()
			await _wait(at, 1.0)
			z.take_damage(1e5, false, p, false, z.global_position + Vector3.UP * 0.3)
		"grenade":
			Explosion.blast(game, z.global_position + Vector3.UP * 0.2, p, Explosion.FRAG)
		"raygun":
			Explosion.blast(game, chest, p, Explosion.raygun_cfg(1e6))
		"flame":
			Burning.ignite(z, p, 1e5, 3.0)
			var t := 0.0
			while is_instance_valid(z) and z.state != Zombie.State.DEAD and t < 2.0:
				await at.get_tree().physics_frame
				t += 1.0 / 60.0
		"trap":
			game.kill_without_points(z)
		"instakill":
			game.insta_kill = true
			z.take_damage(1.0, false, p)
			game.insta_kill = false
		"nuke":
			game.apply_powerup("nuke")
			await _wait(at, 0.3)
	if is_instance_valid(z) and z.state != Zombie.State.DEAD:
		# blasts do not reach behind walls: the case is about death, finish it
		z.take_damage(1e7, false, p)


# ------------------------------------------------------------------ corpse watch

class Corpse:
	var z: Zombie
	var label := ""
	var t_dead := 0.0
	var pos := Vector3.INF   # where it lies once settled
	var emits := 0
	var bad := false


static var _corpses: Array[Corpse] = []
static var _clock := 0.0


static func _watch(z: Zombie, label: String) -> Corpse:
	var c := Corpse.new()
	c.z = z
	c.label = label
	_corpses.append(c)
	z.killed.connect(func(_z, _h, _k):
		c.emits += 1
		c.t_dead = _clock)
	return c


# every frame: the dead stay dead, unshootable and where they fell; one kill each
static func _observe(at: Node, game: Game, secs: float) -> void:
	var t := 0.0
	while t < secs:
		await at.get_tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		_clock += dt
		for c in _corpses:
			if c.bad or c.emits == 0 or not is_instance_valid(c.z):
				continue
			var z := c.z
			var why := ""
			if z.state != Zombie.State.DEAD:
				why = "state %s after death" % Zombie.State.keys()[z.state]
			elif z.revive_blocked > 0:
				why = "%d attempts to leave DEAD" % z.revive_blocked
			elif z.collision_layer != 0:
				why = "corpse shootable again"
			elif c.emits > 1:
				why = "killed %d times" % c.emits
			elif game._live.has(z):
				why = "still counted alive"
			elif _clock - c.t_dead > 0.5:
				var flat := Vector3(z.global_position.x, 0, z.global_position.z)
				if c.pos == Vector3.INF:
					c.pos = flat
				elif flat.distance_to(c.pos) > 0.05:
					why = "corpse moved %.2f m" % flat.distance_to(c.pos)
			if why != "":
				c.bad = true
				_check(false, "%s: %s" % [c.label, why])


# ------------------------------------------------------------------ the test

static func run(at: Node) -> void:
	var game: Game = at.game
	var p := game.player
	p.health = 1e9
	_corpses.clear()
	fails = 0
	checks = 0
	game.round_number = 3
	game._between_rounds = false
	game._to_spawn = 1000
	game._spawned = 0
	var states := ["CHASE", "ATTACK", "TEARING", "CLIMBING", "RISING", "UNSTICK", "TO_WINDOW"]
	var cases := []
	for m in METHODS:
		cases.append(["CHASE", m])
	for st in states:
		for m in ["gun", "headshot", "grenade", "trap", "instakill", "flame"] if st in ["CLIMBING", "RISING"] else ["gun", "trap"]:
			if st != "CHASE":
				cases.append([st, m])
	cases.append(["ATTACK", "knife"])
	cases.append(["ATTACK", "crawler"])
	var killed_total := 0
	for cs in cases:
		var z := _spawn(game)
		var label := "%s/%s" % cs
		var c := _watch(z, label)
		var in_state: bool = await _prep(at, game, z, cs[0])
		if not in_state:
			print("[life] %s: zombie was %s, not %s (killed anyway)" % [label, Zombie.State.keys()[z.state], cs[0]])
		var before := game.alive_count()
		var pts := p.points
		await _kill(at, game, z, cs[1])
		killed_total += 1
		_check(z.state == Zombie.State.DEAD and c.emits == 1 and game.alive_count() == before - 1,
			"%s dead, counted once (alive %d -> %d)" % [label, before, game.alive_count()])
		# hit again in every way: nothing more is counted or paid
		pts = p.points
		z.take_damage(1e6, true, p)
		z.nuke_kill()
		game.kill_without_points(z)
		z._die(false)
		z.become_crawler()
		_check(c.emits == 1 and game.alive_count() == before - 1 and p.points == pts, "%s: killing the corpse again is ignored" % label)
		await _observe(at, game, 0.6)
	# dogs (any map: as game.spawn_dog makes a tracked one)
	for how in ["gun", "trap", "nuke"]:
		var d := Dog.new()
		d.setup_dog(_ahead(game, 3.0) + Vector3.UP * 0.1, p, 1000.0, game.level.windows[0])
		d.killed.connect(game._on_dog_killed)
		game.add_child(d)
		game._track(d)
		var c := _watch(d, "dog/" + how)
		await _wait(at, 0.3)
		var before := game.alive_count()
		await _kill(at, game, d, how)
		_check(d.state == Zombie.State.DEAD and c.emits == 1 and game.alive_count() == before - 1, "dog/%s dead, counted once" % how)
		await _observe(at, game, 0.4)
	# nuke with several alive in different states
	var group: Array[Zombie] = []
	for st in ["CHASE", "CLIMBING", "TEARING", "RISING"]:
		var z := _spawn(game)
		_watch(z, "nuke/" + st)
		group.append(z)
		await _prep(at, game, z, st)
	var n_before := game.alive_count()
	game.apply_powerup("nuke")
	await _observe(at, game, 5.5)   # the wave lasts 5 s (radial_effect.gd)
	_check(group.all(func(z): return z.state == Zombie.State.DEAD) and game.alive_count() == n_before - group.size(),
		"nuke kills %d in CHASE/CLIMBING/TEARING/RISING (alive %d -> %d)" % [group.size(), n_before, game.alive_count()])
	# freed without dying: no longer counted, the wave spawns a replacement
	var gone := _spawn(game)
	var sp := game._spawned
	var al := game.alive_count()
	gone.queue_free()
	await at.get_tree().physics_frame
	_check(game.alive_count() == al - 1 and game._spawned == sp - 1, "zombie freed without dying: uncounted, replaced (spawned %d -> %d)" % [sp, game._spawned])
	# the corpses have all been watched past the end of a climb (4.07 s) and are freed
	await _observe(at, game, 6.5)
	var left := _corpses.filter(func(c): return is_instance_valid(c.z))
	_check(left.is_empty(), "all %d corpses freed (left: %s)" % [_corpses.size(), left.map(func(c): return c.label)])
	_check(game._live.is_empty() and game.alive_count() == 0, "round bookkeeping empty (live %d, alive %d)" % [game._live.size(), game.alive_count()])
	# the round ends only when the last one is really dead
	game._to_spawn = game._spawned + 2
	var a := _spawn(game)
	var b := _spawn(game)
	_watch(a, "round/chase")
	_watch(b, "round/climb")
	await _prep(at, game, a, "CHASE")
	await _prep(at, game, b, "CLIMBING")
	game.set_process(true)
	await _wait(at, 0.3)
	_check(not game._between_rounds, "round goes on with 2 alive")
	b.take_damage(1e6, false, p)   # dies in the window
	await _observe(at, game, 4.0)   # past the end of the climb
	_check(not game._between_rounds and a.state != Zombie.State.DEAD, "round goes on with 1 alive after a climbing kill")
	a.take_damage(1e6, true, p)
	await _wait(at, 0.2)
	_check(game._between_rounds and game.alive_count() == 0, "round over once both are dead")
	game.set_process(false)
	await _observe(at, game, 0.5)
	print("[life] lifecycle %d checks, %d failed: %s" % [checks, fails, "OK" if fails == 0 else "FAIL"])


# ------------------------------------------------------------------ stress watch

var game: Game
var _t := 0.0
var _force := 0.0
var _nuke := 45.0
var _round := -1
var _round_kills := 0
var _dog_kills := 0
var _kills := 0
var _forced := 0
var _fail := 0
var _rounds_ended := 0
var _was_between := true
var _last_log := 0.0
var _dead := {}          # Zombie -> [t_dead, settled pos]
var _emits := {}         # instance id -> kill signals
var _by_state := {}      # state name -> forced kills in it
var _pending_crawl := []


func _ready() -> void:
	game.child_entered_tree.connect(_on_child)
	for n in game.get_children():
		_on_child(n)


func _on_child(n: Node) -> void:
	if n is Zombie and not n.killed.is_connected(_on_killed):
		n.killed.connect(_on_killed)


func _on_killed(z: Zombie, _h: bool, _k: bool) -> void:
	var id := z.get_instance_id()
	_emits[id] = int(_emits.get(id, 0)) + 1
	if _emits[id] > 1:
		_fail_log("zombie killed %d times" % _emits[id])
	_dead[z] = [_t, Vector3.INF]
	_kills += 1
	if z is Dog:
		if not (z as Dog).untracked:
			_dog_kills += 1
	else:
		_round_kills += 1


func _fail_log(what: String) -> void:
	_fail += 1
	if _fail <= 40:
		print("[life] FAIL t=%.1f round=%d %s" % [_t, game.round_number, what])


func _living() -> Array:
	return game.get_children().filter(func(n): return n is Zombie and n.state != Zombie.State.DEAD \
		and not (n is Dog and (n as Dog).untracked))


func _physics_process(delta: float) -> void:
	if game == null or game.player == null:
		return
	_t += delta
	if game.round_number != _round:
		_round = game.round_number
		_round_kills = 0
		_dog_kills = 0
	var living := _living()
	var counted := game.alive_count() - game._dogs_pending
	if living.size() != counted:
		_fail_log("living %d != counted alive %d" % [living.size(), counted])
	if game.dog_round:
		if game._dogs_spawned - _dog_kills != living.size() + game._dogs_pending:
			_fail_log("dogs spawned %d - killed %d != alive %d" % [game._dogs_spawned, _dog_kills, living.size() + game._dogs_pending])
	elif not game._between_rounds and game._spawned - _round_kills != living.filter(func(n): return not n is Dog).size():
		_fail_log("spawned %d - killed %d != alive %d" % [game._spawned, _round_kills, living.size()])
	if game._between_rounds and not _was_between:
		_rounds_ended += 1
		if not living.is_empty():
			_fail_log("round %d ended with %d alive: %s" % [game.round_number, living.size(), living.map(func(z): return Zombie.State.keys()[z.state])])
	_was_between = game._between_rounds
	for z in _dead.keys():
		if not is_instance_valid(z):
			_dead.erase(z)
			continue
		var rec: Array = _dead[z]
		var why := ""
		if z.state != Zombie.State.DEAD:
			why = "corpse got up: %s" % Zombie.State.keys()[z.state]
		elif z.revive_blocked > 0:
			why = "%d attempts to leave DEAD" % z.revive_blocked
		elif z.collision_layer != 0:
			why = "corpse shootable"
		elif _t - rec[0] > 7.5:
			why = "corpse not freed after %.1f s" % (_t - rec[0])
		elif _t - rec[0] > 0.6 and not z is Dog:
			var flat := Vector3(z.global_position.x, 0, z.global_position.z)
			if rec[1] == Vector3.INF:
				rec[1] = flat
			elif flat.distance_to(rec[1]) > 0.05:
				why = "corpse moved %.2f m" % flat.distance_to(rec[1])
		if why != "":
			_fail_log(why)
			_dead.erase(z)
	# forced kills: random zombie (window/rise states first), random method
	_force -= delta
	_nuke -= delta
	if not game._between_rounds and not living.is_empty():
		if _nuke <= 0.0:
			_nuke = 70.0
			game.apply_powerup("nuke")
			_forced += 1
		elif _force <= 0.0:
			_force = 1.5
			# zombies at the windows, rising or snagged first; walkers only once they are slow
			var odd := living.filter(func(z): return z.state in [Zombie.State.CLIMBING, Zombie.State.TEARING, Zombie.State.RISING] or z._unsticking)
			var rest := living.filter(func(z): return z.state != Zombie.State.TO_WINDOW or z.life > 30.0)
			var pool := odd if not odd.is_empty() and randf() < 0.85 else rest
			if not pool.is_empty():
				var z: Zombie = pool.pick_random()
				var st: String = "UNSTICK" if z._unsticking else Zombie.State.keys()[z.state]
				_by_state[st] = int(_by_state.get(st, 0)) + 1
				_forced += 1
				_kill_now(z, METHODS.pick_random())
	if int(_t) != int(_last_log) and int(_t) % 15 == 0:
		print("[life] t=%.0f round=%d%s alive=%d spawned=%d/%d kills=%d forced=%d %s rounds_ended=%d fails=%d" % [_t, game.round_number,
			" (dogs)" if game.dog_round else "", living.size(), game._spawned, game._to_spawn, _kills, _forced, _by_state, _rounds_ended, _fail])
	_last_log = _t


func _kill_now(z: Zombie, how: String) -> void:
	var p := game.player
	var chest := z.global_position + Vector3.UP * 1.1
	match how:
		"gun":
			z.take_damage(1e6, false, p, false, chest)
		"headshot":
			z.take_damage(1e6, true, p, false, chest + Vector3.UP * 0.5)
		"knife":
			z.take_damage(1e6, false, p, true)
		"crawler":
			if z.state in [Zombie.State.CHASE, Zombie.State.ATTACK] and not z is Dog:
				z.become_crawler()   # as take_damage / Explosion do it
			get_tree().create_timer(1.5, false).timeout.connect(func():
				if is_instance_valid(z):
					z.take_damage(1e6, false, p, false, z.global_position + Vector3.UP * 0.3))
		"grenade":
			Explosion.blast(game, z.global_position + Vector3.UP * 0.2, p, Explosion.FRAG)
		"raygun":
			Explosion.blast(game, chest, p, Explosion.raygun_cfg(1e6))
		"flame":
			Burning.ignite(z, p, 1e6, 2.0)
		"trap":
			game.kill_without_points(z)
		"instakill":
			var was := game.insta_kill
			game.insta_kill = true
			z.take_damage(1.0, false, p)
			game.insta_kill = was
	if how in ["grenade", "raygun"] and is_instance_valid(z) and z.state != Zombie.State.DEAD:
		z.take_damage(1e7, false, p)   # behind a wall from the blast


func _exit_tree() -> void:
	print("[life] watch %.0f s: rounds ended %d, kills %d (forced %d, by state %s), fails %d: %s" % [_t, _rounds_ended, _kills, _forced, _by_state, _fail, "OK" if _fail == 0 else "FAIL"])
