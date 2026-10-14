# Zombie: walks from its spawn to a window, tears the boards down, climbs in
# and chases the player. Body animations are in-place; movement speed comes
# from the paired root-motion track (see analysis/zombie_anims.tsv).
class_name Zombie
extends CharacterBody3D

signal killed(zombie: Zombie, headshot: bool, knife: bool)

# Each level's shared group loads one zombie model group (nacht_shared / verruckt_shared:
# zombiesModelsGer, shinonuma_shared: zombiesModelsJap, derriese_shared: zombiesModelsRiese).
# Their CRenderableModelSetLODQuotaSpec (b0c61ea8 / b0c62ae5 / fb917fa2) never uses the
# first model (fee5ccda / 4009f754): the top LOD the game draws is the second one.
const MODELS := {
	"ger": "res://assets/characters/ingame/zombiesmodelsger/fee5ccdb.glb",
	"jap": "res://assets/characters/ingame/zombiesmodelsjap/4009f755.glb",
	"riese": "res://assets/characters/ingame/zombiesmodelsriese/fee5ccdb.glb",
}
const LEVEL_MODELS := {"shinonuma": "jap", "derriese": "riese"}
# The 8 templates zombie, zombie_var1..zombie_var7 (waves.lua 370-378 cycles them by
# spawn count % 8) are the same model with two component lists of zombiesbase:
#  - CMatAnimSetterSpec 320775bb (frame 0) / 320775bc (frame 4): the cel of the animated
#    body material (771bc860 / 392ad35a: cel 128 texels wide, 8 per row of the 1024 atlas),
#    so frame 4 moves the UVs half the texture across (the other uniform);
#  - CModelBlockSwitcherSpec b762e213 / 7217bdf7 / a4ceb1d6 / af97215a: which blocks
#    (triangle lists, the mesh parts) each switch shows. Switch = [blocks, on at start]:
#    head_on {neck, 25d19111, head, helmet} 1, head_off {94c24809} 1, spare head 0,
#    left_arm_on {leftarm | sleevel} 1, left_arm_off {e1f1c9f3} 1, right_arm_on {rightarm |
#    sleever} 1, right_arm_off {75a47286} 1, legs_on {legs} 1, legs_off {acf2ab46} 0,
#    body_on {body} 1, body_off {980daf40} 1, sleeves (unused arms) 0, hat {a3eaf623} 0.
#    The "_off" blocks drawn at start are the gore inside the limb (hidden by it); here
#    they stay hidden until the limb comes off.
# variant -> [material frame, head block, arm blocks, helmet / hat block (jap model)]
const VARIANTS := [
	[0, "3f7355a5", "arms", "01d84724"], [4, "3f7355a5", "arms", "01d84724"],   # b762e213
	[0, "headb", "arms", "01d84724"], [4, "headb", "arms", "01d84724"],         # 7217bdf7
	[0, "3f7355a5", "sleeves", "a3eaf623"], [4, "3f7355a5", "sleeves", "a3eaf623"],  # a4ceb1d6
	[0, "headb", "sleeves", "a3eaf623"], [4, "headb", "sleeves", "a3eaf623"],   # af97215a
]
const ANIM_MATERIALS := ["771bc860", "392ad35a"]   # the materials with the cel animation
const ALL_BLOCKS := ["neck", "25d19111", "3f7355a5", "headb", "01d84724", "a3eaf623", "94c24809",
	"leftarm", "sleevel", "e1f1c9f3", "rightarm", "sleever", "75a47286", "legs", "acf2ab46",
	"body", "980daf40", "89513fe2"]
var variant := -1         # 0..7 (set before add_child; -1 = random)
var model_set := ""       # "ger" / "jap" / "riese" (set before add_child; "" = by level)
var head_block := "3f7355a5"
var _blocks := {}         # block name -> [MeshInstance3D] (all its materials)
# body animation -> speed (m/s) of its root-motion partner
const WALKS := {"fbe7b3da": 0.96, "fbe7b3db": 0.95, "fbe7b3dc": 1.0, "fbe7b3dd": 1.21,
	"fbe7b3de": 0.57, "fbe7b3df": 0.58, "fbe7b3e0": 0.65, "9a1f4265": 0.69}
const RUNS := {"c9903fc0": 3.03, "842441ac": 3.61, "842441ab": 3.49, "c349cc28": 1.65,
	"4e83b4a9": 2.02, "4e83b4aa": 1.97}
# The original "zombie speed" 1..14 (second number of each pair in the wave tables,
# ZombieMovementMaxSpeed = 14) selects movement state 7..20 of the zombie anim state
# machine (zombiesanimsger CIsAnimStateMachine "zombie"): [body anim, playback rate].
# 1-8 walk, 9-11 run, 12-14 sprint. Ground speed = root-motion speed x rate.
const SPEED_STATES := [
	["fbe7b3dc", 0.8], ["fbe7b3da", 0.7], ["fbe7b3db", 0.8], ["fbe7b3dd", 0.8],
	["fbe7b3de", 1.0], ["fbe7b3df", 1.0], ["fbe7b3e0", 1.0], ["9a1f4265", 1.0],
	["c349cc28", 1.0], ["4e83b4a9", 1.0], ["4e83b4aa", 1.0],
	["c9903fc0", 1.0], ["842441ab", 0.8], ["842441ac", 0.9]]
