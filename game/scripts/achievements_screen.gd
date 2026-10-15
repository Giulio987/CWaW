# Achievement list (menu Extra -> "Obiettivi", pause menu "Obiettivi"), laid out like the
# original fe_view_achievements (frontend.group.bin; pieces in frontend_art.gd):
# - title bar, blood splats, Back at the bottom-left; the groups of fe_achievements
#   ("Overall Achievements" plus one per map group) as tabs under the title
# - the list on the left (CGuiFrameAchievementList va_buttonContainer, highlight strip on the
#   selected row; here also the red tick / padlock of the HUD atlas and the points)
# - the right panel 9dede741 with the selected one: va_description (right edge 5, y 46,
#   190 wide), "Score:" / va_score, "Complete:" / va_complete (red labels, colour ff0000) and,
#   when unlocked, the va_completed_bitmap stamp "COMPLETED!" (4270e3c2, right edge on the
#   screen's, y 35 %, 256x128)
# - bottom right, over the red stroke (atlas (2,838)-(348,899)): "Total" (va_total, points)
#   and "Completed" (va_completed_num, "23/80")
# view(id): ig_viewachievement, opened by touching the unlock popup (hud_acheivementFrame
# achievementButton -> "viewachievement", achievements.gd): that one achievement, game paused.
# Esc / Indietro closes it.
class_name AchievementsScreen
extends CanvasLayer

signal closed

const TABS := [["Tutti", ""], ["Generali", "achievements"], ["Nacht der Untoten", "nacht_achievements"],
	["Verrückt", "verruckt_achievements"], ["Shi No Numa", "shinonuma_achievements"], ["Der Riese", "derriese_achievements"]]
const RED := Color(0.62, 0.04, 0.03)
const ROW_H := 22.0     # original units (the original's rows are 40: 106 achievements here)

var only_id := ""       # ig_viewachievement: just this one
var _list: VBoxContainer
var _summary: Label
var _scroll: ScrollContainer
var _tab_buttons := []
var _group := ""
var _s := 2.25
var _rows := {}         # id -> Button
var _sel := ""
var _d_name: Label
var _d_desc: Label
var _d_score: Label
var _d_complete: Label
var _stamp: TextureRect
var _total: Label
var _completed: Label
var _was_paused := false


func _init() -> void:
	layer = 65   # over the unlock popups (60)
	process_mode = Node.PROCESS_MODE_ALWAYS


static func view(id: String) -> AchievementsScreen:
	var a := AchievementsScreen.new()
	a.only_id = id
	return a


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_s = FrontendArt.unit(root)
	var s := _s
	if only_id != "":
		# ig_viewachievement: a full-screen bitmap with no texture, colour 969696, over the paused
		# game. Its image alpha byte is 2 (maybe IwMaterial ALPHA_ADD, not confirmed): drawn as
		# half-transparent grey, an additive grey washed the screen out (estimate)
		var grey := ColorRect.new()
		grey.color = Color8(0x96, 0x96, 0x96, 0x80)
		grey.set_anchors_preset(Control.PRESET_FULL_RECT)
		grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(grey)
	else:
		FrontendArt.background(root, Color(0.5, 0.5, 0.55))
		FrontendArt.blood_splats(root, s, 11)
	FrontendArt.title_bar(root, s, Lang.t("Obiettivi"))
	var vw := root.get_viewport().get_visible_rect().size.x / s
	var list_w := vw - 202.0

	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", int(2 * s))
	root.add_child(tabs)
	FrontendArt.place(tabs, s, 8, 50, list_w - 8, 20)
	for t in TABS:
		var b := Button.new()
		b.text = Lang.maybe(t[0])
		b.toggle_mode = true
		b.add_theme_font_override("font", UiArt.font())
		b.add_theme_font_size_override("font_size", int(9 * s))
		b.pressed.connect(_select.bind(t[1]))
		tabs.add_child(b)
		_tab_buttons.append(b)
	tabs.visible = only_id == ""

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	FrontendArt.place(_scroll, s, 0, 74 if only_id == "" else 60, list_w - 4, 0)
	_scroll.anchor_bottom = 1.0
	_scroll.offset_bottom = -50 * s
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_scroll.add_child(_list)

	# right panel
	FrontendArt.right_panel(root, s)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", int(1 * s))
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(info)
	FrontendArt.place(info, s, -5, 46, 190, 200, 2, 0)
	_d_name = _info_label(info, 13, Color.WHITE, true)
	_d_desc = _info_label(info, 8.5, Color(0.92, 0.9, 0.88))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4 * s)
	info.add_child(gap)
	_info_label(info, 10, FrontendArt.RED_TEXT, true).text = Lang.t("Punteggio:")
	_d_score = _info_label(info, 11, Color.WHITE, true)
	_info_label(info, 10, FrontendArt.RED_TEXT, true).text = Lang.t("Completamento:")
	_d_complete = _info_label(info, 11, Color.WHITE, true)
	_stamp = FrontendArt.image(root, FrontendArt.tex(FrontendArt.TEX + FrontendArt.STAMP_COMPLETED + ".png"))
	FrontendArt.place(_stamp, s, 0, 0, 256, 128, 2, 0)
	_stamp.anchor_top = 0.35
	_stamp.anchor_bottom = 0.35
	_stamp.visible = false
	_stamp.name = "CompletedStamp"
	# bottom right: Total / Completed
	var stroke := FrontendArt.image(root, UiArt.region(FrontendArt.TOTAL_STROKE))
	FrontendArt.place(stroke, s, 0, 0, 346, 75, 2, 2)
	stroke.anchor_left = 1.15
	stroke.anchor_right = 1.15
	var totals := GridContainer.new()
	totals.columns = 2
	totals.add_theme_constant_override("h_separation", int(6 * s))
	totals.add_theme_constant_override("v_separation", 0)
	root.add_child(totals)
	FrontendArt.place(totals, s, -5, -4, 190, 40, 2, 2)
	_info_label(totals, 10, Color.BLACK, true).text = Lang.t("Totale")
	_total = _info_label(totals, 10, Color.WHITE, true)
	_info_label(totals, 10, Color.BLACK, true).text = Lang.t("Completati")
	_completed = _info_label(totals, 10, Color.WHITE, true)
	for l in [_total, _completed]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary = _total   # (kept for callers reading the summary)

	FrontendArt.back_button(root, s, close)
	if only_id != "":
		_was_paused = get_tree().paused
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_select("")


