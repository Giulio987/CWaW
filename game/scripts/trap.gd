# Buyable trap (CActionBuyTrapSpec): the electric "zappers" of Verrückt, Shi No
# Numa's huts and Der Riese, and Shi No Numa's flogger. As in the level scripts
# (verruckt.lua / derriese.lua / shinonuma.lua): bought at its switch, it runs
# for 30 s ("zapperStart" -> Timeout(30000, "<trap>End")), killing every zombie
# and dog that walks into it and hurting the player; then it cools down. On maps
# with a generator the traps get "genTurnOn" from TurnOnGenerator: power first.
#
# Kill volume: the trap's "<trap>Effect<n>" sub-entities mark the electric arcs
# (Der Riese, Shi No Numa); Verrückt has none, so its two fences are found among
# the entity's collider boxes + child offsets by checking which placement fits a
# doorway in the level geometry. The flogger kills in a circle around its pivot.
class_name Trap
extends Node3D

const ACTIVE_TIME := 30.0     # Lua: Timeout(30000, "<trap>End")
const COOLDOWN := 40.0
const USE_RANGE := 1.9
const PLAYER_DAMAGE := 40.0   # per second spent in the trap
const LEVER_MODEL := "c110c7c0"
const LEVER_PULL := "223b149d"
const LEVER_RESET := "726310c1"
const FLOGGER_MODEL := "b373d4cb"
const FLOGGER_RADIUS := 3.4

enum State { IDLE, ACTIVE, COOLDOWN }

var level: Level
var entity := ""
var cost := 1000
var kind := "electric"        # or "flogger"
var state := State.IDLE
var volumes := []             # world AABBs that kill (electric)
var arcs := []                # [from, to] pairs of arc end points (electric)
var use_point := Vector3.ZERO
var pivot := Vector3.ZERO     # flogger centre
var _timer := 0.0
var _hurt_cd := 0.0
var _lever: AnimationPlayer
var _flogger: Node3D
var _fx: Node3D
var _bolts: MeshInstance3D
var _bolt_timer := 0.0
var _loop: AudioStreamPlayer3D
var _lights := []


func setup(level_: Level, entity_: String) -> void:
	level = level_
	entity = entity_
	var e: Dictionary = level.entities[entity]
	cost = int(e.get("params", {}).get("cost", 1000))
	kind = "flogger" if "flogger" in entity.to_lower() else "electric"
	var root := level.entity_transform(entity)
	global_transform = root
	var cols: Array = e.get("colliders", [])
	if not cols.is_empty():
		use_point = root * _box_centre(cols[0])
	else:
		use_point = root.origin
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
	var rest := _closest_pose(_lever, LEVER_PULL)
	if rest != "":
		_lever.play(rest)
		_lever.seek(0.0, true)
		_lever.pause()


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
	_make_arcs()


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
	_make_arcs()
	if OS.get_cmdline_user_args().has("--trap-debug"):
		print("[trap] %s volumes %s" % [entity, volumes])


func _doorway_score(space: PhysicsDirectSpaceState3D, box: AABB) -> float:
	var c := box.get_center()
	var bottom := box.position.y
	# a floor right under the fence
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, bottom + 1.0, c.z), Vector3(c.x, bottom - 1.0, c.z), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or absf((hit["position"] as Vector3).y - bottom) > 0.4:
		return INF
	var along := Vector3.RIGHT if box.size.x >= box.size.z else Vector3.BACK
	var half := (box.size.x if along == Vector3.RIGHT else box.size.z) / 2.0
	var at := Vector3(c.x, bottom + 1.0, c.z)
	var score := 0.0
	for dir: Vector3 in [along, -along]:
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + dir * (half + 1.5), 1))
		score += 1.5 if r.is_empty() else absf((r["position"] - at).length() - half)
	# open on both sides of the fence (it is a passage)
	var side := along.cross(Vector3.UP)
	for dir: Vector3 in [side, -side]:
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + dir * 1.2, 1))
		if not r.is_empty():
			score += 1.0
	return score


