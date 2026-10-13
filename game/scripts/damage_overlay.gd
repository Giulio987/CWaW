# Damage overlay of the original HUD (CGuiFrameHUD 0b887cc6, kiwi 0xc3b3c):
# "DamageBitmapTop" (480x85 along the top edge, atlas 3,616-483,721) and
# "DamageBitmapBottom" (480x100 along the bottom edge, atlas 3,513-483,613), two grunge
# strips of the HUD atlas tinted blood red (170, 9, 13) that show the player's damage.
# (CGuiFrameBloodSplat is the front end's blood splat, not used in game.)
class_name DamageOverlay
extends Control

const TOP := Rect2(3, 616, 480, 105)
const BOTTOM := Rect2(3, 513, 480, 100)
const TOP_H := 85.0 / 320.0      # share of the screen height
const BOTTOM_H := 100.0 / 320.0
const TINT := Color8(170, 9, 13)

var level := 0.0   # 0 unhurt .. 1 about to go down
var _top: TextureRect
var _bottom: TextureRect
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top = _strip(TOP, 0.0, TOP_H)
	_bottom = _strip(BOTTOM, 1.0 - BOTTOM_H, 1.0)


func _strip(r: Rect2, top: float, bottom: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UiArt.region(r)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate = Color(TINT, 0.0)
	add_child(t)
	t.anchor_left = 0.0
	t.anchor_right = 1.0
	t.anchor_top = top
	t.anchor_bottom = bottom
	t.offset_left = 0
	t.offset_top = 0
	t.offset_right = 0
	t.offset_bottom = 0
	return t


# health fraction left; a hit also flashes the strips
func set_health(frac: float, hit: bool) -> void:
	var l := clampf(1.0 - frac, 0.0, 1.0)
	if hit and l > level:
		_flash = 1.0
	level = l


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.0, 0.0)
	var a := clampf(level * 0.75 + _flash * 0.25, 0.0, 0.9)
	_top.modulate.a = a
	_bottom.modulate.a = a
