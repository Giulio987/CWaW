# Checks for the ambient emitters, the character lines and the debris sounds:
#   -- <map> --sound-test    (nacht, verruckt, shinonuma, derriese)
# Emitters: the map's on-from-the-start CSoundEmitterSpec entities with the expected sound
# specs, each one audible near it and silent far away / a floor away. Lines (vox_lines.gd,
# with the level's vox forced on): ammo_low / ammo_out after shots, close_kill for a knife
# kill and a 0.8 m gun kill (not 5 m), weapon_bad / weapon_good, been_hit from a zombie.
extends Node

const EXPECTED := {
	"nacht": {"251efc07": 3, "f14c76c6": 2, "105f1846": 1},
	"verruckt": {"983b03d2": 4, "360c877f": 2, "f8ec2453": 1, "f00abdd9": 1},
	"shinonuma": {"91501f52": 30, "b3e7c00b": 11},
	"derriese": {"f00abdd9": 1},
}

var game: Game
var fails := 0


static func start(parent: Node, game_: Game, _args: PackedStringArray) -> void:
	var t: Node = load("res://scripts/sound_tests.gd").new()
	t.game = game_
	parent.add_child(t)
	t._run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("[sound] %s: %s" % ["OK" if ok else "FAIL", what])
	fails += int(not ok)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _asked(line: String, from: int) -> Array:
	var out := []
	for e in VoxLines.instance.log_lines.slice(from):
		if e[0] == line:
			out.append(e)
	return out


func _run() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var lv := game.level
	var p := game.player
	p.health = 1e6
	await _frames(5)
	# ---- ambient emitters
	var amb := game.get_node_or_null("AmbientEmitters") as AmbientEmitters
	_check(amb != null, "AmbientEmitters created")
	var counts := {}
	for em in amb.emitters:
		counts[em.spec] = counts.get(em.spec, 0) + 1
	var want: Dictionary = EXPECTED.get(lv.level_name, {})
	_check(counts == want, "emitters %s (expected %s)" % [counts, want])
	for em in amb.emitters:
		if Sfx.instance._stream(em.spec) == null:
			_check(false, "%s has no sound %s" % [em.name, em.spec])
	if not amb.emitters.is_empty():
		var em: AmbientEmitters.Emitter = amb.emitters[0]
		var prm := AmbientEmitters.spec_params(em.spec)
		print("[sound] %s spec %s: vol %d..%d, dist %d..%d units, height range %.1f m" % [em.name, em.spec, prm[0], prm[1], prm[4], prm[5], em.range_m])
		p.global_position = em.global_position + Vector3(0.5, -1.6, 0.0)   # camera about at its height
		p.velocity = Vector3.ZERO
		await _frames(6)
		var cam := get_viewport().get_camera_3d()
		print("[sound] camera %s, emitter %s" % [cam.global_position, em.global_position])
		_check(em.volume > 0.0 and em._player.playing and not em._player.stream_paused,
			"near %s: playing at volume %.2f (%.1f dB)" % [em.name, em.volume, em._player.volume_db])
		_check(is_zero_approx(em.compute_volume(em.global_position + Vector3(float(prm[5]) / 400.0 + 1.0, 0, 0))), "silent beyond its max distance")
		_check(is_zero_approx(em.compute_volume(em.global_position + Vector3(0.3, em.range_m + 0.2, 0))), "silent %.1f m above (height range)" % (em.range_m + 0.2))
		_check(absf(em.compute_volume(em.global_position) - float(prm[1]) / 4096.0) < 0.01, "full spec volume at the emitter")
	# ---- debris sounds
	for d: Debris in lv.debris:
		var ok: bool = d.open_sound == "" or Sfx.instance._stream(d.open_sound) != null
		_check(ok, "%s opens with %s" % [d.entity, d.open_sound if d.open_sound != "" else "(no sound, as its ASM)"])
	# ---- character lines
	Sfx.instance.using_vox = true
	var vl := VoxLines.instance
	_check(vl != null, "VoxLines created")
	p.give_weapon("colt45")
	var w := p.weapon()
	w["mag"] = 3
	w["reserve"] = 0
	await _frames(2)
	var n0 := vl.log_lines.size()
	w["mag"] = 2   # a shot: 2 x 100 / 8 <= 35 %
	await _frames(2)
	var low := _asked("ammo_low", n0)
	_check(low.size() == 1 and low[0][1], "ammo_low when the shot makes the gun low %s" % [low])
	w["mag"] = 1
	await _frames(2)
	_check(_asked("ammo_low", n0).size() == 1 and _asked("ammo_out", n0).is_empty(), "no line for a shot while already low")
	w["mag"] = 0
	await _frames(2)
	_check(_asked("ammo_out", n0).size() == 1, "ammo_out on the last round")
	# close kills
	var n1 := vl.log_lines.size()
	var fwd := -p.global_basis.z
	for c in [[0.8, true], [0.8, false], [5.0, false]]:
		var z := Zombie.new()
		z.setup(p.global_position + fwd * float(c[0]), lv.windows[0], p, 100.0, false)
		game.add_child(z)
		z.state = Zombie.State.CHASE
		z.set_physics_process(false)
		await _frames(1)
		z.global_position = p.global_position + fwd * float(c[0])
		z.take_damage(1e6, false, p, c[1])
		await _frames(1)
	var ck := _asked("close_kill", n1)
	_check(ck.size() == 2, "close_kill asked for the knife kill and the 0.8 m kill, not at 5 m (%d)" % ck.size())
	# box lines
	var n2 := vl.log_lines.size()
	VoxLines.box_shown("kar98")
	VoxLines.box_shown("thompson")
	VoxLines.box_taken("trenchgun")
	VoxLines.box_taken("mp40")
	_check(_asked("weapon_bad", n2).size() == 1 and _asked("weapon_good", n2).size() == 1, "weapon_bad for the Kar98k, weapon_good for the trench gun, nothing for the others")
	# been_hit from a zombie attack
	var n3 := vl.log_lines.size()
	var za := Zombie.new()
	za.setup(p.global_position + fwd * 0.6, lv.windows[0], p, 100.0, false)
	game.add_child(za)
	await _frames(1)
	za.global_position = p.global_position + fwd * 0.6
	za.state = Zombie.State.ATTACK
	za._timer = 1.0
	za._hit_done = false
	var t0 := Time.get_ticks_msec()
	while _asked("been_hit", n3).is_empty() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().physics_frame
	_check(not _asked("been_hit", n3).is_empty(), "been_hit when a zombie hits the player")
	print("[sound] lines asked: %s" % [vl.log_lines.map(func(e): return "%s%s" % [e[0], "" if e[1] else "(skipped)"])])
	print("[sound] %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()
