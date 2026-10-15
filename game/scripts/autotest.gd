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
	var args := OS.get_cmdline_user_args()
	if args.has("--gib-test"):
		_gib_test.call_deferred()
	elif args.has("--knife-live"):
		_knife_live.call_deferred()
	elif args.has("--crawl-test"):
		_crawl_test.call_deferred()
	elif args.has("--powerup-test"):
		_powerup_test.call_deferred()
	elif args.has("--hud-test"):
		_hud_test.call_deferred()
	elif args.has("--hud-weapon-test"):   # weapon icon, ammo, reticle, headshot icon (hud_weapon_tests.gd)
		(func(): load("res://scripts/hud_weapon_tests.gd").run(self)).call_deferred()
	elif args.has("--touch-test"):   # original touch buttons, with --touch-ui (touch_hud_tests.gd)
		(func(): load("res://scripts/touch_hud_tests.gd").run(self)).call_deferred()
	elif args.has("--weapon-test"):   # grenade | raygun | flame | buy (weapon_tests.gd)
		(func(): WeaponTests.run(self)).call_deferred()
	elif args.has("--drink-test") or args.has("--teddy-test") or args.has("--music-test") or args.has("--egg-test") or args.has("--monkey-test"):   # extra_tests.gd
		(func(): ExtraTests.run(self)).call_deferred()
	elif args.has("--zombie-test"):   # rise | arm | speed (zombie_tests.gd)
		(func(): ZombieTests.run(self)).call_deferred()
	elif args.has("--wunder-test"):   # shot | grave (wunder_tests.gd, Wunderwaffe DG-2)
		(func(): load("res://scripts/wunder_tests.gd").run(self)).call_deferred()
	elif args.has("--swamp-test"):   # map | rise | zipline (swamp_tests.gd, Shi No Numa)
		(func(): load("res://scripts/swamp_tests.gd").run(self)).call_deferred()
	elif args.has("--endgame-test"):   # nuke | carpenter (endgame_tests.gd, radial power-up waves)
		(func(): load("res://scripts/endgame_tests.gd").run(self)).call_deferred()
	if args.has("--life-watch"):   # alongside the bot: round counters and corpses (lifecycle_tests.gd)
		var lw: Node = load("res://scripts/lifecycle_tests.gd").new()
		lw.game = game
		add_child(lw)
	if args.has("--zombie-watch"):   # alongside the bot: zombies slow to reach windows
		(func(): ZombieTests.watch(self)).call_deferred()
	var dir := ProjectSettings.globalize_path("res://../analysis/autotest")
	DirAccess.make_dir_recursive_absolute(dir)


func _process(delta: float) -> void:
	if OS.get_cmdline_user_args().has("--hud-test") or OS.get_cmdline_user_args().has("--hud-weapon-test") or OS.get_cmdline_user_args().has("--touch-test"):
		return
	if OS.get_cmdline_user_args().has("--weapon-test") or OS.get_cmdline_user_args().has("--zombie-test") or OS.get_cmdline_user_args().has("--swamp-test") or OS.get_cmdline_user_args().has("--wunder-test") or OS.get_cmdline_user_args().has("--endgame-test"):
		return
	if OS.get_cmdline_user_args().has("--drink-test") or OS.get_cmdline_user_args().has("--teddy-test") or OS.get_cmdline_user_args().has("--music-test") or OS.get_cmdline_user_args().has("--egg-test") or OS.get_cmdline_user_args().has("--monkey-test"):
		return
	if OS.get_cmdline_user_args().has("--gib-test") or OS.get_cmdline_user_args().has("--powerup-test") or OS.get_cmdline_user_args().has("--crawl-test") or OS.get_cmdline_user_args().has("--knife-live"):
		return
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
		for z in game.get_children():
			if z is Zombie and z.state == Zombie.State.TO_WINDOW and Vector2(z.velocity.x, z.velocity.z).length() < 0.1:
				print("[autotest]   to_window: pos=%s dist=%.1f vel=%.2f occupied=%s next=%s" % [z.global_position.snapped(Vector3(0.1, 0.1, 0.1)), z.global_position.distance_to(z.window.outside), Vector2(z.velocity.x, z.velocity.z).length(), z.window.occupied_by != null, z._agent.get_next_path_position().snapped(Vector3(0.1, 0.1, 0.1))])
		print("[autotest] t=%.0f round=%d points=%d hp=%.0f zombies=%s boards=%s%s" % [_t, game.round_number, p.points, p.health, states, boards, " PAUSED" if get_tree().paused else ""])
	_shot -= delta
	if _shot <= 0.0:
		_shot = 15.0
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://../analysis/autotest/t%03d.png" % int(_t)))
	if _t >= duration:
		get_tree().quit()