# console.bin: ZombieSpeedUpThresholds {5,8,12}, ZombieSpeedUpTime 180000 ms. The
# speed-up is enabled by waves.lua once a wave (> 4) has spawned all its zombies.
# Interpretation: a zombie still alive ZombieSpeedUpTime after that steps up to the
# next threshold speed (then up to 14), so stragglers end up running.
const SPEED_UP_THRESHOLDS := [5, 8, 12]
const SPEED_UP_TIME := 180.0
const MAX_SPEED_INDEX := 14
# Rising out of the ground ("zombie_ground" spawns: Verrückt courtyard, Der Riese
# DRSpecialGroundSpawns; "_water" swamp spawns): state machine f402afc2 plays
# 013110cb (10.1 s at rate 1, hips from -0.82 m to standing) with a "spawnEffect".
const RISE := "013110cb"
const IDLE := "c98b07c8"
const ATTACKS := ["fab4136a", "fb0fe592"]
const DEATHS := ["20b0e521", "371f7199", "f037474d"]
# electric damage (type 6: Wunderwaffe) picks one of ZombieNumDeathsLightning = 2 lightning
# deaths: states 34 / 35 of the state machine f402afc2 (the normal deaths are 24-26)
const LIGHTNING_DEATHS := ["407213ce", "407213cf"]
var electric_death := false   # set by wunderwaffe.gd before the killing hit
# crawlers ("zombies with half a body", CrawlingZombieMaxHealth in the original): legs
# blown off, they drag themselves along with these animations
const CRAWL := "4b64cfc6"         # root-motion partner a429672c: 0.52 m/s
const CRAWL_SPEED := 0.52
const CRAWL_ATTACK := "dddede7a"  # zombie_crawl_attack
const CRAWL_DEATH := "bd4b9b0a"
var crawler := false
var max_health := 100.0
var _shape: CollisionShape3D
# window: swipe at the boards in place, then climb through (its root-motion partner
# 4c478fd4 moves 1.34 m forward over the 4.07 s animation)
const TEAR := "fb0fe592"
const CLIMB := "9c58e56e"
const ATTACK_RANGE := 1.3
# Zombie spec (zombiesbase CIwSpecList c9872545): CAIControllerSpec (Serialise kiwi 0x119be8)
# embeds a CAttackSpec (Serialise 0xa8a24): 0x10 damage 10, 0x14 damage type 0, 0x18 reach
# 400 units (1 m). The ASM "damage" event (CDamageHandler kiwi 0xe9d78) sends it through
# 0xa70a0 to CHealth::TakeDamage (0x19c4c8): 10 of the player's 20 -> two hits down
# (Juggernog 40: four). x HEALTH_SCALE for the remake.
const ATTACK_DAMAGE := 10.0 * Player.HEALTH_SCALE

enum State { TO_WINDOW, TEARING, CLIMBING, CHASE, ATTACK, DEAD, RISING }

# Death is final: once DEAD no callback (climb/drop tween, rise timer, attack) can
# bring the body back. Attempts are counted for the lifecycle tests.
var state := State.TO_WINDOW:
	set(v):
		if state == State.DEAD and v != State.DEAD:
			revive_blocked += 1
			return
		state = v
var revive_blocked := 0
var health := 100.0
var window: Barricade
var target: Player
var lure: Node3D   # a thrown Monkey Bomb (monkey_bomb.gd): CHASE goes for it while valid
var move_anim := ""
var speed := 1.0
var move_rate := 1.0     # playback rate of move_anim (SPEED_STATES)
var speed_index := 0     # original speed 1..14, 0 = picked from WALKS/RUNS
var rise := false        # set before add_child: climb out of the ground first
var water := false       # "_water" template (Shi No Numa swamp spawns): rises out of the water
var entry := Vector3.INF # set before add_child: walk straight in from a spawn off the navmesh
var _after_rise: State = State.TO_WINDOW
var _speed_up_t := 0.0
var life := 0.0             # seconds since spawn
var reached_window := -1.0  # life when it got to its window (tests / stuck checks)

var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _model: Node3D
var _timer := 0.0
var _hit_done := false
var _repath := 0.0
var _best_dist := INF
var _stall := 0.0

# Turning (console.bin, angles 4096 = 360 degrees per second, a random value of the range
# per zombie): ZombieTurnSpeedRangeMove {2000,5000} turns the walking direction,
# ZombieTurnSpeedRangeRender {1000,2000} the body drawn on top of it.
const TURN_SPEED_MOVE := Vector2(2000, 5000)
const TURN_SPEED_RENDER := Vector2(1000, 2000)
const MAX_BODY_LAG := deg_to_rad(45.0)   # remake: the body never trails further behind
var _turn_move := 5.0
var _turn_render := 3.0
var _heading := 0.0      # walking direction (yaw); rotation.y is the drawn body

# Target prediction (ZombiePredictionEnabled 1): farther than ZombiePredictionProximity
# (750 units = 1.875 m) a zombie heads for the player's predicted position, the point
# ZombiePredictionDist ahead along his movement, clipped by the navmesh (kiwi 0x209ee8:
# the raw value 1228, written as the fixed 0.3, is passed as a distance in units = 3.07 m).
const PREDICTION := true
const PREDICTION_PROXIMITY := 750.0 / 400.0
const PREDICTION_DIST := 1228.0 / 400.0

# Antiflock (ZombieAntiflockEnabled 1, kiwi 0x138c4c decision / 0x13936c state): every
# ZombieAntiflockInterval (1 s) a chasing zombie between ZombieAntiflockMinRange and
# MaxRange (2000..10000 units = 5..25 m) from the player counts the zombies after the same
# player within ZombieAntiflockRadius (800 = 2 m). With at least ZombieAntiflockCrowdSize (4)
# of them, pressing on it by more than ZombieAntiflockCrowdPushThreshold (sum of 2^36/d^2,
# d in units), it steps away from the crowd: the direction away from them, turned towards the
# player to at most ZombieAntiflockAngleHeading (796 = 70 degrees) off the line to him (not
# at all when it is within ZombieAntiflockAngleTolerance, 20 = 1.8 degrees, of that line),
# ZombieAntiflockDist ahead (1200 = 3 m). The detour lasts ZombieAntiflockTime (2 s), until
# it is within ZombieAntiflockTolerance (500 = 1.25 m) of the point or the player is nearer
# than MinRange.
const ANTIFLOCK := true
const AF_INTERVAL := 1.0
const AF_TIME := 2.0
const AF_MIN := 2000.0 / 400.0
const AF_MAX := 10000.0 / 400.0
const AF_RADIUS := 800.0 / 400.0
const AF_CROWD := 4
const AF_PUSH := 1000000.0
const AF_ANGLE_TOL := 20.0 * TAU / 4096.0
const AF_HEADING := 796.0 * TAU / 4096.0
const AF_DIST := 1200.0 / 400.0
const AF_TOLERANCE := 500.0 / 400.0
var antiflock_on := false
var antiflock_count := 0      # detours taken (tests)
var _af_goal := Vector3.ZERO
var _af_timer := -1.0


