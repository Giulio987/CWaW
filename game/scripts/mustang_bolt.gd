# Mustang & Sally (colt45_upgrade): the original CItemGun fires the projectile ede95410
# instead of a bullet (player group): its CProjectileSpec is the Ray Gun's (same speed),
# spec list eba1a798 = collider sphere 50 units, CLifeTimeSpec 6000 ms and the model
# 7d6f6707 (a 3 cm round); when it dies it spawns ab7c47a0 (CDeathActionSpawnSpec): a
# CSplashEffectSpec of 1000 damage, type 2 (explosive: legs off), target mask 0x4000 (as
# the betty's: zombies and dogs, not the player), line of sight from 960 units, on the
# betty's spec list ee72b935 (sphere 1700 units = 4.25 m, and the explosion emitters:
# smoke 34c2dd63, fireball bce537be, sparks 623a30c5 -> HitFx). Sound 8e5dac4d
# (betty_explosion, the splash's sound field). The projectile carries no damage of its
# own: the zombie hit takes the splash like the others.
class_name MustangBolt
extends RaygunBolt

const MODEL := "7d6f6707"
const LIFETIME := 6.0
const EXPLOSION := "ee72b935"
const SOUND := "8e5dac4d"
const SPLASH := {
	"radius": 4.25, "max_damage": 1000.0, "min_damage": 1000.0, "kill_radius": 0.0, "los_free": 2.4,
	"crawl_chance": 1.0, "gib_chance": 0.0, "head_chance": 0.0,
	"player_radius": 0.0, "player_damage": 0.0, "shake": 1.0, "shake_radius": 14.0,
}

static var _template: Node3D
static var last_result := {}


static func release_cache() -> void:
	if _template:
		_template.free()
		_template = null


func _build() -> void:
	max_range = SPEED * LIFETIME
	if _template == null:
		var scene := load("res://assets/models/ingame/player.glb") as PackedScene
		if scene:
			var root := scene.instantiate()
			var n := root.find_child(MODEL, true, false) as Node3D
			if n:
				_template = n.duplicate() as Node3D
				_template.transform = Transform3D(n.transform.basis, Vector3.ZERO)
			root.free()
	var glow := Node3D.new()   # RaygunBolt moves "Glow" from the muzzle onto the aim line
	glow.name = "Glow"
	add_child(glow)
	if _template:
		var m := _template.duplicate() as Node3D
		glow.add_child(m)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if absf(_dir.y) < 0.99:
		glow.look_at(glow.global_position + _dir, Vector3.UP)


func _impact(hit: Dictionary) -> void:
	_done = true
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var game := get_parent() as Node3D
	var at := pos + normal * 0.1
	last_result = Explosion.blast(game, at, player, SPLASH)
	HitFx.play(game, Transform3D(Basis.IDENTITY, at), EXPLOSION)
	Sfx.instance.play_at(SOUND, at, 4.0)
	if OS.get_cmdline_user_args().has("--mustang-log"):
		print("[mustang] exploded at %s: %s" % [at.snapped(Vector3.ONE * 0.01), last_result])
	queue_free()
