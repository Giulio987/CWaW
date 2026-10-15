# Shi No Numa tests, started from autotest.gd (screenshots in analysis/preview/swamp_*.png):
#   tools/run_godot.sh 150 -- shinonuma --autotest 120 --swamp-test <test>
# map [--at x,z,size] [--side yaw]: orthographic view with the navmesh (yellow), the floor
#   from the original navmesh (magenta), zombie spawns (red), swamp spawns (blue), windows
# rise: swamp spawns picked by the spawner, a "_water" zombie rising (front/side shots)
# spawns [--open-all]: every spawn reaches its window (walk-in + path length) -> OK/FAIL
# walk --spawn <name> [--side-off x,y,z]: follow one zombie to its window (or to its
#   boardless swamp window, then CHASE)
# zipline [--zip-log]: switch, gate, ride up, ride down killing a zombie -> OK/FAIL
# profile --line x1,z1,x2,z2 [--hy y,..]: world / nav floor / navmesh heights along a line
# wade: player and a zombie in the doctors' swamp: bed height, speed x0.5, grenade on the bed
# view --cam x,y,z,yaw,pitch[;...] [--markers]: free camera shots
class_name SwampTests


static func run(at: Node) -> void:
	var game: Game = at.game
	await game.level.wait_navigation()
	await at.get_tree().create_timer(0.5).timeout
	game.set_process(false)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--swamp-test")
	var which: String = args[i + 1] if i + 1 < args.size() else "map"
	match which:
		"map":
			await _map(at, game)
		"rise":
			await _rise(at, game)
		"zipline":
			await _zipline(at, game)
		"profile":
			_profile(at, game)
		"view":
			await _view(at, game)
		"spawns":
			await _spawns(at, game)
		"walk":
			await _walk(at, game)
		"wade":
			await _wade(at, game)
	at.get_tree().quit()


