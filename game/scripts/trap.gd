# Buyable trap (CActionBuyTrapSpec): the electric "zappers" of Verrückt, Shi No
# Numa's huts and Der Riese, and Shi No Numa's flogger. As in the level scripts
# (verruckt.lua / derriese.lua / shinonuma.lua): bought at its switch, it runs
# for 30 s ("zapperStart" -> Timeout(30000, "<trap>End")), killing every zombie
# and dog that walks into it and hurting the player; then it cools down. On maps
# with a generator the traps get "genTurnOn" from TurnOnGenerator: power first.
#
# Timing from the switch's CIsAnimStateMachine (2b8efeb7, the same for every
# electric trap of the three maps; the flogger's b373d4cb has the same 30 s state):
#   off (d7a98b8c) -genTurnOn-> READY (1ac5406a) -goodieInteract-> TurnOn 11f334e0 0.966 s
#   -> 726310c1 1.299 s, Lua "zapperStart" (the 30 s Lua timer starts)
#   -> 9768b2de loop, Lua "zapperOn" (arcs on) -zapperEnd-> 5059d03e 1.033 s
#   -> 8d5f0abc held for 30000 ms (the cooldown) -> TurnOff 09888375 0.966 s,
#   plays f629ac13, Lua "zapperOff" -> READY.
# The CActionBuyTrapSpec itself only stores the cost.
#
# Kill volume: the trap's "<trap>Effect<n>" sub-entities mark the electric arcs
# (Der Riese, Shi No Numa); Verrückt has none, so its two fences are found among
# the entity's collider boxes + child offsets by checking which placement fits a
# doorway in the level geometry. The flogger kills in a circle around its pivot.
class_name Trap
extends Node3D

const ACTIVE_TIME := 30.0     # Lua: Timeout(30000, "<trap>End"), from "zapperStart"
const COOLDOWN := 30.0        # ASM state 8e02e6be: 30000 ms
const USE_RANGE := 1.9
const PLAYER_DAMAGE := 40.0   # per second spent in the trap
const LEVER_MODEL := "c110c7c0"
# switch animations and state times of ASM 2b8efeb7 (see above)
const LEVER_OFF := "d7a98b8c"
const LEVER_READY := "1ac5406a"
const LEVER_TURN_ON := ["11f334e0", 0.966]
const LEVER_PULL := ["726310c1", 1.299]   # "zapperStart"
const LEVER_ACTIVE := "9768b2de"          # "zapperOn", loops while the trap runs
const LEVER_BACK := ["5059d03e", 1.033]   # after "zapperEnd"
const LEVER_COOL := "8d5f0abc"            # held for COOLDOWN
const LEVER_TURN_OFF := ["09888375", 0.966]   # plays TRAP_READY_SOUND, "zapperOff"
const TRAP_READY_SOUND := "f629ac13"
const FLOGGER_TURN_OFF := 0.833           # flogger ASM b373d4cb TurnOff state
# Flogger ASM b373d4cb (Lua outputs named by their hashes):
#   READY -goodieInteract-> TurnOn 875 ms, plays 7653e0bc
#   -> spin up 5977 ms: "floggerStart" (the 30 s, as zapperStart), plays 35e60ba8;
#      at 2333 ms "floggerStartEngineLoopSound", at 3333 ms "floggerStartDamager" (kills)
#   -> full force: "floggerStartWhooshLoopSound", until "floggerEnd"
#   -> spin down 7533 ms: "floggerStopLoopSounds", plays 56f77680; at 2000 ms
#      "floggerEndDamager" -> 30000 ms -> TurnOff 833 ms, plays f629ac13 -> READY.
# The loops are the child emitters Trap_FloggerSound1 (eafe4b96, 0.46 s: the whoosh) and
# Trap_FloggerSound2 (56f38a94, 1.9 s: the engine) of Trap_Flogger (which is which: estimate).
const FLOG_TURN_ON := 0.875
const FLOG_ENGINE_AT := 2.333
const FLOG_DAMAGER_AT := 3.333
const FLOG_SPIN_UP := 5.977
const FLOG_SPIN_DOWN := 7.533
const FLOG_DAMAGER_END := 2.0
const FLOG_SOUND_TURN_ON := "7653e0bc"
const FLOG_SOUND_START := "35e60ba8"
const FLOG_SOUND_STOP := "56f77680"
const FLOG_LOOP_WHOOSH := "eafe4b96"
const FLOG_LOOP_ENGINE := "56f38a94"
const FLOGGER_MODEL := "b373d4cb"
const FLOGGER_RADIUS := 3.4

