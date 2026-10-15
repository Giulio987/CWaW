# The original front end as pages (frontend.group.bin, CIwGuiMultiFrame "frontend_multi";
# layout pieces in frontend_art.gd), over the menu background (menu.gd):
# - fe_title: the logo (7c9a2e56, region (41,32)-(437,307), centred at y 16) and a full-screen
#   touch item to the main menu; its label has no text (the "Touch screen to start" string
#   e6b587f5 is used by no resource and no code), so none here. Only at start-up.
# - fe_mainmenu "Main Menu": Single Player, Extras, Options (Co-Op, news and BUY NOW left out)
# - fe_singleplayer: si_difficultytoggle "Difficulty:" Regular / Recruit with its description
#   in the bottom panel (LS strings fa235ba4 / 0a25cbed), New Game, Continue (si_resumegame,
#   grey without a saved game)
# - fe_selectlevel "Select Level": the map list on the left; on the right the panel 9dede741,
#   the white frame ad5ebcb2 (right edge 44 past the screen, y 15, 256x128) with the map
#   thumbnail (sv_thumbnail: right edge 19 from the screen's, y 30, 128x128) and
#   sv_description (right edge 15, y 120, 175 wide). Hover (or a first tap) shows a map,
#   a click (second tap) plays it. The DEBUG switch of the remake sits at the bottom.
# - fe_extras: Achievements, Leaderboards, Credits, About (Profile left out)
# - fe_options: Settings, Help, Default Settings (Controls and Language left out)
# Every page but the title has the CGuiFrameBloodSplat splats and a Back item (Esc).
# The music mx_frontend and menu_press come from ui_sound.gd; the pages of Extras/Options
# open over the menu (extras_screen.gd, options_screen.gd, achievements_screen.gd).
class_name FrontendMenu
extends Control

static var title_seen := false   # fe_title only once, at start-up

var menu: Menu
var page := ""
var _pages := {}
var _desc: Label          # map description (fe_selectlevel sv_description)
var _title: Label         # map name over the description
var _thumb: TextureRect
var _map_rows := []
var _diff_value: Label
var _diff_desc: Label
var _overlay: Node
var _s := 2.25
var _selected_at := 0


static func attach(m: Menu) -> FrontendMenu:
	var f := FrontendMenu.new()
	f.menu = m
	m.add_child(f)
	return f


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSound.install()
	UiSound.music(self)
	_s = FrontendArt.unit(self)
	_build_title()
	_build_main()
	_build_single()
	_build_select()
	_build_list("extras", "Extra", [["Obiettivi", func(): menu.show_achievements()],
		["Classifiche", open_page.bind("leaderboard")], ["Riconoscimenti", open_page.bind("credits")],
		["Informazioni", open_page.bind("about")]], "main")
	_build_list("options", "Opzioni", [["Impostazioni", open_options], ["Aiuto", open_page.bind("help")],
		["Impostazioni predefinite", open_defaults]], "main")
	show_page("main" if title_seen else "title")
	title_seen = true


func show_page(name: String) -> void:
	page = name
	for k in _pages:
		_pages[k].visible = k == name
	var first := _first_button(_pages[name])
	if first and name != "title":
		first.grab_focus.call_deferred()


func _first_button(n: Node) -> BaseButton:
	for c in n.get_children():
		if c is BaseButton and c.visible and not (c as BaseButton).disabled and c.name != "BACK":
			return c
		var f := _first_button(c)
		if f:
			return f
	return null


func _new_page(name: String, title: String, back_to: String, splat_seed: int) -> Control:
	var p := Control.new()
	p.name = "page_" + name
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	_pages[name] = p
	if title != "":
		FrontendArt.blood_splats(p, _s, splat_seed)
		FrontendArt.title_bar(p, _s, title)
	if back_to != "":
		p.set_meta("back", back_to)
	return p


func back() -> void:
	var p: Control = _pages.get(page)
	if p and p.has_meta("back"):
		show_page(String(p.get_meta("back")))


func _back_button(p: Control) -> void:
	FrontendArt.back_button(p, _s, back)


func _build_title() -> void:
	var p := _new_page("title", "", "", 0)
	var a := AtlasTexture.new()
	a.atlas = FrontendArt.tex(Menu.TEX + "7c9a2e56.png")
	a.region = Rect2(41, 32, 396, 275)
	var logo := FrontendArt.image(p, a)
	FrontendArt.place(logo, _s, 0, 16, 396, 275, 1, 0)
	var touch := Button.new()   # CGuiTouchButtonMenuItem over the whole page -> mainmenu
	touch.name = "TITLE_TOUCH"
	touch.flat = true
	touch.focus_mode = Control.FOCUS_NONE
	touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var none := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		touch.add_theme_stylebox_override(k, none)
	touch.pressed.connect(show_page.bind("main"))
	p.add_child(touch)


