# Render a .glb to a PNG and quit.
# godot --path game -s res://tools/preview.gd -- <res://model.glb> <out.png> [yaw_deg] [pitch_deg] [dist_mul] [node|*] [anim_index] [time]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: PackedScene = load(args[0])
	var root := scene.instantiate()
	if args.size() > 5 and args[5] != "*":
		for c in root.get_children():
			c.visible = c.name == args[5]
	get_root().add_child(root)
	if args.size() > 7:
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer")[0]
		var names := ap.get_animation_list()
		var a := names[int(args[6]) % names.size()]
		print("anims ", names.size(), " playing ", a, " len ", ap.get_animation(a).length)
		ap.play(a)
		ap.seek(float(args[7]), true)
		ap.pause()
	var aabb := _aabb(root, Transform3D.IDENTITY)
	var yaw := deg_to_rad(float(args[2])) if args.size() > 2 else 0.6
	var pitch := deg_to_rad(float(args[3])) if args.size() > 3 else -0.4
	var dist := (float(args[4]) if args.size() > 4 else 1.2) * aabb.size.length()
	var cam := Camera3D.new()
	cam.far = dist * 4.0
	get_root().add_child(cam)
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	cam.look_at_from_position(aabb.get_center() + dir * dist, aabb.get_center())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	get_root().add_child(env)
	print("aabb ", aabb)
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[1])
	quit()

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is VisualInstance3D and n.visible:
		out = t * (n as VisualInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		if c is Node3D and not c.visible:
			continue
		var a := _aabb(c, t)
		if a.size != Vector3.ZERO:
			out = a if first else out.merge(a)
			first = false
	return out
