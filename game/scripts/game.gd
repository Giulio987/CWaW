# Game director: loads the level, runs rounds from waves.json (extracted from
# the original Lua wave tables), spawns zombies, owns the HUD.
class_name Game
extends Node3D

# Game.GetDifficulty() (waves.lua 384/608/696): the column of the Lua Zombies tables
# (and of DogNumberCalculation, which ignores it). The engine's getter (kiwi 0x37f88)
# returns the profile difficulty: toggleDifficulty (kiwi 0x17bd1c) flips it between
# 1 = Recruit and 2 = Regular (the default); co-op games store players + 1 (kiwi
# 0x18aac8), so columns 3..5 are 2..4 players. Set at the start of a game (Settings
# "recruit", or --recruit); Recruit counts no achievements or stats (as the original,
# which skips them when the difficulty is 1, e.g. kiwi 0x10bcc4).
const RECRUIT := 1
const REGULAR := 2
static var difficulty := REGULAR


static func recruit() -> bool:
	return difficulty == RECRUIT


# Achievements and stats are off in the debug start and on Recruit.
static func no_achievements() -> bool:
	return debug_start or recruit()


var max_alive := 24     # Script.Level.MaxZombiesAmount

# Debug start (menu switch or --debug-start): round 5, Ray Gun, 10000 points; no achievements
const DEBUG_ROUND := 5
const DEBUG_WEAPON := "raygun"
const DEBUG_POINTS := 10000
static var debug_start := false

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
var spawn_count := 0   # Game.GetSpawnCount: zombies spawned in the game (template = count % 8)
var _alive := 0          # living enemies of the round: _live + dogs still on their way in
var _live := {}          # tracked zombie/dog -> true, until it dies or leaves the tree
var _dogs_pending := 0   # dogs whose lightning has struck but which are not in the tree yet
var _spawn_timer := 0.0
var _spawn_interval := 4.0
var _initial_times := []   # round times of the pending "WaveSpawnZombieInitial" timeouts
var _round_time := 0.0
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
# Script.FastWaves (shinonuma.lua:14, derriese.lua:12): "waveEnd" 0.5 s after the
# last kill instead of 2 s (waves.lua EnemyKilled)
const FAST_WAVES := ["shinonuma", "derriese"]

# Level Begin/Resume: Game.StopAmbience + AddAmbienceChannel (nacht.lua 59-62,
# verruckt.lua 195-198, shinonuma.lua 315-325, derriese.lua 282-285). On dog waves
# ("dogWaveStart", shinonuma/derriese Timeout) only "zombies" is dropped.
const AMBIENCE := {"nacht": ["zombies", "world", "wind"], "verruckt": ["zombies", "verrucktAmbience", "wind"],
	"shinonuma": ["zombies", "jungleChatter", "jungleBackground"], "derriese": ["zombies", "derrieseAmbience", "wind"]}
# Game.SetUsingPlayerVox / SetUsingImpactEffects of the level Begin/Resume
# (nacht.lua 66-67, verruckt.lua 203-204, shinonuma.lua 351-354, derriese.lua 295-296)
const USING_VOX := ["shinonuma", "derriese"]
const IMPACT_EFFECTS := ["shinonuma", "derriese"]
const IMPACT_MAX_RANGE := 25.0   # console ImpactEffectsMaxRange 10000 units (kiwi 0x20eadc)
# CFogConfig resources (ingame/misc/misc.group.bin) set by SetDefaultFogConfig("<map>", 1000)
# and, on dog waves, SetFogConfig(Script.Level.DogConfigName or "dogs", 4000) (waves.lua 576-583):
# colour, then (near, far) per detail level; index 0 = high detail (iPad, kiwi 0x1a6f60).
# CFogManager (kiwi 0x10faac): linear fog from ClipPlaneNearZ (64) + near * FogBaseZRange
# (12256) to 64 + far * 12256 units, the far clip plane at the fog end; the clear colour is
# the fog colour. Values here: [colour, start m, end m].
const FOG := {
	"nacht": [Color8(38, 38, 38), 12.41, 27.73],
	"verruckt": [Color8(124, 112, 81), 6.29, 23.96],
	"shinonuma": [Color8(158, 163, 158), 20.07, 27.73],
	"derriese": [Color8(48, 58, 66), 20.07, 33.86],
	"dogs": [Color8(158, 163, 158), 3.22, 15.48],
	"derriese_dogs": [Color8(48, 58, 66), 3.22, 15.48],
}
const DOG_FOG := {"derriese": "derriese_dogs"}   # Script.Level.DogConfigName (derriese.lua 217)
# Default fog of the remake (user's choice): the original's map configs (FOG above) were there
# to keep the 2010 iPhones' draw distance short. Here the fog only hides the far edges of
# the open maps: none near the player or indoors, the map's fog colour far away.
# [colour (the original map config's), start m, end m]; dog rounds still roll in FOG's dog config.
const DEFAULT_FOG := {
	"nacht": [Color8(38, 38, 38), 45.0, 110.0],
	"verruckt": [Color8(124, 112, 81), 30.0, 80.0],
	"shinonuma": [Color8(158, 163, 158), 40.0, 90.0],
	"derriese": [Color8(48, 58, 66), 45.0, 100.0],
}

