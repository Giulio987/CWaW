# Der Riese teleporters (derriese.lua + the engine's CTeleporterPeer / CTeleporterMain):
# three peer pads (TeleporterPeerA/B/C, CTeleporterPeerSpec + CActionBuySpec 1500) and
# the mainframe (TeleporterMainFrame, CTeleporterMainSpec). TurnOnGenerator enables the
# peers. Each link opens the mainframe door a bit more (UpdatePackAPunch firstOpen /
# secondOpen / thirdOpen); the third opens it fully and unlocks the Pack-a-Punch area.
#
# Engine logic, decoded from kiwi (peer update va 0x16fc80, use 0x16ffac, prompt
# 0x22c8d4, countdown 0x16f584, link end 0x16f470, teleport start 0x16f354, fire
# 0x16f724 / 0x16f948, rematerialize 0x16fb00, serialise 0x170210; main: link 0x16eb00,
# use 0x16f09c, all-active PA 0x16efb8):
#  - E on an unlinked pad (no other pad linking) starts the link: 30 s to reach the
#    mainframe (TeleporterLinkingTimeMs 30000), PA "pa_beep_link_count_start", player vox
#    "countdown", a "countdown_tick" every CountDownTickInterval (250 ms), the PA
#    counting down "pa_link_count_<n>" when the time left drops under each value of
#    TeleportPeerCounterTimeMS (console.bin: 20000, 15000, 10000, 9000 ... 1000) and
#    the HUD clock "hud_teleporter_clock" + "hud_clock_hand" (half a turn in 30 s).
#    Time out: "pa_beep_link_count_fail", the pad goes back to unlinked.
#  - E at the mainframe while a pad is linking links it (stat session_teleporterslinked);
#    the pad then plays its CTeleporterPeerSpec PA (pa_beep_pad_active_1/2/3 for A/B/C)
#    and fires once like a teleport (below). 3.2 s after the third link
#    (TeleporterPAAllActiveTimeMs) "pa_beep_pad_active_all" and the vox
#    "linked_teleporters".
#  - E on a linked pad (1500): teleport start. TeleporterStartTimeMs (console.bin 1980)
#    later the pad fires: whoever stands in the pad's collider box goes to the
#    mainframe (the first CTeleporterMainSpec destination, entity d3a8fb56; stat
#    session_teleportertimesused, "tele_gone_wormhole"), otherwise "tele_gone_peer".
#    Every firing sends Event_Teleport(arrive): derriese.lua Teleport -> steam after
#    3 s, TeleporterSpawnPickUp after 8 s. TeleporterRematerializeTimeMs (console.bin
#    2390) after the firing: vox "teleported" and "tele_tinitus" for the teleported
#    player, PA "pa_beep_teleport_successful". The pad cools down
#    TeleporterCoolingDownTimeMs (20000) from the firing.
#  - From the start to the end of the rematerialization the pad's and the mainframe's
#    CSplashEffectSpec are on (derriese.lua Begin turns them off; kiwi 0x14a094): 5000
#    damage to zombies and dogs (target mask 0x4000) in the entity's collider box every
#    100 ms, stat "teleKill" (derriese.totalzombieteleKill: achievement "The Poetry of
#    Steak", 10 kills).
#  - Prompts (0x22c8d4): no power LS_GENERATOR_NEED_POWER; any pad linking
#    LS_TELEPORTER_LINKING; starting or cooling down LS_TELEPORTER_TELEPORTING; another
#    pad starting LS_TELEPORTER_TEMPUNAVAIL; else LS_TELEPORTER_LINK / LS_TELEPORTER_BUY.
class_name TeleporterNetwork
extends Node3D

