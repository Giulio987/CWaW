# Perk-a-Cola machine (CActionBuyPerkSpec entity) or the power switch
# (GeneratorSwitch, kind "power"). On maps with a generator (Der Riese,
# Verrückt) the machines only sell once the power is on, as in the Lua scripts
# (TurnOnGenerator sends "genTurnOn" to the four BuyPerk* machines).
class_name PerkMachine
extends Node3D

const USE_RANGE := 2.4   # metres from the machine centre

var kind := ""        # jugga, speed, dbtap, revive or power
var cost := 0
var entity := ""
var level: Level
var _anim: AnimationPlayer
var _anim_on := ""      # animation played when the power comes on
var _centre := Vector3.ZERO
var _model: Node3D
var _body: StaticBody3D

static var _dyn_cache := {}   # level -> instantiated dynamics.glb (static models by hash)


func setup(level_: Level, entity_: String, kind_: String) -> void:
	level = level_
	entity = entity_
	kind = kind_
	var e: Dictionary = level.entities[entity]
	cost = int(e.get("params", {}).get("cost", Perks.INFO.get(kind, {}).get("cost", 0)))
	# quarter turns in the transform flags (Level.flag_transform), as for the debris
	var root := Level.flag_transform(e["transform"])
	global_transform = root
	var model := _load_model(e)
	_model = model
	if model:
		add_child(model)
		if not e["children"].is_empty():
			var p: Array = e["children"][-1]["pos"]
			model.position = Vector3(p[0], p[1], p[2]) * Level.UNITS
		var aps := model.find_children("*", "AnimationPlayer")
		if aps.size() > 0:
			_anim = aps[0]
			_pick_animations()
	# solid volume from the entity collider; it is in the entity frame (the same box
	# comes out on machines turned differently), so it turns with the entity
	var body := StaticBody3D.new()
	_body = body
	add_child(body)
	var lo_all := Vector3(INF, INF, INF)
	var hi_all := -lo_all
	for c in e.get("colliders", []):
		var lo := Vector3(c["min"][0], c["min"][1], c["min"][2]) * Level.UNITS
		var hi := Vector3(c["max"][0], c["max"][1], c["max"][2]) * Level.UNITS
		lo_all = lo_all.min(lo)
		hi_all = hi_all.max(hi)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (hi - lo).max(Vector3(0.2, 0.2, 0.2))
		shape.shape = box
		shape.position = (lo + hi) / 2
		body.add_child(shape)
	_centre = root * ((lo_all + hi_all) / 2) if lo_all.x < INF else root.origin
	level.power_changed.connect(_on_power)
	_on_power(level.power_on, true)


# frees the dynamics.glb copies kept while the machines are built
static func release_cache() -> void:
	for k in _dyn_cache:
		if _dyn_cache[k]:
			(_dyn_cache[k] as Node).free()
	_dyn_cache.clear()


func _load_model(e: Dictionary) -> Node3D:
	for h in e["models"]:
		var path := "res://assets/characters/levels/%s/dynamics/%s.glb" % [level.level_name, h]
		if ResourceLoader.exists(path):
			return (load(path) as PackedScene).instantiate()
	# static models (e.g. Shi No Numa machines have no rig) are in dynamics.glb by hash
	if not _dyn_cache.has(level.level_name):
		var dpath := "res://assets/models/levels/%s/dynamics.glb" % level.level_name
		_dyn_cache[level.level_name] = (load(dpath) as PackedScene).instantiate() if ResourceLoader.exists(dpath) else null
	var dyn: Node = _dyn_cache[level.level_name]
	if dyn:
		for h in e["models"]:
			var n := dyn.find_child(h, true, false) as Node3D
			if n:
				var copy := n.duplicate() as Node3D
				copy.transform = Transform3D.IDENTITY
				return copy
	return null