func setup(spawn: Vector3, win: Barricade, player: Player, hp: float, runner: bool, speed_idx := 0) -> void:
	window = win
	target = player
	health = hp
	max_health = hp
	if speed_idx > 0:
		set_speed_index(speed_idx)
	else:
		var pool := RUNS if runner else WALKS
		move_anim = pool.keys().pick_random()
		speed = pool[move_anim]
	position = spawn


func set_speed_index(i: int) -> void:
	speed_index = clampi(i, 1, MAX_SPEED_INDEX)
	var st: Array = SPEED_STATES[speed_index - 1]
	move_anim = st[0]
	move_rate = st[1]
	speed = float(WALKS.get(move_anim, RUNS.get(move_anim, 1.0))) * move_rate
	if _anim and not crawler and state in [State.TO_WINDOW, State.CHASE]:
		_play(move_anim)


# World at War zombie health: 150 at round 1, +100 per round up to 950 at round 9,
# then x1.1 per round (2710 at round 20). Used instead of the iOS wave table values.
static func round_health(r: int) -> float:
	r = maxi(r, 1)
	if r <= 9:
		return 150.0 + 100.0 * (r - 1)
	return 950.0 * pow(1.1, r - 9)


func _ready() -> void:
	add_to_group("zombies")
	var g := get_parent() as Game
	if g and g.round_number > 0 and health < 1e5:  # tests use huge health on purpose
		health = round_health(g.round_number)
		max_health = health
	collision_layer = 2
	collision_mask = 1 | 4 | Level.NAV_FLOOR_LAYER
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	_shape = shape
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	_setup_model(g)
	_add_shadow(self, SHADOW_SIZE)
	_turn_move = deg_to_rad(randf_range(TURN_SPEED_MOVE.x, TURN_SPEED_MOVE.y) * 360.0 / 4096.0)
	_turn_render = deg_to_rad(randf_range(TURN_SPEED_RENDER.x, TURN_SPEED_RENDER.y) * 360.0 / 4096.0)
	_heading = rotation.y
	_anim = _model.find_children("*", "AnimationPlayer")[0]
	for a in WALKS.keys() + RUNS.keys() + [IDLE] + ATTACKS:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.radius = 0.35
	_agent.height = 1.8
	add_child(_agent)
	_agent.target_position = window.outside
	if rise:
		_start_rise()
	else:
		_play(move_anim)
		if entry != Vector3.INF:
			_start_entry()


# ------------------------------------------------------------------ model / template
static var _scenes := {}
static var _cel_copies := {}   # material -> its copy on another cel


# The level's zombie model with the blocks and the material cel of template `variant`.
func _setup_model(g: Game) -> void:
	if model_set == "":
		model_set = LEVEL_MODELS.get(g.level_name if g else "", "ger")
	var path: String = MODELS.get(model_set, MODELS["ger"])
	if not _scenes.has(path):
		_scenes[path] = load(path)
	_model = (_scenes[path] as PackedScene).instantiate()
	add_child(_model)
	if variant < 0:
		variant = randi() % VARIANTS.size()
	var v: Array = VARIANTS[variant % VARIANTS.size()]
	head_block = v[1]
	var on := ["neck", "25d19111", head_block, v[3], "legs", "body", "89513fe2"]
	on += ["leftarm", "rightarm"] if v[2] == "arms" else ["sleevel", "sleever"]
	_blocks.clear()
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D"):
		var base := _block_of(mi.name)
		if not _blocks.has(base):
			_blocks[base] = []
		_blocks[base].append(mi)
		mi.visible = base in on or not base in ALL_BLOCKS
		mi.layers = CHAR_LAYER
		if int(v[0]) != 0:
			_set_cel(mi, int(v[0]))


# "neck_m1" -> "neck": the exporter splits a block per material
static func _block_of(n: String) -> String:
	var i := n.rfind("_m")
	return n.substr(0, i) if i > 0 and n.substr(i + 2).is_valid_int() else n


# CMatAnimSetterSpec frame: cel `frame` of the animated material (128 of 1024 texels per
# cel horizontally, 8 per row).
func _set_cel(mi: MeshInstance3D, frame: int) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
		if m == null or not m.resource_name in ANIM_MATERIALS:
			continue
		var key := "%d:%d" % [m.get_instance_id(), frame]
		if not _cel_copies.has(key):
			var c := m.duplicate() as BaseMaterial3D
			c.uv1_offset.x += float(frame % 8) * 0.125
			c.uv1_offset.y += float(frame / 8) * 0.125
			_cel_copies[key] = c
		mi.set_surface_override_material(s, _cel_copies[key])


func _show_block(base: String, on: bool) -> void:
	for mi in _blocks.get(base, []):
		(mi as MeshInstance3D).visible = on


func _block_visible(base: String) -> bool:
	for mi in _blocks.get(base, []):
		if (mi as MeshInstance3D).visible:
			return true
	return false


# Blob shadow (CRenderableShadowSpec of the zombie and dog spec lists): model 6375f9db of
# the effects group, a flat quad of +-229 units (1.15 m) textured with the soft blob
# 1bb1226b (material 1220d7c3, alpha blended), kept on the ground under the character.
const SHADOW_SIZE := 458.0 / 400.0
const CHAR_LAYER := 4   # render layer 3: zombie / dog meshes (not darkened by the shadows)
const SHADOW_TEX := "res://assets/textures/ingame/effects/1bb1226b.png"
static var _shadow_tex: Texture2D


static func _add_shadow(owner: Node3D, size: float) -> Decal:
	if _shadow_tex == null and ResourceLoader.exists(SHADOW_TEX):
		_shadow_tex = load(SHADOW_TEX)
	if _shadow_tex == null:
		return null
	var d := Decal.new()
	d.name = "Shadow"
	d.texture_albedo = _shadow_tex
	# projected down onto the ground from just above the feet (up to 1.5 m below them)
	d.size = Vector3(size, 2.0, size)
	d.position = Vector3.DOWN * 0.5
	d.upper_fade = 0.1
	d.lower_fade = 0.5
	d.modulate = Color(0.3, 0.3, 0.3, 0.8)   # the blob is dark blue-grey: keep it neutral
	d.cull_mask = 0xFFFFF & ~(CHAR_LAYER | Viewmodel.LAYER)   # the ground only
	owner.add_child(d)
	return d