func _build_main() -> void:
	var p := _new_page("main", "Menu principale", "title", 1)
	FrontendArt.rows(p, _s, [["Giocatore singolo", show_page.bind("single")],
		["Extra", show_page.bind("extras")], ["Opzioni", show_page.bind("options")]])
	_back_button(p)


func _build_list(name: String, title: String, specs: Array, back_to: String) -> void:
	var p := _new_page(name, title, back_to, name.length())
	FrontendArt.rows(p, _s, specs)
	_back_button(p)


func _build_single() -> void:
	var p := _new_page("single", "Giocatore singolo", "main", 2)
	# bottom panel: two flipped strips of the grunge band, tinted, over a dark red fill
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(panel)
	FrontendArt.place(panel, _s, 0, 0, 480, 120, 0, 2)
	panel.anchor_right = 1.0
	panel.offset_right = 0
	var e1 := FrontendArt.image(panel, UiArt.region(FrontendArt.BOTTOM_EDGE), true)
	FrontendArt.place(e1, _s, 0, -5, 480, 55)
	e1.anchor_right = 1.0
	e1.offset_right = 0
	e1.modulate = Color8(0xaa, 0x09, 0x0d)
	var e2 := FrontendArt.image(panel, UiArt.region(FrontendArt.BOTTOM_EDGE), true, true)
	FrontendArt.place(e2, _s, 0, 0, 480, 50)
	e2.anchor_right = 1.0
	e2.offset_right = 0
	e2.modulate = Color8(0x3a, 0x0d, 0x0d)
	var fill := ColorRect.new()
	fill.color = Color8(0x3a, 0x0d, 0x0d)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fill)
	FrontendArt.place(fill, _s, 0, 50, 480, 70)
	fill.anchor_right = 1.0
	fill.offset_right = 0
	_diff_desc = Label.new()
	_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_desc.add_theme_font_size_override("font_size", int(10 * _s))
	_diff_desc.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(_diff_desc)
	FrontendArt.place(_diff_desc, _s, 30, 34, 420, 86)
	_diff_desc.anchor_right = 1.0
	_diff_desc.offset_right = -30 * _s

	var box := FrontendArt.rows(p, _s, [["Difficoltà:", _toggle_difficulty],
		["Nuova partita", func():
			SaveGame.pending = {}
			show_page("select")],
		["Continua", _continue]])
	box.name = "rows"
	# the toggle's value with the arrow bitmap, at x 120
	var diff_row := box.get_child(0) as Button
	diff_row.name = "DIFFICOLTA"
	var arrow := FrontendArt.image(diff_row, UiArt.region(FrontendArt.ARROW))
	FrontendArt.place(arrow, _s, 120, 2, 36, 36)
	arrow.modulate = Color8(0xab, 0x08, 0x0c)
	_diff_value = Label.new()
	_diff_value.add_theme_font_override("font", UiArt.font())
	_diff_value.add_theme_font_size_override("font_size", int(22 * _s))
	_diff_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_diff_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diff_row.add_child(_diff_value)
	FrontendArt.place(_diff_value, _s, 160, 0, 260, 40)
	_show_difficulty()
	var cont := box.get_child(2) as Button
	cont.name = "CONTINUA"
	var save := SaveGame.load_save()
	cont.disabled = save.is_empty()
	if not save.is_empty():
		var note := Label.new()
		var map_name := String(save["map"])
		for m in Menu.MAPS:
			if m["id"] == map_name:
				map_name = m["name"]
		note.text = "%s · round %d · %d punti" % [map_name, int(save["round"]), int(save["points"])]
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", int(9 * _s))
		note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cont.add_child(note)
		note.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		note.offset_right = -24 * _s
	_back_button(p)


func _show_difficulty() -> void:
	var recruit := bool(Settings.get_value("recruit"))
	_diff_value.text = "Recluta" if recruit else "Regolare"
	_diff_desc.text = ExtrasScreen.text("recruit_desc" if recruit else "regular_desc")


# toggleDifficulty: Regular <-> Recruit, from the next game (Game.difficulty)
func _toggle_difficulty() -> void:
	Settings.set_value("recruit", not bool(Settings.get_value("recruit")))
	Settings.save()
	_show_difficulty()


func _continue() -> void:
	var s := SaveGame.load_save()
	if s.is_empty():
		return
	SaveGame.pending = s
	start(String(s["map"]))


