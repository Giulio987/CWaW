# A barricaded window zombies tear down and climb through.
# Entities carry no rotation for barricades, so the wall direction comes from
# the level geometry (tools/wall_yaw.py -> "wall_yaw"). Board states are the
# original one-keyframe barricade animations.
class_name Barricade
extends Node3D

const MAX_BOARDS := 5
# boards left -> pose animation of the barricade rig (5 = all boards up)
const STATES := ["36f9cc2c", "36f84bfa", "82c86d87", "65105051", "db3afd0f", "025059eb"]

var area := ""             # e.g. "startroom" from "startroomZombieWindow3"
var boards := MAX_BOARDS
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
	var path := "res://assets/characters/levels/%s/dynamics/fee7f210.glb" % level.level_name
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
	return true


func repair_board() -> bool:
	if boards >= MAX_BOARDS:
		return false
	boards += 1
	_update_boards()
	return true


func _update_boards() -> void:
	if _anim == null:
		return
	var a: String = STATES[clamp(boards, 0, MAX_BOARDS)]
	if _anim.has_animation(a):
		_anim.play(a)
		_anim.seek(0.0, true)
		_anim.pause()
