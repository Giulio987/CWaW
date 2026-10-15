# Radial power-up waves of the original (CRadialEffect, base kiwi va 0x148ac0): a sphere
# grows from where the effect spawned at `growth` units/s (radius = growth x elapsed,
# va 0x148aec); every frame each target inside it is hit once; when the duration runs out
# a last pass hits every target left, wherever it is (Nuke va 0x18f1f0, Carpenter
# va 0x1cd6e4 call the hit pass with "no radius check"). No line-of-sight test.
# Specs (effects group, CRadialEffectSpec base Serialise va 0x18f328: 0x14 duration ms,
# 0x18 growth units/s, 0x1c stat category):
#   atomic_bomb_pickup -> 8e943e0f CRadialEffectNukeSpec (Serialise va 0x1c67ec):
#       5000 ms, 6000 u/s (15 m/s, 75 m), category "nuke", 0x3c attach key 4ff66055
#       "flamethrower", 0x40 points 400, 0x44 kill threshold 4
#   game over (CVar GameOverNukeEffect = "nuke_gameover", kiwi va 0x1b3018: spawned at the
#       player's position) -> b616900d: 8000 ms, 2000 u/s (5 m/s, 40 m), no category,
#       no attach key, 0 points, threshold -1
#   carpenter_pickup -> 91896b15 CRadialEffectCarpenterSpec (Serialise va 0x1e35c0):
#       5000 ms, 6000 u/s, 0x3c points 200
# Nuke hit (va 0x18f0d8): every live zombie / dog (game enemy list) whose position is
# inside the sphere is killed outright (va 0x20cfac: damage = its health, no attacker:
# no kill points) and, with an attach key, gets the zombie's CAttachEffectSpec entry for
# it (zombiesbase c9872545: "flamethrower" -> flames on the body, Burning with no damage).
# At the end, more kills than the threshold -> the points to the player (va 0x131b44,
# doubled by Double Points): the pickup's 400 only for 5 kills or more.
# Carpenter hit (va 0x1cd72c): every barricade (game barricade list) inside the sphere is
# visited once; one with boards missing gets "repairAll" (barricade.gd carpenter_repair);
# at the end, if any was repaired, 200 points (va 0x1cd6e4).
# The atomic bomb pickup also spawns c11b0e78 at the same point (CActionPickupSpawnSpec
# list, va 0x195d84): a CIwGFXEmitterSpec of fireball sprites (texture c03be099, additive):
# emission 1200 ms, one every 75-100 ms, life 700-1000 ms, box +-50 x 0..150 x +-50 units,
# velocity +-1000 / 2500..3500 / +-1000 (fixed), size 400-500 units, growth 1500, spin +-4096.
class_name RadialEffect
extends Node3D

const U := 1.0 / 400.0   # Level.UNITS
const SPECS := {
	"nuke": {"duration": 5.0, "growth": 6000.0 * U, "fire": true, "points": 400, "threshold": 4},
	"nuke_gameover": {"duration": 8.0, "growth": 2000.0 * U, "fire": false, "points": 0, "threshold": -1},
	"carpenter": {"duration": 5.0, "growth": 6000.0 * U, "points": 200},
}
# c11b0e78 (see above), IwEmitter.from_spec fields; spin +-4096 read like the barrel sparks
const NUKE_FIREBALL := ["c03be099", true, 1200.0, [75.0, 100.0], [700.0, 1000.0],
	[Vector3(-50, 0, -50), Vector3(50, 150, 50)], [Vector3(-1000, 2500, -1000), Vector3(1000, 3500, 1000)],
	[400.0, 500.0], 1500.0, [-88.0, 88.0]]

var kind := ""
var game: Game
var radius := 0.0
var kills := 0
var _spec := {}
var _t := 0.0
var _visited := {}      # carpenter: barricades already reached
var _repaired := false

static var last: RadialEffect   # for tests


# The power-up's effects at `at`: the radial wave and, for the atomic bomb, the fireball.
static func spawn(g: Game, kind_: String, at: Vector3) -> RadialEffect:
	var e := RadialEffect.new()
	e.kind = kind_
	e.game = g
	e._spec = SPECS[kind_]
	g.add_child(e)
	e.global_position = at
	if kind_ == "nuke":
		var f: Array = NUKE_FIREBALL
		IwEmitter.burst(g, Transform3D(Basis.IDENTITY, at),
			IwEmitter.from_spec(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9]))
	if kind_ != "carpenter":
		g._nuking = true   # no drops from the wave's kills (game.gd)
	last = e
	return e


func _physics_process(delta: float) -> void:
	var final := _t >= float(_spec["duration"])
	if kind == "carpenter":
		_carpenter_pass(final)
	else:
		_nuke_pass(final)
	if final:
		_finish()
		return
	_t += delta
	radius = float(_spec["growth"]) * minf(_t, float(_spec["duration"]))


func _inside(p: Vector3, final: bool) -> bool:
	return final or global_position.distance_squared_to(p) < radius * radius


func _nuke_pass(final: bool) -> void:
	for n in game.get_children():
		var z := n as Zombie   # dogs too (Dog extends Zombie)
		if z == null or z.state == Zombie.State.DEAD or not _inside(z.global_position, final):
			continue
		game.kill_without_points(z)
		kills += 1
		if _spec["fire"]:
			Burning.ignite(z, null, 0.0, 0.0)   # "flamethrower" attach: flames only


func _carpenter_pass(final: bool) -> void:
	for w: Barricade in game.level.windows:
		if _visited.has(w) or not _inside(w.global_position, final):
			continue
		_visited[w] = true
		if w.carpenter_repair():
			_repaired = true


func _finish() -> void:
	var pts := 0
	if kind == "carpenter":
		pts = int(_spec["points"]) if _repaired else 0
	elif kills > int(_spec["threshold"]):
		pts = int(_spec["points"])
	if pts > 0 and game.player and not game.player.dead:
		game.player.add_points(pts * game.points_multiplier)
	if kind != "carpenter":
		game._nuking = false
	set_physics_process(false)
	queue_free()