# The rigs have an "off" pose, a turning-on animation and an "on" loop/pose;
# the turning-on one is the longest, its first frame is the off pose.
func _pick_animations() -> void:
	var longest := 0.0
	for a in _anim.get_animation_list():
		var anim := _anim.get_animation(a)
		if anim.length > longest:
			longest = anim.length
			_anim_on = a
	if OS.get_cmdline_user_args().has("--perk-anims"):
		for a in _anim.get_animation_list():
			var anim := _anim.get_animation(a)
			var keys := 0
			for t in anim.get_track_count():
				keys = max(keys, anim.track_get_key_count(t))
			print("[perk] %s anim %s length %.2f keys %d" % [entity, a, anim.length, keys])


func _on_power(on: bool, instant := false) -> void:
	if on and kind != "power":
		_hum.call_deferred()
	if _anim == null or _anim_on == "":
		return
	_anim.play(_anim_on)
	if instant or not on:
		_anim.seek(_anim.get_animation(_anim_on).length if on else 0.0, true)
		_anim.pause()


# SoundPerkHum* emitters (perkhumloop), enabled with the power
var _hum_player: AudioStreamPlayer3D

func _hum() -> void:
	if _hum_player or Sfx.instance == null or not is_inside_tree():
		return
	if not level.power_on:
		return   # deferred from setup, before _build_perks turned the power off (Verrückt, Der Riese)
	if hut == Hut.HIDDEN or hut == Hut.HOVER:
		return   # Shi No Numa: SoundPerkHum<hut> starts at "perkMachineDropping"
	var s = Sfx.instance._stream("perk_hum")
	if not (s is AudioStreamWAV):
		return
	var loop := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(loop.get_length() * loop.mix_rate)
	_hum_player = AudioStreamPlayer3D.new()
	_hum_player.stream = loop
	_hum_player.volume_db = -10.0
	_hum_player.unit_size = 2.0
	_hum_player.max_distance = 12.0
	add_child(_hum_player)
	_hum_player.global_position = _centre + Vector3.UP
	_hum_player.play()


func usable_from(p: Vector3) -> bool:
	if hut != Hut.NONE and hut != Hut.READY:
		return false
	return _centre.distance_to(p) < USE_RANGE


func prompt(player: Player) -> String:
	if kind == "power":
		return "" if level.power_on else "Premi E per accendere la corrente"
	if player.has_perk(kind) or (hut != Hut.NONE and hut != Hut.READY):
		return ""
	if not level.power_on:
		return "Serve la corrente"
	return "Premi E per comprare %s [%d]" % [Perks.display(kind), cost]


func interact(player: Player) -> void:
	if kind == "power":
		if not level.power_on:
			Achievements.unlock("ver_yougotpowah")   # verruckt.lua GeneratorSwitch (Verrückt only)
			level.turn_on_power()
			Sfx.instance.play_at(Sfx.iw_hash("genswitch"), global_position + Vector3.UP)
		return
	if player.has_perk(kind) or not level.power_on or (hut != Hut.NONE and hut != Hut.READY):
		return
	if player.points < cost:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-cost)
	Sfx.instance.play("buy_success")
	# the BuyPerk* entity's use sound is the perk's jingle (perkjingle<perk>)
	Sfx.instance.play_at("jingle_" + kind, _centre + Vector3.UP, -2.0)
	player.give_perk(kind)
	drink(player, kind)


# First-person drink (viewmodel.gd); no firing until the weapon is back.
static func drink(player: Player, perk := "jugga") -> void:
	var vm = player.get("_viewmodel")
	if vm is Viewmodel:
		var t: float = vm.drink(perk)
		player.set("_cooldown", maxf(float(player.get("_cooldown")), t + 0.2))