# Spawns behind the jungle backdrop (game.gd _spawn_entry): straight in to the navmesh.
func _start_entry() -> void:
	_unsticking = true
	collision_mask = 0
	var d := entry - global_position
	rotation.y = atan2(d.x, d.z)
	_heading = rotation.y
	_unstick_tw = create_tween()
	_unstick_tw.tween_property(self, "global_position", entry + Vector3.UP * 0.05, d.length() / maxf(speed, 0.5))
	_unstick_tw.finished.connect(func():
		_end_unstick()
		# the agent's path still starts behind the backdrop: path again from here
		_best_dist = INF
		_stall = 0.0
		_agent.target_position = window.outside)


func _play(a: String, blend := 0.2) -> void:
	if _anim.current_animation != a:
		_anim.play(a, blend, move_rate if a == move_anim else 1.0)


func _start_rise() -> void:
	_after_rise = state
	state = State.RISING
	var a := _anim.get_animation(RISE)
	a.loop_mode = Animation.LOOP_NONE
	_anim.play(RISE, 0.0)
	_timer = a.length
	# the hit capsule comes up with the body
	_shape.position.y = -0.5
	var tw := create_tween()
	tw.tween_property(_shape, "position:y", 0.9, a.length * 0.9).set_trans(Tween.TRANS_SINE)
	_spawn_dirt()
	# the state machines differ only in these: f402afc2 (ground) plays sound 9a86b3fd and
	# effect 4fb6c21f, d06d3216 (water) sound 9c17d777 and effect b898c591
	if Sfx.instance:
		Sfx.instance.play_at("9c17d777" if water else "9a86b3fd", global_position + Vector3.UP * 0.5)


