# Pieces of the original front-end pages, from the CIwGuiResource layouts of
# frontend.group.bin (fe_mainmenu, fe_singleplayer, fe_selectlevel, fe_view_achievements...):
# positions in the 480x320 units of the iPhone screen, scaled by the screen height (unit()).
# Layout values: each element has x, y, w, h (u16 value + type byte: 01 = pixels,
# 08 = fraction of the parent, 0x1000 = 1, 02 = parent size + value) and an anchor byte
# (low nibble x: 0 left / 1 centre / 2 right edge, high nibble y: 0 top / 1 centre / 2 bottom).
# - title bar: CIwGuiBitmap (0, 8) 480x40, atlas 2f66d01c (1,794)-(481,834); page title CGuiLabel
#   at (15, 12) h 36
# - menu rows: frame centred at y 60, rows of 40 (CGuiTouchButtonMenuItem), label at x 30, the
#   "highlight" bitmap atlas (0,750)-(480,790) behind the pressed row; disabled text 0x787878
# - Back: bottom-left 120x48, highlight atlas (268,224)-(390,255) 122x31, label at x 15
# - CGuiFrameBloodSplat: x 40 %..100 %, full height, six 128x128 splats c6054a8a..f
# - right panel 9dede741 (texture region (26,0)-(228,420)) at the right edge, 202 wide, full height
#   (fe_selectlevel, fe_view_achievements, the news frame of fe_mainmenu)
class_name FrontendArt
extends RefCounted

const TEX := "res://assets/textures/frontend/"
const TITLE_BAR := Rect2(1, 794, 480, 40)
const HIGHLIGHT := Rect2(0, 750, 480, 40)
const BACK_HL := Rect2(268, 224, 122, 31)
const ARROW := Rect2(108, 2, 44, 44)          # si_difficultytoggle arrow (tinted 0xab080c)
const BOTTOM_EDGE := Rect2(3, 636, 480, 85)   # fe_singleplayer description panel (drawn flipped)
const TOTAL_STROKE := Rect2(2, 838, 346, 61)  # fe_view_achievements "Total"/"Completed" stroke
const PANEL := "9dede741"
const PANEL_REGION := Rect2(26, 0, 202, 420)
const MAP_FRAME := "ad5ebcb2"                 # white frame behind the map thumbnail
const STAMP_COMPLETED := "4270e3c2"           # va_completed_bitmap, english_uk "completed"
const SPLATS := ["res://assets/textures/ingame/effects/c6054a8a.png", "res://assets/textures/ingame/effects/c6054a8b.png",
	"res://assets/textures/ingame/effects/c6054a8c.png", "res://assets/textures/ingame/effects/c6054a8d.png",
	TEX + "c6054a8e.png", TEX + "c6054a8f.png"]
const WHITE := Color(1, 1, 1)
const GREY := Color(0x78 / 255.0, 0x78 / 255.0, 0x78 / 255.0)
const RED_TEXT := Color(1, 0, 0)               # "Score:" / "Complete:" labels (colour ff0000)


# one original pixel in screen pixels
static func unit(n: Node) -> float:
	var vp := n.get_viewport()
	return (vp.get_visible_rect().size.y if vp else 720.0) / 320.0


# Places c at original coordinates; ax/ay: 0 = from the left/top, 1 = centre, 2 = from the
# right/bottom edge (x, y then measured from that anchor, the control's matching edge on it).
static func place(c: Control, s: float, x: float, y: float, w: float, h: float, ax := 0, ay := 0) -> void:
	var a := [0.0, 0.5, 1.0]
	c.anchor_left = a[ax]
	c.anchor_right = a[ax]
	c.anchor_top = a[ay]
	c.anchor_bottom = a[ay]
	c.offset_left = (x - a[ax] * w) * s
	c.offset_right = c.offset_left + w * s
	c.offset_top = (y - a[ay] * h) * s
	c.offset_bottom = c.offset_top + h * s


static func tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


