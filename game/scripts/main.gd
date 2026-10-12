# Entry point. Command line: -- [level] [--autotest seconds]
extends Node3D


func _ready() -> void:
	add_child(Achievements.new())   # achievements.gd: unlock popups, stats, user://achievements.cfg
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
	if args.has("--walk"):
		_walk_test(game)
	if args.has("--orient-probe"):
		_orient_probe(game)
	if args.has("--perk-test"):
		_perk_test(game)
	if args.has("--knife-test"):
		_knife_test(game)
	if args.has("--door-test"):
		_door_test(game)
	if args.has("--debris-test"):
		_debris_test(game)
	if args.has("--window-shot-test"):
		_window_shot_test(game)
	if args.has("--spin"):
		_spin_shots(game)
	if args.has("--reach-test"):
		_reach_test(game)
	if args.has("--dog-look"):
		_dog_look(game)
	if args.has("--dog-test"):
		_dog_test(game)
	if args.has("--trap-test"):
		_trap_test(game)
	if args.has("--tele-test"):
		_tele_test(game)
	if args.has("--bridge-test") or args.has("--flytrap-test"):
		DerrieseTests.start(self, game, args)   # derriese_tests.gd
	if args.has("--achievement-test") or args.has("--footstep-test"):
		AchievementTests.start(self, game, args)   # achievement_tests.gd
	if args.has("--photo-test"):
		_photo_test(game)
	if args.has("--pap-test"):
		_pap_test(game)
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
	await game.level.wait_navigation()
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
	if jumping or not OS.get_cmdline_user_args().has("--nav-path"):
		# walk the straight stair line (debris still there: hopping). The navmesh path
		# (--nav-path) runs along the side of the rubble mound, steeper than a body can climb
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
	await game.level.wait_navigation()
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
	await game.level.wait_navigation()
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


# Open the HELP door, put zombies in the box room chasing the player in the start
# room and check they come through: -- nacht --door-test
func _door_test(game: Game) -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var p := game.player
	p.health = 1e9
	for d in game.level.debris.duplicate():
		if d.entity.to_lower() == "doortrigger":
			d.open()
	await game.level.wait_navigation()
	await get_tree().create_timer(2.0).timeout
	var spawn := game.level.entity_transform("DoorTrigger").origin
	var box_side: Vector3 = game.level.boxes[0].global_position
	var start := spawn + (box_side - spawn).normalized() * 3.0  # inside the box room, near the door
	var zs := []
	for i in 4:
		var z := Zombie.new()
		z.setup(start + Vector3(randf_range(-0.5, 0.5), 0.2, randf_range(-0.5, 0.5)), game.level.windows[0], p, 1e9, false)
		game.add_child(z)
		z.state = Zombie.State.CHASE
		zs.append(z)
	var t := 0.0
	while t < 25.0:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		var d := zs.map(func(z): return snappedf(z.global_position.distance_to(p.global_position), 0.1))
		print("[door] t=%.0f distances %s" % [t, d])
		if d.all(func(x): return x < 2.0):
			break
	var ok := zs.all(func(z): return z.global_position.distance_to(p.global_position) < 2.0)
	if not ok:
		await RenderingServer.frame_post_draw
		var stuck: Zombie = zs[0]
		print("[door] stuck at ", stuck.global_position, " next ", stuck._agent.get_next_path_position(), " finished ", stuck._agent.is_navigation_finished(), " reachable ", stuck._agent.is_target_reachable())
	var c := game.level.entity_transform("DoorTrigger").origin
	var nmap := p.get_world_3d().navigation_map
	for off in [-1.5, -0.75, 0.0, 0.75, 1.5]:
		var probe_at: Vector3 = c + Vector3(off, 0.3, 0)
		var cp := NavigationServer3D.map_get_closest_point(nmap, probe_at)
		print("[door] nav near x%+.2f: closest %s (dist %.2f)" % [off, cp.snapped(Vector3(0.01, 0.01, 0.01)), cp.distance_to(probe_at)])
	for off in [-0.6, -0.3, -0.1, 0.0, 0.1, 0.3, 0.6]:
		var fq := PhysicsRayQueryParameters3D.create(c + Vector3(off, 1.0, 0), c + Vector3(off, -1.0, 0), 1)
		var fh := p.get_world_3d().direct_space_state.intersect_ray(fq)
		print("[door] floor x%+.1f: %s" % [off, "HOLE" if fh.is_empty() else "y=%.2f n=%s by %s" % [fh["position"].y, fh["normal"].snapped(Vector3(0.01, 0.01, 0.01)), fh["collider"].get_parent().name]])
	var up := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.2, c + Vector3.UP * 4.0, 1)
	var uh := p.get_world_3d().direct_space_state.intersect_ray(up)
	print("[door] ceiling at ", "none" if uh.is_empty() else str(snappedf((uh["position"] - c).y, 0.01)), " by ", "" if uh.is_empty() else uh["collider"].get_parent().name)
	# doorway width: cast sideways from the door centre at knee and chest height
	var space := p.get_world_3d().direct_space_state
	for h in [0.4, 1.2]:
		for axis in [Vector3.RIGHT, Vector3.BACK]:
			var w := 0.0
			for sgn in [1.0, -1.0]:
				var q := PhysicsRayQueryParameters3D.create(c + Vector3.UP * h, c + Vector3.UP * h + axis * sgn * 3.0, 1)
				var hit := space.intersect_ray(q)
				w += 3.0 if hit.is_empty() else (hit["position"] - q.from).length()
				print("[door]   h=%.1f axis %s side %+.0f hit %s" % [h, axis, sgn, "none" if hit.is_empty() else "%s at %.2f" % [hit["collider"].get_parent().name, (hit["position"] - q.from).length()]])
			print("[door] h=%.1f axis %s free width %.2f" % [h, axis, w])
	print("[door] %s" % ("OK" if ok else "FAIL"))
	get_tree().quit()