# "spawnEffect": clods of earth (or water) thrown up where the zombie breaks out.
func _spawn_dirt() -> void:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.4
	p.explosiveness = 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -7.0, 0)
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.11
	var mesh: PrimitiveMesh = BoxMesh.new()
	(mesh as BoxMesh).size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.13, 0.09)
	mat.roughness = 1.0
	if water:
		# murky swamp water: drops and spray instead of clods
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 6
		sm.rings = 3
		mesh = sm
		mat.albedo_color = Color(0.22, 0.26, 0.2, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.2
		mat.metallic_specular = 0.8
		p.amount = 60
		p.spread = 25.0
		p.initial_velocity_max = 3.2
		p.scale_amount_min = 0.03
		p.scale_amount_max = 0.08
	mesh.material = mat
	p.mesh = mesh
	p.position = Vector3(0, 0.05, 0.2)
	add_child(p)
	p.emitting = true
	# timers owned by the particles: nothing left behind when the zombie dies mid-rise
	var tw := p.create_tween()
	tw.tween_interval(_timer * 0.8)
	tw.tween_property(p, "emitting", false, 0.0)
	tw.tween_interval(_timer * 0.2 + 2.0)
	tw.tween_callback(p.queue_free)


func _update_speed_up(delta: float) -> void:
	var g := get_parent() as Game
	if g == null or speed_index <= 0 or speed_index >= MAX_SPEED_INDEX or crawler:
		return
	if not (g.round_number > 4 and g._spawned >= g._to_spawn and not g._between_rounds):
		return
	_speed_up_t += delta
	if _speed_up_t >= SPEED_UP_TIME:
		_speed_up_t = 0.0
		var next := MAX_SPEED_INDEX
		for t in SPEED_UP_THRESHOLDS:
			if t > speed_index:
				next = t
				break
		set_speed_index(next)


func _physics_process(delta: float) -> void:
	life += delta
	if state == State.DEAD:
		return
	_update_speed_up(delta)
	_update_bleed(delta)
	match state:
		State.RISING:
			_timer -= delta
			if _timer <= 0.0:
				state = _after_rise
				_shape.position.y = 0.35 if crawler else 0.9
				_play(move_anim, 0.3)
		State.TO_WINDOW:
			var d := global_position.distance_to(window.outside)
			# progress watchdog: a zombie that stops getting closer is put at the window
			# (out of the player's sight; after 20 s anyway)
			if d < _best_dist - 0.2:
				_best_dist = d
				_stall = 0.0
			else:
				_stall += delta
			if _dropping:
				pass
			elif d < 0.7 or (_agent.is_navigation_finished() and d < 2.5):
				global_position = window.outside
				_start_tearing()
			elif (_agent.is_navigation_finished() or _stall > 2.0) and _try_drop():
				pass  # jumping down from a roof / ledge towards a lower window
			elif _stall > 20.0 or ((_stall > 6.0 or (_agent.is_navigation_finished() and _stall > 0.5)) and not _seen()):
				# the navmesh does not reach the window (or the zombie is stuck): put it
				# there, at once when the player cannot see the jump
				global_position = window.outside
				_start_tearing()
			else:
				_move_along_path(delta)
		State.TEARING:
			_face(window.inside)
			_timer -= delta
			if window.boards <= 0:
				_start_climb()
			elif _timer <= 0.0:
				# one board per swipe, like the original
				_anim.stop()
				_anim.play(TEAR, 0.1)
				window.tear_board()
				_timer = _anim.get_animation(TEAR).length + 0.15
		State.CLIMBING:
			pass  # driven by tween
		State.CHASE:
			if is_instance_valid(lure):
				_chase_lure(delta)
				return
			if target.dead:
				_play(IDLE)
				return
			var d := global_position.distance_to(target.global_position)
			if d < ATTACK_RANGE:
				state = State.ATTACK
				_timer = 1.0
				_hit_done = false
				_play(CRAWL_ATTACK if crawler else ATTACKS.pick_random(), 0.1)
				Sfx.instance.play_at("zombie_attack", global_position + Vector3.UP * 1.5)
			else:
				if ANTIFLOCK and _update_antiflock(delta, d):
					_repath = 0.0
				_repath -= delta
				if _repath <= 0.0:
					_agent.target_position = _chase_goal(d)
					_repath = 0.4
				_move_along_path(delta)
		State.ATTACK:
			_face(target.global_position)
			_timer -= delta
			if not _hit_done and _timer < 0.5:
				_hit_done = true
				if global_position.distance_to(target.global_position) < ATTACK_RANGE + 0.4:
					target.take_hit(ATTACK_DAMAGE)
					VoxLines.hit_by_enemy()   # "been_hit" line (vox_lines.gd)
			if _timer <= 0.0:
				state = State.CHASE
				_play(move_anim)
		State.DEAD:
			pass


func _move_along_path(delta: float) -> void:
	_play(move_anim)
	if _unsticking:
		return
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	var mv := Vector3.ZERO
	if dir.length() > 0.05:
		# the walking direction turns at most _turn_move per second; a sharp turn slows it
		var want := atan2(dir.x, dir.z)
		_heading = rotate_toward(_heading, want, _turn_move * delta)
		var off := absf(angle_difference(_heading, want))
		mv = Vector3(sin(_heading), 0.0, cos(_heading)) * speed * clampf(cos(off), 0.25, 1.0)
		_turn_body(delta)
	velocity.x = mv.x
	velocity.z = mv.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 12.0 * delta
	if is_on_floor():
		Stairs.step_up(self, delta)
	move_and_slide()
	_check_progress(delta, next)


# Jumping down: spawns on roofs and ledges (Shi No Numa huts, Verrückt balconies)
# whose window is below and not linked by the navmesh. The original has four drop
# animations, body + root-motion pairs for drops of 1.82 / 2.52 / 3.61 / 4.85 m.
const DROPS := [[1.82, "31de2da0"], [2.52, "31de2d9f"], [3.61, "31de2da1"], [4.85, "31de2da2"]]
var _dropping := false


func _try_drop() -> bool:
	var to := window.outside - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if to.y > -1.0 or flat.length() < 0.3:
		return false
	var dir := flat.normalized()
	var space := get_world_3d().direct_space_state
	var landing := Vector3.INF
	var chest := global_position + Vector3.UP * 1.0
	for ahead in [0.7, 1.1, 1.6, 2.2]:
		# nothing in the way at chest height, then a floor at least 1 m below
		var wall := PhysicsRayQueryParameters3D.create(chest, chest + dir * (ahead + 0.3), 1)
		if not space.intersect_ray(wall).is_empty():
			break
		var p: Vector3 = global_position + dir * ahead
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 7.0, 1))
		if not hit.is_empty() and global_position.y - (hit["position"] as Vector3).y >= 1.0:
			landing = hit["position"]
			break
	if landing == Vector3.INF:
		return false
	var drop := global_position.y - landing.y
	var anim: String = DROPS[0][1]
	for dd in DROPS:
		if absf(dd[0] - drop) < absf(_drop_h(anim) - drop):
			anim = dd[1]
	_dropping = true
	_end_unstick()
	collision_mask = 0
	_face(landing)
	rotation.y = atan2(dir.x, dir.z)
	_heading = rotation.y
	_anim.get_animation(anim).loop_mode = Animation.LOOP_NONE
	_anim.play(anim, 0.15)
	var t: float = _anim.get_animation(anim).length
	var edge := Vector3(landing.x, global_position.y, landing.z).lerp(global_position, 0.35)
	var tw := create_tween()
	tw.tween_property(self, "global_position", edge, t * 0.35)
	tw.tween_property(self, "global_position", landing, t * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(t * 0.15)
	tw.finished.connect(func():
		_dropping = false
		if state == State.TO_WINDOW:
			collision_mask = 1 | 4 | Level.NAV_FLOOR_LAYER
			_best_dist = INF
			_stall = 0.0
			_agent.target_position = window.outside
			_play(move_anim))
	return true


# True when the player's camera has a clear view of this zombie.
func _seen() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var chest := global_position + Vector3.UP * 1.2
	if not cam.is_position_in_frustum(chest) or cam.global_position.distance_to(chest) > 40.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, chest, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _drop_h(anim: String) -> float:
	for dd in DROPS:
		if dd[1] == anim:
			return dd[0]
	return 0.0


# Snag watchdog: the navmesh is baked for a thinner, shorter agent than the body
# capsule and steep stairs are not always climbable by Stairs.step_up, so a zombie
# can stall against a stair stringer, a door frame or a high step. If it has not
# moved for UNSTICK_TIME while it should, it is carried to the next path point
# (collision off, at walking pace) and carries on from there.
const UNSTICK_TIME := 1.5
const UNSTICK_MIN_MOVE := 0.2
const UNSTICK_MAX_HOP := 4.0
var _unsticking := false
var _unstick_tw: Tween
var _prog_pos := Vector3.INF
var _prog_t := 0.0
var unstuck_count := 0
var _last_unstick := -INF


func _check_progress(delta: float, next: Vector3) -> void:
	_prog_t += delta
	if _prog_pos == Vector3.INF:
		_prog_pos = global_position
	# right after a hop (a flight of high steps) the next stall is handled sooner
	if _prog_t < (0.5 if life - _last_unstick < 3.0 else UNSTICK_TIME):
		return
	var moved := global_position.distance_to(_prog_pos)
	_prog_t = 0.0
	_prog_pos = global_position
	if moved >= UNSTICK_MIN_MOVE or _agent.is_navigation_finished():
		return
	var hop := global_position.distance_to(next)
	if hop < 0.3:
		return
	if hop > UNSTICK_MAX_HOP:
		# far waypoint (long stair flight): go part of the way, to a navmesh point
		next = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map,
			global_position + (next - global_position).normalized() * UNSTICK_MAX_HOP * 0.6)
		hop = global_position.distance_to(next)
		if hop < 0.3:
			return
	if state == State.CHASE and global_position.distance_to(target.global_position) < 2.5:
		return  # crowding around the player, not a snag
	for z in get_tree().get_nodes_in_group("zombies"):
		if z != self and z is Zombie and z.state != State.DEAD and (z as Node3D).global_position.distance_to(next) < 0.6:
			return  # the way is blocked by another zombie: wait
	unstuck_count += 1
	_unsticking = true
	collision_mask = 0
	_face(next)
	_unstick_tw = create_tween()
	_unstick_tw.tween_property(self, "global_position", next + Vector3.UP * 0.05, maxf(0.25, hop / maxf(speed, 0.8)))
	_unstick_tw.finished.connect(_end_unstick)


