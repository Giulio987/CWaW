# Front-end checks (prints OK/FAIL, screenshots analysis/preview/frontend_*.png):
#   -- --frontend-test intro          splash logos + intro video, skipped by key presses, then the menu
#   -- --frontend-test menu           title page, menu pages (main, single player, level select with
#                                     the map text), music, help/leaderboards/credits/about pages,
#                                     achievements with the COMPLETED! stamp, options: detail level /
#                                     auto-pause / brightness saved and read back, default settings,
#                                     achievements reset (test files only)
#   -- <map> --frontend-test pause    loading page (spinner) until the level is ready, pause menu
#                                     with the new entries (Opzioni -> Aiuto), local leaderboard,
#                                     the unlock popup's view page, "Ricomincia livello" -> round 1
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
	_check(menu.extras.page == "title", "starts on the title page (fe_title)")
	await _shot("title")
	(menu.find_child("TITLE_TOUCH", true, false) as Button).pressed.emit()
	await _wait(0.2)
	_check(menu.extras.page == "main", "a touch on the title opens the main menu")
	await _shot("menu")
	menu.extras.show_page("single")
	await _wait(0.2)
	await _shot("menu_single")
	var diff_before := bool(Settings.get_value("recruit"))
	(menu.find_child("DIFFICOLTA", true, false) as Button).pressed.emit()
	_check(bool(Settings.get_value("recruit")) != diff_before and ("Recruit" if Lang.is_en() else "Recluta") in menu.extras._diff_desc.text,
		"difficulty toggle with the original description")
	(menu.find_child("DIFFICOLTA", true, false) as Button).pressed.emit()
	menu.extras.show_page("select")
	var music := menu.find_child("MenuMusic", true, false) as AudioStreamPlayer
	_check(music != null and music.playing, "menu music playing")
	var src: String = music.stream.resource_path if music and music.stream else ""
	_check("47a34869" in src, "music is mx_frontend (%s)" % src)
	menu._select(2)
	var desc: String = menu.extras._desc.text
	_check(("swamp" if Lang.is_en() else "palude") in desc, "map description of Shi No Numa: %s" % desc.replace("\n", " / "))
	_check(menu.extras._thumb.texture != null, "map thumbnail in the white frame")
	await _shot("menu_select")
	menu.extras.show_page("extras")
	await _wait(0.2)
	await _shot("menu_extras")
	menu.extras.show_page("options")
	await _wait(0.2)
	await _shot("menu_options")
	# Options -> Language: saved and applied at once (pages rebuilt, back on Options), then back
	var lang0 := Lang.code()
	var saved_lang = Settings.get_value("language")
	var override := Lang._override
	menu.extras._switch_language()
	await _wait(0.3)
	var help_row := menu.extras.find_child("AIUTO", true, false) as Button
	var music2 := menu.extras.find_child("MenuMusic", true, false) as AudioStreamPlayer
	_check(Lang.code() != lang0 and menu.extras.page == "options" and help_row != null
		and help_row.text == ("Help" if Lang.is_en() else "Aiuto") and music2 != null and music2.playing,
		"Language %s -> %s at once (Help row '%s', music on)" % [lang0, Lang.code(), help_row.text if help_row else "?"])
	await _shot("menu_options_lang")
	menu.extras._switch_language()
	await _wait(0.3)
	_check(Lang.code() == lang0, "Language back to %s" % lang0)
	Settings.set_value("language", saved_lang)   # as before the test (and --lang)
	Lang._override = override
	Settings.save()
	# achievements: the COMPLETED! stamp on an unlocked one
	var ach := Achievements.instance
	var first_id := String(ach.entries[0]["id"])
	ach.unlocked[first_id] = int(Time.get_unix_time_from_system())
	var scr := menu.show_achievements()
	await _wait(0.3)
	scr.show_entry(first_id)
	await _wait(0.1)
	_check(scr._stamp.visible, "COMPLETED! stamp on an unlocked achievement")
	await _shot("achievements")
	scr.show_entry(String(ach.entries[1]["id"]))
	_check(not scr._stamp.visible or ach.unlocked.has(String(ach.entries[1]["id"])), "no stamp on a locked one")
	scr.close()
	ach.unlocked.erase(first_id)
	await _wait(0.2)
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
	# Brightness: neutral by default, the slider to the right brightens (grey added)
	var br := o.find_child("brightness", true, false) as HSlider
	var quad := get_tree().root.get_node_or_null("Brightness/Quad") as ColorRect
	_check(br != null and Settings.brightness_level(br.value) == 10 and quad != null and not quad.get_parent().visible,
		"brightness slider, neutral (IwGx 10) by default")
	br.value = 1.0
	await _wait(0.1)
	_check(Settings.brightness_level(1.0) == 1 and quad.get_parent().visible and is_equal_approx(quad.color.r, 56.0 / 255.0)
		and (quad.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "brightness max: +56/255 added")
	await _shot("options_brightness")
	br.value = 0.0
	_check(Settings.brightness_level(0.0) == 15 and is_equal_approx(quad.color.a, 21.0 / 255.0), "brightness min: black 21/255 blended")
	br.value = 0.8
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	o._unhandled_input(esc)   # back: saves and closes the screen
	await _wait(0.3)
	_check(not is_instance_valid(o) or o.is_queued_for_deletion(), "back closes the options screen")
	_check(not get_tree().paused, "menu not paused after the options")
	var cfg := ConfigFile.new()
	_check(cfg.load(Settings.PATH_TEST) == OK and int(cfg.get_value("settings", "detail_level", -1)) == 2 \
		and cfg.get_value("settings", "auto_pause", true) == false and is_equal_approx(float(cfg.get_value("settings", "brightness", 0)), 0.8),
		"options saved to %s" % Settings.PATH_TEST)
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
	_check(Settings.brightness_level(Settings.get_value("brightness")) == 10, "brightness neutral again")
	_check(not is_instance_valid(o) or o.is_queued_for_deletion(), "confirming closes the screen (back to Options)")
	o = menu.extras.open_options()
	await _wait(0.2)
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
	var loading := LoadingScreen.show_over(get_tree())
	await _wait(0.5)
	await _shot("loading")
	var turned: float = loading._spin.rotation
	var steps := turned / LoadingScreen.STEP
	_check(turned > 0.0 and absf(steps - roundf(steps)) < 0.01, "spinner turns in steps of 150/4096 turn (%.1f deg)" % rad_to_deg(turned))
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
	_check(not is_instance_valid(loading), "loading page gone once the level is ready")
	# the unlock popup opens ig_viewachievement
	var ach := Achievements.instance
	var aid := String(ach.entries[2]["id"])
	ach.call("_show_popup", ach.by_id[aid.to_lower()])
	await _wait(0.5)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(ach.get("_popup") as Control).gui_input.emit(click)
	await _wait(0.3)
	var viewer: AchievementsScreen = null
	for n in get_tree().root.get_children():
		if n is AchievementsScreen:
			viewer = n
	_check(viewer != null and viewer.only_id == aid and viewer._rows.size() == 1 and get_tree().paused,
		"touching the popup opens its achievement, game paused")
	await _shot("view_achievement")
	if viewer:
		viewer.close()
	await _wait(0.2)
	_check(not get_tree().paused, "closing the view resumes the game")
	game.hud.open_pause()
	var pm: PauseMenu = game.hud._pause
	await _wait(0.2)
	await _shot("pause")
	pm._show("options")
	await _wait(0.2)
	await _shot("pause_options")
	# ig_options Language: the pause pages rebuilt in the other language, still on Options
	var lang0 := Lang.code()
	var saved_lang = Settings.get_value("language")
	var override := Lang._override
	FrontendOptions.switch_language(pm)
	await _wait(0.2)
	var lrow := pm._pages["options"].find_child("language", false, false) as Button
	_check(Lang.code() != lang0 and pm._pages["options"].visible and lrow != null
		and lrow.text == FrontendOptions.language_label(), "pause Language %s -> %s ('%s')" % [lang0, Lang.code(), lrow.text if lrow else "?"])
	await _shot("pause_options_lang")
	FrontendOptions.switch_language(pm)
	await _wait(0.2)
	Settings.set_value("language", saved_lang)   # as before the test (and --lang)
	Lang._override = override
	Settings.save()
	var help_btn: Button = null
	for b in pm._pages["options"].find_children("*", "Button", true, false):
		if (b as Button).text == Lang.t("Aiuto"):
			help_btn = b
	if help_btn:
		help_btn.pressed.emit()
	await _wait(0.3)
	var help: ExtrasScreen = null
	for c in pm.get_children():
		if c is ExtrasScreen:
			help = c
	_check(help != null and help.page == "help", "pause Opzioni -> Aiuto opens the help (ig_help)")
	await _shot("pause_help")
	if help:
		help.close()
	pm._show("settings")
	await _wait(0.2)
	await _shot("pause_settings")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	pm._unhandled_input(esc)
	_check(pm._pages["options"].visible, "Esc from the settings goes back to Opzioni")
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
