# Front-end pages over the menu (and the local leaderboard over the pause menu), with the
# original texts (assets/frontend_text.json, tools/frontend_text.py; the game shipped them
# in English only: italian.dat is a copy of english_uk.dat):
# - "help": fe_help -> "Game" (fe_helpgame: General, Barricades, Buying guns/items, Opening
#   areas, Bonus Pick-Ups, Last Stand, Perks) and "Performance" (fe_helpperformance);
#   Controls and Multiplayer are left out (different controls here, no co-op)
# - "credits": fe_credits, a CGuiSimpleScrollingFrame that starts after CreditsScrollDelay
#   ("2000" ms, kiwi 0x1b0094) and scrolls the labels up (speed estimated)
# - "about": fe_about (copyright, LS_ABOUT_VERSION with the bundle version)
# - "leaderboard": fe_local_leaderboard / ig_local_leaderboard, the 5 best games per map
#   (leaderboard.gd); from the pause menu it opens on the map being played
# Esc / INDIETRO closes it.
class_name ExtrasScreen
extends CanvasLayer

signal closed

const RED := Color(0.62, 0.04, 0.03)
const DATA := "res://assets/frontend_text.json"
const CREDITS_DELAY := 2.0     # CreditsScrollDelay 2000 ms
const CREDITS_SPEED := 60.0    # px/s at 720 px of height (estimate: not found in the data)
const TITLES := {"help": "AIUTO", "credits": "RICONOSCIMENTI", "about": "INFORMAZIONI", "leaderboard": "CLASSIFICA LOCALE"}

static var _data := {}

var page := "help"
var map := ""                  # leaderboard: map shown first
var _body: Control
var _tabs := []
var _scroll: ScrollContainer
var _credits_t := 0.0


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(DATA):
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = d if d is Dictionary else {}
	return _data


static func text(key: String, fallback := "") -> String:
	return String(data().get("text", {}).get(key, fallback))


func _init(p := "help", m := "") -> void:
	page = p
	map = m
	layer = 65
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	# original page chrome (frontend_art.gd): background, blood splats, title bar, Back
	var frame := Control.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var s := FrontendArt.unit(frame)
	FrontendArt.background(frame, Color(0.35, 0.35, 0.4))
	FrontendArt.blood_splats(frame, s, page.length() + 20)
	var t: String = TITLES.get(page, page.to_upper())
	FrontendArt.title_bar(frame, s, t.substr(0, 1) + t.substr(1).to_lower())

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 52 * s
	root.offset_bottom = -50 * s
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	root.add_child(tabs)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_body)
	var back := FrontendArt.back_button(self, s, close)
	match page:
		"help":
			_tab(tabs, "Gioco", _help.bind("game"))
			_tab(tabs, "Prestazioni", _help.bind("performance"))
			_help("game")
		"leaderboard":
			for m in Menu.MAPS:
				_tab(tabs, m["name"], _leaderboard.bind(m["id"]))
			_leaderboard(map if map != "" else String(Menu.MAPS[0]["id"]))
		"credits":
			_credits()
		"about":
			_about()
	back.grab_focus.call_deferred()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if page != "credits" or _scroll == null:
		return
	_credits_t += delta
	if _credits_t < CREDITS_DELAY:
		return
	var bar := _scroll.get_v_scroll_bar()
	var k := get_viewport().get_visible_rect().size.y / 720.0
	_scroll.scroll_vertical = int((_credits_t - CREDITS_DELAY) * CREDITS_SPEED * k)
	if _scroll.scroll_vertical >= bar.max_value - bar.page - 1 and _credits_t > CREDITS_DELAY + 1.0:
		_credits_t = 0.0   # from the top again
		_scroll.scroll_vertical = 0


func _tab(parent: Node, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.add_theme_font_override("font", UiArt.font())
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func():
		for t in _tabs:
			(t as Button).set_pressed_no_signal(t == b)
		cb.call())
	parent.add_child(b)
	_tabs.append(b)
	if _tabs.size() == 1:
		b.set_pressed_no_signal(true)


