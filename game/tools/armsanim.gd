# First-person frames of arms animations: <out_dir> <anim,...> <frames>
extends SceneTree

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var arms: Node3D = (load("res://assets/characters/ingame/player/7c9433b8.glb") as PackedScene).instantiate()
	get_root().add_child(arms)
	var ap: AnimationPlayer = arms.find_children("*", "AnimationPlayer")[0]
	# knife (world model) on the weapon tag bone
	var skel: Skeleton3D = arms.find_children("*", "Skeleton3D")[0]
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_idx = 22
	var player_models: Node = (load("res://assets/models/ingame/player.glb") as PackedScene).instantiate()
	var knife: Node3D = player_models.find_child("78d2d941", true, false)
	if knife:
		knife.get_parent().remove_child(knife)
		knife.transform = Transform3D.IDENTITY
		att.add_child(knife)
	var cam := Camera3D.new()
	cam.fov = 70
	cam.near = 0.01
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, -0.05), Vector3(0, 0, 1))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	get_root().add_child(env)
	var n := int(a[2])
	for name in a[1].split(","):
		ap.play(name)
		var length := ap.get_animation(name).length
		for f in n:
			ap.seek(length * f / max(n - 1, 1), true)
			ap.pause()
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/%s_%d.png" % [a[0], name, f])
	quit()