func _make_arcs() -> void:
	arcs.clear()
	for v: AABB in volumes:
		var along_x := v.size.x >= v.size.z
		var n := maxi(2, int((v.size.x if along_x else v.size.z) / 1.1))
		for i in n:
			var t := (i + 0.5) / n
			var p := v.position + Vector3(v.size.x * (t if along_x else 0.5), 0.0, v.size.z * (0.5 if along_x else t))
			arcs.append([p + Vector3.UP * 0.25, p + Vector3.UP * 2.3])


# ------------------------------------------------------------------ interaction

func usable_from(p: Vector3) -> bool:
	return Vector2(p.x - use_point.x, p.z - use_point.z).length() < USE_RANGE and absf(p.y - use_point.y) < 2.0


func prompt(_player: Player) -> String:
	if not level.power_on:
		return "Serve la corrente"
	match state:
		State.ACTIVE:
			return ""
		State.COOLDOWN:
			return "Trappola in ricarica"
	return "Premi E per attivare la trappola [%d]" % cost


func interact(player: Player) -> void:
	if state != State.IDLE or not level.power_on:
		return
	if player.points < cost:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-cost)
	Sfx.instance.play("buy_success")
	activate()


func activate() -> void:
	state = State.ACTIVE
	_timer = ACTIVE_TIME
	if _lever and _lever.has_animation(LEVER_PULL):
		_lever.play(LEVER_PULL)
	if kind == "electric":
		_start_fx()


func _start_fx() -> void:
	_fx = Node3D.new()
	add_child(_fx)
	_fx.top_level = true
	_fx.global_transform = Transform3D.IDENTITY
	_bolts = MeshInstance3D.new()
	_bolts.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.65, 0.8, 1.0)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolts.material_override = mat
	_bolts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(_bolts)
	for v: AABB in volumes:
		var l := OmniLight3D.new()
		l.light_color = Color(0.5, 0.7, 1.0)
		l.omni_range = maxf(v.size.x, v.size.z) * 0.8 + 2.0
		l.position = v.get_center()
		_fx.add_child(l)
		_lights.append(l)
	if not volumes.is_empty():
		_loop = AudioStreamPlayer3D.new()
		_loop.stream = Sfx.instance._stream(Sfx.iw_hash("traploop"))
		_loop.unit_size = 6.0
		_loop.max_distance = 35.0
		_fx.add_child(_loop)
		_loop.global_position = (volumes[0] as AABB).get_center()
		_loop.finished.connect(func(): if state == State.ACTIVE: _loop.play())
		if _loop.stream:
			_loop.play()


func _stop() -> void:
	state = State.COOLDOWN
	_timer = COOLDOWN
	if _fx:
		_fx.queue_free()
		_fx = null
		_lights.clear()
	if kind == "electric" and not volumes.is_empty():
		Sfx.instance.play_at(Sfx.iw_hash("trapend"), (volumes[0] as AABB).get_center())
	if _lever and _lever.has_animation(LEVER_RESET):
		_lever.play(LEVER_RESET)


func _physics_process(delta: float) -> void:
	if state == State.IDLE:
		return
	_timer -= delta
	if state == State.COOLDOWN:
		if _timer <= 0.0:
			state = State.IDLE
		return
	if _timer <= 0.0:
		_stop()
		return
	if _flogger:
		_flogger.rotate_y(delta * 2.6)
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


func _process(delta: float) -> void:
	if state != State.ACTIVE or _bolts == null:
		return
	_bolt_timer -= delta
	if _bolt_timer > 0.0:
		return
	_bolt_timer = 0.05
	for l in _lights:
		l.light_energy = randf_range(1.5, 4.0)
	# jagged arcs between floor and top of the fence, redrawn every few frames
	var im := _bolts.mesh as ImmediateMesh
	im.clear_surfaces()
	if arcs.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair in arcs:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var prev := a
		for k in range(1, 9):
			var p := a.lerp(b, k / 8.0)
			if k < 8:
				p += Vector3(randf_range(-0.18, 0.18), 0, randf_range(-0.18, 0.18))
			im.surface_add_vertex(prev)
			im.surface_add_vertex(p)
			prev = p
	im.surface_end()
