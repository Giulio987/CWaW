# Der Riese checks (bridge.gd, flytrap.gd), screenshots in analysis/preview:
#   -- derriese --bridge-test     gap closed before power, bridge lowers with the power, walk across
#   -- derriese --flytrap-test    shoot the fly trap (upgraded gun), ring, items, found voices
class_name DerrieseTests
extends Node

var game: Game
var fails := 0
var _cam: Camera3D


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t := DerrieseTests.new()
	t.game = game_
	parent.add_child(t)
	if args.has("--bridge-test"):
		t._bridge_test()
	elif args.has("--flytrap-test"):
		t._flytrap_test()


func _check(tag: String, ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [tag, "OK" if ok else "FAIL", what])
	fails += int(not ok)


# Screenshot from a free camera at `from` looking at `at` (the player's camera otherwise).
func _shot(name: String, from := Vector3.INF, at := Vector3.ZERO) -> void:
	if from != Vector3.INF:
		if _cam == null:
			_cam = Camera3D.new()
			_cam.far = 400.0
			game.add_child(_cam)
		_cam.global_position = from
		_cam.look_at(at, Vector3.UP)
		_cam.make_current()
	elif _cam:
		_cam.clear_current(true)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))


# Walk the player along +dir for `secs`; returns where it ended.
func _walk(p: Player, dir: Vector3, secs: float) -> Vector3:
	var t := 0.0
	p.rotation.y = atan2(-dir.x, -dir.z)
	while t < secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		p.health = 1e6
		p.move_input = Vector2(0, -1)
	p.move_input = Vector2.ZERO
	return p.global_position


func _views(prefix: String, c: Vector3) -> void:
	await _shot(prefix + "_side", c + Vector3(0, 3.0, 9.0), c)
	await _shot(prefix + "_end", c + Vector3(9.0, 3.5, 1.0), c)
	await _shot(prefix + "_top", c + Vector3(0.0, 14.0, 0.05), c)
	await _shot(prefix + "_low", c + Vector3(0.0, 1.5, 7.0), c)


