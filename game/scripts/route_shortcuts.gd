# Zombie route shortcuts (CRouteShortcut, tools/route_shortcuts.py -> shortcuts.json):
# one-way jumps down from ledges and climbs up walls the walking navmesh does not
# link (Der Riese 11, Shi No Numa 1). Each one names the ASM input the route requester
# sets on the zombie when its route uses it (the "reaction" states of the zombie ASM
# f402afc2 / 2c8a758b are these traversals, not stuns or burning):
#   fad7bdba..bd -> states 46-49: jump down, body 31de2d9f/31de2da0/31de2da1/31de2da2
#                   (1.13 s; root partners drop 2.52 / 1.83 / 3.61 / 4.85 m, 0.89 m forward)
#   07a4bba6     -> state 50 (crawler 51): climb up, aa8af536 (4.83 s; partner 9d210e9c
#                   rises 2.51 m and moves 1.15 m forward)
#   83b8f639     -> states 40-42 (Shi No Numa, zombiesAnimsJap ASM d06d3216): walk
#                   fbe7b3da at 0.8 for 1.2 s, fall (41, fab4136a) until the target
#                   height is reached (input reachedTrgHt), land (42, 0 s)
# Dogs: their ASM has no animation for 46-51, so only zombies use the links
# (navigation layer NAV_LAYER, zombie.gd's agent only).
class_name RouteShortcuts

const NAV_LAYER := 2
const DROP_ANIMS := {"fad7bdba": "31de2d9f", "fad7bdbb": "31de2da0", "fad7bdbc": "31de2da1", "fad7bdbd": "31de2da2"}
const CLIMB_INPUT := "07a4bba6"
const CLIMB_ANIM := "aa8af536"
const JUMP_INPUT := "83b8f639"
const JUMP_WALK := "fbe7b3da"
const JUMP_WALK_TIME := 1.2      # state 40: 1199 ms
const JUMP_WALK_RATE := 0.8
const JUMP_FALL := "fab4136a"
const GRAVITY := 10.0            # WorldColliderGravity 4000 units/s²
# root-motion keyframes [time, forward fraction, height fraction] of the partners
const DROP_CURVE := [[0.0, 0.0, 0.0], [0.2, 0.0, 0.0], [0.333, 0.56, 0.0], [0.533, 1.0, 0.5],
	[0.667, 1.0, 1.0], [1.133, 1.0, 1.0]]
const CLIMB_CURVE := [[0.0, 0.0, 0.0], [0.8, 0.0, 0.0], [1.0, 0.076, 0.306], [1.8, 0.076, 0.306],
	[1.9, 0.076, 0.509], [2.0, 0.076, 0.596], [2.2, 0.076, 0.683], [2.4, 0.076, 0.829],
	[2.5, 0.076, 0.894], [2.6, 0.579, 0.921], [2.7, 0.738, 0.921], [3.0, 0.795, 0.921],
	[3.3, 0.83, 0.921], [3.4, 0.983, 0.921], [3.5, 1.0, 0.922], [4.0, 1.0, 0.952],
	[4.3, 1.0, 0.977], [4.6, 1.0, 0.995], [4.833, 1.0, 1.0]]

static var used := 0   # traversals started (tests)


static func build(level: Level) -> int:
	var path := "res://assets/levels/%s/shortcuts.json" % level.level_name
	if not FileAccess.file_exists(path):
		return 0
	var n := 0
	# Der Riese 0018e648/649 (jump down from / climb up to the ledge at y 3.2 by -1, -17):
	# the baked navmesh has no floor on that ledge (nearest 1.2-1.4 m away, the floor below),
	# so with the default 1 m link connection radius they stay unconnected, on purpose: a
	# wider radius would make zombies pop 1.4 m up from the floor below to the entry point.
	for s in JSON.parse_string(FileAccess.get_file_as_string(path))["shortcuts"]:
		var inp: String = s["input"]
		if not (DROP_ANIMS.has(inp) or inp == CLIMB_INPUT or inp == JUMP_INPUT):
			continue
		var link := NavigationLink3D.new()
		link.name = "RouteShortcut_%s" % s["name"]
		link.bidirectional = false
		link.navigation_layers = NAV_LAYER
		link.set_meta("input", inp)
		level.add_child(link)
		link.global_position = Vector3.ZERO
		link.start_position = Vector3(s["from"][0], s["from"][1], s["from"][2])
		link.end_position = Vector3(s["to"][0], s["to"][1], s["to"][2])
		n += 1
	return n


