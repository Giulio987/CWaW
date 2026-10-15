# Thrown Molotov cocktail (mystery box item "molotov", MolotovBelt).
# Original data (player group CItemMolotov "molotov", effects group):
#   - CItemMolotov: in-hand model c262600f (skinned, animation 0f6787cc), item model fa94ee6a,
#     projectile entity specs 94e126c5 (local player) / 642d3230 (the other players' copy:
#     only the sound entity 6c4fb520), base CIwSpecList 41e4bcad
#   - 41e4bcad: collider sphere 50 units, CIwRenderableModelSpec c3e1f4c9 (the bottle),
#     CProjectileSpec with the frag grenade's speed/gravity fields but no bounce (grenade
#     0x666 restitution, molotov 0) and no CLifeTimeSpec: it breaks at the first contact;
#     a child CIwGFXEmitterSpec = the burning rag in flight
#   - on death CDeathActionSpawnSpec spawns 6aba17b5: CSplashEffectSpec 250 damage, damage
#     type 5 (fire, like the flamethrower), target mask 0x10000 (zombies and dogs, never the
#     player), line of sight only checked beyond 960 units = 2.4 m, radius = the 1200-unit
#     (3 m) sphere of its base 4a073f9d; attach key 4ff66055 = "flamethrower": every target
#     gets the zombie's CAttachEffectSpec entry "zombieonfires" (effect b85a2b48, flames on
#     the body, no lifetime and no damage of its own: the flamethrower's afterburn is the
#     gun's CPeriodicDamage, the molotov has none). Stat "killed", weapon "molotov".
#   - 4a073f9d also carries three CRenderableEffectEmitterSpecs: the fireball 175d4fc7
#     (~1.5 s), a short flash of it (0.3 s) and the flame sheet 0f74ae25 (~1 s): the fire
#     on the ground; sound molotov_explosion (6aba17b5).
# Throw speed: same CProjectileSpec speed as the frag grenade, so GrenadeBelt's throw.
class_name Molotov
extends RigidBody3D

const PROJECTILE_MODEL := "c3e1f4c9"   # CIwRenderableModelSpec of 41e4bcad
const BOX_MODEL := "fa94ee6a"          # CItemMolotov item model (mystery box display)
const HAND_MODEL := "res://assets/characters/ingame/player/c262600f.glb"   # skinned, anim 0f6787cc
const HAND_ANIM := "0f6787cc"
# splash 6aba17b5 (Explosion.blast config: flat 250 inside 3 m, fire: no legs off)
const SPLASH := {
	"radius": 3.0, "max_damage": 250.0, "min_damage": 250.0, "kill_radius": 0.0, "los_free": 2.4, "damage_type": 5,
	"crawl_chance": 0.0, "gib_chance": 0.0, "head_chance": 0.0,
	"player_radius": 0.0, "player_damage": 0.0, "shake": 0.4, "shake_radius": 8.0,
}
const BURN_TIME := 3600.0   # zombieonfires stays until the zombie dies (no lifetime)
const FIRE_TIME := 2.0      # ground flames (emitters ~1-1.5 s plus particle life): estimated
const MAX_FLIGHT := 8.0

static var _templates := {}
static var last_result := {}   # for tests

var by: Player
var _done := false
var _age := 0.0


static func release_cache() -> void:
	for k in _templates:
		if _templates[k]:
			(_templates[k] as Node).free()
	_templates.clear()


# A static model of the player group (player.glb) by hash.
static func model(h := PROJECTILE_MODEL) -> Node3D:
	if not _templates.has(h):
		_templates[h] = null
		var scene := load("res://assets/models/ingame/player.glb") as PackedScene
		if scene:
			var root := scene.instantiate()
			var n := root.find_child(h, true, false) as Node3D
			if n:
				var t := n.duplicate() as Node3D
				t.transform = Transform3D(n.transform.basis, Vector3.ZERO)
				_templates[h] = t
			root.free()
	if _templates[h] == null:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.02
		c.bottom_radius = 0.04
		c.height = 0.2
		mi.mesh = c
		return mi
	var m := (_templates[h] as Node3D).duplicate() as Node3D
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if m is MeshInstance3D:
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# The skinned molotov held by the arms (Lightingmolotov plays its 0f6787cc).
static func hand_model() -> Node3D:
	if not ResourceLoader.exists(HAND_MODEL):
		return model()
	var m := (load(HAND_MODEL) as PackedScene).instantiate() as Node3D
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# Small flame for the rag (in hand and in flight: the child CIwGFXEmitterSpec of 41e4bcad).
static func rag_flame() -> Node3D:
	var root := Node3D.new()
	root.name = "RagFlame"
	var p := WeaponFx.particles("0f74ae25", {"amount": 10, "lifetime": 0.35, "size": 0.09, "grow": 1.4,
		"speed": 0.25, "dir": Vector3.UP, "spread": 15.0, "gravity": Vector3(0, 0.8, 0), "one_shot": false,
		"frames": Vector2i(8, 4), "sphere": 0.012, "rotate": false, "local": false})
	p.emitting = true
	root.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 0.8
	l.omni_range = 1.6
	root.add_child(l)
	return root