func _bridge_test() -> void:
	const TAG := "bridge"
	await game.level.wait_navigation()
	game.set_process(false)
	var lv := game.level
	var p := game.player
	p.health = 1e6
	var br: Bridge = lv.nav_region.get_node_or_null("Bridge")
	_check(TAG, br != null and not br.lowered, "bridge built, raised before the power")
	if br == null:
		get_tree().quit()
		return
	var a := Bridge._v(0)   # deck corners: x -12 (high end) .. -3.5 (low end)
	var c := (Bridge._v(0) + Bridge._v(2)) * 0.5
	await _views("bridge_up", c)
	# gap closed: from the high end walk towards the low end
	p.global_position = Vector3(a.x - 1.2, a.y + 0.3, c.z)
	p.velocity = Vector3.ZERO
	for i in 10:
		await get_tree().physics_frame
	var start := p.global_position
	var end := await _walk(p, Vector3.RIGHT, 2.5)
	_check(TAG, end.x < a.x + 0.3 and end.y > a.y - 1.0, "raised bridge: the gap is closed (from %s to %s)" % [start.snapped(Vector3.ONE * 0.01), end.snapped(Vector3.ONE * 0.01)])
	# power: the halves come down over 4.6 s, with steam
	lv.turn_on_power()
	await get_tree().create_timer(2.0).timeout
	await _shot("bridge_lowering", c + Vector3(0, 3.0, 9.0), c)
	_check(TAG, not br.lowered, "still lowering after 2 s")
	await get_tree().create_timer(3.0).timeout
	_check(TAG, br.lowered, "bridgeClosed after %.1f s" % Bridge.LOWER_TIME)
	await get_tree().create_timer(0.5).timeout
	await _views("bridge_down", c)
	await _views_at_angles(c)
	# walk across, high end to low end
	await game.level.wait_navigation()
	p.global_position = Vector3(a.x - 1.2, a.y + 0.3, c.z)
	p.velocity = Vector3.ZERO
	for i in 10:
		await get_tree().physics_frame
	start = p.global_position
	end = await _walk(p, Vector3.RIGHT, 3.0)
	_check(TAG, end.x > Bridge._v(2).x - 1.5 and end.y > Bridge._v(2).y - 0.6, "walked across the bridge (from %s to %s)" % [start.snapped(Vector3.ONE * 0.01), end.snapped(Vector3.ONE * 0.01)])
	await _shot("bridge_walk")
	# off the side: the long edges are walls
	p.global_position = c + Vector3.UP * 0.4
	p.velocity = Vector3.ZERO
	for i in 5:
		await get_tree().physics_frame
	end = await _walk(p, Vector3.FORWARD, 2.0)
	_check(TAG, end.y > c.y - 0.6 and absf(end.z - c.z) < 2.2, "cannot fall off the side (at %s)" % end.snapped(Vector3.ONE * 0.01))
	print("[%s] %s (%d failures)" % [TAG, "OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _views_at_angles(c: Vector3) -> void:
	for deg in [45, 135, 225, 315]:
		var off := Vector3(9.0, 4.0, 0).rotated(Vector3.UP, deg_to_rad(deg))
		await _shot("bridge_down_%d" % deg, c + off, c)


func _flytrap_test() -> void:
	const TAG := "flytrap"
	await game.level.wait_navigation()
	game.set_process(false)
	var p := game.player
	p.health = 1e6
	var ft: FlyTrap = game.get_node_or_null("FlyTrap")
	_check(TAG, ft != null and ft.triggers.size() == 4 and ft.items.size() == 3, "fly trap built: %d triggers, items %s" % [ft.triggers.size() if ft else 0, ft.items.values().map(func(a): return a.size()) if ft else []])
	if ft == null:
		get_tree().quit()
		return
	_check(TAG, ft.items.values().all(func(a): return a.all(func(o): return not o.visible)), "items hidden at the start")
	var trap_at := ft.centre_of(FlyTrap.TRIGGER)
	var ring_at: Vector3 = ft._ring_base.origin
	# stand 4 m away on the floor, facing the trigger
	var from := _stand_near(trap_at)
	p.global_position = from
	p.velocity = Vector3.ZERO
	_face(p, trap_at)
	await _shot("flytrap_trigger")
	await _shot("flytrap_trigger_side", trap_at + Vector3(3.0, 1.0, 0.5), trap_at)
	# a normal gun does nothing
	p.give_weapon("thompson")
	await _fire_at(p, trap_at)
	_check(TAG, not ft.activated, "an ordinary gun does not set it off")
	p.weapon()["upgraded"] = true
	await _fire_at(p, trap_at)
	_check(TAG, ft.activated, "a Pack-a-Punched gun sets it off")
	await get_tree().create_timer(3.0).timeout
	_check(TAG, ft._ring.visible and ft.emitters["flytrapSoundHit"].enabled, "ring rising, hit sound on")
	await _shot("flytrap_ring", ring_at + Vector3(0, 4.0, 10.0), ring_at + Vector3.UP * 1.0)
	await get_tree().create_timer(3.0).timeout
	_check(TAG, ft.emitters["flytrapSoundVox1"].playing() or ft.emitters["flytrapSoundVox1"].enabled, "Vox1 at 5 s")
	await get_tree().create_timer(9.0).timeout
	_check(TAG, not ft._ring.visible, "ring hidden at 14.2 s")
	await get_tree().create_timer(1.5).timeout
	_check(TAG, "items" in ft.events and ft.items.values().all(func(a): return a.all(func(o): return o.visible)), "items appear at 15.2 s")
	for n in [1, 2, 3]:
		var objs: Array = ft.items[n]
		var at: Vector3 = objs[0].global_position
		await _shot("flytrap_item%d" % n, at + Vector3(1.2, 0.6, 1.2), at)
		await _shot("flytrap_item%d_b" % n, at + Vector3(-1.2, 0.8, -0.6), at)
		var tn := "flyTrapItem%dTrigger" % n
		var stand := _stand_near(ft.centre_of(tn))
		p.global_position = stand
		p.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await _fire_at(p, ft.centre_of(tn))
		_check(TAG, tn in ft.events and not objs[0].visible and ft.found == n, "%s shot from %.1f m: item hidden, found %d" % [tn, stand.distance_to(ft.centre_of(tn)), ft.found])
	print("[%s] %s (%d failures)" % [TAG, "OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _face(p: Player, at: Vector3) -> void:
	var to := at - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	var cam: Camera3D = p._camera
	var d := at - cam.global_position
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


# A floor spot 2-5 m from `at` with a clear line of sight to it.
func _stand_near(at: Vector3) -> Vector3:
	var space := game.get_world_3d().direct_space_state
	for r in [3.0, 2.0, 4.5]:
		for k in 16:
			var dir := Vector3(1, 0, 0).rotated(Vector3.UP, k * TAU / 16.0)
			var spot: Vector3 = at + dir * r
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.5, spot + Vector3.DOWN * 4.0, 1))
			if down.is_empty():
				continue
			var feet: Vector3 = down["position"]
			if absf(feet.y - at.y) > 3.0:
				continue
			var eye := feet + Vector3.UP * 1.6
			var los := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, at, 1))
			if los.is_empty():
				return feet + Vector3.UP * 0.1
	return at + Vector3(2, 0, 0)


func _fire_at(p: Player, at: Vector3) -> void:
	for i in 3:
		await get_tree().physics_frame
	_face(p, at)
	await get_tree().physics_frame
	var from: Vector3 = p._camera.global_position
	RadioEggs.bullet(p, from, from + (at - from).normalized() * ((at - from).length() + 1.0))
	await get_tree().physics_frame
