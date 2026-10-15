# Hellhound (dog rounds on Shi No Numa and Der Riese, waves.lua StartDogWave):
# appears in a lightning strike, runs straight at the player, bites, dies.
# It extends Zombie so bullets, the knife, nukes and traps that look for
# Zombie nodes hit dogs too; everything else is its own.
# Animations (characters/ingame/dogs, model faces +Z, root motion is in the
# root bone so the loops are in place), identified from contact sheets
# (game/tools/dogsheet.gd):
#   run 0b0e1cce / 6d4c918e (gallop loops), bite fe591198, leap 69acb481,
#   deaths 773dd671 8c7140e3 8c7140e4 41af9c33 7811ea46, idle 90866617.
# Flame dogs (ingame.lua SpawnDog: RandomNumber(1, 100, RAND_DOG_TYPE) < 50 spawns
# "flame_dogSpawn" instead of "normal_dogSpawn"): the flame_dog entity of the dogs
# group adds a "dog_fire" CRenderableEffectEmitterSpec (material 175d4fc7) attached to
# the spine bone ba089bde, and a CDeathActionSpawnSpec that spawns effects entity
# 509bce00 when it dies: fireball (bce537be), embers (623a30c5) and smoke (34c2dd63)
# emitters. That entity has no CSplashEffectSpec, so the burst does not hurt anyone.
class_name Dog
extends Zombie

const DOG_MODEL := "res://assets/characters/ingame/dogs/1d22586d.glb"
const DOG_RUNS := ["0b0e1cce", "6d4c918e"]
const DOG_BITE := "fe591198"
const DOG_IDLE := "90866617"
const DOG_DEATHS := ["773dd671", "8c7140e3", "8c7140e4", "41af9c33", "7811ea46"]
# Speeds from the dog's CIsAnimStateMachine "dog" (same layout as the zombie's): movement
# state 7 (speed 1, DogWalkTrigger) c97dad92 at rate 1.0, state 8 (speed 2, DogRunsTrigger)
# fe591198 at rate 0.7; ground speed = their root-motion partners (707d4778: 5.80 m in
# 4.50 s, 81ab28be: 6.37 m in 1.00 s) x rate. DogRunRadius 12000 units = 30 m: farther
# than that from the player a dog walks, nearer it runs. The gallop loops below are kept
# for the look; the run speed is the original one.
const DOG_SPEED := 6.37 * 0.7      # 4.46 m/s
const DOG_WALK_SPEED := 5.8 / 4.5  # 1.29 m/s
const DOG_WALK := "c97dad92"
const DOG_RUN_RADIUS := 12000.0 / 400.0
# DogTurnSpeedRangeMove {30000,30000}, DogTurnSpeedRangeRender {10000,10000}
# (4096 = 360 degrees per second): the walking direction turns almost at once, the body
# at 879 degrees per second.
const DOG_TURN_MOVE := 30000.0 * TAU / 4096.0
const DOG_TURN_RENDER := 10000.0 * TAU / 4096.0
const DOG_RANGE := 1.35      # bite reach (m)
# dog.group.bin CIwSpecList 1d1ca339: CAIControllerSpec -> CAttackSpec damage 7 (of the
# player's 20, reach 1300 units), same path as the zombie (kiwi 0xe9d78 -> 0x19c4c8):
# three bites down a player without Juggernog. x HEALTH_SCALE for the remake.
const DOG_DAMAGE := 7.0 * Player.HEALTH_SCALE
const DOG_BITE_TIME := 0.9

const FLAME_BONE := "ba089bde"
const FLAME_TEX := "175d4fc7"

var untracked := false       # teleporter dogs (Der Riese): not part of a dog round
var flame := false           # flame_dog (set before adding it to the tree)
var _fire: CPUParticles3D
var _fire_light: OmniLight3D
var _d_agent: NavigationAgent3D
var _d_anim: AnimationPlayer
var _d_model: Node3D
var _d_run := ""
var _d_timer := 0.0
var _d_bit := false
var _d_repath := 0.0
var _d_attacking := false


