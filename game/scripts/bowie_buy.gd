# Bowie knife wall buy (Der Riese "BuyWeaponBowie", 3000): created by bowie_knife.gd from
# the CActionBuyWeaponSpec whose weapon is iw_hash("bowieKnife"). Bought once: it replaces
# the knife for the rest of the game.
class_name BowieBuy
extends Node3D

const USE_RANGE := 1.8

var cost := 3000
var use_point := Vector3.ZERO


func usable_from(p: Vector3) -> bool:
	return Vector2(p.x - use_point.x, p.z - use_point.z).length() < USE_RANGE and absf(p.y + 0.9 - use_point.y) < 1.8


func prompt(player: Player) -> String:
	var b := BowieKnife.of(player)
	if b == null or b.owned:
		return ""
	return Lang.prompt("comprare il coltello Bowie", "#40a610a8", cost, true)   # "Buy Bowie Knife\n[Cost: %d]\n(one time only)"


func interact(player: Player) -> void:
	var b := BowieKnife.of(player)
	if b == null or b.owned:
		return
	if player.points < cost:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-cost)
	b.give()
	Sfx.instance.play("buy_success")