# Every debris blocks its passage (rays across its blocker, along its local z, at knee
# and chest height), then opens: the opening animation plays and the blocker goes. -- <map> --debris-test
func _debris_test(game: Game) -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var space := get_viewport().get_world_3d().direct_space_state
	var all_ok := true
	var list: Array = game.level.debris.duplicate()
	for d in list:
		var blocked := 0
		for h in [0.5, 1.2]:
			for side in [-0.3, 0.0, 0.3]:
				var b: Basis = d.global_transform.basis
				var shapes: Array = d._body.get_children().filter(func(n): return n is CollisionShape3D)
				var mid: Vector3 = shapes[0].global_position if shapes.size() > 0 else d.global_position
				var c: Vector3 = Vector3(mid.x, d.global_position.y + h, mid.z) + b.x * side
				var q := PhysicsRayQueryParameters3D.create(c - b.z * 1.5, c + b.z * 1.5)
				q.hit_from_inside = true
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and (hit["collider"] as Node).get_parent() == d:
					blocked += 1
		print("[debris] %s blocked %d/6 yaw %.0f" % [d.entity, blocked, rad_to_deg(d.global_transform.basis.get_euler().y)])
		all_ok = all_ok and blocked == 6
	# --shot <entity>[@deg]: four frames (0.3 s apart) of that debris opening, seen like --look
	var si := OS.get_cmdline_user_args().find("--shot")
	var spec: String = OS.get_cmdline_user_args()[si + 1] if si >= 0 else ""
	if spec != "":
		var target := game.level.entity_transform(spec.get_slice("@", 0)).origin + Vector3.UP
		var dir := target - game.level.player_spawn.origin
		dir.y = 0
		dir = dir.rotated(Vector3.UP, deg_to_rad(float(spec.get_slice("@", 1))) if "@" in spec else 0.0)
		var from := target - dir.normalized() * 3.0
		game.player.global_position = Vector3(from.x, target.y - 1.0, from.z)
		game.player.rotation.y = atan2(-dir.x, -dir.z)
		for i in 8:
			await get_tree().process_frame
	for d in list:
		d.open()
	if spec != "":
		for k in 4:
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/debris_open_%s_%d.png" % [spec.replace("@", "_"), k]))
		get_tree().quit()
		return
	await get_tree().physics_frame
	for d in list:
		if not is_instance_valid(d):
			continue
		var playing: bool = d._anim != null and d._anim.is_playing() and d._anim.current_animation == d._opening
		var shapes: int = d._body.get_children().filter(func(n): return n is CollisionShape3D and not n.is_queued_for_deletion()).size()
		print("[debris] %s opening=%s playing=%s blockers left=%d" % [d.entity, d._opening, playing, shapes])
		all_ok = all_ok and shapes == 0 and (playing or d._anim == null)
	await get_tree().create_timer(6.0).timeout
	var left := list.filter(func(d): return is_instance_valid(d)).size()
	print("[debris] %d still in the scene after 6 s" % left)
	print("[debris] %s" % ("OK" if all_ok and left == 0 else "FAIL"))
	get_tree().quit()


# Shoot from inside at a zombie standing outside each window: -- nacht --window-shot-test
func _window_shot_test(game: Game) -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var p := game.player
	var ok := 0
	for w in game.level.windows:
		var z := Zombie.new()
		z.setup(w.outside, w, p, 1e6, false)
		game.add_child(z)
		z.set_physics_process(false)
		p.global_position = w.inside + (w.inside - w.global_position).normalized() * 0.8
		await get_tree().physics_frame
		var to: Vector3 = z.global_position + Vector3.UP * 1.0 - (p.global_position + Vector3.UP * 1.6)
		p.rotation.y = atan2(-to.x, -to.z)
		p.get_viewport().get_camera_3d().rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
		await get_tree().physics_frame
		var before := z.health
		p.weapon()["mag"] = 8
		p._cooldown = 0.0
		p._fire(p.weapon(), Weapons.stats(p.weapon()["name"]))
		await get_tree().physics_frame
		var hit := z.health < before
		ok += int(hit)
		var cam := p.get_viewport().get_camera_3d()
		var rq := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 20.0, 1 | 2)
		rq.exclude = [p.get_rid()]
		var rh := p.get_world_3d().direct_space_state.intersect_ray(rq)
		print("[shot] %s: %s (ray hits %s at %.2f m, zombie at %.2f m)" % [w.name, "hit" if hit else "MISS", "none" if rh.is_empty() else String(rh["collider"].get_parent().name) + "/" + String(rh["collider"].name), -1.0 if rh.is_empty() else cam.global_position.distance_to(rh["position"]), cam.global_position.distance_to(z.global_position)])
		z.queue_free()
	print("[shot] %d/%d windows" % [ok, game.level.windows.size()])
	get_tree().quit()


