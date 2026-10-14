# Der Riese fly trap easter egg (derriese.lua, read from the bytecode where the
# decompile lost it). Shooting "flytrapTrigger" (CHealthSpec 10 + CTriggerDamageSpec):
#   Trigger "flytrapTrigger": achievement der_ElevateYourSenses ("Activate the Fly
#   Trap"), FlytrapGo: DisableTrigger, EnableRender("flytrapAnim") + ASM "flyTrapGo",
#   EnableSoundEmitter("flytrapSoundHit"), Timeout(5000, "FlytrapSound1").
#   FlytrapSound1: flytrapSoundVox1, 5 s -> FlytrapSound2: Vox1 off, flytrapSoundVox2,
#   3 s -> FlytrapSound3: flytrapSoundEnd, Hit/Vox1/Vox2 off, 1.2 s -> FlytrapOff:
#   DisableRender("flytrapAnim"), End off, 1 s -> flytrapSetUp: FlyTrapUpdate("TurnOn").
#   FlyTrapUpdate TurnOn: the three items appear (flyTrapItem<n>Object<m>, item 1 has
#   two objects) and their flyTrapItem<n>Trigger are enabled (Begin: "TurnOff").
#   Trigger "flyTrapItem<n>Trigger": DisableTrigger, PlaySound("flytrap_item_hit"),
#   UpdateVox: the item is hidden and flytrap_found_vox1/2/3 plays for the 1st/2nd/3rd
#   item found. Nothing else: no reward beyond the voice lines.
# flytrapAnim is model b4301907 (a ring of green sparkle cards) animated by ASM
# 3b00d233 "On" with the SingleBone animation 3b00d233: it turns and rises 7 m over
# 7.5 s, then shoots off (19 m along z) - FlytrapOff hides it at 14.2 s.
# Items: teddy bear 6e3f6288 (ingame dynamics) posed with player-group models: knife
# a507b242 / molotov fa94ee6a, stick grenade f54310eb, monkey bomb 429c0bd4 /
# bottle c7e5e430, colt a0d23f6b (entities.json misses the models of the rotated
# entities, so they are listed here from the entity bodies).
# The four triggers are the only CTriggerDamageSpec of the game whose last byte is 1
# (and the only ones with a CFlagsSpec). Confirmed in the code: CTriggerDamageSpec::
# Serialise (kiwi 0x13c050) reads u32 0x30 (required damage type, 0 = any) and that byte
# as bool 0x34; CTriggerDamage's damage-message handler (0xf5344) ignores a hit when 0x34
# is set and the damage info byte 0x2a is 0. That byte is the "upgraded" flag: splash
# damage copies it from CSplashEffectSpec 0x75 (0xe4730), which is 1 only for the
# Pack-a-Punched Ray Gun's splash (c5a7a7b6), 0 for the normal Ray Gun's. So only
# Pack-a-Punched weapons trigger the fly trap and its items (UPGRADED_ONLY).
class_name FlyTrap
extends Node3D

const UPGRADED_ONLY := true
const TRIGGER := "flytrapTrigger"
const ANIM_ENTITY := "flytrapAnim"
const ANIM_MODEL := "b4301907"
const ITEMS := {
	1: {1: "6e3f6288", 2: "a507b242"},
	2: {1: "fa94ee6a", 2: "f54310eb", 3: "429c0bd4"},
	3: {1: "6e3f6288", 2: "c7e5e430", 3: "a0d23f6b"},
}
const ITEM_GLB := {"6e3f6288": "res://assets/models/ingame/dynamics.glb"}
const PLAYER_GLB := "res://assets/models/ingame/player.glb"
# CSoundEmitterSpec of the flytrap sound entities: [spec, mode, range units]
const EMITTERS := {
	"flytrapSoundHit": [["88f2dfb4"], "loop", 1600],
	"flytrapSoundVox1": [["c97084a1"], "once", 1600],
	"flytrapSoundVox2": [["c97084a2"], "once", 1600],
	"flytrapSoundEnd": [["5fef1d91"], "once", 1600],
}
# SingleBone animation 3b00d233: [time s, root position (bone units, posScale 1/4), yaw quaternion y, w]
const ANIM_KEYS := [
	[0.0, Vector3(-168, -226, 0), 0.0, 1.0],
	[2.458, Vector3(-168, 3494, 0), 0.707, 0.707],
	[4.958, Vector3(-168, 7304, 0), -0.208, 0.978],
	[5.083, Vector3(-168, 7502, 0), 0.0, 1.0],
	[7.458, Vector3(-168, 11068, 0), 0.0, 1.0],
	[7.875, Vector3(-168, 11068, 0), 0.0, 1.0],
	[8.417, Vector3(-168, 11068, 30582), 0.0, 1.0],
	[19.083, Vector3(-168, 11068, 30582), 0.0, 1.0],
]
const ANIM_POS_SCALE := 0.25