func _info_label(parent: Node, size: float, color: Color, hud := false) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if not parent is GridContainer else TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if hud:
		l.add_theme_font_override("font", UiArt.font())
	l.add_theme_font_size_override("font_size", int(size * _s))
	l.add_theme_color_override("font_color", color)
	if color == Color.BLACK:
		l.add_theme_color_override("font_color", Color(0.1, 0.0, 0.0))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func close() -> void:
	if only_id != "" and is_inside_tree():
		get_tree().paused = _was_paused
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
	_rows.clear()
	var a := Achievements.instance
	if a == null:
		return
	var shown := 0
	var got := 0
	var pts := 0
	var all_pts := 0
	var first := ""
	for e in a.entries:
		if only_id != "" and String(e["id"]) != only_id:
			continue
		if only_id == "" and _group != "" and e["group"] != _group:
			continue
		var done := a.unlocked.has(String(e["id"]))
		shown += 1
		got += int(done)
		all_pts += e["points"]
		pts += e["points"] if done else 0
		var b := _row(e, done)
		_list.add_child(b)
		_rows[String(e["id"])] = b
		if first == "":
			first = String(e["id"])
	_total.text = "%d/%d" % [pts, all_pts]
	_completed.text = "%d/%d" % [got, shown]
	_scroll.scroll_vertical = 0
	show_entry(first)


func _row(e: Dictionary, done: bool) -> Button:
	var s := _s
	var b := FrontendArt.row(Achievements.title_of(e), s, show_entry.bind(String(e["id"])), 11.0)
	b.custom_minimum_size = Vector2(0, ROW_H * s)
	b.clip_text = true
	for k in ["normal", "disabled", "hover", "pressed", "focus", "hover_pressed"]:
		var sb := b.get_theme_stylebox(k).duplicate() as StyleBox
		sb.content_margin_left = 30 * s
		sb.content_margin_right = 26 * s
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_color_override("font_color", Color(0.98, 0.92, 0.85) if done else Color(0.72, 0.72, 0.72))
	b.mouse_entered.connect(show_entry.bind(String(e["id"])))
	b.focus_entered.connect(show_entry.bind(String(e["id"])))
	var icon := TextureRect.new()
	icon.texture = UiArt.region(Achievements.ICON_DONE if done else Achievements.ICON_LOCKED)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color.WHITE if done else Color(1.7, 1.7, 1.7)   # the atlas padlock is dark grey
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	FrontendArt.place(icon, s, 6, 3, 20, ROW_H - 6)
	var points := Label.new()
	points.text = str(e["points"])
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	points.add_theme_font_override("font", UiArt.font())
	points.add_theme_font_size_override("font_size", int(10 * s))
	points.add_theme_color_override("font_color", UiArt.POINTS if done else Color(0.5, 0.5, 0.5))
	points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(points)
	points.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	points.offset_right = -4 * s
	if not e["available"] and not done:
		b.modulate = Color(1, 1, 1, 0.55)
	return b


# the right panel for one achievement
func show_entry(id: String) -> void:
	_sel = id
	var a := Achievements.instance
	if a == null or id == "" or not a.by_id.has(id.to_lower()):
		_d_name.text = ""
		_d_desc.text = ""
		_d_score.text = ""
		_d_complete.text = ""
		_stamp.visible = false
		return
	var e: Dictionary = a.by_id[id.to_lower()]
	var done := a.unlocked.has(String(e["id"]))
	_d_name.text = Achievements.title_of(e)
	var text: String = Achievements.desc_of(e)
	if not e["available"]:
		text += "\n" + Lang.t("(non disponibile in questa versione)")
	if done:
		var when := Time.get_datetime_dict_from_unix_time(int(a.unlocked[String(e["id"])]) + _tz())
		text += "\n" + Lang.t("Sbloccato il %02d/%02d/%d") % [when["day"], when["month"], when["year"]]
	_d_desc.text = text
	_d_score.text = str(e["points"])
	var pr := a.progress(e["num"])
	if done:
		_d_complete.text = "100%"
	elif not pr.is_empty() and pr[1] > 0:
		_d_complete.text = "%d%%  (%s / %s)" % [int(100.0 * minf(pr[0], pr[1]) / pr[1]), _num(minf(pr[0], pr[1])), _num(pr[1])]
	else:
		_d_complete.text = "0%"
	_stamp.visible = done
	for k in _rows:
		var b := _rows[k] as Button
		if b and is_instance_valid(b):
			b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover") if k == id else b.get_theme_stylebox("disabled"))


static func _num(v: float) -> String:
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _tz() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