func _end_unstick() -> void:
	if _unstick_tw and _unstick_tw.is_valid():
		_unstick_tw.kill()
	if _unsticking:
		_unsticking = false
		_last_unstick = life
		if state in [State.TO_WINDOW, State.CHASE, State.ATTACK, State.TEARING]:
			collision_mask = 1 | 4 | Level.NAV_FLOOR_LAYER


func _face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.01:
		# model faces +Z
		var dt := get_physics_process_delta_time()
		_heading = rotate_toward(_heading, atan2(d.x, d.z), _turn_move * dt)
		_turn_body(dt)


# The drawn body follows the walking direction at ZombieTurnSpeedRangeRender.
func _turn_body(dt: float) -> void:
	rotation.y = rotate_toward(rotation.y, _heading, _turn_render * dt)
	var lag := angle_difference(_heading, rotation.y)
	if absf(lag) > MAX_BODY_LAG:
		rotation.y = _heading + signf(lag) * MAX_BODY_LAG


# Where a chasing zombie paths to: the player, his predicted position, or the antiflock
# detour point.
func _chase_goal(dist: float) -> Vector3:
	var tp := target.global_position
	if antiflock_on:
		return _af_goal
	if not PREDICTION or dist <= PREDICTION_PROXIMITY:
		return tp
	var v := target.velocity
	v.y = 0.0
	if v.length() < 0.5:
		return tp
	var ahead := tp + v.normalized() * PREDICTION_DIST
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(tp + Vector3.UP * 0.5, ahead + Vector3.UP * 0.5, 1))
	if not hit.is_empty():
		ahead = (hit["position"] as Vector3) - v.normalized() * 0.3
		ahead.y = tp.y
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, ahead)


# Antiflock state; true when it changed (path again).
func _update_antiflock(delta: float, dist: float) -> bool:
	if crawler:
		return false
	if _af_timer < 0.0:
		_af_timer = randf() * AF_INTERVAL   # spread the checks
	_af_timer -= delta
	if antiflock_on:
		var off := _af_goal - global_position
		off.y = 0.0
		if _af_timer <= 0.0 or off.length() < AF_TOLERANCE or dist < AF_MIN:
			antiflock_on = false
			_af_timer = AF_INTERVAL
			return true
		return false
	if _af_timer > 0.0:
		return false
	_af_timer = AF_INTERVAL
	var g := _antiflock_point(dist)
	if g == Vector3.INF:
		return false
	antiflock_on = true
	antiflock_count += 1
	_af_goal = g
	_af_timer = AF_TIME
	return true


func _antiflock_point(dist: float) -> Vector3:
	if dist < AF_MIN or dist > AF_MAX:
		return Vector3.INF
	var count := 0
	var away := Vector3.ZERO
	var push := 0.0
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z == self or z.target != target or not z.state in [State.CHASE, State.ATTACK]:
			continue
		var off := global_position - z.global_position
		var dd := off.length()
		if dd > AF_RADIUS or dd < 0.01:
			continue
		count += 1
		away += off
		push += 68719476736.0 / ((dd * 400.0) * (dd * 400.0))   # 2^36 / d^2
	if count < AF_CROWD or push < AF_PUSH:
		return Vector3.INF
	away.y = 0.0
	var to_p := target.global_position - global_position
	to_p.y = 0.0
	if away.length() < 0.01 or to_p.length() < 0.01:
		return Vector3.INF
	away = away.normalized()
	var dirp := to_p.normalized()
	var ang := dirp.angle_to(away)
	if ang < AF_ANGLE_TOL:
		return Vector3.INF
	var dir := away
	if ang > AF_HEADING:
		# the line to the player turned by AngleHeading towards the side away from the crowd
		var a := dirp.rotated(Vector3.UP, AF_HEADING)
		var b := dirp.rotated(Vector3.UP, -AF_HEADING)
		dir = a if a.dot(away) >= b.dot(away) else b
	var from := global_position + Vector3.UP * 0.9
	var goal := global_position + dir * AF_DIST
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, goal + Vector3.UP * 0.9, 1))
	if not hit.is_empty():
		goal = (hit["position"] as Vector3) - dir * 0.4
		goal.y = global_position.y
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, goal)


func _start_tearing() -> void:
	_end_unstick()
	if reached_window < 0.0:
		reached_window = life
	if window.occupied_by != null and window.occupied_by != self and is_instance_valid(window.occupied_by):
		_play(IDLE)
		return  # wait for the zombie ahead
	window.occupied_by = self
	state = State.TEARING
	_timer = 1.0
	_play(TEAR)


var _climb_tw: Tween


func _start_climb() -> void:
	state = State.CLIMBING
	_play(CLIMB, 0.1)
	collision_mask = 0
	_climb_tw = create_tween()
	_climb_tw.tween_property(self, "global_position", window.inside, _anim.get_animation(CLIMB).length)
	_climb_tw.finished.connect(func():
		# killed while climbing in: this used to set CHASE again, so the corpse got up
		# and attacked (unshootable, already counted dead) until it was freed
		if state == State.DEAD:
			return
		collision_mask = 1 | 4 | Level.NAV_FLOOR_LAYER
		window.occupied_by = null
		state = State.CHASE
		_play(move_anim))


# hit_pos (world space, optional): where the shot landed; with it (or a head hit) the
# hit has a location and can take a limb off (CDismembermentSpec, below). Without it
# (explosions, fire, traps, knife) no limb is hurt.
# `headshot` from the caller means the shot hit the head volume; the kill counts as a
# headshot (points, stats) only when that hit took the head off, as in the original
# (damage info byte 0x1e, set by the dismemberment handler kiwi 0x14fe94).
func take_damage(amount: float, headshot: bool, by: Player, knife := false, hit_pos := Vector3.INF) -> void:
	if state == State.DEAD:
		return
	var g := get_parent() as Game
	var insta := g != null and g.insta_kill
	if insta:
		amount = health
	health -= amount
	if by:
		by.add_points(10 * (g.points_multiplier if g else 1))
	var loc := -1
	if headshot:
		loc = Weapons.LOC_HEAD
	elif hit_pos != Vector3.INF:
		loc = Weapons.location(self, hit_pos, false)
	var popped := false
	if not knife and loc >= 0 and not _pistol(by):
		popped = _damage_limb(loc, amount)
	if insta and by != null:
		lose_head()   # Insta-Kill (damage info byte 0x20) forces the head off
	if health <= 0.0:
		_die(popped, knife)
	elif popped and _bleed_left <= 0.0:
		_bleed_left = BLEED_TIME   # headless and still standing: bleeds out
		_bleed_t = BLEED_PERIOD
		_bleed_by = by
	if popped and by and by.has_method("head_popped"):
		by.head_popped()