var game: Game
var level: Level
var activated := false
var found := 0
var triggers := {}        # name -> Target
var emitters := {}        # name -> RadioEggs.Emitter
var items := {}           # n -> [Node3D objects]
var events := []          # trigger names and "items", for tests
var _ring: Node3D
var _ring_base := Transform3D.IDENTITY
var _ring_t := -1.0


static func create(game_: Game) -> FlyTrap:
	var lv := game_.level
	if not lv.has_entity(TRIGGER):
		return null
	var f := FlyTrap.new()
	f.name = "FlyTrap"
	f.game = game_
	f.add_to_group(SaveGame.PROVIDER_GROUP)   # fly trap progress (save_game.gd)
	f.level = lv
	game_.add_child(f)
	f._build()
	return f


func _ent(n: String) -> Dictionary:
	var e := level.entity(n)
	if e.is_empty():
		e = level.entity(Sfx.iw_hash(n))   # names not recovered: entities.json keeps the hash
	return e


func _build() -> void:
	triggers[TRIGGER] = _make_target(TRIGGER, [])
	for n in EMITTERS:
		var ent := _ent(n)
		if ent.is_empty():
			continue
		var em := RadioEggs.Emitter.new()
		em.name = "Emitter_" + n
		em.chain = EMITTERS[n][0]
		em.mode = EMITTERS[n][1]
		em.range_m = float(EMITTERS[n][2]) / 400.0
		add_child(em)
		em.global_position = Level._to_transform(ent["transform"]).origin
		emitters[n] = em
	# the sparkle ring, hidden until the trap goes
	var anim_ent := _ent(ANIM_ENTITY)
	_ring = level.dynamics_model(ANIM_MODEL)
	level._release_dynamics()
	if _ring and not anim_ent.is_empty():
		_ring_base = Level._to_transform(anim_ent["transform"])
		add_child(_ring)
		_ring.global_transform = _ring_base
		_effect_materials(_ring)
		_ring.visible = false
	# items: hidden, triggers off (Begin: FlyTrapUpdate("TurnOff"))
	var scenes := {}
	for n in ITEMS:
		items[n] = []
		var spots := []
		for m in ITEMS[n]:
			var ent := _ent("flyTrapItem%dObject%d" % [n, m])
			if ent.is_empty():
				continue
			var h: String = ITEMS[n][m]
			var path: String = ITEM_GLB.get(h, PLAYER_GLB)
			if not scenes.has(path):
				scenes[path] = (load(path) as PackedScene).instantiate()
			var src := (scenes[path] as Node).find_child(h, true, false) as Node3D
			if src == null:
				continue
			var obj := src.duplicate() as Node3D
			add_child(obj)
			obj.global_transform = Level._to_transform(ent["transform"])
			obj.visible = false
			items[n].append(obj)
			spots.append(obj.global_position)
		var t := _make_target("flyTrapItem%dTrigger" % n, spots)
		if t:
			t.enabled = false
			triggers[t.trigger_name] = t
	for s in scenes.values():
		(s as Node).free()


# Additive/alpha cards (material extras "blend", see Level._prepare_meshes)
static func _effect_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false) + ([root] if root is MeshInstance3D else []):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var m := mat.duplicate() as StandardMaterial3D
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.vertex_color_use_as_albedo = true
			mi.set_surface_override_material(s, m)


# Shootable box from the trigger entity's AABox; for the items it also covers the
# objects (flyTrapItem3Trigger's box sits 1.2 m beside its teddy bear).
func _make_target(n: String, spots: Array) -> Target:
	var ent := _ent(n)
	if ent.is_empty() or (ent["colliders"] as Array).is_empty():
		return null
	var at := Level._to_transform(ent["transform"]).origin
	var col: Dictionary = ent["colliders"][0]
	var lo := at + Vector3(col["min"][0], col["min"][1], col["min"][2]) / 400.0
	var hi := at + Vector3(col["max"][0], col["max"][1], col["max"][2]) / 400.0
	var box := AABB(lo, hi - lo).abs()
	for p: Vector3 in spots:
		box = box.merge(AABB(p - Vector3.ONE * 0.25, Vector3.ONE * 0.5))
	var t := Target.new()
	t.name = "Trigger_" + n
	t.trigger_name = n
	t.owner_trap = self
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box.size
	cs.shape = b
	t.add_child(cs)
	add_child(t)
	t.global_position = box.get_center()
	return t


func centre_of(n: String) -> Vector3:
	return (triggers[n] as Node3D).global_position if triggers.has(n) else Vector3.INF