enum State { IDLE, ACTIVE, COOLDOWN }

var level: Level
var entity := ""
var cost := 1000
var kind := "electric"        # or "flogger"
var state := State.IDLE
var volumes := []             # world AABBs that kill (electric)
var use_point := Vector3.ZERO
var pivot := Vector3.ZERO     # flogger centre
var _timer := 0.0
var armed := false             # killing (electric: from "zapperOn", 2.3 s after buying)
var _arm_at := 0.0
var _turned_off := false
var _hurt_cd := 0.0
var _lever: AnimationPlayer
var _flogger: Node3D
var _fx: Node3D
var gen_on := false           # the switch got "genTurnOn" (power, maybe delayed: GEN_DELAY)
const GEN_DELAY := {"Trap_power": 4.3}
# Shi No Numa: buying Link_DwnSt_FshSw_Trigger sends the flogger "doorOpen"
# (shinonuma.lua Trigger, bytecode 212-225); until then the trap is not for sale.
# The door counts as open once it has left level.debris (bought, or freed by a resumed save).
const FLOGGER_DOOR := "Link_DwnSt_FshSw_Trigger"
var _door: Node = null
var _flog_loops := {}         # spec -> AmbientEmitters.Emitter (flogger)
var _flog_started := false


func setup(level_: Level, entity_: String) -> void:
	level = level_
	entity = entity_
	var e: Dictionary = level.entities[entity]
	add_to_group(SaveGame.PROVIDER_GROUP)   # running / cooling down state (save_game.gd)
	cost = int(e.get("params", {}).get("cost", 1000))
	kind = "flogger" if "flogger" in entity.to_lower() else "electric"
	var root := level.entity_transform(entity)
	global_transform = root
	var cols: Array = e.get("colliders", [])
	if not cols.is_empty():
		use_point = root * _box_centre(cols[0])
	else:
		use_point = root.origin
	gen_on = level.power_on
	level.power_changed.connect(_gen_turn_on)
	if kind == "flogger":
		for d in level.debris:
			if PerkMachine.same_name(d.entity, FLOGGER_DOOR):
				_door = d
	if kind == "electric":
		_place_lever(e)
		var fx := []
		for i in range(1, 13):
			var n := "%sEffect%d" % [entity, i]
			if level.has_entity(n):
				fx.append(level.entity_transform(n).origin)
		if not fx.is_empty():
			_volume_from_effects(fx)
	else:
		pivot = root * _box_centre(cols[1]) if cols.size() > 1 else root.origin
		_flogger = level.dynamics_model(FLOGGER_MODEL)
		if _flogger:
			add_child(_flogger)
		# the lever is the small rig hanging off one of the child entities
		for h in e["models"]:
			if h != FLOGGER_MODEL:
				var lever := level.dynamics_model(h)
				if lever:
					add_child(lever)
					var aps := lever.find_children("*", "AnimationPlayer")
					_lever = aps[0] if aps.size() > 0 else null
	if volumes.is_empty() and kind == "electric":
		_finalize_from_geometry.call_deferred(e)


static func _box_centre(c: Dictionary) -> Vector3:
	return (Vector3(c["min"][0], c["min"][1], c["min"][2]) + Vector3(c["max"][0], c["max"][1], c["max"][2])) * 0.5 * Level.UNITS


static func _box_size(c: Dictionary) -> Vector3:
	return (Vector3(c["max"][0], c["max"][1], c["max"][2]) - Vector3(c["min"][0], c["min"][1], c["min"][2])) * Level.UNITS


func _place_lever(_e: Dictionary) -> void:
	var lever := level.dynamics_model(LEVER_MODEL)
	if lever == null:
		return
	add_child(lever)
	var aps := lever.find_children("*", "AnimationPlayer")
	if aps.is_empty():
		return
	_lever = aps[0]
	if _lever.has_animation(LEVER_ACTIVE):
		_lever.get_animation(LEVER_ACTIVE).loop_mode = Animation.LOOP_LINEAR
	_lever_pose(LEVER_READY if level.power_on else LEVER_OFF)
	# ASM "off" -genTurnOn-> "READY" (_gen_turn_on)