const PEERS := ["TeleporterPeerA", "TeleporterPeerB", "TeleporterPeerC"]
const COST := 1500
const LINK_TIME := 30.0          # TeleporterLinkingTimeMs (kiwi default, not in console.bin)
const TICK_INTERVAL := 0.25      # CountDownTickInterval (kiwi default 250)
const COUNTER_MS := [20000, 15000, 10000, 9000, 8000, 7000, 6000, 5000, 4000, 3000, 2000, 1000]   # console.bin TeleportPeerCounterTimeMS
const START_TIME := 1.98         # console.bin TeleporterStartTimeMs 1980 (kiwi default 3000)
const REMATERIALIZE_TIME := 2.39 # console.bin TeleporterRematerializeTimeMs 2390 (default 3000)
const COOLDOWN := 20.0           # TeleporterCoolingDownTimeMs (kiwi default 20000)
const ALL_ACTIVE_TIME := 3.2     # TeleporterPAAllActiveTimeMs (kiwi default 3200)
const PAD_PA := ["pa_beep_pad_active_1", "pa_beep_pad_active_2", "pa_beep_pad_active_3"]   # CTeleporterPeerSpec +0x48
const DESTINATION := "d3a8fb56"  # CTeleporterMainSpec destinations (player 1 of 4)
const SPLASH_DAMAGE := 5000.0    # CSplashEffectSpec of the four entities
const SPLASH_PERIOD := 0.1       # its repeat time (100 ms)
const DOOR_MODEL := "750ed528"
const USE_RANGE := 2.6
# HUD clock (Der Riese HUD texture 54f786f3): the dial (0 at the top, 15 at the sides,
# 30 at the bottom) and the red hand; screen place estimated (top left)
const CLOCK_ATLAS := "res://assets/textures/fixed/54f786f3.png"
const CLOCK_DIAL := Rect2(4, 128, 56, 60)
const CLOCK_HAND := Rect2(78, 131, 4, 24)
const CLOCK_CENTRE := Vector2(28, 32)   # dial centre in the dial region
const CLOCK_SCALE := 2.0
# mainframe_door CIsAnimStateMachine (750ed528): one-bone root offsets of its poses (anim
# root y 0 / -1428 / -3064 / -4700 x 0.25 units): the door sinks into the floor.
#   S0 "open" (a772b3f7, down) -"start"-> S1 "Closing" (0ce02df9 at rate 2048: 2000 ms,
#   sound 99d29ce6) -> S2 closed (94ee06db) -"firstOpen"-> S3 (c476cb64, 485 ms, sound
#   d4a114a6) -> S4 (9522b80d) -"secondOpen"-> S5 (9c1cd258, 555 ms) -> S6 (577c1cc1)
#   -"thirdOpen"-> S7 (96a709f0, 555 ms) -> S8 renderChild(0): the door is hidden.
const DOOR_DROP := [0.0, 357.0 * Level.UNITS, 766.0 * Level.UNITS, 1175.0 * Level.UNITS]
const DOOR_OPEN_TIME := [0.0, 0.485, 0.555, 0.555]
const DOOR_CLOSE_TIME := 2.0
const DOOR_CLOSE_SOUND := "99d29ce6"
const DOOR_OPEN_SOUND := "d4a114a6"

signal peer_state_changed   # derriese.lua TeleporterPeerStateChanged (teleporter maps)
signal arrived              # Event_Teleport(arrive): derriese.lua Teleport(..., true), every firing


class Pad:
	extends Node3D
	var net: TeleporterNetwork
	var entity := ""
	var index := 0
	var is_mainframe := false
	var centre := Vector3.ZERO
	var box := AABB()             # collider box (world): who teleports, splash volume
	var state := "off"            # peers: off, idle, linking, linked
	var link_timer := 0.0         # peer +0x28
	var start_timer := 0.0        # +0x2c
	var remat_timer := 0.0        # +0x30
	var cooldown := 0.0           # +0x34
	var activator: Player         # +0x38
	var teleporting := false      # +0x3c: the player is on his way
	var count_index := 0          # +0x44
	var tick_timer := 0.0         # +0x48
	var incoming := false         # main's peer state 3 (between start and firing)
	var splash := false           # CSplashEffect on
	var splash_timer := 0.0

	func usable_from(p: Vector3) -> bool:
		return Vector2(p.x - centre.x, p.z - centre.z).length() < TeleporterNetwork.USE_RANGE and absf(p.y - centre.y) < 2.0

	func prompt(player: Player) -> String:
		return net.prompt_for(self, player)

	func interact(player: Player) -> void:
		net.interact_with(self, player)


