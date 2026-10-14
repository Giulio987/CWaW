# Mystery box timeline from the ASM (mystery_box.gd), screenshots from the front and the side
# in analysis/preview/boxa_*.png:
#   -- nacht --box-anim-test            open, rise, offer, lower, close (times printed)
#   -- derriese --box-anim-test teddy   the bear: wait, rise, flight, fall at the new spot
extends Node

var game: Game
var fails := 0
var _cam: Camera3D
var _clock := -1.0   # game time since the purchase (screenshots stall the wall clock)


static func start(parent: Node, game_: Game, args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/box_anim_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	var i := args.find("--box-anim-test")
	var which := args[i + 1] if i + 1 < args.size() and not args[i + 1].begins_with("--") else "weapon"
	t._run.call_deferred(which)


func _check(ok: bool, what: String) -> void:
	print("[boxa] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _process(delta: float) -> void:
	if _clock >= 0.0:
		_clock += delta
		if delta > 0.5:
			print("[boxa] long frame %.2f s at %.2f" % [delta, _clock])


func _now() -> float:
	return _clock


# front (+Z of the box, or -Z when that side is walled) and side views, cameras placed
# where a ray from the box reaches them
func _free(from: Vector3, to: Vector3) -> Vector3:
	var space := game.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	return to if hit.is_empty() else from.lerp(hit["position"], 0.85)


func _shots(box: MysteryBox, name: String) -> void:
	var xf := box.global_transform
	var at := xf.origin + Vector3.UP * 0.8
	var fwd := xf.basis.z.normalized()
	if _free(at, at + fwd * 2.2).distance_to(at) < _free(at, at - fwd * 2.2).distance_to(at):
		fwd = -fwd
	var side := xf.basis.x.normalized()
	if _free(at, at + side * 2.2).distance_to(at) < _free(at, at - side * 2.2).distance_to(at):
		side = -side
	for v in [["front", fwd * 2.2 + Vector3.UP * 0.5], ["side", (side + fwd * 0.6).normalized() * 2.6 + Vector3.UP * 0.6]]:
		_cam.global_position = _free(at, at + v[1])
		_cam.look_at(at, Vector3.UP)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/boxa_%s_%s.png" % [name, v[0]]))
	print("[boxa] %.2f s %s state=%s weapon=%s" % [_now(), name, MysteryBox.State.keys()[box.state],
		"-" if box.get("_weapon") == null else str((box.get("_weapon") as Node3D).position)])


func _at(t: float) -> void:
	while _now() < t:
		await get_tree().process_frame


func _run(which: String) -> void:
	await game.level.wait_navigation()
	game.set_process(false)   # no waves
	var box: MysteryBox = game.level.boxes[0]
	var p := game.player
	p.points = 5000
	p.health = 1e9
	_cam = Camera3D.new()
	_cam.near = 0.02
	game.add_child(_cam)
	_cam.make_current()
	get_tree().paused = false
	await get_tree().create_timer(0.5).timeout
	_clock = 0.0
	if which == "teddy":
		box.set("_teddy_next", true)
		var from := box.entity
		box.interact(p)
		for t in [0.7, 1.6, 3.5, 5.5, 6.0, 7.5, 8.5, 9.5, 11.0, 13.0]:
			await _at(t)
			await _shots(box, "teddy_%04.1f" % t)
		_check(box.state in [MysteryBox.State.LEAVING, MysteryBox.State.GONE], "flying away at 13 s (%s)" % MysteryBox.State.keys()[box.state])
		await _at(15.0)
		_check(box.entity != from, "moved %s -> %s" % [from, box.entity])
		for t in [15.2, 16.5, 18.0, 19.5, 21.0]:
			await _at(t)
			await _shots(box, "teddy_%04.1f" % t)
		_check(box.state == MysteryBox.State.CLOSED, "closed at the new spot (%s)" % MysteryBox.State.keys()[box.state])
	else:
		await _shots(box, "w_00.0_closed")
		box.interact(p)
		for t in [0.7, 1.4, 1.6, 3.5, 5.3, 6.0, 12.0, 17.6, 19.5, 21.2, 22.0, 22.6]:
			await _at(t)
			await _shots(box, "w_%04.1f" % t)
			if t == 1.4:
				_check(box.get("_weapon") == null, "no weapon before the lid is open")
			if t == 6.0:
				_check(box.state == MysteryBox.State.OFFERED, "offered at 6 s")
			if t == 19.5:
				_check(box.state == MysteryBox.State.LOWERING and box.prompt(p) != "", "lowering, still takeable")
		_check(box.state == MysteryBox.State.CLOSED, "closed at 22.6 s (%s)" % MysteryBox.State.keys()[box.state])
	print("[boxa] done, %d failures" % fails)
	get_tree().quit()