func setup_dog(spawn: Vector3, player: Player, hp: float, any_window: Barricade) -> void:
	target = player
	health = hp
	window = any_window   # unused by dogs; Zombie code paths expect one
	position = spawn
	state = State.CHASE


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 2
	collision_mask = 1 | 4 | Level.NAV_FLOOR_LAYER
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 0.95
	shape.shape = cap
	shape.position.y = 0.5
	add_child(shape)
	_d_model = (load(DOG_MODEL) as PackedScene).instantiate()
	add_child(_d_model)
	for mi: MeshInstance3D in _d_model.find_children("*", "MeshInstance3D"):
		mi.layers = CHAR_LAYER
	_add_shadow(self, SHADOW_SIZE)   # CRenderableShadowSpec: the same blob as the zombies'
	_heading = rotation.y
	_d_anim = _d_model.find_children("*", "AnimationPlayer")[0]
	for a in DOG_RUNS + [DOG_IDLE, DOG_WALK]:
		if _d_anim.has_animation(a):
			_d_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_d_run = DOG_RUNS.pick_random()
	_d_agent = NavigationAgent3D.new()
	_d_agent.path_desired_distance = 0.6
	_d_agent.target_desired_distance = 0.5
	_d_agent.radius = 0.35
	_d_agent.height = 1.0
	add_child(_d_agent)
	_d_play(_d_run)
	_d_anim.speed_scale = 1.15
	if target:
		_d_agent.target_position = target.global_position
	if flame:
		_add_fire()


# ingame.lua SpawnDog: a dog is a flame dog when RandomNumber(1, 100) < 50
static func roll_flame() -> bool:
	return randi_range(1, 100) < 50


# "dog_fire" emitter on the spine: 25-60 flames living 0.75-1.75 s, 0.25-0.6 m,
# drifting up (emitter values 100-250 units, velocity -50..50 / 10..60, accel up 1000-2250)
func _add_fire() -> void:
	var holder: Node3D = self
	var sk := _d_model.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		var skel := sk[0] as Skeleton3D
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).ends_with(FLAME_BONE):   # exported as "bone13_ba089bde"
				var att := BoneAttachment3D.new()
				att.bone_name = skel.get_bone_name(i)
				skel.add_child(att)
				holder = att
				break
	_fire = WeaponFx.particles(FLAME_TEX, {"amount": 40, "lifetime": 1.0, "size": 0.42, "grow": 0.6,
		"speed": 0.15, "dir": Vector3.UP, "spread": 60.0, "gravity": Vector3(0, 4.0, 0), "one_shot": false,
		"box": Vector3(0.45, 0.15, 0.18), "local": false, "color": Color(1, 1, 1, 0.9), "fade_in": 0.15})
	holder.add_child(_fire)
	if holder != self:
		_fire.position = Vector3(-0.3, 0, 0)   # the bone's +x runs to the neck: cover the back too
	_fire.emitting = true
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.5, 0.15)
	_fire_light.light_energy = 1.2
	_fire_light.omni_range = 3.0
	_fire_light.position = Vector3.UP * 0.7
	add_child(_fire_light)


func _process(_delta: float) -> void:
	if _fire_light and state != State.DEAD:
		_fire_light.light_energy = 0.9 + randf() * 0.6


