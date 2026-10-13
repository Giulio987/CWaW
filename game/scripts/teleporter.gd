# Der Riese teleporters (derriese.lua): three peer pads (TeleporterPeerA/B/C,
# CTeleporterPeerSpec + CActionBuySpec 1500) and the mainframe
# (TeleporterMainFrame). TurnOnGenerator enables the peers; a peer is activated
# on its pad and then linked at the mainframe ("LinkCheck"). Each link opens the
# mainframe door a bit more (UpdatePackAPunch firstOpen/secondOpen/thirdOpen); the
# third opens it fully and unlocks the Pack-a-Punch area. A linked pad teleports
# the player to the mainframe for 1500 points ("Teleport": leave/arrive effects),
# then needs to cool down. 8 s after arriving, TeleporterSpawnPickUp drops a
# power-up at TeleportPerkSpawn or, sometimes, sends two dogs.
class_name TeleporterNetwork
extends Node3D

const PEERS := ["TeleporterPeerA", "TeleporterPeerB", "TeleporterPeerC"]
const COST := 1500
const COOLDOWN := 30.0
const DOOR_MODEL := "750ed528"
const USE_RANGE := 2.6
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
signal arrived              # derriese.lua Teleport(..., true): the player reached the mainframe


class Pad:
	extends Node3D
	var net: TeleporterNetwork
	var entity := ""
	var is_mainframe := false
	var centre := Vector3.ZERO
	var state := "off"            # peers: off, idle, linking, linked

	func usable_from(p: Vector3) -> bool:
		return Vector2(p.x - centre.x, p.z - centre.z).length() < TeleporterNetwork.USE_RANGE and absf(p.y - centre.y) < 2.0

	func prompt(player: Player) -> String:
		return net.prompt_for(self, player)

	func interact(player: Player) -> void:
		net.interact_with(self, player)


var level: Level
var pads := []        # peers
var mainframe: Pad
var cooldown := 0.0
var teleports := 0    # teleports made (stats)
var teleports_occured := 0   # Script.TeleportsOccured: pick-up rolls made (derriese.lua 729-730)
var _door: Node3D
var _door_body: StaticBody3D
var _door_closed_y := 0.0
var _door_tween: Tween
var _flash: ColorRect


func setup(level_: Level) -> void:
	level = level_
	mainframe = _make_pad(level.entity("TeleporterMainFrame")["name"], true)
	for n in PEERS:
		if level.has_entity(n):
			pads.append(_make_pad(level.entity(n)["name"], false))
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


func prompt_for(pad: Pad, player: Player) -> String:
	if not level.power_on:
		return "Serve la corrente" if not pad.is_mainframe else ""
	if pad.is_mainframe:
		if pads.any(func(p): return p.state == "linking"):
			return "Premi E per collegare il teletrasporto"
		return ""
	match pad.state:
		"idle":
			return "" if pads.any(func(p): return p.state == "linking") else "Premi E per attivare il teletrasporto"
		"linking":
			return "Collega il teletrasporto al mainframe"
		"linked":
			if cooldown > 0.0:
				return "Il teletrasporto si sta ricaricando"
			return "Premi E per teletrasportarti [%d]" % COST
	return ""


func interact_with(pad: Pad, player: Player) -> void:
	if not level.power_on:
		return
	if pad.is_mainframe:
		for p in pads:
			if p.state == "linking":
				p.state = "linked"
				Sfx.instance.play_at(Sfx.iw_hash("tele_gone_peer"), mainframe.centre + Vector3.UP)
				_update_door()
				peer_state_changed.emit()
				if level.pack_a_punch:
					level.pack_a_punch._refresh()
		return
	match pad.state:
		"idle":
			if not pads.any(func(p): return p.state == "linking"):
				pad.state = "linking"
				Sfx.instance.play_at(Sfx.iw_hash("tele_tinitus"), pad.centre + Vector3.UP)
				peer_state_changed.emit()
		"linked":
			if cooldown > 0.0:
				return
			if player.points < COST:
				Sfx.instance.play("buy_fail")
				return
			player.add_points(-COST)
			teleport(pad, player)


# Peer -> mainframe. The screen flashes white, the player is moved at the peak.
func teleport(pad: Pad, player: Player) -> void:
	cooldown = COOLDOWN
	Sfx.instance.play(Sfx.iw_hash("tele_teleport_start"))
	_white_flash(1.6)
	await get_tree().create_timer(0.75, false).timeout
	if player.dead:
		return
	player.global_position = mainframe.centre + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	Sfx.instance.play(Sfx.iw_hash("tele_gone_wormhole"))
	teleports += 1
	get_tree().create_timer(8.0, false).timeout.connect(_spawn_pickup)
	arrived.emit()
	var game := level.get_parent() as Game
	if game:
		game.player_moved()


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


func _white_flash(duration: float) -> void:
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
	tw.tween_property(_flash, "color:a", 1.0, duration * 0.45)
	tw.tween_property(_flash, "color:a", 0.0, duration * 0.55)


func _process(delta: float) -> void:
	if cooldown > 0.0:
		cooldown -= delta
