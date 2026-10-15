# Hip-fire reticle: CGuiFrameAimingReticle "AimingReticleFrame" (ui.group.bin 9ff422c1).
# A square frame centred on the aim point with four 8x8 pieces of the HUD atlas bar
# (383,457-391,465: a 3 px wide line), at the middle of its top and bottom edges and
# turned a quarter for the left and right ones (their image rects are reversed).
# The HUD sets it every frame (kiwi va 0x129604..0x129664 -> 0x1ca9d8): the frame side
# is the gun's current spread, never less than its cone (CItemGun +0x60, shotguns), in
# angle units (4096 = 360 degrees) taken as pixels of the 480x320 HUD, times
# ReticleScaleModifier (console.bin 1.0; ReticleScaleModifierIPad 2.0). The spread
# here is Weapons.spread() with the player's heat, which already widens and settles
# smoothly; ReticleResizeSpeed (console.bin 1.0) is not read by the 1.5.0 code (the name
# is not in the binary). Colours of the frame: ff0000 / ffffff at alpha c8, the red one
# when byte +0x21 of the player's targeting component is set: each frame (kiwi va
# 0x212674..0x212778) it picks the target enemy (+0x20) and sets +0x21 when the aim ray
# hits that enemy's collision model (va 0x228868). Here: the centre ray hits a live zombie.
# The aim states switch it off (gun state machine output "reticle"): hidden while aiming.
class_name AimingReticle
extends Control

const SCALE := 2.0                   # HUD pixels -> screen (as PowerupFrame / WeaponHud)
const SCALE_MODIFIER := 1.0          # ReticleScaleModifier
const PIECE := Rect2(383, 457, 8, 8)
const C_NORMAL := Color8(0xff, 0xff, 0xff, 0xc8)
const C_TARGET := Color8(0xff, 0x00, 0x00, 0xc8)

var player: Player
var side := 0.0                      # frame side in HUD pixels (tests)
var on_target := false
var _tex: AtlasTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex = UiArt.region(PIECE)


static func spread_units(w: Dictionary, aimed: bool, heat: float) -> float:
	var s := Weapons.stats_of(w)
	var deg := maxf(Weapons.spread(w, aimed, heat), float(s.get("cone", 0.0)))
	return deg * 4096.0 / 360.0


func _process(_delta: float) -> void:
	if player == null or player.weapons.is_empty():
		visible = false
		return
	visible = not player.aiming and not player.dead
	if not visible:
		return
	side = spread_units(player.weapon(), false, float(player.get("_heat"))) * SCALE_MODIFIER
	on_target = _zombie_ahead()
	queue_redraw()


func _zombie_ahead() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return false
	var from := cam.global_position
	var to := from - cam.global_basis.z * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	var ex: Array[RID] = [player.get_rid()]
	q.exclude = ex
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var z := hit["collider"] as Zombie
	return z != null and z.state != Zombie.State.DEAD


func _draw() -> void:
	var c := get_viewport_rect().size / 2.0
	var half := side * SCALE / 2.0
	var p := PIECE.size.x * SCALE
	var col := C_TARGET if on_target else C_NORMAL
	# top / bottom: the piece as it is, centred on the edge, inside the frame
	draw_texture_rect(_tex, Rect2(c + Vector2(-p / 2.0, -half), Vector2(p, p)), false, col)
	draw_texture_rect(_tex, Rect2(c + Vector2(-p / 2.0, half - p), Vector2(p, p)), false, col)
	# left / right: turned a quarter
	for x in [-half + p / 2.0, half - p / 2.0]:
		draw_set_transform(c + Vector2(x, 0), PI / 2.0, Vector2.ONE)
		draw_texture_rect(_tex, Rect2(-p / 2.0, -p / 2.0, p, p), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
