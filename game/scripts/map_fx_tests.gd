# Checks for tele_fx.gd / effect_emitter.gd, map_props.gd and the barricades with their own
# rig (barricade.gd); screenshots in analysis/preview:
#   -- derriese --telefx-test                     teleport from pad A: leave/arrive effects
#   -- verruckt|shinonuma|derriese --stands-test  box stands: hidden under the box, shown elsewhere
#   -- nacht|verruckt --altwin-test               barricades 4b84e4d2 & co.: rig, 6 boards, sounds
#   -- derriese --panel-test                      the Link_oLC_L_Trigger1 panel
class_name MapFxTests
extends Node

var game: Game
var fails := 0
var _cam: Camera3D


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t := MapFxTests.new()
	t.game = game_
	parent.add_child(t)
	if args.has("--telefx-test"):
		t._telefx_test()
	elif args.has("--stands-test"):
		t._stands_test()
	elif args.has("--altwin-test"):
		t._altwin_test()
	elif args.has("--panel-test"):
		t._panel_test()


func _check(tag: String, ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [tag, "OK" if ok else "FAIL", what])
	fails += int(not ok)


func _done(tag: String) -> void:
	print("[%s] %s (%d failures)" % [tag, "PASS" if fails == 0 else "FAILED", fails])
	get_tree().quit()


func _shot(name: String, from: Vector3, at: Vector3, frames := 4) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 400.0
		game.add_child(_cam)
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP if absf((at - from).normalized().y) < 0.99 else Vector3.FORWARD)
	_cam.make_current()
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))


func _quiet() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	game.player.health = 1e9
	game.player.set_physics_process(false)


func _telefx_test() -> void:
	const TAG := "telefx"
	await _quiet()
	var lv := game.level
	var net := lv.teleporters
	lv.turn_on_power()
	var pad: TeleporterNetwork.Pad = net.pads[0]
	var at := lv.entity_transform("TeleporterPeerA_fxSpawn").origin
	var main := lv.entity_transform("TeleporterMain_fxSpawn").origin
	TeleFx.log.clear()
	pad.state = "linked"
	pad.start_timer = TeleporterNetwork.START_TIME
	net._start_teleport(pad)
	_check(TAG, TeleFx.log.size() == 1 and TeleFx.log[0] == ["teleporterLeave", "TeleporterPeerA_fxSpawn"], "start: teleporterLeave at the pad %s" % [TeleFx.log])
	await get_tree().create_timer(0.4).timeout
	var ems := lv.find_children("*", "EffectEmitter", false, false)
	_check(TAG, ems.size() == 1, "one flame emitter at the pad (%d)" % ems.size())
	await _shot("telefx_leave_front", at + Vector3(0, 1.6, 6.0), at + Vector3.UP * 1.2, 1)
	await _shot("telefx_leave_side", at + Vector3(6.0, 1.6, 0.5), at + Vector3.UP * 1.2, 1)
	await get_tree().create_timer(0.5).timeout
	_check(TAG, TeleFx.log.any(func(e): return e == ["teleporterArrive", "TeleporterMain_fxSpawn"]), "750 ms later: teleporterArrive at the mainframe")
	await _shot("telefx_arrive_front", main + Vector3(0, 1.6, 6.0), main + Vector3.UP * 1.2, 1)
	await _shot("telefx_arrive_side", main + Vector3(6.0, 1.6, 0.5), main + Vector3.UP * 1.2, 1)
	await get_tree().create_timer(3.4).timeout   # flames: 4 s + 0.2 s of particle life
	_check(TAG, TeleFx.log.any(func(e): return e[0] == "teleporterLeave2"), "after the flames: teleporterLeave2 (sparks) %s" % [TeleFx.log])
	await _shot("telefx_sparks_front", at + Vector3(0, 1.6, 6.0), at + Vector3.UP * 1.2, 1)
	await _shot("telefx_sparks_side", at + Vector3(6.0, 1.6, 0.5), at + Vector3.UP * 1.2, 1)
	await get_tree().create_timer(0.8).timeout
	_check(TAG, TeleFx.log.any(func(e): return e[0] == "teleporterArrive2"), "then teleporterArrive2 (beams)")
	await get_tree().create_timer(4.0).timeout
	ems = lv.find_children("*", "EffectEmitter", false, false)
	_check(TAG, ems.is_empty(), "all emitters gone after their particles (%d left)" % ems.size())
	_done(TAG)


const STAND_COUNT := {"verruckt": 5, "shinonuma": 6, "derriese": 6}