# Dog rounds (waves.lua; Script.DogSpawns on Shi No Numa and Der Riese)
var dog_rounds := false
var dog_round := false
var dog_wave_counter := 0
var waves_since_dog := 0
var _dogs_total := 0
var _dogs_spawned := 0
var _dog_timer := 0.0
var _dog_health := 0.0

# Power-up drops: CPickupManager::OnEnemyKilled (kiwi 0xf36b8; its CVars are
# registered at 0xf3c8c with the code defaults in brackets, values from console.bin).
const DROP_CHANCE := 78.0 / 4096.0   # PickupDropOnDeathProbability 0.019 [0.02], rolled as rand(4096) < 78
const MAX_DROPS := 4                 # MaxPickupsPerWave [4]
const DROP_POINTS := 3000            # PickupPointsThreshold [100]: points earned since the last drop force one
const DROP_KILLS := 10               # PickupKillThreshold [10]: kills between drops, only with
const DIFFICULTY_TWEAKS := ["derriese"]   # Game.SetUsingDifficultyTweaks(true) (derriese.lua 298)
const NO_DROP_RADIUS := 1.0          # PickupNoSpawnCheckRadius [400 units]: no drop next to another pickup
const TIMED := 30.0                  # DoublePointsTime / InstaKillTime 30000 ms
var points_multiplier := 1
var insta_kill := false
var _drops_this_round := 0
var _drop_kills := 0       # kills since the last drop (CPickupManager +0x24)
var _drop_points := 0      # points earned since the last drop (+0x20, added at kiwi 0xcbc80)
var _timers := {}          # "instakill"/"doublepoints" -> seconds left (read by PowerupFrame)

# game over screen / leaderboard (ig_gameover: gos_points, gos_kills, gos_headshots)
var kills := 0
var headshots := 0
var score := 0             # points earned in the game (spending does not lower it)
var _resume := {}          # save_game.gd: the saved game being resumed


