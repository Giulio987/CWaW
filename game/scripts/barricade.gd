# A barricaded window zombies tear down and climb through.
# Entities carry no rotation for barricades, so the wall direction comes from
# the level geometry (tools/wall_yaw.py -> "wall_yaw"). Board states are the
# original one-keyframe barricade animations.
class_name Barricade
extends Node3D

const MAX_BOARDS := 5
# boards left -> pose animation of the barricade rig (5 = all boards up)
const STATES := ["36f9cc2c", "36f84bfa", "82c86d87", "65105051", "db3afd0f", "025059eb"]
# Barricades with their own rig (model of the CBarricadeSpec entity instead of fee7f210):
# Nacht mysteryboxroomZombieWindow3 4b84e4d2 and Verrückt AmericanDown2/AmericanUp1/
# GermanUp1ZombieWindow1 4a7f842b / 9a6665e4 / 9a707fea (same 7-bone skeleton aae9b3f6,
# Verrückt's own copies of the animations). Their ASM 4b84e4d2 (nacht/verruckt dynamics)
# has board states "0".."6" (6 boards), break transitions with sound 43dd4a39 and repairs
# with e3f3e537 (fee7f210: 1a3da352 window_break1 / 3eaaf6ff window_repair).
const ALT_RIGS := ["4b84e4d2", "4a7f842b", "9a6665e4", "9a707fea"]
const ALT_STATES := ["1c98e674", "1624e62f", "165b2fb2", "1636feb0", "167f60b4", "166d4833", "16491731"]

var area := ""             # e.g. "startroom" from "startroomZombieWindow3"
var max_boards := MAX_BOARDS   # 6 on the ALT_RIGS barricades
var boards := MAX_BOARDS
var rig := "fee7f210"
var break_sound := "window_break1"
var repair_sound := "window_repair"   # player.gd plays it on a repair
var inside := Vector3.ZERO  # standing point inside the room
var outside := Vector3.ZERO # standing point outside
var normal := Vector3.FORWARD
var occupied_by: Node = null
var _anim: AnimationPlayer
var _blocker: StaticBody3D


func setup(level: Level, entity: String) -> void:
	var i := entity.to_lower().find("zombie")
	area = entity.substr(0, i).to_lower() if i > 0 else ""
	var e: Dictionary = level.entities[entity]
	var yaw: float = e.get("wall_yaw", 0.0)
	var root := level.entity_transform(entity)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), root.origin)
	normal = global_basis.z
	var own: String = e["models"][0] if not e["models"].is_empty() else rig
	if own in ALT_RIGS and ResourceLoader.exists("res://assets/characters/levels/%s/dynamics/%s.glb" % [level.level_name, own]):
		rig = own
		max_boards = ALT_STATES.size() - 1
		boards = max_boards
		break_sound = "43dd4a39"
		repair_sound = "e3f3e537"
	var path := "res://assets/characters/levels/%s/dynamics/%s.glb" % [level.level_name, rig]
	if ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate()
		add_child(model)
		if not e["children"].is_empty():
			var p: Array = e["children"][-1]["pos"]
			model.position = Vector3(p[0], p[1], p[2]) * Level.UNITS
		var aps := model.find_children("*", "AnimationPlayer")
		_anim = aps[0] if aps.size() > 0 else null


# Called after level collision exists and before navigation is baked.
func finalize(level, room_hint: Vector3) -> void:
	# inside = the side that lies in a room sector; the measured wall normal can be
	# off by 90 degrees, so both axes are tried
	inside = Vector3.ZERO
	for axis: Vector3 in [normal, normal.rotated(Vector3.UP, PI / 2)]:
		var a: Vector3 = global_position + axis * 1.1 + Vector3.UP
		var b: Vector3 = global_position - axis * 1.1 + Vector3.UP
		if level.is_indoors(a) != level.is_indoors(b):
			inside = (a if level.is_indoors(a) else b) - Vector3.UP
			outside = (b if level.is_indoors(a) else a) - Vector3.UP
			normal = axis
			break
	if inside == Vector3.ZERO:
		# no sector information: fall back to the side closer to the room
		var a: Vector3 = global_position + normal * 1.1
		var b: Vector3 = global_position - normal * 1.1
		inside = a if a.distance_to(room_hint) < b.distance_to(room_hint) else b
		outside = b if inside == a else a
	# boards and blocker follow the axis that actually crosses the wall
	global_transform = Transform3D(Basis(Vector3.UP, atan2(normal.x, normal.z)), global_position)
	# invisible blocker in the opening: keeps the player in and splits the navmesh
	_blocker = StaticBody3D.new()
	_blocker.collision_layer = 4  # blocks bodies (player, zombies) but not bullets or the navmesh-free sight lines
	_blocker.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.6, 0.3)
	shape.shape = box
	_blocker.add_child(shape)
	add_child(_blocker)
	_blocker.position = Vector3(0, 1.3, 0)
	_update_boards()


func tear_board() -> bool:
	if boards <= 0:
		return false
	boards -= 1
	_update_boards()
	Sfx.instance.play_at(break_sound, global_position)
	return true


func repair_board() -> bool:
	if boards >= max_boards:
		return false
	boards += 1
	_update_boards()
	return true


func _update_boards() -> void:
	if _anim == null:
		return
	var st: Array = ALT_STATES if rig != "fee7f210" else STATES
	var a: String = st[clamp(boards, 0, max_boards)]
	if _anim.has_animation(a):
		_anim.play(a)
		_anim.seek(0.0, true)
		_anim.pause()


# ------------------------------------------------------------------ Carpenter (radial_effect.gd)
# CRadialEffectCarpenter (kiwi va 0x1cd72c) fires the barricade state machine event
# "repairAll" (CBarricade va 0xfc594, state set up at 0xfc238). Only Der Riese's barricade
# ASM fee7f210 has that state (the original offers the Carpenter only there): animation
# 68af85c2 (the "last board back" clip, 1.75 s: the other four boards already up, board 3
# flies in) at speed 0x999/4096 = 0.6 -> 2917 ms, sound 27be06a0 (1.16 s); then the
# full-boards pose. The other barricade rigs' "last board back" clips are listed after it
# (Shi No Numa b35a1649 / 6e451bb7; ALT_RIGS 4b84e4d2: e1f91cfe, state 7c7c1b93 5 -> 6 boards):
# the remake uses the same state on
# every map (the Carpenter stays on all of them), with the same speed (estimated there).
const REPAIR_ALL_ANIMS := ["68af85c2", "a7a967f8", "a7a96a29", "e1f91cfe"]
const REPAIR_ALL_SPEED := 2457.0 / 4096.0
const REPAIR_ALL_SOUND := "27be06a0"
var _repair_all_token := 0


# true when the barricade needed it (some board missing)
func carpenter_repair() -> bool:
	if boards >= max_boards:
		return false
	boards = max_boards
	Sfx.instance.play_at(REPAIR_ALL_SOUND, global_position + Vector3.UP)
	var clip := ""
	if _anim:
		for a in REPAIR_ALL_ANIMS:
			if _anim.has_animation(a):
				clip = a
				break
	if clip == "":
		_update_boards()
		return true
	_repair_all_token += 1
	var token := _repair_all_token
	_anim.play(clip, 0.0, REPAIR_ALL_SPEED)
	_anim.seek(0.0, true)
	var length := _anim.get_animation(clip).length / REPAIR_ALL_SPEED
	get_tree().create_timer(length, false).timeout.connect(func():
		if is_instance_valid(self) and token == _repair_all_token:
			_update_boards())   # the pose of the boards there are by then
	return true
