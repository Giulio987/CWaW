# Touch controls checks (touch_controls.gd): real InputEventScreenTouch / Drag events on
# the original buttons. Prints OK/FAIL; screenshots in analysis/preview/touch_*.png:
#   tools/run_godot.sh 120 -- nacht --autotest 100 --touch-test --touch-ui [--resolution 2556x1179]
extends RefCounted


static func run(at: Node) -> void:
	var game: Game = at.game
	await game.level.wait_navigation()
	var p := game.player
	p.health = 1e9
	var tc: TouchControls = game.hud.touch_ui
	var res := {"ok": true}
	var check := func(c: bool, what: String) -> void:
		print("[touch] %s %s" % ["OK" if c else "FAIL", what])
		if not c:
			res["ok"] = false
	if tc == null:
		check.call(false, "touch controls built (run with --touch-ui)")
		at.get_tree().quit()
		return
	var tag := "%dx%d" % [at.get_viewport().get_visible_rect().size.x, at.get_viewport().get_visible_rect().size.y]
	await at.get_tree().create_timer(1.0).timeout
	MolotovBelt.give(p)   # two special types: "+" on the special button
	await _wait(at, 0.3)
	await _snap(at, "touch_idle_" + tag)
	var r := tc.rects()
	var c := func(k: String) -> Vector2: return (r[k] as Rect2).get_center()
	# stick: press on the pad, push forward to the edge
	var pad := tc._pad_centre()
	_touch(at, tc, 0, pad, true)
	_drag(at, tc, 0, pad + Vector2(0, -200), Vector2(0, -200))
	await _wait(at, 0.1)
	check.call(p.move_input.y < -0.95, "stick forward %s" % p.move_input)
	# run: toggle on while moving
	var start := p.global_position
	_touch(at, tc, 1, c.call("run"), true)
	_touch(at, tc, 1, c.call("run"), false)
	await _wait(at, 0.6)
	check.call(tc.running() and Input.is_action_pressed("sprint") and p._running(), "run toggled on")
	var hv := Vector2(p.velocity.x, p.velocity.z).length()
	check.call(hv > 7.0, "running speed %.2f m/s" % hv)
	await _snap(at, "touch_run_" + tag)
	# jump
	_touch(at, tc, 2, c.call("jump"), true)
	await _wait(at, 0.15)
	check.call(p.velocity.y > 0.5 or p.global_position.y > start.y + 0.1, "jump (vy %.2f)" % p.velocity.y)
	await _snap(at, "touch_jump_" + tag)
	_touch(at, tc, 2, c.call("jump"), false)
	# fire held + drag on it aims (help text), with the stick still held
	var yaw := p.rotation.y
	var mag: int = p.weapon()["mag"]
	_touch(at, tc, 3, c.call("fire"), true)
	await _wait(at, 0.05)
	check.call(tc.held("fire") and p.weapon()["mag"] < mag, "fire pressed: shot (mag %d -> %d)" % [mag, p.weapon()["mag"]])
	await _snap(at, "touch_fire_" + tag)
	_drag(at, tc, 3, c.call("fire") + Vector2(-60, 0), Vector2(-60, 0))
	await _wait(at, 0.05)
	check.call(absf(p.rotation.y - yaw) > 0.01, "drag on fire turns (%.3f)" % (p.rotation.y - yaw))
	_touch(at, tc, 3, c.call("fire"), false)
	check.call(not p.fire_held, "fire released")
	# stick released: the run stops
	_touch(at, tc, 0, pad, false)
	await _wait(at, 0.1)
	check.call(p.move_input == Vector2.ZERO and not tc.running() and not Input.is_action_pressed("sprint"), "stick released, run off")
	# look drag in the free right area
	yaw = p.rotation.y
	var free := Vector2(tc.size.x * 0.6, tc.size.y * 0.3)
	_touch(at, tc, 4, free, true)
	_drag(at, tc, 4, free + Vector2(80, 0), Vector2(80, 0))
	_touch(at, tc, 4, free + Vector2(80, 0), false)
	await _wait(at, 0.05)
	check.call(absf(p.rotation.y - yaw) > 0.01, "look drag turns (%.3f)" % (p.rotation.y - yaw))
	# aim toggle
	var aim0 := p.aim_wanted
	_touch(at, tc, 5, c.call("aim"), true)
	_touch(at, tc, 5, c.call("aim"), false)
	check.call(p.aim_wanted != aim0, "aim button toggles")
	await _wait(at, 0.5)
	await _snap(at, "touch_aim_" + tag)
	if p.aim_wanted:
		p.toggle_aim()
	# special: selected grenade, double tap -> molotov
	var sel := tc.special_selected()
	tc._last_special_up = Time.get_ticks_msec() / 1000.0   # as if just tapped (no grenade thrown)
	_touch(at, tc, 6, c.call("special"), true)
	_touch(at, tc, 6, c.call("special"), false)
	check.call(sel == "grenade" and tc.special_selected() == "molotov", "double tap cycles special %s -> %s" % [sel, tc.special_selected()])
	await _wait(at, 0.1)
	await _snap(at, "touch_special_" + tag)
	tc.cycle_special()
	# interact: in reach of a wall buy, the hand appears; pressing holds interact
	var interact_ok := false
	if not game.wall_buys.is_empty():
		var b: Dictionary = game.wall_buys[0]
		var pos: Vector3 = b["position"]
		p.global_position = Vector3(pos.x, p.global_position.y, pos.z)
		await _wait(at, 0.3)
		r = tc.rects()
		if p.prompt != "":
			_touch(at, tc, 7, (r["interact"] as Rect2).get_center(), true)
			await _wait(at, 0.05)
			interact_ok = Input.is_action_pressed("interact")
			await _snap(at, "touch_interact_" + tag)
			_touch(at, tc, 7, (r["interact"] as Rect2).get_center(), false)
	check.call(interact_ok, "interact button shown and held near a wall buy (prompt '%s')" % p.prompt.replace("\n", " | "))
	check.call(not "E per" in p.prompt and not p.prompt.begins_with("Hold E") and not p.prompt.begins_with("Press E"),
		"the touch prompt names the hand, not a key (lang.gd)")
	# melee
	_touch(at, tc, 8, c.call("melee"), true)
	await _wait(at, 0.05)
	await _snap(at, "touch_melee_" + tag)
	_touch(at, tc, 8, c.call("melee"), false)
	# pause on the score icon
	_touch(at, tc, 9, c.call("pause"), true)
	await at.get_tree().process_frame
	check.call(at.get_tree().paused, "score icon pauses")
	await _snap(at, "touch_pause_" + tag)
	print("[touch] %s" % ("ALL OK" if res["ok"] else "SOME FAILED"))
	at.get_tree().quit()


static func _touch(at: Node, tc: Control, index: int, local: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = tc.get_global_transform_with_canvas() * local
	at.get_viewport().push_input(ev, true)


static func _drag(at: Node, tc: Control, index: int, local: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = tc.get_global_transform_with_canvas() * local
	ev.relative = rel
	at.get_viewport().push_input(ev, true)


static func _wait(at: Node, t: float) -> void:
	await at.get_tree().create_timer(t).timeout


static func _snap(at: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	at.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))