var level: Level
var pads := []        # peers
var mainframe: Pad
var teleports := 0    # teleports made (stats)
var teleports_occured := 0   # Script.TeleportsOccured: pick-up rolls made (derriese.lua 729-730)
var tele_kills := 0   # zombies killed by the pads (tests)
var log := []         # [time, what] of the sounds/events (tests)
var _clock := 0.0
var _all_active_timer := 0.0
var _door: Node3D
var _door_body: StaticBody3D
var _door_closed_y := 0.0
var _door_tween: Tween
var _flash: ColorRect
var _hud: Control
var _hand: Control

# the longest cooldown of the pads (save_game.gd "tele_cooldown"; per pad in save_state)
var cooldown: float:
	get:
		var c := 0.0
		for p in pads:
			c = maxf(c, p.cooldown)
		return c
	set(v):
		for p in pads:
			if p.state == "linked":
				p.cooldown = v


func setup(level_: Level) -> void:
	level = level_
	add_to_group(SaveGame.PROVIDER_GROUP)
	mainframe = _make_pad(level.entity("TeleporterMainFrame")["name"], true)
	for n in PEERS:
		if level.has_entity(n):
			var p := _make_pad(level.entity(n)["name"], false)
			p.index = PEERS.find(n)
			pads.append(p)
	_build_door()
	level.power_changed.connect(func(on: bool):
		if on:
			for p in pads:
				if p.state == "off":
					p.state = "idle")
	if level.power_on:
		for p in pads:
			p.state = "idle"