# ------------------------------------------------------------------ dismemberment
# CDismembermentSpec of the zombie (zombiesbase c9872545, serialiser kiwi 0x196510):
# per entry u32 hit volume, u32 damage type mask, u32 CPeriodicDamage, i32 health
# (fraction of the zombie's max health, 4096 = 1), u8 disable the volume, u32 block switch
# name ("<name>_on" / "<name>_off"), u32 effect entity:
#   0 head      0xc1  a8c8c6e1  3276 (0.8)    1  head      3e08391d
#   1 left arm  0xc1  -          106 (0.026)  1  left_arm  34a75f56
#   2 right arm 0xc1  -          106 (0.026)  1  right_arm 888d60e9
#   3 chest     0xc1  -          106 (0.026)  0  body      -
# A limb is a pool of health of its own (kiwi 0x150210: fraction x max health); bullet
# damage on its hit volume drains it (kiwi 0x1505a0) and at 0 the limb comes off: the
# "_on" blocks hide, the "_off" ones show. Mask 0xc1 = damage types 0 (guns), 6, 7: not
# the starting pistol (type 1, colt45 only), explosives (2), the knife (3) or fire (5).
# The chest only opens up (body_on -> body_off), it never flies off. No legs here: those
# go with explosive damage (explosion.gd).
const LIMB_HEALTH := {0: 3276.0 / 4096.0, 1: 106.0 / 4096.0, 2: 106.0 / 4096.0, 3: 106.0 / 4096.0}
# CPeriodicDamage a8c8c6e1 (head): period 1000 ms, type 5, 100 damage, for 10000 ms
const BLEED_DAMAGE := 100.0
const BLEED_PERIOD := 1.0
const BLEED_TIME := 10.0
var _limbs := {}
var _bleed_left := 0.0
var _bleed_t := 0.0
var _bleed_by: Player


func _init_limbs() -> void:
	for k in LIMB_HEALTH:
		_limbs[k] = LIMB_HEALTH[k] * max_health


func _pistol(by: Player) -> bool:
	return by != null and String(by.weapon().get("name", "")) == "colt45"


# Drains limb `loc`; true when this hit took the head off.
func _damage_limb(loc: int, amount: float) -> bool:
	if _limbs.is_empty():
		_init_limbs()
	if not _limbs.has(loc) or float(_limbs[loc]) <= 0.0:
		return false
	_limbs[loc] = maxf(float(_limbs[loc]) - amount, 0.0)
	if _limbs[loc] > 0.0:
		return false
	match loc:
		Weapons.LOC_HEAD:
			var was := _block_visible("neck")
			lose_head()
			return was
		Weapons.LOC_LEFT_ARM:
			lose_arm("left")
		Weapons.LOC_RIGHT_ARM:
			lose_arm("right")
		Weapons.LOC_CHEST:
			open_chest()
	return false


func _update_bleed(delta: float) -> void:
	if _bleed_left <= 0.0:
		return
	_bleed_left -= delta
	_bleed_t -= delta
	if _bleed_t <= 0.0:
		_bleed_t += BLEED_PERIOD
		take_damage(BLEED_DAMAGE, false, _bleed_by if is_instance_valid(_bleed_by) else null)


# Which arm (if any) a hit at world position p lands on: the arm whose posed bones
# (shoulder -> elbow -> wrist) pass closest to it. Shots hit the 0.3 m capsule, not
# the mesh, so the test is done in the zombie's horizontal frame: the side of the
# hit (local x, model faces +Z, its left arm is +X) and the height band of that arm.
const LEG_HIT_HEIGHT := 0.95
const ARM_BONES := {"left": [13, 14, 15], "right": [23, 24, 25]}
func arm_at(p: Vector3) -> String:
	var lp := to_local(p)
	var side := "left" if lp.x > 0.0 else "right"
	if absf(lp.x) < 0.12 and lp.z < 0.0:
		return ""   # middle of the back: torso
	var lo := 1.0
	var hi := 1.5
	var skel: Skeleton3D = _skeleton()
	if skel:
		lo = INF
		hi = -INF
		for b in ARM_BONES[side]:
			if b < skel.get_bone_count():
				var y: float = to_local(skel.global_transform * skel.get_bone_global_pose(b).origin).y
				lo = minf(lo, y)
				hi = maxf(hi, y)
		lo -= 0.12
		hi += 0.06
	if lp.y < lo or lp.y > hi:
		return ""
	# front shots: the arms reach forward, anything off the centre line is an arm;
	# side shots: the arm covers the flank
	if absf(lp.x) < 0.1:
		return ""
	return side


var _skel_cache: Skeleton3D
func _skeleton() -> Skeleton3D:
	if _skel_cache == null and _model:
		var s := _model.find_children("*", "Skeleton3D")
		if s.size() > 0:
			_skel_cache = s[0]
	return _skel_cache


# ------------------------------------------------------------------ gibs
# Blocks of the zombie model (named in tools/export_characters.py, one mesh per block and
# material, "neck_m1" = block "neck" with material 1), switched like the original's
# CModelBlockSwitcherSpec (see VARIANTS): head_on = neck, 25d19111, the head (3f7355a5 or
# headb) and the helmet / hat; head_off = 94c24809 (neck stump); left/right_arm_on = the
# whole arm (leftarm / sleevel, rightarm / sleever), left/right_arm_off = the shoulder
# stumps e1f1c9f3 / 75a47286; legs_on = legs, legs_off = acf2ab46 (waist stump);
# body_on = body (the tunic front), body_off = 980daf40 (the open chest).
var _arms_lost := {}


func _part(n: String) -> MeshInstance3D:
	return _model.find_child(n, true, false) as MeshInstance3D


