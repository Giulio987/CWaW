# Debris/door bought with points to open the way to another area.
class_name Debris
extends Node3D

signal opened(debris: Debris)

var cost := 1000
var entity := ""
var _body: StaticBody3D


func setup(level: Level, name_: String) -> void:
	entity = name_
	var e: Dictionary = level.entities[name_]
	cost = int(e["params"].get("cost", 1000))
	global_transform = level.entity_transform(name_)
	_body = StaticBody3D.new()
	add_child(_body)
	for h in e["models"]:
		var path := "res://assets/characters/levels/%s/dynamics/%s.glb" % [level.level_name, h]
		if not ResourceLoader.exists(path):
			continue
		var model: Node3D = (load(path) as PackedScene).instantiate()
		_body.add_child(model)
		model.global_transform = level.entity_transform(name_, true)
		for mi in model.find_children("*", "MeshInstance3D"):
			var aabb: AABB = mi.get_aabb()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = aabb.size.max(Vector3(0.2, 0.2, 0.2))
			shape.shape = box
			_body.add_child(shape)
			shape.global_transform = mi.global_transform * Transform3D(Basis(), aabb.get_center())


func interact_position() -> Vector3:
	return global_position


func open() -> void:
	opened.emit(self)
	queue_free()
