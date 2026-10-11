# Render each mesh part of a character alone: <glb> <outdir>
extends SceneTree

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var root: Node3D = (load(a[0]) as PackedScene).instantiate()
	get_root().add_child(root)
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(1.6, 1.4, 2.4), Vector3(0, 1.1, 0))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	get_root().add_child(env)
	var parts := root.find_children("*", "MeshInstance3D")
	for target in parts:
		for mi in parts:
			mi.visible = mi == target
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/%s.png" % [a[1], target.name])
	quit()
