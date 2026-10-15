# The original loading page (bootstrap.group.bin "loading", console LoadingScreenGuiPage):
# a black full-screen bitmap, an empty centred label (the "Loading" string 6e0a0761 is not used
# by any resource or code) and the CIwGuiRotatingFrame "lo_spinner": a 32x32 bitmap of
# f6bbb293 centred at (50 %, 60 %) of the 480x320 screen. CLoadingScreen (kiwi va 0x15912c)
# turns it by LoadingSpinnerSpeed (150, in 1/4096 of a turn) at each loading callback,
# every LoadingScreenCallbackMs (200 ms): steps of 13.2 degrees.
# Shown from the map choice until the level is ready (navigation baked, game._begin).
class_name LoadingScreen
extends CanvasLayer

const SPINNER := "res://assets/textures/bootstrap/f6bbb293.png"
const STEP := 150.0 / 4096.0 * TAU    # LoadingSpinnerSpeed
const PERIOD := 0.2                   # LoadingScreenCallbackMs 200
const TIMEOUT := 60.0

var _spin: TextureRect
var _t := 0.0
var _life := 0.0
var _game: Node


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "LoadingScreen"


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var s := FrontendArt.unit(bg)
	_spin = TextureRect.new()
	_spin.texture = FrontendArt.tex(SPINNER)
	_spin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spin.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_spin)
	FrontendArt.place(_spin, s, 0, 320 * 0.6, 32, 32, 1, 0)
	_spin.offset_top -= 16 * s       # centred on 60 % (anchor byte 0x11)
	_spin.offset_bottom -= 16 * s
	_spin.pivot_offset = Vector2(16, 16) * s


# shown over the menu; frees itself when the level of the next Game is ready
static func show_over(tree: SceneTree) -> LoadingScreen:
	var l := LoadingScreen.new()
	tree.root.add_child.call_deferred(l)   # (the root may be busy setting up children)
	return l


func _process(delta: float) -> void:
	_life += delta
	_t += delta
	while _t >= PERIOD:
		_t -= PERIOD
		_spin.rotation = fmod(_spin.rotation + STEP, TAU)
	if _game == null or not is_instance_valid(_game):
		_game = null
		var main := get_tree().current_scene
		for n in (main.get_children() if main else []):
			if n is Game:
				_game = n
				break
		if _game:
			var lvl = _game.get("level")
			if lvl and bool(lvl.get("nav_ready")):
				queue_free()
			elif lvl and lvl.has_signal("navigation_ready"):
				lvl.navigation_ready.connect(queue_free, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
			else:
				_game = null
	if _life > TIMEOUT:
		queue_free()