static func _snap(at: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	at.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/swamp_%s.png" % name))


static func _wait(at: Node, t: float) -> void:
	await at.get_tree().create_timer(t).timeout


static func _marker(game: Game, pos: Vector3, color: Color, r := 0.5) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	s.material = mat
	m.mesh = s
	game.add_child(m)
	m.global_position = pos


static func _navmesh_overlay(game: Game) -> void:
	var nm := game.level.nav_region.navigation_mesh
	var verts := nm.get_vertices()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.9, 0.1, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for pi in nm.get_polygon_count():
		var poly := nm.get_polygon(pi)
		for k in range(1, poly.size() - 1):
			for v in [poly[0], poly[k], poly[k + 1]]:
				im.surface_add_vertex(verts[v] + Vector3.UP * 0.05)
	im.surface_end()
	for fl in [["NavFloor", Color(1, 0, 1, 0.5)], ["SwampBed", Color(0, 0.9, 1, 0.45)]]:
		var floor := game.level.nav_region.find_child(fl[0], false, false)
		if floor == null:
			continue
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = fl[1]
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.no_depth_test = true
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fm)
		for v in ((floor.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces():
			im.surface_add_vertex(v + Vector3.UP * 0.1)
		im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	game.add_child(mi)


# Top view (or side view with --side yaw) around --at x,z,size with spawn/window markers.
static func _map(at: Node, game: Game) -> void:
	var args := OS.get_cmdline_user_args()
	var c := Vector3(0, 0, 0)
	var size := 180.0
	var ai := args.find("--at")
	if ai >= 0:
		var f := args[ai + 1].split_floats(",")
		c = Vector3(f[0], 0, f[1])
		size = f[2] if f.size() > 2 else 40.0
	for we in game.find_children("*", "WorldEnvironment", true, false):
		we.environment.fog_enabled = false
		we.environment.ambient_light_energy = 3.0
	game.hud.visible = false if "visible" in game.hud else true
	if not args.has("--no-nav"):
		_navmesh_overlay(game)
	var lv := game.level
	for n in lv.entities_matching(""):
		var ln := String(n).to_lower()
		var col := Color.TRANSPARENT
		if "zombieswampspawn" in ln:
			col = Color(0.1, 0.4, 1)
		elif "zombiespawn" in ln:
			col = Color(1, 0.1, 0.1)
		elif "zombiewindow" in ln:
			col = Color(0.1, 1, 0.2)
		elif ln.begins_with("zipline"):
			col = Color(1, 0.2, 1)
		if col.a > 0:
			_marker(game, lv.entity_transform(n).origin, col, 0.2 + size / 150.0)
	game.player.global_position = Vector3(c.x, -50, c.z)   # out of the picture
	game.player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.far = 500.0
	game.add_child(cam)
	var si := args.find("--side")
	if si >= 0:
		var yaw := deg_to_rad(float(args[si + 1]))
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		cam.global_position = c + Vector3.UP * 3.0 + dir * 150.0
		cam.look_at(c + Vector3.UP * 3.0, Vector3.UP)
	else:
		cam.global_position = c + Vector3.UP * 150.0
		cam.rotation = Vector3(-PI / 2, 0, 0)   # -z up in the picture
	cam.make_current()
	await _wait(at, 0.3)
	await _snap(at, "map" if ai < 0 else "map_%d_%d%s" % [int(c.x), int(c.z), "" if si < 0 else "_side" + args[si + 1]])


# All doors open, the player in a swamp: the spawner picks swamp spawns ("_water"
# zombies rise out of the water, no window); screenshots of one rising, front and side.
static func _open_all(at: Node, game: Game) -> void:
	for d in game.level.debris:
		if is_instance_valid(d) and d.has_method("open"):
			d.open()
	for a in game._areas:
		game.open_area(a)
	await _wait(at, 1.0)
	game.level.bake_navigation()
	await _wait(at, 0.2)
	while game.level.nav_region.is_baking():
		await _wait(at, 0.2)


static func _rise(at: Node, game: Game) -> void:
	await _open_all(at, game)
	var p := game.player
	p.health = 1e9
	var spot := Vector3(24.4, 0.6, -24.4)   # doctorsswampDogSpawn2
	p.global_position = spot
	await _wait(at, 0.5)
	print("[swamp] player area=%s local=%s" % [game.player_area(), game._local_areas()])
	var counts := {}
	var swamp := 0
	game.round_number = 3
	game._hp = Vector2(1e6, 1e6)
	for i in 30:
		game._spawn_zombie()
		var z: Zombie = game.get_children().filter(func(n): return n is Zombie).back()
		counts[game.last_spawn] = counts.get(game.last_spawn, 0) + 1
		if "SwampSpawn" in game.last_spawn:
			swamp += 1
		if i < 29:
			z.queue_free()
			game._alive -= 1
	print("[swamp] spawns picked: %s" % counts)
	print("[swamp] swamp spawns %d/30 %s" % [swamp, "OK" if swamp > 0 else "FAIL"])
	# watch one swamp zombie rise
	for z in game.get_children().filter(func(n): return n is Zombie):
		z.queue_free()
	await _wait(at, 0.1)
	var origin := game.level.entity_transform("doctorsSwampZombieSwampSpawn3").origin
	game.last_spawn = ""
	var z := game.spawn_zombie_at("doctorsSwampZombieSwampSpawn3")
	z.set_physics_process(true)
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.make_current()
	var front := z.global_position + Vector3(0, 1.6, 0) + (spot - z.global_position).normalized() * 4.0
	for t in [0.3, 1.5, 3.0, 5.0, 7.0, 9.5]:
		await _wait(at, t - z.life)
		cam.global_position = front if t < 7.0 else z.global_position + Vector3(4.0, 1.2, 0.5)
		cam.look_at(z.global_position + Vector3.UP * 0.7)
		await _snap(at, "rise_%02d" % int(t * 10))
		print("[swamp] rise t=%.1f state=%s anim=%s y=%.2f" % [z.life, Zombie.State.keys()[z.state], z._anim.current_animation, z.global_position.y])
	await _wait(at, 3.0)
	print("[swamp] after rise state=%s pos=%s dist_to_player=%.1f" % [Zombie.State.keys()[z.state], z.global_position.snapped(Vector3(0.01, 0.01, 0.01)), z.global_position.distance_to(p.global_position)])
	print("[swamp] rise %s" % ["OK" if z.state in [Zombie.State.CHASE, Zombie.State.ATTACK] and z.global_position.y > origin.y - 0.3 else "FAIL"])


# The zipline: activate at the doctors' switch (gate opens, car comes down empty),
# ride up from the bottom, ride down from the top killing a zombie on the way.
static func _zipline(at: Node, game: Game) -> void:
	var zip: Zipline = game.level.zipline
	var p := game.player
	p.health = 1e9
	p.points = 10000
	var ok := zip != null
	if not ok:
		print("[swamp] zipline FAIL: none")
		return
	for we in game.find_children("*", "WorldEnvironment", true, false):
		we.environment.fog_enabled = false
	var cam := Camera3D.new()
	game.add_child(cam)
	print("[swamp] zip A=%s B=%s cost=%d gate=%s switch=%s" % [zip._a.origin.snapped(Vector3(0.01, 0.01, 0.01)), zip._b.origin.snapped(Vector3(0.01, 0.01, 0.01)), zip.cost, zip.gate.global_position.snapped(Vector3(0.01, 0.01, 0.01)), zip.switch.use_point.snapped(Vector3(0.01, 0.01, 0.01))])
	# views of the stations before anything happens
	await _shot(at, cam, zip.car.global_position + Vector3(0, 1.5, 0), Vector3(7, 2, 3), "zip_top")
	await _shot(at, cam, zip.gate.global_position + Vector3(1, 0.8, 0), Vector3(3, 1.5, 3), "zip_gate_closed")
	await _shot(at, cam, zip.gate.global_position + Vector3(1, 0.8, 0), Vector3(-3, 1.5, 1), "zip_gate_closed_side")
	await _shot(at, cam, zip.switch.global_position + Vector3(0, 1, 0), Vector3(2, 1.2, 2), "zip_switch")
	# 1. the switch
	p.global_position = zip.switch.use_point + Vector3(0.6, 0, 0.6)
	p.look_at(zip.switch.use_point, Vector3.UP)
	await _wait(at, 0.3)
	print("[swamp] zip switch prompt='%s' target=%s" % [p.prompt, p._interaction_target()])
	ok = ok and "attivare" in p.prompt
	_use(p)
	await _wait(at, 0.5)
	print("[swamp] zip after switch: activated=%s ledge_open=%s car=%s gate_open=%s" % [zip.activated, "ledge" in game.open_areas, Zipline.Car.keys()[zip.car_state], zip.gate.is_open])
	ok = ok and zip.activated and "ledge" in game.open_areas and zip.car_state == Zipline.Car.DOWN
	await _wait(at, 1.5)
	await _shot(at, cam, zip.gate.global_position + Vector3(1, 0.8, 0), Vector3(3, 1.5, 3), "zip_gate_open")
	await _shot(at, cam, zip.gate.global_position + Vector3(1, 0.8, 0), Vector3(-3, 1.5, 1), "zip_gate_open_side")
	await _shot(at, cam, zip.car.global_position + Vector3(0, 1.5, 0), Vector3(-9, 3, 5), "zip_mid_empty")
	await _wait(at, 4.0)
	print("[swamp] zip car=%s at %s (B %s)" % [Zipline.Car.keys()[zip.car_state], zip.car.global_position.snapped(Vector3(0.01, 0.01, 0.01)), zip._b.origin.snapped(Vector3(0.01, 0.01, 0.01))])
	ok = ok and zip.car_state == Zipline.Car.AT_BOTTOM_WAIT
	await _shot(at, cam, zip.car.global_position + Vector3(0, 1.5, 0), Vector3(6, 2, 4), "zip_bottom")
	await _shot(at, cam, zip.car.global_position + Vector3(0, 1.5, 0), Vector3(-5, 1, -5), "zip_bottom_side")
	zip._timer = 0.0   # skip the 30 s
	await _wait(at, 0.2)
	# 2. ride up from the bottom
	var start_pts := p.points
	p.global_position = zip.car.global_transform * zip._box.get_center() + Vector3.UP * 0.2
	await _wait(at, 0.4)
	print("[swamp] zip car prompt='%s' in_car=%s" % [p.prompt, zip.in_car(p.global_position)])
	_use(p)
	await _wait(at, 3.0)
	var mid := p.global_position
	await _shot(at, cam, zip.car.global_position + Vector3(0, 1.0, 0), Vector3(6, 1, 6), "zip_ride_up")
	await _wait(at, 3.5)
	print("[swamp] zip rode up: paid=%d car=%s player=%s mid=%s" % [start_pts - p.points, Zipline.Car.keys()[zip.car_state], p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), mid.snapped(Vector3(0.01, 0.01, 0.01))])
	ok = ok and start_pts - p.points == zip.cost and zip.car_state == Zipline.Car.AT_TOP_WAIT and p.global_position.distance_to(zip._a.origin) < 4.0
	zip._timer = 0.0
	await _wait(at, 0.3)
	print("[swamp] zip ready at top: switch prompt from below='%s'" % zip.switch.prompt(p))
	ok = ok and zip.car_state == Zipline.Car.AT_TOP and "chiamare" in zip.switch.prompt(p)
	# 3. ride down with a zombie in the way
	var z := Zombie.new()
	z.setup(zip._a.origin.lerp(zip._b.origin, 0.5) + (zip.car.global_transform.basis * zip._box.get_center()), game.level.windows[0], p, 1e6, false, 1)
	z.state = Zombie.State.CHASE
	game.add_child(z)
	z.set_physics_process(false)
	p.global_position = zip.car.global_transform * zip._box.get_center() + Vector3.UP * 0.2
	await _wait(at, 0.4)
	_use(p)
	await _wait(at, 2.0)
	await _shot(at, cam, zip.car.global_position + Vector3(0, 1.0, 0), Vector3(-6, 1, 5), "zip_ride_down")
	await _wait(at, 4.5)
	print("[swamp] zip rode down: car=%s player=%s zombie=%s" % [Zipline.Car.keys()[zip.car_state], p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), Zombie.State.keys()[z.state] if is_instance_valid(z) else "freed"])
	ok = ok and zip.car_state == Zipline.Car.AT_BOTTOM_WAIT and p.global_position.distance_to(zip._b.origin) < 4.0 and (not is_instance_valid(z) or z.state == Zombie.State.DEAD)
	await _wait(at, 1.0)
	print("[swamp] zip player after release y=%.2f on_floor=%s" % [p.global_position.y, p.is_on_floor()])
	print("[swamp] zipline %s" % ["OK" if ok else "FAIL"])


