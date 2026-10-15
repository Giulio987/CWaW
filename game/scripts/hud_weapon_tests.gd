# Weapon HUD checks (weapon_hud.gd, aiming_reticle.gd, powerup_frame.gd headshot/repair,
# prompts of the box, debris and flogger). Prints OK/FAIL; screenshots in
# analysis/preview/hudw_*.png:
#   tools/run_godot.sh 120 -- nacht --autotest 100 --hud-weapon-test
extends RefCounted


static func run(at: Node) -> void:
	var game: Game = at.game
	await game.level.wait_navigation()
	var p := game.player
	p.health = 1e9
	var hud: Hud = game.hud
	var wh: WeaponHud = hud._weapon_hud
	var ret: AimingReticle = hud._reticle
	var res := {"ok": true}
	var check := func(c: bool, what: String) -> void:
		print("[hud-weapon] %s %s" % ["OK" if c else "FAIL", what])
		if not c:
			res["ok"] = false
	await at.get_tree().create_timer(1.0).timeout
	# clip display modes from the original thresholds
	for t in [["colt45", 8, "vertical"], ["raygun", 20, "vertical"], ["kar98", 5, "bitmap"],
			["trenchgun", 6, "bitmap"], ["wunderwaffe", 3, "bitmap"], ["mp40", 32, "horizontal"],
			["ppsh", 71, "half"], ["mg42", 125, "half"], ["thompson", 20, "vertical"], ["type100", 30, "horizontal"]]:
		check.call(WeaponHud.clip_mode(t[0], t[1]) == t[2], "%s mag %d -> %s (%s)" % [t[0], t[1], WeaponHud.clip_mode(t[0], t[1]), t[2]])
	check.call(WeaponHud.clip_low(2, 8) and WeaponHud.clip_low(1, 2) and not WeaponHud.clip_low(4, 8), "LowClipPercentage 35 / last round")
	# every gun the remake can hold has an icon, except the flamethrower (empty frame)
	for n in Weapons.STATS:
		if n != "flamethrower" and n != "knife":
			check.call(WeaponHud.gun_texture(n) != null, "icon for %s" % n)
	await _snap(at, "hudw_colt45")
	p.weapon()["mag"] = 2
	await at.get_tree().create_timer(0.3).timeout
	await _snap(at, "hudw_colt45_low")
	# second gun, then the icon is touched: weapon switch
	for g in ["kar98", "trenchgun", "mp40", "ppsh", "wunderwaffe", "type100", "flamethrower"]:
		p.weapons.resize(1)
		p.current = 0
		p.give_weapon(g)
		if g == "ppsh":
			p.weapon()["upgraded"] = true
			var s := Weapons.stats_of(p.weapon())
			p.weapon()["mag"] = s["mag"] - 40
		elif g == "flamethrower":
			p.weapon()["mag"] = int(Weapons.stats(g)["mag"] * 0.6)
		else:
			p.weapon()["mag"] = maxi(int(Weapons.stats(g)["mag"]) - 2, 1)
		p.changed.emit()
		await at.get_tree().create_timer(0.25).timeout
		await _snap(at, "hudw_" + g)
	check.call(wh._fuel.size.x > 40 and wh._fuel.size.x < 55 and wh._flame.visible and not wh._count.visible, "flamethrower fuel bar %.0f / 81" % wh._fuel.size.x)
	var before := p.current
	var vs := at.get_viewport().get_visible_rect().size
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = Vector2(vs.x - 60, 40)
	at.get_viewport().push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	at.get_viewport().push_input(up)
	at.get_viewport().push_input(ev.duplicate())   # double tap (a single tap reloads)
	at.get_viewport().push_input(up.duplicate())
	await at.get_tree().process_frame
	check.call(p.current != before, "double tap on the gun icon switches weapon (%s)" % p.weapon()["name"])
	# no ammo
	p.weapon()["mag"] = 0
	p.weapon()["reserve"] = 0
	await at.get_tree().create_timer(0.3).timeout
	check.call(wh._no_ammo.visible and not wh._count.visible, "No Ammo shown")
	await _snap(at, "hudw_noammo")
	p.weapon()["reserve"] = 3
	await at.get_tree().create_timer(0.2).timeout
	check.call(not wh._no_ammo.visible and wh._count.text == "3", "No Ammo hidden with reserve left")
	# reticle size follows the spread: hip minimum, after continuous fire, shotgun cone
	p.weapons.resize(1)
	p.current = 0
	p.give_weapon("colt45")
	p.set("_heat", 0.0)
	await at.get_tree().process_frame
	await at.get_tree().process_frame
	var lo := ret.side
	p.set("_heat", 1.0)
	await at.get_tree().process_frame
	await at.get_tree().process_frame
	var hi := ret.side
	await _snap(at, "hudw_reticle_wide")
	check.call(absf(lo - 68.0) < 0.6 and hi > 115.0 and hi <= 125.0, "colt45 reticle %.1f -> %.1f px (68 -> 125)" % [lo, hi])
	p.give_weapon("shotgun")
	p.set("_heat", 0.0)
	await at.get_tree().process_frame
	await at.get_tree().process_frame
	check.call(ret.side >= 112.0, "shotgun reticle at least its cone (%.1f)" % ret.side)
	p.toggle_aim()
	await at.get_tree().create_timer(0.6).timeout
	check.call(not ret.visible, "reticle hidden while aiming")
	if p.aiming:
		p.toggle_aim()
	# headshot streak icon "xN"
	p.headshot_streak = 3
	await at.get_tree().create_timer(0.7).timeout
	var hs: Dictionary = hud._powerups._slots["headshot"]
	check.call((hs["icon"] as TextureRect).modulate.a > 0.9 and (hs["time"] as Label).text == "x3", "headshot icon x3")
	await _snap(at, "hudw_headshot")
	p.headshot_streak = 0
	await at.get_tree().create_timer(0.7).timeout
	check.call((hs["icon"] as TextureRect).modulate.a < 0.05, "headshot icon gone with the streak")
	# prompts
	var names := {}
	for d in game.level.debris:
		names[d.entity] = d.action_text()
	check.call(names.get("BackSofaTrigger") == "sgombrare le macerie" and names.get("DoorTrigger") == "aprire la porta", "debris texts %s" % names)
	var box: MysteryBox = game.level.boxes[0] if not game.level.boxes.is_empty() else null
	if box:
		var st = box.state
		box.set("_buyer", p)
		box.offered = "mp40"
		box.state = MysteryBox.State.OFFERED
		p.weapons.resize(1)
		p.current = 0
		var one := box.prompt(p)
		p.give_weapon("kar98")
		var two := box.prompt(p)
		box.state = st
		check.call(one.begins_with("Premi E per prendere") and two.begins_with("Premi E per scambiare le armi"), "box prompts '%s' / '%s'" % [one, two])
	# layout of the original frames: points / perks / round top left, power-ups top,
	# message at 42 %, prompt at the top
	for k in ["jugga", "speed", "dbtap"]:
		if Perks.INFO.has(k):
			p.give_perk(k)
	game._timers["doublepoints"] = 20.0
	game._timers["instakill"] = 12.0
	hud.round_changed(3)
	hud.show_message("Round 3", 5.0)
	p.add_points(50)
	await at.get_tree().create_timer(0.15).timeout
	p.headshot_streak = 2
	await at.get_tree().create_timer(2.5).timeout
	var vs2 := at.get_viewport().get_visible_rect().size
	check.call(hud._points.position.y < 20 and hud._points.position.x < 100, "points top left %s" % hud._points.position)
	check.call(absf(hud._msg.position.y + hud._msg.size.y / 2.0 - vs2.y * 0.42) < 3.0, "message centred at 42 %% (%.0f)" % (hud._msg.position.y + hud._msg.size.y / 2.0))
	await _snap(at, "hudw_layout")
	# red reticle: a live zombie under the centre of the screen
	var z := Zombie.new()
	var cam := at.get_viewport().get_camera_3d()
	# on the camera's own forward ray (its pitch includes the kick / look state)
	var fwd := -cam.global_basis.z
	z.setup(cam.global_position + fwd * 3.0 - Vector3.UP * 1.2, game.level.windows[0], p, 1e6, false)
	game.add_child(z)
	z.state = Zombie.State.ATTACK
	z.set_physics_process(false)
	await at.get_tree().create_timer(0.3).timeout
	check.call(ret.on_target, "reticle red on a zombie")
	await _snap(at, "hudw_reticle_red")
	print("[hud-weapon] %s" % ("ALL OK" if res["ok"] else "SOME FAILED"))
	at.get_tree().quit()


static func _snap(at: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	at.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../analysis/preview/%s.png" % name))
