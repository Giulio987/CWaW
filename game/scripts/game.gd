# Game director: loads the level, runs rounds from waves.json (extracted from
# the original Lua wave tables), spawns zombies, owns the HUD.
class_name Game
extends Node3D

const DIFFICULTY := 3   # index into the Lua tables (1..5)

var max_alive := 24     # Script.Level.MaxZombiesAmount

var level: Level
var player: Player
var hud: Hud
var wall_buys := []
var round_number := 0
var waves := []
var open_areas := []
var level_name := ""

var _to_spawn := 0
var _spawned := 0
var _alive := 0
var _spawn_timer := 0.0
var _spawn_interval := 4.0
var _initial_left := 0
var _initial_interval := 5.0
var _hp := Vector2(40, 80)
var _between_rounds := true
var _links := {}   # debris entity -> area it opens
var _cfg := {}            # level.json (areas and links from the level's Lua)
var _areas := {}          # lower-case area name -> Lua area table
var _win_by_name := {}    # lower-case window entity -> Barricade
var _area_points := []    # [position, area] to find the area the player is in
var _courtyard_n := 0     # Script.Mode.CourtyardSpawnNumber
var _env: Environment
var suppress_kill_points := false

# Map specifics from the level scripts that level.json does not carry.
# Verrückt (Script.Level.NumberOfStartAreas = 2): solo starts at random in the
# German (Player1Spawn) or American (Player3Spawn) half; TurnOnGenerator joins them.
const SPLIT_START := {"verruckt": [["GermanStart", "Player1Spawn"], ["AmericanStart", "Player3Spawn"]]}
const POWER_OPENS := {"verruckt": ["GermanStart", "AmericanStart"], "derriese": ["outerGCourtyard", "outerLabCourtyard"]}
# Script.Level.Trigger: buying these links also opens areas behind "NA" links
const TRIGGER_OPENS := {
	"derriese": {"link_l_ltop_trigger": ["powerCourtyard", "garageTop"], "link_g_gt_trigger": ["powerCourtyard", "labTop"]},
	"shinonuma": {
		"link_strm_swrm_no1_trigger": ["commRoomRoom", "storageRoom", "warningRoom", "doctorsRoom", "fishingRoom", "ledge"],
		"link_strm_swrm_no2_trigger": ["commRoomRoom", "storageRoom", "warningRoom", "doctorsRoom", "fishingRoom", "ledge"]},
}
const LOCAL_SPAWNING := ["shinonuma"]   # Script.Level.UseLocalSpawning
const COURTYARD_SPAWNS := {"verruckt": 8}  # Script.NumberOfCourtyardSpawns

# Dog rounds (waves.lua; Script.DogSpawns on Shi No Numa and Der Riese)
var dog_rounds := false
var dog_round := false
var dog_wave_counter := 0
var waves_since_dog := 0
var _dogs_total := 0
var _dogs_spawned := 0
var _dog_timer := 0.0
var _dog_health := 0.0

# power-ups (World at War): random drops from kills, at most MAX_DROPS per round
const DROP_CHANCE := 0.03
const MAX_DROPS := 4
const TIMED := 30.0
var points_multiplier := 1
var insta_kill := false
var _drops_this_round := 0
var _timers := {}          # "instakill"/"doublepoints" -> seconds left
var _pu_label: Label