func start(level_name_: String) -> void:
	# difficulty of this game (fixed until the next one, as the original's profile setting)
	difficulty = RECRUIT if bool(Settings.get_value("recruit")) or OS.get_cmdline_user_args().has("--recruit") else REGULAR
	# resumed game (menu Riprendi, or --resume): save_game.gd
	_resume = SaveGame.pending
	SaveGame.pending = {}
	if _resume.is_empty() and OS.get_cmdline_user_args().has("--resume"):
		_resume = SaveGame.load_save()
		print("[save] resuming: %s" % ("round %d" % int(_resume["round"]) if not _resume.is_empty() else "no valid save at " + SaveGame.path()))
	if not _resume.is_empty() and String(_resume["map"]) != level_name_:
		_resume = {}
	if not _resume.is_empty():
		difficulty = int(_resume.get("difficulty", difficulty))
		Level.forced_perk_order = _resume.get("perk_order", [])
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
	sfx.level_name = level_name_
	sfx.using_vox = level_name_ in USING_VOX
	sfx.start_ambience(AMBIENCE.get(level_name_, AMBIENCE["nacht"]))
	player = Player.new()
	player.game = self
	add_child(player)
	player.global_transform = level.player_spawn
	player.died.connect(_on_player_died)
	sfx.listener = player
	RadioEggs.create(self)   # shootable radios/phone easter eggs (radio_egg.gd)
	Bridge.create(level)     # Der Riese drawbridge (bridge.gd)
	FlyTrap.create(self)     # Der Riese fly trap easter egg (flytrap.gd)
	DerrieseExtras.create(self)   # Der Riese start sequence, dropping doors, map boards (derriese_extras.gd)

	hud = Hud.new()
	add_child(hud)
	hud.bind(self)
	if not _resume.is_empty():
		SaveGame.apply_world(self, _resume)
		SaveGame.apply_player(self, _resume)
	add_child(SaveGame.Watcher.new(self))   # round-start saves, app background, auto-pause

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
	if not _resume.is_empty():
		SaveGame.begin_rounds(self, _resume)
		hud.show_message("Round %d" % (round_number + 1), 4.0)   # the round about to start
		return
	if OS.get_cmdline_user_args().has("--debug-start"):
		debug_start = true
	if level_name == "verruckt":
		# verruckt.lua Begin (bytecode, lost by the decompiler): RandomNumber(1, 3,
		# RAND_MYSTBOX) == 1 -> Timeout(6000, "PowerStart1") else "PowerStart2"; Timeout
		# plays it. RandomNumber's upper bound is exclusive (shinonuma.lua picks perk
		# machines with RandomNumber(1, PerkMachineCount + 1)): one in two.
		var line := "PowerStart1" if randi_range(1, 2) == 1 else "PowerStart2"
		get_tree().create_timer(6.0, false).timeout.connect(func(): Sfx.instance.play(line))
	# waves.lua Begin: Game.ShowStartGameMessage(4000) shows LS_ROUND_1 "Round 1" (kiwi 0x63974)
	hud.show_message("Round %d" % (DEBUG_ROUND if debug_start else 1), 4.0)
	if debug_start:
		round_number = DEBUG_ROUND - 1   # _next_round starts DEBUG_ROUND
		player.points = DEBUG_POINTS
		player.give_weapon(DEBUG_WEAPON)
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


func _setup_environment(level_id: String) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 1.0
	# SetDefaultFogConfig("<map>", 1000): linear depth fog of the map's CFogConfig (FOG)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 1.0
	_env = env
	_apply_fog(DEFAULT_FOG.get(level_id, DEFAULT_FOG["nacht"]))
	var fc := OS.get_cmdline_user_args().find("--fog-config")   # debug: an original config (FOG), e.g. nacht, dogs
	if fc >= 0 and FOG.has(OS.get_cmdline_user_args()[fc + 1]):
		_apply_fog(FOG[OS.get_cmdline_user_args()[fc + 1]])
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ------------------------------------------------------------------ rounds

func _next_round() -> void:
	_drops_this_round = 0
	round_number += 1
	dog_round = false
	# dog rounds take a round number but not a wave of the table (RecalculateWaveInfo)
	var w := wave_info(round_number - dog_wave_counter)
	var counts: Array = _wave_counts(w)
	_to_spawn = 0
	for c in counts:
		_to_spawn += int(c[0])
	_spawned = 0
	_hp = Vector2(w["ZombieHealth"][0], w["ZombieHealth"][1])
	_spawn_interval = w["SpawnSpeed"] / 1000.0
	# StartWave (waves.lua 502-519): initial zombie i at i x InitialSpawnSpeed (only
	# while i <= the wave total), the regular "WaveSpawnZombie" chain from
	# (InitialSpawns + 3) x InitialSpawnSpeed, then every SpawnSpeed
	var iss: float = w["InitialSpawnSpeed"] / 1000.0
	_initial_times.clear()
	for i in range(1, int(w["InitialSpawns"]) + 1):
		if i <= _to_spawn:
			_initial_times.append(i * iss)
	_round_time = 0.0
	_spawn_timer = (int(w["InitialSpawns"]) + 3) * iss
	_between_rounds = false
	hud.round_changed(round_number)
	if _wave_log:
		print("[wave] round %d start: difficulty %d, %d zombies, initial %s, chain from %.1f s every %.2f s" % [
			round_number, difficulty, _to_spawn, _initial_times, _spawn_timer, _spawn_interval])


