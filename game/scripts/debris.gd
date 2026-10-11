# Debris/door bought with points to open the way to another area.
# The model is shown in its "closed" one-keyframe pose and plays the opening
# animation when bought. Entities carry no rotation, so the model is turned to
# the wall-aligned yaw that best fits the entity's own collider box.
class_name Debris
extends Node3D

signal opened(debris: Debris)

const JUMP_GUARD := 2.5  # metres added above the original volume

var cost := 1000
var entity := ""
var _body: StaticBody3D
var _anim: AnimationPlayer
var _closed := ""
var _opening := ""


func setup(level: Level, name_: String) -> void:
	entity = name_
	var e: Dictionary = level.entities[name_]
	cost = int(e["params"].get("cost", 1000))
	# rotation fitted to the entity's collider box (tools/wall_yaw.py), else the wall direction
	var yaw: float = e.get("debris_yaw", e.get("wall_yaw", 0.0))
	var extra := OS.get_cmdline_user_args().find("--debris-yaw-add")
	if extra >= 0:
		yaw += deg_to_rad(float(OS.get_cmdline_user_args()[extra + 1]))
	var root := level.entity_transform(name_)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), root.origin)
	_body = StaticBody3D.new()
	add_child(_body)
	for h in e["models"]:
		var path := "res://assets/characters/levels/%s/dynamics/%s.glb" % [level.level_name, h]
		if not ResourceLoader.exists(path):
			continue
		var model: Node3D = (load(path) as PackedScene).instantiate()
		_body.add_child(model)
		if not e["children"].is_empty():
			var p: Array = e["children"][-1]["pos"]
			model.position = Vector3(p[0], p[1], p[2]) * Level.UNITS
		var aps := model.find_children("*", "AnimationPlayer")
		if aps.size() > 0:
			_anim = aps[0]
			_pick_animations()
			var forced := OS.get_cmdline_user_args().find("--debris-pose")
			if forced >= 0 and _anim.has_animation(OS.get_cmdline_user_args()[forced + 1]):
				_closed = OS.get_cmdline_user_args()[forced + 1]
			if _closed != "":
				_anim.play(_closed)
				_anim.seek(0.0, true)
				_anim.pause()
	# the entity's own collision volume (CIwColliderSpec) blocks the whole passage;
	# it is world aligned (entities carry no rotation) and raised so it cannot be jumped
	for c in e.get("colliders", []):
		var lo := Vector3(c["min"][0], c["min"][1], c["min"][2]) * Level.UNITS
		var hi := Vector3(c["max"][0], c["max"][1], c["max"][2]) * Level.UNITS + Vector3.UP * JUMP_GUARD
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (hi - lo).max(Vector3(0.2, 0.2, 0.2))
		shape.shape = box
		_body.add_child(shape)
		shape.global_transform = Transform3D(Basis(), root.origin + (lo + hi) / 2)


# The rigs have a closed pose (1 key), an opening animation (many keys) and an
# open pose (1 key). The closed pose is the single-key one matching the first
# frame of the opening animation.
func _pick_animations() -> void:
	var longest := 0.0
	var poses := []
	for a in _anim.get_animation_list():
		var anim := _anim.get_animation(a)
		var keys := 0
		for t in anim.get_track_count():
			keys = max(keys, anim.track_get_key_count(t))
		if keys <= 1:
			poses.append(a)  # single-key pose (its imported length is not 0)
		elif anim.length > longest:
			longest = anim.length
			_opening = a
	if _opening == "" or poses.is_empty():
		_closed = poses[0] if poses.size() > 0 else ""
		return
	var open_anim := _anim.get_animation(_opening)
	var best := INF
	for p in poses:
		var pose := _anim.get_animation(p)
		var d := 0.0
		for t in pose.get_track_count():
			var ot := open_anim.find_track(pose.track_get_path(t), pose.track_get_type(t))
			if ot < 0 or pose.track_get_key_count(t) == 0:
				continue
			match pose.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					d += (pose.track_get_key_value(t, 0) as Quaternion).angle_to(open_anim.rotation_track_interpolate(ot, 0.0))
				Animation.TYPE_POSITION_3D:
					d += (pose.track_get_key_value(t, 0) as Vector3).distance_to(open_anim.position_track_interpolate(ot, 0.0))
		if d < best:
			best = d
			_closed = p


func interact_position() -> Vector3:
	return global_position


func open() -> void:
	opened.emit(self)
	for c in _body.get_children():
		if c is CollisionShape3D:
			c.queue_free()
	if _anim and _opening != "":
		_anim.play(_opening)
		get_tree().create_timer(_anim.get_animation(_opening).length + 0.5).timeout.connect(queue_free)
	else:
		queue_free()
