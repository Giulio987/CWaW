# Bouncing Betty wall buy (entities with CActionBuyBettySpec, cost from params: 1000 on
# Der Riese, Shi No Numa and Verrückt): unlocks the betties and fills the player to
# BettyBelt.MAX. Registered in level.interactables by BettyBelt, like GrenadeBuy.
class_name BettyBuy
extends Node3D

const USE_RANGE := 1.8

var cost := 1000
var use_point := Vector3.ZERO


static func create_all(level: Level) -> Array:
	var out := []
	for n in level.entities:
		var e: Dictionary = level.entities[n]
		if not "CActionBuyBettySpec" in e["components"]:
			continue
		var b := BettyBuy.new()
		b.name = "BettyBuy_" + String(n)
		b.cost = int(e.get("params", {}).get("cost", 1000))
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
	var belt := BettyBelt.of(player)
	if belt == null or belt.count >= BettyBelt.MAX:
		return ""
	return "Premi E per comprare le Bouncing Betty [%d]" % cost


func interact(player: Player) -> void:
	var belt := BettyBelt.of(player)
	if belt == null or belt.count >= BettyBelt.MAX:
		return
	if player.points < cost:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-cost)
	BettyBelt.give(player)
	Sfx.instance.play("buy_success")
