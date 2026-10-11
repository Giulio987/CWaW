# Hellhound (dog rounds on Shi No Numa and Der Riese, waves.lua StartDogWave):
# appears in a lightning strike, runs straight at the player, bites, dies.
# It extends Zombie so bullets, the knife, nukes and traps that look for
# Zombie nodes hit dogs too; everything else is its own.
# Animations (characters/ingame/dogs, model faces +Z, root motion is in the
# root bone so the loops are in place), identified from contact sheets
# (game/tools/dogsheet.gd):
#   run 0b0e1cce / 6d4c918e (gallop loops), bite fe591198, leap 69acb481,
#   deaths 773dd671 8c7140e3 8c7140e4 41af9c33 7811ea46, idle 90866617.
class_name Dog
extends Zombie

const DOG_MODEL := "res://assets/characters/ingame/dogs/1d22586d.glb"
const DOG_RUNS := ["0b0e1cce", "6d4c918e"]
const DOG_BITE := "fe591198"
const DOG_IDLE := "90866617"
const DOG_DEATHS := ["773dd671", "8c7140e3", "8c7140e4", "41af9c33", "7811ea46"]
const DOG_SPEED := 5.2       # faster than walking (4.2), a sprinting player (6.0) can still outrun them
const DOG_RANGE := 1.35      # bite reach (m)
const DOG_DAMAGE := 35.0     # three bites down a player without Juggernog
const DOG_BITE_TIME := 0.9

var untracked := false       # teleporter dogs (Der Riese): not part of a dog round
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
	collision_mask = 1 | 4
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
	_d_anim = _d_model.find_children("*", "AnimationPlayer")[0]
	for a in DOG_RUNS + [DOG_IDLE]:
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
	_d_play(_d_run)
	var next := _d_agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if _d_agent.is_navigation_finished() or dir.length() < 0.05:
		dir = flat   # off the navmesh or at the end of the path: head straight for the player
	if dir.length() > 0.05:
		dir = dir.normalized()
		_d_face(global_position + dir)
	velocity.x = dir.x * DOG_SPEED
	velocity.z = dir.z * DOG_SPEED
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
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 0.25)


func take_damage(amount: float, headshot: bool, by: Player, knife := false) -> void:
	if state == State.DEAD:
		return
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
	state = State.DEAD
	_d_attacking = false
	collision_layer = 0
	collision_mask = 1
	Sfx.instance.play_at(["dog_death1", "dog_death2"].pick_random(), global_position + Vector3.UP * 0.5)
	_d_anim.speed_scale = 1.0
	_d_anim.play(DOG_DEATHS.pick_random(), 0.1)
	# the original dogs burst into flames as they die: a short orange flash
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.15)
	l.light_energy = 3.0
	l.omni_range = 4.0
	l.position = Vector3.UP * 0.5
	add_child(l)
	create_tween().tween_property(l, "light_energy", 0.0, 0.8)
	killed.emit(self, headshot, knife)
	get_tree().create_timer(4.0, false).timeout.connect(queue_free)