func start(level_name_: String) -> void:
	_setup_input()
	_setup_environment(level_name_)
	level = Level.new()
	add_child(level)
	level.load_level(level_name_)
	waves = JSON.parse_string(FileAccess.get_file_as_string("res://assets/levels/%s/waves.json" % level_name_))
	for b in level.wall_buys:
		var params: Dictionary = level.entities[b["name"]]["params"]
		if params.has("weapon"):
			b.merge(params)
			wall_buys.append(b)
	# areas and links come from the level's Lua script (tools/lua/dump_level.lua)
	level_name = level_name_
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/levels/%s/level.json" % level_name_))
	max_alive = int(cfg.get("max_zombies", 24))
	_cfg = cfg
	for a in cfg["areas"]:
		_areas[String(a["Name"]).to_lower()] = a
		if int(a.get("NumberOfDogSpawns", 0)) > 0:
			dog_rounds = true
	for a in cfg["start_areas"]:
		open_areas.append(String(a).to_lower())
	if SPLIT_START.has(level_name_):
		var pick: Array = SPLIT_START[level_name_].pick_random()
		var forced := OS.get_cmdline_user_args().find("--start")
		if forced >= 0:
			for opt in SPLIT_START[level_name_]:
				if String(opt[0]).to_lower().begins_with(OS.get_cmdline_user_args()[forced + 1].to_lower()):
					pick = opt
		open_areas = [String(pick[0]).to_lower()]
		level.player_spawn = level.entity_transform(pick[1])
	if open_areas.is_empty():
		for a in cfg["areas"]:
			if "start" in String(a["Name"]).to_lower():
				open_areas.append(String(a["Name"]).to_lower())
				break
	for l in cfg["links"]:
		if l.has("TriggerName"):
			_links[String(l["TriggerName"]).to_lower()] = [String(l["Area1"]).to_lower(), String(l["Area2"]).to_lower()]
	for d in level.debris:
		d.opened.connect(_on_debris_opened)
	for w in level.windows:
		_win_by_name[String(w.name).to_lower()] = w
	level.power_changed.connect(_on_power_changed)

	var sfx := Sfx.new()
	add_child(sfx)
	sfx.start_ambience(["zombies", "world", "wind"])
	player = Player.new()
	player.game = self
	add_child(player)
	player.global_transform = level.player_spawn
	player.died.connect(_on_player_died)
	sfx.listener = player
	RadioEggs.create(self)   # shootable radios/phone easter eggs (radio_egg.gd)
	Bridge.create(level)     # Der Riese drawbridge (bridge.gd)
	FlyTrap.create(self)     # Der Riese fly trap easter egg (flytrap.gd)

	hud = Hud.new()
	add_child(hud)
	hud.bind(self)

	# collision exists only after a physics frame; then orient windows and bake the navmesh
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for w in level.windows:
		var room := level.windows.filter(func(o): return o.area == w.area)
		var centre := Vector3.ZERO
		for o in room:
			centre += o.global_position
		w.finalize(level, centre / room.size() if room.size() > 2 else level.player_spawn.origin)
	_collect_area_points()
	hud.message("Caricamento navigazione…")
	level.navigation_ready.connect(_begin, CONNECT_ONE_SHOT)
	level.bake_navigation()


# node caches kept in static vars are not freed with the scene
func _exit_tree() -> void:
	Grenade.release_cache()
	Powerup.release_cache()
	PerkMachine.release_cache()


func _begin() -> void:
	hud.message("")
	get_tree().create_timer(2.0).timeout.connect(_next_round)


func _setup_input() -> void:
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "interact": KEY_E, "reload": KEY_R, "switch_weapon": KEY_Q,
		"melee": KEY_V}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[a]
			InputMap.action_add_event(a, ev)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)


func _setup_environment(_level: String) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.13, 0.16)
	env.fog_density = 0.025
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ------------------------------------------------------------------ rounds

func _next_round() -> void:
	_drops_this_round = 0
	round_number += 1
	dog_round = false
	# dog rounds take a round number but not a wave of the table (RecalculateWaveInfo)
	var w: Dictionary = waves[clampi(round_number - dog_wave_counter, 1, waves.size()) - 1]
	var counts: Array = w["Zombies"][DIFFICULTY - 1]
	_to_spawn = 0
	for c in counts:
		_to_spawn += int(c[0])
	_spawned = 0
	_hp = Vector2(w["ZombieHealth"][0], w["ZombieHealth"][1])
	_spawn_interval = w["SpawnSpeed"] / 1000.0
	_initial_left = int(w["InitialSpawns"])
	_initial_interval = w["InitialSpawnSpeed"] / 1000.0
	_spawn_timer = 1.0
	_between_rounds = false
	hud.round_changed(round_number)