static func image(parent: Node, t: Texture2D, flip_v := false, flip_h := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.flip_v = flip_v
	r.flip_h = flip_h
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


# full-screen black + the frontend background (a04fbb00, 480x320 used)
static func background(parent: Node, dim := Color(0.75, 0.75, 0.8)) -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var fog := image(parent, Menu.cropped(TEX + "a04fbb00.png"))
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fog.modulate = dim


# CGuiFrameBloodSplat: the six splats over the right 60 % of the page. Placement and size
# are not in the resource (all at 0,0, 128x128): spread at random, seeded per page so a page
# keeps its look (estimate).
static func blood_splats(parent: Node, s: float, seed_ := 0) -> Control:
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.anchor_left = 0.4
	frame.anchor_right = 1.0
	frame.anchor_bottom = 1.0
	parent.add_child(frame)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + seed_
	var vp := parent.get_viewport().get_visible_rect().size if parent.get_viewport() else Vector2(1280, 720)
	var fw := vp.x * 0.6 / s
	for i in SPLATS.size():
		var t := tex(SPLATS[i])
		if t == null:
			continue
		var r := image(frame, t)
		var size := rng.randf_range(96.0, 150.0)
		place(r, s, rng.randf_range(-20.0, fw - size + 20.0), rng.randf_range(-10.0, 320.0 - size + 10.0), size, size)
		r.pivot_offset = Vector2(size, size) * s * 0.5
		r.rotation = rng.randf_range(-PI, PI)
		r.modulate = Color(1, 1, 1, rng.randf_range(0.55, 0.85))
	return frame


# the title strip and the page title (CGuiLabel, title font: here the HUD font)
static func title_bar(parent: Node, s: float, text: String) -> Label:
	var bar := image(parent, UiArt.region(TITLE_BAR))
	place(bar, s, 0, 8, 480, 40)
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiArt.font())
	l.add_theme_font_size_override("font_size", int(24 * s))
	l.add_theme_color_override("font_color", WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	place(l, s, 15, 12, 450, 36)
	return l


# a menu row (CGuiTouchButtonMenuItem): highlight strip when hovered, focused or pressed
static func row(text: String, s: float, cb: Callable, size := 22.0) -> Button:
	var b := Button.new()
	b.text = text
	b.name = text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", UiArt.font())
	b.add_theme_font_size_override("font_size", int(size * s))
	b.add_theme_color_override("font_color", WHITE)
	for k in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, WHITE)
	b.add_theme_color_override("font_disabled_color", GREY)
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 30 * s
	var hl := StyleBoxTexture.new()
	hl.texture = UiArt.region(HIGHLIGHT)
	hl.content_margin_left = 30 * s
	b.add_theme_stylebox_override("normal", none)
	b.add_theme_stylebox_override("disabled", none)
	for k in ["hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(k, hl)
	b.custom_minimum_size = Vector2(0, 40 * s)
	b.pressed.connect(cb)
	return b


# rows stacked from y 60 (the original's button frame), full width unless w is given
static func rows(parent: Node, s: float, specs: Array, w := 0.0, y := 60.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	if w > 0.0:
		place(box, s, 0, y, w, 40 * specs.size())
	else:
		box.anchor_right = 1.0
		box.offset_top = y * s
		box.offset_bottom = (y + 40 * specs.size()) * s
	for spec in specs:
		box.add_child(row(spec[0], s, spec[1]))
	return box


# "Back" at the bottom-left
static func back_button(parent: Node, s: float, cb: Callable, text := "Indietro") -> Button:
	var b := Button.new()
	b.text = text
	b.name = "BACK"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", UiArt.font())
	b.add_theme_font_size_override("font_size", int(22 * s))
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, WHITE)
	var hl := StyleBoxTexture.new()
	hl.texture = UiArt.region(BACK_HL)
	hl.content_margin_left = 15 * s
	hl.expand_margin_left = 20 * s
	hl.expand_margin_top = -8 * s
	hl.expand_margin_bottom = -9 * s
	var normal := hl.duplicate()
	normal.modulate_color = Color(1, 1, 1, 0.85)
	for k in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(k, hl if k != "normal" else normal)
	parent.add_child(b)
	place(b, s, 0, 0, 120, 48, 0, 2)
	b.pressed.connect(cb)
	return b


# the right panel with blood drips (9dede741), 202 wide at the right edge
static func right_panel(parent: Node, s: float, w := 202.0) -> TextureRect:
	var a := AtlasTexture.new()
	a.atlas = tex(TEX + PANEL + ".png")
	a.region = PANEL_REGION
	var p := image(parent, a)
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -w * s
	return p
