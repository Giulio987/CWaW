# Thrown grenade (World at War frag behaviour; the original model is a stick grenade): bounces, explodes when the fuse (started when
# the pin was pulled, so cooking shortens it) runs out. Model: "grenade1"
# (c53574cc) from the player group.
class_name Grenade
extends RigidBody3D

const FUSE := 3.0
const MODEL_NODE := "c53574cc"   # iw_hash("grenade1")

static var _template: Node3D
static var last_result := {}   # for tests


# frees the model template (game exit)
static func release_cache() -> void:
	if _template:
		_template.free()
		_template = null

var by: Player
var fuse := FUSE
var _exploded := false
var in_hand := false   # cooked too long: goes off in the player's hand (explosion.gd FRAG)
var _last_bounce := 0.0


static func model() -> Node3D:
	if _template == null:
		var scene := load("res://assets/models/ingame/player.glb") as PackedScene
		if scene:
			var root := scene.instantiate()
			var n := root.find_child(MODEL_NODE, true, false) as Node3D
			if n:
				_template = n.duplicate() as Node3D
				_template.transform = Transform3D(n.global_transform.basis if n.is_inside_tree() else n.transform.basis, Vector3.ZERO)
			root.free()
	if _template == null:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.04
		s.height = 0.09
		mi.mesh = s
		return mi
	var m := _template.duplicate() as Node3D
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if m is MeshInstance3D:
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func spawn(parent: Node, pos: Vector3, vel: Vector3, fuse_left: float, player: Player) -> Grenade:
	var g := Grenade.new()
	g.by = player
	g.fuse = fuse_left
	parent.add_child(g)
	g.global_position = pos
	g.linear_velocity = vel
	g.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-4, 4), randf_range(-10, 10))
	return g


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2   # world and zombies (it bounces off them)
	mass = 0.4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	linear_damp = 0.15
	angular_damp = 1.5
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.3
	mat.friction = 0.8
	physics_material_override = mat
	# stick grenade (Stielhandgranate), 30 cm along +Y from the pivot near the head
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.035
	cap.height = 0.3
	shape.shape = cap
	shape.position.y = 0.09
	add_child(shape)
	add_child(model())
	body_entered.connect(_on_bounce)


func _on_bounce(_b: Node) -> void:
	if linear_velocity.length() > 2.0 and _last_bounce <= 0.0:
		_last_bounce = 0.25
		Sfx.instance.play_at("shotgun_shell_01", global_position, -8.0)


func _physics_process(delta: float) -> void:
	_last_bounce -= delta
	fuse -= delta
	if fuse <= 0.0 and not _exploded:
		explode()


func explode() -> void:
	_exploded = true
	var game := get_parent() as Node3D
	var pos := global_position + Vector3.UP * 0.05
	var res := Explosion.blast(game, pos, by, Explosion.FRAG)
	if in_hand and by != null and is_instance_valid(by) and not by.dead:
		res["player"] = maxf(by.health, 1.0)
		by.take_hit(res["player"])
	last_result = res
	Explosion.frag_effect(game, pos)
	Sfx.instance.play_at("grenade_explosion", pos, 4.0)
	if OS.get_cmdline_user_args().has("--grenade-log"):
		print("[grenade] exploded at %s: %s" % [pos.snapped(Vector3(0.01, 0.01, 0.01)), res])
	queue_free()