static func _use(p: Player) -> void:
	var t = p._interaction_target()
	print("[swamp] use %s" % [t])
	if t is Object and t.has_method("interact"):
		t.interact(p)


static func _shot(at: Node, cam: Camera3D, target: Vector3, off: Vector3, name: String) -> void:
	cam.make_current()
	cam.global_position = target + off
	cam.look_at(target)
	await _wait(at, 0.1)
	await _snap(at, name)
	(at.game.player._camera as Camera3D).make_current()


# Heights of the world (layer 1), the nav floor (layer 7) and the navmesh along a line:
# --swamp-test profile --line x1,z1,x2,z2
static func _profile(at: Node, game: Game) -> void:
	var f := OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--line") + 1].split_floats(",")
	var a := Vector3(f[0], 0, f[1])
	var b := Vector3(f[2], 0, f[3])
	var space := game.get_world_3d().direct_space_state
	var map := game.player.get_world_3d().navigation_map
	var n := int(a.distance_to(b) / 0.5)
	var hys := [0.0, 0.5, 1.0, 1.5]
	if OS.get_cmdline_user_args().has("--hy"):
		hys = Array(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--hy") + 1].split_floats(","))
	for y in hys:
		var hq := PhysicsRayQueryParameters3D.create(a + Vector3.UP * y, b + Vector3.UP * y, 1)
		var hh := space.intersect_ray(hq)
		if hh:
			var nd: Node = hh["collider"]
			print("[swamp] horizontal y=%.1f hit %s at %s normal %s" % [y, "%s/%s" % [nd.get_parent().get_parent().name, nd.get_parent().name], hh["position"].snapped(Vector3(0.01, 0.01, 0.01)), hh["normal"].snapped(Vector3(0.01, 0.01, 0.01))])
		else:
			print("[swamp] horizontal y=%.1f free" % y)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var out := []
		for mask in [1, Level.NAV_FLOOR_LAYER]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 10.0, p + Vector3.DOWN * 10.0, mask)
			var h := space.intersect_ray(q)
			out.append("%6.2f" % h["position"].y if h else "   -  ")
		var c := NavigationServer3D.map_get_closest_point(map, p + Vector3.UP * 0.0)
		var h0 := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 10.0, p + Vector3.DOWN * 10.0, 1))
		var who := ""
		if h0:
			var nd: Node = h0["collider"]
			who = "%s/%s" % [nd.get_parent().get_parent().name, nd.get_parent().name]
		print("[swamp] profile %s world=%s floor=%s nav=%s off=%.2f %s" % [p.snapped(Vector3(0.1, 0.1, 0.1)), out[0], out[1], c.snapped(Vector3(0.01, 0.01, 0.01)), Vector2(c.x - p.x, c.z - p.z).length(), who])


