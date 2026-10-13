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
	elif args.has("--extras-test"):
		t._extras_test()


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


# -- derriese --extras-test: derriese_extras.gd (start sequence, dropping doors, map boards,
# genElectric, SeeTeleporterTrigger, mainframe steam) and the delayed generator timings.
func _extras_test() -> void:
	const TAG := "extras"
	var lv := game.level
	var p := game.player
	var x := lv.nav_region.get_node_or_null("DerrieseExtras") as DerrieseExtras
	_check(TAG, x != null, "DerrieseExtras built")
	if x == null:
		get_tree().quit()
		return
	var net := lv.teleporters
	var door_y0: float = net._door.position.y
	_check(TAG, absf(door_y0 - (net._door_closed_y - TeleporterNetwork.DOOR_DROP[3])) < 0.01, "mainframe door starts down (ASM S0 open): %.2f" % door_y0)
	await lv.wait_navigation()
	game.set_process(false)
	p.health = 1e9
	var mf: Vector3 = lv.entity_transform("mainframe_door").origin
	var mf_from := mf + Vector3(0, 2.0, -7.0)
	await get_tree().create_timer(1.2).timeout
	await _shot("extras_mainframe_closing", mf_from, mf + Vector3.UP * 1.5)
	await get_tree().create_timer(6.0).timeout
	print("[%s] start log %s" % [TAG, x.start_log])
	var want := {"doorClose": 0.5, "pa_level_start": 2.5, "power_out": 6.5}
	for e in x.start_log:
		_check(TAG, absf(float(e[0]) - float(want.get(e[1], -9.0))) < 0.25, "%s at %.2f s (lua %.1f s)" % [e[1], e[0], want.get(e[1], -1.0)])
	_check(TAG, x.start_log.size() == 3, "3 start events")
	_check(TAG, absf(net._door.position.y - net._door_closed_y) < 0.01, "mainframe door closed after the start")
	await _shot("extras_mainframe_closed", mf_from, mf + Vector3.UP * 1.5)
	await _shot("extras_mainframe_closed_side", mf + Vector3(5.0, 2.0, -3.0), mf + Vector3.UP * 1.5)
	# dropping doors: closed and solid before the power
	_check(TAG, x.drop_doors.size() == 2, "2 dropping doors")
	var space := game.get_world_3d().direct_space_state
	var mids := []
	for d in x.drop_doors:
		var holder: Node3D = d["holder"]
		var model: Node3D = d["model"]
		var mid: Vector3 = holder.global_transform * (model.position + Vector3(1.6, 1.0, -0.27))
		var nrm: Vector3 = holder.global_basis.z.normalized()
		mids.append([mid, nrm])
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + nrm * 2.0, mid - nrm * 2.0, 1))
		_check(TAG, not hit.is_empty() and (hit["collider"] as Node).name == "Blocker", "%s blocks before the power (%s)" % [d["entity"], "nothing" if hit.is_empty() else hit["collider"].name])
		await _shot("extras_%s_closed_front" % d["entity"], mid + nrm * 5.0 + Vector3.UP * 0.6, mid)
		await _shot("extras_%s_closed_back" % d["entity"], mid - nrm * 5.0 + Vector3.UP * 0.6, mid)
		await _shot("extras_%s_closed_side" % d["entity"], mid + nrm * 3.5 + holder.global_basis.x * 3.5 + Vector3.UP * 1.0, mid)
		# the player cannot walk through
		p.global_position = mid + nrm * 1.2 + Vector3.DOWN * 0.9
		p.velocity = Vector3.ZERO
		for i in 5:
			await get_tree().physics_frame
		var end := await _walk(p, -nrm, 2.0)
		_check(TAG, (end - mid).dot(nrm) > 0.0, "%s: walking into it stops in front (%.2f m)" % [d["entity"], (end - mid).dot(nrm)])
	# boards, genElectric before the power
	_check(TAG, x.tele_maps.size() == 3 and x.mystery_maps.size() == 6, "3 teleporter + 6 mystery boards (%d, %d)" % [x.tele_maps.size(), x.mystery_maps.size()])
	_check(TAG, x.tele_map_state == "off", "teleporter boards off: %s" % x.tele_map_state)
	_check(TAG, x._gen_electric.size() == 6 and x._gen_electric.all(func(n): return not n.visible), "genElectric6-11 hidden")
	var box: MysteryBox = lv.boxes[0]
	_check(TAG, x.mystery_map_pose == DerrieseExtras.BOX_MAP_ANIMS.get(box.entity, "?"), "mystery boards on %s (%s)" % [box.entity, x.mystery_map_pose])
	await _board_shots(x, "TeleporterMapA", "extras_telemap_off")
	await _board_shots(x, "mysteryMap_lab", "extras_mysterymap")
	for n in ["TeleporterMapB", "TeleporterMapC", "mysteryMap_power", "mysteryMap_powerTele", "mysteryMap_labTele", "mysteryMap_garage", "mysteryMap_garageTele"]:
		await _board_shots(x, n, "extras_board_" + n)
	var ge: Vector3 = (x._gen_electric[0] as Node3D).global_position
	await _shot("extras_genelectric_off", ge + Vector3(0, 0.5, 4.0), ge)
	# SeeTeleporterTrigger: in the volume, looking at the Pack-a-Punch
	var see: AABB = x._see_box
	p.global_position = see.get_center() - Vector3(0, see.size.y * 0.5 - 0.05, 0)
	p.velocity = Vector3.ZERO
	await get_tree().physics_frame
	_face(p, lv.entity_transform("packapunch").origin + Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	_check(TAG, x.see_teleporter_done, "see_teleporter line in SeeTeleporterTrigger looking at the Pack-a-Punch")
	# power: pa_power_on after 1 s, doors drop, Trap_power 4.3 s later
	lv.turn_on_power()
	var tp: Trap = null
	for t in lv.traps:
		if t.entity == "Trap_power":
			tp = t
	_check(TAG, tp != null and not tp.gen_on, "Trap_power not powered at once")
	await get_tree().create_timer(0.4).timeout
	var d0: Dictionary = x.drop_doors[0]
	await _shot("extras_%s_dropping" % d0["entity"], mids[0][0] + mids[0][1] * 5.0 + Vector3.UP * 0.6, mids[0][0])
	await get_tree().create_timer(1.0).timeout
	_check(TAG, x.tele_map_state == "tele", "teleporter boards powered: %s" % x.tele_map_state)
	_check(TAG, x._gen_electric.all(func(n): return n.visible), "genElectric6-11 shown")
	for i in x.drop_doors.size():
		var d: Dictionary = x.drop_doors[i]
		var mid: Vector3 = mids[i][0]
		var nrm: Vector3 = mids[i][1]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + nrm * 2.0, mid - nrm * 2.0, 1))
		_check(TAG, d["open"] and hit.is_empty(), "%s dropped, the way is clear (%s)" % [d["entity"], "clear" if hit.is_empty() else hit["collider"].name])
		await _shot("extras_%s_open_front" % d["entity"], mid + nrm * 5.0 + Vector3.UP * 0.6, mid)
		await _shot("extras_%s_open_side" % d["entity"], mid + nrm * 3.5 + (d["holder"] as Node3D).global_basis.x * 3.5 + Vector3.UP * 1.0, mid)
	await _shot("extras_genelectric_on", ge + Vector3(0, 0.5, 4.0), ge)
	await get_tree().create_timer(3.2).timeout
	_check(TAG, tp != null and tp.gen_on, "Trap_power powered after 4.3 s")
	# walk through the Lab door's opening once the navmesh is rebuilt
	await lv.wait_navigation()
	p.global_position = mids[0][0] + mids[0][1] * 1.2 + Vector3.DOWN * 0.9
	p.velocity = Vector3.ZERO
	for i in 5:
		await get_tree().physics_frame
	var through := await _walk(p, -mids[0][1], 2.0)
	_check(TAG, (through - mids[0][0]).dot(mids[0][1]) < -0.5, "walked through %s (%.2f m)" % [d0["entity"], (through - mids[0][0]).dot(mids[0][1])])
	# teleporter boards: linking blinks, a link shows the peer
	var pad: TeleporterNetwork.Pad = net.pads[0]
	net.interact_with(pad, p)
	await get_tree().create_timer(0.7).timeout
	_check(TAG, x.tele_map_blinking and x.tele_map_state == "tele", "peer A linking: boards blink (%s)" % x.tele_map_state)
	await _board_shots(x, "TeleporterMapA", "extras_telemap_linking")
	net.interact_with(net.mainframe, p)
	await get_tree().create_timer(0.7).timeout
	_check(TAG, x.tele_map_state == "tele1" and not x.tele_map_blinking, "peer A linked: %s" % x.tele_map_state)
	await _board_shots(x, "TeleporterMapA", "extras_telemap_tele1")
	await _shot("extras_mainframe_first_open", mf_from, mf + Vector3.UP * 1.5)
	_check(TAG, absf(net._door.position.y - (net._door_closed_y - TeleporterNetwork.DOOR_DROP[1])) < 0.01, "firstOpen: the door sinks %.2f m" % TeleporterNetwork.DOOR_DROP[1])
	# mystery boards follow the box
	var before := x.mystery_map_pose
	box._warp()
	_check(TAG, x.mystery_map_pose == DerrieseExtras.BOX_MAP_ANIMS.get(box.entity, "?") and x.mystery_map_pose != before, "box moved to %s: boards %s" % [box.entity, x.mystery_map_pose])
	await _board_shots(x, "mysteryMap_lab", "extras_mysterymap_moved")
	# mainframe steam: 3 s after arriving, for 8 s
	net.arrived.emit()
	await get_tree().create_timer(2.7).timeout
	_check(TAG, not x.steam_on(), "no steam before 3 s")
	await get_tree().create_timer(0.6).timeout
	_check(TAG, x.steam.size() == 5 and x.steam_on(), "mainframe steam on at 3 s (%d vents)" % x.steam.size())
	await get_tree().create_timer(1.5).timeout
	await _shot("extras_mainframe_steam", mf + Vector3(0, 6.0, -12.0), mf + Vector3(0, 6.0, 2.0))
	await get_tree().create_timer(6.7).timeout
	_check(TAG, not x.steam_on(), "steam off after 8 s")
	print("[%s] %s (%d failures)" % [TAG, "OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()


# A board from the front (both faces tried: +z and -z of its frame) and from a side.
func _board_shots(x: DerrieseExtras, entity: String, prefix: String) -> void:
	var b := x.get_node_or_null("Board_" + entity) as Node3D
	if b == null:
		_check("extras", false, "board %s" % entity)
		return
	var c := b.global_transform * Vector3(0, 0.6 if entity.begins_with("mystery") else 1.3, 0)
	var z := b.global_basis.z.normalized()
	await _shot(prefix + "_z", c + z * 2.5, c)
	await _shot(prefix + "_side", c + z * 1.8 + b.global_basis.x.normalized() * 1.8, c)