func _stands_test() -> void:
	const TAG := "stands"
	await _quiet()
	var lv := game.level
	var mp := lv.get_node_or_null("MapProps") as MapProps
	_check(TAG, mp != null and mp.stands.size() == STAND_COUNT.get(lv.level_name, 0), "%d stands" % (mp.stands.size() if mp else -1))
	var box: MysteryBox = lv.boxes[0]
	await get_tree().create_timer(0.3).timeout
	for loc in mp.stands:
		var s: Node3D = mp.stands[loc]
		_check(TAG, s.visible == (loc != box.entity), "%s: %s" % [loc, "hidden (box here)" if not s.visible else "shown"])
	# the box location and an empty one, front and side
	var other: String = mp.stands.keys().filter(func(n): return n != box.entity)[0]
	for pair in [[box.entity, "box"], [other, "empty"]]:
		var s: Node3D = mp.stands[pair[0]]
		var c: Vector3 = s.global_position + Vector3.UP * 0.4
		var front: Vector3 = s.global_basis.z
		await _shot("stand_%s_%s_front" % [lv.level_name, pair[1]], c + front * 2.6 + Vector3.UP * 0.9, c)
		await _shot("stand_%s_%s_side" % [lv.level_name, pair[1]], c + s.global_basis.x * 2.8 + front * 0.6 + Vector3.UP * 0.7, c)
	# the box moves away: its old stand shows up, the new location's hides
	var from := box.entity
	box._vanish()
	await get_tree().create_timer(0.4).timeout
	_check(TAG, mp.stands[from].visible, "box gone: stand at %s shown" % from)
	await get_tree().create_timer(1.0).timeout
	_check(TAG, box.entity != from and not mp.stands[box.entity].visible, "box landed at %s: its stand hidden" % box.entity)
	_done(TAG)


func _altwin_test() -> void:
	const TAG := "altwin"
	await _quiet()
	var lv := game.level
	var alts := lv.windows.filter(func(w): return w.rig != "fee7f210")
	var want := 1 if lv.level_name == "nacht" else 3
	_check(TAG, alts.size() == want, "%d barricades with their own rig %s" % [alts.size(), alts.map(func(w): return [w.name, w.rig])])
	for w: Barricade in alts:
		_check(TAG, w.max_boards == 6 and w.boards == 6 and w._anim != null and w._anim.has_animation("16491731"),
			"%s: rig %s, 6 boards, pose animations" % [w.name, w.rig])
		_check(TAG, w.break_sound == "43dd4a39" and w.repair_sound == "e3f3e537", "%s: sounds 43dd4a39 / e3f3e537" % w.name)
		var n := w.normal
		var c := w.global_position + Vector3.UP * 1.2
		var side := n.cross(Vector3.UP)
		var tag := "%s_%s" % [lv.level_name, w.rig]
		await _shot("altwin_%s_6_in" % tag, c + n * 2.5, c)
		await _shot("altwin_%s_6_out" % tag, c - n * 2.5, c)
		await _shot("altwin_%s_6_side" % tag, c + n * 1.4 + side * 1.6, c)
		w.tear_board()
		w.tear_board()
		w.tear_board()
		await _shot("altwin_%s_3_in" % tag, c + n * 2.5, c)
		while w.tear_board():
			pass
		await _shot("altwin_%s_0_in" % tag, c + n * 2.5, c)
		var k := 0
		while w.repair_board():
			k += 1
		_check(TAG, k == 6 and w.boards == 6, "%s: 6 repairs back to 6 boards (%d)" % [w.name, k])
	# a normal one for comparison
	var normal: Barricade = lv.windows.filter(func(w): return w.rig == "fee7f210")[0]
	_check(TAG, normal.max_boards == 5 and normal.break_sound == "window_break1", "normal barricades: 5 boards, window_break1")
	_done(TAG)


func _panel_test() -> void:
	const TAG := "panel"
	await _quiet()
	var mp := game.level.get_node_or_null("MapProps") as MapProps
	_check(TAG, mp != null and mp.panel != null, "panel built")
	if mp == null or mp.panel == null:
		_done(TAG)
		return
	var c := mp.panel.global_position
	var n := mp.panel.global_basis.z
	await _shot("panel_front", c + n * 9.0 + Vector3.DOWN * 5.0, c)
	await _shot("panel_back", c - n * 9.0 + Vector3.DOWN * 5.0, c)
	await _shot("panel_side", c + mp.panel.global_basis.x * 8.0 + n * 3.0 + Vector3.DOWN * 4.0, c)
	await _shot("panel_far", c + n * 18.0 + Vector3.DOWN * 6.5, c)
	# hand: rest 1.5 s, jerk 0.291 s with the clank, back
	var t0 := mp.panel_ticks
	await get_tree().create_timer(1.6).timeout
	_check(TAG, mp.panel_ticks > t0, "the hand ticks (%d)" % mp.panel_ticks)
	await _shot("panel_tick", c + n * 7.0 + Vector3.DOWN * 3.0, c, 1)
	await get_tree().create_timer(4.0).timeout
	_check(TAG, mp.panel_ticks >= t0 + 3, "every 1.79 s (%d ticks in ~5.6 s)" % (mp.panel_ticks - t0))
	_done(TAG)
