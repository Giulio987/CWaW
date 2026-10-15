# Weapon icon and ammo of the original HUD (ingame/ui/ui.group.bin, 480x320 HUD,
# drawn here at SCALE and anchored to the top right corner like the original):
#
# "hud_guns" (CIwGuiFrame, right-aligned at the top, 219x62): a dark smear (atlas
# 295,39-514,101 at +60,-5) and "gunIcon", a CGuiTouchButtonIcon over the whole frame
# whose CGuiTouchActionPlayerInput reloads (tap) or switches weapon (double tap). Inside, a 130x40
# frame at the right edge holds "gunImageFrame", a CIwGuiMultiFrame with one bitmap
# per gun, named after the gun: CGuiInGameHud (kiwi va 0x129730..0x1297a8) shows the
# child named like the held CItemGun, or like its base gun for a Pack-a-Punch
# "_upgrade" (CItemGun +0xf4). Rects x0 > x1 are mirrored: every gun points left.
# The "flamethrower" child is an empty frame: that gun shows its fuel instead.
#
# "ammos_container" (right-aligned at the top, 150x50) of CGuiFrameHUD 0b887cc6,
# updated by kiwi va 0x13d008 (clip setup 0x13bb64, drawing 0x13c394):
#  - normal guns: the magazine drawn from the point "ammoRightBottom" (67 px from the
#    right edge, 25 px down) towards the left over the 83 px left of it:
#      * up to 20 rounds (mag x ClipVertBarWidth x 2 < 83): ClipVertBar 2x10 bars,
#        ClipHoriBarOffsetX 2 apart; with a CItemGun ammo type (+0x108) "shotgun" or
#        "rifle" the bitmaps <type>AmmoFull / <type>AmmoEmpty of hud_guns instead
#        (13x7 shells, 16x6 rifle rounds), ClipBitmapXOffset 25 / YOffset 2 further
#        right / down, a new row after ClipBitmapWidth 50 px;
#      * more: ClipHoriBar 5x2 bars in rows (ClipHoriBarOffsetX 2, OffsetY 10), half
#        height when they need more than ClipHoriBarNumRowUseHalfHeight 4 rows;
#    rounds still in the magazine (the right ones) in colourAmmoPresent, spent ones
#    in colourAmmoConsumed; the clip is "low" at LowClipPercentage 35 % or 1 round
#    left and then blinks in colourAmmoLow (AmmoBlinkTime 500 ms);
#  - "ammos_count": the reserve ("%d"), colourAmmoText, colourAmmoLow at or below
#    LowAmmoPercentage 20 % of the full reserve;
#  - magazine and reserve empty: no clip, no count, "noAmmoLabel" ("No Ammo", 07d8bba9)
#    centred at 23.5 % of the screen height, in colourAmmoLow, glowing
#    (NoAmmoGlowPeriodMs: no value in console.bin, HudGlowPeriodMs 1000 used);
#  - flamethrower (CItemGun +0x5d): "flamethrower_ammo", the grey flamethrower picture
#    (atlas 267,158 81x32) with the red one ("flamethrower_fuel", CGuiClippedBitmap,
#    267,190) clipped to the fuel left (kiwi va 0x13d13c), no count.
# Colours of CGuiInGameHud: present 808080, consumed 404040, low c80000, text ffffff.
class_name WeaponHud
extends Control