# GetWaveInfo(n) (nacht.lua 95-101): the level's table, then ZombieWaveEquationFull.
# waves.json holds rounds 1..40 (tools/lua/dump_waves.lua); from round 11 they are
# already the equation, whose counts and spawn speeds do not depend on the round,
# so later rounds reuse the last entry with the equation's health
# (n^2 x 10 - 150, half of it as the low value; zombie.gd sets the real health).
func wave_info(n: int) -> Dictionary:
	n = maxi(n, 1)
	if n <= waves.size():
		return waves[n - 1]
	var w: Dictionary = (waves[-1] as Dictionary).duplicate()
	var hi := n * n * 10.0 - 150.0
	w["ZombieHealth"] = [hi / 2.0, hi]
	return w


# Zombies[GetDifficulty()] (RecalculateWaveInfo clamps the index to the table)
static func _wave_counts(w: Dictionary) -> Array:
	var cols: Array = w["Zombies"]
	return cols[clampi(difficulty, 1, cols.size()) - 1]


func _process(delta: float) -> void:
	_update_powerups(delta)
	if _between_rounds or player == null or player.dead:
		return
	if dog_round:
		_process_dog_round(delta)
		return
	_round_time += delta
	while not _initial_times.is_empty() and _round_time >= _initial_times[0]:
		_initial_times.pop_front()
		_timed_spawn()   # "WaveSpawnZombieInitial": no new timeout
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		# "WaveSpawnZombie": at the MaxZombiesAmount cap this tick is skipped, the
		# next one is SpawnSpeed later anyway (waves.lua 323-327, 409-418)
		_timed_spawn()
		_spawn_timer += _spawn_interval
	if _spawned >= _to_spawn and alive_count() <= 0:
		_between_rounds = true
		if _wave_log:
			print("[wave] round %d cleared at %d ms" % [round_number, Time.get_ticks_msec()])
		# EnemyKilled: "waveEnd" 2 s after the last kill, 0.5 s with FastWaves
		get_tree().create_timer(0.5 if level_name in FAST_WAVES else 2.0, false).timeout.connect(_wave_end)


# One spawn timeout: a zombie unless the wave is complete (IsSpawnLimitReached)
# or MaxZombiesAmount are alive (IsPopulationLimitReached).
func _timed_spawn() -> void:
	if _spawned < _to_spawn and _alive < max_alive:
		_spawn_zombie()
		if _wave_log:
			print("[wave] round %d t=%.2f spawn %d/%d alive %d" % [round_number, _round_time, _spawned, _to_spawn, _alive])


var _wave_log := OS.get_cmdline_user_args().has("--wave-log")   # round timing log (tests)


# waves.lua "waveEnd" (bytecode 74-117): end_wave, then on DogSpawns maps a dog round
# after more than two rounds since the last one when RandomNumber(1, 3) == 1 or
# after more than four, the next round 5 s later; other maps 6 s later.
func _wave_end() -> void:
	if not is_inside_tree() or player == null or player.dead:
		return
	Sfx.instance.play("end_wave")
	if _wave_log:
		print("[wave] round %d end_wave at %d ms" % [round_number, Time.get_ticks_msec()])
	if not dog_rounds:
		get_tree().create_timer(6.0, false).timeout.connect(_next_round)
		return
	waves_since_dog += 1
	var dogs := waves_since_dog > 2 and (lua_random(1, 3) == 1 or waves_since_dog > 4)
	if OS.get_cmdline_user_args().has("--dogs-next"):
		dogs = true
	get_tree().create_timer(5.0, false).timeout.connect(_start_dog_round if dogs else _next_round)


# Game.RandomNumber(lo, hi): the upper bound is exclusive (the scripts index lists
# with RandomNumber(1, n + 1): ingame.lua:682 and SelectRandomArea, waves.lua:457), so
# RandomNumber(1, 3) is 1 or 2.
static func lua_random(lo: int, hi: int) -> int:
	return randi_range(lo, maxi(hi - 1, lo))


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
var _last_spawn_key := ""   # Script.LastSpawnNumber