# Free camera shots: --swamp-test view --cam x,y,z,yaw,pitch[;x,y,z,yaw,pitch...] [--markers]
static func _view(at: Node, game: Game) -> void:
	var args := OS.get_cmdline_user_args()
	for we in game.find_children("*", "WorldEnvironment", true, false):
		we.environment.fog_enabled = false
	if args.has("--markers"):
		for n in game.level.entities_matching(""):
			var ln := String(n).to_lower()
			if "zombieswampspawn" in ln:
				_marker(game, game.level.entity_transform(n).origin, Color(0.1, 0.4, 1), 0.2)
			elif "zombiespawn" in ln:
				_marker(game, game.level.entity_transform(n).origin, Color(1, 0.1, 0.1), 0.2)
	game.player.set_physics_process(false)
	game.player.global_position = Vector3(0, -80, 0)
	var cam := Camera3D.new()
	cam.far = 300.0
	game.add_child(cam)
	cam.make_current()
	var k := 0
	for spec in args[args.find("--cam") + 1].split(";"):
		var f := spec.split_floats(",")
		cam.global_position = Vector3(f[0], f[1], f[2])
		cam.rotation = Vector3(deg_to_rad(f[4]), deg_to_rad(f[3]), 0)
		await _wait(at, 0.3)
		await _snap(at, "view_%d" % k)
		k += 1


