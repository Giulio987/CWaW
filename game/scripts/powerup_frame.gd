# CGuiFramePowerup (ui.group.bin, frame at 208,0 160x60 of the 480x320 HUD): one
# 34x34 icon from the HUD atlas per running power-up with its seconds left below
# ("doublePoints"/"doublePointsTime", "instaKill"/"instaKillTime"; kiwi 0x10ee54 shows
# timer / 1000). An icon fades in and out over PowerupFadeIn/OutDurationMs (code
# default 500 ms, kiwi 0x10ebb0) and glows during the last PowerupGlowDurationMs
# (console.bin 5000) with period PowerupGlowPeriodMs (750) (kiwi 0x10ed2c). The frame
# also has "headShot" with "headShotCount" ("x%d", kiwi va 0x174ec8..0x174f60: shown while
# the local player's headshot streak is above 0; Player.headshot_streak) and "repair"
# (no label; shown while the global flag +0x20 is set, which the barricade sets while the
# local player holds interact at it and it can be repaired, kiwi va 0xfc29c..0xfc3d8 /
# 0xfc408). Those two fade like the others but do not glow. Slots at x 0, 34, 68, 102
# of the frame, in this order.
# Above them, the pickup message ("Max. Ammo!"...) for PickupMessageTimeMs (4000).
class_name PowerupFrame
extends Control

const ICONS := {   # atlas rects from the frame's CIwGuiImage entries
	"doublepoints": Rect2(338, 2, 34, 34),
	"instakill": Rect2(371, 2, 34, 34),
	"headshot": Rect2(437, 2, 34, 34),
	"repair": Rect2(404, 2, 34, 34),
}
const FRAME_X := 208.0 - 240.0   # frame x relative to the middle of the 480 HUD
const SCALE := 2.0
const FADE_IN := 0.5
const FADE_OUT := 0.5
const GLOW_TIME := 5.0
const GLOW_PERIOD := 0.75
const MESSAGE_TIME := 4.0

var game: Node   # Game
var _slots := {}   # kind -> {"icon": TextureRect, "time": Label, "a": float}
var _msg: Label
var _msg_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	var size := 34.0 * SCALE
	var i := 0
	for k in ICONS:
		var icon := TextureRect.new()
		icon.texture = UiArt.region(ICONS[k])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.size = Vector2(size, size)
		icon.position = Vector2((FRAME_X + 34.0 * i) * SCALE, 0)   # frame and icons at y 0
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate.a = 0.0
		add_child(icon)
		var t := Label.new()
		t.add_theme_font_override("font", UiArt.font())
		t.add_theme_font_size_override("font_size", 26)
		t.add_theme_color_override("font_color", Color.WHITE)
		t.add_theme_color_override("font_outline_color", Color.BLACK)
		t.add_theme_constant_override("outline_size", 4)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.size = Vector2(size, 30)
		t.position = icon.position + Vector2(0, size)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.modulate.a = 0.0
		add_child(t)
		_slots[k] = {"icon": icon, "time": t, "a": 0.0}
		i += 1
	_msg = Label.new()
	_msg.add_theme_font_override("font", UiArt.font())
	_msg.add_theme_font_size_override("font_size", 40)
	_msg.add_theme_color_override("font_color", Color(1.0, 0.93, 0.55))
	_msg.add_theme_color_override("font_outline_color", Color.BLACK)
	_msg.add_theme_constant_override("outline_size", 6)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.size = Vector2(600, 50)
	_msg.position = Vector2(-300, 10 + size + 40)
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_msg)


func message(text: String) -> void:
	_msg.text = text
	_msg_t = MESSAGE_TIME


func _process(delta: float) -> void:
	_msg_t -= delta
	_msg.modulate.a = clampf(_msg_t / 0.5, 0.0, 1.0)   # fades in the last half second
	var timers: Dictionary = game.get("_timers") if game else {}
	var player: Node = game.get("player") if game else null
	for k in _slots:
		var s: Dictionary = _slots[k]
		var left: float = timers.get(k, 0.0)
		var on := left > 0.0
		if k == "headshot":
			var streak := int(player.get("headshot_streak")) if player and player.get("headshot_streak") != null else 0
			on = streak > 0
			left = INF
			if on:
				(s["time"] as Label).text = "x%d" % streak
		elif k == "repair":
			on = repairing(player)
			left = INF
			(s["time"] as Label).text = ""
		s["a"] = clampf(s["a"] + (delta / FADE_IN if on else -delta / FADE_OUT), 0.0, 1.0)
		var glow := 1.0
		if on and left <= GLOW_TIME:
			glow = 0.35 + 0.65 * (0.5 + 0.5 * cos(TAU * (GLOW_TIME - left) / GLOW_PERIOD))
		(s["icon"] as TextureRect).modulate.a = s["a"] * glow
		var t: Label = s["time"]
		t.modulate.a = s["a"]
		if on and left < INF:
			t.text = str(int(left))


# "repair": the local player holds interact at a barricade that can take boards
# (the remake's barricade prompt is only offered then, player.gd _update_prompt).
static func repairing(player: Node) -> bool:
	return player != null and bool(player.get("prompt_repair")) \
		and Input.is_action_pressed("interact")