func _build_select() -> void:
	var p := _new_page("select", "Seleziona livello", "single", 3)
	var vw := get_viewport().get_visible_rect().size.x / _s
	var specs := []
	for i in Menu.MAPS.size():
		specs.append([Menu.MAPS[i]["name"], _map_pressed.bind(i)])
	var box := FrontendArt.rows(p, _s, specs, vw - 202.0)
	for i in box.get_child_count():
		var b := box.get_child(i) as Button
		b.name = "MAP_" + String(Menu.MAPS[i]["id"])
		b.focus_entered.connect(menu._select.bind(i))
		if not DisplayServer.is_touchscreen_available():
			b.mouse_entered.connect(menu._select.bind(i))
		_map_rows.append(b)
	FrontendArt.right_panel(p, _s)
	var frame := FrontendArt.image(p, FrontendArt.tex(Menu.TEX + FrontendArt.MAP_FRAME + ".png"))
	FrontendArt.place(frame, _s, 44, 15, 256, 128, 2, 0)
	_thumb = FrontendArt.image(p, null)
	FrontendArt.place(_thumb, _s, -19, 30, 128, 128, 2, 0)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(info)
	FrontendArt.place(info, _s, -15, 120, 175, 190, 2, 0)
	_title = Label.new()
	_title.add_theme_font_override("font", UiArt.font())
	_title.add_theme_font_size_override("font_size", int(14 * _s))
	_title.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(_title)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc.add_theme_font_size_override("font_size", int(9 * _s))
	_desc.add_theme_color_override("font_color", Color(0.92, 0.9, 0.88))
	_desc.add_theme_color_override("font_outline_color", Color.BLACK)
	_desc.add_theme_constant_override("outline_size", 3)
	info.add_child(_desc)
	_back_button(p)
	# remake: debug start (round 5, Ray Gun, points; no achievements)
	var dbg := CheckButton.new()
	dbg.name = "DEBUG"
	dbg.text = "DEBUG: round %d · Ray Gun · %d punti" % [Game.DEBUG_ROUND, Game.DEBUG_POINTS]
	dbg.tooltip_text = "Gli obiettivi non si sbloccano in questa modalità"
	dbg.add_theme_font_size_override("font_size", int(7.5 * _s))
	dbg.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dbg.button_pressed = Game.debug_start
	dbg.toggled.connect(func(on: bool): Game.debug_start = on)
	p.add_child(dbg)
	FrontendArt.place(dbg, _s, 128, -8, 170, 32, 0, 2)


func _map_pressed(i: int) -> void:
	# a first tap only shows the map; hovering already did that with a mouse
	if i != menu._selected or Time.get_ticks_msec() - _selected_at < 150:
		menu._select(i)
		if DisplayServer.is_touchscreen_available():
			return
	start(String(Menu.MAPS[i]["id"]))


# menu.gd _select
func selected(map_id: String) -> void:
	_selected_at = Time.get_ticks_msec()
	if _desc == null:
		return
	var m: Dictionary = ExtrasScreen.data().get("maps", {}).get(map_id, {})
	_title.text = String(m.get("title", ""))
	_desc.text = String(m.get("desc", "")).replace("\n\n", "\n")
	for i in Menu.MAPS.size():
		if Menu.MAPS[i]["id"] == map_id:
			_thumb.texture = FrontendArt.tex("res://assets/textures/frontend/mapinfo/%s.png" % Menu.MAPS[i]["preview"])
			if i < _map_rows.size():
				(_map_rows[i] as Button).add_theme_color_override("font_color", Color(1, 0.75, 0.7))
		elif i < _map_rows.size():
			(_map_rows[i] as Button).add_theme_color_override("font_color", Color.WHITE)


# the loading page (loading_screen.gd), then the game (main.gd on Menu.play)
func start(map_id: String) -> void:
	if get_tree().root.has_node("LoadingScreen"):
		return
	LoadingScreen.show_over(get_tree())
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	menu.play.emit(map_id)


func overlay_open() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


func open_page(page_: String) -> ExtrasScreen:
	var s := ExtrasScreen.new(page_)
	menu.add_child(s)
	_overlay = s
	return s


func open_options() -> OptionsScreen:
	var o := OptionsScreen.new()
	menu.add_child(o)
	o.open_options()
	_overlay = o
	return o


# fe_options "Default Settings" -> fe_restoretofactoryyesno
func open_defaults() -> OptionsScreen:
	var o := OptionsScreen.new()
	menu.add_child(o)
	o.open_options("defaults")
	_overlay = o
	return o


func _unhandled_input(event: InputEvent) -> void:
	if menu._achievements != null or overlay_open():
		return
	if page == "title":
		if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo():
			get_viewport().set_input_as_handled()
			show_page("main")
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()