# "genTurnOn" from TurnOnGenerator. Der Riese's Trap_power gets it 4.3 s after the
# switch (derriese.lua 611: Timeout(4300, "TrapPowerTurnOn") -> SetASMTrigger
# ("Trap_power", "genTurnOn")); the other traps at once (612-613).
func _gen_turn_on(on: bool) -> void:
	if not on or gen_on:
		return
	var delay: float = GEN_DELAY.get(entity, 0.0) if level.level_name == "derriese" else 0.0
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
	gen_on = true
	if state == State.IDLE:
		_lever_pose(LEVER_READY)


func _lever_pose(a: String) -> void:
	if _lever and _lever.has_animation(a):
		_lever.play(a)
		_lever.seek(0.0, true)
		_lever.pause()


func _lever_play(a: String) -> void:
	if _lever and _lever.has_animation(a):
		_lever.play(a)


# the single-key pose that matches the first frame of a motion (see Debris)
static func _closest_pose(ap: AnimationPlayer, motion: String) -> String:
	if not ap.has_animation(motion):
		return ""
	var m := ap.get_animation(motion)
	var best := ""
	var best_d := INF
	for a in ap.get_animation_list():
		var pose := ap.get_animation(a)
		var keys := 0
		for t in pose.get_track_count():
			keys = max(keys, pose.track_get_key_count(t))
		if keys > 1:
			continue
		var d := 0.0
		for t in pose.get_track_count():
			var mt := m.find_track(pose.track_get_path(t), pose.track_get_type(t))
			if mt < 0 or pose.track_get_key_count(t) == 0:
				continue
			if pose.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				d += (pose.track_get_key_value(t, 0) as Quaternion).angle_to(m.rotation_track_interpolate(mt, 0.0))
			elif pose.track_get_type(t) == Animation.TYPE_POSITION_3D:
				d += (pose.track_get_key_value(t, 0) as Vector3).distance_to(m.position_track_interpolate(mt, 0.0))
		if d < best_d:
			best_d = d
			best = a
	return best


# Effect sub-entities sit on the floor along the fence: the volume spans them.
func _volume_from_effects(pts: Array) -> void:
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var along_x := (hi.x - lo.x) >= (hi.z - lo.z)
	var pad_long := 0.6
	var pad_side := 0.55
	var grow := Vector3(pad_long if along_x else pad_side, 0, pad_side if along_x else pad_long)
	volumes.append(AABB(Vector3(lo.x, lo.y - 0.3, lo.z) - grow, Vector3(hi.x - lo.x, 2.6, hi.z - lo.z) + grow * 2))


# Verrückt: candidate fence boxes are the volume colliders placed at +/- each
# child offset; keep the ones that stand on a floor and fill a doorway.
func _finalize_from_geometry(e: Dictionary) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var root := level.entity_transform(entity)
	var cols: Array = e.get("colliders", [])
	var offsets := [Vector3.ZERO]
	for ch in e["children"]:
		var p := Vector3(ch["pos"][0], ch["pos"][1], ch["pos"][2]) * Level.UNITS
		if absf(p.y) < 0.05:
			for s in [1.0, -1.0]:
				offsets.append(p * s)
	var picked := []
	for ci in range(1, cols.size()):
		var size := _box_size(cols[ci])
		var best := INF
		var best_box := AABB()
		for off in offsets:
			var c: Vector3 = root.origin + off + _box_centre(cols[ci])
			var box := AABB(c - size / 2, size)
			if picked.any(func(b): return (b as AABB).get_center().distance_to(c) < 3.0):
				continue
			var sc := _doorway_score(space, box)
			if OS.get_cmdline_user_args().has("--trap-debug"):
				print("[trap] %s col %d at %s score %.2f" % [entity, ci, c.snapped(Vector3(0.01, 0.01, 0.01)), sc])
			if sc < best:
				best = sc
				best_box = box
		if best < 2.5:
			picked.append(best_box)
	volumes = picked
	if OS.get_cmdline_user_args().has("--trap-debug"):
		print("[trap] %s volumes %s" % [entity, volumes])


