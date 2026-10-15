# Touch controls of the original HUD (ingame/ui/ui.group.bin): the "Touch Screen"
# scheme of the iPhone (CGuiFrameTouchHUDDualStickA "DualstickControlsAFrame",
# 011259bd; help text 4cd406ec: move with the stick on the left, aim by pressing the
# screen and dragging, shoot button, target button next to it, tap the ammo icon to
# reload / double tap to change weapon, tap the grenade icon to throw / double tap to
# change type, pause on the score icon). Layout in units of the 480x320 HUD drawn at
# U screen pixels per unit; each rect is decoded from the frame's layout record
# (align byte: low nibble x, high nibble y, 0 = left/top, 1 = centre, 2 = right/bottom;
# values: 01 pixels, 02 parent size + value, 08 fraction /4096 of the parent), always
# against this control's own size, i.e. the visible area of the HUD layer:
#  - AnalogueMovePad: frame 0,100 % 140x140 (left, bottom), CGuiTouchAnaloguePad 105x105
#    centred: ring (atlas 1,54 105x105) and knob (2,1 52x52)
#  - FloatArea: x 180, width parent - 180, full height: CGuiTouchFloat with an invisible
#    AnalogueAimPad (aim drag); an aim drag cannot start on another button except fire,
#    but keeps going over them (help text)
#  - FireIcon: right/bottom at parent - 63, parent - 103, 70x70: atlas 391,431 82x82
#    stretched, input fire (held)
#  - ToggleAimIcon: right/bottom at 100 %, parent - 95, 65x85; image 158,1 45x45 at
#    x 15 from the left, its bottom 22 above the frame's bottom; input toggleAim
#  - MeleeIcon: centre/bottom at 50 %, 100 %, 163x50: bar 349,161 163x28 at the bottom,
#    knife 87,412 66x20 centred, bottom 3 above; input melee
#  - InteractIcon: centre/bottom at 50 %, parent - 55, 200x130; the button 83x83 at its
#    bottom centre, hand 419,840 83x83, input interact; shown only when there is something
#    to use (its last flag 01; here: the player has a prompt). Its CGuiLabelInteractMessage
#    is the prompt at the top of the screen (hud.gd)
#  - special CGuiTouchButton: right/top at parent - 2, 58, 60x60; specialBitmap (one image
#    per item: grenade 139,433, betty 204,472, molotov 100,433, monkey 54f786f3 60,154, all
#    39x40) right-aligned at 40, centred; "+" (specialCycleIndicator, alpha 0x96) at the top
#    left when more than one type is carried; curSpecialCount bottom right. Inputs +grenade /
#    -grenade on press / release, cycleSpecial on double tap
#  - pause: ingame_hud CGuiTouchButtonMenuItem at 0,0, 0x147/4096 of the width x 42, its
#    26x26 icon (349,131) centred; the help text calls it "the score icon": the whole
#    points_container 120x50 is accepted
# Pressed tint 5f6982 (the colour after the button's ffffffff in each CGuiTouchButtonIcon
# record; read as the pressed colour, not verified in the code).
# Remake extras (the original iPhone game has no run nor jump; toggleRun exists only in
# the PC key map PlayerControlsWin): RUN (toggle, as the original input toggleRun: on until
# tapped again, the stick is let go or the player aims) above the stick, JUMP under the
# aim button; drawn with the HUD atlas' own triangles (60,5 and 108,3) on the stick ring.
# Each touch is tracked by its index, so stick, aim and buttons work together.
class_name TouchControls
extends Control

