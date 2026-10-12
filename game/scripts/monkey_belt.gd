# Monkey Bombs carried by the player (Der Riese mystery box): they take the grenade
# slot, so while the player has any, G (or the touch grenade button) throws a monkey
# instead of a frag (GrenadeBelt forwards to us). The box gives 3 (ScriptMaxMonkeys).
class_name MonkeyBelt
extends Node

const MAX := 3
const THROW_SPEED := 11.0
const THROW_UP := 3.0
const COOLDOWN := 0.8
const HOLD_POS := Vector3(0.26, -0.33, -0.62)

var player: Player
var count := 0
var holding := false
var _cooldown := 0.0
var _in_hand: Node3D
var _label: Label


static func of(p: Node) -> MonkeyBelt:
	return p.get_node_or_null("MonkeyBelt") as MonkeyBelt if p else null


# The mystery box hands over the monkeys.
static func give(p: Player) -> MonkeyBelt:
	var b := of(p)
	if b == null:
		b = MonkeyBelt.new()
		b.player = p
		p.add_child(b)
	b.count = MAX
	b._refresh()
	Sfx.instance.play(Sfx.iw_hash("player1_weapon_monkey"))
	return b


# true while the grenade key belongs to the monkeys
func active() -> bool:
	return count > 0 or holding


func _ready() -> void:
	name = "MonkeyBelt"
	if player == null:
		player = get_parent() as Player
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.position += Vector2(-330, -48)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)
	_refresh()


# One press plays the whole Throwingmonkeybomb state (viewmodel.gd): the arms bring the
# monkey up, wind it and throw it at MONKEY_RELEASE; releasing the button changes nothing.
func set_held(down: bool) -> void:
	if not down or holding:
		return
	if count <= 0 or _cooldown > 0.0 or player.dead:
		return
	var vm := player.get("_viewmodel") as Viewmodel
	if vm and vm.drinking:
		return
	holding = true
	count -= 1
	_refresh()
	if vm:
		vm.hold_item(MonkeyBomb.model(), Viewmodel.MONKEY_ARMS, Viewmodel.MONKEY_ANIM)
		var t := vm.throw_item("", Viewmodel.MONKEY_RELEASE)
		player.set("_cooldown", maxf(float(player.get("_cooldown")), t + 0.3))
		get_tree().create_timer(Viewmodel.MONKEY_RELEASE, false).timeout.connect(_throw)
		return
	_in_hand = MonkeyBomb.model()
	player.get_viewport().get_camera_3d().add_child(_in_hand)
	_in_hand.rotation = Vector3(0.2, 0.5, 0)
	_in_hand.scale = Vector3.ONE * 0.75
	_in_hand.position = HOLD_POS
	get_tree().create_timer(0.4, false).timeout.connect(_throw)


func _throw() -> void:
	if not holding:
		return
	holding = false
	_cooldown = COOLDOWN
	if _in_hand:
		_in_hand.queue_free()
		_in_hand = null
	_refresh()
	if player.dead or player.game == null:
		return
	var cam := player.get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	var from := cam.global_position + fwd * 0.45 + cam.global_basis.x * 0.12
	var vm := player.get("_viewmodel") as Viewmodel
	var hand: Variant = vm.item_position() if vm else null
	if hand != null and (hand as Vector3).distance_to(cam.global_position) < 1.2:
		from = hand   # from the hand of the throw animation
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, from, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		from = (hit["position"] as Vector3) - fwd * 0.1
	var vel := fwd * THROW_SPEED + Vector3.UP * THROW_UP + Vector3(player.velocity.x, 0.0, player.velocity.z)
	var b := MonkeyBomb.spawn(player.game, from, vel, player)
	b.rotation.y = player.rotation.y
	Sfx.instance.play("knife_slash", -10.0, 0.7)   # whoosh


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if holding and player.dead:
		holding = false
		var vm := player.get("_viewmodel") as Viewmodel
		if vm:
			vm.end_item()
		if _in_hand:
			_in_hand.queue_free()
			_in_hand = null


# HUD: replaces the frag icons while monkeys are in the slot
func _refresh() -> void:
	if _label == null:
		return
	_label.text = "Monkey Bomb ×%d" % count if count > 0 else ""
	var gb := GrenadeBelt.of(player)
	if gb and gb.get("_icons"):
		(gb.get("_icons") as Control).visible = not active()
