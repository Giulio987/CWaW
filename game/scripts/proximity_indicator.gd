# CGuiFrameProximityIndicator ("ProximityIndicatorFrame" of the HUD, frame f71849b6):
# every frame (kiwi 0x180484) the HUD queries the enemies around the player and, for
# each one close enough, shows one of the curved arrows of the HUD atlas around the
# centre of the screen pointing at it, so a zombie at the player's back or side is
# noticed. The frame data has the radii 2000 / 1400 / 1200 / 600 units (5 / 3.5 / 3 /
# 1.5 m); the code picks the radius by enemy kind (flags 0x4000 / 0x40000000). Here:
# zombies and dogs within 5 m outside the view cone get an arrow, the larger the
# closer (exact per-kind radii and fades not decoded).
class_name ProximityIndicator
extends Control

const ARROWS := [Rect2(477, 426, 33, 51), Rect2(488, 483, 22, 63), Rect2(494, 554, 15, 46)]   # big .. small
const RANGE := 2000.0 / 400.0    # 5 m
const NEAR := 600.0 / 400.0      # 1.5 m
const MID := 1200.0 / 400.0      # 3 m
const VIEW_HALF := deg_to_rad(40.0)   # in sight: no arrow
const SCALE := 1.6

var game: Node   # Game
var _marks := []   # [angle, arrow index, alpha]
var _tex: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex = load(UiArt.ATLAS)


func _process(_d: float) -> void:
	_marks.clear()
	var p = game.get("player") if game else null
	if p == null or p.dead:
		queue_redraw()
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	for n in game.get_children():
		if not n is Zombie or (n as Zombie).state == Zombie.State.DEAD:
			continue
		var to: Vector3 = (n as Node3D).global_position - p.global_position
		var d := Vector2(to.x, to.z).length()
		if d > RANGE or absf(to.y) > 2.5:
			continue
		# angle of the enemy from the view direction, clockwise (right = +)
		var a := wrapf(yaw - atan2(-to.x, -to.z), -PI, PI)
		if absf(a) < VIEW_HALF:
			continue
		var idx := 0 if d < NEAR else (1 if d < MID else 2)
		_marks.append([a, idx, clampf(1.2 - d / RANGE, 0.35, 1.0)])
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.32
	for m in _marks:
		var a: float = m[0]
		var rect: Rect2 = ARROWS[m[1]]
		var s: Vector2 = rect.size * SCALE
		draw_set_transform(c + Vector2(sin(a), -cos(a)) * r, a, Vector2.ONE)
		draw_texture_rect_region(_tex, Rect2(-s / 2.0, s), rect, Color(1, 1, 1, m[2]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
