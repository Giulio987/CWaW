# Mystery box (CMysteryBoxSpec entity). The box logic lived in the engine, not in
# Lua, so it follows World at War: 950 points, the lid opens, weapons cycle above
# the box for ~5 s, the result floats for 12 s and sinks back if not taken.
# Teddy bear (World at War; box state machine 350fb630 + WarpMysteryBox in the
# level Lua): on maps with several MysteryBox locations, after a few uses the box
# can give the teddy instead: it laughs, the 950 points are refunded, the box rises
# and vanishes (teddypoof), then falls at another location (not one of the last two).
class_name MysteryBox
extends Node3D

const COST := 950
# Nacht's box (ecee0a62); other maps use 350fb630 with different animation names,
# so open/close/poses are recognised from their key counts (see _pick_animations)
var ANIM_OPEN := "d8283c46"
var ANIM_CLOSE := "dc54990a"
var ANIM_IDLE_OPEN := "ef143ac4"
var ANIM_IDLE_CLOSED := "b4bcad2c"
const CYCLE_TIME := 5.0     # box_music is loud for ~5.5 s
const TEDDY_MODEL := "6e3f6288"   # second model of the CMysteryBoxSpec entities (ingame dynamics)
const TEDDY_YAW := PI / 2           # faces the front of the box
# Teddy rules from console.bin, per map (CMysteryBoxSpec reads
# MysteryUsedCountTeddy%s, MysteryResetUsedCountTeddy%s, MysteryTeddyBearPercent%s
# at kiwi 0xb9204-0xb92c8). Every purchase counts one use (kiwi 0xb8d4c, a counter of
# the game, not of the location); when the box opens with more than UsedCount uses,
# the bear comes with Percent % (kiwi 0xb8034-0xb8078: Random(100) < Percent) and the
# counter drops to UsedCount - ResetUsedCount.
#   map: [UsedCount, ResetUsedCount, Percent]
const TEDDY_RULES := {"nacht": [10, 10, 10], "verruckt": [10, 3, 10], "shinonuma": [3, 2, 20],
	"derriese": [3, 2, 20]}
const TEDDY_DEFAULT := [10, 5, 10]   # engine defaults when a variable is missing
const TEDDY_LAUGH := 2.0     # teddy floats and laughs
const RISE_TIME := 4.5       # box rises and shakes (box_flyaway)
const GONE_TIME := 2.0
const FALL_TIME := 1.6       # falls at the new location (box_fall, then teddyland)
const MEMORY := 2            # Script.Level.MysteryBoxMemorySize
const OFFER_TIME := 12.0
# What the box gives, per map: console.bin MysteryWeapons<map> (read by CMysteryBoxSpec,
# kiwi 0xb82c0 "MysteryWeapons%s"), in the original order. Items: "betty" (BettyBelt),
# "molotov" (MolotovBelt: MaxMolotovs 4 via CActionBuyMolotov), "monkeybomb" (MonkeyBelt).
# MysteryUniqueWeaponsDerRiese = "flamethrower,wunderwaffe": one at a time among the
# co-op players; in solo _pick already skips the guns the buyer holds.
const MYSTERY_WEAPONS := {
	"nacht": ["bar", "browning", "carbine", "flamethrower", "kar98", "magnum", "mp40", "raygun", "sawnoff",
		"shotgun", "stg44", "thompson", "trenchgun", "fg42", "g43", "garand", "mg42", "ppsh", "ptrs", "springfield",
		"molotov", "arisaka", "type100", "betty"],
	"verruckt": ["bar", "browning", "carbine", "flamethrower", "kar98", "magnum", "mp40", "raygun", "sawnoff",
		"shotgun", "stg44", "thompson", "trenchgun", "fg42", "g43", "garand", "mg42", "ppsh", "ptrs", "springfield",
		"molotov", "arisaka", "type100"],
	"shinonuma": ["bar", "browning", "carbine", "flamethrower", "kar98", "magnum", "mp40", "raygun", "sawnoff",
		"shotgun", "stg44", "thompson", "trenchgun", "fg42", "g43", "garand", "mg42", "ppsh", "ptrs", "springfield",
		"molotov", "arisaka", "type100", "wunderwaffe"],
	"derriese": ["bar", "browning", "carbine", "flamethrower", "kar98", "magnum", "mp40", "raygun", "shotgun",
		"stg44", "thompson", "trenchgun", "fg42", "g43", "garand", "mg42", "ppsh", "ptrs", "molotov", "type100",
		"wunderwaffe", "monkeybomb"],
}
const MYSTERY_DEFAULT := "nacht"

signal moved(entity: String)

enum State { CLOSED, CYCLING, OFFERED, CLOSING, TEDDY, LEAVING, GONE, ARRIVING }