func _d_play(a: String, blend := 0.15) -> void:
	if _d_anim.current_animation != a:
		_d_anim.play(a, blend)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		velocity = Vector3(0, velocity.y - 12.0 * delta, 0) if not is_on_floor() else Vector3.ZERO
		move_and_slide()
		return
	if target == null or target.dead:
		_d_play(DOG_IDLE)
		return
	var to := target.global_position - global_position
	var flat := Vector3(to.x, 0, to.z)
	if _d_attacking:
		_d_face(target.global_position)
		_d_timer -= delta
		if not _d_bit and _d_timer < DOG_BITE_TIME * 0.5:
			_d_bit = true
			if flat.length() < DOG_RANGE + 0.5 and absf(to.y) < 1.5:
				target.take_hit(DOG_DAMAGE)
				VoxLines.hit_by_enemy()   # "been_hit" line (vox_lines.gd)
		if _d_timer <= 0.0:
			_d_attacking = false
			_d_play(_d_run)
		_d_gravity(delta)
		return
	if flat.length() < DOG_RANGE and absf(to.y) < 1.5:
		_d_attacking = true
		_d_bit = false
		_d_timer = DOG_BITE_TIME
		_d_anim.stop()
		_d_anim.play(DOG_BITE, 0.1)
		Sfx.instance.play_at("dog_attack", global_position + Vector3.UP * 0.6)
		return
	_d_repath -= delta
	if _d_repath <= 0.0:
		_d_agent.target_position = target.global_position
		_d_repath = 0.3
	var walking := flat.length() > DOG_RUN_RADIUS
	_d_play(DOG_WALK if walking else _d_run)
	_d_anim.speed_scale = 1.0 if walking else 1.15
	var next := _d_agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if _d_agent.is_navigation_finished() or dir.length() < 0.05:
		dir = flat   # off the navmesh or at the end of the path: head straight for the player
	if dir.length() > 0.05:
		dir = dir.normalized()
		_d_face(global_position + dir)
	var v := DOG_WALK_SPEED if walking else DOG_SPEED
	velocity.x = dir.x * v
	velocity.z = dir.z * v
	_d_gravity(delta)


func _d_gravity(delta: float) -> void:
	if _d_attacking:
		velocity.x = 0.0
		velocity.z = 0.0
	velocity.y = 0.0 if is_on_floor() else velocity.y - 12.0 * delta
	if is_on_floor():
		Stairs.step_up(self, delta)
	move_and_slide()


func _d_face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.01:
		var dt := get_physics_process_delta_time()
		_heading = rotate_toward(_heading, atan2(d.x, d.z), DOG_TURN_MOVE * dt)
		rotation.y = rotate_toward(rotation.y, _heading, DOG_TURN_RENDER * dt)


func take_damage(amount: float, headshot: bool, by: Player, knife := false, hit_pos := Vector3.INF) -> void:
	if state == State.DEAD:
		return
	HitFx.on_hit(self, amount, hit_pos, by, knife)   # the dogs' CHitTemplate 1d1ca339 (hit_fx.gd)
	var g := get_parent() as Game
	if g and g.insta_kill:
		amount = health
	health -= amount
	if by:
		by.add_points(10 * (g.points_multiplier if g else 1))
	if health <= 0.0:
		_dog_die(headshot, knife)


func nuke_kill() -> void:
	if state == State.DEAD:
		return
	health = 0.0
	_dog_die(false, false)


func _dog_die(headshot: bool, knife: bool) -> void:
	if state == State.DEAD:
		return   # killed (and counted) once only
	state = State.DEAD
	_d_attacking = false
	collision_layer = 0
	collision_mask = 1
	Sfx.instance.play_at(["dog_death1", "dog_death2"].pick_random(), global_position + Vector3.UP * 0.5)
	_d_anim.speed_scale = 1.0
	_d_anim.play(DOG_DEATHS.pick_random(), 0.1)
	if flame:
		_flame_burst()
	killed.emit(self, headshot, knife)
	get_tree().create_timer(4.0, false).timeout.connect(queue_free)


# flame_dog CDeathActionSpawnSpec -> effects entity 509bce00: fireball, embers, smoke
func _flame_burst() -> void:
	var at := global_position + Vector3.UP * 0.5
	var parent := get_parent()
	if _fire:
		_fire.emitting = false
	if _fire_light:
		_fire_light.queue_free()
		_fire_light = null
	WeaponFx.pop(parent, at, "bce537be", 1.0, 2.2, 0.45)
	WeaponFx.burst(parent, at, "623a30c5", {"amount": 40, "lifetime": 0.5, "size": 0.35, "grow": 0.5,
		"speed": 3.75, "spread": 180.0, "gravity": Vector3(0, -3.0, 0), "damping": 2.0})
	WeaponFx.burst(parent, at, "34c2dd63", {"amount": 12, "lifetime": 2.5, "size": 0.6, "grow": 2.5,
		"speed": 0.6, "spread": 180.0, "gravity": Vector3(0, 0.5, 0), "additive": false,
		"color": Color(0.55, 0.52, 0.5, 0.6), "sphere": 0.3})
	WeaponFx.flash(parent, at, Color(1.0, 0.55, 0.2), 4.0, 5.0, 0.8)
