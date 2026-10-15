# CGuiFrameGameFader "fader" of the in-game HUD (ui.group 0b887cc6): a black bitmap
# (9902db54) whose alpha follows a timer (kiwi va 0x1976c0: elapsed / duration, reversed
# when fading in). Its default duration (field 0x94) is 1000 ms. The HUD reset at the start
# of a game (va 0x1294c4) starts it fading in from black with that duration; the only
# other caller is the Lua Game.FadeScreen (va 0x743ec), used by tutorial.lua alone: there
# is no fade at the end of a game (the game over shows ig_gameover_dead at once).
# Drawn under the HUD (the fader comes before the HUD's later frames), above the world.
class_name GameFader
extends CanvasLayer

const DURATION := 1.0

var _rect: ColorRect


# Fade-in from black at the start of a game (game.gd _begin). Skipped for the debug
# captures (any "--" option but the game over test) so their screenshots are not dark.
static func fade_in(parent: Node) -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--gameover-test") and Array(args).any(func(a: String): return a.begins_with("--")):
		return
	var f := GameFader.new()
	parent.add_child(f)
	f.fade(true)


func _ready() -> void:
	layer = 0
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func fade(fade_in_: bool, seconds := DURATION) -> void:
	_rect.color.a = 1.0 if fade_in_ else 0.0
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 0.0 if fade_in_ else 1.0, seconds)
	if fade_in_:
		tw.tween_callback(queue_free)