func _process(delta: float) -> void:
	_update_powerups(delta)
	if _between_rounds or player == null or player.dead:
		return
	if dog_round:
		_process_dog_round(delta)
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _spawned < _to_spawn and _alive < max_alive:
		_spawn_zombie()
		if _initial_left > 0:
			_initial_left -= 1
			_spawn_timer = _initial_interval / 4.0
		else:
			_spawn_timer = _spawn_interval
	if _spawned >= _to_spawn and _alive <= 0:
		_between_rounds = true
		Sfx.instance.play("end_wave")
		_wave_end()


# waves.lua "waveEnd": on dog maps a dog round can follow (more than two rounds
# since the last one, then 1 in 3, always after four), FastWaves start sooner.
func _wave_end() -> void:
	if not dog_rounds:
		get_tree().create_timer(8.0).timeout.connect(_next_round)
		return
	waves_since_dog += 1
	var dogs := waves_since_dog > 2 and (randi_range(1, 3) == 1 or waves_since_dog > 4)
	if OS.get_cmdline_user_args().has("--dogs-next"):
		dogs = true
	get_tree().create_timer(5.5).timeout.connect(_start_dog_round if dogs else _next_round)


# One spawn candidate per Lua AvailableSpawns entry of the open areas:
# <Area>ZombieSpawn<n> -> <Area>ZombieWindow<n>, courtyard spawns -> <Area>ZombieCYWindow<n>,
# swamp spawns (Shi No Numa) have no window: those zombies come straight at the player.
func _spawn_candidates(areas: Array) -> Array:
	var out := []
	for an in areas:
		var a: Dictionary = _areas.get(an, {})
		if a.is_empty():
			continue
		var nm := String(a["Name"])
		for i in range(1, int(a.get("NumberOfSpawns", 0)) + 1):
			var sp := "%sZombieSpawn%d" % [nm, i]
			if level.has_entity(sp):
				out.append({"spawn": sp, "window": ("%sZombieWindow%d" % [nm, i]).to_lower(), "area": an})
		for i in range(1, int(a.get("NumberOfCourtyardWindows", 0)) + 1):
			if COURTYARD_SPAWNS.has(level_name):
				out.append({"spawn": "COURTYARD", "window": ("%sZombieCYWindow%d" % [nm, i]).to_lower(), "area": an})
		for i in range(1, int(a.get("NumberOfSwampSpawns", 0)) + 1):
			var sp := "%sZombieSwampSpawn%d" % [nm, i]
			if level.has_entity(sp):
				out.append({"spawn": sp, "window": "", "area": an})
	return out


# waves.lua RecalculateWaveInfo: the wave's Zombies[difficulty] pairs {count, speed}
# expand to a shuffled list of zombie speeds (1..14, see Zombie.SPEED_STATES); the
# n-th zombie spawned in the wave takes the n-th speed.
var _wave_speeds: Array[int] = []
const GROUND_SPAWNS := {"derriese": ["outerLabCourtyardZombieSpawn2", "powerCourtyardZombieSpawn1",
	"powerCourtyardZombieSpawn2", "powerCourtyardZombieSpawn3", "labTopZombieSpawn2",
	"garageZombieSpawn2", "labZombieSpawn3"]}   # Script.Level.DRSpecialGroundSpawns


var last_spawn := ""   # spawn entity of the last zombie (tests)


func _wave_speed() -> int:
	if _spawned == 0 or _wave_speeds.size() != _to_spawn:
		_wave_speeds.clear()
		var w: Dictionary = waves[clampi(round_number - dog_wave_counter, 1, waves.size()) - 1]
		for pair in w["Zombies"][DIFFICULTY - 1]:
			for i in int(pair[0]):
				_wave_speeds.append(int(pair[1]))
		_wave_speeds.shuffle()
	if _wave_speeds.is_empty():
		return 1
	return _wave_speeds[clampi(_spawned, 0, _wave_speeds.size() - 1)]