# PickRandomSpawnNumber (ingame.lua 636-649): a random AvailableSpawns entry, drawn
# again (up to 20 times) while it is the same as the previous pick.
func _pick_random_spawn(cands: Array) -> Dictionary:
	var c: Dictionary = cands.pick_random()
	for i in 20:
		if cands.size() < 2 or _cand_key(c) != _last_spawn_key:
			break
		c = cands.pick_random()
	_last_spawn_key = _cand_key(c)
	return c


static func _cand_key(c: Dictionary) -> String:
	return "%s|%s" % [c["spawn"], c["window"]]


func _wave_speed() -> int:
	if _spawned == 0 or _wave_speeds.size() != _to_spawn:
		_wave_speeds.clear()
		for pair in _wave_counts(wave_info(round_number - dog_wave_counter)):
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
	var c := {}
	if level_name in LOCAL_SPAWNING:
		# PickLocalSpawnpoint: the player's area or an open neighbour, one of its 4 closest spawns
		var near := _spawn_candidates(_local_areas())
		if not near.is_empty():
			var area: String = near.map(func(x): return x["area"]).pick_random()
			near = near.filter(func(x): return x["area"] == area)
			near.sort_custom(func(a, b): return _cand_pos(a).distance_to(player.global_position) < _cand_pos(b).distance_to(player.global_position))
			c = near.slice(0, 4).pick_random()
	if c.is_empty():
		c = _pick_random_spawn(cands)
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
	# waves.lua: template "zombie" or "zombie_var<n>" with n = GetSpawnCount() % 8
	z.variant = spawn_count % 8
	spawn_count += 1
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
	_track(z)
	return z


# ------------------------------------------------------------------ round bookkeeping
# Every zombie/dog of the round is tracked by node, not by a bare counter: a kill is
# counted once however many times it is reported, and the round cannot end while a
# tracked body is still alive. One that leaves the tree without dying (freed by
# something else) is replaced: the wave spawns another.

func _track(z: Zombie) -> void:
	_live[z] = true
	z.tree_exiting.connect(_on_tracked_exit.bind(z), CONNECT_ONE_SHOT)
	_alive = _live.size() + _dogs_pending


func _untrack(z: Zombie) -> bool:
	var was := _live.erase(z)
	_alive = _live.size() + _dogs_pending
	return was


func _on_tracked_exit(z: Zombie) -> void:
	if not _live.has(z):
		return
	_untrack(z)
	if z.state != Zombie.State.DEAD and not z is Dog and not _between_rounds and is_inside_tree():
		_spawned = maxi(_spawned - 1, 0)


# Living tracked enemies (pending dogs included). A tracked body counts while it is
# not DEAD, whatever the kill signal said.
func alive_count() -> int:
	var n := _dogs_pending
	for z in _live.keys():
		if not is_instance_valid(z):
			_live.erase(z)
		elif (z as Zombie).state != Zombie.State.DEAD:
			n += 1
	_alive = _live.size() + _dogs_pending
	return n


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
	_dogs_total = _dog_number(dog_wave_counter, difficulty)
	_dogs_spawned = 0
	_dog_timer = 7.0
	hud.round_changed(round_number)
	Sfx.instance.vox("dog_round")   # PlayMultiplayerSound("dog_round", true) (waves.lua 542-544)
	Sfx.instance.play("dog_fog")
	# the level's "dogWaveStart" Timeout keeps its ambience without "zombies"
	# (derriese.lua 407-411, shinonuma Timeout bytecode 140-163)
	Sfx.instance.start_ambience(AMBIENCE.get(level_name, []).filter(func(c): return c != "zombies"))
	_fog(true)
	get_tree().create_timer(7.5, false).timeout.connect(func(): Sfx.instance.play("dog_start_vox"))


# DogNumberCalculation(dogWaveCounter, difficulty) (waves.lua 616-650): the shipped
# bytecode (waves.luac, function at line 441) jumps past its per-difficulty branches
# (12/16/18 and 16/18/20 are dead code), so every difficulty gets 6 dogs in the
# first two dog rounds and 8 from the third on.
static func _dog_number(counter: int, _difficulty: int) -> int:
	return 6 if counter < 3 else 8


