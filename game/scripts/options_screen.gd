# Main menu "OPZIONI" (fe_options/fe_settings): the pause menu's settings page on its own,
# over the menu; going back from it closes the screen.
class_name OptionsScreen
extends PauseMenu

var _opening := false


func _ready() -> void:
	super._ready()
	_shade.color = Color(0, 0, 0, 0.93)   # over the menu, not over the game


func open_options() -> void:
	_opening = true
	open()
	_opening = false
	_show("settings")


func _show(name: String) -> void:
	if name == "main" and not _opening:
		close()
		queue_free()
		return
	super._show(name)
