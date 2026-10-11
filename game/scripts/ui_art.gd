# Shared art for the WaW-style UI: regions of the original HUD atlas
# (fixed/2f66d01c.png) and the original HUD bitmap font (CIwGxFont 0xda9dc767,
# extracted by tools/fonts.py to assets/fonts/hud.fnt).
class_name UiArt
extends RefCounted

const ATLAS := "res://assets/textures/fixed/2f66d01c.png"
const FONT := "res://assets/fonts/hud.fnt"
# measured on the atlas (alpha bounding boxes)
const TALLY_STROKES := [Rect2(117, 110, 6, 37), Rect2(127, 110, 4, 41), Rect2(136, 110, 5, 40), Rect2(146, 111, 6, 38)]
const TALLY_FIVE := Rect2(154, 110, 48, 41)
const PAUSE_ICON := Rect2(350, 132, 24, 24)
const RED_SMEAR := Rect2(140, 59, 148, 38)
const RED := Color(0.75, 0.05, 0.03)       # round number red
const POINTS := Color(1.0, 0.93, 0.55)    # points counter / gained points
const SPENT := Color(0.85, 0.08, 0.05)

static var _font: Font
static var _cache := {}


static func region(r: Rect2) -> AtlasTexture:
	if _cache.has(r):
		return _cache[r]
	var a := AtlasTexture.new()
	a.atlas = load(ATLAS)
	a.region = r
	_cache[r] = a
	return a


# Original HUD font (white glyphs, dark outline: tint with font_color);
# characters missing from the bitmap (accents) fall back to the default font.
static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT):
			var f: FontFile = load(FONT)
			f.fallbacks = [ThemeDB.fallback_font]
			_font = f
		else:
			_font = ThemeDB.fallback_font
	return _font
