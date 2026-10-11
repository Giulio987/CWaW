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
	for a in cfg["start_areas"]:
		open_areas.append(String(a).to_lower())
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

	var sfx := Sfx.new()
	add_child(sfx)
	sfx.start_ambience(["zombies", "world", "wind"])
	player = Player.new()
	player.game = self
	add_child(player)
	player.global_transform = level.player_spawn
	player.died.connect(_on_player_died)
	sfx.listener = player

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
	hud.message("Caricamento navigazione…")
	level.navigation_ready.connect(_begin, CONNECT_ONE_SHOT)
	level.bake_navigation()


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
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ------------------------------------------------------------------ rounds

func _next_round() -> void:
	_drops_this_round = 0
	round_number += 1
	var w: Dictionary = waves[min(round_number, waves.size()) - 1]
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
		get_tree().create_timer(8.0).timeout.connect(_next_round)


func _spawn_zombie() -> void:
	var spawns := []
	for area in open_areas:
		spawns += level.entities_matching(area + "ZombieSpawn")
	if spawns.is_empty():
		return
	var sp: String = spawns.pick_random()
	var area := sp.substr(0, sp.find("Zombie")).to_lower()
	var wins := level.windows.filter(func(w): return w.area == area)
	if wins.is_empty():
		wins = level.windows
	var origin := level.entity_transform(sp).origin
	wins.sort_custom(func(a, b): return a.outside.distance_to(origin) < b.outside.distance_to(origin))
	var z := Zombie.new()
	var runner: bool = round_number >= 4 and randf() < clamp((round_number - 3) * 0.15, 0.0, 0.8)
	z.setup(origin, wins[0], player, randf_range(_hp.x, _hp.y), runner)
	z.killed.connect(_on_zombie_killed)
	add_child(z)
	_spawned += 1
	_alive += 1


func _on_zombie_killed(z: Zombie, headshot: bool, knife: bool) -> void:
	_alive -= 1
	# World at War: 130 knife kill, 100 headshot, 60 other (plus 10 per hit)
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
				w["reserve"] = Weapons.stats(w["name"])["reserve"]
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
