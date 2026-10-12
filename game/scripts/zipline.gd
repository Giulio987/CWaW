# Shi No Numa zipline ("teleferica"), rebuilt from the level data:
#
# ZipLine entity: CZiplineSpec moves the whole entity between DestA (its own origin,
# on the "ledge" off the warning room balcony) and DestB (child entity 02c7023c at
# local (33.76, -3.76, 2.98): by the doctors' hut) in ZiplineMovementTime = 6000 ms
# (default in the binary, console.bin does not override it); CActionBuyTrapSpec cost
# 1500; car model b015f907 hung at local (0, 2.5, 1.46); platform collider with
# CSplashEffectSpec 5000 damage (shinonuma.lua SetDamageActive("ZipLine") between
# zipLineStart and zipLineEnd: it kills the zombies it runs into); handle lever b2d32af6.
#
# Car state machine b015f907 (CIsAnimStateMachine; entry actions and inputs are
# indexed from the end of the machine's input/output name tables):
#   S0 at the top: msg "Activate Zipline [Cost: %d]", Lua zipLineReadyAtTop
#     -goodieInteract-> S1: buy, Lua zipLineStart, moveToDestB -reachedDestination-> S3
#     -altGoodieInteract-> S2: Lua zipLineStart, moveToDestB (empty)           -> S3
#   S3 at the bottom: Lua zipLineEnd, releasePlayers, 30000 ms -> S4
#   S4 at the bottom: msg "Activate Zipline [Cost: %d]" -goodieInteract-> S5: buy,
#     zipLineStart, moveToDestA -reachedDestination-> S6: zipLineEnd, releasePlayers,
#     30000 ms -> S0
# ZiplineDoctorSwitch lever (state machine b2d32af6): off, msg "Activate Zipline"
#   -goodieInteract-> move (fireAction -> shinonuma.lua: OpenLink(Links[11]) =
#   ledge <-> warningRoom, ZipLineDoorLink "ZipLineTurnOn", ZipLine "altGoodieInteract")
#   -> on. zipLineStart sends it altGoodieInteract (stays on, no message);
#   zipLineReadyAtTop sends returnToIdle -> msg "Call Zipline [Cost: 1500]" -> move ...
# ZipLineDoorLink gate (state machine 5ebd2101): closed, msg "The zipline must be
#   activated first" -ZipLineTurnOn-> opening (anim 2064c972 at rate 0.8: 85 deg about
#   its hinge in 1.46 s, sound 8737cbb6) -> open.
class_name Zipline
extends Node3D

const MOVE_TIME := 6.0          # ZiplineMovementTime 6000
const WAIT_TIME := 30.0         # car states S3 / S6
const CALL_COST := 1500         # "Call Zipline [Cost: 1500]"
const CAR_MODEL := "b015f907"
const LEVER_MODEL := "b2d32af6"
const GATE_MODEL := "5ebd2101"
const LEVER_OFF := "ac24d813"
const LEVER_MOVE := "3d837212"
const LEVER_ON := "48bb3790"
const GATE_SOUND := "8737cbb6"
const GATE_OPEN := Quaternion(0.0, 0.677, 0.0, 0.736)   # anim 2064c972 last key
const GATE_TIME := 1.458

enum Car { AT_TOP, DOWN, AT_BOTTOM_WAIT, AT_BOTTOM, UP, AT_TOP_WAIT }

var level: Level
var cost := 1500
var activated := false
var car_state := Car.AT_TOP
var _a: Transform3D             # DestA: the entity's transform
var _b: Transform3D             # DestB
var _t := 0.0                   # 0 at A, 1 at B
var _timer := 0.0
var _riders := {}               # Player -> offset in the car frame
var _box := AABB()              # interaction / kill volume in the car frame
var car: Node3D                 # moves between A and B
var _platform: AnimatableBody3D
var _car_lever: AnimationPlayer
var switch: ZipSwitch
var gate: ZipGate
var car_use: ZipCar


