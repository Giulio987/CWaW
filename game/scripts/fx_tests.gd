# Looks at the original effects (iw_fx.gd), screenshots in analysis/preview:
#   -- verruckt --trap-fx-look    every electric trap on: its <trap>Effect<n> arcs and
#                                 <trap>Sound emitters, front and side views of each arc group
#   -- derriese --dog-fx-look     the dogs' lightning strike (dog_spawn_fx.gd) in front of the
#                                 player, front and side, at 0.1 / 0.6 / 1.2 s
extends Node

var game: Game
var fails := 0
var _cam: Camera3D


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/fx_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	if args.has("--trap-fx-look"):
		t._trap_look()
	elif args.has("--dog-fx-look"):
		t._dog_look()


func _check(ok: bool, what: String) -> void:
	print("[fx] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 400.0
		game.add_child(_cam)
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	_cam.make_current()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))


func _trap_look() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	game.player.health = 1e9
	game.player.set_physics_process(false)
	var lv := game.level
	if not lv.power_on:
		lv.turn_on_power()
	for i in 3:
		await get_tree().process_frame
	if lv.level_name != "shinonuma":   # the huts' hums start when their machine drops
		var hums := lv.get_children().filter(func(n): return String(n.name).begins_with("Hum_"))
		_check(hums.size() == 4 and hums.all(func(e): return e.enabled), "4 SoundPerkHum emitters on: %s" % [str(hums.map(func(e): return [e.name, e.global_position.snapped(Vector3(0.01, 0.01, 0.01)), e.range_m]))])
	for tr: Trap in lv.traps:
		if tr.kind != "electric":
			continue
		tr.gen_on = true
		tr.activate()
		tr._arm()
		var parts := tr.effect_parts()
		var sounds := tr.sound_parts()
		_check(not parts.is_empty(), "%s: %d arcs, models %s" % [tr.entity, parts.size(), parts.map(func(p): return p[1])])
		_check(not sounds.is_empty(), "%s: %d sound emitters %s" % [tr.entity, sounds.size(), sounds.map(func(s): return [s[1]["spec"], s[0].snapped(Vector3(0.01, 0.01, 0.01))])])
		await get_tree().process_frame
		var ems := tr.find_children("*", "Node3D", true, false).filter(func(n): return n is AmbientEmitters.Emitter)
		_check(ems.size() == sounds.size() and ems.all(func(e): return e.enabled), "%s: emitters on" % tr.entity)
		# group the arcs by fence (within 2.5 m of each other)
		var groups := []
		for p in parts:
			var o: Vector3 = (p[0] as Transform3D).origin
			var g = null
			for gg in groups:
				if (gg[0] as Vector3).distance_to(o) < 2.5:
					g = gg
			if g == null:
				groups.append([o, [p]])
			else:
				g[1].append(p)
		var k := 0
		for g in groups:
			var c := Vector3.ZERO
			for p in g[1]:
				c += (p[0] as Transform3D).origin
			c /= g[1].size()
			var normal: Vector3 = ((g[1][0][0] as Transform3D).basis.z * Vector3(1, 0, 1)).normalized()
			var along := normal.cross(Vector3.UP)
			var mid := c + Vector3.UP * 1.1
			await _shot("trapfx_%s_%d_front" % [tr.entity, k], mid + normal * 3.5, mid)
			await _shot("trapfx_%s_%d_back" % [tr.entity, k], mid - normal * 3.5, mid)
			await _shot("trapfx_%s_%d_side" % [tr.entity, k], mid + (normal + along).normalized() * 3.0 + Vector3.UP * 0.4, mid)
			k += 1
		tr._stop()
		await get_tree().process_frame
		_check(tr._fx == null, "%s: arcs off after zapperEnd" % tr.entity)
	print("[fx] %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _dog_look() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	game.player.health = 1e9
	game.player.set_physics_process(false)
	var p := game.player
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := p.global_position + fwd * 6.0
	var hit := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0))
	if not hit.is_empty():
		at = hit["position"]
	var life := preload("res://scripts/dog_spawn_fx.gd").spawn(game, at)
	_check(absf(life - 1.5) < 0.01, "strike lifetime %.2f s (CLifeTimeSpec 1500 ms)" % life)
	var fx := game.get_node_or_null("DogSpawnFx")
	_check(fx != null and fx.get_child_count() == 8, "8 parts")
	var t0 := Time.get_ticks_msec()
	var side := fwd.cross(Vector3.UP)
	for t in [0.1, 0.6, 1.2]:
		while (Time.get_ticks_msec() - t0) / 1000.0 < t:
			await get_tree().process_frame
		var eye := at + Vector3.UP * 1.7
		if t < 1.0:
			await _shot("dogfx_front_%d" % int(t * 10), eye - fwd * 7.0 + Vector3.UP * 0.5, at + Vector3.UP * 2.0)
		await _shot("dogfx_side_%d" % int(t * 10), eye + side * 7.0, at + Vector3.UP * 2.0)
	await get_tree().create_timer(0.6).timeout
	_check(not is_instance_valid(fx), "gone after its lifetime")
	print("[fx] %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()
