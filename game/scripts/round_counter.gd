# Round number like World at War: chalk tally marks for rounds 1-5 (original
# HUD atlas strokes), digits from round 6 on. On a round change the old number
# flashes white, fades out, and the new one fades in white and settles to red.
class_name RoundCounter
extends Control

const SCALE := 2.0          # the tally images at 1:1 in the 480x320 HUD, x2 (as Hud.UI_SCALE)
const DIGIT_SIZE := 110
const FLASHES := 3

var value := 0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate = Color(UiArt.RED, 0.0)


func set_round(n: int, animate := true) -> void:
	if _tween:
		_tween.kill()
	if not animate:
		value = n
		modulate = UiArt.RED
		queue_redraw()
		return
	_tween = create_tween()
	if value > 0 and modulate.a > 0.01:
		for i in FLASHES:
			_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.22)
			_tween.tween_property(self, "modulate", UiArt.RED, 0.22)
		_tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.6)
	_tween.tween_callback(func():
		value = n
		queue_redraw())
	_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.7).from(Color(1, 1, 1, 0))
	_tween.tween_property(self, "modulate", UiArt.RED, 1.2)


func _draw() -> void:
	if value <= 0:
		return
	if value <= 5:
		var origin: float = UiArt.TALLY_STROKES[0].position.x
		if value == 5:
			var r: Rect2 = UiArt.TALLY_FIVE
			draw_texture_rect(UiArt.region(r), Rect2(Vector2(0, (r.position.y - 151) * SCALE), r.size * SCALE), false)
		else:
			for i in value:
				var r: Rect2 = UiArt.TALLY_STROKES[i]
				var pos := Vector2((r.position.x - origin) * SCALE, (r.position.y - 151) * SCALE)
				draw_texture_rect(UiArt.region(r), Rect2(pos, r.size * SCALE), false)
	else:
		var f := UiArt.font()
		draw_string(f, Vector2(0, -6), str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, DIGIT_SIZE)