static func spawn(parent: Node, pos: Vector3, vel: Vector3, player: Player) -> Molotov:
	var m := Molotov.new()
	m.by = player
	parent.add_child(m)
	m.global_position = pos
	m.linear_velocity = vel
	m.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8))
	return m


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2   # world and zombies
	mass = 0.5
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	linear_damp = 0.1
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 50.0 / 400.0 * 0.6   # 50-unit sphere, a little smaller so it clears door frames
	shape.shape = s
	add_child(shape)
	add_child(model())
	var f := rag_flame()
	f.position = Vector3(0, 0.12, 0)
	add_child(f)
	body_entered.connect(func(_b): shatter())


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > MAX_FLIGHT and not _done:
		shatter()


# The bottle breaks: splash 6aba17b5 at the impact point.
func shatter() -> void:
	if _done:
		return
	_done = true
	var game := get_parent() as Node3D
	var pos := global_position
	# fire sits on the floor below the impact (hitting a wall or a zombie)
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, pos + Vector3.DOWN * 2.5, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ground: Vector3 = hit["position"] if not hit.is_empty() else pos
	last_result = burn_area(game, pos, by)
	fire_effect(game, ground)
	Sfx.instance.play_at("molotov_explosion", pos, 2.0)
	if OS.get_cmdline_user_args().has("--grenade-log"):
		print("[molotov] broke at %s: %s" % [pos.snapped(Vector3(0.01, 0.01, 0.01)), last_result])
	queue_free()


# Damage (Explosion.blast with the splash values) and the zombieonfires effect on every
# zombie/dog the splash reached (also the ones it killed: their corpses burn a little).
static func burn_area(game: Node3D, pos: Vector3, player: Player) -> Dictionary:
	if game == null or not game.is_inside_tree():
		return {}
	var targets := []
	var space := game.get_world_3d().direct_space_state
	var eye := pos + Vector3.UP * 0.5
	for n in game.get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z.state == Zombie.State.DEAD:
			continue
		var feet := z.global_position
		var top := feet + Vector3.UP * (0.6 if z.crawler else 1.6)
		var d := pos.distance_to(Geometry3D.get_closest_point_to_segment(pos, feet + Vector3.UP * 0.15, top))
		if d > float(SPLASH["radius"]):
			continue
		if d > float(SPLASH["los_free"]) and not Explosion._visible(space, eye, [(feet + top) * 0.5, top], player):
			continue
		targets.append(z)
	var res := Explosion.blast(game, pos, player, SPLASH)
	res["burning"] = 0
	for z in targets:
		if not is_instance_valid(z):
			continue
		res["burning"] += 1
		if z.get_node_or_null("Burning") == null:   # already burning (flamethrower): keep its afterburn
			Burning.ignite(z, player, 0.0, BURN_TIME, 0.0)   # visual only (zombieonfires)
	return res


# Fireball and flames on the ground (4a073f9d's emitters), a flash of light.
static func fire_effect(parent: Node, ground: Vector3) -> void:
	var c := ground + Vector3.UP * 0.3
	WeaponFx.flash(parent, c + Vector3.UP * 0.5, Color(1.0, 0.55, 0.2), 6.0, 8.0, FIRE_TIME)
	WeaponFx.burst(parent, c, "175d4fc7", {"amount": 6, "lifetime": 0.9, "size": 1.0, "grow": 2.2,
		"speed": 1.2, "dir": Vector3.UP, "spread": 70.0, "sphere": 0.4, "gravity": Vector3(0, 1.0, 0)})
	WeaponFx.burst(parent, c, "175d4fc7", {"amount": 2, "lifetime": 0.3, "size": 2.0, "grow": 1.5, "speed": 0.2})
	# flames spread over the ground for a while
	var flames := WeaponFx.particles("0f74ae25", {"amount": 40, "lifetime": 0.7, "size": 0.6, "grow": 1.3,
		"speed": 0.5, "dir": Vector3.UP, "spread": 15.0, "gravity": Vector3(0, 1.5, 0), "one_shot": false,
		"frames": Vector2i(8, 4), "box": Vector3(1.1, 0.05, 1.1), "rotate": false})
	parent.add_child(flames)
	flames.global_position = ground + Vector3.UP * 0.25
	flames.emitting = true
	var tree := parent.get_tree()
	tree.create_timer(FIRE_TIME, false).timeout.connect(func():
		if is_instance_valid(flames):
			flames.emitting = false)
	tree.create_timer(FIRE_TIME + 1.0, false).timeout.connect(func():
		if is_instance_valid(flames):
			flames.queue_free())
	WeaponFx.burst(parent, c + Vector3.UP * 0.4, "81d92923", {"amount": 5, "lifetime": 2.5, "size": 1.0, "grow": 2.5,
		"speed": 0.8, "dir": Vector3.UP, "spread": 40.0, "gravity": Vector3(0, 0.4, 0), "additive": false,
		"color": Color(0.25, 0.22, 0.2, 0.6), "fade_in": 0.2, "explosiveness": 0.5})
