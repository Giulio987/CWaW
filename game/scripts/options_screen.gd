# Main menu Options entries (fe_options -> fe_settings, fe_restoretofactoryyesno): the pause
# menu's settings page (or the Default Settings confirmation) on its own, over the menu; going
# back to the pause menu's main or options page closes the screen (the menu has its own
# Options page, frontend_menu.gd).
class_name OptionsScreen
extends PauseMenu

var _opening := false


func _ready() -> void:
	super._ready()
	_shade.color = Color(0, 0, 0, 0.93)   # over the menu, not over the game


func open_options(first := "settings") -> void:
	_opening = true
	open()
	_opening = false
	_show(first)


func _show(name: String) -> void:
	if (name == "main" or name == "options") and not _opening:
		close()
		queue_free()
		return
	super._show(name)
