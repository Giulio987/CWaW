# Entry point. Command line: -- [level] [--autotest seconds]
extends Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level := ""
	for a in args:
		# only real level names count; anything else (option values) is ignored
		if DirAccess.dir_exists_absolute("res://assets/levels/" + a) and a != "":
			level = a
	if level == "":
		_show_menu(args.has("--menu-shot"))
		return
	_start(level, args)


func _show_menu(screenshot: bool) -> void:
	var menu := Menu.new()
	add_child(menu)
	menu.play.connect(func(l: String):
		menu.queue_free()
		_start(l, PackedStringArray()))
	if screenshot:
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/menu.png"))
		get_tree().quit()


func _start(level: String, args: PackedStringArray) -> void:
	var game := Game.new()
	add_child(game)
	game.start(level)
	var look := args.find("--look")
	if look >= 0:
		_look_shots(game, args[look + 1].split(","))
	if args.has("--stairs-test"):
		_stairs_test(game)
	if args.has("--box-test"):
		_box_test(game)
	if args.has("--knife-test"):
		_knife_test(game)
	if args.has("--spin"):
		_spin_shots(game)
	var shots := args.find("--shots")
	if shots >= 0:
		_weapon_shots(game, args[shots + 1].split(","))
	var i := args.find("--autotest")
	if i >= 0:
		var t := AutoTest.new()
		t.duration = float(args[i + 1]) if args.size() > i + 1 else 60.0
		t.game = game
		add_child(t)


# Screenshot each listed weapon held in first person: -- nacht --shots colt45,kar98
func _weapon_shots(game: Game, names: PackedStringArray) -> void:
	for i in 6:
		await get_tree().physics_frame
	for n in names:
		if n.begins_with("swing="):
			# swing=<arms anim>: 5 frames of one knife slash with that animation
			game.player.melee()
			for f in 5:
				await get_tree().create_timer(0.075).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/swing_%s_%d.png" % [n.get_slice("=", 1), f]))
			await get_tree().create_timer(1.0).timeout
			continue
		if n.begins_with("knife"):
			# knife@0.2 = mid-swing screenshot 0.2 s after the slash starts
			game.player.melee()
			await get_tree().create_timer(float(n.get_slice("@", 1)) if "@" in n else 0.2).timeout
		else:
			game.player.give_weapon(n)
			for i in 10:
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/wpn_%s.png" % n.replace("@", "_")))
	get_tree().quit()


# Screenshot entities from 3 m away on the player's side: -- nacht --look startroomZombieWindow1,DoorTrigger
func _look_shots(game: Game, names: PackedStringArray) -> void:
	for i in 6:
		await get_tree().physics_frame
	for spec in names:
		# name@deg: orbit the camera that many degrees around the target (side views)
		var n := spec.get_slice("@", 0)
		var orbit := deg_to_rad(float(spec.get_slice("@", 1))) if "@" in spec else 0.0
		var target := game.level.entity_transform(n).origin + Vector3.UP * 1.0
		var from := game.level.player_spawn.origin
		for w in game.level.windows:
			if String(w.name).to_lower() == n.to_lower():
				from = w.global_position + (w.inside - w.global_position).normalized() * 3.0
		var dir := (target - from)
		dir.y = 0
		dir = dir.rotated(Vector3.UP, orbit)
		from = target - dir.normalized() * 3.0
		game.player.global_position = Vector3(from.x, target.y - 1.0, from.z)
		game.player.rotation.y = atan2(-dir.x, -dir.z)
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/look_%s.png" % spec.replace("@", "_")))
		if OS.get_cmdline_user_args().has("--pick"):
			var cam := get_viewport().get_camera_3d()
			var size := get_viewport().get_visible_rect().size
			for fx in [0.05, 0.15, 0.3, 0.5]:
				var sp := Vector2(size.x * fx, size.y * 0.4)
				var q := PhysicsRayQueryParameters3D.create(cam.project_ray_origin(sp), cam.project_ray_origin(sp) + cam.project_ray_normal(sp) * 100.0)
				q.collide_with_areas = false
				var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
				var path := "none"
				if not hit.is_empty():
					var node: Node = hit["collider"]
					path = "%s <- %s <- %s" % [node.get_parent().name, node.get_parent().get_parent().name, node.get_parent().get_parent().get_parent().name]
				print("[pick] %s x=%.2f -> %s dist=%.1f" % [spec, fx, path, -1.0 if hit.is_empty() else cam.global_position.distance_to(hit["position"])])
	get_tree().quit()