func _spawn_zombie() -> void:
	var cands := _spawn_candidates(open_areas)
	if cands.is_empty():
		return
	var c: Dictionary = cands.pick_random()
	if level_name in LOCAL_SPAWNING:
		# PickLocalSpawnpoint: the player's area or an open neighbour, one of its 4 closest spawns
		var near := _spawn_candidates(_local_areas())
		if not near.is_empty():
			var area: String = near.map(func(x): return x["area"]).pick_random()
			near = near.filter(func(x): return x["area"] == area)
			near.sort_custom(func(a, b): return _cand_pos(a).distance_to(player.global_position) < _cand_pos(b).distance_to(player.global_position))
			c = near.slice(0, 4).pick_random()
	var origin: Vector3
	if c["spawn"] == "COURTYARD":
		# SupplyCourtyardSpawn: cycles CourtyardZombieSpawn1..N from a random start
		var n: int = COURTYARD_SPAWNS[level_name]
		if _courtyard_n == 0:
			_courtyard_n = randi_range(1, n)
		_courtyard_n = _courtyard_n % n + 1
		origin = level.entity_transform("CourtyardZombieSpawn%d" % _courtyard_n).origin
	else:
		origin = level.entity_transform(c["spawn"]).origin
	_make_zombie(c, origin)


# Tests: a zombie from one named spawn (any area), as the spawner would make it.
func spawn_zombie_at(spawn: String) -> Zombie:
	for c in _spawn_candidates(_areas.keys()):
		if String(c["spawn"]).to_lower() == spawn.to_lower():
			return _make_zombie(c, level.entity_transform(c["spawn"]).origin)
	return null


func _make_zombie(c: Dictionary, origin: Vector3) -> Zombie:
	var win: Barricade = _win_by_name.get(c["window"])
	var direct := win == null
	if win == null:
		# no window (swamp spawn, or a window the level lacks): nearest one as a formality
		var wins := level.windows.duplicate()
		wins.sort_custom(func(a, b): return a.outside.distance_to(origin) < b.outside.distance_to(origin))
		win = wins[0]
	var z := Zombie.new()
	z.setup(origin, win, player, randf_range(_hp.x, _hp.y), false, _wave_speed())
	if direct and c["window"] == "":
		z.state = Zombie.State.CHASE
	# "_ground" / "_water" templates climb out of the ground first (waves.lua)
	z.rise = c["spawn"] == "COURTYARD" or c["window"] == "" \
		or String(c["spawn"]).to_lower() in GROUND_SPAWNS.get(level_name, []).map(func(x): return x.to_lower())
	z.water = "zombieswampspawn" in String(c["spawn"]).to_lower()
	if not z.rise and not direct and level_name in Level.NAV_FLOOR_LEVELS:
		var e := _spawn_entry(origin, win.outside)
		if e != origin:
			z.entry = e
	z.killed.connect(_on_zombie_killed)
	add_child(z)
	last_spawn = c["spawn"]
	_spawned += 1
	_alive += 1
	return z


