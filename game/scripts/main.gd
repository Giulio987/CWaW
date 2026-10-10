# Entry point. Command line: -- [level] [--autotest seconds]
extends Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level := ""
	for a in args:
		if not a.begins_with("--") and not a.is_valid_float() and not "," in a and not a in Weapons.STATS:
			level = a
	if level == "":
		_show_menu(args.has("--menu-shot"))
		return
	_start(level, args)


func _show_menu(screenshot: bool) -> void:
	var menu := Menu.new()
	add_child(menu)
	menu.play.connect(func(l: String):
		menu.queue_free()
		_start(l, PackedStringArray()))
	if screenshot:
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/menu.png"))
		get_tree().quit()


func _start(level: String, args: PackedStringArray) -> void:
	var game := Game.new()
	add_child(game)
	game.start(level)
	var look := args.find("--look")
	if look >= 0:
		_look_shots(game, args[look + 1].split(","))
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


# Screenshot entities from 3 m away on the player's side: -- nacht --look startroomZombieWindow1,DoorTrigger
func _look_shots(game: Game, names: PackedStringArray) -> void:
	for i in 6:
		await get_tree().physics_frame
	for n in names:
		var target := game.level.entity_transform(n).origin + Vector3.UP * 1.0
		var from := game.level.player_spawn.origin
		for w in game.level.windows:
			if w.name == n:
				from = w.inside + (w.inside - w.global_position).normalized() * 2.0
		var dir := (target - from)
		dir.y = 0
		from = target - dir.normalized() * 3.0
		game.player.global_position = Vector3(from.x, target.y - 1.0, from.z)
		game.player.rotation.y = atan2(-dir.x, -dir.z)
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/look_%s.png" % n))
	get_tree().quit()
