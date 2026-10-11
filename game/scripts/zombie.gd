# Zombie: walks from its spawn to a window, tears the boards down, climbs in
# and chases the player. Body animations are in-place; movement speed comes
# from the paired root-motion track (see analysis/zombie_anims.tsv).
class_name Zombie
extends CharacterBody3D

signal killed(zombie: Zombie, headshot: bool, knife: bool)

const MODEL := "res://assets/characters/ingame/zombiesmodelsger/fee5ccda.glb"
const HIDDEN_PARTS := ["headb", "980daf40"]
# body animation -> speed (m/s) of its root-motion partner
const WALKS := {"fbe7b3da": 0.96, "fbe7b3db": 0.95, "fbe7b3dc": 1.0, "fbe7b3dd": 1.21,
	"fbe7b3de": 0.57, "fbe7b3df": 0.58, "fbe7b3e0": 0.65, "9a1f4265": 0.69}
const RUNS := {"c9903fc0": 3.03, "842441ac": 3.61, "842441ab": 3.49, "c349cc28": 1.65,
	"4e83b4a9": 2.02, "4e83b4aa": 1.97}
const IDLE := "c98b07c8"
const ATTACKS := ["fab4136a", "fb0fe592"]
const DEATHS := ["20b0e521", "371f7199", "f037474d"]
# window: swipe at the boards in place, then climb through (its root-motion partner
# 4c478fd4 moves 1.34 m forward over the 4.07 s animation)
const TEAR := "fb0fe592"
const CLIMB := "9c58e56e"
const ATTACK_RANGE := 1.3
const ATTACK_DAMAGE := 45.0

enum State { TO_WINDOW, TEARING, CLIMBING, CHASE, ATTACK, DEAD }

var state := State.TO_WINDOW
var health := 100.0
var window: Barricade
var target: Player
var move_anim := ""
var speed := 1.0

var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _model: Node3D
var _timer := 0.0
var _hit_done := false
var _repath := 0.0
var _best_dist := INF
var _stall := 0.0


func setup(spawn: Vector3, win: Barricade, player: Player, hp: float, runner: bool) -> void:
	window = win
	target = player
	health = hp
	var pool := RUNS if runner else WALKS
	move_anim = pool.keys().pick_random()
	speed = pool[move_anim]
	position = spawn


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	_model = (load(MODEL) as PackedScene).instantiate()
	add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D"):
		mi.visible = not (mi.name in HIDDEN_PARTS or mi.name.ends_with("_m1"))
	_anim = _model.find_children("*", "AnimationPlayer")[0]
	for a in WALKS.keys() + RUNS.keys() + [IDLE] + ATTACKS:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.radius = 0.35
	_agent.height = 1.8
	add_child(_agent)
	_play(move_anim)
	_agent.target_position = window.outside


func _play(a: String, blend := 0.2) -> void:
	if _anim.current_animation != a:
		_anim.play(a, blend)


func _physics_process(delta: float) -> void:
	match state:
		State.TO_WINDOW:
			var d := global_position.distance_to(window.outside)
			# progress watchdog: a zombie that stops getting closer is put at the window
			if d < _best_dist - 0.2:
				_best_dist = d
				_stall = 0.0
			else:
				_stall += delta
			if d < 0.7 or (_agent.is_navigation_finished() and d < 2.5) or _stall > 6.0:
				global_position = window.outside
				_start_tearing()
			else:
				_move_along_path(delta)
		State.TEARING:
			_face(window.inside)
			_timer -= delta
			if window.boards <= 0:
				_start_climb()
			elif _timer <= 0.0:
				# one board per swipe, like the original
				_anim.stop()
				_anim.play(TEAR, 0.1)
				window.tear_board()
				_timer = _anim.get_animation(TEAR).length + 0.15
		State.CLIMBING:
			pass  # driven by tween
		State.CHASE:
			if target.dead:
				_play(IDLE)
				return
			var d := global_position.distance_to(target.global_position)
			if d < ATTACK_RANGE:
				state = State.ATTACK
				_timer = 1.0
				_hit_done = false
				_play(ATTACKS.pick_random(), 0.1)
				Sfx.instance.play_at("zombie_attack", global_position + Vector3.UP * 1.5)
			else:
				_repath -= delta
				if _repath <= 0.0:
					_agent.target_position = target.global_position
					_repath = 0.4
				_move_along_path(delta)
		State.ATTACK:
			_face(target.global_position)
			_timer -= delta
			if not _hit_done and _timer < 0.5:
				_hit_done = true
				if global_position.distance_to(target.global_position) < ATTACK_RANGE + 0.4:
					target.take_hit(ATTACK_DAMAGE)
			if _timer <= 0.0:
				state = State.CHASE
				_play(move_anim)
		State.DEAD:
			pass


func _move_along_path(delta: float) -> void:
	_play(move_anim)
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		_face(global_position + dir)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 12.0 * delta
	if is_on_floor():
		Stairs.step_up(self, delta)
	move_and_slide()


func _face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.01:
		# model faces +Z
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 0.2)


func _start_tearing() -> void:
	if window.occupied_by != null and window.occupied_by != self and is_instance_valid(window.occupied_by):
		_play(IDLE)
		return  # wait for the zombie ahead
	window.occupied_by = self
	state = State.TEARING
	_timer = 1.0
	_play(TEAR)


func _start_climb() -> void:
	state = State.CLIMBING
	_play(CLIMB, 0.1)
	collision_mask = 0
	var tw := create_tween()
	tw.tween_property(self, "global_position", window.inside, _anim.get_animation(CLIMB).length)
	tw.finished.connect(func():
		collision_mask = 1 | 4
		window.occupied_by = null
		state = State.CHASE
		_play(move_anim))


func take_damage(amount: float, headshot: bool, by: Player, knife := false) -> void:
	if state == State.DEAD:
		return
	health -= amount
	by.add_points(10)
	if health <= 0.0:
		_die(headshot, knife)


func _die(headshot: bool, knife := false) -> void:
	Sfx.instance.play_at("zombie_death", global_position + Vector3.UP * 1.5)
	state = State.DEAD
	if window.occupied_by == self:
		window.occupied_by = null
	collision_layer = 0
	collision_mask = 1
	_anim.play(DEATHS.pick_random(), 0.1)
	killed.emit(self, headshot, knife)
	get_tree().create_timer(6.0).timeout.connect(queue_free)