func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))


# Zombie in front of the player loses an arm, then its head: -- nacht --autotest 60 --gib-test
func _gib_test() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var p := game.player
	var z := Zombie.new()
	var fwd := -p.global_basis.z
	z.setup(p.global_position + fwd * 3.0, game.level.windows[0], p, 1e6, false)
	game.add_child(z)
	z.state = Zombie.State.ATTACK
	z.set_physics_process(false)
	z.look_at(p.global_position, Vector3.UP, true)
	await get_tree().create_timer(0.5).timeout
	await _snap("gib_0")
	z.lose_arm("left")
	await get_tree().create_timer(0.15).timeout
	await _snap("gib_1_arm")
	z.lose_head()
	await get_tree().create_timer(0.15).timeout
	await _snap("gib_2_head")
	await get_tree().create_timer(1.2).timeout
	await _snap("gib_3_later")
	get_tree().quit()


# Drop every power-up, screenshot them, then pick each and print the effect.
func _powerup_test() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var p := game.player
	var fwd := -p.global_basis.z
	var kinds: Array = Powerup.KINDS.keys()
	for i in kinds.size():
		game.spawn_powerup(kinds[i], p.global_position + fwd * 3.0 + p.global_basis.x * (i - 2) * 0.9)
	await get_tree().create_timer(0.6).timeout
	await _snap("powerups")
	# set up state to observe the effects
	p.weapons[0]["reserve"] = 0
	for w in game.level.windows:
		w.boards = 0
	var zs := []
	for i in 3:
		var z := Zombie.new()
		z.setup(p.global_position + fwd * 8.0 + Vector3(i, 0, 0), game.level.windows[0], p, 1e6, false)
		game.add_child(z)
		z.set_physics_process(false)
		zs.append(z)
	game.set_process(true)  # power-up timers
	var drops := game.get_children().filter(func(n): return n is Powerup)
	var spots := {}
	for pu in drops:
		spots[pu.kind] = pu.global_position
		pu.position.y -= 50.0  # out of reach until its turn
	for kind in spots:
		var pu: Powerup = drops.filter(func(n): return is_instance_valid(n) and n.kind == kind)[0]
		pu.global_position = spots[kind]
		var before_pts := p.points
		p.global_position = pu.global_position - Vector3.UP * 0.6
		await get_tree().create_timer(0.3).timeout
		var info := ""
		match kind:
			"maxammo": info = "reserve=%d" % p.weapons[0]["reserve"]
			"instakill": info = "insta_kill=%s" % game.insta_kill
			"doublepoints": info = "multiplier=%d" % game.points_multiplier
			"nuke":
				await get_tree().create_timer(1.0).timeout
				info = "zombies dead=%d/3 points +%d" % [zs.filter(func(z): return not is_instance_valid(z) or z.state == Zombie.State.DEAD).size(), p.points - before_pts]
			"carpenter": info = "boards=%s" % [game.level.windows.map(func(w): return w.boards)]
		print("[powerup] %s picked=%s %s" % [kind, not is_instance_valid(pu), info])
	get_tree().quit()


# A zombie loses its legs, crawls to the player and attacks: -- nacht --autotest 60 --crawl-test
func _crawl_test() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var p := game.player
	p.health = 1e9
	var fwd := -p.global_basis.z
	var z := Zombie.new()
	z.setup(p.global_position + fwd * 5.0, game.level.windows[0], p, 1e6, false)
	game.add_child(z)
	z.state = Zombie.State.CHASE
	await get_tree().create_timer(0.3).timeout
	z.become_crawler()
	await get_tree().create_timer(0.5).timeout
	await _snap("crawl_0")
	var t := 0.0
	var attacked := false
	while t < 20.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if z.state == Zombie.State.ATTACK:
			attacked = true
			await _snap("crawl_attack")
			break
	print("[crawl] crawler=%s reached and attacked=%s in %.1fs anim=%s" % [z.crawler, attacked, t, z._anim.current_animation])
	z.take_damage(1e7, false, p)
	await get_tree().create_timer(2.5).timeout
	await _snap("crawl_dead")
	get_tree().quit()


