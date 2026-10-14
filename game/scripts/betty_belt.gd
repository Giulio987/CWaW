# The player's Bouncing Betties: count, planting (key B or the touch "Betty" button),
# round refill, HUD icons, wall buys and save state.
# Original:
#   - sold on the wall by CActionBuyBettySpec entities, cost 1000 (Der Riese, Shi No Numa,
#     two on Verrückt); on Nacht the mystery box has it (MysteryWeaponsNacht "...,betty")
#   - MaxBetties 2 (console.bin); waves.lua StartWave and the dog round:
#     `if Game.ArePlayerBettiesUnlocked() then Game.SetPlayerBetties(2) end`, so once
#     bought the player has 2 again at every round
#   - arms state machine (every gun's CIsAnimStateMachine, e.g. 9690ec52): Primingbetty =
#     arms c4a86447 with betty fae9e306 (0.9 s), then arms e870c316 with betty 8a758615
#     (0.97 s, the pin comes out; primeBetty call), Plantingbetty = arms e86e9ec4 with
#     betty 8a7361c3 (1.0 s; plantBetty call), then back to the gun
#   - BettyPlantDistance 50 units (0.125 m in front of the player)
#   - HUD: the touch "special" button (CIwGuiMultiBitmap specialBitmap in the ui group)
#     shows the item in the slot: stick grenade (139,433), betty (204,472), molotov (100,433)
class_name BettyBelt
extends Node

const ITEM := "betty"            # mystery box item (Nacht)
const MAX := 2                   # MaxBetties
const PLANT_DISTANCE := 0.125    # BettyPlantDistance 50 units
const ARMS_RAISE := "c4a86447"
const ARMS_PRIME := "e870c316"
const ARMS_PLANT := "e86e9ec4"
const BETTY_IDLE := "fae9e306"
const BETTY_PRIME := "8a758615"
const BETTY_PLANT := "8a7361c3"
const PLANT_AT := 0.5            # into Plantingbetty: the betty leaves the hand (inferred)
const PLANT_SOUND := "af527ecb"  # betty_plant
const ICON_ATLAS := "res://assets/textures/ingame/ui/2f66d01c.png"
const ICON_RECT := Rect2(204, 472, 39, 40)

var player: Player
var count := 0
var unlocked := false            # Game.ArePlayerBettiesUnlocked
var planting := false
var _round_seen := 0
var _icons: HBoxContainer
var _icon_tex: AtlasTexture
var _touch_btn: Button
var _step_id := 0


static func of(p: Node) -> BettyBelt:
	return p.get_node_or_null("BettyBelt") as BettyBelt if p else null


# Wall buy / mystery box: unlocks the betties and fills to MAX.
static func give(p: Player) -> BettyBelt:
	var b := of(p)
	if b == null:
		return null
	b.unlocked = true
	b.set_count(MAX)
	return b


func _ready() -> void:
	name = "BettyBelt"
	player = get_parent() as Player
	add_to_group(SaveGame.PROVIDER_GROUP)
	if not InputMap.has_action("betty"):
		InputMap.add_action("betty")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_B
		InputMap.action_add_event("betty", ev)
	_build_hud()
	_setup_buys.call_deferred()


func _setup_buys() -> void:
	if player.game == null or player.game.level == null:
		return
	for b in BettyBuy.create_all(player.game.level):
		player.game.level.interactables.append(b)
	var s := SaveGame.resumed_state(self)
	if not s.is_empty() and not has_meta("save_loaded"):
		set_meta("save_loaded", true)
		load_state(s)


func set_count(n: int) -> void:
	count = clampi(n, 0, MAX)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("betty"):
		start_plant()


