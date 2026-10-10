# Render the first frame of each listed animation of a glb from the front (+Z), one PNG each.
# godot --path game -s res://tools/animsheet2.gd -- <glb> <outdir> <a1,a2,...> [time_fraction]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var root: Node3D = (load(args[0]) as PackedScene).instantiate()
	get_root().add_child(root)
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer")[0]
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(0.6, 1.2, 3.2), Vector3(0, 1.0, 0))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	get_root().add_child(env)
	var frac := float(args[3]) if args.size() > 3 else 0.0
	for a in args[2].split(","):
		if ap.has_animation(a):
			ap.play(a)
			ap.seek(ap.get_animation(a).length * frac, true)
			ap.pause()
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/%s.png" % [args[1], a])
	quit()
