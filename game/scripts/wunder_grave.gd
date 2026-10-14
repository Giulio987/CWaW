# Shi No Numa: the Wunderwaffe grave (shinonuma.lua 817-869 + bytecode of Level.Trigger
# and Level.Timeout, levels/shinonuma/shinonuma.luac):
#   Begin: WunderwaffeCount = 9, WunderwaffeSetup hides WunderwaffeGraveOpen<n> and
#     WunderwaffeGraveClosed<n> and disables WunderwaffeGameTrigger<n> (n = 1..9);
#     Game.SetWunderWaffeFound(false).
#   Level.Trigger (any trigger, end of the function): when AllAreasUnlocked is false and
#     CheckAllAreasUnlocked() (every area but "ledge" open) -> Game.Timeout(2000,
#     "WunderwaffeStart"), AllAreasUnlocked = true.
#   WunderwaffeStart: SetWunderWaffeNumber(RandomNumber(1, 10)) (upper bound excluded:
#     grave 1..9), EnableRender("WunderwaffeGraveClosed"..n), EnableTrigger(
#     "WunderwaffeGameTrigger"..n), ShowMessage("LS_WUNDERWAFFE_GAME_FIND", 8000) ("All
#     areas unlocked, now find the grave!"), SetUsingShovel(true).
#   Level.Trigger "WunderwaffeGameTrigger"..n (a CTriggerInteractableSpec): WunderwaffeEnd
#     (closed grave hidden, open grave shown, trigger off, SetWunderWaffeFound(true)), then
#     Game.AddPlayerWeapon("wunderwaffe") for the local player.
#   Resume (WunderwaffeReload): all areas open -> the open grave if found, else the closed
#     grave and its trigger again (the number is kept by the engine; here in the save).
# The grave models (closed 0f870b7a, open 4aea0959: CIwRenderableModelSpec of the
# WunderwaffeGrave<Closed|Open><n> entities) are not in the static scene: they come from
# the level's dynamics and are placed at the entities here.
# SetUsingShovel turns the melee item into the "shovel" CItemKnife (player group 1bb91af6,
# CItemKnife::Serialise va 0xfef00: damage 400 against the knife's 200, first-person model
# 423ce590): here knife_damage 400 (player.gd, via the "shovel_damage" meta; the base knife
# stays 150) and the shovel model in the knife states (viewmodel.gd set_knife_model, as the
# Bowie knife). Kept for the rest of the game (in the save).
extends Node3D

const COUNT := 9
const START_DELAY := 2.0     # Game.Timeout(2000, "WunderwaffeStart")
const MESSAGE_TIME := 8.0
const DIG_RANGE := 1.6       # metres from the trigger entity (its collider size is not decoded)
const SHOVEL_DAMAGE := 400.0 # CItemKnife "shovel"
const SHOVEL_MODEL := "423ce590"   # in the left fist with no fix, like every CItemKnife model

var level: Level
var number := 0              # Game.GetWunderWaffeNumber (0 = not drawn yet)
var started := false         # Script.WunderwaffeGame
var found := false           # Game.GetWunderWaffeFound
var shovel := false          # Game.SetUsingShovel
var _all_open := false       # Script.AllAreasUnlocked
var _timer := -1.0
var _poll := 0.0
var _models := {}            # entity name -> Node3D
var _shovel_on: Player       # player the shovel was given to


func setup(level_: Level) -> void:
	level = level_
	add_to_group(SaveGame.PROVIDER_GROUP)
	for n in range(1, COUNT + 1):   # WunderwaffeSetup: all hidden
		for k in ["Open", "Closed"]:
			var e := "WunderwaffeGrave%s%d" % [k, n]
			if not level.has_entity(e) or (level.entity(e).get("models", []) as Array).is_empty():
				continue
			var m := level.dynamics_model(String(level.entity(e)["models"][0]))
			if m == null:
				continue
			m.name = e
			level.add_child(m)
			m.global_transform = level.entity_transform(e)
			m.visible = false
			_models[e] = m


func save_key() -> String:
	return "wunderwaffe_grave"


func save_state() -> Dictionary:
	return {"number": number, "started": started, "found": found, "shovel": shovel}


func load_state(d: Dictionary) -> void:
	number = int(d.get("number", 0))
	found = bool(d.get("found", false))
	started = bool(d.get("started", false)) and number > 0
	shovel = bool(d.get("shovel", started))
	if started:   # WunderwaffeReload
		_all_open = true
		_place()
		_render("WunderwaffeGraveOpen%d" % number, found)
		_render("WunderwaffeGraveClosed%d" % number, not found)


func game() -> Game:
	return level.get_parent() as Game if level else null


func all_areas_open() -> bool:   # Script.CheckAllAreasUnlocked
	var g := game()
	if g == null:
		return false
	var areas: Dictionary = g.get("_areas")
	return not areas.is_empty() and areas.keys().all(func(a): return a == "ledge" or a in g.open_areas)


func _process(delta: float) -> void:
	if shovel:
		_apply_shovel()
	if _timer >= 0.0:
		_timer -= delta
		if _timer < 0.0:
			start()
		return
	if _all_open:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	if all_areas_open():
		_all_open = true
		_timer = START_DELAY


# WunderwaffeStart
func start(n := 0) -> void:
	number = n if n > 0 else randi_range(1, COUNT)
	started = true
	shovel = true
	_place()
	_render("WunderwaffeGraveClosed%d" % number, true)
	_apply_shovel()
	var g := game()
	if g and g.hud:
		g.hud.show_message("Tutte le aree sbloccate, ora trova la tomba!", MESSAGE_TIME)


# Game.SetUsingShovel(true): the melee item becomes the shovel (once the player and its
# view model exist; also after a resume)
func _apply_shovel() -> void:
	var g := game()
	var p: Player = g.player if g else null
	if p == null or p == _shovel_on:
		return
	var vm := p.get("_viewmodel") as Viewmodel
	if vm == null:
		return
	p.set_meta("shovel_damage", SHOVEL_DAMAGE)
	vm.set_knife_model(SHOVEL_MODEL)
	_shovel_on = p


func _place() -> void:
	global_transform = level.entity_transform("WunderwaffeGameTrigger%d" % number)


func _render(entity: String, on: bool) -> void:   # Game.EnableRender / DisableRender
	if _models.has(entity):
		_models[entity].visible = on


func model(entity: String) -> Node3D:
	return _models.get(entity)


# ---------------------------------------------------------------- interactable

func usable_from(p: Vector3) -> bool:
	return started and not found and global_position.distance_to(p) < DIG_RANGE + 0.9


func prompt(_player: Player) -> String:
	return "Premi E per scavare la tomba" if started and not found else ""


func interact(player: Player) -> void:
	if not started or found:
		return
	# WunderwaffeEnd
	_render("WunderwaffeGraveClosed%d" % number, false)
	_render("WunderwaffeGraveOpen%d" % number, true)
	found = true
	player.give_weapon("wunderwaffe")
	Sfx.instance.vox("weapon_tesla")
