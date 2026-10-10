# Headless-ish smoke test: a bot aims at the nearest zombie and shoots, while
# we log game state and save screenshots. Run with:
#   Godot --path game -- nacht --autotest 90
class_name AutoTest
extends Node

var game: Game
var duration := 60.0
var _t := 0.0
var _shot := 0.0
var _log_t := 0.0
var _kills := 0


func _ready() -> void:
	var dir := ProjectSettings.globalize_path("res://../analysis/autotest")
	DirAccess.make_dir_recursive_absolute(dir)


func _process(delta: float) -> void:
	_t += delta
	if game.player == null:
		return
	var p := game.player
	p.health = max(p.health, 60.0)  # keep the bot alive for the test
	var best: Zombie = null
	var best_d := 1e9
	for z in game.get_children():
		if z is Zombie and z.state != Zombie.State.DEAD:
			var d := p.global_position.distance_to(z.global_position)
			if d < best_d:
				best_d = d
				best = z
	p.fire_held = false
	if best and best.state in [Zombie.State.CHASE, Zombie.State.ATTACK] and best_d < 15.0:
		var to := best.global_position + Vector3.UP * 1.2 - (p.global_position + Vector3.UP * 1.6)
		p.rotation.y = atan2(-to.x, -to.z)
		var cam: Camera3D = p.get_viewport().get_camera_3d()
		cam.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
		p.fire_held = true
		if best_d < 1.6:
			p.melee()
		if p.weapon()["mag"] == 0 and p.weapon()["reserve"] == 0:
			p.weapon()["reserve"] = 32
	_log_t -= delta
	if _log_t <= 0.0:
		_log_t = 5.0
		var states := {}
		for z in game.get_children():
			if z is Zombie:
				var k: String = Zombie.State.keys()[z.state]
				states[k] = states.get(k, 0) + 1
		var boards := game.level.windows.map(func(w): return w.boards) if game.level else []
		print("[autotest] t=%.0f round=%d points=%d hp=%.0f zombies=%s boards=%s" % [_t, game.round_number, p.points, p.health, states, boards])
	_shot -= delta
	if _shot <= 0.0:
		_shot = 15.0
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://../analysis/autotest/t%03d.png" % int(_t)))
	if _t >= duration:
		get_tree().quit()

