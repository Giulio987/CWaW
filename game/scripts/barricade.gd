# A barricaded window zombies tear down and climb through.
# The wall normal is not stored in the entity, so it is found with ray casts
# once collision exists (finalize()).
class_name Barricade
extends Node3D

const MAX_BOARDS := 6

var area := ""             # e.g. "startroom" from "startroomZombieWindow3"
var boards := MAX_BOARDS
var inside := Vector3.ZERO  # standing point inside the room
var outside := Vector3.ZERO # standing point outside
var occupied_by: Node = null
var _skeleton: Skeleton3D
var _blocker: StaticBody3D


func setup(level: Level, entity: String) -> void:
	var i := entity.find("Zombie")
	area = entity.substr(0, i).to_lower() if i > 0 else ""
	global_transform = Transform3D(Basis(), level.entity_transform(entity).origin)
	var path := "res://assets/characters/levels/%s/dynamics/fee7f210.glb" % level.level_name
	if ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate()
		add_child(model)
		model.global_transform = level.entity_transform(entity, true)
		_skeleton = model.find_children("*", "Skeleton3D")[0] if model.find_children("*", "Skeleton3D").size() > 0 else null


# Called after level collision exists and before navigation is baked.
func finalize(space: PhysicsDirectSpaceState3D, room_hint: Vector3) -> void:
	var c := global_position + Vector3.UP * 1.2
	var best_dir := Vector3.FORWARD
	var best_free := -1.0
	for step in 24:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, PI * step / 24.0)
		var free := _free(space, c, dir) + _free(space, c, -dir)
		if free > best_free:
			best_free = free
			best_dir = dir
	var a := global_position + best_dir * 1.1
	var b := global_position - best_dir * 1.1
	if a.distance_to(room_hint) < b.distance_to(room_hint):
		inside = a
		outside = b
	else:
		inside = b
		outside = a
	# invisible blocker in the opening: keeps the player in and splits the navmesh
	_blocker = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.6, 0.3)
	shape.shape = box
	_blocker.add_child(shape)
	add_child(_blocker)
	_blocker.global_transform = Transform3D(Basis.looking_at(best_dir), global_position + Vector3.UP * 1.3)
	_update_boards()


func _free(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4.0)
	var hit := space.intersect_ray(q)
	return 4.0 if hit.is_empty() else from.distance_to(hit["position"])


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
	if _skeleton == null:
		return
	# one bone per board (bone 0 is the root)
	for bi in range(1, _skeleton.get_bone_count()):
		var visible := bi <= boards
		_skeleton.set_bone_pose_scale(bi, Vector3.ONE if visible else Vector3.ZERO)