const U := 2.0                      # HUD unit -> pixels (as Hud.UI_SCALE / WeaponHud.SCALE)
const ATLAS2 := "res://assets/textures/fixed/54f786f3.png"
const PRESSED := Color8(0x5f, 0x69, 0x82)
const KNOB := Rect2(2, 1, 52, 52)
const RING := Rect2(1, 54, 105, 105)
const FIRE_IMG := Rect2(391, 431, 82, 82)
const AIM_IMG := Rect2(158, 1, 45, 45)
const MELEE_BAR := Rect2(349, 161, 163, 28)
const KNIFE_IMG := Rect2(87, 412, 66, 20)
const INTERACT_IMG := Rect2(419, 840, 83, 83)
const PAUSE_IMG := Rect2(349, 131, 26, 26)
const JUMP_IMG := Rect2(60, 5, 44, 41)      # up triangle of the HUD atlas
const RUN_IMG := Rect2(108, 3, 40, 43)      # right triangle, drawn twice (fast forward)
const SPECIALS := {   # [atlas 0/1, image]
	"grenade": [0, Rect2(139, 433, 39, 40)], "betty": [0, Rect2(204, 472, 39, 40)],
	"molotov": [0, Rect2(100, 433, 39, 40)], "monkey": [1, Rect2(60, 154, 39, 40)],
}
const SPECIAL_ORDER := ["grenade", "betty", "molotov", "monkey"]   # cycleSpecial order
const FLOAT_X := 180.0              # FloatArea x
const PAD := 105.0                  # CGuiTouchAnaloguePad size
const STICK_ZONE := 140.0           # AnalogueMovePad frame
const DOUBLE_TAP := 0.3             # estimated
const LOOK_SPEED := 0.005           # as before (Settings.touch_sens scales it)

var game: Game
var _atlas: Texture2D = load(UiArt.ATLAS)
var _atlas2: Texture2D = load(ATLAS2)
var _font: Font = UiArt.font()
var _held := {}             # touch index -> button name ("stick", "look", "fire", ...)
var _stick_centre := Vector2.ZERO   # local px
var _stick_floating := false
var _knob := Vector2.ZERO           # knob offset in px
var _run_on := false
var _last_special_up := -10.0
var _betty_selected := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ------------------------------------------------------------------ layout (local px)

func _unit_size() -> Vector2:
	return size / U


# rect of a layout record: align byte, x, y (already resolved to units), w, h
func _r(align: int, x: float, y: float, w: float, h: float) -> Rect2:
	var ax := align & 0xf
	var ay := align >> 4
	x -= w * (0.5 if ax == 1 else (1.0 if ax == 2 else 0.0))
	y -= h * (0.5 if ay == 1 else (1.0 if ay == 2 else 0.0))
	return Rect2(Vector2(x, y) * U, Vector2(w, h) * U)


func rects() -> Dictionary:
	var s := _unit_size()
	var W := s.x
	var H := s.y
	var r := {}
	r["stick_zone"] = _r(0x20, 0, H, STICK_ZONE, STICK_ZONE)
	r["fire"] = _r(0x22, W - 63, H - 103, 70, 70)
	var aim := _r(0x22, W, H - 95, 65, 85)
	r["aim"] = aim
	r["aim_img"] = Rect2(aim.position + Vector2(15, 85 - 22 - 45) * U, Vector2(45, 45) * U)
	var melee := _r(0x21, W / 2.0, H, 163, 50)
	r["melee"] = melee
	r["melee_bar"] = Rect2(melee.position + Vector2(0, 22) * U, Vector2(163, 28) * U)
	r["knife"] = Rect2(melee.position + Vector2(48.5, 27) * U, Vector2(66, 20) * U)
	var inter := _r(0x21, W / 2.0, H - 55, 200, 130)
	r["interact"] = Rect2(inter.position + Vector2(58.5, 47) * U, Vector2(83, 83) * U)
	var sp := _r(0x02, W - 2, 58, 60, 60)
	r["special"] = sp
	r["special_img"] = Rect2(sp.position + Vector2(1, 10) * U, Vector2(39, 40) * U)
	r["pause"] = Rect2(0, 0, 120 * U, 50 * U)                    # points_container
	# 0x147/4096 of the 480 HUD (38 units), left of points_count at 36
	r["pause_img"] = Rect2(Vector2(480.0 * 0x147 / 4096.0 / 2.0 - 13, 21 - 13) * U, Vector2(26, 26) * U)
	r["guns"] = _r(0x02, W, 0, 219, 62)                          # hud_guns (weapon_hud.gd)
	# remake extras, clear of the original buttons
	r["run"] = _r(0x20, 10, H - STICK_ZONE - 6, 60, 60)          # above the stick
	r["jump"] = _r(0x22, W - 6, H - 4, 64, 64)                   # under the aim button
	return r


