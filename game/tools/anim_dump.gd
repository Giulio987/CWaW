# Print every animation of a rigged .glb: length, key count, and per track the
# start->end displacement of position tracks (root motion candidates).
# godot --headless --path game -s res://tools/anim_dump.gd -- res://model.glb
extends SceneTree

func _initialize() -> void:
	var root: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	get_root().add_child(root)
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer")[0]
	var skel: Skeleton3D = root.find_children("*", "Skeleton3D")[0]
	print("bones ", skel.get_bone_count(), " root ", skel.get_bone_name(0))
	for m in root.find_children("*", "MeshInstance3D"):
		print("mesh ", m.name, " ", m.get_aabb())
	for a in ap.get_animation_list():
		var anim := ap.get_animation(a)
		var keys := 0
		var info := []
		for t in anim.get_track_count():
			keys = max(keys, anim.track_get_key_count(t))
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and anim.track_get_key_count(t) > 0:
				var p0: Vector3 = anim.track_get_key_value(t, 0)
				var p1: Vector3 = anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
				var path := String(anim.track_get_path(t))
				if (p1 - p0).length() > 0.05 or path.ends_with(skel.get_bone_name(0)):
					info.append("%s d=%s y0=%.2f" % [path.get_slice(":", 1), (p1 - p0).snapped(Vector3(0.01, 0.01, 0.01)), p0.y])
		print("%s len=%.2f keys=%d tracks=%d %s" % [a, anim.length, keys, anim.get_track_count(), info])
	quit()
