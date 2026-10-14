# Nacht's flamethrower cabinet: entity 41870615 (CCabinetSpec + CActionBuyWeaponSpec
# "flamethrower", cost 2000, ammo cost 380; model efe38792 = the two doors, rigged in the
# Nacht dynamics group), upstairs. Its ASM 6d80abac (nacht_dynamics):
#   S0 closed (pose 343eed5b), message "Open Cabinet / [Cost: 2000]"
#      -goodieInteract/open-> S1 opening (7ac8dfb3, 0.766 s): fireAction(1) = the buy action
#      (flamethrower for 2000), playsound 1a86304c (cabinet_open) -> S3
#   S3 open (pose 6f02ccb1), message "Buy Ammo / [Cost: 380]"
#      -goodieInteract-> S4: fireAction(1) (ammo for 380) -> S3
#      -returnToIdle-> S2 closing (7ac8dfb3 backwards, sound) -> S0: nothing sends it in the
#      Nacht Lua, so the cabinet stays open
# The weapon buy itself is the usual CActionBuyWeapon: the gun when the player does not
# have it (cost), ammo when he does (ammo cost). CCabinet (kiwi vtable 0x2b5004, va
# 0x237900) only allows the ammo price once its "open" flag (+0x1c) is set: closed, it is
# always "Open Cabinet [2000]".
class_name FlameCabinet
extends Node3D

const USE_RANGE := 1.8
const ANIM_CLOSED := "343eed5b"
const ANIM_OPENING := "7ac8dfb3"
const ANIM_OPEN := "6f02ccb1"
const SOUND := "1a86304c"     # cabinet_open

var entity := ""
var weapon := "flamethrower"
var cost := 2000
var ammo_cost := 380
var is_open := false
var use_point := Vector3.ZERO
var _anim: AnimationPlayer


static func create_all(level: Level) -> Array:
	var out := []
	for n in level.entities:
		var e: Dictionary = level.entities[n]
		if not ("CCabinetSpec" in e["components"] and "CActionBuyWeaponSpec" in e["components"]):
			continue
		var c := FlameCabinet.new()
		c.name = "Cabinet_" + String(n)
		level.nav_region.add_child(c)
		c.setup(level, n)
		out.append(c)
	return out


func setup(level: Level, entity_: String) -> void:
	entity = entity_
	add_to_group(SaveGame.PROVIDER_GROUP)
	var e: Dictionary = level.entities[entity]
	var p: Dictionary = e.get("params", {})
	weapon = String(p.get("weapon", weapon))
	cost = int(p.get("cost", cost))
	ammo_cost = int(p.get("ammo_cost", ammo_cost))
	var root := Level.flag_transform(e["transform"])
	global_transform = root * Level.flag_transform(e["children"][-1]) if not e["children"].is_empty() else root
	var cols: Array = e.get("colliders", [])
	use_point = root * Trap._box_centre(cols[0]) if not cols.is_empty() else root.origin
	for h in e["models"]:
		var m := level.dynamics_model(h)
		if m:
			add_child(m)
			var aps := m.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty():
				_anim = aps[0]
			break
	_pose(ANIM_CLOSED)
	var s := SaveGame.resumed_state(self)
	if not s.is_empty():
		load_state(s)


func _pose(a: String) -> void:
	if _anim and _anim.has_animation(a):
		_anim.play(a)
		_anim.seek(0.0, true)
		_anim.pause()


func usable_from(p: Vector3) -> bool:
	return Vector2(p.x - use_point.x, p.z - use_point.z).length() < USE_RANGE and absf(p.y + 0.9 - use_point.y) < 1.6


func _owned(player: Player) -> bool:
	return player.weapons.any(func(w): return w["name"] == weapon)


func price(player: Player) -> int:
	return ammo_cost if is_open and _owned(player) else cost


func prompt(player: Player) -> String:
	if not is_open:
		return "Tieni premuto E per aprire l'armadio [%d]" % cost
	if _owned(player):
		return "Tieni premuto E per le munizioni %s [%d]" % [Weapons.display(weapon), ammo_cost]
	return "Tieni premuto E per comprare %s [%d]" % [Weapons.display(weapon), cost]


func interact(player: Player) -> void:
	var c := price(player)
	if player.points < c:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-c)
	player.give_weapon(weapon)   # the gun, or a refill when held
	Sfx.instance.play("buy_success")
	if not is_open:
		open()


func open(animate := true) -> void:
	is_open = true
	if not animate:
		_pose(ANIM_OPEN)
		return
	Sfx.instance.play_at(SOUND, global_position + Vector3.UP)
	if _anim and _anim.has_animation(ANIM_OPENING):
		var a := _anim.get_animation(ANIM_OPENING)
		a.loop_mode = Animation.LOOP_NONE
		_anim.play(ANIM_OPENING)


# ------------------------------------------------------------------ save (save_game.gd providers)

func save_key() -> String:
	return "cabinet_" + entity


func save_state() -> Dictionary:
	return {"open": is_open}


func load_state(d: Dictionary) -> void:
	if bool(d.get("open", false)) and not is_open:
		open(false)