func _process_dog_round(delta: float) -> void:
	# "SpawnDog" every 2 s while fewer than two are alive (DogAmount = 2)
	_dog_timer -= delta
	if _dog_timer <= 0.0 and _dogs_spawned < _dogs_total:
		_dog_timer = 2.0
		if _alive < 2:
			spawn_dog(false)


# Script.SpawnDog: one of the two dog spawns of the player's area closest to the
# player; a lightning strike, then the dog.
func spawn_dog(untracked: bool) -> void:
	var spots := []
	# PickLocalSpawnpoint(player, true, false, 2) (ingame.lua:765): no neighbours,
	# only the area the player stands in (every area of the dog maps has dog spawns)
	var here := player_area()
	var areas := [here] if here != "" else []
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
		_dogs_pending += 1
		_alive = _live.size() + _dogs_pending
	_lightning(at)
	Sfx.instance.play_at("dog_spawn", at + Vector3.UP)
	await get_tree().create_timer(0.6, false).timeout
	var d := Dog.new()
	if not untracked:
		_dogs_pending -= 1
		_track(d)
	d.untracked = untracked
	d.flame = Dog.roll_flame()   # "flame_dogSpawn" or "normal_dogSpawn"
	# SpawnDog (ingame.lua 788-791): Script.Mode.DogHealth, which stays at the last dog
	# round's value (teleporter dogs too); 50 when it has none (before the first dog round)
	d.setup_dog(at + Vector3.UP * 0.1, player, _dog_health if _dog_health > 0.0 else 50.0, level.windows[0])
	d.killed.connect(_on_dog_killed)
	add_child(d)


func _on_dog_killed(d: Zombie, headshot: bool, knife: bool) -> void:
	# dogs have no CDismembermentSpec: no head to take off, no headshot points
	if not suppress_kill_points:
		player.add_points((120 if knife else 50) * points_multiplier)
	kills += 1
	headshots += int(headshot)
	if (d as Dog).untracked:
		return
	_untrack(d)
	# EnemyKilled: the last dog of the round drops a Max Ammo, the round ends 2 s later
	if dog_round and _dogs_spawned >= _dogs_total and alive_count() <= 0:
		spawn_powerup("maxammo", d.global_position)
		dog_round = false
		_between_rounds = true
		get_tree().create_timer(2.0, false).timeout.connect(_dog_round_end)


# dogWaveEnd: music, fog lifts, next zombie round 6 s later
func _dog_round_end() -> void:
	Sfx.instance.play("dog_end_music")
	Sfx.instance.start_ambience(AMBIENCE.get(level_name, AMBIENCE["nacht"]))
	_fog(false)
	get_tree().create_timer(6.0, false).timeout.connect(_next_round)


# Dog wave fog: SetFogConfig(DogConfigName or "dogs", 4000) at StartDogWave; at
# "dogWaveEnd" SetFogMappingEnabled(true) goes back to the default config with its
# SetDefaultFogConfig time, 1000 ms (CFogManager 0x10f77c / 0x10f4c0).
var _fog_tween: Tween

func _fog(on: bool) -> void:
	if _env == null:
		return
	var cfg: Array = FOG[DOG_FOG.get(level_name, "dogs")] if on else DEFAULT_FOG.get(level_name, DEFAULT_FOG["nacht"])
	if _fog_tween:
		_fog_tween.kill()
	_fog_tween = create_tween().set_parallel()
	var t := 4.0 if on else 1.0
	_fog_tween.tween_property(_env, "fog_light_color", cfg[0], t)
	_fog_tween.tween_property(_env, "background_color", cfg[0], t)
	_fog_tween.tween_property(_env, "fog_depth_begin", cfg[1], t)
	_fog_tween.tween_property(_env, "fog_depth_end", cfg[2], t)


