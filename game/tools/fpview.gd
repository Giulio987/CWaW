# Render arms + weapon viewmodels posed by a pair of animations, from the eye.
# godot --path game -s res://tools/fpview.gd -- <weapon_model> <weapon_anim> <arms_anim> <time> <out.png>
extends SceneTree

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new()
	get_root().add_child(root)
	for pair in [[a[0], a[1]], ["7c9433b8", a[2]]]:
		var m: Node3D = (load("res://assets/characters/ingame/player/%s.glb" % pair[0]) as PackedScene).instantiate()
		root.add_child(m)
		var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer")[0]
		if ap.has_animation(pair[1]):
			ap.play(pair[1])
			ap.seek(float(a[3]), true)
			ap.pause()
		else:
			print("missing anim ", pair[1])
	var cam := Camera3D.new()
	cam.fov = 65
	cam.near = 0.01
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3.ZERO, Vector3(0, 0, 1))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	get_root().add_child(env)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(a[4])
	quit()
