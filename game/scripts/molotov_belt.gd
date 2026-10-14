# The player's Molotov cocktails (mystery box item "molotov" on every map).
# Original (kiwi, player inventory object, va 0xfcb24 ctor):
#   - four "special" items with their own counts: grenade (slot 0, +0x3c), betty (1, +0x44,
#     unlocked +0x48), molotov (2, +0x5c), monkey bomb (3, +0x50); +0x60 = the selected
#     slot, the one the touch "special" button uses (its CIwGuiMultiBitmap shows that item:
#     grenade / betty / molotov images of the HUD atlas)
#   - the box hands over CActionBuyMolotov: slot 2, count = MaxMolotovs (console.bin 4,
#     default "4"), set, not added; the selection is not changed (kiwi 0x11cbb8 -> 0xfc9f0)
#   - a player input cycles the selection (0xfc414): next slot with a count > 0, in the
#     order grenade -> betty -> molotov -> monkey -> grenade
#   - using an item (0xfc644, from the throw callback) lowers its count; when the molotovs
#     run out the selection moves on to the next slot with a count (monkey, grenade, betty)
#   - arms states (every gun's CIsAnimStateMachine, e.g. 95a20492): Lightingmolotov = arms
#     d926090d (2.54 s) + molotov 0f6787cc, lightMolotov at its start (MaxMolotov* movement
#     caps: 0.5 like the grenade); input throwMolotov (button released) -> Throwingmolotov
#     = arms d9b67069 (0.46 s), throwMolotov call at 299 ms (the bottle leaves the hand);
#     MolotovThrowOffset "{0,0,0}"
#   - no Lua: molotovs are not refilled at the new round
# Remake: the grenade key (G, touch 💣) throws the selected special item; T (touch ⇄)
# cycles grenade / molotov (the betty keeps its own key B, monkeys take the grenade slot as
# before: monkey_belt.gd). Holding G lights the molotov, releasing throws it.
class_name MolotovBelt
extends Node

const ITEM := "molotov"
const MAX := 4                     # MaxMolotovs
const ARMS_LIGHT := "d926090d"     # Lightingmolotov
const ARMS_THROW := "d9b67069"     # Throwingmolotov
const RELEASE := 0.299             # throwMolotov
const RAG_LIT_AT := 1.3            # the lighter reaches the rag (by eye, estimated)
const RAG_BONE := 7                # bone07: top of the rag
const THROW_SPEED := GrenadeBelt.THROW_SPEED   # same CProjectileSpec speed as the grenade
const THROW_UP := GrenadeBelt.THROW_UP
const COOLDOWN := 0.8
const ICON_ATLAS := "res://assets/textures/ingame/ui/2f66d01c.png"
const ICON_RECT := Rect2(100, 433, 39, 40)   # specialBitmap image 2 (molotov)

var player: Player
var count := 0
var selected := false     # the special slot is on the molotovs (else grenades/monkeys)
var holding := false      # Lightingmolotov
var _held := false
var _throwing := false
var _cooldown := 0.0
var _step := 0
var _icons: HBoxContainer
var _icon_tex: AtlasTexture
var _touch_btn: Button


static func of(p: Node) -> MolotovBelt:
	return p.get_node_or_null("MolotovBelt") as MolotovBelt if p else null


# Mystery box: CActionBuyMolotov sets the count to MaxMolotovs.
static func give(p: Player) -> MolotovBelt:
	var b := of(p)
	if b == null:
		return null
	b.set_count(MAX)
	if p.game and p.game.hud and not b.selected:
		p.game.hud.show_message("Molotov x%d: premi T per selezionarle" % MAX, 3.0)
	return b


# true while the grenade key belongs to the molotovs
func active() -> bool:
	return holding or _throwing or (selected and count > 0)


func _ready() -> void:
	name = "MolotovBelt"
	if player == null:
		player = get_parent() as Player
	add_to_group(SaveGame.PROVIDER_GROUP)
	if not InputMap.has_action("special_cycle"):
		InputMap.add_action("special_cycle")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_T
		InputMap.action_add_event("special_cycle", ev)
	_build_hud()
	_resume.call_deferred()


func _resume() -> void:
	var s := SaveGame.resumed_state(self)
	if not s.is_empty() and not has_meta("save_loaded"):
		set_meta("save_loaded", true)
		load_state(s)


func set_count(n: int) -> void:
	count = clampi(n, 0, MAX)
	_refresh()


# Selection input (0xfc414): grenade <-> molotov (only with molotovs left).
func cycle() -> void:
	if holding or _throwing:
		return
	selected = not selected and count > 0
	_refresh()
	var gb := GrenadeBelt.of(player)
	if gb and gb.has_method("_refresh"):
		gb.call("_refresh")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("special_cycle"):
		cycle()