# Spawns the original hides behind the jungle backdrop on Shi No Numa (its navmesh
# runs on past the edge of the visible ground): when the navmesh from the spawn does
# not reach the window, the zombie walks straight in to the first point that does.
func _spawn_entry(origin: Vector3, target: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if OS.get_cmdline_user_args().has("--no-nav-floor") or _nav_reaches(map, origin, target):
		return origin
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	for i in range(1, int(minf(flat.length(), 15.0) / 0.5) + 1):
		var p := origin + flat.normalized() * 0.5 * i
		var c := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(c.x - p.x, c.z - p.z).length() < 0.4 and absf(c.y - origin.y) < 2.5 and _nav_reaches(map, c, target):
			return c
	return origin


func _nav_reaches(map: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return path.size() > 0 and path[-1].distance_to(to) < 1.5


func _cand_pos(c: Dictionary) -> Vector3:
	var w: Barricade = _win_by_name.get(c["window"])
	if w:
		return w.inside
	return level.entity_transform(c["spawn"]).origin if c["spawn"] != "COURTYARD" else player.global_position


# Points that tell which area the player stands in: windows' inside points and dog spawns.
func _collect_area_points() -> void:
	_area_points.clear()
	for w in level.windows:
		if _areas.has(w.area):
			_area_points.append([w.inside, w.area])
	for an in _areas:
		var a: Dictionary = _areas[an]
		for i in range(1, int(a.get("NumberOfDogSpawns", 0)) + 1):
			var n := "%sDogSpawn%d" % [a["Name"], i]
			if level.has_entity(n):
				_area_points.append([level.entity_transform(n).origin, an])


func player_area() -> String:
	var best := ""
	var bd := INF
	var p := player.global_position
	for ap in _area_points:
		if not ap[1] in open_areas:
			continue
		var v: Vector3 = ap[0]
		var d := Vector2(v.x - p.x, v.z - p.z).length() + absf(v.y - p.y) * 3.0
		if d < bd:
			bd = d
			best = ap[1]
	return best


# the player's area plus the open areas linked to it
func _local_areas() -> Array:
	var here := player_area()
	if here == "":
		return open_areas
	var out := [here]
	for l in _cfg["links"]:
		var a1 := String(l["Area1"]).to_lower()
		var a2 := String(l["Area2"]).to_lower()
		if a1 == here and a2 in open_areas and not a2 in out:
			out.append(a2)
		elif a2 == here and a1 in open_areas and not a1 in out:
			out.append(a1)
	return out


func open_area(name: String) -> void:
	var a := name.to_lower()
	if not a in open_areas:
		open_areas.append(a)
	if a == "packapunch":
		await get_tree().physics_frame
		await get_tree().physics_frame
		level.bake_navigation()


func _on_power_changed(on: bool) -> void:
	if on:
		for a in POWER_OPENS.get(level_name, []):
			open_area(a)


# Trap kills give no points (World at War).
func kill_without_points(z: Zombie) -> void:
	suppress_kill_points = true
	z.nuke_kill()
	suppress_kill_points = false


func player_moved() -> void:
	pass


# ------------------------------------------------------------------ dog rounds

# StartDogWave: dog_round sting, fog rolls in, the announcer, dogs from 7 s on.
func _start_dog_round() -> void:
	_drops_this_round = 0
	round_number += 1
	dog_wave_counter += 1
	waves_since_dog = 0
	dog_round = true
	_between_rounds = false
	_dog_health = dog_wave_counter * 300.0       # RecalculateDogWaveInfo
	_dogs_total = _dog_number(dog_wave_counter, DIFFICULTY)
	_dogs_spawned = 0
	_dog_timer = 7.0
	hud.round_changed(round_number)
	Sfx.instance.play("dog_fog")
	Sfx.instance.ambience = []
	_fog(true)
	get_tree().create_timer(7.5, false).timeout.connect(func(): Sfx.instance.play("dog_start_vox"))


# DogNumberCalculation(dogWaveCounter, difficulty)
static func _dog_number(counter: int, difficulty: int) -> int:
	if counter < 3:
		return [6, 6, 6, 12, 16, 18][clampi(difficulty, 0, 5)]
	return [8, 8, 8, 16, 18, 20][clampi(difficulty, 0, 5)]


func _process_dog_round(delta: float) -> void:
	# "SpawnDog" every 2 s while fewer than two are alive (DogAmount = 2)
	_dog_timer -= delta
	if _dog_timer <= 0.0 and _dogs_spawned < _dogs_total:
		_dog_timer = 2.0
		if _alive < 2:
			spawn_dog(false)


# Script.SpawnDog: the player's area or an open neighbour, one of its two dog
# spawns closest to the player; a lightning strike, then the dog.
func spawn_dog(untracked: bool) -> void:
	var spots := []
	var areas := _local_areas()
	areas.shuffle()
	for an in areas:
		var a: Dictionary = _areas.get(an, {})
		for i in range(1, int(a.get("NumberOfDogSpawns", 0)) + 1):
			var n := "%sDogSpawn%d" % [a["Name"], i]
			if level.has_entity(n):
				spots.append(level.entity_transform(n).origin)
		if not spots.is_empty():
			break
	if spots.is_empty():
		for an in open_areas:
			var a: Dictionary = _areas.get(an, {})
			for i in range(1, int(a.get("NumberOfDogSpawns", 0)) + 1):
				var n := "%sDogSpawn%d" % [a["Name"], i]
				if level.has_entity(n):
					spots.append(level.entity_transform(n).origin)
	if spots.is_empty():
		return
	spots.sort_custom(func(a, b): return a.distance_to(player.global_position) < b.distance_to(player.global_position))
	var at: Vector3 = spots.slice(0, 2).pick_random()
	if not untracked:
		_dogs_spawned += 1
		_alive += 1
	_lightning(at)
	Sfx.instance.play_at("dog_spawn", at + Vector3.UP)
	await get_tree().create_timer(0.6, false).timeout
	var d := Dog.new()
	d.untracked = untracked
	d.flame = Dog.roll_flame()   # "flame_dogSpawn" or "normal_dogSpawn"
	d.setup_dog(at + Vector3.UP * 0.1, player, _dog_health if _dog_health > 0.0 else 300.0, level.windows[0])
	d.killed.connect(_on_dog_killed)
	add_child(d)


func _on_dog_killed(d: Zombie, headshot: bool, knife: bool) -> void:
	if not suppress_kill_points:
		player.add_points((120 if knife else (90 if headshot else 50)) * points_multiplier)
	if (d as Dog).untracked:
		return
	_alive -= 1
	# EnemyKilled: the last dog of the round drops a Max Ammo, the round ends 2 s later
	if dog_round and _dogs_spawned >= _dogs_total and _alive <= 0:
		spawn_powerup("maxammo", d.global_position)
		dog_round = false
		_between_rounds = true
		get_tree().create_timer(2.0, false).timeout.connect(_dog_round_end)


# dogWaveEnd: music, fog lifts, next zombie round 6 s later
func _dog_round_end() -> void:
	Sfx.instance.play("dog_end_music")
	Sfx.instance.start_ambience(["zombies", "world", "wind"])
	_fog(false)
	get_tree().create_timer(6.0).timeout.connect(_next_round)


func _fog(on: bool) -> void:
	if _env == null:
		return
	var tw := create_tween().set_parallel()
	tw.tween_property(_env, "fog_density", 0.07 if on else 0.025, 4.0)
	tw.tween_property(_env, "fog_light_color", Color(0.25, 0.22, 0.2) if on else Color(0.12, 0.13, 0.16), 4.0)


# a white bolt from the sky and a flash where a dog appears
func _lightning(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(0.85, 0.9, 1.0)
	l.light_energy = 8.0
	l.omni_range = 9.0
	add_child(l)
	l.global_position = at + Vector3.UP * 1.5
	var bolt := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var prev := at + Vector3.UP * 14.0
	for k in range(1, 12):
		var p := at.lerp(at + Vector3.UP * 14.0, 1.0 - k / 11.0)
		if k < 11:
			p += Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		im.surface_add_vertex(prev)
		im.surface_add_vertex(p)
		prev = p
	im.surface_end()
	bolt.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	bolt.material_override = mat
	add_child(bolt)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.7)
	tw.tween_callback(l.queue_free)
	get_tree().create_timer(0.25, false).timeout.connect(bolt.queue_free)


func _on_zombie_killed(z: Zombie, headshot: bool, knife: bool) -> void:
	_alive -= 1
	# World at War: 130 knife kill, 100 headshot, 60 other (plus 10 per hit)
	if not suppress_kill_points:
		player.add_points((120 if knife else (90 if headshot else 50)) * points_multiplier)
	if _drops_this_round < MAX_DROPS and randf() < DROP_CHANCE and not _nuking:
		spawn_powerup(Powerup.KINDS.keys().pick_random(), z.global_position)


func spawn_powerup(kind: String, at: Vector3) -> void:
	_drops_this_round += 1
	var pu := Powerup.new()
	pu.setup(self, kind, at)
	add_child(pu)


var _nuking := false


func apply_powerup(kind: String) -> void:
	Sfx.instance.play("14c4f851")  # pickup sting, then the announcer (as in the original sequences)
	get_tree().create_timer(0.3, false).timeout.connect(Sfx.instance.play.bind(kind))
	_show_powerup(Powerup.KINDS[kind]["label"])
	match kind:
		"maxammo":
			for w in player.weapons:
				w["reserve"] = Weapons.stats_of(w)["reserve"]
			player.changed.emit()
		"instakill":
			insta_kill = true
			_timers["instakill"] = TIMED
		"doublepoints":
			points_multiplier = 2
			_timers["doublepoints"] = TIMED
		"nuke":
			_nuking = true
			player.add_points(400 * points_multiplier)
			var zs := get_children().filter(func(n): return n is Zombie and n.state != Zombie.State.DEAD)
			for i in zs.size():
				var z: Zombie = zs[i]
				get_tree().create_timer(0.1 + 0.08 * i, false).timeout.connect(func():
					if is_instance_valid(z) and z.state != Zombie.State.DEAD:
						z.nuke_kill())
			get_tree().create_timer(0.2 + 0.08 * zs.size(), false).timeout.connect(func(): _nuking = false)
		"carpenter":
			for w in level.windows:
				while w.repair_board():
					pass
			player.add_points(200 * points_multiplier)


func _show_powerup(text: String) -> void:
	if _pu_label == null:
		_pu_label = Label.new()
		_pu_label.add_theme_font_size_override("font_size", 26)
		_pu_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.4))
		_pu_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_pu_label.add_theme_constant_override("outline_size", 4)
		_pu_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_pu_label.offset_top = 40
		_pu_label.offset_left = -200
		_pu_label.offset_right = 200
		_pu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var layer := CanvasLayer.new()
		layer.layer = 2
		add_child(layer)
		layer.add_child(_pu_label)
	_pu_label.text = text
	_pu_label.set_meta("flash", 3.0)