func _arm_block(side: String) -> String:
	for b in (["leftarm", "sleevel"] if side == "left" else ["rightarm", "sleever"]):
		if _block_visible(b):
			return b
	return ""


func _first_mesh(block: String) -> MeshInstance3D:
	var l: Array = _blocks.get(block, [])
	return l[0] if not l.is_empty() else null


func lose_head() -> void:
	if not _block_visible("neck"):
		return
	var head := _first_mesh(head_block)
	for b in ["neck", "25d19111", head_block, "01d84724", "a3eaf623"]:
		_show_block(b, false)
	_show_block("94c24809", true)
	_spawn_gib(head, head)


func lose_arm(side: String) -> void:
	if _arms_lost.has(side):
		return
	_arms_lost[side] = true
	var b := _arm_block(side)
	var first := _first_mesh(b) if b != "" else null
	_show_block(b, false)
	_show_block("e1f1c9f3" if side == "left" else "75a47286", true)
	if first:
		_spawn_gib(first, first)


# body_off: the tunic front goes, the open chest shows (no gib, no effect)
func open_chest() -> void:
	if not _block_visible("body"):
		return
	_show_block("body", false)
	_show_block("980daf40", true)


# A physics copy of a part flying off. The mesh is static (unskinned) so it is
# placed where the attached part currently is (its skinned bounds).
func _spawn_gib(src: MeshInstance3D, where: MeshInstance3D) -> void:
	if src == null:
		return
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	for i in src.get_surface_override_material_count():
		mi.set_surface_override_material(i, src.get_surface_override_material(i))   # its cel
	var bounds := src.mesh.get_aabb()
	mi.position = -bounds.get_center()
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = clampf(bounds.size.length() * 0.25, 0.06, 0.18)
	cs.shape = sph
	body.add_child(cs)
	get_parent().add_child(body)
	var at := global_position + Vector3.UP * 1.6
	var skel: Skeleton3D = _model.find_children("*", "Skeleton3D")[0] if _model.find_children("*", "Skeleton3D").size() > 0 else null
	if where != null and skel != null:
		# centre of the attached part, via the nearest bone to its bind-pose centre
		at = where.global_transform * where.mesh.get_aabb().get_center()
		var best := INF
		var c := where.mesh.get_aabb().get_center()
		for b in skel.get_bone_count():
			var rest := skel.get_bone_global_rest(b).origin
			if rest.distance_to(c) < best:
				best = rest.distance_to(c)
				at = skel.global_transform * skel.get_bone_global_pose(b) * (skel.get_bone_global_rest(b).affine_inverse() * c)
	body.global_position = at
	body.global_rotation = global_rotation
	body.apply_central_impulse(Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1)) * body.mass)
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	get_tree().create_timer(8.0, false).timeout.connect(body.queue_free)


# Health of a zombie that has just lost its legs, from the executable's legless handler
# (console vars CrawlingZombieMaxHealth "240" and CrawlingZombieProportionalMaxHealth
# "0.4"): on maps that call Game.SetUsingDifficultyTweaks(true) (only Der Riese) it
# keeps at most 0.4 x its full health, elsewhere at most 240. It never gains health.
const CRAWLER_MAX_HEALTH := 240.0
const CRAWLER_PROPORTIONAL := 0.4
const DIFFICULTY_TWEAKS_LEVELS := ["derriese"]


static func crawler_health(hp: float, full: float, level_name: String) -> float:
	var cap := full * CRAWLER_PROPORTIONAL if level_name in DIFFICULTY_TWEAKS_LEVELS else CRAWLER_MAX_HEALTH
	return minf(hp, cap)


func become_crawler() -> void:
	if crawler or state == State.DEAD:
		return
	crawler = true
	var g := get_parent() as Game
	if max_health < 1e5:   # tests use huge health on purpose
		health = crawler_health(health, max_health, g.level_name if g else "")
	var legs := _first_mesh("legs")
	if _block_visible("legs"):
		_show_block("legs", false)   # legs_on off, legs_off (waist stump) on: kiwi 0x139be8
		_show_block("acf2ab46", true)
		_spawn_gib(legs, legs)
	move_anim = CRAWL
	speed = CRAWL_SPEED
	_anim.get_animation(CRAWL).loop_mode = Animation.LOOP_LINEAR
	_anim.get_animation(CRAWL_ATTACK).loop_mode = Animation.LOOP_NONE
	(_shape.shape as CapsuleShape3D).height = 0.7
	_shape.position.y = 0.35
	if state == State.CHASE:
		_play(CRAWL, 0.3)


func nuke_kill() -> void:
	if state == State.DEAD:
		return
	health = 0.0
	if randf() < 0.5:
		lose_head()
	_die(false, false)


func _die(headshot: bool, knife := false) -> void:
	if state == State.DEAD:
		return   # killed (and counted) once only
	_end_unstick()
	# the climb through the window stops where it is (its end would set CHASE)
	if _climb_tw and _climb_tw.is_valid():
		_climb_tw.kill()
	Sfx.instance.play_at("zombie_death", global_position + Vector3.UP * 1.5)
	if headshot:
		lose_head()
	state = State.DEAD
	if window.occupied_by == self:
		window.occupied_by = null
	collision_layer = 0
	collision_mask = 1
	var death: String = CRAWL_DEATH if crawler else DEATHS.pick_random()
	if electric_death and not crawler:
		var ld: String = LIGHTNING_DEATHS.pick_random()
		if _anim.has_animation(ld):
			death = ld
	_anim.get_animation(death).loop_mode = Animation.LOOP_NONE  # stay down
	_anim.play(death, 0.1)
	killed.emit(self, headshot, knife)
	get_tree().create_timer(6.0).timeout.connect(queue_free)


# Walk to the Monkey Bomb and stand at it (the player is ignored meanwhile).
func _chase_lure(delta: float) -> void:
	var p := lure.global_position
	if global_position.distance_to(Vector3(p.x, global_position.y, p.z)) < 1.0:
		velocity = Vector3.ZERO
		_face(p)
		_play(IDLE)
		return
	_repath -= delta
	if _repath <= 0.0:
		_agent.target_position = p
		_repath = 0.4
	_move_along_path(delta)
