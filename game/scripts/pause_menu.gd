# In-game pause menu (Esc on Mac, pause button on touch): Riprendi, Opzioni (ig_options:
# Impostazioni with sensitivity, invert Y, FOV, volumes, brightness - saved by Settings - and Aiuto),
# Torna al menu principale (with confirmation), Modalità foto (debug: the game stays
# paused with no menu over it, the mouse still looks around, a corner line shows map,
# position and view direction so a screenshot says where it was taken).
class_name PauseMenu
extends CanvasLayer

signal closed

var game: Node  # Game
var _pages := {}
var _was_captured := false
var _shade: ColorRect
var _photo := false
var _info: Label


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.72)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_pages["main"] = _page("PAUSA", [
		["Riprendi", close],
		# ig_pause "options" -> ig_options (Settings, Help, Default Settings: frontend_options.gd)
		["Opzioni", func(): _show("options")],
		# original ig_pause: localleaderboard, resetlevel (with ig_resetlevelyesno)
		["Classifica locale", func(): add_child(ExtrasScreen.new("leaderboard", String(game.get("level_name")) if game else ""))],
		["Ricomincia livello", func(): _show("restart")],
		["Obiettivi", func(): add_child(AchievementsScreen.new())],   # achievements_screen.gd (closes itself)
		["Modalità foto (debug)", _photo_mode],
		["Torna al menu principale", func(): _show("confirm")],
	])
	_pages["confirm"] = _page("Tornare al menu principale?\nLa partita viene salvata: si riprende dal menu.", [
		["No", func(): _show("main")],
		["Sì", _to_main_menu],
	], 44)
	_pages["settings"] = _settings_page()
	FrontendOptions.add_pages(self)   # restart / default settings / reset confirmations
	UiSound.install()                 # menu_press on the buttons


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	Settings.ensure_loaded()
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_show("main")
	get_tree().paused = true


func close() -> void:
	if not visible:
		return
	if _photo:
		_end_photo()
	Settings.save()
	visible = false
	get_tree().paused = false
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _show(name: String) -> void:
	for k in _pages:
		_pages[k].visible = k == name
	var first := _first_focusable(_pages[name])
	if first:
		first.grab_focus.call_deferred()


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is BaseButton or c is Slider:
			return c
		var f := _first_focusable(c)
		if f:
			return f
	return null


func _photo_mode() -> void:
	_photo = true
	_shade.visible = false
	for k in _pages:
		_pages[k].visible = false
	if _info == null:
		_info = Label.new()
		_info.position = Vector2(12, 8)
		_info.add_theme_font_size_override("font_size", 16)
		_info.add_theme_color_override("font_outline_color", Color.BLACK)
		_info.add_theme_constant_override("outline_size", 4)
		add_child(_info)
	_info.visible = true
	_update_info()
	# the pointer stays free (to take screenshots on the Mac): dragging turns the view
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _end_photo() -> void:
	_photo = false
	_shade.visible = true
	_info.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show("main")


func _update_info() -> void:
	var p = game.get("player") if game else null
	if p == null or _info == null:
		return
	var cam: Camera3D = p.get_viewport().get_camera_3d()
	var pos: Vector3 = p.global_position
	var lvl = game.get("level")
	var sector: String = lvl.sector_at(pos) if lvl and lvl.has_method("sector_at") else ""
	_info.text = "FOTO (debug) · %s · round %d · pos (%.2f, %.2f, %.2f)%s · yaw %.0f° pitch %.0f° · trascina per girare · Esc o doppio tocco: torna" % [
		game.get("level_name"), game.get("round_number"), pos.x, pos.y, pos.z,
		(" · settore " + sector) if sector != "" else "",
		rad_to_deg(p.rotation.y), rad_to_deg(cam.rotation.x) if cam else 0.0]


func _unhandled_input(event: InputEvent) -> void:
	if _photo:
		get_viewport().set_input_as_handled()
		var p = game.get("player") if game else null
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and p:
			p.look(event.relative * Player.MOUSE_SENS * Settings.mouse_sens())
			_update_info()
		elif event is InputEventScreenDrag and p:
			p.look(event.relative * 0.005 * Settings.touch_sens())
			_update_info()
		elif event.is_action_pressed("ui_cancel") or (event is InputEventScreenTouch and event.double_tap):
			_end_photo()
		return
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _pages["main"].visible:
			close()
		else:
			Settings.save()
			_show(FrontendOptions.back_page(self))