# Every <Area>ZombieSpawn<n>: walk-in entry (if any) + navmesh path to its window.
static func _spawns(at: Node, game: Game) -> void:
	if OS.get_cmdline_user_args().has("--open-all"):
		await _open_all(at, game)
	var map := game.player.get_world_3d().navigation_map
	var worst := 0.0
	var bad := 0
	var waypoints := 0
	for c in game._spawn_candidates(game._areas.keys()):
		var win: Barricade = game._win_by_name.get(c["window"])
		# boardless swamp "windows" (Zombie.waypoint): the zombie walks to that point
		var goal := Vector3.INF
		var goal_name := ""
		if win:
			goal = win.outside
			goal_name = win.name
		elif c["window"] != "" and game.level.has_entity(c["window"]):
			goal = game.level.entity_transform(c["window"]).origin
			goal_name = "%s (waypoint)" % c["window"]
			waypoints += 1
		else:
			continue   # swamp spawn: rises and chases
		var o := game.level.entity_transform(c["spawn"]).origin
		var e := game._spawn_entry(o, goal)
		var path := NavigationServer3D.map_get_path(map, e, goal, true)
		var l := o.distance_to(e)
		for i in range(1, path.size()):
			l += path[i].distance_to(path[i - 1])
		var end_off := path[-1].distance_to(goal) if path.size() > 0 else 99.0
		var ok := end_off < 1.5 and l < 60.0
		if not ok and win == null and game._nav_detour(e, goal):
			ok = true   # game.gd: a waypoint only reached the long way round -> chase from the entry
			goal_name += " detour->chase"
		if not ok:
			bad += 1
		worst = maxf(worst, l)
		print("[swamp] spawn %-32s -> %-28s walk_in=%5.1fm path=%6.1fm end_off=%5.1f %s" % [c["spawn"], goal_name, o.distance_to(e), l, end_off, "ok" if ok else "BAD"])
	print("[swamp] spawns: %d boardless swamp windows as waypoints" % waypoints)
	print("[swamp] spawns: %d bad, longest %.1fm %s" % [bad, worst, "OK" if bad == 0 else "FAIL"])