# ------------------------------------------------------------------ Shi No Numa huts
# shinonuma.lua: every hut (PerkMachineLocations Fishing, Doctors, Storage, CommRoom) has
# one BuyPerk<perk><hut> entity per perk. Begin hides them all (RenderPerkMachine(0, hut))
# and pre-selects a different perk for each hut (SetPerkMachinePreSelected,
# GetTranslatedRandomPerkNum). Buying the hut's door (Trigger, bytecode 226-261 and 426-466)
# sends "startHover" to the four machines and shows a random one of the perks still
# available (PerkMachineNumberSelected = RandomNumber(1, PerkMachineCount + 1)). The
# machines' state machines (shi_dynamics CIsAnimStateMachine cdc21f4b & co.): hover
# f196d2a7 7066 ms (anim 2bd77b21), the DbTap one also sends "perkMachineStartCycling" and
# plays perk_random (1cf498d7, 7.9 s); the Lua Timeout "PerkMachineNextCycle<hut>" then
# shows the next available perk every PerkMachineCycleTimeout = 130 ms. Drop 17f00dc8
# 899 ms (anim 40ebee34) sends "perkMachineDropping" (Signal, bytecode 386-489): the cycle
# stops, the pre-selected machine stays (EnableRender), its hum starts, its perk leaves
# PerkMachineNamesAvaliable; the other three get "disable". Then idle: for sale.
enum Hut { NONE, HIDDEN, HOVER, DROP, READY }
const HUT_LINKS := {"Fishing": "Link_FshSw_FshHt_Trigger", "Doctors": "Link_DtrSw_DtrHt_Trigger",
	"Storage": "Link_StrHt_StrSw_Trigger", "CommRoom": "Link_CRSw_CRHt_Trigger"}
const HUT_CYCLE := 0.13    # Script.PerkMachineCycleTimeout
const HUT_HOVER := 7.066   # ASM hover state
const HUT_DROP := 0.899    # ASM drop state
# root keyframes of the one-bone anims (skeleton 4db7c78b, posScale 1/4; tools/anim.py):
# [s, height in units, quaternion y, z] in the entity frame
const HOVER_KEYS := [[0.0, 0, 0, 0], [0.033, 5, 0, 0.0304], [0.233, 4, 0, -0.0263], [0.4, 3, 0, 0.0166],
	[0.567, 1, 0, -0.0166], [0.733, 35, 0, -0.0263], [1.467, 61, 0, 0.0111], [2.033, 96, 0, -0.0083],
	[2.733, 126, 0, 0.0069], [3.333, 126, 0, -0.0069], [3.933, 119, 0.0014, 0.0042],
	[4.6, 111, 0.0028, -0.0083], [5.2, 105, 0.0014, 0.0055], [5.833, 103, 0, -0.0069],
	[6.433, 112, 0.0014, 0.0042], [7.067, 123, 0.0028, -0.0083]]
const DROP_KEYS := [[0.0, 114, 0.0028, -0.0055], [0.167, 5, 0.0042, 0.0304], [0.366, 4, 0.0028, -0.0263],
	[0.533, 3, 0.0028, 0.0166], [0.7, 1, 0.0028, -0.0097], [0.767, 0, 0.0028, 0], [0.866, 3, 0.0028, 0.0083],
	[0.9, 2, 0.0028, 0.0069]]

static var hut_pool: Array = []   # Script.PerkMachineNamesAvaliable (shared by the four huts)

var hut := Hut.NONE
var location := ""
var _variants := {}       # perk -> its machine model at this hut
var _hover_root: Node3D
var _door: Node
var _hut_t := 0.0
var _cycle_t := 0.0
var _selected := 0        # PerkMachineNumberSelected[hut] (1-based in hut_pool; -1 once dropped)


# entity names not recovered by tools/resolve_names.py stay as their hash
static func same_name(n: String, wanted: String) -> bool:
	return n.to_lower() == wanted.to_lower() or n == Sfx.iw_hash(wanted)


static func reset_hut_pool() -> void:
	hut_pool = ["revive", "speed", "dbtap", "jugga"]   # Script.PerkMachineNames order


