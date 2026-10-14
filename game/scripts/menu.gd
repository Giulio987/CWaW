# Main menu built from the original frontend textures: pick a map and play.
class_name Menu
extends CanvasLayer

signal play(level: String)

const TEX := "res://assets/textures/frontend/"
const MAPS := [
	{"id": "nacht", "name": "Nacht der Untoten", "preview": "0ffc6b53", "note": ""},
	{"id": "verruckt", "name": "Verrückt", "preview": "d3023ebb", "note": ""},
	{"id": "shinonuma", "name": "Shi No Numa", "preview": "dc131b97", "note": ""},
	{"id": "derriese", "name": "Der Riese", "preview": "365abbd8", "note": ""},
]
const RED := Color(0.62, 0.04, 0.03)

var _selected := 0
var _cards := []
var _title: Label
var _achievements: AchievementsScreen
var extras: FrontendMenu   # music, map description, options/help/leaderboards/credits/about


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiSound.install()   # menu_press on the buttons (ui_sound.gd)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var fog := _image(TEX + "a04fbb00.png", Control.PRESET_FULL_RECT)
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fog.modulate = Color(0.75, 0.75, 0.8)
	var shade := ColorRect.new()  # darken the lower half so the cards read well
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var logo := _image(TEX + "7c9a2e56.png", Control.PRESET_CENTER_TOP)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	logo.offset_left = -260
	logo.offset_right = 260
	logo.offset_top = 10
	logo.offset_bottom = 290

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	row.offset_left = -600
	row.offset_right = 600
	row.offset_top = 20
	row.offset_bottom = 260
	add_child(row)
	for i in MAPS.size():
		var card := _card(MAPS[i], i)
		row.add_child(card)
		_cards.append(card)

	var play_btn := Button.new()
	play_btn.text = "GIOCA"
	play_btn.add_theme_font_override("font", UiArt.font())
	play_btn.add_theme_font_size_override("font_size", 56)
	play_btn.add_theme_color_override("font_color", RED)
	play_btn.add_theme_color_override("font_hover_color", Color(1, 0.2, 0.1))
	play_btn.flat = true
	play_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	play_btn.offset_left = -110
	play_btn.offset_right = 110
	play_btn.offset_top = -110
	play_btn.offset_bottom = -40
	play_btn.pressed.connect(func(): play.emit(MAPS[_selected]["id"]))
	add_child(play_btn)
	_add_resume()
	var ach_btn := Button.new()
	ach_btn.text = "OBIETTIVI"
	ach_btn.add_theme_font_override("font", UiArt.font())
	ach_btn.add_theme_font_size_override("font_size", 34)
	ach_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	ach_btn.add_theme_color_override("font_hover_color", Color(1, 0.2, 0.1))
	ach_btn.flat = true
	ach_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ach_btn.offset_left = -250
	ach_btn.offset_right = -24
	ach_btn.offset_top = -86
	ach_btn.offset_bottom = -30
	ach_btn.pressed.connect(show_achievements)
	add_child(ach_btn)
	var dbg := CheckButton.new()
	dbg.text = "DEBUG: round %d · Ray Gun · %d punti" % [Game.DEBUG_ROUND, Game.DEBUG_POINTS]
	dbg.tooltip_text = "Gli obiettivi non si sbloccano in questa modalità"
	dbg.add_theme_font_size_override("font_size", 18)
	dbg.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dbg.button_pressed = Game.debug_start
	dbg.toggled.connect(func(on: bool): Game.debug_start = on)
	dbg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	dbg.offset_left = 24
	dbg.offset_right = 420
	dbg.offset_top = -80
	dbg.offset_bottom = -36
	add_child(dbg)
	# toggleDifficulty (single player screen, si_difficultytoggle): Regular or Recruit
	var diff := CheckButton.new()
	diff.text = "Difficoltà: Recluta"
	diff.tooltip_text = "Più facile; obiettivi e statistiche disattivati (come l'originale)"
	diff.add_theme_font_size_override("font_size", 18)
	diff.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	diff.button_pressed = bool(Settings.get_value("recruit"))
	diff.toggled.connect(func(on: bool):
		Settings.set_value("recruit", on)
		Settings.save())
	diff.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	diff.offset_left = 24
	diff.offset_right = 420
	diff.offset_top = -124
	diff.offset_bottom = -80
	add_child(diff)
	extras = FrontendMenu.attach(self)   # frontend_menu.gd
	_select(0)


# "Resume Carnage" (original resumegame button): continue the saved game (save_game.gd).
func _add_resume() -> void:
	var s := SaveGame.load_save()
	if s.is_empty():
		return
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = 286
	box.offset_bottom = 372
	box.add_theme_constant_override("separation", -6)
	add_child(box)
	var b := Button.new()
	b.text = "RIPRENDI LA CARNEFICINA"
	b.flat = true
	b.add_theme_font_override("font", UiArt.font())
	b.add_theme_font_size_override("font_size", 40)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	b.add_theme_color_override("font_hover_color", Color(1, 0.2, 0.1))
	b.pressed.connect(func():
		SaveGame.pending = s
		play.emit(String(s["map"])))
	box.add_child(b)
	var note := Label.new()
	var map_name := String(s["map"])
	for m in MAPS:
		if m["id"] == map_name:
			map_name = m["name"]
	note.text = "%s · round %d · %d punti" % [map_name, int(s["round"]), int(s["points"])]
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 17)
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(note)


# Original textures are padded to powers of two: show only the used part.
static func cropped(path: String) -> Texture2D:
	var tex: Texture2D = load(path)
	var rect := tex.get_image().get_used_rect()
	if rect.size == Vector2i.ZERO or rect.size == Vector2i(tex.get_size()):
		return tex
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = Rect2(rect)
	return a


func _image(path: String, preset: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = cropped(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.set_anchors_preset(preset)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t


func _card(m: Dictionary, i: int) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(262, 230)
	var pic := TextureButton.new()
	pic.texture_normal = cropped("res://assets/textures/frontend/mapinfo/%s.png" % m["preview"])
	pic.ignore_texture_size = true
	pic.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(262, 150)
	pic.pressed.connect(func(): _select(i))
	box.add_child(pic)
	var name := Label.new()
	name.text = m["name"]
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_override("font", UiArt.font())
	name.add_theme_font_size_override("font_size", 30)
	box.add_child(name)
	var note := Label.new()
	note.text = m["note"]
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(note)
	return box


func _select(i: int) -> void:
	_selected = i
	for j in _cards.size():
		var c: Control = _cards[j]
		var picked := j == i
		c.modulate = Color.WHITE if picked else Color(0.55, 0.55, 0.55)
		(c.get_child(1) as Label).add_theme_color_override("font_color", RED if picked else Color(0.85, 0.85, 0.85))
	if extras:
		extras.selected(MAPS[i]["id"])


# achievement list over the menu (achievements_screen.gd)
func show_achievements() -> AchievementsScreen:
	if _achievements == null:
		_achievements = AchievementsScreen.new()
		add_child(_achievements)
		_achievements.closed.connect(func(): _achievements = null)
	return _achievements


func _unhandled_input(event: InputEvent) -> void:
	if _achievements != null or (extras and extras.overlay_open()):
		return
	if event.is_action_pressed("ui_right"):
		_select((_selected + 1) % MAPS.size())
	elif event.is_action_pressed("ui_left"):
		_select((_selected - 1 + MAPS.size()) % MAPS.size())
	elif event.is_action_pressed("ui_accept"):
		play.emit(MAPS[_selected]["id"])
