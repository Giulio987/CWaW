# Checks for route_shortcuts.gd (prints OK/FAIL, screenshots in analysis/preview):
#   -- derriese --shortcut-test [i,j,...]   a zombie chasing the player from the entry side
#   -- shinonuma --shortcut-test              of each CRouteShortcut takes it (jump down /
#                                             climb up) and ends at the exit height
extends Node

var game: Game
var fails := 0
var _cam: Camera3D
const LifecycleTests := preload("res://scripts/lifecycle_tests.gd")


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/shortcut_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	var i := args.find("--shortcut-test")
	var only := []
	if i + 1 < args.size() and not args[i + 1].begins_with("--"):
		for s in args[i + 1].split(","):
			only.append(int(s))
	t._run(only)


func _check(tag: String, ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [tag, "OK" if ok else "FAIL", what])
	fails += int(not ok)


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 400.0
		game.add_child(_cam)
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	_cam.make_current()
	for k in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))
	_cam.clear_current(true)


# the largest horizontal invisible slab: a grenade thrown up from under it bounces
# back, and the bullets' ray mask stops on it
func _blocker_check(tag: String) -> void:
	var best: CollisionShape3D = null
	for n in get_tree().get_nodes_in_group(ShotBlockers.GROUP):
		var cs := (n as Node).get_child(0) as CollisionShape3D
		var sz := (cs.shape as BoxShape3D).size
		if sz.y < 1.0 and (best == null or sz.x * sz.z > (best.shape as BoxShape3D).size.x * (best.shape as BoxShape3D).size.z):
			best = cs
	if best == null:
		return
	var c := best.global_position
	var bottom := c.y - (best.shape as BoxShape3D).size.y * 0.5
	var g := Grenade.spawn(game, Vector3(c.x, bottom - 1.0, c.z), Vector3(0.5, 9.0, 0.0), 2.5, game.player)
	var top := -INF
	for k in 90:
		await get_tree().physics_frame
		if is_instance_valid(g):
			top = maxf(top, g.global_position.y)
	if is_instance_valid(g):
		g.queue_free()
	_check(tag, top < bottom, "grenade thrown up under the slab %s (bottom y %.2f): highest y %.2f" % [best.get_parent().name, bottom, top])
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, bottom - 2.0, c.z), Vector3(c.x, bottom + 5.0, c.z), 1 | 2 | ShotBlockers.LAYER)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	_check(tag, not hit.is_empty() and (hit["collider"] as Node).is_in_group(ShotBlockers.GROUP), "a bullet ray up into it stops on the invisible wall")


# a camera spot beside the traversal (either side, 2-5 m) with a clear view of `at`
func _side_cam(at: Vector3, dir: Vector3) -> Vector3:
	var side := dir.cross(Vector3.UP).normalized()
	var space := game.get_world_3d().direct_space_state
	for d in [4.5, 3.5, 2.5, 1.8]:
		for sgn in [1.0, -1.0]:
			for back in [0.0, -1.5, 1.5]:
				var c: Vector3 = at + side * d * sgn + dir * back + Vector3.UP * 0.4
				var q := PhysicsRayQueryParameters3D.create(at, c, 1)
				if space.intersect_ray(q).is_empty():
					return c
	return at + side * 2.0 + Vector3.UP * 0.4


func _run(only: Array) -> void:
	const TAG := "shortcut"
	var lv := game.level
	await lv.wait_navigation()
	var links := lv.get_children().filter(func(n): return n is NavigationLink3D and n.has_meta("input"))
	_check(TAG, links.size() == {"derriese": 11, "shinonuma": 1}.get(lv.level_name, 0), "%d route shortcut links" % links.size())
	var blockers := lv.get_tree().get_nodes_in_group(ShotBlockers.GROUP).size()
	_check(TAG, blockers == {"nacht": 9, "verruckt": 39, "shinonuma": 9, "derriese": 54}.get(lv.level_name, -1), "%d invisible walls" % blockers)
	if blockers > 0:
		await _blocker_check(TAG)
	var map := lv.get_world_3d().navigation_map
	for k in 10:
		await get_tree().physics_frame   # the map syncs the new links
	var p := game.player
	p.health = 1e6
	for i in links.size():
		if not only.is_empty() and not i in only:
			continue
		var link: NavigationLink3D = links[i]
		var a := link.to_global(link.start_position)
		var b := link.to_global(link.end_position)
		var na := NavigationServer3D.map_get_closest_point(map, a)
		var nb := NavigationServer3D.map_get_closest_point(map, b)
		var name := "%s %s %s" % [link.name, link.get_meta("input"), "up" if b.y > a.y else "down"]
		print("[shortcut] %s: entry %s (navmesh %.2f m) exit %s (navmesh %.2f m)" % [name, a.snapped(Vector3.ONE * 0.01), na.distance_to(a), b.snapped(Vector3.ONE * 0.01), nb.distance_to(b)])
		if na.distance_to(a) > 1.0 or nb.distance_to(b) > 1.0:
			print("[shortcut] %s: not on the baked navmesh, unconnected (skipped)" % name)
			continue
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var zpos := NavigationServer3D.map_get_closest_point(map, a - dir * 2.0)
		var ppos := NavigationServer3D.map_get_closest_point(map, b + dir * 2.5)
		p.global_position = ppos + Vector3.UP * 0.1
		p.velocity = Vector3.ZERO
		var z: Zombie = LifecycleTests._spawn(game)
		z.max_health = 1e6
		z.health = 1e6
		z.global_position = zpos
		z.state = Zombie.State.CHASE
		var used := RouteShortcuts.used
		var t := 0.0
		var shot := false
		var t_trav := -1.0
		while t < 14.0 and is_instance_valid(z):
			await get_tree().physics_frame
			t += 1.0 / 60.0
			p.global_position = ppos + Vector3.UP * 0.1   # stay put
			if z.traversing and t_trav < 0.0:
				t_trav = t
			if z.traversing and not shot and t - t_trav > (0.45 if b.y < a.y else 2.2):
				shot = true
				await _shot("shortcut_%d_side" % i, _side_cam(z.global_position + Vector3.UP, dir), z.global_position + Vector3.UP)
			if RouteShortcuts.used > used and not z.traversing:
				break
		var ok := RouteShortcuts.used > used and is_instance_valid(z) and absf(z.global_position.y - b.y) < 0.5
		_check(TAG, ok, "%s: used %s, zombie at %s after %.1f s" % [name, RouteShortcuts.used > used, z.global_position.snapped(Vector3.ONE * 0.01) if is_instance_valid(z) else "-", t])
		if is_instance_valid(z):
			z.queue_free()
		await get_tree().physics_frame
	print("[shortcut] %s" % ("ALL OK" if fails == 0 else "%d FAIL" % fails))
	get_tree().quit()