func _make_pad(entity: String, main: bool) -> Pad:
	var p := Pad.new()
	p.net = self
	p.entity = entity
	p.is_mainframe = main
	var e := level.entity(entity)
	var root := level.entity_transform(entity)
	var cols: Array = e.get("colliders", [])
	p.centre = root * Trap._box_centre(cols[0]) if not cols.is_empty() else root.origin
	if not cols.is_empty():
		var c: Dictionary = cols[0]
		var lo := Vector3(c["min"][0], c["min"][1], c["min"][2]) * Level.UNITS
		var hi := Vector3(c["max"][0], c["max"][1], c["max"][2]) * Level.UNITS
		p.box = AABB(root * lo, Vector3.ZERO)
		for i in 8:
			p.box = p.box.expand(root * Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	else:
		p.box = AABB(p.centre - Vector3(1, 0.3, 1), Vector3(2, 1.5, 2))
	p.name = entity
	add_child(p)
	p.global_position = p.centre
	level.interactables.append(p)
	return p


func _build_door() -> void:
	if not level.has_entity("mainframe_door"):
		return
	var e := level.entity("mainframe_door")
	_door = level.dynamics_model(DOOR_MODEL)
	if _door == null:
		return
	var holder := Node3D.new()
	add_child(holder)
	holder.global_transform = level.entity_transform("mainframe_door")
	holder.add_child(_door)
	if not e["children"].is_empty():
		var c: Array = e["children"][-1]["pos"]
		_door.position = Vector3(c[0], c[1], c[2]) * Level.UNITS
	_door_closed_y = _door.position.y
	# ASM S0 "open": the level starts with the door down; derriese.lua Begin closes it
	# (Timeout 500 "doorClose" -> SetASMTrigger("mainframe_door", "start"), close_at_start)
	_door.position.y = _door_closed_y - DOOR_DROP[3]
	# seen from the mainframe side too: draw both faces
	for mi in _door.find_children("*", "MeshInstance3D", true, false) + ([_door] if _door is MeshInstance3D else []):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).mesh.surface_get_material(i)
			if m is BaseMaterial3D:
				m = m.duplicate()
				(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
				(mi as MeshInstance3D).set_surface_override_material(i, m)
	if OS.get_cmdline_user_args().has("--tele-debug"):
		for mi in _door.find_children("*", "MeshInstance3D", true, false) + ([_door] if _door is MeshInstance3D else []):
			print("[tele] door mesh %s aabb %s" % [mi.name, (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()])
	_door_body = StaticBody3D.new()
	holder.add_child(_door_body)
	for c in e.get("colliders", []):
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Trap._box_size(c).max(Vector3(0.2, 0.2, 0.2))
		cs.shape = box
		cs.position = Trap._box_centre(c)
		_door_body.add_child(cs)


func linked_count() -> int:
	return pads.filter(func(p): return p.state == "linked").size()


func linking_pad() -> Pad:
	for p in pads:
		if p.state == "linking":
			return p
	return null


# ------------------------------------------------------------------ prompts / use

func prompt_for(pad: Pad, _player: Player) -> String:
	if not level.power_on:
		return Lang.t("Serve la corrente") if not pad.is_mainframe else ""
	if pad.is_mainframe:
		if linking_pad() != null:
			return Lang.prompt("collegare il teletrasporto", "#5094f8ba")   # "Link peer teleporter"
		return ""
	if linking_pad() != null:
		return Lang.t("Collegamento in corso")              # LS_TELEPORTER_LINKING
	if pad.start_timer > 0.0 or pad.cooldown > 0.0:
		return Lang.t("Il teletrasporto si sta ricaricando")   # LS_TELEPORTER_TELEPORTING
	if pads.any(func(p): return p.incoming):
		return Lang.t("Temporaneamente non disponibile")   # LS_TELEPORTER_TEMPUNAVAIL
	if pad.state != "linked":
		return Lang.prompt("collegare il teletrasporto al mainframe", "LS_TELEPORTER_LINK")
	return Lang.prompt("teletrasportarti", "LS_TELEPORTER_BUY", COST)


func _usable(pad: Pad) -> bool:
	return level.power_on and pad.state != "off" and linking_pad() == null and pad.start_timer <= 0.0 \
		and pad.cooldown <= 0.0 and not pads.any(func(p): return p.incoming)


func interact_with(pad: Pad, player: Player) -> void:
	if not level.power_on:
		return
	if pad.is_mainframe:
		# CTeleporterMain use (0x16f09c): links the pad that is linking
		var lp := linking_pad()
		if lp != null:
			_set_linked(lp)
		return
	if not _usable(pad):
		return
	if pad.state == "linked":
		if player.points < COST:
			Sfx.instance.play("buy_fail")
			return
		player.add_points(-COST)
		pad.activator = player
		pad.start_timer = START_TIME
		_start_teleport(pad)
	else:
		_start_link(pad, player)


# peer use, not linked (0x170004): the 30 s link starts
func _start_link(pad: Pad, player: Player) -> void:
	pad.state = "linking"
	pad.activator = player
	pad.link_timer = LINK_TIME
	pad.count_index = 0
	pad.tick_timer = 0.0
	_pa("pa_beep_link_count_start")
	Sfx.instance.vox("countdown")
	_log("link_start " + pad.entity)
	_show_clock(true)
	peer_state_changed.emit()


# CTeleporterMain link (0x16eb00): stat, state event, the HUD clock off; after the third
# link the all-active announcement
func _set_linked(pad: Pad) -> void:
	pad.state = "linked"
	_log("linked " + pad.entity)
	_show_clock(false)
	_update_door()
	peer_state_changed.emit()
	if level.pack_a_punch:
		level.pack_a_punch._refresh()
	if linked_count() >= pads.size():
		_all_active_timer = ALL_ACTIVE_TIME


# peer link end (0x16f470): linked -> its PA and a firing; time out -> fail PA
func _link_end(pad: Pad) -> void:
	pad.link_timer = 0.0
	if pad.state == "linked":
		_pa(PAD_PA[clampi(pad.index, 0, 2)])
		pad.start_timer = START_TIME
		_start_teleport(pad)
	else:
		_pa("pa_beep_link_count_fail")
		pad.activator = null


# teleport start (0x16f354): the mainframe "incoming", splash on, "tele_teleport_start";
# Event_Teleport(leave) -> derriese.lua leave/arrive effects
func _start_teleport(pad: Pad) -> void:
	pad.incoming = true
	_pa("teleport_incoming", mainframe.centre + Vector3.UP)
	if pad.activator != null:
		pad.splash = true
		pad.splash_timer = 0.0
		mainframe.splash = true
		mainframe.splash_timer = 0.0
	Sfx.instance.play_at(Sfx.iw_hash("tele_teleport_start"), pad.centre + Vector3.UP)
	TeleFx.teleport(level, pad.entity)   # Event_Teleport(leave): teleporterLeave/Arrive effects
	_log("start " + pad.entity)


# firing (0x16f724 + 0x16f948): the player in the pad's box goes to the mainframe
func _fire(pad: Pad) -> void:
	pad.incoming = false
	var game := level.get_parent() as Game
	var p: Player = game.player if game else pad.activator
	pad.teleporting = p != null and not p.dead and pad.box.grow(0.05).has_point(p.global_position + Vector3.UP * 0.5)
	pad.cooldown = COOLDOWN
	pad.remat_timer = REMATERIALIZE_TIME
	if pad.teleporting:
		pad.activator = p
		var to := mainframe.centre + Vector3.UP * 0.1
		if level.has_entity(DESTINATION):
			to = level.entity_transform(DESTINATION).origin + Vector3.UP * 0.1
		p.global_position = to
		p.velocity = Vector3.ZERO
		teleports += 1
		_white_flash()
		Sfx.instance.play_at(Sfx.iw_hash("tele_gone_wormhole"), pad.centre + Vector3.UP)
		if game:
			game.player_moved()
	else:
		Sfx.instance.play_at(Sfx.iw_hash("tele_gone_peer"), pad.centre + Vector3.UP)
	_log("fire %s %s" % [pad.entity, "teleported" if pad.teleporting else "empty"])
	# Event_Teleport(arrive): derriese.lua Teleport -> Timeout(8000, "TeleportSpawnPickUp"),
	# Timeout(3000, "MainframeSteamOn") (derriese_extras.gd)
	get_tree().create_timer(8.0, false).timeout.connect(_spawn_pickup)
	arrived.emit()


# rematerialized (0x16fb00): vox/tinnitus for the teleported player, splash off, PA
func _rematerialized(pad: Pad) -> void:
	if pad.teleporting and pad.activator != null:
		Sfx.instance.vox("teleported")
		Sfx.instance.play_at(Sfx.iw_hash("tele_tinitus"), pad.activator.global_position + Vector3.UP)
	pad.splash = false
	mainframe.splash = false
	pad.teleporting = false
	pad.activator = null
	_pa("pa_beep_teleport_successful")
	_log("remat " + pad.entity)


# countdown while linking (0x16f584): PA numbers and the clock tick
func _countdown(pad: Pad, delta: float) -> void:
	if pad.count_index < COUNTER_MS.size() and pad.link_timer * 1000.0 < COUNTER_MS[pad.count_index]:
		var n: int = COUNTER_MS[pad.count_index] / 1000
		Sfx.instance.play(Sfx.iw_hash("pa_link_count_%d" % n), -4.0)
		_log("count %d" % n)
		pad.count_index += 1
	pad.tick_timer -= delta
	if pad.tick_timer <= 0.0:
		pad.tick_timer = TICK_INTERVAL
		Sfx.instance.play("countdown_tick", -4.0)


func _process(delta: float) -> void:
	_clock += delta
	for pad in pads:
		if pad.link_timer > 0.0:
			if pad.state == "linked":
				_link_end(pad)
			else:
				pad.link_timer -= delta
				if pad.link_timer <= 0.0:
					pad.state = "idle"
					_show_clock(false)
					peer_state_changed.emit()
					_link_end(pad)
				else:
					_set_clock(LINK_TIME - pad.link_timer)
					_countdown(pad, delta)
		if pad.cooldown > 0.0:
			pad.cooldown = maxf(pad.cooldown - delta, 0.0)
		if pad.start_timer > 0.0:
			pad.start_timer -= delta
			if pad.start_timer <= 0.0:
				pad.start_timer = 0.0
				_fire(pad)
		if pad.remat_timer > 0.0:
			pad.remat_timer -= delta
			if pad.remat_timer <= 0.0:
				pad.remat_timer = 0.0
				_rematerialized(pad)
	if _all_active_timer > 0.0:
		_all_active_timer -= delta
		if _all_active_timer <= 0.0:
			_all_active_timer = 0.0
			_pa("pa_beep_pad_active_all")
			Sfx.instance.vox("linked_teleporters")
	for pad in pads + [mainframe]:
		if pad.splash:
			pad.splash_timer -= delta
			if pad.splash_timer <= 0.0:
				pad.splash_timer = SPLASH_PERIOD
				_splash(pad)


# CSplashEffect (kiwi 0x14aba0 / 0x14a0a4): 5000 to every zombie and dog in the box,
# no points (like the zipline's and the traps')
func _splash(pad: Pad) -> void:
	var game := level.get_parent() as Game
	var box := pad.box.grow(0.05)
	for z in get_tree().get_nodes_in_group("zombies"):
		if not (z is Zombie) or z.state == Zombie.State.DEAD or not box.has_point(z.global_position + Vector3.UP * 0.5):
			continue
		if game:
			game.suppress_kill_points = true
		HitFx.hit_sound(z, true)   # CHitTemplate splash sound (hit_fx.gd)
		z.take_damage(SPLASH_DAMAGE, false, null)
		if game:
			game.suppress_kill_points = false
		if z.state == Zombie.State.DEAD and not (z is Dog):
			tele_kills += 1
			Achievements.event("derriese.totalzombieteleKill")   # "activezombie" + stat teleKill


# TeleporterSpawnPickUp (derriese.lua 640-731): RandomNumber(1, top), upper bound
# exclusive (Game.lua_random), top 17, 25 from round 30, 14 while TeleportsOccured < 4;
# 14 and up is a "bad teleport" with two dogs, else a power-up. TeleportsOccured
# grows after the roll: no dogs in the first four, then 3/16, 11/24 from round 30.
func _spawn_pickup() -> void:
	var game := level.get_parent() as Game
	if game == null:
		return
	var top := 25 if game.round_number >= 30 else 17
	if teleports_occured < 4:
		top = 14
	var r := Game.lua_random(1, top)
	teleports_occured += 1
	if r >= 14:
		Sfx.instance.play(Sfx.iw_hash("tele_uhoh"))
		for i in 2:
			game.spawn_dog(true)
		return
	var kind := "maxammo"
	if r == 1:
		kind = "maxammo"
	elif r <= 4:
		kind = "doublepoints"
	elif r <= 7:
		kind = "instakill"
	elif r <= 10:
		kind = "nuke"
	else:
		kind = "carpenter"
	var at := mainframe.centre
	if level.has_entity("TeleportPerkSpawn"):
		at = level.entity_transform("TeleportPerkSpawn").origin
	Sfx.instance.play_at("dog_spawn", at)
	game.spawn_powerup(kind, at)


# PA announcement (kiwi 0x1c82d4): a CSoundSequence (beep, then the line 700 ms later),
# at a place for "teleport_incoming"
func _pa(seq: String, at = null) -> void:
	_log(seq)
	if at == null:
		Sfx.instance.sequence(seq)
		return
	var pos: Vector3 = at
	for st in Sfx.instance._index["sequences"].get(Sfx.iw_hash(seq), []):
		get_tree().create_timer(float(st[0]) / 1000.0, false).timeout.connect(
			func(): Sfx.instance.play_at(String(st[1]), pos))


func _log(what: String) -> void:
	log.append([_clock, what])
	if OS.get_cmdline_user_args().has("--tele-debug"):
		print("[tele] %.2f %s" % [_clock, what])


func _update_door() -> void:
	var n := linked_count()
	if _door and n >= 1:
		# UpdatePackAPunch: firstOpen / secondOpen / thirdOpen sink the door a step
		if _door_tween:
			_door_tween.kill()
		var i := mini(n, 3)
		_door_tween = create_tween()
		_door_tween.tween_property(_door, "position:y", _door_closed_y - DOOR_DROP[i], DOOR_OPEN_TIME[i])
		if i >= 3:
			_door_tween.tween_callback(func(): _door.visible = false)   # S8 renderChild(0)
		Sfx.instance.play_at(DOOR_OPEN_SOUND, _door.global_position + Vector3.UP)
	if n >= 3:
		if _door_body:
			_door_body.queue_free()
			_door_body = null
		var game := level.get_parent() as Game
		if game:
			game.open_area("packAPunch")


# derriese.lua Timeout "doorClose": SetASMTrigger("mainframe_door", "start") - the door
# rises out of the floor (ASM S1 "Closing", 2000 ms, sound 99d29ce6).
func close_at_start() -> void:
	if _door == null or linked_count() > 0:
		return
	if _door_tween:
		_door_tween.kill()
	_door_tween = create_tween()
	_door_tween.tween_property(_door, "position:y", _door_closed_y, DOOR_CLOSE_TIME)
	Sfx.instance.play_at(DOOR_CLOSE_SOUND, _door.global_position + Vector3.UP)


# the teleported player's screen: white at the firing, back during the rematerialization
func _white_flash() -> void:
	if _flash == null:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		_flash = ColorRect.new()
		_flash.color = Color(1, 1, 1, 0)
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_flash)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 1.0, 0.1)
	tw.tween_property(_flash, "color:a", 0.0, REMATERIALIZE_TIME)