# Press / release of the grenade key (GrenadeBelt forwards while active()).
func set_held(down: bool) -> void:
	if down and not _held:
		_held = true
		_light()
	elif not down and _held:
		_held = false
		if holding:
			_throw()


func _vm() -> Viewmodel:
	return player.get("_viewmodel") as Viewmodel


func _hold_fire(t: float) -> void:
	player.set("_cooldown", maxf(float(player.get("_cooldown")), t))


func _light() -> bool:
	if holding or _throwing or count <= 0 or _cooldown > 0.0 or player.dead or player.game == null:
		return false
	var vm := _vm()
	if vm and (vm.drinking or vm.throwing()):
		return false
	holding = true
	_step += 1
	var id := _step
	if vm:
		var item := Molotov.hand_model()
		vm.hold_item(item, ARMS_LIGHT, Molotov.HAND_ANIM)
		get_tree().create_timer(RAG_LIT_AT, false).timeout.connect(func():
			if id == _step and is_instance_valid(item) and item.is_inside_tree():
				_light_rag(item))
	_hold_fire(0.5)
	return true


# flame on the rag (bone07 of the skinned molotov)
func _light_rag(item: Node3D) -> void:
	var sk := item.find_children("*", "Skeleton3D", true, false)
	var flame := Molotov.rag_flame()
	flame.scale = Vector3.ONE * 0.6
	if sk.is_empty() or (sk[0] as Skeleton3D).get_bone_count() <= RAG_BONE:
		item.add_child(flame)
		return
	var ba := BoneAttachment3D.new()
	ba.bone_idx = RAG_BONE
	(sk[0] as Skeleton3D).add_child(ba)
	ba.add_child(flame)
	Sfx.instance.play("knife_slash", -18.0, 1.6)   # whoosh of the rag catching (no sound in the original data)


func _throw() -> void:
	holding = false
	_throwing = true
	_cooldown = COOLDOWN
	var vm := _vm()
	var id := _step
	if vm and vm.throwing():
		var t := vm.throw_item(ARMS_THROW, RELEASE)
		_hold_fire(t + 0.3)
		get_tree().create_timer(RELEASE, false).timeout.connect(_release.bind(id))
	else:
		_release(id)
	Sfx.instance.play("knife_slash", -10.0, 0.7)   # whoosh


func _release(id: int) -> void:
	_throwing = false
	if id != _step or player.dead or player.game == null:
		_refresh()
		return
	set_count(count - 1)   # 0xfc644
	if count <= 0:
		selected = false   # the selection moves on (monkeys / grenades)
		_refresh()
	var cam := player.get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	var from := cam.global_position + fwd * 0.45 + cam.global_basis.x * 0.12
	var vm := _vm()
	var hand: Variant = vm.item_position() if vm else null
	if hand != null and (hand as Vector3).distance_to(cam.global_position) < 1.2:
		from = hand
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, from, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		from = (hit["position"] as Vector3) - fwd * 0.1
	var vel := fwd * THROW_SPEED + Vector3.UP * THROW_UP + Vector3(player.velocity.x, 0.0, player.velocity.z)
	Molotov.spawn(player.game, from, vel, player)


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if (holding or _throwing) and player.dead:
		holding = false
		_throwing = false
		_step += 1
		if _vm():
			_vm().end_item()
	if holding:
		_hold_fire(0.3)
	if _touch_btn:
		_touch_btn.visible = count > 0


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_icons = HBoxContainer.new()
	_icons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_icons.position += Vector2(-330, -84)   # above the grenade icons (grenade_belt.gd)
	_icons.add_theme_constant_override("separation", 2)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_icons)
	_icon_tex = AtlasTexture.new()
	_icon_tex.atlas = load(ICON_ATLAS) as Texture2D
	_icon_tex.region = ICON_RECT
	if DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch-ui"):
		_touch_btn = Button.new()
		_touch_btn.text = "⇄"
		_touch_btn.icon = _icon_tex
		_touch_btn.expand_icon = true
		_touch_btn.size = Vector2(90, 90)
		_touch_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_touch_btn.position += Vector2(-450, -530)   # above the 💣 button (hud.gd)
		_touch_btn.modulate = Color(1, 1, 1, 0.6)
		_touch_btn.visible = false
		_touch_btn.button_down.connect(cycle)
		layer.add_child(_touch_btn)
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
	_icons.modulate = Color(1, 1, 1, 1.0 if selected else 0.45)   # the selected special item is bright


# ------------------------------------------------------------------ save (save_game.gd providers)

func save_key() -> String:
	return "molotov_belt"


func save_state() -> Dictionary:
	return {"count": count + (1 if holding or _throwing else 0), "selected": selected}


func load_state(d: Dictionary) -> void:
	set_count(int(d.get("count", 0)))
	selected = bool(d.get("selected", false)) and count > 0
	_refresh()
