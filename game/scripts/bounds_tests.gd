# --bounds-test reach|escape (level.gd player_allowed, player.gd _keep_in_bounds)
#   reach:  walks the map from the spawns, perks, boxes... without jumping (every door open, windows
#           closed) on a 0.4 m grid and lists the floor spots the bounds would refuse.
#   escape: jumps forward from --bounds-from "x,y,z[,yaw];..." for 6 s and checks the player
#           is still allowed (no yaw: eight directions; Nacht's balcony railing by default).
extends RefCounted

const GRID := 0.4


static func start(main: Node, game: Game, args: PackedStringArray) -> void:
	var mode := args[args.find("--bounds-test") + 1] if args.size() > args.find("--bounds-test") + 1 else "reach"
	await game.level.wait_navigation()
	if mode == "escape":
		await _escape(main, game, args)
	else:
		await _reach(main, game)
	main.get_tree().quit()


static func _reach(main: Node, game: Game) -> void:
	game.set_process(false)
	for d in game.level.debris.duplicate():
		d.open()
	game.level.turn_on_power()
	await main.get_tree().create_timer(4.0).timeout
	var p := game.player
	p.set_physics_process(false)
	var space := main.get_viewport().get_world_3d().direct_space_state
	var mask := 1 | 4 | Level.SEE_THROUGH_LAYER
	var ray := func(a: Vector3, b: Vector3) -> Dictionary:
		var q := PhysicsRayQueryParameters3D.create(a, b, mask)
		q.exclude = [p.get_rid()]
		return space.intersect_ray(q)
	# from the spawns and everything the player uses (stairs the grid misses do not cut it short)
	var queue: Array[Vector3] = []
	var seen := {}
	for sd in game.level.player_seeds():
		var h: Dictionary = ray.call(sd[0] + Vector3.UP, sd[0] + Vector3.DOWN * 2)
		if not h.is_empty() and not seen.has(_key(h["position"])) and not p.test_move(Transform3D(Basis.IDENTITY, h["position"] + Vector3.UP * 0.4), Vector3.UP * 0.05):
			seen[_key(h["position"])] = true
			queue.append(h["position"])
	var reached := 0
	var refused := []
	var levels := {}   # floor height (m) -> spots
	while not queue.is_empty() and reached < 200000:
		var c: Vector3 = queue.pop_back()
		reached += 1
		levels[floori(c.y)] = levels.get(floori(c.y), 0) + 1
		if not game.level.player_allowed(c, false):
			refused.append(c)
		for d in [Vector3(GRID, 0, 0), Vector3(-GRID, 0, 0), Vector3(0, 0, GRID), Vector3(0, 0, -GRID)]:
			var n: Vector3 = c + d
			# the player's own capsule, lifted by a stair step, then the floor under the next spot
			if p.test_move(Transform3D(Basis.IDENTITY, c + Vector3.UP * 0.4), d):
				continue
			var f: Dictionary = ray.call(n + Vector3.UP * 0.5, n + Vector3.DOWN * 1.0)
			if f.is_empty() or (f["normal"] as Vector3).y < 0.6:
				continue
			var fp: Vector3 = f["position"]
			if p.test_move(Transform3D(Basis.IDENTITY, fp + Vector3.UP * 0.4), Vector3.UP * 0.05):
				continue   # no room to stand there
			var k := _key(fp)
			if seen.has(k):
				continue
			seen[k] = true
			queue.append(fp)
	print("[bounds] %s: %d spots reached on foot, %d refused; by height %s" % [game.level_name, reached, refused.size(), levels])
	var shown := {}
	for r in refused:
		var cell := Vector3i(floori(r.x), floori(r.y), floori(r.z))
		if shown.has(cell):
			continue
		shown[cell] = true
		if shown.size() <= 40:
			print("[bounds]   refused %s" % (r as Vector3).snapped(Vector3.ONE * 0.01))
	print("[bounds] RESULT %s (%d refused spots in %d m cells)" % ["OK" if refused.size() == 0 else "FAIL", refused.size(), shown.size()])


static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x / GRID), roundi(v.y / 0.5), roundi(v.z / GRID))


static func _escape(main: Node, game: Game, args: PackedStringArray) -> void:
	# "x,y,z,yaw;x,y,z;..." (no yaw: eight directions)
	var fi := args.find("--bounds-from")
	var runs := []
	for spec in (args[fi + 1] if fi >= 0 else "-24.97,3.7,-3.2,180").split(";"):
		var v := spec.split_floats(",")
		for yaw in ([v[3]] if v.size() > 3 else range(0, 360, 45)):
			runs.append([Vector3(v[0], v[1], v[2]), float(yaw)])
	var p := game.player
	var fails := 0
	for r in runs:
		p.global_position = r[0]
		p.rotation.y = deg_to_rad(r[1])
		p.velocity = Vector3.ZERO
		p.set("_last_safe", Vector3.INF)
		for k in 10:
			await main.get_tree().physics_frame
		var t := 0.0
		Input.action_press("move_forward")
		while t < 6.0:
			Input.action_press("jump")
			await main.get_tree().physics_frame
			Input.action_release("jump")
			await main.get_tree().physics_frame
			t += 2.0 / Engine.physics_ticks_per_second
		Input.action_release("move_forward")
		for k in 60:
			await main.get_tree().physics_frame
		var ok: bool = game.level.player_allowed(p.global_position, not p.is_on_floor())
		if not ok:
			fails += 1
		print("[bounds] escape from %s yaw %d ended at %s: %s" % [r[0], r[1], p.global_position.snapped(Vector3.ONE * 0.01), "inside" if ok else "OUTSIDE"])
	print("[bounds] RESULT %s (%d of %d runs outside)" % ["OK" if fails == 0 else "FAIL", fails, runs.size()])
