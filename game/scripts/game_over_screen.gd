# Game over screen after ig_gameover (ui.group.bin): "gos_survivedlabel" with
# LS_YOU_HAVE_SURVIVED "You Have Survived %d Rounds" (LS_YOU_HAVE_SURVIVED1 for one),
# "Points" / "Kills" / "Headshots" (gos_points, gos_kills, gos_headshots), the Retry
# button (gos_retryButton) and the way back to the menu; next to it the map's local
# leaderboard (ig_local_leaderboard, 5 rows, ranks LS_RANK_*), where the game is added.
class_name GameOverScreen
extends Control

const RED := Color(0.75, 0.05, 0.03)
const GREY := Color(0.85, 0.85, 0.85)

var game: Node   # Game
var rank := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var g = game
	var rounds: int = g.round_number
	var map: String = g.level_name
	var record := not Game.no_achievements() or OS.get_cmdline_user_args().has("--gameover-test")
	if record:
		rank = Leaderboard.add(map, rounds, g.score, g.kills, g.headshots)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	create_tween().tween_property(shade, "color:a", 0.78, 1.5)

	var smear := TextureRect.new()
	smear.texture = UiArt.region(UiArt.RED_SMEAR)
	smear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	smear.stretch_mode = TextureRect.STRETCH_SCALE
	smear.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	smear.offset_left = -430
	smear.offset_right = 430
	smear.offset_top = 40
	smear.offset_bottom = 150
	smear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(smear)
	var title := _label("Sei sopravvissuto a %d round" % rounds, 54, Color.WHITE)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -500
	title.offset_right = 500
	title.offset_top = 58
	title.offset_bottom = 130
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# left: this game; right: the leaderboard
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 40)
	stats.add_theme_constant_override("v_separation", 14)
	stats.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	stats.offset_left = -560
	stats.offset_right = -160
	stats.offset_top = -150
	stats.offset_bottom = 60
	add_child(stats)
	for row in [["Punti", g.score], ["Uccisioni", g.kills], ["Colpi alla testa", g.headshots]]:
		var k := _label(row[0], 34, GREY, stats)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := _label(str(row[1]), 40, UiArt.POINTS, stats)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 6)
	board.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	board.offset_left = -60
	board.offset_right = 580
	board.offset_top = -170
	board.offset_bottom = 120
	add_child(board)
	_label("Classifica · %s" % _map_name(map), 30, RED, board)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	board.add_child(grid)
	for h in ["", "Round", "Punti", "Uccisioni", "Testa"]:
		_label(h, 20, Color(0.6, 0.6, 0.6), grid)
	var list := Leaderboard.entries(map)
	for i in Leaderboard.ROWS:
		var mine := i + 1 == rank
		var col := UiArt.POINTS if mine else GREY
		if i < list.size():
			var e: Dictionary = list[i]
			for v in [Leaderboard.rank_text(i + 1), e["rounds"], e["points"], e["kills"], e["headshots"]]:
				_label(str(v), 26, col, grid)
		else:
			for v in [Leaderboard.rank_text(i + 1), "-", "-", "-", "-"]:
				_label(v, 26, Color(0.45, 0.45, 0.45), grid)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 80)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	buttons.offset_left = -400
	buttons.offset_right = 400
	buttons.offset_top = -150
	buttons.offset_bottom = -70
	add_child(buttons)
	var retry := _button("RIPROVA", buttons)
	retry.pressed.connect(_retry)
	var menu := _button("MENU PRINCIPALE", buttons)
	menu.pressed.connect(_to_menu)
	retry.grab_focus.call_deferred()


func _label(text: String, size: int, color: Color, parent: Node = self) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiArt.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(text: String, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_override("font", UiArt.font())
	b.add_theme_font_size_override("font_size", 46)
	b.add_theme_color_override("font_color", RED)
	b.add_theme_color_override("font_hover_color", Color(1, 0.2, 0.1))
	b.add_theme_color_override("font_focus_color", Color(1, 0.2, 0.1))
	parent.add_child(b)
	return b


static func _map_name(id: String) -> String:
	for m in Menu.MAPS:
		if m["id"] == id:
			return m["name"]
	return id


# Retry: the same map again, from a fresh game (main.gd _start).
func _retry() -> void:
	var main := get_tree().current_scene
	var g: Node = game
	var lvl: String = g.level_name
	get_tree().paused = false
	if main == null or not main.has_method("_start"):
		get_tree().reload_current_scene()
		return
	(func():
		main.remove_child(g)
		g.queue_free()
		main._start(lvl, PackedStringArray())).call_deferred()


func _to_menu() -> void:
	var main := get_tree().current_scene
	var g: Node = game
	get_tree().paused = false
	if main == null or not main.has_method("_show_menu"):
		get_tree().reload_current_scene()
		return
	(func():
		main.remove_child(g)
		g.queue_free()
		main._show_menu(false)).call_deferred()
