# Mystery box (CMysteryBoxSpec entity), driven like its anim state machine: ASM 350fb630
# (Verrückt, Shi No Numa, Der Riese; Nacht's f3e136cb is the same without the teddy states).
#   S0 closed (pose e98b0527) -goodieInteract-> S1 opening (b83ef401, 1458 ms, createWeapon,
#   music_box_open) -> S3 open (e6e657ff, raiseWeapon, music_box_play): the weapon rises
#   -weaponInterpComplete-> S4 offer, 12000 ms -> S6 lowerWeapon (still takeable)
#   -weaponInterpComplete-> S2 Closing (bf424825, 833 ms, music_box_close) -> S0.
#   Taken (S4/S6 goodieInteract) -> S7 destroyWeapon -> S2.
#   Teddy: S3 -teddyBear-> S5 (teddylaugh) -teddyBearInterpComplete-> S8 flight (c7403104 at
#   14336/4096 = 3.5x, 5238 ms, box_flyaway + teddypoof, effect 03ca2c23 twice, Lua teddyBear =
#   WarpMysteryBox) -> S9 INACTIVE (dormant); the new box: activateMysteryBoxFalling -> S10
#   (c7403104 backwards at 5x, 3666 ms, box_fall + teddyland, effect 03ca2c23) -> S2 Closing.
# The weapon (CMysteryBoxSpec, console.bin): shown once the lid is open, it rises in a straight
# line from MysteryStartGunOffset (0,25,-32) to MysteryEndGunOffset (0,125,-32) in
# MysteryInterpolateTime 4000 ms, switching among MysteryNumOtherGunsToShow 13 other guns at a
# steady pace; lowering takes the same time. The bear waits MysteryWaitToFlyBearTime 1000 ms,
# then goes up to MysteryEndTeddyBearOffset (0,300,-32) in MysteryTeddyBearInterpolateTime 2000 ms.
# The offsets are in the units of the code's defaults ({0,100,-125} / {0,500,-125}): x4 is an
# estimate that matches those defaults (100 / 25 = 4). They are in the entity frame: z -32 x4
# = -128 units puts the gun over the middle of the box model (its child sits at z -135 / -163).
# Teddy rules: on maps with several MysteryBox locations, after a few uses the box can give
# the teddy instead: the 950 points are refunded and the box moves to another location (not
# one of the last two).
class_name MysteryBox
extends Node3D

const COST := 950
# animation names from the ASMs, per box model
const ANIMS := {
	"350fb630": {"closed": "e98b0527", "open": "b83ef401", "opened": "e6e657ff", "close": "bf424825", "fly": "c7403104"},
	"ecee0a62": {"closed": "b4bcad2c", "open": "d8283c46", "opened": "ef143ac4", "close": "dc54990a"},   # Nacht, ASM f3e136cb
}
var ANIM_OPEN := "d8283c46"
var ANIM_CLOSE := "dc54990a"
var ANIM_IDLE_OPEN := "ef143ac4"
var ANIM_IDLE_CLOSED := "b4bcad2c"
var ANIM_FLY := ""
const OPEN_TIME := 1.458        # S1 dur
const CLOSE_TIME := 0.833       # S2 dur
const GUN_TIME := 4.0           # MysteryInterpolateTime
const OTHER_GUNS := 13          # MysteryNumOtherGunsToShow
const CYCLE_TIME := OPEN_TIME + GUN_TIME   # bought -> weapon offered (or the bear)
const OFFSET_SCALE := 4.0 * Level.UNITS   # console.bin offsets -> metres (x4 estimated)
const GUN_START := Vector3(0, 25, -32) * OFFSET_SCALE     # MysteryStartGunOffset
const GUN_END := Vector3(0, 125, -32) * OFFSET_SCALE      # MysteryEndGunOffset
const TEDDY_END := Vector3(0, 300, -32) * OFFSET_SCALE    # MysteryEndTeddyBearOffset
const TEDDY_WAIT := 1.0         # MysteryWaitToFlyBearTime
const TEDDY_RISE := 2.0         # MysteryTeddyBearInterpolateTime
const FLY_SPEED := 14336.0 / 4096.0   # S8 rate (3.5x)
const FLY_TIME := 5.238               # S8 dur
const FALL_SPEED := 20480.0 / 4096.0  # S10 rate -20480 (5x backwards)
const FALL_TIME := 3.666              # S10 dur
const GONE_TIME := 1.0     # WarpMysteryBox sends activateMysteryBoxFalling with a 1 (estimated as 1 s)
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