# Script.Level.Trigger for the fly trap names
func trigger(n: String, by: Player) -> void:
	if UPGRADED_ONLY and (by == null or not by.weapon().get("upgraded", false)):
		return
	events.append(n)
	if OS.get_cmdline_user_args().has("--egg-log"):
		print("[flytrap] trigger %s" % n)
	if n == TRIGGER:
		_go()
		return
	var i := int(n.trim_prefix("flyTrapItem").trim_suffix("Trigger"))
	triggers[n].enabled = false
	Sfx.instance.play("flytrap_item_hit")
	for o in items.get(i, []):
		o.visible = false
	found += 1
	if found <= 3:
		Sfx.instance.play("flytrap_found_vox%d" % found)


func _timeout(ms: int, f: Callable) -> void:
	get_tree().create_timer(ms / 1000.0, false).timeout.connect(f)


# Script.Level.FlytrapGo and its Timeout chain
func _go() -> void:
	activated = true
	triggers[TRIGGER].enabled = false
	print("[flytrap] achievement der_ElevateYourSenses")
	Achievements.unlock("der_ElevateYourSenses")
	if _ring:
		_ring.visible = true
		_ring_t = 0.0
	_enable("flytrapSoundHit")
	_timeout(5000, func():   # FlytrapSound1
		_enable("flytrapSoundVox1")
		_timeout(5000, func():   # FlytrapSound2
			_disable("flytrapSoundVox1")
			_enable("flytrapSoundVox2")
			_timeout(3000, func():   # FlytrapSound3
				_enable("flytrapSoundEnd")
				for e in ["flytrapSoundHit", "flytrapSoundVox1", "flytrapSoundVox2"]:
					_disable(e)
				_timeout(1200, func():   # FlytrapOff
					if _ring:
						_ring.visible = false
					_ring_t = -1.0
					_disable("flytrapSoundEnd")
					_timeout(1000, _set_up)))))


# flytrapSetUp: FlyTrapUpdate("TurnOn")
func _set_up() -> void:
	events.append("items")
	for n in items:
		for o in items[n]:
			o.visible = true
		var tn := "flyTrapItem%dTrigger" % n
		if triggers.has(tn):
			triggers[tn].enabled = true


func _enable(n: String) -> void:
	if emitters.has(n):
		emitters[n].enable()


func _disable(n: String) -> void:
	if emitters.has(n):
		emitters[n].disable()


func _process(delta: float) -> void:
	if _ring_t < 0.0 or _ring == null:
		return
	_ring_t += delta
	var t := minf(_ring_t, ANIM_KEYS[-1][0])
	var k := 0
	while k < ANIM_KEYS.size() - 2 and t > ANIM_KEYS[k + 1][0]:
		k += 1
	var a: Array = ANIM_KEYS[k]
	var b: Array = ANIM_KEYS[k + 1]
	var f := clampf((t - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
	var pos: Vector3 = (a[1] as Vector3).lerp(b[1], f) * ANIM_POS_SCALE * Level.UNITS
	var qa := Quaternion(0, a[2], 0, a[3]).normalized()
	var qb := Quaternion(0, b[2], 0, b[3]).normalized()
	_ring.global_transform = _ring_base * Transform3D(Basis(qa.slerp(qb, f)), pos)


# ------------------------------------------------------------------ save provider (save_game.gd)

func save_key() -> String:
	return "flytrap"


func save_state() -> Dictionary:
	var got := []
	if "items" in events:
		for n in items:
			var tn := "flyTrapItem%dTrigger" % n
			if triggers.has(tn) and not triggers[tn].enabled:
				got.append(n)
	return {"activated": activated, "found_items": got}


# Activated: the ring and its voices are skipped, the items are out at once and the
# ones already found stay hidden.
func load_state(d: Dictionary) -> void:
	if not d.get("activated", false):
		return
	activated = true
	if triggers.has(TRIGGER):
		triggers[TRIGGER].enabled = false
	_set_up()
	found = 0
	for n in d.get("found_items", []):
		var i := int(n)
		var tn := "flyTrapItem%dTrigger" % i
		if triggers.has(tn):
			triggers[tn].enabled = false
		for o in items.get(i, []):
			o.visible = false
		found += 1


# A shootable trigger (layer RadioEggs.TRIGGER_LAYER: player.gd's RadioEggs.bullet finds it)
class Target extends StaticBody3D:
	var trigger_name := ""
	var owner_trap: FlyTrap
	var enabled := true

	func _ready() -> void:
		collision_layer = RadioEggs.TRIGGER_LAYER
		collision_mask = 0

	func trigger_damage(by: Player) -> void:
		if enabled:
			owner_trap.trigger(trigger_name, by)
