# Der Riese drawbridge between garageTop and labTop (entity "bridge": CIwColliderSpec,
# CTriggerInteractableASMSpec, model f4c2c6b2 rigged in characters/levels/derriese/dynamics).
# From derriese.lua and the bridge's CIsAnimStateMachine (f4c2c6b2):
#   state 0 (anim a0d800c1, both halves raised) -"genTurnOn"-> state 1 (c19aa5c3, the
#   halves come down, sound f4b8d41a, 4563 ms) -> state 2 (a0da1253, down: Lua signal
#   "bridgeClosed", sound 9180a3e8).
#   TurnOnGenerator: SetASMTrigger("bridge", "genTurnOn"), EnableParticles bridgeSteam1-4,
#   Timeout(7500, "TurnOffSteam").
#   Signal "bridgeClosed": ActivateCollisionMesh("col_Link_pC_pC"),
#   ActivateNavigationMesh("nav_Link_pC_pC"), SetLinkUnlocked("Link_pC_pC").
# The walkway collision is the original col_Link_pC_pC (CIwNavMesh, environment group):
# a 8.5 x 3.75 m deck sloping from labTop down to garageTop plus two kerbs. Until the
# bridge is down an invisible wall closes each end of the gap.
class_name Bridge
extends Node3D

const ENTITY := "bridge"
const MODEL := "f4c2c6b2"
const ANIM_UP := "a0d800c1"
const ANIM_LOWER := "c19aa5c3"
const ANIM_DOWN := "a0da1253"
const LOWER_TIME := 4.563          # ASM state 1
const SND_LOWER := "f4b8d41a"
const SND_DOWN := "9180a3e8"
const STEAM := ["bridgeSteam1", "bridgeSteam2", "bridgeSteam3", "bridgeSteam4"]
const STEAM_TIME := 7.5            # Timeout(7500, "TurnOffSteam")
# bridgeSteam1-4 use the effects-group spec list 1061589f: CIwGFXEmitterSpec (Serialise
# kiwi 0x11c358; iw_emitter.gd): texture b8975a67, flags 10 (bit 3: fade out), emission
# time -1 (loops until DisableParticles), spawn box (-8,40,0)-(8,55,80) units, velocity
# field (-300,50,300)-(300,800,2200) x 1000/4096 = (-73..73, 12..195, 73..537) units/s along
# the entity's local +z, which the transform flags turn into the gap (0x14 at the garage
# end -> +x, 0x10 at the lab end -> -x), lifetime 1500-3000 ms, a new particle every
# 55-150 ms (0x80), start size 65-150 units centre to corner (0x68), growth 0x88 = 500
# (+0.3 m/s), spin 0-88 deg/s (0x70). No gravity, no damping.
const STEAM_TEX := "b8975a67"
const STEAM_EVERY := [55.0, 150.0]          # ms
const STEAM_LIFE := [1500.0, 3000.0]        # ms
const STEAM_BOX := [Vector3(-8, 40, 0), Vector3(8, 55, 80)]
const STEAM_VEL := [Vector3(-300, 50, 300), Vector3(300, 800, 2200)]
const STEAM_SIZE := [65.0, 150.0]
const STEAM_GROW := 500.0
const STEAM_SPIN := [0.0, 88.0]
const STEAM_COLOR := Color(0.85, 0.85, 0.85, 0.45)   # not decoded (no material): estimated
# col_Link_pC_pC: s32 vertices (entity units) and triangles
const COL_VERTS := [
	[-4793, 2530, -12029], [-4793, 2534, -13527], [-1386, 2066, -13527], [-1386, 2066, -12029],
	[-4793, 2669, -13527], [-4793, 2669, -13589], [-1480, 2197, -13613], [-1386, 2197, -13527],
	[-1536, 2201, -11892], [-4793, 2665, -11941], [-4793, 2665, -12029], [-1386, 2201, -12029]]
const COL_TRIS := [[0, 1, 2], [0, 2, 3], [4, 5, 6], [4, 6, 7], [8, 9, 10], [8, 10, 11]]
const WALL_HEIGHT := 2.0
const MODEL_YAW := 90.0   # the exported rig lies along z; col_Link_pC_pC (and the gap) run along x

signal closed

