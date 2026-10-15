# Planted Bouncing Betty (S-mine). Original data:
#   CItemBetty "betty" (player group): in-hand model 88149b6a (skinned, with the pin
#     animations fae9e306 / 8a758615 / 8a7361c3), world spec list 7b8c2195 (CIwSpecList)
#   world entity (7b8c2195): CIwRenderableModelSpec 881a509f (static betty),
#     CIwColliderSpec + CIwVolumeCylinder radius 300 units, HEIGHT 0, base (0,60,0) (serializer
#     0x1286ec): a flat disc 60 units above the betty's origin (which is 55 units underground,
#     so ~1.25 cm above the floor); CTriggerVolumeSpec with target mask 0x4000 (zombies and dogs; the splash uses the same mask, so the
#     player neither triggers it nor is hurt), CActionBettySpec {0x14 = 1840, 0x18 = 640,
#     0x1c = sound 106207e0}
#   CActionBetty (kiwi code 0xc2634: triggered -> plays spec 0x1c at the betty and starts
#     bouncing; 0xc253c update: the entity rises by 0x14 * dt units per second until it
#     has gone up 0x18 units, then it goes off) -> 1840 units/s = 4.6 m/s up to 640 units
#     = 1.6 m (0.35 s), then the CSplashEffectSpec "betty_explosion" 8e5dac4d: 1000 damage
#     to everything within 1700 units = 4.25 m, line of sight beyond 2.4 m, damage type 2
#     (explosive: legs off, explosion.gd)
#   BettyPlantedDepth -55 units (kiwi 0x1aa400 default): planted 0.1375 m into the ground
#   cylinder-cylinder test (kiwi 0x1ca348): the radii add up and the zombie / dog cylinder is
#     r 180 h 750 units -> it fires when the horizontal centre distance is < 480 units (1.2 m)
#     and the zombie's feet are between disc_y - 750 units (1.875 m) and disc_y
#   MaxBettiesInWorld default 0x20: the CActionBetty pool is sized for 32 betties (kiwi
#     0x12b67c); with 32 in the world planting fails and the betty stays in the belt (that
#     last part is our choice: the pooled create just has no free slot)
# No arming delay (confirmed): the trigger volume is live as soon as the betty is planted.
class_name Betty
extends Node3D

const PLANTED_MODEL := "881a509f"       # CIwRenderableModelSpec of the betty entity
const HAND_MODEL := "res://assets/characters/ingame/player/88149b6a.glb"   # CItemBetty model
const TRIGGER_RADIUS := 1.2             # CIwVolumeCylinder r 300 + zombie/dog cylinder r 180 units
const TRIGGER_DISC_Y := 0.15            # disc base (0,60,0) above the betty origin (60 units)
const TRIGGER_DEPTH := 1.875            # zombie/dog cylinder height 750 units: feet down to this below the disc
const MAX_IN_WORLD := 32                # MaxBettiesInWorld default 0x20
const RISE_SPEED := 4.6                 # CActionBettySpec 0x14 = 1840 units/s
const RISE_HEIGHT := 1.6                # CActionBettySpec 0x18 = 640 units
const PLANTED_DEPTH := 0.1375           # BettyPlantedDepth -55
const TRIGGER_SOUND := "106207e0"       # CActionBettySpec 0x1c
const EXPLOSION_SOUND := "8e5dac4d"     # betty_explosion
# splash "betty_explosion" (tools/weapon_stats.py splash_effects): flat 1000, no falloff
const BLAST := {
	"radius": 4.25, "max_damage": 1000.0, "min_damage": 1000.0, "kill_radius": 0.0, "los_free": 2.4,
	"crawl_chance": 1.0, "gib_chance": 0.0, "head_chance": 0.0,
	"player_radius": 0.0, "player_damage": 0.0, "shake": 1.0, "shake_radius": 14.0,
}
const ACH_TWO_AT_ONCE := "ffa0ab45"     # "This is for you, Betty!": 2 zombies with one betty

