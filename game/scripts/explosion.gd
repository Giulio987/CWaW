# Radius damage (frag grenades, Ray Gun splash) and the explosion visuals.
# World at War: damage falls off with distance, zombies near the centre die,
# and the player is hurt by his own explosives when very close.
# Legs: the zombie's damage handler (kiwi 0x110708) takes the legs off every zombie hit
# by explosive damage (damage type 2: grenade, monkey bomb, betty, barrels), dead or alive;
# it is the only way to make a crawler. Explosions take no arms or heads: the
# CDismembermentSpec limbs only take bullet damage on a hit location (see zombie.gd).
# The Ray Gun splash is damage type 0 without a hit location: no legs, no gibs.
class_name Explosion

# Frag grenade, original values (effects group CSplashEffectSpec 925f425b, see
# tools/weapon_stats.py): a flat 250 to every zombie within 1200 units = 3 m, no falloff;
# line of sight is only checked beyond 960 units = 2.4 m ("los_free"). The splash's
# target mask (0x10000) does not include the player: thrown grenades never hurt him;
# the entity the grenade is attached to always takes the damage, so a grenade cooked
# until it goes off in hand kills him (Grenade.in_hand; 250 > PlayerHealth 20/40).
const FRAG := {
	"radius": 3.0, "max_damage": 250.0, "min_damage": 250.0, "kill_radius": 0.0, "los_free": 2.4,
	"crawl_chance": 1.0, "gib_chance": 0.0, "head_chance": 0.0,
	"player_radius": 0.0, "player_damage": 0.0, "shake": 1.0, "shake_radius": 14.0,
}
# Monkey bomb: same splash volume, 10000 damage (CSplashEffectSpec 9cede4f8)
const MONKEY := {
	"radius": 3.0, "max_damage": 10000.0, "min_damage": 10000.0, "kill_radius": 0.0, "los_free": 2.4,
	"crawl_chance": 1.0, "gib_chance": 0.0, "head_chance": 0.0,
	"player_radius": 0.0, "player_damage": 0.0, "shake": 1.0, "shake_radius": 14.0,
}
# Ray Gun splash; max/min damage are fractions of the gun's damage. Original: the
# projectile spawns a CSplashEffect (effects group 8e9001fb): the full 2450 to everything
# within 900 units = 2.25 m, no falloff (tools/weapon_stats.py)
const RAYGUN := {
	"radius": 2.25, "max_damage": 1.0, "min_damage": 1.0, "kill_radius": 0.0,
	"crawl_chance": 0.0, "gib_chance": 0.0, "head_chance": 0.0,
	"player_radius": 1.6, "player_damage": 40.0, "shake": 0.35, "shake_radius": 4.0,
}


# Applies the blast; returns {"hit": n, "killed": n, "crawlers": n, "gibs": n, "player": damage}.
static func blast(game: Node3D, pos: Vector3, by: Player, cfg: Dictionary, exclude: Object = null) -> Dictionary:
	var res := {"hit": 0, "killed": 0, "crawlers": 0, "gibs": 0, "player": 0.0}
	if game == null or not game.is_inside_tree():
		return res
	var space := game.get_world_3d().direct_space_state
	var radius := float(cfg["radius"])
	var eye := pos + Vector3.UP * 0.5
	for n in game.get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z == exclude or z.state == Zombie.State.DEAD:
			continue
		var feet := z.global_position
		var top := feet + Vector3.UP * (0.6 if z.crawler else 1.6)
		var closest := Geometry3D.get_closest_point_to_segment(pos, feet + Vector3.UP * 0.15, top)
		var d := pos.distance_to(closest)
		if d > radius:
			continue
		if d > float(cfg.get("los_free", 0.0)) and not _visible(space, eye, [(feet + top) * 0.5, top], by):
			continue
		var dmg := lerpf(float(cfg["max_damage"]), float(cfg["min_damage"]), clampf(d / radius, 0.0, 1.0))
		if d < float(cfg["kill_radius"]):
			dmg = maxf(dmg, z.health + 1.0)
		var g := z.get_parent() as Game
		var dies := dmg >= z.health or (g != null and g.insta_kill)
		res["hit"] += 1
		if not z is Dog:
			var standing := not z.crawler and z.state in [Zombie.State.CHASE, Zombie.State.ATTACK]
			# legs blown off: dead or alive (explosive damage, see the top)
			if standing and randf() < float(cfg["crawl_chance"]):
				z.become_crawler()
				res["crawlers"] += 1
			if randf() < float(cfg["gib_chance"]):
				z.lose_arm(["left", "right"].pick_random())
				res["gibs"] += 1
			if dies and d < float(cfg["kill_radius"]) and randf() < float(cfg["head_chance"]):
				z.lose_head()
				res["gibs"] += 1
		z.take_damage(dmg, false, by)
		if z.state == Zombie.State.DEAD:
			res["killed"] += 1
	# the player's own explosives
	if by != null and is_instance_valid(by) and not by.dead:
		var pc := by.global_position + Vector3.UP * 0.9
		var pd := pos.distance_to(pc)
		var pr := float(cfg["player_radius"])
		if pd < pr:
			if _visible(space, eye, [pc, pc + Vector3.UP * 0.6], by):
				var hurt := float(cfg["player_damage"]) * (1.0 - pd / pr * 0.7)
				res["player"] = hurt
				by.take_hit(hurt)
		var sr := float(cfg.get("shake_radius", 10.0))
		var dist := pos.distance_to(by.global_position)
		if dist < sr:
			WeaponFx.shake(by, float(cfg.get("shake", 1.0)) * (1.0 - dist / sr))
	return res