# CLOSED S0, OPENING S1, CYCLING S3, OFFERED S4, LOWERING S6, CLOSING S2, TEDDY S5,
# LEAVING S8, GONE S9, ARRIVING S10
enum State { CLOSED, CYCLING, OFFERED, CLOSING, TEDDY, LEAVING, GONE, ARRIVING, OPENING, LOWERING }

var state := State.CLOSED
var offered := ""
var _anim: AnimationPlayer
var _weapon: Node3D
var _timer := 0.0
var _swap := 0.0
var _shown := 0             # other guns shown while rising
var _teddy_from := Vector3.ZERO
# entity frame -> this node (the model sits on the entity's child, 0.34-0.41 m behind the
# entity origin): the gun / bear offsets and the effect are in the entity frame
var _from_entity := Transform3D.IDENTITY
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
		var names: Dictionary = ANIMS.get(model_hash, ANIMS["ecee0a62"])
		ANIM_OPEN = names["open"]
		ANIM_CLOSE = names["close"]
		ANIM_IDLE_OPEN = names["opened"]
		ANIM_IDLE_CLOSED = names["closed"]
		ANIM_FLY = names.get("fly", "")
		for a in [ANIM_OPEN, ANIM_CLOSE, ANIM_FLY]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_NONE
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
	_from_entity = global_transform.affine_inverse() * root
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


func _pose(a: String) -> void:
	if _anim and _anim.has_animation(a):
		_anim.speed_scale = 1.0
		_anim.play(a)
		_anim.seek(0.0, true)
		_anim.pause()


func prompt(player: Player) -> String:
	match state:
		State.CLOSED:
			return "Premi E per la Mystery Box [%d]" % COST
		State.OFFERED, State.LOWERING:
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
		State.OFFERED, State.LOWERING:
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


# S1 opening: the lid opens, the weapon appears once it is open (S3)
func _open() -> void:
	state = State.OPENING
	_timer = OPEN_TIME
	Sfx.instance.play_at("music_box_open", global_position + Vector3.UP)
	_play(ANIM_OPEN)


# S3: raiseWeapon + music_box_play
func _raise() -> void:
	state = State.CYCLING
	_timer = GUN_TIME
	_shown = 0
	_swap = GUN_TIME / OTHER_GUNS
	_pose(ANIM_IDLE_OPEN)
	Sfx.instance.play_at("music_box_play", global_position + Vector3.UP)
	_show_weapon(pool().pick_random())
	_gun_at(0.0)


# S2 Closing (taken: S7 destroyWeapon first)
func _close() -> void:
	state = State.CLOSING
	_timer = CLOSE_TIME
	Sfx.instance.play_at("music_box_close", global_position + Vector3.UP)
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	_play(ANIM_CLOSE)


func _play(a: String, speed := 1.0, backwards := false) -> void:
	if _anim and _anim.has_animation(a):
		if backwards:
			_anim.play_backwards(a)
		else:
			_anim.play(a)
		_anim.speed_scale = speed


func _gun_at(k: float) -> void:
	if _weapon:
		_weapon.position = _from_entity * GUN_START.lerp(GUN_END, clampf(k, 0.0, 1.0))


func _process(delta: float) -> void:
	match state:
		State.OPENING:
			_timer -= delta
			if _timer <= 0.0:
				_raise()
		State.CYCLING:
			_timer -= delta
			_swap -= delta
			if _timer <= 0.0:
				if _teddy_roll():
					_teddy()
					return
				offered = _pick()
				_show_weapon(offered)
				_gun_at(1.0)
				state = State.OFFERED
				VoxLines.box_shown(offered)   # weapon_bad (vox_lines.gd)
				_timer = OFFER_TIME
			elif _swap <= 0.0 and _shown < OTHER_GUNS - 1:
				# a steady switch among the other guns
				_swap += GUN_TIME / OTHER_GUNS
				_shown += 1
				_show_weapon(pool().pick_random())
				_gun_at(1.0 - _timer / GUN_TIME)
			else:
				_gun_at(1.0 - _timer / GUN_TIME)
		State.OFFERED:
			_timer -= delta
			if _timer <= 0.0:
				state = State.LOWERING   # S6 lowerWeapon
				_timer = GUN_TIME
		State.LOWERING:
			_timer -= delta
			_gun_at(_timer / GUN_TIME)
			if _timer <= 0.0:
				_close()
		State.CLOSING:
			_timer -= delta
			if _timer <= 0.0:
				state = State.CLOSED
				_pose(ANIM_IDLE_CLOSED)
		State.TEDDY:
			_timer -= delta
			if _weapon:
				var k := clampf(-_timer / TEDDY_RISE, 0.0, 1.0)
				_weapon.position = _from_entity * _teddy_from.lerp(TEDDY_END, k)
			if _timer <= -TEDDY_RISE:
				_leave()   # teddyBearInterpComplete
		State.LEAVING:
			_timer -= delta
			if _timer <= 0.0:
				_vanish()
		State.ARRIVING:
			_timer -= delta
			if _timer <= 0.0:
				_close()


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