var state := State.CLOSED
var offered := ""
var _anim: AnimationPlayer
var _weapon: Node3D
var _timer := 0.0
var _swap := 0.0
var _buyer: Player
var _cache := {}
var level: Level
var entity := ""
var locations := []       # every MysteryBox entity of the map (set by level.gd)
var uses := 0             # purchases at this location
var used_count := 0       # purchases for the teddy rule (whole game, lowered by the bear)
var _memory := []         # last locations (WarpMysteryBox does not go back to them)
var _model: Node3D
var _body: StaticBody3D
var _teddy_next := false  # tests: --teddy forces the bear on the next use
static var _teddy_scene: PackedScene


func setup(level_: Level, entity_: String) -> void:
	level = level_
	var e: Dictionary = level.entities[entity_]
	var model_hash: String = e["models"][0] if not e["models"].is_empty() else "ecee0a62"
	var path := "res://assets/characters/levels/%s/dynamics/%s.glb" % [level.level_name, model_hash]
	if ResourceLoader.exists(path):
		_model = (load(path) as PackedScene).instantiate()
		add_child(_model)
		_anim = _model.find_children("*", "AnimationPlayer")[0]
		if not _anim.has_animation(ANIM_OPEN):
			_pick_animations()
		_pose(ANIM_IDLE_CLOSED)
	_place(entity_)
	if locations.is_empty():
		locations = [entity_]


# Put the box at a MysteryBox entity: transform and its solid volume.
func _place(entity_: String) -> void:
	entity = entity_
	_memory.append(entity)
	while _memory.size() > MEMORY:
		_memory.pop_front()
	uses = 0
	var e: Dictionary = level.entities[entity]
	# quarter turns in the transform flags (Level.flag_transform), as for the debris
	var root := Level.flag_transform(e["transform"])
	global_transform = root * Level.flag_transform(e["children"][-1]) if not e["children"].is_empty() else root
	if _body:
		_body.free()
	# solid box from the closed model: the entity collider is the use area, 2.2 x 1.9 m
	# around the 1.1 m box, and kept the player an arm's length away
	var body := StaticBody3D.new()
	_body = body
	add_child(body)
	var solid := _model_box()
	if solid.size != Vector3.ZERO:
		solid.size.y = maxf(solid.size.y, 1.0)   # as tall as the original volume: no standing on it
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = solid.size.max(Vector3(0.2, 0.2, 0.2))
		shape.shape = box
		shape.position = solid.get_center()
		body.add_child(shape)


# Bounds of the box meshes in this node's frame (closed pose, teddy and weapon left out).
var _solid := AABB()


func _model_box() -> AABB:
	if _solid.size != Vector3.ZERO or _model == null:
		return _solid
	var first := true
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = mi.transform
		var n: Node = mi.get_parent()
		while n != self and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * mi.get_aabb()
		_solid = b if first else _solid.merge(b)
		first = false
	return _solid


# Two one-key poses (closed/open) and two animations (open/close): the opening
# animation starts from the closed pose.
func _pick_animations() -> void:
	var poses := []
	var moves := []
	for a in _anim.get_animation_list():
		var anim := _anim.get_animation(a)
		var keys := 0
		for t in anim.get_track_count():
			keys = max(keys, anim.track_get_key_count(t))
		(poses if keys <= 1 else moves).append(a)
	if poses.size() < 2 or moves.size() < 2:
		return
	# the opening animation ends far from where it starts and starts at a pose
	var best := INF
	for m in moves:
		for p in poses:
			var d := _pose_distance(p, m, 0.0)
			if d < best:
				best = d
				ANIM_OPEN = m
				ANIM_IDLE_CLOSED = p
	ANIM_CLOSE = moves[0] if moves[1] == ANIM_OPEN else moves[1]
	ANIM_IDLE_OPEN = poses[0] if poses[1] == ANIM_IDLE_CLOSED else poses[1]


func _pose_distance(pose_name: String, move_name: String, t: float) -> float:
	var pose := _anim.get_animation(pose_name)
	var move := _anim.get_animation(move_name)
	var d := 0.0
	for i in pose.get_track_count():
		var mt := move.find_track(pose.track_get_path(i), pose.track_get_type(i))
		if mt < 0 or pose.track_get_key_count(i) == 0:
			continue
		if pose.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			d += (pose.track_get_key_value(i, 0) as Quaternion).angle_to(move.rotation_track_interpolate(mt, t))
		elif pose.track_get_type(i) == Animation.TYPE_POSITION_3D:
			d += (pose.track_get_key_value(i, 0) as Vector3).distance_to(move.position_track_interpolate(mt, t))
	return d


func _pose(a: String) -> void:
	if _anim and _anim.has_animation(a):
		_anim.play(a)
		_anim.seek(0.0, true)
		_anim.pause()