# Line of sight from the blast to any of the points (world geometry only; the
# player's own capsule is on the world layer and must not block).
static func _visible(space: PhysicsDirectSpaceState3D, from: Vector3, points: Array, by: Player) -> bool:
	for pt in points:
		var q := PhysicsRayQueryParameters3D.create(from, pt, 1)
		if by != null and is_instance_valid(by):
			q.exclude = [by.get_rid()]
		if space.intersect_ray(q).is_empty():
			return true
	return false


# Scale the RAYGUN fractions by the gun's damage.
static func raygun_cfg(damage: float) -> Dictionary:
	var c := RAYGUN.duplicate()
	c["max_damage"] = damage * float(RAYGUN["max_damage"])
	c["min_damage"] = damage * float(RAYGUN["min_damage"])
	return c


# ------------------------------------------------------------------ visuals

# Frag grenade: fireballs, embers, flying dirt, a lingering smoke cloud and a flash.
static func frag_effect(parent: Node, pos: Vector3) -> void:
	var c := pos + Vector3.UP * 0.4
	WeaponFx.flash(parent, c + Vector3.UP * 0.4, Color(1.0, 0.62, 0.3), 12.0, 10.0, 0.45)
	WeaponFx.burst(parent, c, "c03be099", {"amount": 5, "lifetime": 0.55, "size": 1.3, "grow": 2.4,
		"speed": 1.6, "sphere": 0.3})
	WeaponFx.burst(parent, c + Vector3.UP * 0.3, "a42e102d", {"amount": 4, "lifetime": 0.7, "size": 1.1, "grow": 2.0,
		"speed": 2.2, "dir": Vector3.UP, "spread": 60.0, "sphere": 0.4})
	WeaponFx.burst(parent, c, "623a30c5", {"amount": 2, "lifetime": 0.45, "size": 2.0, "grow": 2.0, "speed": 0.5})
	WeaponFx.burst(parent, c, "1d980a04", {"amount": 24, "lifetime": 0.9, "size": 0.12, "grow": 0.5,
		"speed": 9.0, "dir": Vector3.UP, "spread": 80.0, "gravity": Vector3(0, -9.8, 0), "rotate": false})
	WeaponFx.burst(parent, pos + Vector3.UP * 0.1, "a03e6a9a", {"amount": 16, "lifetime": 1.3, "size": 0.12,
		"speed": 7.0, "dir": Vector3.UP, "spread": 65.0, "gravity": Vector3(0, -12, 0), "additive": false,
		"color": Color(0.55, 0.45, 0.35)})
	WeaponFx.burst(parent, c + Vector3.UP * 0.3, "81d92923", {"amount": 9, "lifetime": 3.2, "size": 1.4, "grow": 3.0,
		"speed": 1.1, "dir": Vector3.UP, "spread": 70.0, "gravity": Vector3(0, 0.25, 0), "damping": 0.4,
		"additive": false, "color": Color(0.85, 0.82, 0.78, 0.7), "fade_in": 0.15, "explosiveness": 0.8})


# Ray Gun impact: green burst, glow cloud and sparks (red for Porter's X2).
static func raygun_effect(parent: Node, pos: Vector3, upgraded := false) -> void:
	var col := Color(1.0, 0.35, 0.3) if upgraded else Color(0.45, 1.0, 0.4)
	WeaponFx.flash(parent, pos, col, 6.0, 4.5, 0.35)
	WeaponFx.pop(parent, pos, "b81905e3", 0.5, 4.0, 0.3, col)
	WeaponFx.burst(parent, pos, "a85c021b", {"amount": 4, "lifetime": 0.6, "size": 0.5, "grow": 2.6,
		"speed": 0.8, "color": col})
	WeaponFx.burst(parent, pos, "aca98856", {"amount": 14, "lifetime": 0.4, "size": 0.14, "grow": 0.4,
		"speed": 5.0, "color": col, "gravity": Vector3(0, -4, 0), "rotate": false})