# ------------------------------------------------------------------ HUD clock
# CHud: frame "hud_teleporter_clock" shown while the HUD value (+0xc4) is not -1, its
# "hud_clock_hand" turned by -(elapsed / TeleporterLinkingTimeMs) x 2048 (half a turn)

func clock_visible() -> bool:
	return _hud != null and _hud.visible


func _show_clock(on: bool) -> void:
	if _hud == null:
		if not on:
			return
		var layer := CanvasLayer.new()
		layer.layer = 4
		add_child(layer)
		_hud = Control.new()
		_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.position = Vector2(24, 24)
		_hud.scale = Vector2.ONE * CLOCK_SCALE
		layer.add_child(_hud)
		var dial := TextureRect.new()
		var a := AtlasTexture.new()
		a.atlas = load(CLOCK_ATLAS)
		a.region = CLOCK_DIAL
		dial.texture = a
		dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(dial)
		_hand = Control.new()
		_hand.position = CLOCK_CENTRE
		_hud.add_child(_hand)
		var hand := TextureRect.new()
		var h := AtlasTexture.new()
		h.atlas = a.atlas
		h.region = CLOCK_HAND
		hand.texture = h
		hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand.position = Vector2(-CLOCK_HAND.size.x / 2.0, -CLOCK_HAND.size.y + 2.0)   # pivot at its dark end
		_hand.add_child(hand)
	_hud.visible = on
	if on:
		_set_clock(0.0)


