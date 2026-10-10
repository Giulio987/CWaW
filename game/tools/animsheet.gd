# Render frames of named animations into PNGs: <glb> <outdir> <anim1,anim2,...> <frames>
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var root: Node3D = (load(args[0]) as PackedScene).instantiate()
	get_root().add_child(root)
	for mi in root.find_children("*", "MeshInstance3D"):
		mi.visible = not (mi.name in ["headb", "980daf40"] or mi.name.ends_with("_m1"))
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer")[0]
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(2.2, 1.4, 2.2), Vector3(0, 0.7, 0))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	get_root().add_child(env)
	var n := int(args[3])
	for a in args[2].split(","):
		ap.play(a)
		var length := ap.get_animation(a).length
		for f in n:
			ap.seek(length * f / max(n - 1, 1), true)
			ap.pause()
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/%s_%d.png" % [args[1], a, f])
	quit()