func setup(level_: Level) -> void:
	level = level_
	process_physics_priority = 10   # after the player: riders are carried
	var e := level.entity("ZipLine")
	cost = int(e.get("params", {}).get("cost", 1500))
	_a = level.entity_transform("ZipLine")
	_b = level.entity_transform("ZipLine", true)
	_b.basis = _a.basis
	car = Node3D.new()
	car.name = "Car"
	add_child(car)
	car.global_transform = _a
	var ch: Array = e["children"]
	# car model (sub-entity transform 2) and handle lever (sub-entity 3)
	var m := level.dynamics_model(CAR_MODEL)
	if m and ch.size() > 1:
		car.add_child(m)
		m.transform = Level._to_transform(ch[1])
	var lever := level.dynamics_model(LEVER_MODEL)
	if lever and ch.size() > 2:
		car.add_child(lever)
		lever.transform = Level._to_transform(ch[2])
		var aps := lever.find_children("*", "AnimationPlayer")
		_car_lever = aps[0] if aps.size() > 0 else null
		_pose(_car_lever, LEVER_OFF)
	# platform (sub-entity 1: collider box 2) the riders stand on
	var cols: Array = e.get("colliders", [])
	if cols.size() > 1 and ch.size() > 0:
		_platform = AnimatableBody3D.new()
		_platform.sync_to_physics = false
		car.add_child(_platform)
		_platform.transform = Level._to_transform(ch[0])
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Trap._box_size(cols[1])
		cs.shape = box
		cs.position = Trap._box_centre(cols[1])
		_platform.add_child(cs)
	# interaction volume (collider box 1, in the entity frame), also the kill volume
	if not cols.is_empty():
		var c: Dictionary = cols[0]
		var lo := Vector3(c["min"][0], c["min"][1], c["min"][2]) * Level.UNITS
		var hi := Vector3(c["max"][0], c["max"][1], c["max"][2]) * Level.UNITS
		_box = AABB(lo, hi - lo).grow(0.3)
		_box.size.y += 2.0
	car_use = ZipCar.new()
	car_use.zip = self
	car_use.name = "Use"
	car.add_child(car_use)
	car_use.position = _box.get_center()
	switch = ZipSwitch.new()
	switch.zip = self
	switch.name = "ZiplineDoctorSwitch"
	add_child(switch)
	switch.setup()
	gate = ZipGate.new()
	gate.zip = self
	gate.name = "ZipLineDoorLink"
	add_child(gate)
	gate.setup()


func interactables() -> Array:
	return [car_use, switch, gate]


static func _pose(ap: AnimationPlayer, a: String) -> void:
	if ap and ap.has_animation(a):
		ap.get_animation(a).loop_mode = Animation.LOOP_NONE
		ap.play(a)
		ap.seek(ap.get_animation(a).length, true)


static func _play(ap: AnimationPlayer, a: String) -> void:
	if ap and ap.has_animation(a):
		ap.get_animation(a).loop_mode = Animation.LOOP_NONE
		ap.play(a)


func game() -> Game:
	return level.get_parent() as Game


func moving() -> bool:
	return car_state in [Car.DOWN, Car.UP]


# the point in the car's interaction volume (world)
func in_car(p: Vector3) -> bool:
	return _box.has_point(car.global_transform.affine_inverse() * p)


# shinonuma.lua, ZiplineDoctorSwitch: open the ledge, the gate, and call the car down
func switch_fired() -> void:
	if not activated:
		activated = true
		var g := game()
		if g:
			g.open_area("ledge")
		gate.open()
	if car_state == Car.AT_TOP:
		_start(Car.DOWN, false)   # altGoodieInteract: S0 -> S2, nobody aboard


# goodieInteract on the car (S0 / S4): pay and ride
func ride(player: Player) -> void:
	if car_state == Car.AT_TOP:
		_start(Car.DOWN, true, player)
	elif car_state == Car.AT_BOTTOM:
		_start(Car.UP, true, player)


