# In-game pause menu (Esc on Mac, pause button on touch): Riprendi,
# Impostazioni (sensitivity, invert Y, FOV, volumes - saved by Settings),
# Torna al menu principale (with confirmation).
class_name PauseMenu
extends CanvasLayer

signal closed

var game: Node  # Game
var _pages := {}
var _was_captured := false


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_pages["main"] = _page("PAUSA", [
		["Riprendi", close],
		["Impostazioni", func(): _show("settings")],
		["Torna al menu principale", func(): _show("confirm")],
	])
	_pages["confirm"] = _page("Tornare al menu principale?\nI progressi andranno persi.", [
		["No", func(): _show("main")],
		["Sì", _to_main_menu],
	], 44)
	_pages["settings"] = _settings_page()


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


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _pages["main"].visible:
			close()
		else:
			Settings.save()
			_show("main")


func _to_main_menu() -> void:
	Settings.save()
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
	box.add_child(_title("IMPOSTAZIONI", 66))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(grid)
	_slider(grid, "Sensibilità mouse", "mouse_sens", 0.2, 3.0, 0.05, "×%.2f")
	_slider(grid, "Sensibilità touch", "touch_sens", 0.2, 3.0, 0.05, "×%.2f")
	_check(grid, "Inverti asse Y", "invert_y")
	_slider(grid, "Campo visivo", "fov", 55.0, 100.0, 1.0, "%d°")
	_slider(grid, "Volume generale", "master_volume", 0.0, 1.0, 0.05, "pct")
	_slider(grid, "Volume effetti", "effects_volume", 0.0, 1.0, 0.05, "pct")
	_slider(grid, "Volume musica", "music_volume", 0.0, 1.0, 0.05, "pct")
	var back := _button("Indietro", func():
		Settings.save()
		_show("main"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
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