const HUD_W := 480.0      # original HUD size
const SCALE := 2.0        # as PowerupFrame
const ATLAS2 := "res://assets/textures/fixed/54f786f3.png"
const SMEAR := Rect2(295, 39, 217, 62)      # 295,39-514,101, clipped to the atlas
const SMEAR_AT := Vector2(321, -5)          # hud_guns x 261 + 60, y -5
const GUNS_FRAME := Rect2(261, 0, 219, 62)  # hud_guns (touch area of gunIcon)
# gunImageFrame children: [atlas 0/1, x0, y0, x1, y1, offset from the right edge, y]
const GUNS := {
	"stg44": [0, 204, 474, 106, 511, 2, 2], "sawnoff": [0, 240, 451, 184, 470, 2, 7],
	"mp40": [0, 344, 477, 253, 513, 1, 3], "raygun": [0, 244, 407, 179, 447, 1, 1],
	"magnum": [0, 229, 372, 170, 406, 2, 2], "shotgun": [0, 249, 345, 130, 369, 3, 6],
	"carbine": [0, 254, 318, 130, 343, 3, 4], "kar98": [0, 254, 289, 130, 316, 3, 3],
	"thompson": [0, 104, 477, 2, 511, 2, 1], "browning": [0, 120, 375, 3, 405, 3, 1],
	"trenchgun": [0, 119, 285, 3, 309, 3, 4], "bar": [0, 381, 437, 257, 461, 4, 5],
	"colt45": [0, 170, 373, 120, 407, 5, 5], "g43": [0, 123, 312, 3, 338, 0, 0],
	"garand": [0, 122, 341, 4, 371, 0, 0], "ppsh": [0, 100, 436, 0, 466, 0, 0],
	"springfield": [0, 377, 296, 259, 320, 0, 0], "fg42": [0, 383, 350, 259, 379, 0, 0],
	"ptrs": [0, 381, 383, 259, 405, 0, 0], "mg42": [0, 383, 409, 260, 435, 0, 0],
	"type100": [1, 0, 0, 118, 35, 0, 0], "wunderwaffe": [1, 0, 34, 127, 79, 0, 0],
	"arisaka": [1, 0, 81, 123, 105, 0, 0],
}
# CItemGun +0x108 (analysis/weapon_stats.json u_108): 10493d97 "rifle", 92db6b0d "shotgun"
const AMMO_TYPE := {
	"kar98": "rifle", "ptrs": "rifle", "springfield": "rifle", "arisaka": "rifle",
	"shotgun": "shotgun", "trenchgun": "shotgun", "sawnoff": "shotgun", "wunderwaffe": "shotgun",
}
const AMMO_IMG := {   # <type>AmmoFull, <type>AmmoEmpty
	"shotgun": [Rect2(492, 138, 13, 7), Rect2(492, 129, 13, 7)],
	"rifle": [Rect2(489, 154, 16, 6), Rect2(489, 147, 16, 6)],
}
const CONTAINER := Rect2(330, 0, 150, 50)   # ammos_container
const CLIP_START := Vector2(413, 25)         # ammoRightBottom (-67 from the right, 25)
const CLIP_AVAIL := 83.0                     # ammos_container width left of the start
const VERT_BAR := Vector2(2, 10)             # ClipVertBarWidth / Height
const HORI_BAR := Vector2(5, 2)              # ClipHoriBarWidth / Height
const HORI_OFFSET := Vector2(2, 10)          # ClipHoriBarOffsetX / Y
const HALF_HEIGHT_ROWS := 4                  # ClipHoriBarNumRowUseHalfHeight
const BITMAP_OFFSET := Vector2(25, 2)        # ClipBitmapXOffset / YOffset
const BITMAP_WIDTH := 50.0                   # ClipBitmapWidth (code default)
const COUNT_AT := Vector2(440, 18)           # ammos_count (-40 from the right, 18)
const NO_AMMO_Y := 75.0                      # noAmmoLabel: 0x3c2 / 4096 of 320
const FLAME_AT := Vector2(389, 6)            # flamethrower_ammo: 0x0cf5, 0x51 / 4096
const FLAME_IMG := Rect2(267, 158, 81, 32)
const FUEL_IMG := Rect2(267, 190, 81, 32)
const LOW_CLIP := 35            # LowClipPercentage
const LOW_AMMO := 20            # LowAmmoPercentage
const AMMO_BLINK := 0.5         # AmmoBlinkTime
const NO_AMMO_GLOW := 1.0       # NoAmmoGlowPeriodMs (estimated, see above)
const C_PRESENT := Color8(0x80, 0x80, 0x80)
const C_CONSUMED := Color8(0x40, 0x40, 0x40)
const C_LOW := Color8(0xc8, 0, 0)
const C_TEXT := Color.WHITE

