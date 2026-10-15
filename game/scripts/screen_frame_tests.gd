# "Dimensione schermo" checks (screen_frame.gd), screenshots analysis/preview/margini_<tag>_*.png:
#   -- --frame-test menu [--screen-scale 0.8]          main menu, Options -> Impostazioni page,
#                                                         a click and a touch on its buttons
#   -- <map> --frame-test game [--screen-scale 0.8]    in game (HUD), the pause menu and its
#                                                         settings page, clicks on the buttons
# Uses user://settings_test.cfg (Settings.path). Window size from --resolution.
class_name ScreenFrameTests
extends Node

var main: Node
var fails := 0
var tag := ""


static func start(main_: Node, args: PackedStringArray, level: String) -> void:
	var t := ScreenFrameTests.new()
	t.main = main_
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	main_.add_child(t)
	var i := args.find("--frame-test")
	var mode := args[i + 1] if i + 1 < args.size() else "menu"
	Settings.ensure_loaded()
	var sc := ScreenFrame.cmdline_scale()
	t.tag = "%s_%d_%dx%d" % [mode, roundi((sc if sc > 0.0 else 1.0) * 100.0), DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	if mode == "game":
		t._game(level if level != "" else "nacht")
	else:
		t._menu()


func _check(ok: bool, what: String) -> void:
	print("[margini] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/margini_%s_%s.png" % [tag, name]))


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


# Window (physical) position of a control's centre: what a real click / touch would carry.
func _screen_pos(c: Control) -> Vector2:
	var vp := c.get_viewport()
	return vp.get_final_transform() * c.get_global_transform_with_canvas() * (c.size * 0.5)


func _click(c: Control, touch: bool) -> void:
	var p := _screen_pos(c)
	if touch:
		for down in [true, false]:
			var e := InputEventScreenTouch.new()
			e.index = 0
			e.position = p
			e.pressed = down
			Input.parse_input_event(e)
			await get_tree().process_frame
	else:
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
		Input.parse_input_event(m)
		await get_tree().process_frame
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.position = p
			e.global_position = p
			e.pressed = down
			e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			Input.parse_input_event(e)
			await get_tree().process_frame


func _frame_report() -> void:
	var root := get_tree().root
	var r := Rect2(root.get_final_transform() * Vector2.ZERO, root.get_final_transform() * root.get_visible_rect().size - root.get_final_transform() * Vector2.ZERO)
	print("[margini] window %s, logical %s, scale %.2f, picture %s, 3D in root %s, auto %.2f" % [
		root.size, root.get_visible_rect().size, ScreenFrame.scale, r, not root.disable_3d, ScreenFrame.auto_scale()])
	_check(ScreenFrame.scale >= 1.0 or root.disable_3d, "3D drawn by the frame when shrunk")


func _menu() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH_TEST))
	Settings._loaded = false
	Settings.ensure_loaded()
	main._show_menu(false)
	await _wait(1.0)
	_frame_report()
	var menu: Menu = null
	for c in main.get_children():
		if c is Menu:
			menu = c
	(menu.find_child("TITLE_TOUCH", true, false) as Button).pressed.emit()
	await _wait(0.3)
	await _shot("menu")
	var o: OptionsScreen = menu.extras.open_options()
	await _wait(0.3)
	await _shot("settings")
	var sl := o._pages["settings"].find_child("screen_scale", true, false) as HSlider
	_check(sl != null and is_equal_approx(sl.value, float(Settings.get_value("screen_scale"))), "Dimensione schermo slider on the settings page")
	# a real click on "Azzera obiettivi e statistiche" opens its confirmation
	var b := o._pages["settings"].find_child("reset_stats", true, false) as Button
	await _click(b, false)
	await _wait(0.2)
	_check(o._pages["reset_stats"].visible, "mouse click at the shrunk button's screen position works")
	await _shot("click")
	# a touch on "No" goes back to the settings page
	var no: Button = null
	for n in o._pages["reset_stats"].find_children("*", "Button", true, false):
		if (n as Button).text == "No":
			no = n
	await _click(no, true)
	await _wait(0.2)
	_check(o._pages["settings"].visible, "touch at the shrunk button's screen position works")
	if ScreenFrame.cmdline_scale() < 0.0:
		# the slider (moved by keys / a tap: applied at once), saved, then Default Settings
		sl.value = 0.85
		await _wait(0.3)
		_check(is_equal_approx(ScreenFrame.scale, 0.85) and get_tree().root.disable_3d, "slider applies 85 %")
		await _shot("slider85")
		Settings.save()
		var cfg := ConfigFile.new()
		cfg.load(Settings.path())
		_check(is_equal_approx(float(cfg.get_value("settings", "screen_scale", 0.0)), 0.85), "screen_scale saved in the settings file")
		FrontendOptions.restore_defaults(o)
		await _wait(0.3)
		var root := get_tree().root
		_check(ScreenFrame.scale == ScreenFrame.auto_scale() and float(Settings.get_value("screen_scale")) == ScreenFrame.auto_scale()
			and (ScreenFrame.scale < 1.0 or (not root.disable_3d and root.global_canvas_transform == Transform2D())),
			"Default Settings: back to the automatic value (%.2f)" % ScreenFrame.auto_scale())
	print("[margini] RESULT %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _game(level: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH_TEST))
	Settings._loaded = false
	Settings.ensure_loaded()
	main._start(level, PackedStringArray())
	var game: Game = null
	for c in main.get_children():
		if c is Game:
			game = c
	for i in 300:
		if game.round_number >= 1 and game.hud:
			break
		await _wait(0.1)
	await _wait(2.0)
	_frame_report()
	var cam := get_viewport().get_camera_3d()
	if cam:
		# the screen centre (crosshair) is still the camera's centre ray
		var ray := cam.project_ray_normal(get_viewport().get_visible_rect().size * 0.5)
		_check(ray.dot(-cam.global_basis.z) > 0.9999, "crosshair (logical centre) = camera centre ray")
	await _shot("hud")
	# look speed: 40 window pixels of mouse motion turn the same at any screen size
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var yaw0: float = game.player.rotation.y
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(40, 0)
	mm.screen_relative = Vector2(40, 0)
	Input.parse_input_event(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	var turned := rad_to_deg(angle_difference(yaw0, game.player.rotation.y))
	print("[margini] 40 px of mouse motion turn %.3f deg" % turned)
	_check(absf(turned) > 0.0, "mouse look works")
	game.hud.open_pause()
	var pm: PauseMenu = game.hud._pause
	await _wait(0.3)
	await _shot("pause")
	var opt: Button = null
	for n in pm._pages["main"].find_children("*", "Button", true, false):
		if (n as Button).text == "Opzioni":
			opt = n
	await _click(opt, true)
	await _wait(0.2)
	_check(pm._pages["options"].visible, "touch on Opzioni in the shrunk pause menu")
	pm._show("settings")
	await _wait(0.3)
	await _shot("settings")
	print("[margini] RESULT %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()