var level: Level
var lowered := false      # "bridgeClosed" received
var _anim: AnimationPlayer
var _model: Node3D
var _deck: StaticBody3D
var _ends: StaticBody3D
var _steam := []


static func create(level_: Level) -> Bridge:
	if not level_.has_entity(ENTITY):
		return null
	var b := Bridge.new()
	b.name = "Bridge"
	b.level = level_
	level_.nav_region.add_child(b)
	b._build()
	return b


func _build() -> void:
	# the model hangs off the entity's child frame (renderable at -16, 4, -31 units)
	global_transform = level.entity_transform(ENTITY, true)
	_model = level.dynamics_model(MODEL)
	if _model:
		add_child(_model)
		_model.rotation_degrees.y = MODEL_YAW
		var aps := _model.find_children("*", "AnimationPlayer")
		_anim = aps[0] if not aps.is_empty() else null
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pose(ANIM_UP)
	_build_ends()
	for n in STEAM:
		if level.has_entity(n):
			var p := IwEmitter.make(IwEmitter.from_spec(STEAM_TEX, false, -1.0, STEAM_EVERY,
				STEAM_LIFE, STEAM_BOX, STEAM_VEL, STEAM_SIZE, STEAM_GROW, STEAM_SPIN, STEAM_COLOR))
			level.nav_region.add_child(p)
			# the flags hold the emitter's quarter turn (Level.flag_transform)
			p.global_transform = Level.flag_transform(level.entity(n)["transform"])
			_steam.append(p)
	level.power_changed.connect(func(on: bool): if on: lower())
	if level.power_on:
		lower(true)


func _pose(a: String) -> void:
	if _anim and _anim.has_animation(a):
		_anim.play(a)
		_anim.seek(0.0, true)
		_anim.pause()


# ASM "genTurnOn": the halves come down over LOWER_TIME, then "bridgeClosed"
func lower(instant := false) -> void:
	if lowered or (_anim and _anim.current_animation == ANIM_LOWER and _anim.is_playing()):
		return
	if instant:
		_pose(ANIM_DOWN)
		_close(true)
		return
	for p in _steam:
		p.start()
	get_tree().create_timer(STEAM_TIME, false).timeout.connect(func():
		for p in _steam:
			p.stop())
	if _anim and _anim.has_animation(ANIM_LOWER):
		_anim.play(ANIM_LOWER)
		_anim.speed_scale = _anim.get_animation(ANIM_LOWER).length / LOWER_TIME
	Sfx.instance.play_at(SND_LOWER, global_position + Vector3.UP)
	get_tree().create_timer(LOWER_TIME, false).timeout.connect(_close)


# Signal "bridgeClosed": walkway collision on, the link between garageTop and labTop opens
func _close(silent := false) -> void:
	if lowered:
		return
	lowered = true
	if _anim:
		_anim.speed_scale = 1.0
	_pose(ANIM_DOWN)
	if not silent:
		Sfx.instance.play_at(SND_DOWN, global_position + Vector3.UP)
	_build_deck()
	if _ends:
		_ends.queue_free()
		_ends = null
	closed.emit()
	await get_tree().physics_frame
	await get_tree().physics_frame
	level.bake_navigation()


static func _v(i: int) -> Vector3:
	var a: Array = COL_VERTS[i]
	return Vector3(a[0], a[1], a[2]) * Level.UNITS


func _build_deck() -> void:
	var faces := PackedVector3Array()
	for t in COL_TRIS:
		for i in t:
			faces.append(_v(i))
	# the original keeps the player on its navmesh: the long edges are walls
	for e in [[1, 2], [3, 0]]:
		_add_wall(faces, _v(e[0]), _v(e[1]))
	_deck = _body(faces)
	_deck.name = "BridgeDeck"


# Invisible walls across both ends of the gap while the bridge is up.
func _build_ends() -> void:
	var faces := PackedVector3Array()
	for e in [[0, 1], [2, 3]]:
		_add_wall(faces, _v(e[0]), _v(e[1]))
	_ends = _body(faces)
	_ends.name = "BridgeGapWalls"


static func _add_wall(faces: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var up := Vector3.UP * WALL_HEIGHT
	faces.append_array([a, b, b + up, a, b + up, a + up])


func _body(faces: PackedVector3Array) -> StaticBody3D:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	level.nav_region.add_child(body)
	return body