func _doorway_score(space: PhysicsDirectSpaceState3D, box: AABB) -> float:
	# the world plus the upright cut-out faces (Level.SEE_THROUGH_LAYER): the jambs and
	# grilles beside Verrueckt's fences are alpha-scissor surfaces, only on that layer
	var mask := 1 | Level.SEE_THROUGH_LAYER
	var c := box.get_center()
	var bottom := box.position.y
	# a floor right under the fence
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, bottom + 1.0, c.z), Vector3(c.x, bottom - 1.0, c.z), mask)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or absf((hit["position"] as Vector3).y - bottom) > 0.4:
		return INF
	var along := Vector3.RIGHT if box.size.x >= box.size.z else Vector3.BACK
	var half := (box.size.x if along == Vector3.RIGHT else box.size.z) / 2.0
	var at := Vector3(c.x, bottom + 1.0, c.z)
	var score := 0.0
	for dir: Vector3 in [along, -along]:
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + dir * (half + 1.5), mask))
		score += 1.5 if r.is_empty() else absf((r["position"] - at).length() - half)
	# open on both sides of the fence (it is a passage)
	var side := along.cross(Vector3.UP)
	for dir: Vector3 in [side, -side]:
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + dir * 1.2, mask))
		if not r.is_empty():
			score += 1.0
	return score


# ------------------------------------------------------------------ interaction

func usable_from(p: Vector3) -> bool:
	return Vector2(p.x - use_point.x, p.z - use_point.z).length() < USE_RANGE and absf(p.y - use_point.y) < 2.0


func door_open() -> bool:
	return _door == null or not level.debris.has(_door)


func prompt(_player: Player) -> String:
	if not door_open():   # flogger ASM b373d4cb: "The door must be opened first" (bcf369e3)
		return Lang.t("Prima bisogna aprire la porta")
	if not gen_on:
		return Lang.t("Serve la corrente")
	match state:
		State.ACTIVE:
			return ""
		State.COOLDOWN:
			return Lang.t("Trappola in ricarica")
	# "Activate Flogger\n[Cost: %d]" / "Activate Electric Barrier [Cost: %d]"
	return Lang.prompt("attivare la trappola", "#37ef76ce" if kind == "flogger" else "#7214cf9f", cost)


func interact(player: Player) -> void:
	if state != State.IDLE or not gen_on or not door_open():
		return
	if player.points < cost:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-cost)
	Sfx.instance.play("buy_success")
	activate()


func activate() -> void:
	state = State.ACTIVE
	armed = kind != "electric"
	if kind == "electric":
		# TurnOn, then the pull ("zapperStart": the 30 s start), then "zapperOn"
		_timer = LEVER_TURN_ON[1] + ACTIVE_TIME
		_arm_at = ACTIVE_TIME - LEVER_PULL[1]
		_lever_play(LEVER_TURN_ON[0])
		if _lever and _lever.has_animation(LEVER_PULL[0]):
			_lever.queue(LEVER_PULL[0])
		if _lever and _lever.has_animation(LEVER_ACTIVE):
			_lever.queue(LEVER_ACTIVE)
	else:
		# TurnOn, then spin up: the 30 s run from "floggerStart", kills from the damager
		_timer = FLOG_TURN_ON + ACTIVE_TIME
		_arm_at = ACTIVE_TIME - FLOG_DAMAGER_AT
		armed = false
		_flog_started = false
		Sfx.instance.play_at(FLOG_SOUND_TURN_ON, use_point + Vector3.UP)


# Flogger sounds by the time since it was bought (ACTIVE)
func _flogger_sounds() -> void:
	var t := FLOG_TURN_ON + ACTIVE_TIME - _timer
	if not _flog_started and t >= FLOG_TURN_ON:
		_flog_started = true
		if t < FLOG_TURN_ON + 1.0:   # not when a saved game resumes mid-run
			Sfx.instance.play_at(FLOG_SOUND_START, pivot + Vector3.UP)
	if t >= FLOG_TURN_ON + FLOG_ENGINE_AT:
		_flog_loop(FLOG_LOOP_ENGINE, true)
	if t >= FLOG_TURN_ON + FLOG_SPIN_UP:
		_flog_loop(FLOG_LOOP_WHOOSH, true)