# S5: the bear instead of a gun, teddylaugh; it waits, then goes up
func _teddy() -> void:
	state = State.TEDDY
	offered = ""
	_timer = TEDDY_WAIT
	_show_model(_teddy_model())
	_teddy_from = GUN_END
	if _weapon:
		_weapon.position = _from_entity * GUN_END
	Sfx.instance.play_at("teddylaugh", global_position + Vector3.UP)
	VoxLines.say("teddy")   # character line (vox_lines.gd)
	if _buyer:
		_buyer.add_points(COST)  # refunded


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


# S8: the bear goes (teddypoof, effect 03ca2c23) and the box flies off with its lid open
func _leave() -> void:
	state = State.LEAVING
	_timer = FLY_TIME
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	Sfx.instance.play_at("box_flyaway", global_position + Vector3.UP)
	Sfx.instance.play_at("teddypoof", global_transform * (_from_entity * TEDDY_END))
	_beams()
	_play(ANIM_FLY, FLY_SPEED)


# S9 INACTIVE (dormant)
func _vanish() -> void:
	state = State.GONE
	if _model:
		_model.visible = false
	if _body:
		_body.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().create_timer(GONE_TIME, false).timeout.connect(_warp)


# Effect entity 03ca2c23 (ingame effects): three children 03ca2c24-26, each the quad model
# f85b75b2 (1.3 x 5.2 m, additive material 995344cb: lightning) at an offset from the box, with
# a short life (450 / 375 / 500 in their specs, read here as ms). Offsets and lives are
# read from the specs without a full decoding; facing the camera around the vertical is
# an estimate.
const BEAMS := [[Vector3(-50, 50, -50), 0.45], [Vector3(70, 0, 70), 0.375], [Vector3(500, 0, -100), 0.5]]
static var _effects_scene: PackedScene


func _beams() -> void:
	var path := "res://assets/models/ingame/effects.glb"
	if _effects_scene == null and ResourceLoader.exists(path):
		_effects_scene = load(path)
	if _effects_scene == null:
		return
	for b in BEAMS:
		var all := _effects_scene.instantiate()
		var quad := all.find_child("f85b75b2", true, false) as MeshInstance3D
		if quad == null:
			all.free()
			continue
		quad.get_parent().remove_child(quad)
		all.free()
		quad.transform = Transform3D.IDENTITY
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in quad.mesh.get_surface_count():
			var m := quad.get_active_material(i)
			if m is BaseMaterial3D:
				m = m.duplicate()
				var bm := m as BaseMaterial3D
				bm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
				# material byte 3 = 2: additive (as the CIwGFXEmitterSpec sprites, iw_emitter.gd)
				bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				bm.cull_mode = BaseMaterial3D.CULL_DISABLED
				bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				quad.set_surface_override_material(i, m)
		add_child(quad)
		quad.position = _from_entity * ((b[0] as Vector3) * Level.UNITS)
		get_tree().create_timer(float(b[1]), false).timeout.connect(quad.queue_free)


# WarpMysteryBox: a random location that is not one of the last MEMORY ones
func _warp() -> void:
	var choices := locations.filter(func(n): return not n in _memory)
	if choices.is_empty():
		choices = locations.filter(func(n): return n != entity)
	_place(choices.pick_random() if not choices.is_empty() else entity)
	if _model:
		_model.visible = true
	# S10: c7403104 backwards at 5x, from up in the air down onto the new spot
	state = State.ARRIVING
	_timer = FALL_TIME
	if _anim and _anim.has_animation(ANIM_FLY):
		_play(ANIM_FLY, FALL_SPEED, true)
	else:
		_pose(ANIM_IDLE_OPEN)
	Sfx.instance.play_at("box_fall", global_position + Vector3.UP * 3.0)
	Sfx.instance.play_at("teddyland", global_position + Vector3.UP)
	_beams()
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