# Four screenshots turning around at the player spawn: -- nacht --spin
func _spin_shots(game: Game) -> void:
	for i in 6:
		await get_tree().physics_frame
	for k in 4:
		game.player.rotation.y = k * PI / 2
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/spin_%d.png" % k))
	get_tree().quit()


# Walk the player from spawn up the stairs to an upstairs window: -- nacht --stairs-test
func _stairs_test(game: Game) -> void:
	await game.level.navigation_ready
	var jumping := OS.get_cmdline_user_args().has("--no-open")
	if not jumping:
		for d in game.level.debris.duplicate():
			if d.entity == "FrontSofaTrigger":
				d.open()
	var target := Vector3.ZERO
	for w in game.level.windows:
		if w.area == "upstairsroom":
			target = w.inside
	var p := game.player
	var path := PackedVector3Array()
	for attempt in (1 if jumping else 40):  # wait for the rebake without the debris to reach upstairs
		await get_tree().create_timer(0.5).timeout
		path = NavigationServer3D.map_get_path(p.get_world_3d().navigation_map, p.global_position, target, true)
		if path.size() > 0 and path[-1].y > 3.0:
			break
	if jumping:
		# debris still there: walk the straight stair line instead (navmesh is blocked)
		var top := game.level.entity_transform("FrontSofaTrigger").origin
		path = PackedVector3Array([Vector3(-11.6, 0, -7.0), Vector3(-11.6, 1.25, -8.5), Vector3(-12.6, 2.0, -10.0), Vector3(-13.9, 2.75, -10.5), top + Vector3(-1.0, 0.6, 0), Vector3(-19.3, 4.0, -11.2)])
	print("[stairs] path points=%d from %s to %s\n%s" % [path.size(), p.global_position, target, path])
	var i := 0
	var t := 0.0
	var last := 0.0
	while i < path.size() and t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		p.health = Player.MAX_HEALTH
		var to := path[i] - p.global_position
		to.y = 0
		if to.length() < 0.4:
			i += 1
			continue
		p.rotation.y = atan2(-to.x, -to.z)  # face where we walk
		if jumping and p.is_on_floor():
			p.velocity.y = Player.JUMP  # hop constantly, as a player trying to skip the debris
		var local := p.global_basis.inverse() * to.normalized()
		p.move_input = Vector2(local.x, local.z)
		Input.action_release("jump")
		if t - last >= 1.0:
			last = t
			print("[stairs] t=%.0f y=%.2f waypoint %d/%d vel=%s floor=%s input=%s" % [t, p.global_position.y, i, path.size(), p.velocity.snapped(Vector3(0.01, 0.01, 0.01)), p.is_on_floor(), p.move_input.snapped(Vector2(0.01, 0.01))])
	p.move_input = Vector2.ZERO
	for view in ["ahead", "left"]:
		if view == "left":
			p.rotation.y += PI / 2
		for k in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/stairs_%s.png" % view))
	var space := p.get_world_3d().direct_space_state
	for dir in [Vector3.UP, -p.global_basis.z]:
		var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 0.9, p.global_position + Vector3.UP * 0.9 + dir * 2.0)
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		print("[stairs] ray ", dir, " -> ", "none" if hit.is_empty() else "%s at %.2f (%s)" % [hit["collider"].get_parent().name, (hit["position"] - q.from).length(), hit["collider"].get_parent().get_parent().name])
	var dir3 := path[min(i, path.size() - 1)] - p.global_position
	dir3.y = 0
	for h in [0.0, 0.2, 0.45, 0.8]:
		var col := KinematicCollision3D.new()
		var xf := p.global_transform.translated(Vector3.UP * h)
		if p.test_move(xf, dir3.normalized() * 0.3, col):
			print("[stairs] probe lift %.2f: hit %s normal=%s at %.2f above feet" % [h, col.get_collider().get_parent().name, col.get_normal().snapped(Vector3(0.01, 0.01, 0.01)), col.get_position().y - p.global_position.y])
		else:
			print("[stairs] probe lift %.2f: free" % h)
	for v in [dir3.normalized() * 0.2, dir3.normalized() * 0.2 + Vector3.UP * 0.1, Vector3.UP * 0.2, -dir3.normalized() * 0.2]:
		var r := p.move_and_collide(v, true)
		print("[stairs] move_and_collide %s -> %s" % [v.snapped(Vector3(0.01, 0.01, 0.01)), "free" if r == null else "%s n=%s travel=%s depth=%.3f" % [r.get_collider().get_parent().name, r.get_normal().snapped(Vector3(0.01, 0.01, 0.01)), r.get_travel().snapped(Vector3(0.001, 0.001, 0.001)), r.get_depth()]])
	for c in p.get_slide_collision_count():
		var col := p.get_slide_collision(c)
		print("[stairs] touching %s normal=%s at y=%.2f (feet %.2f)" % [col.get_collider().get_parent().name, col.get_normal().snapped(Vector3(0.01, 0.01, 0.01)), col.get_position().y, p.global_position.y])
	print("[stairs] next waypoint ", path[min(i, path.size() - 1)], " pos ", p.global_position)
	var ok := p.global_position.y > target.y - 0.3  # reached the upstairs floor
	if jumping:
		ok = not ok  # with the debris in place, getting upstairs is the bug
	print("[stairs] %s: end y=%.2f dist=%.2f time=%.1fs" % ["OK" if ok else "FAIL", p.global_position.y, p.global_position.distance_to(target), t])
	get_tree().quit()