func _to_main_menu() -> void:
	Settings.save()
	if game is Game:
		SaveGame.save(game)   # SaveProgress: "Riprendi" in the main menu (save_game.gd)
	get_tree().paused = false
	var main := get_tree().current_scene
	if game and main and main.has_method("_show_menu"):
		game.queue_free()
		main.call_deferred("_show_menu", false)
	else:
		get_tree().reload_current_scene()


# ------------------------------------------------------------------ widgets

func _title(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiArt.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UiArt.RED.lightened(0.15))
	return l


func _button(text: String, cb: Callable, size := 44) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 58)
	b.add_theme_font_override("font", UiArt.font())
	b.add_theme_font_size_override("font_size", size)
	for c in ["font_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color(0.92, 0.92, 0.92))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	var smear := StyleBoxTexture.new()  # red brush stroke of the original HUD atlas
	smear.texture = UiArt.region(UiArt.RED_SMEAR)
	var none := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", none)
	b.add_theme_stylebox_override("hover", smear)
	b.add_theme_stylebox_override("pressed", smear)
	b.add_theme_stylebox_override("focus", smear)
	b.pressed.connect(cb)
	return b


func _page(title: String, buttons: Array, title_size := 88) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(_title(title, title_size))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	box.add_child(gap)
	for spec in buttons:
		var b := _button(spec[0], spec[1])
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(b)
	return box


func _settings_page() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(_title("IMPOSTAZIONI", 56))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(grid)
	_slider(grid, "Sensibilità mouse", "mouse_sens", 0.2, 3.0, 0.05, "×%.2f")
	_slider(grid, "Sensibilità touch", "touch_sens", 0.2, 3.0, 0.05, "×%.2f")
	_check(grid, "Inverti asse Y", "invert_y")
	# SensitivityYDefault / SensitivityXDefault = 0.375 / 0.5 in the original
	_slider(grid, "Sensibilità verticale", "look_y_ratio", 0.3, 1.5, 0.05, "×%.2f")
	# original ViewportFOV 50 (across the average screen dimension, settings.gd)
	_slider(grid, "Campo visivo", "fov", 40.0, 100.0, 1.0, "%d°")
	# toggleAim: the original's aim button is a toggle; on desktop the right button is held
	_check(grid, "Mirino: clic per attivare", "aim_toggle")
	# toggleAutoaim ("Auto-Aim:")
	_check(grid, "Mira assistita", "auto_aim")
	_slider(grid, "Volume generale", "master_volume", 0.0, 1.0, 0.05, "pct")
	_slider(grid, "Volume effetti", "effects_volume", 0.0, 1.0, 0.05, "pct")
	_slider(grid, "Volume musica", "music_volume", 0.0, 1.0, 0.05, "pct")
	# fe_settings / ig_settings se_brightnessslider (Settings.apply_brightness)
	_slider(grid, "Luminosità", "brightness", 0.0, 1.0, 0.01, "pct")
	# toggleDifficulty: Recruit / Regular, used from the next game (Game.difficulty)
	_check(grid, "Difficoltà Recluta (prossima partita)", "recruit")
	FrontendOptions.add_rows(self, grid, box)   # Detail Level, Auto-Pause, Default Settings, reset
	var back := _button("Indietro", func():
		Settings.save()
		_show("options"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	# fe_settings / ig_settings note (44ee966e): a bottom frame from x 160 (480x320 units)
	var note := Label.new()
	note.name = "headphones"
	note.text = ExtrasScreen.text("headphones")
	note.top_level = true
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(note)
	box.move_child(note, 0)   # top_level: out of the layout; Indietro stays the last child (frontend_options.gd)
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var u := vp.y / 320.0
	note.position = Vector2(190 * u, vp.y - 20)
	note.size = Vector2(vp.x - 220 * u, 18)
	box.offset_bottom = -24   # the page content above the note
	return box


func _row_label(grid: GridContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	grid.add_child(l)


func _slider(grid: GridContainer, text: String, key: String, lo: float, hi: float, step: float, fmt: String) -> void:
	_row_label(grid, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(320, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value = float(Settings.get_value(key))
	var v := Label.new()
	v.custom_minimum_size = Vector2(80, 0)
	v.add_theme_font_size_override("font_size", 22)
	var show := func(x: float):
		v.text = ("%d%%" % roundi(x * 100.0)) if fmt == "pct" else (fmt % x)
	show.call(s.value)
	s.value_changed.connect(func(x: float):
		Settings.set_value(key, x)
		show.call(x))
	s.name = key
	grid.add_child(s)
	grid.add_child(v)


func _check(grid: GridContainer, text: String, key: String) -> void:
	_row_label(grid, text)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(key))
	c.toggled.connect(func(on: bool): Settings.set_value(key, on))
	c.name = key
	grid.add_child(c)
	grid.add_child(Control.new())