func _flog_loop(spec: String, on: bool) -> void:
	var em = _flog_loops.get(spec)
	if em == null:
		if not on:
			return
		em = AmbientEmitters.Emitter.make({"spec": spec, "range": 800, "attenuate": 1})
		add_child(em)
		em.global_position = pivot + Vector3.UP
		_flog_loops[spec] = em
	if on and not em.enabled:
		em.enable()
	elif not on and em.enabled:
		em.disable()


# the arcs come on ("zapperOn"): from now on the trap kills
func _arm() -> void:
	armed = true
	if kind == "electric":
		_start_fx()


# SetTrapActive (verruckt.lua 278-303, shinonuma.lua 676-686, derriese.lua 784-837):
# EnableRender(<trap>Effect<n>) and EnableSoundEmitter(<trap>Sound / Sound1 / Sound2).
# The effects are instances of a CIwSpecList of the effects group (tools/ent_fx.py):
# e29069ed -> model c5ea57f2 (Der Riese power/garage, 2.46 m), c5e4a13d -> fda76742
# (Der Riese lab, Shi No Numa huts, Verrueckt: 1.94 m), an upright card whose bolt
# texture fda76742 scrolls 32 texels a tick (material 43266a5b); on Der Riese and Shi No
# Numa they are level entities, on Verrueckt child entities of Trap1/Trap2. The sound
# emitters play traploop (bb630b36, range 800) like the ambient ones (AmbientEmitters).
func _start_fx() -> void:
	_fx = Node3D.new()
	add_child(_fx)
	_fx.top_level = true
	_fx.global_transform = Transform3D.IDENTITY
	for ef in effect_parts():
		var m := IwFx.make(ef[1], 0)
		_fx.add_child(m)
		m.global_transform = ef[0]
		if OS.get_cmdline_user_args().has("--trap-debug"):
			print("[trap] %s effect %s at %s in volume %s" % [entity, ef[1], (ef[0] as Transform3D).origin.snapped(Vector3(0.01, 0.01, 0.01)), contains(ef[0].origin + Vector3.UP * 0.5)])
	for se in sound_parts():
		var em := AmbientEmitters.Emitter.make(se[1])
		_fx.add_child(em)
		em.global_position = se[0]
		em.enable()


# [world transform, model] of the trap's "<trap>Effect<n>" entities
func effect_parts() -> Array:
	var out := []
	var data := IwFx.level_data(level.level_name)
	for i in range(1, 13):
		var n := "%sEffect%d" % [entity, i]
		var h := Sfx.iw_hash(n)
		if level.has_entity(n):
			var t: Dictionary = data.get("templates", {}).get(String(level.entity(n).get("hash", h)), {})
			if t.get("model", "") != "":
				out.append([Level.flag_transform(level.entity(n)["transform"]), t["model"]])
		elif data.get("nested", {}).has(h):
			var c: Dictionary = data["nested"][h]
			if c.get("model", "") != "":
				out.append([_child_transform(c), c["model"]])
	return out


# [world position, sound emitter fields] of "<trap>Sound", "<trap>Sound1", "<trap>Sound2"
func sound_parts() -> Array:
	var out := []
	var data := IwFx.level_data(level.level_name)
	var own: Array = level.entity(entity).get("sound_emitters", [])
	for suffix in ["Sound", "Sound1", "Sound2"]:
		var h := Sfx.iw_hash(entity + suffix)
		var e := level.entity(h) if level.has_entity(h) else level.entity(entity + suffix)
		if not e.is_empty():
			for se in e.get("sound_emitters", []):
				if not se.has("child"):
					out.append([Level._to_transform(e["transform"]).origin, se])
		elif data.get("nested", {}).has(h):
			for se in own:
				if String(se.get("child", "")) == h:
					out.append([_child_transform(data["nested"][h]).origin, se])
	return out


# a child entity of the trap (Verrueckt): its transform within the trap entity's
func _child_transform(c: Dictionary) -> Transform3D:
	return Level.flag_transform(level.entity(entity)["transform"]) * Level.flag_transform(c["transform"])