static var _template: Node3D
static var last_result := {}            # tests

var by: Player
var triggered := false
var exploded := false
var _exploded := false   # read by achievements.gd _cause (group ach_blasts) during the blast
var _risen := 0.0
var _ground := Vector3.ZERO


static func release_cache() -> void:
	if _template:
		_template.free()
		_template = null


# The static betty model (planted / mystery box).
static func planted_model() -> Node3D:
	if _template == null:
		var scene := load("res://assets/models/ingame/player.glb") as PackedScene
		if scene:
			var root := scene.instantiate()
			var n := root.find_child(PLANTED_MODEL, true, false) as Node3D
			if n:
				_template = n.duplicate() as Node3D
				_template.transform = Transform3D(n.transform.basis, Vector3.ZERO)
			root.free()
	if _template == null:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.06
		c.bottom_radius = 0.06
		c.height = 0.25
		mi.mesh = c
		return mi
	return _template.duplicate() as Node3D


# The in-hand model with its skeleton (pin animations), also shown by the mystery box.
static func model() -> Node3D:
	if not ResourceLoader.exists(HAND_MODEL):
		return planted_model()
	var m := (load(HAND_MODEL) as PackedScene).instantiate() as Node3D
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# Plants a betty on the ground below `at` (null when there is no floor there).
static func plant(game: Node3D, at: Vector3, yaw: float, player: Player) -> Betty:
	var space := game.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 2.5, 1)
	if player:
		q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	if game.get_tree().get_nodes_in_group("betties").size() >= MAX_IN_WORLD:
		return null
	var b := Betty.new()
	b.by = player
	game.add_child(b)
	b._ground = hit["position"]
	b.global_position = b._ground + Vector3.DOWN * PLANTED_DEPTH
	b.rotation.y = yaw
	return b


func _ready() -> void:
	add_to_group("betties")
	add_to_group("ach_blasts")
	var m := planted_model()
	add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false) + ([m] if m is MeshInstance3D else []):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	if exploded:
		return
	if not triggered:
		if _zombie_in_volume():
			trigger()
		return
	# CActionBetty update: straight up at 0x14 units/s until 0x18 units, then the splash
	var step := minf(RISE_SPEED * delta, RISE_HEIGHT - _risen)
	_risen += step
	global_position.y += step
	rotation.y += delta * 12.0
	if _risen >= RISE_HEIGHT - 0.0001:
		explode()


func _zombie_in_volume() -> bool:
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z.state == Zombie.State.DEAD:
			continue
		# flat disc at origin + 60 units; the zombie cylinder (feet up 750 units) must cross it
		var d: Vector3 = z.global_position - (global_position + Vector3.UP * TRIGGER_DISC_Y)
		if Vector2(d.x, d.z).length() < TRIGGER_RADIUS and d.y <= 0.0 and d.y >= -TRIGGER_DEPTH:
			return true
	return false


func trigger() -> void:
	if triggered:
		return
	triggered = true
	Sfx.instance.play_at(TRIGGER_SOUND, global_position + Vector3.UP * 0.2)


func explode() -> void:
	if exploded:
		return
	exploded = true
	_exploded = true
	var game := get_parent() as Node3D
	var pos := global_position
	var res := Explosion.blast(game, pos, by, BLAST)
	last_result = res
	HitFx.play(game, Transform3D(Basis.IDENTITY, pos), HitFx.EXPLOSION)   # splash entity 8e5dac4d: spec list ee72b935 (hit_fx.gd)
	Sfx.instance.play_at(EXPLOSION_SOUND, pos, 4.0)
	if int(res.get("killed", 0)) >= 2:
		Achievements.unlock(ACH_TWO_AT_ONCE)
	if OS.get_cmdline_user_args().has("--betty-log"):
		print("[betty] exploded at %s: %s" % [pos.snapped(Vector3(0.01, 0.01, 0.01)), res])
	queue_free()