# NavigationAgent3D.link_reached of a zombie: play the traversal and carry the body from
# the entry to the exit point along the animation's root motion.
static func traverse(z: Zombie, details: Dictionary) -> void:
	var link := details.get("owner") as NavigationLink3D
	if link == null or not link.has_meta("input") or z.traversing:
		return
	if not z.state in [Zombie.State.CHASE, Zombie.State.TO_WINDOW] or z.get("_dropping"):
		return
	var inp: String = link.get_meta("input")
	var a: Vector3 = link.to_global(link.start_position)
	var b: Vector3 = link.to_global(link.end_position)
	var anim_player: AnimationPlayer = z.get("_anim")
	var anim := ""
	var curve := []
	var dur := 0.0
	if inp == JUMP_INPUT:
		anim = JUMP_WALK
	elif inp == CLIMB_INPUT:
		anim = CLIMB_ANIM
		curve = CLIMB_CURVE
	else:
		anim = Zombie.CRAWL if z.crawler else String(DROP_ANIMS[inp])
		curve = DROP_CURVE
	if not anim_player.has_animation(anim):
		return
	used += 1
	z.traversing = true
	z.call("_end_unstick")
	z.velocity = Vector3.ZERO
	z.collision_mask = 0
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length() > 0.05:
		z.rotation.y = atan2(flat.x, flat.z)
		z.set("_heading", z.rotation.y)
	z.global_position = a
	var tw := z.create_tween()
	if inp == JUMP_INPUT:
		# state 40: walk to the edge, 41: fall to the exit height, 42: land (0 s)
		anim_player.play(anim, 0.15, JUMP_WALK_RATE)
		var walk := minf(float(Zombie.WALKS.get(JUMP_WALK, 0.96)) * JUMP_WALK_RATE * JUMP_WALK_TIME, flat.length() * 0.5)
		var edge := a + flat.normalized() * walk
		tw.tween_method(func(t: float): _step(z, tw, a.lerp(edge, t)), 0.0, 1.0, JUMP_WALK_TIME)
		tw.tween_callback(func():
			if z.state != Zombie.State.DEAD:
				anim_player.get_animation(JUMP_FALL).loop_mode = Animation.LOOP_LINEAR
				anim_player.play(JUMP_FALL, 0.1))
		var fall_t := sqrt(2.0 * maxf(edge.y - b.y, 0.1) / GRAVITY)
		tw.tween_method(func(t: float):
			var p := edge.lerp(b, t)
			p.y = edge.y - 0.5 * GRAVITY * pow(t * fall_t, 2.0)
			_step(z, tw, Vector3(p.x, maxf(p.y, b.y), p.z)), 0.0, 1.0, fall_t)
	else:
		var al := anim_player.get_animation(anim)
		al.loop_mode = Animation.LOOP_NONE if not z.crawler else Animation.LOOP_LINEAR
		anim_player.play(anim, 0.15)
		dur = curve[-1][0]
		tw.tween_method(func(t: float): _step(z, tw, _along(curve, t, a, b)), 0.0, dur, dur)
	tw.finished.connect(func(): _finish(z))


# position at time t of a [time, forward, height] keyframe table, a -> b
static func _along(curve: Array, t: float, a: Vector3, b: Vector3) -> Vector3:
	var f := 1.0
	var h := 1.0
	for i in range(1, curve.size()):
		if t <= curve[i][0]:
			var k: float = inverse_lerp(curve[i - 1][0], curve[i][0], t)
			f = lerpf(curve[i - 1][1], curve[i][1], k)
			h = lerpf(curve[i - 1][2], curve[i][2], k)
			break
	var p := a + Vector3(b.x - a.x, 0.0, b.z - a.z) * f
	p.y = lerpf(a.y, b.y, h)
	return p


static func _step(z: Zombie, tw: Tween, p: Vector3) -> void:
	if not is_instance_valid(z):
		return
	if z.state == Zombie.State.DEAD:
		# killed on the way: the body drops straight to the floor below
		tw.kill()
		z.traversing = false
		var q := PhysicsRayQueryParameters3D.create(z.global_position + Vector3.UP * 0.3, z.global_position + Vector3.DOWN * 8.0, 1 | Level.NAV_FLOOR_LAYER)
		var hit := z.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var y: float = (hit["position"] as Vector3).y
			z.create_tween().tween_property(z, "global_position:y", y, sqrt(2.0 * maxf(z.global_position.y - y, 0.0) / GRAVITY))
		return
	z.global_position = p


static func _finish(z: Zombie) -> void:
	if not is_instance_valid(z):
		return
	z.traversing = false
	if z.state == Zombie.State.DEAD:
		return
	z.collision_mask = 1 | 4 | Level.NAV_FLOOR_LAYER
	z.set("_stall", 0.0)
	z.set("_best_dist", INF)
	var agent: NavigationAgent3D = z.get("_agent")
	agent.target_position = agent.target_position   # path again from the exit
	z.call("_play", z.move_anim, 0.2)