func _start(s: Car, paid: bool, player: Player = null) -> void:
	car_state = s
	_riders.clear()
	if paid and player:
		var off := car.global_transform.affine_inverse() * player.global_position
		_riders[player] = off
	switch.zip_started()    # Lua zipLineStart: switch altGoodieInteract, damage on
	_play(_car_lever, LEVER_MOVE)
	if OS.get_cmdline_user_args().has("--zip-log"):
		print("[zip] start %s riders=%d t=%.2f" % [Car.keys()[s], _riders.size(), _t])


func _arrive() -> void:
	# reachedDestination: Lua zipLineEnd (damage off), releasePlayers, 30 s
	car_state = Car.AT_BOTTOM_WAIT if car_state == Car.DOWN else Car.AT_TOP_WAIT
	_timer = WAIT_TIME
	for p in _riders:
		if is_instance_valid(p):
			p.velocity = Vector3.ZERO
	_riders.clear()
	_pose(_car_lever, LEVER_ON)
	if OS.get_cmdline_user_args().has("--zip-log"):
		print("[zip] arrived %s at %s" % [Car.keys()[car_state], car.global_position.snapped(Vector3(0.01, 0.01, 0.01))])


func _physics_process(delta: float) -> void:
	match car_state:
		Car.DOWN, Car.UP:
			_t = clampf(_t + (delta if car_state == Car.DOWN else -delta) / MOVE_TIME, 0.0, 1.0)
			car.global_transform = Transform3D(_a.basis, _a.origin.lerp(_b.origin, _t))
			for p: Player in _riders:
				if is_instance_valid(p) and not p.dead:
					p.global_position = car.global_transform * _riders[p]
					p.velocity = Vector3.ZERO
			_kill_in_path()
			if (car_state == Car.DOWN and _t >= 1.0) or (car_state == Car.UP and _t <= 0.0):
				_arrive()
		Car.AT_BOTTOM_WAIT, Car.AT_TOP_WAIT:
			_timer -= delta
			if _timer <= 0.0:
				if car_state == Car.AT_BOTTOM_WAIT:
					car_state = Car.AT_BOTTOM
				else:
					car_state = Car.AT_TOP
					switch.ready_at_top()   # Lua zipLineReadyAtTop: switch returnToIdle
				_pose(_car_lever, LEVER_OFF)


# CSplashEffectSpec while moving: zombies and dogs in the car's way die (no points)
func _kill_in_path() -> void:
	var g := game()
	var inv := car.global_transform.affine_inverse()
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Zombie and z.state != Zombie.State.DEAD and _box.has_point(inv * (z.global_position + Vector3.UP * 0.8)):
			if g:
				g.kill_without_points(z)
			else:
				z.nuke_kill()


# --------------------------------------------------------------- interactables

class ZipCar extends Node3D:
	var zip: Zipline

	func usable_from(p: Vector3) -> bool:
		return zip.in_car(p)

	func prompt(_player: Player) -> String:
		if zip.car_state in [Zipline.Car.AT_TOP, Zipline.Car.AT_BOTTOM]:
			return "Premi E per attivare la teleferica [%d]" % zip.cost
		return ""

	func interact(player: Player) -> void:
		if not zip.car_state in [Zipline.Car.AT_TOP, Zipline.Car.AT_BOTTOM]:
			return
		if player.points < zip.cost:
			Sfx.instance.play("buy_fail")
			return
		player.add_points(-zip.cost)
		Sfx.instance.play("buy_success")
		zip.ride(player)