# "zapperEnd": arcs off, the switch goes back and holds for the 30 s cooldown
func _stop() -> void:
	state = State.COOLDOWN
	armed = false
	if kind == "electric":
		_timer = LEVER_BACK[1] + COOLDOWN + LEVER_TURN_OFF[1]
		_lever_play(LEVER_BACK[0])
		if _lever and _lever.has_animation(LEVER_COOL):
			_lever.queue(LEVER_COOL)
	else:
		# floggerEnd: spin down (still killing for FLOG_DAMAGER_END), then the cooldown
		_timer = FLOG_SPIN_DOWN + COOLDOWN + FLOGGER_TURN_OFF
		armed = true
		_flog_loop(FLOG_LOOP_WHOOSH, false)
		_flog_loop(FLOG_LOOP_ENGINE, false)
		Sfx.instance.play_at(FLOG_SOUND_STOP, pivot + Vector3.UP)
	_turned_off = false
	if _fx:
		_fx.queue_free()
		_fx = null


# ASM TurnOff, at the end of the cooldown: switch animation and its sound
func _turn_off() -> void:
	_turned_off = true
	if kind != "electric":
		Sfx.instance.play_at(TRAP_READY_SOUND, use_point + Vector3.UP)   # flogger TurnOff
		return
	_lever_play(LEVER_TURN_OFF[0])
	if _lever and _lever.has_animation(LEVER_READY):
		_lever.queue(LEVER_READY)
	Sfx.instance.play_at(TRAP_READY_SOUND, use_point + Vector3.UP)


func _physics_process(delta: float) -> void:
	if state == State.IDLE:
		return
	_timer -= delta
	if state == State.COOLDOWN:
		if not _turned_off and _timer <= (LEVER_TURN_OFF[1] if kind == "electric" else FLOGGER_TURN_OFF):
			_turn_off()
		if _timer <= 0.0:
			state = State.IDLE
		if armed and kind == "flogger":
			var down := FLOG_SPIN_DOWN + COOLDOWN + FLOGGER_TURN_OFF - _timer
			if _flogger:
				_flogger.rotate_y(delta * 2.6 * maxf(0.0, 1.0 - down / FLOG_SPIN_DOWN))
			if down >= FLOG_DAMAGER_END:
				armed = false   # floggerEndDamager
			else:
				_kill_inside(delta)
		return
	if _timer <= 0.0:
		_stop()
		return
	if kind == "flogger":
		_flogger_sounds()
	if not armed:
		if _timer <= _arm_at:
			_arm()
		return
	if _flogger:
		_flogger.rotate_y(delta * 2.6)
	_kill_inside(delta)


func _kill_inside(delta: float) -> void:
	_hurt_cd -= delta
	var game := level.get_parent() as Game
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Zombie and z.state != Zombie.State.DEAD and contains(z.global_position + Vector3.UP * 0.5):
			if game:
				game.kill_without_points(z)
			else:
				z.nuke_kill()
	if game and game.player and not game.player.dead and _hurt_cd <= 0.0 \
			and contains(game.player.global_position + Vector3.UP * 0.5):
		_hurt_cd = 1.0
		game.player.take_hit(PLAYER_DAMAGE)


func contains(p: Vector3) -> bool:
	if kind == "flogger":
		return Vector2(p.x - pivot.x, p.z - pivot.z).length() < FLOGGER_RADIUS and p.y > pivot.y - 2.0 and p.y < pivot.y + 2.0
	for v: AABB in volumes:
		if v.has_point(p):
			return true
	return false


# ------------------------------------------------------------------ save provider (save_game.gd)

func save_key() -> String:
	return "trap:" + entity


func save_state() -> Dictionary:
	return {"state": State.keys()[state], "timer": _timer}


# A running trap keeps running for the time it had left, a cooling one keeps cooling.
func load_state(d: Dictionary) -> void:
	var t := float(d.get("timer", 0.0))
	match String(d.get("state", "IDLE")):
		"ACTIVE":
			if t > 0.0:
				activate()
				_timer = t
		"COOLDOWN":
			if t > 0.0:
				state = State.COOLDOWN
				armed = false
				_turned_off = false
				_timer = t
				_lever_pose(LEVER_COOL)
