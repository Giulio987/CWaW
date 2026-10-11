# Frag grenade wall buy (entities with CActionBuyGrenadeSpec, cost from params):
# refills the player to GrenadeBelt.MAX. Registered in level.interactables by
# GrenadeBelt, so Player's usual prompt/interact code drives it.
class_name GrenadeBuy
extends Node3D

const USE_RANGE := 1.8

var cost := 250
var use_point := Vector3.ZERO


static func create_all(level: Level) -> Array:
	var out := []
	for n in level.entities:
		var e: Dictionary = level.entities[n]
		if not "CActionBuyGrenadeSpec" in e["components"]:
			continue
		var b := GrenadeBuy.new()
		b.name = "GrenadeBuy_" + String(n)
		b.cost = int(e.get("params", {}).get("cost", 250))
		var root := level.entity_transform(n)
		var cols: Array = e.get("colliders", [])
		b.use_point = root * Trap._box_centre(cols[0]) if not cols.is_empty() else root.origin
		level.add_child(b)
		b.global_position = b.use_point
		out.append(b)
	return out


func usable_from(p: Vector3) -> bool:
	return Vector2(p.x - use_point.x, p.z - use_point.z).length() < USE_RANGE and absf(p.y + 0.9 - use_point.y) < 1.6


func prompt(player: Player) -> String:
	var belt := GrenadeBelt.of(player)
	if belt == null or belt.count >= GrenadeBelt.MAX:
		return ""
	return "Premi E per comprare granate [%d]" % cost


func interact(player: Player) -> void:
	var belt := GrenadeBelt.of(player)
	if belt == null or belt.count >= GrenadeBelt.MAX:
		return
	if player.points < cost:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-cost)
	belt.set_count(GrenadeBelt.MAX)
	Sfx.instance.play("buy_success")