func prompt(player: Player) -> String:
	match state:
		State.CLOSED:
			return "Premi E per la Mystery Box [%d]" % COST
		State.OFFERED:
			if player == _buyer:
				return "Premi E per prendere %s" % Weapons.display(offered)
	return ""


func interact(player: Player) -> void:
	match state:
		State.CLOSED:
			if player.points < COST:
				return
			player.add_points(-COST)
			_buyer = player
			uses += 1
			used_count += 1
			_open()
		State.OFFERED:
			if player == _buyer:
				if offered == MonkeyBomb.ITEM:
					MonkeyBelt.give(player)
				elif offered == BettyBelt.ITEM:
					BettyBelt.give(player)
				elif offered == MolotovBelt.ITEM:
					MolotovBelt.give(player)
				else:
					player.give_weapon(offered)
					VoxLines.box_taken(offered)   # weapon_good (vox_lines.gd)
					if offered == "wunderwaffe":
						Sfx.instance.vox("weapon_tesla")   # player vox line for the Wunderwaffe
				_close()


func _open() -> void:
	state = State.CYCLING
	_timer = CYCLE_TIME
	Sfx.instance.play_at("music_box_open", global_position + Vector3.UP)
	Sfx.instance.play_at("box_music", global_position + Vector3.UP)
	if _anim:
		_anim.play(ANIM_OPEN)
	_show_weapon(pool().pick_random())


func _close() -> void:
	state = State.CLOSING
	Sfx.instance.play_at("music_box_close", global_position + Vector3.UP)
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	if _anim:
		_anim.play(ANIM_CLOSE)
	var t := _anim.get_animation(ANIM_CLOSE).length if _anim else 0.5
	get_tree().create_timer(t + 0.3).timeout.connect(func():
		state = State.CLOSED
		_pose(ANIM_IDLE_CLOSED))


func _process(delta: float) -> void:
	match state:
		State.CYCLING:
			_timer -= delta
			_swap -= delta
			var p := 1.0 - _timer / CYCLE_TIME
			if _weapon:
				_weapon.position = Vector3(0, 0.25 + 0.45 * p, 0)
			if _timer <= 0.0:
				if _teddy_roll():
					_teddy()
					return
				offered = _pick()
				_show_weapon(offered)
				state = State.OFFERED
				VoxLines.box_shown(offered)   # weapon_bad (vox_lines.gd)
				_timer = OFFER_TIME
			elif _swap <= 0.0:
				_swap = lerpf(0.08, 0.35, p)  # slows down like the original
				_show_weapon(pool().pick_random())
		State.OFFERED:
			_timer -= delta
			if _weapon:
				# floats, then sinks back into the box in the last seconds
				var sink := clampf((3.0 - _timer) / 3.0, 0.0, 1.0)
				_weapon.position = Vector3(0, 0.7 - 0.45 * sink + sin(_timer * 3.0) * 0.02, 0)
			if _timer <= 0.0:
				_close()
		State.LEAVING:
			_timer -= delta
			_fly(1.0 - _timer / RISE_TIME)
			if _timer <= 0.0:
				_vanish()
		State.ARRIVING:
			_timer -= delta
			var k := clampf(1.0 - _timer / FALL_TIME, 0.0, 1.0)
			if _model:
				_model.position = Vector3(0, 6.0 * (1.0 - k * k), 0)
				_model.rotation = Vector3.ZERO
			if _timer <= 0.0:
				if _model:
					_model.position = Vector3.ZERO
				Sfx.instance.play_at("teddyland", global_position + Vector3.UP)
				state = State.CLOSED


# ------------------------------------------------------------------ teddy bear

func _teddy_roll() -> bool:
	if locations.size() < 2:
		return false  # Nacht: one location, the box never moves
	if _teddy_next or OS.get_cmdline_user_args().has("--teddy"):
		_teddy_next = false
		return true
	var rule: Array = TEDDY_RULES.get(level.level_name if level else "", TEDDY_DEFAULT)
	if used_count > int(rule[0]) and randi_range(0, 99) < int(rule[2]):
		used_count = int(rule[0]) - int(rule[1])
		return true
	return false


func _teddy() -> void:
	state = State.TEDDY
	offered = ""
	_show_model(_teddy_model())
	if _weapon:
		_weapon.position = Vector3(0, 0.8, 0)
	Sfx.instance.play_at("teddylaugh", global_position + Vector3.UP)
	VoxLines.say("teddy")   # character line (vox_lines.gd)
	if _buyer:
		_buyer.add_points(COST)  # refunded
	get_tree().create_timer(TEDDY_LAUGH, false).timeout.connect(_leave)