# Turn the power on, then walk up to every perk machine, buy it and check its
# effect (prints OK/FAIL per step): -- derriese --perk-test
func _perk_test(game: Game) -> void:
	await game.level.wait_navigation()
	game.set_process(false)  # no zombies during the test
	var p := game.player
	var lv := game.level
	var fails := [0]  # in an array: lambdas capture locals by value
	var space := p.get_world_3d().direct_space_state
	var place := func(m: PerkMachine) -> void:
		# stand on the free side of the machine, facing it
		var best := Vector3.ZERO
		var best_free := -1.0
		for k in 8:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, k * PI / 4)
			var from: Vector3 = m._centre + Vector3.UP * 0.4
			var q := PhysicsRayQueryParameters3D.create(from + dir * 0.9, from + dir * 2.0, 1)
			var hit := space.intersect_ray(q)
			var free: float = 2.0 if hit.is_empty() else (hit["position"] - q.from).length()
			if free > best_free:
				best_free = free
				best = dir
		p.global_position = m._centre + best * 1.4 + Vector3.DOWN * 0.3
		p.velocity = Vector3.ZERO
		var to: Vector3 = m._centre - p.global_position
		p.rotation.y = atan2(-to.x, -to.z)
	var check := func(ok: bool, what: String) -> void:
		print("[perk] %s: %s" % ["OK" if ok else "FAIL", what])
		if not ok:
			fails[0] += 1
	var machines := lv.perk_machines.filter(func(m): return m.kind != "power")
	var switch: PerkMachine = null
	for m in lv.perk_machines:
		if m.kind == "power":
			switch = m
	check.call(machines.size() == 4, "%d perk machines %s" % [machines.size(), machines.map(func(m): return "%s=%s" % [m.entity, m.kind])])
	p.points = 100000
	if switch:
		place.call(machines[0])
		await get_tree().physics_frame
		check.call(not lv.power_on and machines[0].prompt(p) == "Serve la corrente" and not p.has_perk(machines[0].kind), "power off: '%s'" % machines[0].prompt(p))
		if OS.get_cmdline_user_args().has("--perk-reach"):
			# the switch must be reachable once every door is open (slow: one rebake per door)
			for d in lv.debris.duplicate():
				d.open()
			await get_tree().create_timer(1.0).timeout
			while lv.nav_region.is_baking() or lv.nav_region.bake_finished.get_connections().size() > 0:
				await get_tree().create_timer(1.0).timeout
			await get_tree().create_timer(1.0).timeout
			var path := NavigationServer3D.map_get_path(p.get_world_3d().navigation_map, lv.player_spawn.origin, switch._centre, true)
			var gap := switch._centre.distance_to(path[-1]) if path.size() > 0 else INF
			check.call(gap < 2.0, "switch reachable on the navmesh (path end %.2f m away, %d points)" % [gap, path.size()])
		place.call(switch)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var t = p._interaction_target()
		check.call(t == switch, "switch is the interaction target ('%s')" % switch.prompt(p))
		if t == switch:
			t.interact(p)
		check.call(lv.power_on, "power on")
		await get_tree().create_timer(1.0).timeout
	for m in machines:
		place.call(m)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var t = p._interaction_target()
		var before := p.points
		check.call(t == m, "%s target, prompt '%s'" % [m.entity, m.prompt(p)])
		m.interact(p)
		check.call(p.has_perk(m.kind) and before - p.points == m.cost, "bought %s for %d" % [Perks.display(m.kind), before - p.points])
		match m.kind:
			"jugga":
				check.call(p.max_health == Perks.JUGG_HEALTH and p.health == Perks.JUGG_HEALTH, "max health %.0f" % p.max_health)
			"speed":
				p.give_weapon("thompson")
				p._reloading = 0.0
				p.weapon()["mag"] = 0
				p.reload()
				var base: float = Weapons.stats("thompson")["reload"]
				check.call(absf(p._reloading - base * 0.5) < 0.01, "reload %.2f s (base %.2f)" % [p._reloading, base])
				p._reloading = 0.0
				p.weapon()["mag"] = 10
			"dbtap":
				p._cooldown = 0.0
				p._reloading = 0.0
				p._fire(p.weapon(), Weapons.stats(p.weapon()["name"]))
				var rate: float = Weapons.stats(p.weapon()["name"])["rate"]
				check.call(absf(p._cooldown - rate * Perks.DBTAP_RATE) < 0.001, "fire interval %.3f s (base %.3f)" % [p._cooldown, rate])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/perk_%s.png" % m.kind))
		m.interact(p)
		check.call(p.perks.count(m.kind) == 1, "%s can be bought only once" % m.kind)
	print("[perk] perks owned %s" % [p.perks])
	if p.has_perk("revive"):
		p.take_hit(10000.0)
		check.call(not p.dead and p.health == Player.MAX_HEALTH and p.perks.is_empty() and p.max_health == Player.MAX_HEALTH, "quick revive: dead=%s health=%.0f perks=%s" % [p.dead, p.health, p.perks])
		p._revive_grace = 0.0
		p.take_hit(10000.0)
		check.call(p.dead, "second down is death")
	print("[perk] %s (%d failures)" % ["OK" if fails[0] == 0 else "FAIL", fails[0]])
	get_tree().quit()


