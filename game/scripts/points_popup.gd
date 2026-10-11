# World at War points popup: "+10" floats away from the points counter
# (yellow) when points are earned, "-950" drops in red when spent.
class_name PointsPopup
extends Label

var _vel := Vector2.ZERO
var _life := 0.0
var _total := 1.0


static func spawn(parent: Node, amount: int, anchor: Vector2) -> PointsPopup:
	var p := PointsPopup.new()
	p.text = ("+%d" if amount > 0 else "-%d") % absi(amount)
	p.add_theme_font_override("font", UiArt.font())
	p.add_theme_font_size_override("font_size", 40 if amount > 0 else 42)
	p.add_theme_color_override("font_color", UiArt.POINTS if amount > 0 else UiArt.SPENT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if amount > 0:
		# like WaW: to the left of the counter, random height, drifting away
		p.position = anchor + Vector2(-80 - randf() * 30, randf_range(-45, 25))
		p._vel = Vector2(-randf_range(60, 110), randf_range(-50, 50))
		p._total = 1.0
	else:
		p.position = anchor + Vector2(-110, 4)
		p._vel = Vector2(-10, 22)
		p._total = 1.6
	parent.add_child(p)
	return p


func _process(delta: float) -> void:
	_life += delta
	position += _vel * delta
	modulate.a = clampf(1.5 * (1.0 - _life / _total), 0.0, 1.0)
	if _life >= _total:
		queue_free()