func _clear() -> VBoxContainer:
	for c in _body.get_children():
		c.queue_free()
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	_scroll.add_child(list)
	return list


func _label(parent: Node, t: String, size: int, color: Color, hud_font := false) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if hud_font:
		l.add_theme_font_override("font", UiArt.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


# Help sections: the original wraps its lines by hand for 480 px; here the text reflows.
func _help(which: String) -> void:
	var list := _clear()
	for sec in data().get("help", {}).get(which, []):
		_label(list, String(sec[0]), 30, Color(0.95, 0.85, 0.75), true)
		if String(sec[1]) != "":
			_label(list, _unwrap(String(sec[1])), 19, Color(0.82, 0.8, 0.78))
	if which == "game":
		_label(list, "", 8, Color.WHITE)
	_label(list, text("help_support"), 16, Color(0.55, 0.55, 0.55))


# "• a\n    b" -> "• a b": joins the hand-wrapped continuation lines of each bullet
static func _unwrap(t: String) -> String:
	var out := []
	for line in t.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("•") or out.is_empty():
			out.append(s)
		else:
			out[-1] += " " + s
	return "\n".join(out)


func _credits() -> void:
	var list := _clear()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var view_h := get_viewport().get_visible_rect().size.y
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, view_h * 0.5)
	list.add_child(pad)
	for t in data().get("credits", []):
		var s := String(t).strip_edges(false, true)
		# headings (upper-case lines, company names) larger, in the HUD font
		var heading := s.length() < 50 and not "\n" in s.strip_edges()
		var l := _label(list, s.strip_edges(true, false), 30 if heading else 20,
			Color(0.95, 0.3, 0.2) if heading else Color(0.85, 0.85, 0.85), heading)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 18 if heading else 30)
		list.add_child(gap)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, view_h * 0.6)
	list.add_child(tail)


func _about() -> void:
	var list := _clear()
	var title := _label(list, "Call of Duty: World at War – Zombies", 36, Color(0.95, 0.85, 0.75), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var about: Dictionary = data().get("about", {})
	var v := _label(list, String(about.get("version", "")), 22, Color(0.8, 0.8, 0.8))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 20)
	list.add_child(gap)
	var c := _label(list, String(about.get("copyright", "")), 18, Color(0.7, 0.7, 0.7))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label(list, "\nRemake personale in Godot %s degli asset e degli script originali (iOS 1.5.0, Ideaworks Airplay SDK). Non distribuito." % Engine.get_version_info()["string"], 16, Color(0.5, 0.5, 0.5))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _leaderboard(m: String) -> void:
	map = m
	for i in Menu.MAPS.size():
		if i < _tabs.size():
			(_tabs[i] as Button).set_pressed_no_signal(Menu.MAPS[i]["id"] == m)
	var list := _clear()
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list.add_child(grid)
	for h in ["", "Round", "Punti", "Uccisioni", "Colpi alla testa", "Data"]:
		_label(grid, h, 24, Color(0.95, 0.85, 0.75), true).autowrap_mode = TextServer.AUTOWRAP_OFF
	var rows := Leaderboard.entries(m)
	for i in Leaderboard.ROWS:
		var e: Dictionary = rows[i] if i < rows.size() else {}
		var cells := [Leaderboard.rank_text(i + 1)]
		if e.is_empty():
			cells += ["-", "-", "-", "-", ""]
		else:
			cells += [str(e.get("rounds", 0)), str(e.get("points", 0)), str(e.get("kills", 0)),
				str(e.get("headshots", 0)), _date(String(e.get("date", "")))]
		for j in cells.size():
			var l := _label(grid, cells[j], 28 if j < 5 else 20, RED.lightened(0.3) if j == 0 else Color(0.88, 0.88, 0.88), j < 5)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if rows.is_empty():
		var none := _label(list, "\nNessuna partita registrata su questa mappa (le partite in Recluta e in modalità DEBUG non contano).", 18, Color(0.6, 0.6, 0.6))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func _date(iso: String) -> String:
	var p := iso.split("-")
	return "%s/%s/%s" % [p[2], p[1], p[0]] if p.size() == 3 else iso
