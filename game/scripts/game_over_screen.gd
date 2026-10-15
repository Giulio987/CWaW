# Game over, as in the original (kiwi va 0x1b2f04 / update 0x1b318c):
#  - at death the GUI page ig_gameover_dead: the title "Game Over" (7865e519) and
#    go_survivedlabel LS_YOU_HAVE_SURVIVED "You Have Survived %d Rounds" (LS_YOU_HAVE_SURVIVED1
#    for one; the Italian table keeps the English text); the GameOverNukeEffect
#    "nuke_gameover" wave starts at the player (game.gd, radial_effect.gd); timer 3000 ms
#  - then the camera switches to "cam_flythrough" (end_camera.gd, EndCamera1..5), the
#    GameOverMusic CVar ("gameover_intro") plays and the page ig_gameover opens: the title,
#    gos_survivedlabel, "Points" / "Kills" / "Headshots" (gos_points, gos_kills,
#    gos_headshots) on a panel, the Retry button (gos_retryButton) and the way back to the
#    menu; next to it the map's local leaderboard (ig_local_leaderboard, 5 rows, ranks
#    LS_RANK_*), where the game is added. The HUD is hidden from the death on.
# The numbers are taken at the death (the game over wave still kills zombies afterwards).
class_name GameOverScreen
extends Control

const RED := Color(0.75, 0.05, 0.03)
const GREY := Color(0.85, 0.85, 0.85)
const DEAD_TIME := 3.0          # ig_gameover_dead timer (kiwi va 0x1b2fcc: 0xbb8 ms)
const MUSIC := "gameover_intro" # CVar GameOverMusic (va 0x1b3228)

var game: Node   # Game
var rank := 0
var stats_shown := false
var camera: EndCamera
var _rounds := 0
var _score := 0
var _kills := 0
var _headshots := 0
var _dead_page: Control


static func survived_text(rounds: int) -> String:
	return ("You Have Survived %d Round" if rounds == 1 else "You Have Survived %d Rounds") % rounds


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g = game
	_rounds = g.round_number
	_score = g.score
	_kills = g.kills
	_headshots = g.headshots
	var record := not Game.no_achievements() or OS.get_cmdline_user_args().has("--gameover-test")
	if record:
		rank = Leaderboard.add(g.level_name, _rounds, _score, _kills, _headshots)
	_hide_hud()
	_hide_layers()
	# ig_gameover_dead
	_dead_page = Control.new()
	_dead_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dead_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dead_page)
	_titles(_dead_page, 0.0)
	get_tree().create_timer(DEAD_TIME, false).timeout.connect(_show_stats)


# "Game Over" and the survived label, centred; `top` moves them up for the stats page
func _titles(parent: Control, top: float) -> void:
	for row in [["Game Over", 72, RED, -110.0], [survived_text(_rounds), 46, Color.WHITE, -20.0]]:
		var l := _label(row[0], row[1], row[2], parent)
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		l.offset_left = -600
		l.offset_right = 600
		l.offset_top = row[3] + top
		l.offset_bottom = row[3] + top + 90
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 8)


# Siblings in the HUD (points, ammo, perks, prompts...): hidden, also if they re-show
func _hide_hud() -> void:
	for c in get_parent().get_children():
		if c != self and c is CanvasItem:
			(c as CanvasItem).visible = false


# the item belts' own layers (grenade, molotov, betty icons: *_belt.gd)
func _hide_layers() -> void:
	for l in (game as Node).find_children("*", "CanvasLayer", true, false):
		if l != get_parent() and not l is GameFader:
			(l as CanvasLayer).visible = false


func _process(_d: float) -> void:
	_hide_hud()


func _show_stats() -> void:
	if not is_inside_tree() or stats_shown:
		return
	stats_shown = true
	_dead_page.queue_free()
	_hide_layers()
	camera = EndCamera.start(game)
	Sfx.instance.play(MUSIC)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_stats()


func _build_stats() -> void:
	var g = game
	var map: String = g.level_name
	var shade := ColorRect.new()   # light: the fly-through shows behind the page
	shade.color = Color(0, 0, 0, 0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	create_tween().tween_property(shade, "color:a", 0.3, 1.0)
	_titles(self, -230.0)

	# panel behind the numbers (ig_gameover: a CIwGuiBitmap under the labels)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.55)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -600
	panel.offset_right = 610
	panel.offset_top = -175
	panel.offset_bottom = 140
	add_child(panel)

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
	for row in [["Punti", _score], ["Uccisioni", _kills], ["Colpi alla testa", _headshots]]:
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