func _update_powerups(delta: float) -> void:
	for k in _timers.keys():
		_timers[k] -= delta
		if _timers[k] <= 0.0:
			_timers.erase(k)
			if k == "instakill":
				insta_kill = false
			elif k == "doublepoints":
				points_multiplier = 1
	if _pu_label:
		var flash: float = _pu_label.get_meta("flash", 0.0) - delta
		_pu_label.set_meta("flash", flash)
		var parts := []
		if flash > 0.0:
			parts.append(_pu_label.text.split("\n")[0])
		for k in _timers:
			parts.append("%s %d" % [Powerup.KINDS[k]["label"], ceili(_timers[k])])
		_pu_label.text = "\n".join(parts) if not parts.is_empty() else ""


func _on_debris_opened(d: Debris) -> void:
	# a link joins two areas; once bought both sides are open
	for area in _links.get(d.entity.to_lower(), []):
		if not area in open_areas:
			open_areas.append(area)
	for area in TRIGGER_OPENS.get(level_name, {}).get(d.entity.to_lower(), []):
		open_area(area)
	level.debris.erase(d)
	await get_tree().physics_frame
	await get_tree().physics_frame
	level.bake_navigation()


func _on_player_died() -> void:
	Sfx.instance.ambience = []
	Sfx.instance.play("gameover_intro")
	hud.game_over(round_number)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ effects

func muzzle_flash(cam: Camera3D) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.4)
	l.light_energy = 3.0
	l.omni_range = 6.0
	cam.add_child(l)
	l.position = Vector3(0.2, -0.15, -0.6)
	get_tree().create_timer(0.05).timeout.connect(l.queue_free)


func spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = mat
	m.mesh = q
	add_child(m)
	m.global_position = pos + normal * 0.01
	if abs(normal.dot(Vector3.UP)) < 0.99:
		m.look_at(pos + normal, Vector3.UP)
	get_tree().create_timer(10.0).timeout.connect(m.queue_free)