# Live knife fight: a chasing zombie (round-5 health) attacks, the player keeps knifing
# whatever is in front: -- nacht --autotest 60 --knife-live [--crawler]
func _knife_live() -> void:
	await game.level.wait_navigation()
	game.set_process(false)
	var args := OS.get_cmdline_user_args()
	if args.has("--round"):
		game.round_number = int(args[args.find("--round") + 1])
	var p := game.player
	p.health = 1e9
	var fwd := -p.global_basis.z
	var z := Zombie.new()
	if args.has("--round"):
		game.round_number = int(args[args.find("--round") + 1])
	z.setup(p.global_position + fwd * 4.0, game.level.windows[0], p, 400.0, false)
	game.add_child(z)
	print("[knife-live] round %d health %.0f" % [game.round_number, z.health])
	z.state = Zombie.State.CHASE
	if OS.get_cmdline_user_args().has("--crawler"):
		await get_tree().create_timer(0.2).timeout
		z.become_crawler()
		print("[knife-live] crawler health %.0f (max %.0f, %s)" % [z.health, z.max_health, game.level_name])
	var hits := 0
	for i in 24:
		await get_tree().create_timer(1.0).timeout
		# aim at the zombie like a player would (centre of its body)
		var target: Vector3 = z.global_position + Vector3.UP * (0.3 if z.crawler else 1.1)
		var to: Vector3 = target - (p.global_position + Vector3.UP * 1.6)
		p.rotation.y = atan2(-to.x, -to.z)
		p.get_viewport().get_camera_3d().rotation.x = 0.0 if OS.get_cmdline_user_args().has("--level-aim") else atan2(to.y, Vector2(to.x, to.z).length())
		var before := z.health
		if args.has("--round"):
			game.round_number = int(args[args.find("--round") + 1])
		p._melee_cooldown = 0.0
		p.melee()
		await get_tree().create_timer(Player.KNIFE_HIT_TIME + 0.05).timeout   # knifeDamage at 199 ms
		var dist := p.global_position.distance_to(z.global_position)
		var hit := z.health < before
		hits += int(hit)
		print("[knife-live] t=%d dist=%.2f state=%s hit=%s health=%.0f" % [i, dist, Zombie.State.keys()[z.state], hit, z.health])
		if z.state == Zombie.State.DEAD:
			break
	print("[knife-live] %s hits=%d" % ["OK" if z.state == Zombie.State.DEAD else "FAIL", hits])
	get_tree().quit()


# HUD (ui agent): points popups, WaW round counter, pause menu + settings:
#   -- nacht --autotest 120 --hud-test   (screenshots in analysis/preview/hud_*.png)
func _hud_test() -> void:
	await game.level.wait_navigation()
	var p := game.player
	p.health = 1e9
	var hud := game.hud
	await get_tree().create_timer(3.5).timeout
	await _snap("hud_round1")
	for n in [10, 60, 100, 10]:
		p.add_points(n)
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.15).timeout
	await _snap("hud_points_gain")
	await get_tree().create_timer(1.2).timeout
	p.add_points(-500)
	await get_tree().create_timer(0.3).timeout
	await _snap("hud_points_spent")
	for r in [2, 5, 6, 12]:
		hud.round_changed(r)
		await get_tree().create_timer(0.3).timeout
		if r == 2:
			await _snap("hud_round_flash")
		await get_tree().create_timer(4.5).timeout
		await _snap("hud_round%d" % r)
	# pause menu
	var before := Settings.values.duplicate()
	hud.open_pause()
	await get_tree().create_timer(0.3).timeout
	print("[hud-test] paused=%s menu=%s" % [get_tree().paused, hud._pause.is_open()])
	await _snap("hud_pause")
	hud._pause._show("settings")
	Settings.set_value("fov", 90.0)
	Settings.set_value("effects_volume", 0.5)
	await get_tree().create_timer(0.3).timeout
	await _snap("hud_settings")
	var cam := get_viewport().get_camera_3d()
	print("[hud-test] fov=%.0f effects_bus_db=%.1f buses=%s" % [cam.fov, AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Settings.BUS_EFFECTS)), range(AudioServer.bus_count).map(func(i): return AudioServer.get_bus_name(i))])
	var tagged := 0
	for n in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false) + get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		tagged += int(n.bus == Settings.BUS_EFFECTS)
	print("[hud-test] audio players on Effects bus: %d" % tagged)
	hud._pause._show("confirm")
	await get_tree().create_timer(0.2).timeout
	await _snap("hud_confirm")
	hud._pause.close()
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	print("[hud-test] saved fov=%s paused=%s" % [cfg.get_value("settings", "fov"), get_tree().paused])
	Settings.values = before
	Settings.save()
	Settings.set_value("fov", before["fov"])
	hud.open_pause()
	hud._pause._to_main_menu()
	await get_tree().create_timer(1.0).timeout
	var menus := get_tree().current_scene.get_children().filter(func(n): return n is Menu)
	print("[hud-test] back to menu: menu=%d game alive=%s paused=%s" % [menus.size(), is_instance_valid(game), get_tree().paused])
	await _snap("hud_back_menu")
	print("[hud-test] OK")
	get_tree().quit()

