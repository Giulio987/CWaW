# Entry point. Command line: -- [level] [--autotest seconds]
extends Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level := "nacht"
	for a in args:
		if not a.begins_with("--") and not a.is_valid_float() and not "," in a and not a in Weapons.STATS:
			level = a
	var game := Game.new()
	add_child(game)
	game.start(level)
	var shots := args.find("--shots")
	if shots >= 0:
		_weapon_shots(game, args[shots + 1].split(","))
	var i := args.find("--autotest")
	if i >= 0:
		var t := AutoTest.new()
		t.duration = float(args[i + 1]) if args.size() > i + 1 else 60.0
		t.game = game
		add_child(t)


# Screenshot each listed weapon held in first person: -- nacht --shots colt45,kar98
func _weapon_shots(game: Game, names: PackedStringArray) -> void:
	for i in 6:
		await get_tree().physics_frame
	for n in names:
		game.player.give_weapon(n)
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/wpn_%s.png" % n))
	get_tree().quit()