func _apply_fog(cfg: Array) -> void:
	_env.fog_light_color = cfg[0]
	_env.background_color = cfg[0]
	_env.fog_depth_begin = cfg[1]
	_env.fog_depth_end = cfg[2]


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
	if not _untrack(z):
		return   # not one of the round's, or already counted
	# Original (kiwi 0x1315a0): PlayerKillPointsMelee 130, PlayerKillPoints 60, a kill that
	# took the head off PlayerHeadShotPoints[streak] (100..140, Player.headshot_points), all
	# including the 10 of the hit (PlayerHitPoints, added by take_damage)
	if not suppress_kill_points:
		player.add_points((120 if knife else (player.headshot_points() - 10 if headshot else 50)) * points_multiplier)
	kills += 1
	headshots += int(headshot)
	if not _nuking:
		_roll_drop(z.global_position)


# CPickupManager::OnEnemyKilled (kiwi 0xf36b8): count the kill; below MaxPickupsPerWave
# (and, with the difficulty tweaks, after more than PickupKillThreshold kills since the
# last drop) a drop comes with probability PickupDropOnDeathProbability, or anyway once
# more than PickupPointsThreshold points were earned since the last one. The kill count
# restarts at every drop, the points when they forced it (always with the tweaks). No
# drop within PickupNoSpawnCheckRadius of another pickup.
func _roll_drop(at: Vector3) -> void:
	_drop_kills += 1
	if _drops_this_round >= MAX_DROPS:
		return
	var tweaks := level_name in DIFFICULTY_TWEAKS
	if tweaks and _drop_kills <= DROP_KILLS:
		return
	if not (randi() % 4096 < int(DROP_CHANCE * 4096.0) or _drop_points > DROP_POINTS):
		return
	_drop_kills = 0
	if tweaks or _drop_points > DROP_POINTS:
		_drop_points = 0
	for n in get_children():
		if n is Powerup and n.global_position.distance_to(at + Vector3.UP * 0.6) < NO_DROP_RADIUS:
			return
	spawn_powerup(_drop_kind(), at)


# Kind choice (kiwi 0xf39e4): a random one of the five, without Double Points or
# Insta-Kill while it is running. The original offers the Carpenter only where the
# level calls Game.SetUseCarpenter(true) (Der Riese); here it stays on every map.
func _drop_kind() -> String:
	var kinds := Powerup.KINDS.keys().filter(func(k): return not _timers.has(k))
	return kinds.pick_random() if not kinds.is_empty() else "maxammo"


# Player.add_points: earned points move the drop threshold and the game score.
func points_earned(n: int) -> void:
	if n > 0:
		_drop_points += n
		score += n


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
	Achievements.powerup(kind)   # before the nuke kills (achievements.gd)
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


# PickupMessageTimeMs: the pickup's message, then its CGuiFramePowerup icon (hud_powerups.gd)
func _show_powerup(text: String) -> void:
	if hud:
		hud.pickup_message(text)


func _update_powerups(delta: float) -> void:
	for k in _timers.keys():
		_timers[k] -= delta
		if _timers[k] <= 0.0:
			_timers.erase(k)
			if k == "instakill":
				insta_kill = false
			elif k == "doublepoints":
				points_multiplier = 1


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
	SaveGame.clear()   # the saved game is over
	hud.game_over(round_number)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ effects

func muzzle_flash(cam: Camera3D, muzzle: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.4)
	l.light_energy = 3.0
	l.omni_range = 6.0
	# lights the surroundings only: right next to the gun it burnt the first-person
	# model to flat yellow, constantly with fast guns (the PPSh fires every 0.041 s)
	l.light_cull_mask = ~Viewmodel.LAYER
	cam.add_child(l)
	l.global_position = muzzle - cam.global_basis.z * 0.3   # just past the barrel

	get_tree().create_timer(0.05).timeout.connect(l.queue_free)


func spawn_impact(pos: Vector3, normal: Vector3) -> void:
	# Game.SetUsingImpactEffects(false) on Nacht and Verrückt: the impact routine (kiwi
	# 0x20eadc) returns at once; elsewhere only within ImpactEffectsMaxRange of the camera
	if not level_name in IMPACT_EFFECTS:
		return
	if player and player.global_position.distance_to(pos) > IMPACT_MAX_RANGE:
		return
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