var player: Player
var _gun: TextureRect
var _clip: Control
var _shown_gun := ""
var _count: Label
var _no_ammo: Label
var _flame: TextureRect
var _fuel: TextureRect
var _t := 0.0
var _w := {}       # held weapon (copy of what was drawn)
var _mag_size := 0
var _atlas: Texture2D = load(UiArt.ATLAS)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(HUD_W, 320)
	scale = Vector2(SCALE, SCALE)
	var smear := TextureRect.new()
	smear.texture = UiArt.region(SMEAR)
	smear.position = SMEAR_AT
	smear.size = SMEAR.size
	smear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(smear)
	_gun = TextureRect.new()
	_gun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gun)
	# the clip is drawn above the gun picture (the Wunderwaffe's covers its shells)
	_clip = Control.new()
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.size = Vector2(HUD_W, 320)
	_clip.draw.connect(_draw_clip)
	add_child(_clip)
	_flame = _image(UiArt.region(FLAME_IMG), FLAME_AT)
	_fuel = _image(UiArt.region(FUEL_IMG), FLAME_AT)
	_fuel.stretch_mode = TextureRect.STRETCH_KEEP   # clipped from the right (CGuiClippedBitmap)
	_fuel.clip_contents = true
	_count = Label.new()
	_count.add_theme_font_override("font", UiArt.font())
	_count.add_theme_font_size_override("font_size", 22)
	_count.position = COUNT_AT
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	_no_ammo = Label.new()
	_no_ammo.text = "No Ammo"
	_no_ammo.add_theme_font_override("font", UiArt.font())
	_no_ammo.add_theme_font_size_override("font_size", 22)
	_no_ammo.add_theme_color_override("font_color", C_LOW)
	_no_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_no_ammo)


