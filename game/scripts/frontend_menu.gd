# Additions to the main menu (menu.gd) from the original frontend: the music mx_frontend and
# menu_press (ui_sound.gd), the map description of the level select screen (CMapInfo,
# sv_description) for the selected map, and the entries of fe_options / fe_extras:
# Opzioni (settings, options_screen.gd), Aiuto (fe_help), Classifiche (local leaderboards),
# Riconoscimenti (fe_credits), Informazioni (fe_about) - extras_screen.gd.
class_name FrontendMenu
extends Control

var menu: Menu
var _desc: Label
var _title: Label
var _overlay: Node


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
	# right: the extra entries
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	col.offset_left = -300
	col.offset_right = -24
	col.offset_top = 24
	col.offset_bottom = 300
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	for spec in [["OPZIONI", open_options], ["AIUTO", open_page.bind("help")],
			["CLASSIFICHE", open_page.bind("leaderboard")], ["RICONOSCIMENTI", open_page.bind("credits")],
			["INFORMAZIONI", open_page.bind("about")]]:
		var b := Button.new()
		b.text = spec[0]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_theme_font_override("font", UiArt.font())
		b.add_theme_font_size_override("font_size", 32)
		b.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		b.add_theme_color_override("font_hover_color", Color(1, 0.2, 0.1))
		b.add_theme_color_override("font_focus_color", Color(1, 0.2, 0.1))
		b.pressed.connect(spec[1])
		b.name = spec[0]
		col.add_child(b)
	# left: the selected map's description
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.offset_left = 28
	box.offset_right = 370
	box.offset_top = 30
	box.offset_bottom = 300
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_override("font", UiArt.font())
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Menu.RED.lightened(0.2))
	box.add_child(_title)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 17)
	_desc.add_theme_color_override("font_color", Color(0.82, 0.8, 0.78))
	_desc.add_theme_color_override("font_outline_color", Color.BLACK)
	_desc.add_theme_constant_override("outline_size", 3)
	box.add_child(_desc)


# menu.gd _select
func selected(map_id: String) -> void:
	if _desc == null:
		return
	var m: Dictionary = ExtrasScreen.data().get("maps", {}).get(map_id, {})
	_title.text = String(m.get("title", ""))
	_desc.text = String(m.get("desc", "")).replace("\n\n", "\n")


func overlay_open() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


func open_page(page: String) -> ExtrasScreen:
	var s := ExtrasScreen.new(page)
	menu.add_child(s)
	_overlay = s
	return s


func open_options() -> OptionsScreen:
	var o := OptionsScreen.new()
	menu.add_child(o)
	o.open_options()
	_overlay = o
	return o
