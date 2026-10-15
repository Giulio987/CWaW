# "Ghost while strafing" check: -- <map> --ghost-test [left|right] [--view "x,y,z,yaw,pitch"]
# Holds the strafe key and saves consecutive frames (analysis/preview/ghost_<n>.png) plus a
# log line per frame with the camera and the viewmodel positions, to spot doubled images.
extends Node

var game: Game


static func start(main: Node, game_: Game, args: PackedStringArray) -> void:
	var t = load("res://scripts/ghost_tests.gd").new()
	t.game = game_
	main.add_child(t)
	var i := args.find("--ghost-test")
	var side := args[i + 1] if i + 1 < args.size() and args[i + 1] in ["left", "right"] else "right"
	t._run(side)


func _run(side: String) -> void:
	await game.level.wait_navigation()
	for i in 200:   # the HUD and the first round
		if game.round_number >= 1 and game.hud:
			break
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(1.5).timeout
	var p := game.player
	var cam := get_viewport().get_camera_3d()
	var action := "move_right" if side == "right" else "move_left"
	Input.action_press(action)
	await get_tree().create_timer(0.4).timeout
	var shots := 24
	var imgs: Array[Image] = []
	var log := []
	var xs: Array[Vector3] = []
	for n in shots:   # kept in memory: saving every frame would slow the game down
		await RenderingServer.frame_post_draw
		imgs.append(get_viewport().get_texture().get_image())
		xs.append(cam.global_position)
		log.append("[ghost] %d frame %d phys %d player %s cam %s vm %s" % [n, Engine.get_frames_drawn(),
			Engine.get_physics_frames(), p.global_position.snapped(Vector3.ONE * 0.001),
			cam.global_position.snapped(Vector3.ONE * 0.001), p._viewmodel.global_position.snapped(Vector3.ONE * 0.001)])
	for n in shots:
		imgs[n].save_png(ProjectSettings.globalize_path("res://../analysis/preview/ghost_%d.png" % n))
		print(log[n])
	# camera step per drawn frame: even steps = smooth; 0 / 2x alternating = the stop-and-go
	# that looks like a doubled image on a screen faster than the physics rate
	var steps := []
	for n in range(1, shots):
		steps.append(xs[n].distance_to(xs[n - 1]))
	var lo: float = steps.min()
	var hi: float = steps.max()
	print("[ghost] camera step per frame: min %.4f max %.4f m (%d fps, %d physics ticks/s)" % [lo, hi,
		Engine.get_frames_per_second(), Engine.physics_ticks_per_second])
	print("[ghost] RESULT %s" % ("OK" if hi > 0.0 and lo > hi * 0.5 else "FAIL (uneven camera steps)"))
	Input.action_release(action)
	get_tree().quit()
