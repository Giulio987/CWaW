# Front-end checks (prints OK/FAIL, screenshots analysis/preview/frontend_*.png):
#   -- --frontend-test intro          splash logos + intro video, skipped by key presses, then the menu
#   -- --frontend-test menu           menu (music, map text), help/leaderboards/credits/about pages,
#                                     options: detail level / auto-pause saved and read back,
#                                     default settings, achievements reset (test files only)
#   -- <map> --frontend-test pause    pause menu with the new entries, local leaderboard,
#                                     "Ricomincia livello" -> a new game from round 1
# Test files: user://settings_test.cfg, achievements_test.cfg, leaderboard_test.cfg, savegame_test.json.
class_name FrontendTests
extends Node

var main: Node
var fails := 0


static func start(main_: Node, args: PackedStringArray, level: String) -> void:
	var t := FrontendTests.new()
	t.main = main_
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	main_.add_child(t)
	var mode := args[args.find("--frontend-test") + 1] if args.find("--frontend-test") + 1 < args.size() else "menu"
	match mode:
		"intro":
			t._intro()
		"pause":
			t._pause(level if level != "" else "nacht")
		_:
			t._menu()


func _check(ok: bool, what: String) -> void:
	print("[frontend] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/frontend_%s.png" % name))


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _key() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = true
	Input.parse_input_event(e)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)


