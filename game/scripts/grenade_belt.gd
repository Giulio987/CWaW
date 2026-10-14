# The player's frag grenades: count, cooking/throwing (key G or the touch 💣
# button), round refill and the HUD icons.
# waves.lua: every wave gives the player two grenades up to four
# (GetPlayerGrenades() + 2, max 4), so a game starts with 2; a wall buy
# (CActionBuyGrenadeSpec) fills up to four. Holding the button cooks the
# grenade (WaW): the fuse is already burning and it blows up in hand at zero.
class_name GrenadeBelt
extends Node

const MAX := 4
const PER_ROUND := 2
const THROW_SPEED := 13.0
const THROW_UP := 3.0
const COOLDOWN := 0.8
const HOLD_POS := Vector3(0.24, -0.3, -0.5)
# frag icon in the in-game UI atlas: the stick grenade. The touch "special" button
# (CIwGuiMultiBitmap specialBitmap, ui group) has one image per item in CItem order
# grenade / betty / molotov: (139,433)-(178,473), (204,472)-(243,512), (100,433)-(139,473);
# the canister with the prongs at (204,472) is the Bouncing Betty (betty_belt.gd).
const ICON_ATLAS := "res://assets/textures/ingame/ui/2f66d01c.png"
const ICON_RECT := Rect2(139, 433, 39, 40)

var player: Player
var count := 0
var cooking := false
var cook_time := 0.0
var _held := false
var _cooldown := 0.0
var _round_seen := 0
var _in_hand: Node3D
var _icons: HBoxContainer
var _icon_tex: AtlasTexture


static func of(p: Node) -> GrenadeBelt:
	return p.get_node_or_null("GrenadeBelt") as GrenadeBelt if p else null


func _ready() -> void:
	name = "GrenadeBelt"
	player = get_parent() as Player
	if not InputMap.has_action("grenade"):
		InputMap.add_action("grenade")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_G
		InputMap.action_add_event("grenade", ev)
	_build_hud()
	_setup_buys.call_deferred()


func _setup_buys() -> void:
	if player.game == null or player.game.level == null:
		return
	for b in GrenadeBuy.create_all(player.game.level):
		player.game.level.interactables.append(b)


func set_count(n: int) -> void:
	count = clampi(n, 0, MAX)
	_refresh()


# Press / release (keyboard or touch).
func set_held(down: bool) -> void:
	var monkeys := MonkeyBelt.of(player)   # monkey bombs take the grenade slot (monkey_belt.gd)
	if monkeys and monkeys.active() and not _held:
		monkeys.set_held(down)
		return
	if down and not _held:
		_held = true
		_start_cook()
	elif not down and _held:
		_held = false
		if cooking:
			_throw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("grenade"):
		set_held(true)
	elif event.is_action_released("grenade"):
		set_held(false)


func _start_cook() -> void:
	if cooking or count <= 0 or _cooldown > 0.0 or player.dead:
		return
	var vm := _vm()
	if vm and vm.drinking:
		return
	cooking = true
	cook_time = 0.0
	set_count(count - 1)
	# the arms pull the pin with the grenade in hand (viewmodel.gd, state Priminggrenade)
	if vm:
		vm.hold_item(Grenade.model(), Viewmodel.GRENADE_PRIME)
		return
	_in_hand = Grenade.model()
	var cam := player.get_viewport().get_camera_3d()
	cam.add_child(_in_hand)
	_in_hand.rotation = Vector3(deg_to_rad(-35), deg_to_rad(20), deg_to_rad(-15))
	_in_hand.position = HOLD_POS + Vector3(0, -0.15, 0.1)
	_in_hand.create_tween().tween_property(_in_hand, "position", HOLD_POS, 0.15)


