# Invisible walls and ceilings of the original levels: entities made only of a
# CIwColliderSpec box and a CFlagsSpec (Nacht 9, Verrückt 39, Shi No Numa 9, Der Riese 55;
# tools/entities.py "colliders"). Their CFlags set 0x08000000, the flag of the shootable
# easter-egg triggers (Der Riese flytrap: CTargetSpec + CTriggerDamageSpec): CEnt's message
# handler (kiwi 0x1f7f94) absorbs a hit from the player for an entity with that flag, and
# the weapon query (kiwi 0x1491cc) looks for 0x08000000 | 0x20000 entities. Thin slabs over
# the roofs (Verrückt 9.3 m, Der Riese 10.6 m, Nacht 7.2 m) and walls at the upper
# openings only make sense against projectiles, so they stop bullets and grenades here.
# The player, zombies and the navmesh bake ignore them: layer LAYER only, outside the
# NavigationRegion3D (its bake parses the static colliders of its children).
class_name ShotBlockers

const LAYER := 256   # layer 9: bullets (player.gd) and grenades (grenade.gd) look for it
const GROUP := "shot_blockers"
# the only collider-only entity with other flags: Der Riese c9df0b77 sets 0x10000000
# (the flag of the trap entities), not 0x08000000
const OTHER_FLAGS := ["c9df0b77"]


static func build(level: Level) -> int:
	var root := Node3D.new()
	root.name = "ShotBlockers"
	level.add_child(root)
	var n := 0
	for e in level.entities.values():
		var comps: Array = e.get("components", [])
		if comps.size() != 2 or not "CFlagsSpec" in comps or not "CIwColliderSpec" in comps:
			continue
		if e.get("hash", "") in OTHER_FLAGS:
			continue
		var xf := Level._to_transform(e["transform"])
		for col in e.get("colliders", []):
			var lo := Vector3(col["min"][0], col["min"][1], col["min"][2]) * Level.UNITS
			var hi := Vector3(col["max"][0], col["max"][1], col["max"][2]) * Level.UNITS
			var body := StaticBody3D.new()
			body.name = "Blocker_%s" % e["name"]
			body.collision_layer = LAYER
			body.collision_mask = 0
			body.add_to_group(GROUP)
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = (hi - lo).max(Vector3.ONE * 0.04)
			cs.shape = box
			body.add_child(cs)
			root.add_child(body)
			body.global_transform = xf * Transform3D(Basis.IDENTITY, (lo + hi) * 0.5)
			n += 1
	return n