func _teddy_model() -> Node3D:
	var path := "res://assets/models/ingame/dynamics.glb"
	if _teddy_scene == null and ResourceLoader.exists(path):
		_teddy_scene = load(path)
	if _teddy_scene == null:
		return null
	var all := _teddy_scene.instantiate()
	var bear := all.find_child(TEDDY_MODEL, true, false) as Node3D
	if bear:
		bear.get_parent().remove_child(bear)
		bear.transform = Transform3D(Basis(Vector3.UP, TEDDY_YAW), Vector3.ZERO)
	all.free()
	return bear


func _leave() -> void:
	state = State.LEAVING
	_timer = RISE_TIME
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	Sfx.instance.play_at("box_flyaway", global_position + Vector3.UP)


# rises slowly, shaking more and more, then shoots up
func _fly(k: float) -> void:
	if _model == null:
		return
	var shake := k * 0.12
	var t := Time.get_ticks_msec() / 1000.0
	_model.position = Vector3(sin(t * 31.0) * shake * 0.3, 1.2 * k * k + 3.0 * maxf(k - 0.85, 0.0) / 0.15, cos(t * 27.0) * shake * 0.3)
	_model.rotation = Vector3(sin(t * 23.0) * shake, sin(t * 17.0) * shake * 0.5, cos(t * 29.0) * shake)


func _vanish() -> void:
	state = State.GONE
	Sfx.instance.play_at("teddypoof", global_position + Vector3.UP * 2.5)
	if _model:
		_model.visible = false
	if _body:
		_body.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().create_timer(GONE_TIME, false).timeout.connect(_warp)


# WarpMysteryBox: a random location that is not one of the last MEMORY ones
func _warp() -> void:
	var choices := locations.filter(func(n): return not n in _memory)
	if choices.is_empty():
		choices = locations.filter(func(n): return n != entity)
	_place(choices.pick_random() if not choices.is_empty() else entity)
	_pose(ANIM_IDLE_CLOSED)
	if _model:
		_model.visible = true
		_model.position = Vector3(0, 6.0, 0)
	state = State.ARRIVING
	_timer = FALL_TIME
	Sfx.instance.play_at("box_fall", global_position + Vector3.UP * 3.0)
	moved.emit(entity)


func _pick() -> String:
	var owned := _buyer.weapons.map(func(w): return w["name"]) if _buyer else []
	var choices := pool().filter(func(w): return not w in owned)
	return choices.pick_random() if not choices.is_empty() else pool().pick_random()


# The map's MysteryWeapons list (MYSTERY_WEAPONS); "monkeybomb" is MonkeyBomb.ITEM here.
# Every map has the .357 Magnum, the Molotovs, the Kar98k and the M1 Carbine; the betty only
# on Nacht (the other maps sell it on the wall, CActionBuyBettySpec); the Wunderwaffe on
# Shi No Numa and Der Riese; Der Riese drops the sawed-off, Springfield and Arisaka and
# adds the Monkey Bomb.
func pool() -> Array:
	var key: String = level.level_name if level and MYSTERY_WEAPONS.has(level.level_name) else MYSTERY_DEFAULT
	return MYSTERY_WEAPONS[key].map(func(w): return MonkeyBomb.ITEM if w == "monkeybomb" else w)


func _show_weapon(name: String) -> void:
	if name == MolotovBelt.ITEM:
		var mm := Molotov.model(Molotov.BOX_MODEL)
		mm.scale = Vector3.ONE * 2.0
		_show_model(mm)
		return
	if name == BettyBelt.ITEM:
		var bm := Betty.model()
		bm.scale = Vector3.ONE * 2.0
		_show_model(bm)
		return
	if name == MonkeyBomb.ITEM:
		var m := MonkeyBomb.model()
		m.scale = Vector3.ONE * 2.0
		_show_model(m)
		return
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	# same model as held in first person (tools/pair_arms.py picks it per weapon)
	var path := ""
	var info: Dictionary = Viewmodel.pairs()["weapons"].get(name, {})
	if info.has("model"):
		path = "res://assets/characters/ingame/player/%s.glb" % info["model"]
	if path == "" or not ResourceLoader.exists(path):
		return
	if not _cache.has(path):
		_cache[path] = load(path)
	var model: Node3D = (_cache[path] as PackedScene).instantiate()
	model.rotation.y = PI / 2  # lie along the box
	_show_model(model)


func _show_model(model: Node3D) -> void:
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	if model == null:
		return
	# holder floats; the model inside is centred on its bounds (origins vary per model)
	_weapon = Node3D.new()
	add_child(_weapon)
	_weapon.add_child(model)
	var bounds := AABB()
	var first := true
	var meshes := model.find_children("*", "MeshInstance3D")
	if model is MeshInstance3D:
		meshes.append(model)
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# static display: unbind the skin so the mesh shows as modelled, matching its bounds
		mi.skin = null
		mi.skeleton = NodePath("")
		var a: AABB = mi.get_aabb()
		bounds = a if first else bounds.merge(a)
		first = false
	model.position = -(model.basis * bounds.get_center())