# Follow a zombie from a spawn to its window, side views every few seconds:
# --swamp-test walk --spawn startRoomZombieSpawn4 [--side-off x,y,z]
static func _walk(at: Node, game: Game) -> void:
	var args := OS.get_cmdline_user_args()
	var sp := args[args.find("--spawn") + 1]
	game.player.health = 1e9
	game._hp = Vector2(1e6, 1e6)
	var z := game.spawn_zombie_at(sp)
	z.set_speed_index(5)
	var off := Vector3(3.5, 1.5, 0.0)
	if args.has("--side-off"):
		var f := args[args.find("--side-off") + 1].split_floats(",")
		off = Vector3(f[0], f[1], f[2])
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.make_current()
	for we in game.find_children("*", "WorldEnvironment", true, false):
		we.environment.fog_enabled = false
	print("[swamp] walk %s from %s entry=%s window=%s" % [sp, z.global_position.snapped(Vector3(0.01, 0.01, 0.01)), z.entry, z.window.name])
	var map := game.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, z.entry if z.entry != Vector3.INF else z.global_position, z.walk_goal(), true)
	print("[swamp] walk path %s" % [Array(path).map(func(v): return v.snapped(Vector3(0.1, 0.1, 0.1)))])
	var k := 0
	while z.life < 40.0 and z.state == Zombie.State.TO_WINDOW:
		cam.global_position = z.global_position + off
		cam.look_at(z.global_position + Vector3.UP * 0.9)
		await _snap(at, "walk_%s_%02d" % [sp, k])
		var fl := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(z.global_position + Vector3.UP, z.global_position + Vector3.DOWN * 3.0, 1 | Level.NAV_FLOOR_LAYER))
		print("[swamp] walk t=%.1f pos=%s floor=%s state=%s" % [z.life, z.global_position.snapped(Vector3(0.01, 0.01, 0.01)), (fl["collider"] as Node).name if fl else "-", Zombie.State.keys()[z.state]])
		k += 1
		await _wait(at, 2.5)
	# a boardless swamp window (waypoint): reached, then straight into the chase
	var ok := z.reached_window > 0.0 and (z.waypoint == Vector3.INF or z.state in [Zombie.State.CHASE, Zombie.State.ATTACK])
	print("[swamp] walk end t=%.1f state=%s reached=%.1f dist=%.1f waypoint=%s %s" % [z.life, Zombie.State.keys()[z.state], z.reached_window, z.global_position.distance_to(z.walk_goal()), z.waypoint != Vector3.INF, "OK" if ok else "FAIL"])