func _image(tex: Texture2D, at: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.position = at
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.size = tex.get_size()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


static func gun_texture(name: String) -> AtlasTexture:
	if not GUNS.has(name):
		return null
	var g: Array = GUNS[name]
	var a := AtlasTexture.new()
	a.atlas = load(UiArt.ATLAS if g[0] == 0 else ATLAS2)
	a.region = Rect2(mini(g[1], g[3]), g[2], absi(g[3] - g[1]), g[4] - g[2])
	return a


# clip display of a magazine size: "vertical" bars, "bitmap" (shotgun / rifle) or
# "horizontal" bars ("half" when they need more than 4 rows)
static func clip_mode(gun: String, mag_size: int) -> String:
	if mag_size * VERT_BAR.x * 2.0 < CLIP_AVAIL:
		return "bitmap" if AMMO_TYPE.has(gun) else "vertical"
	if int((HORI_BAR.x + HORI_OFFSET.x) * mag_size / CLIP_AVAIL) > HALF_HEIGHT_ROWS:
		return "half"
	return "horizontal"


static func clip_low(mag: int, mag_size: int) -> bool:
	return mag_size > 0 and (LOW_CLIP >= mag * 100 / mag_size or mag == 1)


func _process(delta: float) -> void:
	_t += delta
	var vw := get_viewport_rect().size.x
	position = Vector2(vw - HUD_W * SCALE, 0)
	_no_ammo.position = Vector2(-position.x / SCALE, NO_AMMO_Y)
	_no_ammo.size = Vector2(vw / SCALE, 30)
	if player == null or player.weapons.is_empty():
		return
	var w: Dictionary = player.weapon()
	var s := Weapons.stats_of(w)
	var name := String(w["name"])
	_mag_size = int(s["mag"])
	_w = w.duplicate()
	if name != _shown_gun:
		_shown_gun = name
		var tex := gun_texture(name)
		_gun.texture = tex
		_gun.visible = tex != null
		if tex:
			var g: Array = GUNS[name]
			_gun.flip_h = g[1] > g[3]
			_gun.size = tex.get_size()
			_gun.position = Vector2(HUD_W - g[5] - tex.get_size().x, g[6])
	var flame: bool = name == "flamethrower"
	_flame.visible = flame
	_fuel.visible = flame
	var mag := int(w["mag"])
	var reserve := int(w["reserve"])
	if flame:
		var fuel := clampf(float(mag) / maxf(_mag_size, 1), 0.0, 1.0)
		_fuel.size = Vector2(roundf(FUEL_IMG.size.x * fuel), FUEL_IMG.size.y)
	var empty := mag == 0 and reserve == 0
	_count.visible = not flame and not empty
	_no_ammo.visible = not flame and empty
	if _count.visible:
		_count.text = str(reserve)
		var full := int(s["reserve"])
		var low := full > 0 and LOW_AMMO >= reserve * 100 / full
		_count.add_theme_color_override("font_color", C_LOW if low else C_TEXT)
	if _no_ammo.visible:
		_no_ammo.modulate.a = 0.55 + 0.45 * cos(TAU * _t / NO_AMMO_GLOW)
	_clip.queue_redraw()


func _draw_clip() -> void:
	if _w.is_empty() or _shown_gun == "flamethrower":
		return
	var mag := int(_w["mag"])
	if mag == 0 and int(_w["reserve"]) == 0:
		return
	var present := C_PRESENT
	if clip_low(mag, _mag_size) and fmod(_t, AMMO_BLINK * 2.0) < AMMO_BLINK:
		present = C_LOW
	var mode := clip_mode(_shown_gun, _mag_size)
	var x := CLIP_START.x
	var y := CLIP_START.y
	if mode == "vertical":
		for i in _mag_size:
			_clip.draw_rect(Rect2(x - VERT_BAR.x, y, VERT_BAR.x, VERT_BAR.y), present if i < mag else C_CONSUMED)
			x -= VERT_BAR.x + HORI_OFFSET.x
	elif mode == "bitmap":
		var imgs: Array = AMMO_IMG[AMMO_TYPE[_shown_gun]]
		var tint := C_LOW if present == C_LOW else Color.WHITE
		x += BITMAP_OFFSET.x
		y += BITMAP_OFFSET.y
		for i in _mag_size:
			var r: Rect2 = imgs[0] if i < mag else imgs[1]
			if CLIP_START.x - x > BITMAP_WIDTH:
				x = CLIP_START.x + BITMAP_OFFSET.x
				y += r.size.y + BITMAP_OFFSET.y
			x -= r.size.x + HORI_OFFSET.x
			_clip.draw_texture_rect_region(_atlas, Rect2(Vector2(x, y), r.size), r, tint if i < mag else Color.WHITE)
	else:
		var bar := HORI_BAR
		if mode == "half":
			bar.y = floorf(bar.y / 2.0)
		x += HORI_OFFSET.x
		y += HORI_OFFSET.y
		for i in _mag_size:
			_clip.draw_rect(Rect2(x - bar.x, y, bar.x, bar.y), present if i < mag else C_CONSUMED)
			x -= bar.x + HORI_OFFSET.x
			if CLIP_START.x - x > CLIP_AVAIL:
				x = CLIP_START.x + HORI_OFFSET.x
				y += bar.y * 2.0


# gunIcon (CGuiTouchButtonIcon): as the original help text (4cd406ec) says, a tap on the
# ammo icon reloads, a double tap changes weapon (the switch drops the reload begun by the
# first tap). Mouse clicks do the same.
const DOUBLE_TAP := 0.3   # estimated
var _last_tap := -10.0


func _input(event: InputEvent) -> void:
	if player == null or get_tree().paused:
		return
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		# not the mouse clicks emulated from touches (handled above), not while the mouse looks
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if not pressed:
		return
	var local: Vector2 = (event.position - position) / SCALE
	if GUNS_FRAME.has_point(local):
		get_viewport().set_input_as_handled()
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_tap < DOUBLE_TAP:
			_last_tap = -10.0
			player.switch_weapon()
		else:
			_last_tap = now
			player.reload()