func _finish() -> void:
	print("[frontend] RESULT %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _intro() -> void:
	var intro := IntroSequence.new()
	main.add_child(intro)
	var done := [false]
	intro.finished.connect(func(): done[0] = true)
	await _wait(0.5)
	_check(intro.phase == "logos", "starts with the splash logos")
	await _shot("intro_logo1")
	await _wait(3.2)   # SplashScreenMs: the next logo by itself
	await _shot("intro_logo2")
	_key()
	await _wait(0.3)
	await _shot("intro_logo3")
	_check(intro.phase == "logos", "a key shows the next logo")
	_key()
	await _wait(1.5)
	_check(intro.phase == "video", "then the intro video")
	var v: VideoStreamPlayer = intro.get("_video")
	_check(v != null and v.is_playing(), "video playing (%s)" % IntroSequence.VIDEO)
	await _wait(4.0)
	await _shot("intro_video")
	_key()
	await _wait(0.5)
	_check(done[0], "a key skips the video")
	main._show_menu(false)
	await _wait(1.0)
	var menu := _menu_node()
	_check(menu != null, "main menu after the intro")
	var music := menu.find_child("MenuMusic", true, false) as AudioStreamPlayer if menu else null
	_check(music != null and music.playing and music.stream != null, "menu music mx_frontend playing")
	_finish()


func _menu_node() -> Menu:
	for c in main.get_children():
		if c is Menu and not c.is_queued_for_deletion():
			return c
	return null


func _menu() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH_TEST))
	Settings._loaded = false
	Settings.ensure_loaded()
	main._show_menu(false)
	await _wait(1.0)
	var menu := _menu_node()
	_check(get_tree().root.find_children("*", "IntroSequence", true, false).is_empty(), "no intro with test options")
	var music := menu.find_child("MenuMusic", true, false) as AudioStreamPlayer
	_check(music != null and music.playing, "menu music playing")
	var src: String = music.stream.resource_path if music and music.stream else ""
	_check("47a34869" in src, "music is mx_frontend (%s)" % src)
	menu._select(2)
	var desc: String = menu.extras._desc.text
	_check("swamp" in desc, "map description of Shi No Numa: %s" % desc.replace("\n", " / "))
	await _shot("menu")
	# press sound on a button
	var before := get_tree().root.find_children("MenuPress", "AudioStreamPlayer", true, false).size()
	(menu.find_child("AIUTO", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var presses := get_tree().root.find_children("MenuPress*", "AudioStreamPlayer", true, false).size()
	_check(presses > before, "menu_press on a button")
	for p in [["help", "help_game"], ["leaderboard", "leaderboards"], ["credits", "credits"], ["about", "about"]]:
		for c in menu.get_children():
			if c is ExtrasScreen:
				c.close()
		var s: ExtrasScreen = menu.extras.open_page(p[0])
		await _wait(0.3)
		if p[0] == "credits":
			await _wait(4.0)   # CreditsScrollDelay, then scrolling
			_check(s._scroll.scroll_vertical > 0, "credits scroll after the delay")
		await _shot(p[1])
		if p[0] == "help":
			s._tabs[1].pressed.emit()
			await _wait(0.2)
			await _shot("help_performance")
	for c in menu.get_children():
		if c is ExtrasScreen:
			c.close()
	await _wait(0.2)
	# options: Detail Level / Auto-Pause saved to the (test) settings file
	var o: OptionsScreen = menu.extras.open_options()
	await _wait(0.3)
	await _shot("options")
	var opt := o.find_child("detail_level", true, false) as OptionButton
	opt.select(2)
	opt.item_selected.emit(2)
	var ap := o.find_child("auto_pause", true, false) as CheckButton
	ap.button_pressed = false
	_check(is_equal_approx(get_viewport().scaling_3d_scale, 0.6), "detail Low: 3D render scale 0.6")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	o._unhandled_input(esc)   # back: saves and closes the screen
	await _wait(0.3)
	_check(not is_instance_valid(o) or o.is_queued_for_deletion(), "back closes the options screen")
	_check(not get_tree().paused, "menu not paused after the options")
	var cfg := ConfigFile.new()
	_check(cfg.load(Settings.PATH_TEST) == OK and int(cfg.get_value("settings", "detail_level", -1)) == 2 \
		and cfg.get_value("settings", "auto_pause", true) == false, "options saved to %s" % Settings.PATH_TEST)
	Settings._loaded = false
	Settings.ensure_loaded()
	_check(int(Settings.get_value("detail_level")) == 2 and not Settings.get_value("auto_pause"), "options read back")
	# Default Settings with its confirmation
	o = menu.extras.open_options()
	await _wait(0.2)
	(o.find_child("defaults", true, false) as Button).pressed.emit()
	await _wait(0.2)
	_check(o._pages["defaults"].visible, "default settings asks for confirmation")
	await _shot("options_defaults")
	FrontendOptions.restore_defaults(o)
	await _wait(0.2)
	_check(int(Settings.get_value("detail_level")) == 0 and Settings.get_value("auto_pause") == true, "defaults restored")
	_check(is_equal_approx(get_viewport().scaling_3d_scale, 1.0), "detail High again")
	# achievements reset: only the test file
	var a := Achievements.instance
	_check(a.test_mode and String(a.get("_path")) == Achievements.SAVE_TEST, "achievements on the test file")
	a.unlocked["test_dummy"] = 1
	a.stats["global.kills"] = 5
	a.set("_dirty", true)
	a.save()
	(o.find_child("reset_stats", true, false) as Button).pressed.emit()
	await _wait(0.2)
	_check(o._pages["reset_stats"].visible, "reset asks for confirmation")
	await _shot("options_reset")
	FrontendOptions.reset_stats(o)
	var c2 := ConfigFile.new()
	c2.load(Achievements.SAVE_TEST)
	_check(a.unlocked.is_empty() and not c2.has_section("unlocked") and not c2.has_section("stats"), "achievements and stats reset in the test file")
	o.close()
	_finish()


func _pause(level: String) -> void:
	Leaderboard.add(level, 12, 4321, 150, 40)   # a row to show (test leaderboard)
	main._start(level, PackedStringArray())
	var game: Game = null
	for c in main.get_children():
		if c is Game:
			game = c
	for i in 300:
		if game.round_number >= 1 and game.hud:
			break
		await _wait(0.1)
	await _wait(1.0)
	game.hud.open_pause()
	var pm: PauseMenu = game.hud._pause
	await _wait(0.2)
	await _shot("pause")
	pm._show("settings")
	await _wait(0.2)
	await _shot("pause_settings")
	pm._show("main")
	var lb := ExtrasScreen.new("leaderboard", level)
	pm.add_child(lb)
	await _wait(0.3)
	_check(lb.map == level, "pause leaderboard opens on %s" % level)
	await _shot("pause_leaderboard")
	lb.close()
	pm._show("restart")
	await _wait(0.2)
	_check(pm._pages["restart"].visible, "restart asks for confirmation")
	await _shot("pause_restart")
	game.round_number = 7
	game.score = 9999
	SaveGame.save(game)
	_check(SaveGame.has_save(), "a save before the restart")
	FrontendOptions.restart_level(pm)
	await _wait(0.5)
	var fresh: Game = null
	for c in main.get_children():
		if c is Game and c != game:
			fresh = c
	_check(fresh != null and not is_instance_valid(game), "a new game replaces the old one")
	for i in 300:
		if fresh and fresh.round_number >= 1:
			break
		await _wait(0.1)
	_check(fresh != null and fresh.round_number == 1 and fresh.level_name == level, "restarted from round 1 on %s" % level)
	_check(fresh != null and fresh.score < 9999 and not get_tree().paused, "fresh score, not paused")
	await _shot("after_restart")
	_finish()
