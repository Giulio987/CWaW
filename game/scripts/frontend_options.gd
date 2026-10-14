# Additions of the original options and pause menu to pause_menu.gd (kept here so the
# pause menu itself changes little):
# - ig_settings / fe_settings: se_performanceleveltoggle ("High (slowest)" / "Medium" /
#   "Low (fastest)", the "Detail Level" of the help) and cl_autopausetoggle "Auto-Pause"
#   (Settings "detail_level", "auto_pause"; settings.gd apply_detail, save_game.gd Watcher)
# - fe_options / ig_options "Default Settings" (restoretofactory) with
#   ig_restoretofactoryyesno "Are you sure you want to reset your settings?"
# - a reset of achievements and statistics (not in the original), with confirmation; it
#   writes Achievements' current file (achievements_test.cfg in tests)
# - ig_pause "resetlevel" with ig_resetlevelyesno "Are you sure you want to restart the
#   level? Your progress will be lost.": a new game on the same map from round 1, the save
#   deleted (as the game over's Retry, game_over_screen.gd)
# The original's "In-Game Messages" is not an option: it is a heading of the multiplayer
# help (fe_helpmultiplayer, about system alerts during a game).
class_name FrontendOptions
extends RefCounted

const DETAIL := ["Alto (più lento)", "Medio", "Basso (più veloce)"]


static func add_rows(pm: PauseMenu, grid: GridContainer, box: VBoxContainer) -> void:
	grid.add_theme_constant_override("v_separation", 6)
	pm._row_label(grid, "Livello di dettaglio")
	var opt := OptionButton.new()
	for t in DETAIL:
		opt.add_item(t)
	opt.select(clampi(int(Settings.get_value("detail_level")), 0, 2))
	opt.item_selected.connect(func(i: int): Settings.set_value("detail_level", i))
	opt.name = "detail_level"
	opt.add_theme_font_size_override("font_size", 20)
	grid.add_child(opt)
	grid.add_child(Control.new())
	pm._check(grid, "Pausa automatica", "auto_pause")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for spec in [["Impostazioni predefinite", "defaults"], ["Azzera obiettivi e statistiche", "reset_stats"]]:
		var b := pm._button(spec[0], pm._show.bind(spec[1]), 28)
		b.custom_minimum_size = Vector2(380, 44)
		b.name = spec[1]
		row.add_child(b)
	# the page's "Indietro" (added after these rows) goes on the same line, to fit 720 px
	(func():
		var back := box.get_child(box.get_child_count() - 1) as Control
		if back != row and back is Button:
			back.reparent(row)
			row.move_child(back, 0)).call_deferred()


static func add_pages(pm: PauseMenu) -> void:
	pm._pages["restart"] = pm._page("Ricominciare il livello?\nI progressi andranno persi.", [
		["No", pm._show.bind("main")],
		["Sì", restart_level.bind(pm)],
	], 44)
	pm._pages["defaults"] = pm._page("Ripristinare le impostazioni predefinite?", [
		["No", pm._show.bind("settings")],
		["Sì", restore_defaults.bind(pm)],
	], 44)
	pm._pages["reset_stats"] = pm._page("Azzerare tutti gli obiettivi e le statistiche?\nNon si può annullare.", [
		["No", pm._show.bind("settings")],
		["Sì, azzera", reset_stats.bind(pm)],
	], 44)
	for k in ["restart", "defaults", "reset_stats"]:
		pm._pages[k].visible = false


static func restore_defaults(pm: PauseMenu) -> void:
	Settings.restore_defaults()
	# rebuild the settings page so its sliders show the defaults
	var old: Control = pm._pages["settings"]
	pm._pages["settings"] = pm._settings_page()
	old.queue_free()
	pm._show("settings")


static func reset_stats(pm: PauseMenu) -> void:
	var a := Achievements.instance
	if a:
		a.unlocked = {}
		a.stats = {}
		a.set("_dirty", true)
		a.save()
		print("[options] achievements and statistics reset (%s)" % a.get("_path"))
	pm._show("settings")


# Restart Level: like GameOverScreen._retry, from the pause menu.
static func restart_level(pm: PauseMenu) -> void:
	var g: Node = pm.game
	var tree := pm.get_tree()
	var main := tree.current_scene
	pm.visible = false
	tree.paused = false
	SaveGame.clear()   # "Your progress will be lost"
	if g == null or main == null or not main.has_method("_start"):
		tree.reload_current_scene()
		return
	var lvl: String = g.get("level_name")
	(func():
		main.remove_child(g)
		g.queue_free()
		main._start(lvl, PackedStringArray())).call_deferred()