# Buy from the mystery box and take the weapon: -- nacht --box-test
func _box_test(game: Game) -> void:
	await game.level.navigation_ready
	var box: MysteryBox = game.level.boxes[0]
	var p := game.player
	p.points = 5000
	# stand 1.6 m in front of the box (its local +Z), looking at it
	var front := box.global_transform * Vector3(0, 0, 1.6)
	var probe := box.global_transform * Vector3(0, 0, -1.6)
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(box.global_position + Vector3.UP, front + Vector3.UP)
	if not space.intersect_ray(q).is_empty():
		front = probe  # the other side is the open one
	p.global_position = front
	var to := box.global_position - front
	p.rotation.y = atan2(-to.x, -to.z)
	var cam := p.get_viewport().get_camera_3d()
	cam.rotation.x = -0.35
	var shots := {"closed": 0.5, "cycling1": 1.5, "cycling3": 2.5, "offered": 2.0}
	for k in ["closed", "cycling1", "cycling3", "offered"]:
		if k == "cycling1":
			print("[box] prompt before: ", box.prompt(p))
			box.interact(p)
		await get_tree().create_timer(shots[k]).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/box_%s.png" % k))
		print("[box] %s state=%s offered=%s" % [k, MysteryBox.State.keys()[box.state], box.offered])
	print("[box] prompt offered: ", box.prompt(p))
	box.interact(p)
	await get_tree().create_timer(1.0).timeout
	print("[box] %s: weapon in hand=%s points=%d state=%s" % ["OK" if p.weapon()["name"] == box.offered else "FAIL", p.weapon()["name"], p.points, MysteryBox.State.keys()[box.state]])
	for o in [40, -40]:
		p.global_position = box.global_position + (front - box.global_position).rotated(Vector3.UP, deg_to_rad(o))
		to = box.global_position - p.global_position
		p.rotation.y = atan2(-to.x, -to.z)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/box_side%d.png" % o))
	get_tree().quit()


# One knife slash against a 100 hp zombie at several distances/angles: -- nacht --knife-test
func _knife_test(game: Game) -> void:
	await game.level.navigation_ready
	game.set_process(false)  # no wave spawns during the test
	var p := game.player
	var results := []
	for dist in [0.5, 0.8, 1.1, 1.4, 1.7]:
		for ang in [-30.0, 0.0, 30.0]:
			var fwd := -p.global_basis.z
			var at: Vector3 = p.global_position + fwd.rotated(Vector3.UP, deg_to_rad(ang)) * dist
			var z := Zombie.new()
			z.setup(at, game.level.windows[0], p, 100.0, false)
			game.add_child(z)
			z.state = Zombie.State.ATTACK
			z.set_physics_process(false)
			for i in 3:
				await get_tree().physics_frame
			p._melee_cooldown = 0.0
			p.melee()
			await get_tree().physics_frame
			results.append("%.1fm %+.0f°: %s" % [dist, ang, "dead" if z.state == Zombie.State.DEAD else "ALIVE hp=%.0f" % z.health])
			z.queue_free()
			await get_tree().create_timer(0.1).timeout
	for r in results:
		print("[knife] ", r)
	get_tree().quit()
