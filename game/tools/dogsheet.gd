# Contact sheet of every animation of a rigged glb seen from the side (+X):
# one row per animation, <frames> columns, a red marker 1 m along +Z.
# godot --path game -s res://tools/dogsheet.gd -- <glb> <out_prefix> [frames] [rows_per_sheet]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var root: Node3D = (load(args[0]) as PackedScene).instantiate()
	get_root().add_child(root)
	var frames := int(args[2]) if args.size() > 2 else 4
	var rows := int(args[3]) if args.size() > 3 else 10
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer")[0]
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(2.6, 0.7, 0.4), Vector3(0, 0.45, 0.4))
	var marker := MeshInstance3D.new()
	marker.mesh = BoxMesh.new()
	(marker.mesh as BoxMesh).size = Vector3(0.1, 0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	marker.position = Vector3(0, 0, 1.0)
	get_root().add_child(marker)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	get_root().add_child(env)
	cam.current = true
	var names := ap.get_animation_list()
	var sheet: Image = null
	var row := 0
	var sheet_no := 0
	for a in names:
		if sheet == null:
			sheet = Image.create(320 * frames, 200 * rows, false, Image.FORMAT_RGBA8)
		ap.play(a)
		var length := ap.get_animation(a).length
		for f in frames:
			ap.seek(length * f / max(frames - 1, 1), true)
			ap.pause()
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := get_root().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(320, 200)
			sheet.blit_rect(img, Rect2i(0, 0, 320, 200), Vector2i(320 * f, 200 * row))
		print("sheet %d row %d: %s" % [sheet_no, row, a])
		row += 1
		if row == rows or a == names[-1]:
			sheet.save_png("%s_%d.png" % [args[1], sheet_no])
			sheet = null
			row = 0
			sheet_no += 1
	quit()
