# Render a character with only the listed parts visible.
# godot --path game -s res://tools/parts.gd -- <glb> <out.png> <comma-separated hidden parts> [anim] [time]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var root: Node3D = (load(args[0]) as PackedScene).instantiate()
	get_root().add_child(root)
	var hidden := args[2].split(",")
	for mi in root.find_children("*", "MeshInstance3D"):
		var nm: String = mi.name
		var hide := nm in hidden or nm.ends_with("_m1")
		mi.visible = not hide
		print(nm, " visible=", mi.visible)
	if args.size() > 4:
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer")[0]
		ap.play(ap.get_animation_list()[int(args[3])])
		ap.seek(float(args[4]), true)
		ap.pause()
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(1.2, 1.3, 2.6), Vector3(0, 0.9, 0))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	get_root().add_child(env)
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[1])
	quit()