# names: the BuyPerk<perk><hut> entities at this machine's place (this one sells its perk)
func setup_hut(names: Array) -> void:
	for loc in HUT_LINKS:
		if same_name(entity, "BuyPerk%s%s" % [Perks.SHINO_NAMES.get(kind, ""), loc]):
			location = loc
	_hover_root = Node3D.new()
	_hover_root.name = "Hover"
	add_child(_hover_root)
	if _model:
		_model.reparent(_hover_root, false)
		_variants[kind] = _model
	for n in names:
		var k := Perks.kind_of(level.entities[n])
		if k == "" or _variants.has(k):
			continue
		var e: Dictionary = level.entities[n]
		var m := _load_model(e)
		if m == null:
			continue
		_hover_root.add_child(m)
		if not e["children"].is_empty():
			var p: Array = e["children"][-1]["pos"]
			m.position = Vector3(p[0], p[1], p[2]) * Level.UNITS
		_variants[k] = m
	for d in level.debris:
		if location != "" and same_name(d.entity, HUT_LINKS[location]):
			_door = d
			d.opened.connect(func(_d): start_hover())
	hut = Hut.HIDDEN
	visible = false
	if _body:
		_body.process_mode = Node.PROCESS_MODE_DISABLED
	if _door == null:
		_land(true)


# "startHover": the machines rise and cycle the perks still available
func start_hover() -> void:
	if hut != Hut.HIDDEN:
		return
	hut = Hut.HOVER
	_hut_t = 0.0
	_cycle_t = HUT_CYCLE
	visible = true
	_selected = randi_range(1, maxi(hut_pool.size(), 1))
	_render(hut_pool[_selected - 1] if _selected <= hut_pool.size() else kind)
	Sfx.instance.play_at("perk_random", _centre + Vector3.UP, -2.0)
	_pose(HOVER_KEYS, 0.0)


func _render(k: String) -> void:
	for v in _variants:
		(_variants[v] as Node3D).visible = v == k


# "perkMachineDropping": the pre-selected perk lands; instant when a resumed save had the
# door bought already
func _land(instant := false) -> void:
	_selected = -1
	_render(kind)
	hut_pool.erase(kind)
	visible = true
	if instant:
		_finish()
	else:
		hut = Hut.DROP
		_hut_t = 0.0
	_hum()


func _finish() -> void:
	hut = Hut.READY
	_hover_root.transform = Transform3D.IDENTITY
	if _body:
		_body.process_mode = Node.PROCESS_MODE_INHERIT


func _pose(keys: Array, t: float) -> void:
	var i := 0
	while i < keys.size() - 2 and t >= float(keys[i + 1][0]):
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[mini(i + 1, keys.size() - 1)]
	var f := clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
	var qa := Quaternion(0.0, float(a[2]), float(a[3]), sqrt(1.0 - float(a[2]) ** 2 - float(a[3]) ** 2))
	var qb := Quaternion(0.0, float(b[2]), float(b[3]), sqrt(1.0 - float(b[2]) ** 2 - float(b[3]) ** 2))
	_hover_root.transform = Transform3D(Basis(qa.slerp(qb, f)),
		Vector3(0.0, lerpf(float(a[1]), float(b[1]), f) * Level.UNITS, 0.0))


func _process(delta: float) -> void:
	match hut:
		Hut.HIDDEN:
			# a resumed save frees the bought doors without "opened": land at once
			if _door != null and not level.debris.has(_door):
				_land(true)
		Hut.HOVER:
			_hut_t += delta
			_cycle_t -= delta
			if _cycle_t <= 0.0 and not hut_pool.is_empty():
				_cycle_t += HUT_CYCLE
				_selected = _selected % hut_pool.size() + 1
				_render(hut_pool[_selected - 1])
			if _hut_t >= HUT_HOVER:
				_land()
			else:
				_pose(HOVER_KEYS, _hut_t)
		Hut.DROP:
			_hut_t += delta
			if _hut_t >= HUT_DROP:
				_finish()
			else:
				_pose(DROP_KEYS, _hut_t)
