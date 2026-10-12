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

static var _dyn_cache := {}   # level -> instantiated dynamics.glb (static models by hash)


func setup(level_: Level, entity_: String, kind_: String) -> void:
	level = level_
	entity = entity_
	kind = kind_
	var e: Dictionary = level.entities[entity]
	cost = int(e.get("params", {}).get("cost", Perks.INFO.get(kind, {}).get("cost", 0)))
	var root := level.entity_transform(entity)
	global_transform = root
	var model := _load_model(e)
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
	return _centre.distance_to(p) < USE_RANGE


func prompt(player: Player) -> String:
	if kind == "power":
		return "" if level.power_on else "Premi E per accendere la corrente"
	if player.has_perk(kind):
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
	if player.has_perk(kind) or not level.power_on:
		return
	if player.points < cost:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-cost)
	Sfx.instance.play("buy_success")
	# the BuyPerk* entity's use sound is the perk's jingle (perkjingle<perk>)
	Sfx.instance.play_at("jingle_" + kind, _centre + Vector3.UP, -2.0)
	player.give_perk(kind)
	drink(player)


# First-person drink (viewmodel.gd); no firing until the weapon is back.
static func drink(player: Player) -> void:
	var vm = player.get("_viewmodel")
	if vm is Viewmodel:
		var t: float = vm.drink()
		player.set("_cooldown", maxf(float(player.get("_cooldown")), t + 0.2))