# ZiplineDoctorSwitch: the lever by the doctors' hut
class ZipSwitch extends Node3D:
	enum S { OFF, IDLE, ON }
	var zip: Zipline
	var state := S.OFF
	var use_point := Vector3.ZERO
	var _lever: AnimationPlayer

	func setup() -> void:
		var lv := zip.level
		var e := lv.entity("ZiplineDoctorSwitch")
		global_transform = lv.entity_transform("ZiplineDoctorSwitch")
		var cols: Array = e.get("colliders", [])
		use_point = global_transform * Trap._box_centre(cols[0]) if not cols.is_empty() else global_position
		var m := lv.dynamics_model(Zipline.LEVER_MODEL)
		if m:
			add_child(m)
			if not e["children"].is_empty():
				m.transform = Level._to_transform(e["children"][-1])
			var aps := m.find_children("*", "AnimationPlayer")
			_lever = aps[0] if aps.size() > 0 else null
			Zipline._pose(_lever, Zipline.LEVER_OFF)

	func usable_from(p: Vector3) -> bool:
		return Vector2(p.x - use_point.x, p.z - use_point.z).length() < 1.9 and absf(p.y - use_point.y) < 2.0

	func prompt(_player: Player) -> String:
		match state:
			S.OFF:
				return "Premi E per attivare la teleferica"
			S.IDLE:
				return "Premi E per chiamare la teleferica [%d]" % Zipline.CALL_COST
		return ""

	func interact(player: Player) -> void:
		if state == S.ON:
			return
		if state == S.IDLE:
			if player.points < Zipline.CALL_COST:
				Sfx.instance.play("buy_fail")
				return
			player.add_points(-Zipline.CALL_COST)
			Sfx.instance.play("buy_success")
		state = S.ON
		Zipline._play(_lever, Zipline.LEVER_MOVE)
		zip.switch_fired()

	# zipLineStart: altGoodieInteract -> "on" without firing
	func zip_started() -> void:
		if state == S.IDLE:
			state = S.ON
			Zipline._play(_lever, Zipline.LEVER_MOVE)

	# zipLineReadyAtTop: returnToIdle
	func ready_at_top() -> void:
		if state == S.ON and zip.activated:
			state = S.IDLE
			Zipline._pose(_lever, Zipline.LEVER_OFF)


# ZipLineDoorLink: the gate between the warning room balcony and the ledge
class ZipGate extends Node3D:
	var zip: Zipline
	var is_open := false
	var use_point := Vector3.ZERO
	var _model: Node3D
	var _body: StaticBody3D
	var _closed := Basis.IDENTITY

	func setup() -> void:
		var lv := zip.level
		var e := lv.entity("ZipLineDoorLink")
		global_transform = lv.entity_transform("ZipLineDoorLink")
		_model = lv.dynamics_model(Zipline.GATE_MODEL)
		if _model:
			add_child(_model)
			if not e["children"].is_empty():
				_model.transform = Level._to_transform(e["children"][-1])
			_closed = _model.transform.basis
		var cols: Array = e.get("colliders", [])
		use_point = global_transform * Trap._box_centre(cols[0]) if not cols.is_empty() else global_position
		# the closed gate blocks the way (its model's span, raised so it cannot be jumped)
		if _model:
			_body = StaticBody3D.new()
			add_child(_body)
			_body.transform = _model.transform
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2.2, 3.0, 0.3)
			cs.shape = box
			cs.position = Vector3(1.05, 1.5, 0.03)
			_body.add_child(cs)

	func usable_from(p: Vector3) -> bool:
		return not is_open and Vector2(p.x - use_point.x, p.z - use_point.z).length() < 2.2 and absf(p.y - use_point.y) < 2.0

	func prompt(_player: Player) -> String:
		return "" if is_open else "La teleferica deve essere attivata prima"

	func interact(_player: Player) -> void:
		pass

	func open() -> void:
		if is_open:
			return
		is_open = true
		if _body:
			_body.queue_free()
		Sfx.instance.play_at(Zipline.GATE_SOUND, global_position + Vector3.UP)
		if _model:
			var tw := create_tween()
			tw.tween_property(_model, "basis", _closed * Basis(Zipline.GATE_OPEN), Zipline.GATE_TIME).set_trans(Tween.TRANS_SINE)
