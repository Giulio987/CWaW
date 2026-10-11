# Thrown Monkey Bomb (Der Riese box item; CItemMonkey "monkeybomb", spec list 013e99e0
# in the player group). From its components: CLifeTimeSpec 9000 ms, a CSoundEmitterSpec
# playing "monkey_song" (random monkey_song1 ee3b3ebf / monkey_song2 ee3b3ec0, ~8 s),
# CMonkeyBombBehaviourSpec; from the executable's tuning: MonkeyByeSoundTime 2000 ms
# before the end one of MonkeyByeSoundNum (3) "monkey_expl_vox<n>". It lands, claps its
# cymbals (animation monkeybomb_loop) and lures the zombies around it, then explodes.
class_name MonkeyBomb
extends RigidBody3D

const ITEM := "monkey_bomb"           # mystery box / Weapons.display name
const MODEL := "res://assets/characters/ingame/player/1561c758.glb"   # iw_hash("monkeybomb")
const ANIM_LOOP := "a0d05611"         # monkeybomb_loop
const LIFETIME := 9.0                 # CLifeTimeSpec 9000
const BYE_TIME := 2.0                 # MonkeyByeSoundTime
const LURE_RADIUS := 20.0
const SONGS := ["ee3b3ebf", "ee3b3ec0"]   # monkey_song1, monkey_song2

static var last_result := {}   # for tests

var by: Player
var life := 0.0
var landed := false
var _bye := false
var _exploded := false
var _model: Node3D
var _song: AudioStreamPlayer3D
var _lure_t := 0.0
var lured := []   # zombies currently lured (tests)


static func model() -> Node3D:
	if not ResourceLoader.exists(MODEL):
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.08
		s.height = 0.16
		mi.mesh = s
		return mi
	var m := (load(MODEL) as PackedScene).instantiate() as Node3D
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func spawn(parent: Node, pos: Vector3, vel: Vector3, player: Player) -> MonkeyBomb:
	var b := MonkeyBomb.new()
	b.by = player
	parent.add_child(b)
	b.global_position = pos
	b.linear_velocity = vel
	return b


func _ready() -> void:
	add_to_group("monkey_bombs")
	collision_layer = 0
	collision_mask = 1     # world only: it rolls under the zombies' feet
	mass = 0.6
	continuous_cd = true
	linear_damp = 0.3
	angular_damp = 4.0
	lock_rotation = true   # keeps it upright for the clapping
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.15
	mat.friction = 1.0
	physics_material_override = mat
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.16, 0.24, 0.16)
	shape.shape = box
	shape.position.y = 0.12
	add_child(shape)
	_model = model()
	add_child(_model)
	_song = AudioStreamPlayer3D.new()
	_song.unit_size = 6.0
	_song.max_distance = 45.0
	add_child(_song)


func _physics_process(delta: float) -> void:
	life += delta
	if not landed and (life > 0.25 and linear_velocity.length() < 0.4 or life > 2.0):
		_land()
	if landed:
		_lure_t -= delta
		if _lure_t <= 0.0:
			_lure_t = 0.25
			_lure()
	if not _bye and life >= LIFETIME - BYE_TIME:
		_bye = true
		Sfx.instance.play_at(Sfx.iw_hash("monkey_expl_vox%d" % randi_range(1, 3)), global_position + Vector3.UP * 0.3)
	if life >= LIFETIME and not _exploded:
		explode()


func _land() -> void:
	landed = true
	linear_velocity = Vector3.ZERO
	freeze = true
	var ap := _model.find_children("*", "AnimationPlayer", true, false)
	if not ap.is_empty():
		var anim := ap[0] as AnimationPlayer
		if anim.has_animation(ANIM_LOOP):
			anim.get_animation(ANIM_LOOP).loop_mode = Animation.LOOP_LINEAR
			anim.play(ANIM_LOOP)
	var s := Sfx.instance._stream(SONGS.pick_random())
	if s:
		_song.stream = s
		_song.play()


# zombies chasing the player within LURE_RADIUS go for the monkey instead (zombie.gd lure)
func _lure() -> void:
	lured = []
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z is Dog or z.state == Zombie.State.DEAD:
			continue
		if z.global_position.distance_to(global_position) > LURE_RADIUS:
			continue
		var cur = z.get("lure")
		if cur == null or not is_instance_valid(cur) or cur == self:
			z.set("lure", self)
			lured.append(z)


func explode() -> void:
	_exploded = true
	var game := get_parent() as Node3D
	var pos := global_position + Vector3.UP * 0.1
	remove_from_group("monkey_bombs")
	for z in lured:
		if is_instance_valid(z) and z.get("lure") == self:
			z.set("lure", null)
	var res := Explosion.blast(game, pos, by, Explosion.FRAG)
	res["lured"] = lured.size()
	last_result = res
	Explosion.frag_effect(game, pos)
	Sfx.instance.play_at("grenade_explosion", pos, 4.0)
	if OS.get_cmdline_user_args().has("--grenade-log"):
		print("[monkey] exploded at %s: %s" % [pos.snapped(Vector3(0.01, 0.01, 0.01)), res])
	queue_free()