# The player wades on the swamp bed (original navmesh) at WaterMoveSpeedModifier;
# a zombie wades towards them; a grenade comes to rest on the bed; holes in the bed.
static func _wade(at: Node, game: Game) -> void:
	var lv := game.level
	var p := game.player
	p.health = 1e9
	var ok := true
	# floor everywhere under the water: rays over every water cell
	var space := game.get_world_3d().direct_space_state
	var holes := 0
	var lo := INF
	var hi := -INF
	for cell: Vector2i in lv._water_cells:
		var c := (Vector3(cell.x, 0, cell.y) + Vector3(0.5, 0, 0.5)) * Level.WATER_CELL
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.2, c + Vector3.DOWN * 3.0, 1))
		if h.is_empty():
			holes += 1
		else:
			lo = minf(lo, h["position"].y)
			hi = maxf(hi, h["position"].y)
	print("[swamp] wade water cells=%d holes=%d floor y %.2f..%.2f" % [lv._water_cells.size(), holes, lo, hi])
	ok = ok and holes == 0
	# player in the doctors' swamp
	var spot := Vector3(29.0, 0.5, 38.0)   # storage swamp, bed ~0.9 m under the water
	p.global_position = spot
	p.rotation.y = 0.0   # facing -z
	await _wait(at, 1.0)
	print("[swamp] wade player at %s on_floor=%s in_water=%s" % [p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), p.is_on_floor(), lv.in_water(p.global_position)])
	ok = ok and p.is_on_floor() and lv.in_water(p.global_position) and p.global_position.y < -0.2
	await _snap(at, "wade_fp")
	var a := p.global_position
	p.move_input = Vector2(0, -1)
	await _wait(at, 1.5)
	p.move_input = Vector2.ZERO
	var v := Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length() / 1.5
	print("[swamp] wade speed %.2f m/s (dry %.2f x %.2f)" % [v, Player.SPEED, Level.WATER_MOVE_SPEED])
	ok = ok and absf(v - Player.SPEED * Level.WATER_MOVE_SPEED) < 0.4
	# a zombie wading in, side view at water level
	var z := Zombie.new()
	z.setup(p.global_position + Vector3(0.5, 0.3, 6), lv.windows[0], p, 1e6, false, 5)
	z.state = Zombie.State.CHASE
	game.add_child(z)
	var cam := Camera3D.new()
	game.add_child(cam)
	for we in game.find_children("*", "WorldEnvironment", true, false):
		we.environment.fog_enabled = false
	await _wait(at, 2.0)
	for k in 3:
		cam.make_current()
		var side := Vector3(0.5, 0.0, 1.0).rotated(Vector3.UP, k * 1.2).normalized() * 3.0
		cam.global_position = z.global_position + side + Vector3(0, 0.35 + lv.water_y - z.global_position.y, 0)
		cam.look_at(z.global_position + Vector3.UP * 0.9)
		await _wait(at, 0.05)
		await _snap(at, "wade_zombie_%d" % k)
	print("[swamp] wade zombie at %s state=%s" % [z.global_position.snapped(Vector3(0.01, 0.01, 0.01)), Zombie.State.keys()[z.state]])
	ok = ok and z.global_position.y < -0.1
	z.queue_free()
	# a grenade dropped into the water
	var g := Grenade.spawn(game, p.global_position + Vector3(0, 1.5, -1.0), Vector3.ZERO, 30.0, p)
	await _wait(at, 2.5)
	var gq := PhysicsRayQueryParameters3D.create(g.global_position + Vector3.UP, g.global_position + Vector3.DOWN * 3.0, 1)
	gq.exclude = [p.get_rid()]
	var gh := space.intersect_ray(gq)
	print("[swamp] wade grenade y=%.2f bed=%.2f water=%.2f" % [g.global_position.y, gh["position"].y if gh else 99.0, lv.water_y])
	ok = ok and g.global_position.y < lv.water_y - 0.1 and gh and absf(g.global_position.y - gh["position"].y) < 0.25
	cam.global_position = g.global_position + Vector3(1.5, 0.4 + lv.water_y - g.global_position.y, 1.0)
	cam.look_at(g.global_position)
	cam.make_current()
	await _wait(at, 0.05)
	await _snap(at, "wade_grenade")
	g.queue_free()
	print("[swamp] wade %s" % ["OK" if ok else "FAIL"])