func _set_clock(elapsed: float) -> void:
	if _hand:
		_hand.rotation = clampf(elapsed / LINK_TIME, 0.0, 1.0) * PI


# ------------------------------------------------------------------ save
# CTeleporterPeer serialise (0x170210): link/start/rematerialize/cooldown timers. A link
# in progress starts again with the time it had left (start PA and vox, as the
# original's load), a teleport being started fires again without charging.

func save_key() -> String:
	return "teleporters"


func save_state() -> Dictionary:
	var out := {}
	for p in pads:
		out[p.entity] = {"link": p.link_timer if p.state == "linking" else 0.0, "cooldown": p.cooldown,
			"start": p.start_timer}
	return {"pads": out, "all_active": _all_active_timer}


func load_state(d: Dictionary) -> void:
	var st: Dictionary = d.get("pads", {})
	for p in pads:
		var s: Dictionary = st.get(p.entity, {})
		if s.is_empty():
			continue
		p.cooldown = float(s.get("cooldown", 0.0))
		var link := float(s.get("link", 0.0))
		if link > 0.0 and p.state != "linked" and level.power_on and linking_pad() == null:
			var game := level.get_parent() as Game
			_start_link(p, game.player if game else null)
			p.link_timer = link
		if float(s.get("start", 0.0)) > 0.0 and p.state == "linked":
			var game := level.get_parent() as Game
			p.activator = game.player if game else null
			p.start_timer = START_TIME
			_start_teleport(p)
	_all_active_timer = float(d.get("all_active", 0.0))