# Open every debris (and turn the power on with --power), then report which
# areas the navmesh connects to the player spawn: -- derriese --reach-test [--power]
func _reach_test(game: Game) -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var lv := game.level
	if OS.get_cmdline_user_args().has("--power"):
		lv.turn_on_power()
	for d in lv.debris.duplicate():
		d.open()
	await get_tree().create_timer(1.0).timeout
	while lv.nav_region.is_baking() or lv.nav_region.bake_finished.get_connections().size() > 0:
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(1.0).timeout
	var nmap := game.player.get_world_3d().navigation_map
	var pi := OS.get_cmdline_user_args().find("--probe")
	if pi >= 0:
		# floor heights (and nearest navmesh point) along a line: --probe x1,z1,x2,z2
		var c := OS.get_cmdline_user_args()[pi + 1].split(",")
		var a := Vector3(float(c[0]), 0, float(c[1]))
		var b := Vector3(float(c[2]), 0, float(c[3]))
		var space := game.player.get_world_3d().direct_space_state
		for k in int(a.distance_to(b) / 0.1) + 1:
			var p: Vector3 = a.lerp(b, k * 0.1 / a.distance_to(b))
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 8.0, p + Vector3.DOWN * 8.0, 1)
			var hit := space.intersect_ray(q)
			var fy: float = hit["position"].y if not hit.is_empty() else NAN
			var np := NavigationServer3D.map_get_closest_point(nmap, Vector3(p.x, fy, p.z))
			print("[probe] %s floor %.2f nav %s (%.2f)" % [p.snapped(Vector3(0.01, 0.01, 0.01)), fy, np.snapped(Vector3(0.1, 0.1, 0.1)), np.distance_to(Vector3(p.x, fy, p.z))])
	var from := lv.player_spawn.origin
	var fi := OS.get_cmdline_user_args().find("--from")
	if fi >= 0:
		from = lv.entity_transform(OS.get_cmdline_user_args()[fi + 1]).origin
	var points := {}   # label -> position
	for w in lv.windows:
		points["win " + String(w.name)] = w.inside
	for m in lv.perk_machines:
		points["perk " + m.entity] = m._centre
	for n in lv.entities:
		if n.to_lower().contains("dogspawn") and n.ends_with("1"):
			points["dog " + n] = lv.entity_transform(n).origin
	var fails := 0
	var keys := points.keys()
	keys.sort()
	for k in keys:
		var to: Vector3 = points[k]
		var path := NavigationServer3D.map_get_path(nmap, from, to, true)
		var gap := to.distance_to(path[-1]) if path.size() > 0 else INF
		var ok := gap < 2.0
		fails += int(not ok)
		print("[reach] %s %s (end %.1f m away at %s)" % ["OK  " if ok else "FAIL", k, gap, (path[-1] if path.size() > 0 else Vector3.ZERO).snapped(Vector3(0.1, 0.1, 0.1))])
	print("[reach] %s (%d unreachable)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))


func _face(p: Player, at: Vector3) -> void:
	var to := at - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	var cam := p.get_viewport().get_camera_3d()
	cam.rotation.x = atan2(to.y - 1.6, Vector2(to.x, to.z).length())


# Round 1 is cleared at once, a dog round follows (--dogs-next is implied): dogs
# must spawn, reach and bite the player, die, and the last one must drop a Max
# Ammo before round 3 starts: -- derriese --dog-test
func _dog_test(game: Game) -> void:
	var fails := [0]
	var check := func(ok: bool, what: String) -> void:
		print("[dog] %s: %s" % ["OK" if ok else "FAIL", what])
		fails[0] += int(not ok)
	await game.level.wait_navigation()
	var p := game.player
	p.health = 1e6
	p.max_health = 1e6
	while game.round_number < 1:
		await get_tree().create_timer(0.5).timeout
	game.waves_since_dog = 5   # force the dog round
	game._to_spawn = 0
	game._spawned = 0
	for z in get_tree().get_nodes_in_group("zombies"):
		game.kill_without_points(z)
	var t := 0.0
	while not game.dog_round and t < 15.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	check.call(game.dog_round and game.round_number == 2, "dog round started (round %d, %d dogs, %.0f hp)" % [game.round_number, game._dogs_total, game._dog_health])
	game._dogs_total = 4
	var killed := 0
	var reached := 0
	var shot_done := false
	var hp0 := p.health
	t = 0.0
	while game.dog_round and t < 90.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		p.health = maxf(p.health, 1e5)
		for d in get_tree().get_nodes_in_group("zombies"):
			if d is Dog and d.state != Zombie.State.DEAD:
				var dist: float = d.global_position.distance_to(p.global_position)
				if dist < 4.0 and not shot_done:
					shot_done = true
					_face(p, d.global_position + Vector3.UP * 0.5)
					await _shot("dog_close")
				if dist < 2.0 and d.get_meta("bit_time", 0.0) == 0.0:
					d.set_meta("bit_time", t)
					reached += 1
				if d.get_meta("bit_time", 0.0) > 0.0 and t - float(d.get_meta("bit_time")) > 2.5:
					d.take_damage(1e6, false, p)
					killed += 1
		if int(t * 4) % 20 == 0:
			var ds := get_tree().get_nodes_in_group("zombies").filter(func(x): return x is Dog and x.state != Zombie.State.DEAD)
			print("[dog] t=%.0f alive=%d spawned=%d/%d dists=%s" % [t, ds.size(), game._dogs_spawned, game._dogs_total, ds.map(func(x): return snappedf(x.global_position.distance_to(p.global_position), 0.1))])
	check.call(reached == 4, "%d/4 dogs reached the player" % reached)
	check.call(p.health < 1e5 or hp0 > p.health, "player was bitten")
	check.call(killed == 4 and not game.dog_round, "%d dogs killed, round over" % killed)
	var drop := get_tree().get_nodes_in_group("zombies").size() >= 0 and game.get_children().any(func(n): return n is Powerup and n.kind == "maxammo")
	check.call(drop, "max ammo dropped")
	t = 0.0
	while game.round_number < 3 and t < 15.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	check.call(game.round_number == 3 and not game.dog_round, "round 3 (zombies) started")
	print("[dog] %s (%d failures)" % ["OK" if fails[0] == 0 else "FAIL", fails[0]])
	get_tree().quit()


# Every trap: power on, buy it at its switch, a zombie standing in it must die,
# without kill points; screenshots of the arcs: -- verruckt --trap-test
func _trap_test(game: Game) -> void:
	var fails := [0]
	var check := func(ok: bool, what: String) -> void:
		print("[trap] %s: %s" % ["OK" if ok else "FAIL", what])
		fails[0] += int(not ok)
	await game.level.wait_navigation()
	game.set_process(false)
	var lv := game.level
	var p := game.player
	p.health = 1e6
	await get_tree().create_timer(0.5).timeout
	check.call(not lv.traps.is_empty(), "%d traps" % lv.traps.size())
	if not lv.power_on:
		lv.turn_on_power()
	for tr: Trap in lv.traps:
		check.call(tr.kind == "flogger" or not tr.volumes.is_empty(), "%s %s volumes %s" % [tr.entity, tr.kind, tr.volumes])
		p.global_position = tr.use_point + Vector3.DOWN * 0.3
		p.velocity = Vector3.ZERO
		_face(p, tr.use_point + Vector3.UP)
		p.points = 10000
		await get_tree().physics_frame
		await get_tree().physics_frame
		var target = p._interaction_target()
		# a closed door right next to the switch takes precedence (Der Riese lab): fine once bought
		check.call(target == tr or target is Debris, "%s is the interaction target (prompt '%s'%s)" % [tr.entity, tr.prompt(p), "" if target == tr else ", a door in front"])
		tr.interact(p)
		check.call(tr.state == Trap.State.ACTIVE and p.points == 10000 - tr.cost, "%s bought for %d" % [tr.entity, tr.cost])
		# the switch animates first (ASM TurnOn + pull, 2.3 s): then the arcs come on
		var t0 := Time.get_ticks_msec()
		while not tr.armed and Time.get_ticks_msec() - t0 < 4000:
			await get_tree().physics_frame
		check.call(tr.armed and absf((Time.get_ticks_msec() - t0) / 1000.0 - (0.0 if tr.kind == "flogger" else 2.265)) < 0.3, "%s armed after %.2f s" % [tr.entity, (Time.get_ticks_msec() - t0) / 1000.0])
		var at: Vector3 = tr.pivot + Vector3(1.5, 0, 0) if tr.kind == "flogger" else (tr.volumes[0] as AABB).get_center()
		at.y = (tr.pivot.y - 0.5) if tr.kind == "flogger" else (tr.volumes[0] as AABB).position.y + 0.35
		var z := Zombie.new()
		z.setup(at, lv.windows[0], p, 1e6, false)
		game.add_child(z)
		z.state = Zombie.State.CHASE
		z.set_physics_process(false)
		var pts := p.points
		for i in 6:
			await get_tree().physics_frame
		check.call(z.state == Zombie.State.DEAD and p.points == pts, "%s kills a zombie in it (no points: %d)" % [tr.entity, p.points - pts])
		# a view of the trap from 3 m beside it
		var c: Vector3 = at
		var side := Vector3(3.0, 0, 0) if tr.kind == "flogger" or (tr.volumes[0] as AABB).size.z > (tr.volumes[0] as AABB).size.x else Vector3(0, 0, 3.0)
		for sgn in [1.0, -1.0]:
			var from: Vector3 = c + side * sgn
			var q := PhysicsRayQueryParameters3D.create(c + Vector3.UP, from + Vector3.UP, 1)
			if get_viewport().get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				p.global_position = Vector3(from.x, c.y - 0.3, from.z)
				break
		_face(p, c + Vector3.UP * 1.0)
		for i in 4:
			await get_tree().process_frame
		await _shot("trap_" + tr.entity)
		tr._stop()
		check.call(tr.state == Trap.State.COOLDOWN and tr.prompt(p) == "Trappola in ricarica", "%s cools down" % tr.entity)
		var expect := (Trap.LEVER_BACK[1] + Trap.COOLDOWN + Trap.LEVER_TURN_OFF[1]) if tr.kind == "electric" else Trap.COOLDOWN + Trap.FLOGGER_TURN_OFF
		check.call(absf(tr._timer - expect) < 0.05, "%s cooldown %.1f s (ASM: 30 s hold)" % [tr.entity, tr._timer])
	print("[trap] %s (%d failures)" % ["OK" if fails[0] == 0 else "FAIL", fails[0]])
	get_tree().quit()


# Der Riese teleporters: power, link the three pads at the mainframe (the door
# opens step by step), then teleport from pad A to the mainframe: -- derriese --tele-test
func _tele_test(game: Game) -> void:
	var fails := [0]
	var check := func(ok: bool, what: String) -> void:
		print("[tele] %s: %s" % ["OK" if ok else "FAIL", what])
		fails[0] += int(not ok)
	await game.level.wait_navigation()
	game.set_process(false)
	var lv := game.level
	var net := lv.teleporters
	var p := game.player
	p.health = 1e6
	p.points = 100000
	check.call(net != null and net.pads.size() == 3, "3 teleporter pads")
	var go := func(pad) -> void:
		p.global_position = pad.centre + Vector3.UP * 0.2
		p.velocity = Vector3.ZERO
	go.call(net.pads[0])
	await get_tree().physics_frame
	await get_tree().physics_frame
	check.call(net.pads[0].prompt(p) == "Serve la corrente", "pad needs power: '%s'" % net.pads[0].prompt(p))
	await _shot("tele_padA")
	p.global_position = net.mainframe.centre + Vector3(0, 0.2, 0)
	_face(p, lv.pack_a_punch.global_position + Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await _shot("tele_door_closed")
	lv.turn_on_power()
	for pad in net.pads:
		go.call(pad)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var t = p._interaction_target()
		check.call(t == pad, "%s target: '%s'" % [pad.entity, pad.prompt(p)])
		pad.interact(p)
		check.call(pad.state == "linking", "%s activated" % pad.entity)
		go.call(net.mainframe)
		await get_tree().physics_frame
		await get_tree().physics_frame
		t = p._interaction_target()
		check.call(t == net.mainframe, "mainframe target: '%s'" % net.mainframe.prompt(p))
		net.mainframe.interact(p)
		check.call(pad.state == "linked", "%s linked (%d)" % [pad.entity, net.linked_count()])
		await get_tree().create_timer(2.2).timeout
	check.call("packapunch" in game.open_areas and net._door_body == null, "third link opens the mainframe door and the Pack-a-Punch area")
	p.global_position = net.mainframe.centre + Vector3(0, 0.2, 0)
	_face(p, lv.pack_a_punch.global_position + Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await _shot("tele_door_open")
	go.call(net.pads[0])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before := p.points
	check.call(net.pads[0].prompt(p).begins_with("Premi E per teletrasportarti"), "teleport prompt '%s'" % net.pads[0].prompt(p))
	net.pads[0].interact(p)
	await get_tree().create_timer(0.4).timeout
	await _shot("tele_flash")
	await get_tree().create_timer(1.0).timeout
	check.call(p.global_position.distance_to(net.mainframe.centre) < 1.5 and before - p.points == TeleporterNetwork.COST, "teleported to the mainframe for %d (at %s)" % [before - p.points, p.global_position])
	go.call(net.pads[1])
	await get_tree().physics_frame
	check.call(net.pads[1].prompt(p) == "Il teletrasporto si sta ricaricando", "cooldown: '%s'" % net.pads[1].prompt(p))
	await get_tree().create_timer(8.0).timeout
	var pick := game.get_children().any(func(n): return n is Powerup) or get_tree().get_nodes_in_group("zombies").any(func(n): return n is Dog)
	check.call(pick, "power-up or dogs after the teleport")
	print("[tele] %s (%d failures)" % ["OK" if fails[0] == 0 else "FAIL", fails[0]])
	get_tree().quit()


# Pack-a-Punch: off before power/links, upgrades the Thompson for 5000 once
# working: -- derriese --pap-test
func _pap_test(game: Game) -> void:
	var fails := [0]
	var check := func(ok: bool, what: String) -> void:
		print("[pap] %s: %s" % ["OK" if ok else "FAIL", what])
		fails[0] += int(not ok)
	await game.level.wait_navigation()
	game.set_process(false)
	var lv := game.level
	var pap := lv.pack_a_punch
	var p := game.player
	p.health = 1e6
	p.points = 20000
	var args := OS.get_cmdline_user_args()
	var gun: String = args[args.find("--pap-weapon") + 1] if args.has("--pap-weapon") else "thompson"   # other guns: look only
	p.give_weapon(gun)
	check.call(pap != null, "Pack-a-Punch built")
	p.global_position = pap._centre + Vector3.UP * 0.2
	_face(p, pap.global_position + Vector3.UP * 1.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check.call(pap.prompt(p) == "Serve la corrente", "off without power: '%s'" % pap.prompt(p))
	lv.turn_on_power()
	check.call(pap.prompt(p) == "Collega i teletrasporti al mainframe", "needs links: '%s'" % pap.prompt(p))
	for pad in lv.teleporters.pads:
		pad.state = "linked"
	lv.teleporters._update_door()
	pap._refresh()
	await get_tree().create_timer(2.5).timeout
	var t = p._interaction_target()
	check.call(t == pap, "PaP target: '%s'" % pap.prompt(p))
	await _shot("pap_machine")
	var base: float = Weapons.stats(gun)["damage"]
	pap.interact(p)
	check.call(pap.state == PackAPunch.State.WORKING and p.points == 15000, "paid 5000")
	await get_tree().create_timer(PackAPunch.WORK_TIME + 0.5).timeout
	check.call(pap.prompt(p).begins_with("Premi E per prendere"), "ready: '%s'" % pap.prompt(p))
	pap.interact(p)
	var w := p.weapon()
	var s := Weapons.stats_of(w)
	check.call(w.get("upgraded", false) and (gun != "thompson" or w["mag"] == 40) and s["damage"] >= base, "%s: mag %d reserve %d damage %.0f (base %.0f)" % [Weapons.display_of(w), w["mag"], w["reserve"], s["damage"], base])
	check.call(pap.prompt(p) == "Arma già potenziata", "no second upgrade: '%s'" % pap.prompt(p))
	for i in 10:
		await get_tree().process_frame
	await _shot("pap_weapon" if gun == "thompson" else "pap_weapon_" + gun)
	print("[pap] %s (%d failures)" % ["OK" if fails[0] == 0 else "FAIL", fails[0]])
	get_tree().quit()


# A dog standing 3 m in front of the player, seen from the front and the side: -- derriese --dog-look
func _dog_look(game: Game) -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var p := game.player
	var fwd := -p.global_basis.z
	var d := Dog.new()
	d.flame = OS.get_cmdline_user_args().has("--flame")   # --dog-look --flame: a flame dog, then its death burst
	d.setup_dog(p.global_position + fwd * 3.0, p, 1e6, game.level.windows[0])
	game.add_child(d)
	await get_tree().physics_frame
	if OS.get_cmdline_user_args().has("--live"):
		# --dog-look --live: let it run at the player for a moment, side view of the gait
		p.health = 1e6
		await get_tree().create_timer(0.7).timeout
		p.set_physics_process(false)
		var side := d.global_position + (d.global_position - p.global_position).normalized().cross(Vector3.UP) * 2.5
		var cam := Camera3D.new()
		game.add_child(cam)
		cam.global_position = side + Vector3.UP * 0.5
		cam.look_at(d.global_position + Vector3.UP * 0.4)
		cam.make_current()
		for k in 3:
			await _shot("dog_live_%d" % k)
			await get_tree().create_timer(0.12).timeout
			cam.look_at(d.global_position + Vector3.UP * 0.4)
		print("[doglook] live dog y=%.2f floor ray=%s" % [d.global_position.y, p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(d.global_position + Vector3.UP, d.global_position + Vector3.DOWN * 3)).get("position", Vector3.INF)])
		get_tree().quit()
		return
	d.set_physics_process(false)
	for mi in d.find_children("*", "MeshInstance3D", true, false):
		print("[doglook] mesh %s visible=%s aabb %s" % [mi.name, mi.visible, (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()])
	print("[doglook] dog at %s player %s" % [d.global_position, p.global_position])
	var sk: Skeleton3D = d.find_children("*", "Skeleton3D", true, false)[0]
	print("[doglook] skel %s scale %s bone0 %s bone5 %s anim %s" % [sk.global_position, sk.global_transform.basis.get_scale(), sk.global_transform * sk.get_bone_global_pose(0).origin, sk.global_transform * sk.get_bone_global_pose(5).origin, d._d_anim.current_animation])
	for mi in d.find_children("*", "MeshInstance3D", true, false):
		print("[doglook] %s skin=%s skeleton=%s layers=%d" % [mi.name, mi.skin, mi.skeleton, mi.layers])
	_face(p, d.global_position + Vector3.UP * 0.4)
	await get_tree().create_timer(0.2).timeout
	await _shot("dog_front")
	p.global_position = d.global_position + fwd.cross(Vector3.UP) * 2.5
	_face(p, d.global_position + Vector3.UP * 0.4)
	await get_tree().create_timer(0.2).timeout
	await _shot("dog_side")
	if d.flame:
		await get_tree().create_timer(0.8).timeout
		await _shot("dog_flame_side")
		d.nuke_kill()
		await get_tree().create_timer(0.15).timeout
		await _shot("dog_flame_burst")
		await get_tree().create_timer(0.6).timeout
		await _shot("dog_flame_burst2")
	get_tree().quit()


# Pause menu photo mode: -- nacht --photo-test
func _photo_test(game: Game) -> void:
	await game.level.wait_navigation()
	await get_tree().create_timer(1.0).timeout
	var hud: Hud = game.hud
	hud.open_pause()
	await get_tree().create_timer(0.2).timeout
	await _shot("photo_0_menu")
	hud._pause._photo_mode()
	var yaw0 := game.player.rotation.y
	# the pointer is free (moving it alone does not turn), dragging turns the view
	for drag in [false, true]:
		for i in 10:
			var ev := InputEventMouseMotion.new()
			ev.relative = Vector2(40, 0)
			ev.button_mask = MOUSE_BUTTON_MASK_LEFT if drag else 0
			hud._pause._unhandled_input(ev)
		if not drag:
			print("[photo] %s: free pointer (visible=%s, turned %.0f° without dragging)" % ["OK" if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and is_equal_approx(yaw0, game.player.rotation.y) else "FAIL", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, rad_to_deg(yaw0 - game.player.rotation.y)])
	await get_tree().create_timer(0.2).timeout
	await _shot("photo_1_photo")
	print("[photo] %s: paused=%s turned=%.0f° by dragging, info='%s'" % ["OK" if get_tree().paused and absf(yaw0 - game.player.rotation.y) > 0.1 else "FAIL", get_tree().paused, rad_to_deg(yaw0 - game.player.rotation.y), hud._pause._info.text])
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	hud._pause._unhandled_input(esc)
	print("[photo] back to menu=%s paused=%s" % [hud._pause._pages["main"].visible, get_tree().paused])
	hud._pause.close()
	print("[photo] %s" % ["OK" if not get_tree().paused else "FAIL"])
	get_tree().quit()


# Orientation probe: for every perk machine / box entity, the free space (m) along the
# four local axes with and without the transform flags: -- verruckt --orient-probe
func _orient_probe(game: Game) -> void:
	await game.level.wait_navigation()
	var lv := game.level
	var space := game.player.get_world_3d().direct_space_state
	for n in lv.entities:
		var e: Dictionary = lv.entities[n]
		var c: Array = e["components"]
		if not ("CActionBuyPerkSpec" in c or n.to_lower() == "generatorswitch" or n.to_lower().begins_with("mysterybox")) or e["models"].is_empty():
			continue
		var line := "[orient] %s flags %s" % [n, e["transform"].get("flags")]
		for mode in ["plain", "flag"]:
			var t: Transform3D = lv.entity_transform(n) if mode == "plain" else Level.flag_transform(e["transform"])
			var from := t.origin + Vector3.UP * 0.8
			var d := []
			for ax in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
				var dir: Vector3 = (t.basis * ax).normalized()
				var q := PhysicsRayQueryParameters3D.create(from, from + dir * 5.0, 1)
				var hit := space.intersect_ray(q)
				d.append(5.0 if hit.is_empty() else snappedf((hit["position"] - from).length(), 0.01))
			line += "  %s -Z %.2f +Z %.2f -X %.2f +X %.2f" % [mode, d[0], d[1], d[2], d[3]]
		print(line)
	get_tree().quit()


# Walk the player along points (x,y,z;x,y,z;...), optionally after opening a debris,
# printing progress and saving a screenshot at the start and at the end:
#   -- verruckt --walk "2.3,1.2,-15.4;-4,3.1,-16.6" [--open AmerDwn_AmerUp1_Trigger]
func _walk_test(game: Game) -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var args := OS.get_cmdline_user_args()
	var p := game.player
	var oi := args.find("--open")
	if oi >= 0:
		for d in game.level.debris.duplicate():
			if d.entity == args[oi + 1]:
				d.open()
		await get_tree().create_timer(3.0).timeout
	var path := []
	for s in args[args.find("--walk") + 1].split(";"):
		var v := s.split_floats(",")
		path.append(Vector3(v[0], v[1], v[2]))
	if args.has("--nav"):
		# follow the navmesh from the first point to the last one (after the rebake)
		while game.level.nav_region.is_baking():
			await get_tree().create_timer(0.5).timeout
		await get_tree().create_timer(1.0).timeout
		var np := NavigationServer3D.map_get_path(p.get_world_3d().navigation_map, path[0], path[-1], true)
		print("[walk] nav path %s" % np)
		path = [path[0]]
		for v in np:
			path.append(v)
	p.global_position = path[0]
	p.velocity = Vector3.ZERO
	var first: Vector3 = path[1] - path[0]
	p.rotation.y = atan2(-first.x, -first.z)
	for k in 10:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/walk_start.png"))
	var i := 1
	var t := 0.0
	var last := 0.0
	var buy := args.has("--buy")   # once stuck: buy what is in reach and walk on
	var stuck := 0.0
	var prev := p.global_position
	while i < path.size() and t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		p.health = Player.MAX_HEALTH
		var to: Vector3 = path[i] - p.global_position
		to.y = 0
		if to.length() < 0.4:
			i += 1
			continue
		p.rotation.y = atan2(-to.x, -to.z)
		var local := p.global_basis.inverse() * to.normalized()
		p.move_input = Vector2(local.x, local.z)
		stuck = stuck + get_physics_process_delta_time() if p.global_position.distance_to(prev) < 0.005 else 0.0
		prev = p.global_position
		if buy and stuck > 1.0:
			buy = false
			p.points = 10000
			var target = p._interaction_target()
			print("[walk] stuck at %s, target %s prompt '%s'" % [p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), target.get("entity") if target is Object else target, str(target)])
			Input.action_press("interact")
			for k in 3:
				await get_tree().process_frame
			Input.action_release("interact")
			print("[walk] points after buying: %d" % p.points)
			await get_tree().create_timer(4.0).timeout
		if t - last >= 0.5:
			last = t
			print("[walk] t=%.1f pos=%s waypoint %d/%d floor=%s" % [t, p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), i, path.size(), p.is_on_floor()])
	p.move_input = Vector2.ZERO
	print("[walk] %s: end %s after %.1f s" % ["OK" if i >= path.size() else "FAIL", p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), t])
	if i < path.size():
		# what stops the body: a shape cast ahead at a few heights
		var dir: Vector3 = path[i] - p.global_position
		dir.y = 0
		for h in [0.05, 0.3, 0.6, 1.0, 1.5]:
			var col := KinematicCollision3D.new()
			if p.test_move(p.global_transform.translated(Vector3.UP * h), dir.normalized() * 0.3, col):
				var c := col.get_collider()
				print("[walk] blocked at +%.2f by %s (%s) normal %s at %s" % [h, c.name if c else "?", c.get_parent().name if c else "", col.get_normal().snapped(Vector3(0.01, 0.01, 0.01)), col.get_position().snapped(Vector3(0.01, 0.01, 0.01))])
	for k in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/walk_end.png"))
	get_tree().quit()