func _vm() -> Viewmodel:
	return player.get("_viewmodel") as Viewmodel


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if player.game and player.game.round_number > _round_seen:
		_round_seen = player.game.round_number
		set_count(count + PER_ROUND)
	if not cooking:
		return
	cook_time += delta
	if _vm() and _vm().throwing():
		_hold_fire(0.3)
	else:
		_dip_weapon()
	if player.dead:
		_drop_in_hand()
		cooking = false
		return
	if cook_time >= Grenade.FUSE:
		# cooked too long: it goes off in the player's hand
		var cam := player.get_viewport().get_camera_3d()
		var g := Grenade.spawn(player.game, cam.global_position - cam.global_basis.z * 0.4 - Vector3.UP * 0.3, Vector3.ZERO, 0.0, player)
		g.in_hand = true
		g.explode()
		_drop_in_hand()
		cooking = false
		_cooldown = COOLDOWN


func _throw() -> void:
	cooking = false
	_cooldown = COOLDOWN
	var vm := _vm()
	if vm and vm.throwing():
		# Throwinggrenade: the grenade leaves the hand at the throwGrenade call (99 ms)
		var t := vm.throw_item(Viewmodel.GRENADE_THROW, Viewmodel.GRENADE_RELEASE)
		_hold_fire(t + 0.3)
		get_tree().create_timer(Viewmodel.GRENADE_RELEASE, false).timeout.connect(_release.bind(Grenade.FUSE - cook_time - Viewmodel.GRENADE_RELEASE))
	else:
		_release(Grenade.FUSE - cook_time)
	Sfx.instance.play("knife_slash", -10.0, 0.7)   # whoosh
	if _in_hand:
		var h := _in_hand
		_in_hand = null
		var tw := h.create_tween()
		tw.tween_property(h, "position", HOLD_POS + Vector3(-0.1, 0.15, -0.5), 0.08)
		tw.tween_callback(h.queue_free)


func _release(fuse_left: float) -> void:
	if player.dead or player.game == null:
		return
	var cam := player.get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	var from := cam.global_position + fwd * 0.45 + cam.global_basis.x * 0.12
	var vm := player.get("_viewmodel") as Viewmodel
	var hand: Variant = vm.item_position() if vm else null
	if hand != null and (hand as Vector3).distance_to(cam.global_position) < 1.2:
		from = hand   # from the hand of the throw animation
	# don't spawn it inside a wall right in front of the player
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, from, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		from = (hit["position"] as Vector3) - fwd * 0.1
	var vel := fwd * THROW_SPEED + Vector3.UP * THROW_UP + Vector3(player.velocity.x, 0.0, player.velocity.z)
	Grenade.spawn(player.game, from, vel, maxf(fuse_left, 0.05), player)


# no shooting while the hand holds the grenade
func _hold_fire(t: float) -> void:
	player.set("_cooldown", maxf(float(player.get("_cooldown")), t))


func _drop_in_hand() -> void:
	var vm := _vm()
	if vm:
		vm.end_item()
	if _in_hand:
		_in_hand.queue_free()
		_in_hand = null


# lower the gun while the grenade is in hand (Viewmodel's own reload dip)
func _dip_weapon() -> void:
	var vm = player.get("_viewmodel")
	if vm != null and "_kick" in vm:
		vm.set("_kick", minf(float(vm.get("_kick")), -0.6))


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_icons = HBoxContainer.new()
	_icons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_icons.position += Vector2(-330, -48)  # under the ammo line, clear of the points popups
	_icons.add_theme_constant_override("separation", 2)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_icons)
	_icon_tex = AtlasTexture.new()
	_icon_tex.atlas = load(ICON_ATLAS) as Texture2D
	_icon_tex.region = ICON_RECT
	_refresh()


func _refresh() -> void:
	if _icons == null:
		return
	for c in _icons.get_children():
		c.queue_free()
	for i in count:
		var t := TextureRect.new()
		t.texture = _icon_tex
		t.custom_minimum_size = Vector2(30, 30)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icons.add_child(t)