# One press plays Primingbetty + Plantingbetty; the betty is planted at PLANT_AT.
func start_plant() -> bool:
	if planting or count <= 0 or player.dead or player.game == null:
		return false
	var vm := _vm()
	if vm and (vm.drinking or vm.throwing()):
		return false
	planting = true
	set_count(count - 1)
	_step_id += 1
	var id := _step_id
	if vm == null:
		_plant(id)
		return true
	var t1 := vm.hold_item(Betty.model(), ARMS_RAISE, BETTY_IDLE)
	_hold_fire(3.2)   # no shooting with the betty in hand (0.9 + 0.97 + 1.0 s)
	get_tree().create_timer(maxf(t1, 0.05), false).timeout.connect(func():
		if id != _step_id or _vm() == null:
			return
		var t2 := _vm().play_item_anim(ARMS_PRIME, BETTY_PRIME)
		get_tree().create_timer(maxf(t2, 0.05), false).timeout.connect(func():
			if id != _step_id or _vm() == null:
				return
			var t3 := _vm().play_item_anim(ARMS_PLANT, BETTY_PLANT)
			get_tree().create_timer(PLANT_AT, false).timeout.connect(_plant.bind(id))
			get_tree().create_timer(maxf(t3, PLANT_AT + 0.05), false).timeout.connect(func():
				if id != _step_id:
					return
				if _vm():
					_vm().end_item())))
	return true


func _plant(id: int) -> void:
	if id != _step_id or not planting:
		return
	planting = false
	if player.dead or player.game == null:
		return
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := player.global_position + fwd * PLANT_DISTANCE
	var b := Betty.plant(player.game, at, player.rotation.y, player)
	if b:
		Sfx.instance.play_at(PLANT_SOUND, b.global_position)
	else:
		set_count(count + 1)   # nowhere to put it: keep it
	var vm := _vm()
	if vm and vm.throwing():
		vm.throw_item("", 0.0)   # the betty leaves the hand now


func _vm() -> Viewmodel:
	return player.get("_viewmodel") as Viewmodel


func _hold_fire(t: float) -> void:
	player.set("_cooldown", maxf(float(player.get("_cooldown")), t))


func _physics_process(_delta: float) -> void:
	if player.game and player.game.round_number > _round_seen:
		_round_seen = player.game.round_number
		if unlocked:
			set_count(MAX)   # SetPlayerBetties(2) at every round (waves.lua)
	if planting and player.dead:
		planting = false
		_step_id += 1
		if _vm():
			_vm().end_item()
	if _touch_btn:
		_touch_btn.visible = count > 0 or planting


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_icons = HBoxContainer.new()
	_icons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_icons.position += Vector2(-190, -48)   # right of the grenade icons (grenade_belt.gd: 4 x 32 px from -330)
	_icons.add_theme_constant_override("separation", 2)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_icons)
	_icon_tex = AtlasTexture.new()
	_icon_tex.atlas = load(ICON_ATLAS) as Texture2D
	_icon_tex.region = ICON_RECT
	if DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch-ui"):
		_touch_btn = Button.new()
		_touch_btn.text = "Betty"
		_touch_btn.icon = _icon_tex
		_touch_btn.expand_icon = true
		_touch_btn.size = Vector2(90, 90)
		_touch_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_touch_btn.position += Vector2(-560, -420)   # left of the 💣 button (hud.gd)
		_touch_btn.modulate = Color(1, 1, 1, 0.6)
		_touch_btn.visible = false
		_touch_btn.button_down.connect(start_plant)
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


# ------------------------------------------------------------------ save (save_game.gd providers)

func save_key() -> String:
	return "betty_belt"


func save_state() -> Dictionary:
	var placed := []
	if player and player.game:
		for b in player.get_tree().get_nodes_in_group("betties"):
			var bt := b as Betty
			if bt and not bt.triggered and not bt.exploded and player.game.is_ancestor_of(bt):
				placed.append([bt._ground.x, bt._ground.y, bt._ground.z, bt.rotation.y])
	return {"unlocked": unlocked, "count": count + (1 if planting else 0), "placed": placed}


func load_state(d: Dictionary) -> void:
	unlocked = bool(d.get("unlocked", false))
	set_count(int(d.get("count", 0)))
	if player and player.game:
		_round_seen = player.game.round_number
		for p in d.get("placed", []):
			if p is Array and p.size() >= 4:
				Betty.plant(player.game, Vector3(p[0], p[1], p[2]), float(p[3]), player)
