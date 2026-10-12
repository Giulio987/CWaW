# Achievement list (main menu "OBIETTIVI", pause menu "Obiettivi"): like the
# original frontend page (CFrontendStateAchievements: "Overall Achievements" plus one
# page per map group), every achievement with its icon (red tick when unlocked,
# padlock when not, from the HUD atlas), name, description, points and, for the
# counted ones, the progress. Esc / INDIETRO closes it.
class_name AchievementsScreen
extends CanvasLayer

signal closed

const TABS := [["Tutti", ""], ["Generali", "achievements"], ["Nacht der Untoten", "nacht_achievements"],
	["Verrückt", "verruckt_achievements"], ["Shi No Numa", "shinonuma_achievements"], ["Der Riese", "derriese_achievements"]]
const RED := Color(0.62, 0.04, 0.03)

var _list: VBoxContainer
var _summary: Label
var _scroll: ScrollContainer
var _tab_buttons := []
var _group := ""


func _init() -> void:
	layer = 65   # over the unlock popups (60)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var fog := TextureRect.new()
	fog.texture = load("res://assets/textures/frontend/a04fbb00.png") if ResourceLoader.exists("res://assets/textures/frontend/a04fbb00.png") else null
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fog.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fog.modulate = Color(0.35, 0.35, 0.4, 0.5)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fog)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "OBIETTIVI"
	title.add_theme_font_override("font", UiArt.font())
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", RED)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_summary = Label.new()
	_summary.add_theme_font_override("font", UiArt.font())
	_summary.add_theme_font_size_override("font_size", 24)
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_summary)

	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	root.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = t[0]
		b.toggle_mode = true
		b.add_theme_font_override("font", UiArt.font())
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_select.bind(t[1]))
		tabs.add_child(b)
		_tab_buttons.append(b)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)

	var back := Button.new()
	back.text = "INDIETRO"
	back.flat = true
	back.add_theme_font_override("font", UiArt.font())
	back.add_theme_font_size_override("font_size", 36)
	back.add_theme_color_override("font_color", RED)
	back.add_theme_color_override("font_hover_color", Color(1, 0.2, 0.1))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	root.add_child(back)
	_select("")


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _select(group: String) -> void:
	_group = group
	for i in TABS.size():
		(_tab_buttons[i] as Button).set_pressed_no_signal(TABS[i][1] == group)
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var a := Achievements.instance
	if a == null:
		return
	var shown := 0
	var got := 0
	var pts := 0
	var all_pts := 0
	for e in a.entries:
		if _group != "" and e["group"] != _group:
			continue
		var done := a.unlocked.has(String(e["id"]))
		shown += 1
		got += int(done)
		all_pts += e["points"]
		pts += e["points"] if done else 0
		_list.add_child(_row(a, e, done))
	var what: String = "Obiettivi complessivi" if _group == "" else TABS.filter(func(t): return t[1] == _group)[0][0]
	_summary.text = "%s: %d/%d  ·  %d/%d punti" % [what, got, shown, pts, all_pts]
	_scroll.scroll_vertical = 0


func _row(a: Achievements, e: Dictionary, done: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.03, 0.02, 0.75) if done else Color(0.08, 0.08, 0.09, 0.7)
	sb.content_margin_left = 10
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UiArt.region(Achievements.ICON_DONE if done else Achievements.ICON_LOCKED)
	icon.custom_minimum_size = Vector2(44, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color.WHITE if done else Color(1.7, 1.7, 1.7)   # the atlas padlock is dark grey
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var title := Label.new()
	title.text = e["it_name"]
	title.add_theme_font_override("font", UiArt.font())
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.8) if done else Color(0.78, 0.78, 0.78))
	col.add_child(title)
	var desc := Label.new()
	var text: String = e["it_desc"]
	if not e["available"]:
		text += "  (non disponibile in questa versione)"
	elif not done:
		var pr := a.progress(e["num"])
		if not pr.is_empty():
			text += "  —  %s / %s" % [_num(minf(pr[0], pr[1])), _num(pr[1])]
	if done:
		var when := Time.get_datetime_dict_from_unix_time(int(a.unlocked[String(e["id"])]) + _tz())
		text += "  —  sbloccato il %02d/%02d/%d" % [when["day"], when["month"], when["year"]]
	desc.text = text
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.62, 0.6, 0.58) if e["available"] else Color(0.45, 0.45, 0.45))
	col.add_child(desc)
	var points := Label.new()
	points.text = str(e["points"])
	points.add_theme_font_override("font", UiArt.font())
	points.add_theme_font_size_override("font_size", 26)
	points.add_theme_color_override("font_color", UiArt.POINTS if done else Color(0.5, 0.5, 0.5))
	points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(points)
	if not e["available"] and not done:
		panel.modulate = Color(1, 1, 1, 0.55)
	return panel


static func _num(v: float) -> String:
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _tz() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