func _pad_centre() -> Vector2:
	return Vector2(STICK_ZONE / 2.0, _unit_size().y - STICK_ZONE / 2.0) * U


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if game == null or game.player == null:
		return
	if get_tree().paused or not is_visible_in_tree():
		if not _held.is_empty():
			release_all()
		return
	if event is InputEventScreenTouch:
		var pos := _local(event.position)
		if event.pressed:
			if _press(event.index, pos):
				get_viewport().set_input_as_handled()
		elif _held.has(event.index):
			_release(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _held.has(event.index):
		var what: String = _held[event.index]
		if what == "stick":
			_move_stick(_local(event.position))
		elif what == "look" or what == "fire":
			game.player.look(event.relative * LOOK_SPEED * Settings.touch_sens())
		get_viewport().set_input_as_handled()


func _local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _press(index: int, pos: Vector2) -> bool:
	var r := rects()
	var p := game.player
	var hit := ""
	for k in ["pause", "special", "interact", "fire", "aim", "jump", "run", "melee"]:
		if k == "interact" and p.prompt == "":
			continue
		if k == "special" and _special_kinds().is_empty():
			continue
		if (r[k] as Rect2).has_point(pos):
			hit = k
			break
	if hit == "" and (r["guns"] as Rect2).has_point(pos):
		return false   # the weapon icon (weapon_hud.gd)
	if hit == "":
		if pos.x < FLOAT_X * U:
			if _held.values().has("stick"):
				return true
			hit = "stick"
		elif not _held.values().has("look"):
			hit = "look"
		else:
			return true
	_held[index] = hit
	match hit:
		"stick":
			var c := _pad_centre()
			_stick_floating = pos.distance_to(c) > PAD / 2.0 * U
			_stick_centre = pos if _stick_floating else c
			_move_stick(pos)
		"fire":
			p.fire_held = true
		"aim":
			p.toggle_aim()
		"melee":
			p.melee()
		"interact":
			Input.action_press("interact")
		"jump":
			Input.action_press("jump")
		"run":
			_set_run(not _run_on)
		"special":
			_special_down()
		"pause":
			_held.erase(index)
			game.hud.open_pause()
	queue_redraw()
	return true


func _release(index: int) -> void:
	var what: String = _held[index]
	_held.erase(index)
	match what:
		"stick":
			_knob = Vector2.ZERO
			game.player.move_input = Vector2.ZERO
		"fire":
			game.player.fire_held = false
		"interact":
			Input.action_release("interact")
		"jump":
			Input.action_release("jump")
		"special":
			_special_up()
	queue_redraw()


func release_all() -> void:
	for i in _held.keys():
		_release(i)
	_set_run(false)


func _move_stick(pos: Vector2) -> void:
	var radius := PAD / 2.0 * U
	_knob = (pos - _stick_centre).limit_length(radius)
	game.player.move_input = _knob / radius
	queue_redraw()


func _set_run(on: bool) -> void:
	if on == _run_on:
		return
	_run_on = on
	if on:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	queue_redraw()


func held(what: String) -> bool:
	return _held.values().has(what)


func running() -> bool:
	return _run_on


# ------------------------------------------------------------------ special items

# carried special items, in the cycleSpecial order (monkeys take the grenade slot here)
func _special_kinds() -> Array:
	var p := game.player
	var out := []
	var gb := GrenadeBelt.of(p)
	var mk := MonkeyBelt.of(p)
	var bb := BettyBelt.of(p)
	var mb := MolotovBelt.of(p)
	if mk and mk.active():
		out.append("monkey")
	elif gb and gb.count > 0:
		out.append("grenade")
	if bb and (bb.count > 0 or bb.planting):
		out.append("betty")
	if mb and (mb.count > 0 or mb.holding):
		out.append("molotov")
	out.sort_custom(func(a, b): return SPECIAL_ORDER.find(a) < SPECIAL_ORDER.find(b))
	return out


func special_selected() -> String:
	var kinds := _special_kinds()
	var mb := MolotovBelt.of(game.player)
	if mb and mb.selected and kinds.has("molotov"):
		return "molotov"
	if _betty_selected and kinds.has("betty"):
		return "betty"
	for k in kinds:
		if k != "betty" and k != "molotov":
			return k
	return kinds[0] if not kinds.is_empty() else ""


func _special_count(kind: String) -> int:
	var p := game.player
	match kind:
		"grenade":
			return GrenadeBelt.of(p).count
		"monkey":
			return MonkeyBelt.of(p).count
		"betty":
			return BettyBelt.of(p).count
		"molotov":
			return MolotovBelt.of(p).count
	return 0


func _special_down() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_special_up < DOUBLE_TAP:
		_last_special_up = -10.0
		cycle_special()
		_held[_held.find_key("special")] = "special_cycle"   # its release does nothing
		return
	var kind := special_selected()
	if kind == "betty":
		BettyBelt.of(game.player).start_plant()
	elif kind != "":
		var gb := GrenadeBelt.of(game.player)
		if gb:
			gb.set_held(true)   # forwards to the molotovs / monkeys when selected


func _special_up() -> void:
	_last_special_up = Time.get_ticks_msec() / 1000.0
	var gb := GrenadeBelt.of(game.player)
	if gb:
		gb.set_held(false)


# cycleSpecial: the next carried type
func cycle_special() -> void:
	var kinds := _special_kinds()
	if kinds.size() < 2:
		return
	var cur := special_selected()
	var next: String = kinds[(kinds.find(cur) + 1) % kinds.size()]
	var mb := MolotovBelt.of(game.player)
	if mb and mb.selected != (next == "molotov"):
		mb.cycle()
	_betty_selected = next == "betty"
	queue_redraw()


# ------------------------------------------------------------------ drawing

func _process(_d: float) -> void:
	if game == null or game.player == null:
		return
	var p := game.player
	if _run_on and (not held("stick") or p.aiming or p.dead):
		_set_run(false)
	# the special button shows the counts: no extra rows of item icons (the belts' own)
	for b in [GrenadeBelt.of(p), BettyBelt.of(p), MolotovBelt.of(p), MonkeyBelt.of(p)]:
		if b:
			var row = b.get("_icons") if b.get("_icons") != null else b.get("_label")
			if row is CanvasItem:
				(row as CanvasItem).visible = false
	if held("interact") and p.prompt == "":
		for i in _held.keys():
			if _held[i] == "interact":
				_release(i)
	queue_redraw()


func _img(r: Rect2, src: Rect2, pressed := false, alpha := 1.0, tex: Texture2D = null) -> void:
	var c := PRESSED if pressed else Color.WHITE
	c.a = alpha
	draw_texture_rect_region(tex if tex else _atlas, r, src, c)


func _draw() -> void:
	if game == null or game.player == null:
		return
	var p := game.player
	var r := rects()
	# stick: ring + knob (the ring follows a floating start)
	var c := _stick_centre if held("stick") else _pad_centre()
	var ring := PAD * U
	_img(Rect2(c - Vector2(ring, ring) / 2.0, Vector2(ring, ring)), RING)
	var k := 52.0 * U
	_img(Rect2(c + _knob - Vector2(k, k) / 2.0, Vector2(k, k)), KNOB, held("stick"))
	_img(r["fire"], FIRE_IMG, held("fire"))
	_img(r["aim_img"], AIM_IMG, held("aim") or p.aim_wanted)
	_img(r["melee_bar"], MELEE_BAR, held("melee"))
	_img(r["knife"], KNIFE_IMG, held("melee"))
	if p.prompt != "":
		_img(r["interact"], INTERACT_IMG, held("interact"))
	_img(r["pause_img"], PAUSE_IMG, false, 0.9)
	# special item
	var kinds := _special_kinds()
	var kind := special_selected()
	var sp: Rect2 = r["special"]
	if kind != "":
		var s: Array = SPECIALS[kind]
		_img(r["special_img"], s[1], held("special"), 1.0, _atlas2 if s[0] == 1 else null)
		var fs := int(16 * U)
		draw_string(_font, sp.position + Vector2(36, 54) * U, str(_special_count(kind)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		if kinds.size() > 1:
			draw_string(_font, sp.position + Vector2(0, 16) * U, "+", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0x96 / 255.0))
	# remake extras: jump and run on the stick ring
	for b in ["jump", "run"]:
		var br: Rect2 = r[b]
		var on: bool = held(b) or (b == "run" and _run_on)
		_img(br, RING, false, 1.0)
		var ic := br.grow(-br.size.x * 0.24)
		if b == "jump":
			_img(ic, JUMP_IMG, on)
		else:
			var half := Rect2(ic.position, Vector2(ic.size.x * 0.55, ic.size.y))
			_img(half, RUN_IMG, on)
			_img(Rect2(half.position + Vector2(ic.size.x * 0.45, 0), half.size), RUN_IMG, on)
