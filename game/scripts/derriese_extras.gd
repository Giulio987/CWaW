# Der Riese level-script details (derriese.lua) around the power and the teleporters:
#  - start: Begin's Timeout(500, "doorClose") -> mainframe_door "start" (it rises out of
#    the floor), Timeout(2000, "paStartSound") -> pa_level_start, Timeout(4000,
#    "PowerOnStartSound") -> PlayMultiplayerSound("power_out") (lines 418-425; Begin read
#    from the bytecode, the decompile lost it).
#  - DroppingDoorLab / DroppingDoorHanger (CTriggerInteractableASMSpec, model 898a6e9c):
#    TurnOnGenerator "genTurnOn" (614-615). Their ASM (898a6e9c): closed (1bd6417d)
#    -genTurnOn-> "opening" (1a19cfed, 958 ms, sound 312518cb "dooropen") -> "open"
#    (1bd42feb). The one-bone anims sink the door 3340 x 0.25 = 835 units into the floor.
#    Closed, they shut the shortcuts between the outer courtyards and the power courtyard
#    (the "NA" links Link_oGC_pC / Link_oLC_pC the generator unlocks, 596-599, 625-629).
#  - genElectric6..11 (electric arcs, additive sprites) are shown only with the power
#    (Begin hides them, TurnOnGenerator 630-635, Resume 318-332).
#  - teleporter map boards TeleporterMapA/B/C (rig cd366b65, ASM 0b888f83):
#    UpdateTeleporterMaps (864-888, from the bytecode): with the power on, every peer
#    state change sets "tele<linked peers 1..3>linked"; 500 ms later "LinkCheck"
#    (496-505) sends "teleLinking" if a peer is linking: that state blinks between two
#    poses every 500 ms. "genTurnOn" (604-606) shows the powered board.
#  - mystery box map boards mysteryMap_* (rig f3e163c0, ASM f3e163c0): UpdateMysteryMaps
#    (978-986) with the box's MysteryBoxMapTriggers entry when the box moves (WarpMysteryBox)
#    or the level resumes (RefreshMysteryMaps 989-1013).
#  - SeeTeleporterTrigger (398-400): before the power, standing in it and looking at the
#    Pack-a-Punch (within 30 degrees) plays the "see_teleporter" line once.
#  - after a teleport to the mainframe, Timeout(3000, "MainframeSteamOn") turns on the
#    mainframeSteam1..5 vents for 8 s (481-493, 553-561).
class_name DerrieseExtras
extends Node3D

const DROPPING_DOORS := ["DroppingDoorLab", "DroppingDoorHanger"]
const DROP_MODEL := "898a6e9c"
const DROP_DEPTH := 835.0 * Level.UNITS
const DROP_TIME := 0.958
const DROP_SOUND := "312518cb"
const DROP_MIN_DEPTH := 0.4      # blocker thickness at least this
const DROP_SIDE_GROW := 0.25     # the CIwColliderSpec of DroppingDoorLab reaches ~97 units past each side

const GEN_ELECTRIC := ["genElectric6", "genElectric7", "genElectric8", "genElectric9", "genElectric10", "genElectric11"]

const TELE_MAPS := ["TeleporterMapA", "TeleporterMapB", "TeleporterMapC"]
const TELE_MAP_MODEL := "cd366b65"
# ASM 0b888f83: state -> [still pose, blink pose of its "teleLinking" loop (500 ms each)]
const TELE_MAP_OFF := "4f07b6d9"
const TELE_MAP_ANIMS := {
	"tele": ["f2e1341b", "ee5b4685"], "tele1": ["bce89623", "59fb59e1"], "tele2": ["eddbf384", "a95a6362"],
	"tele3": ["1ecf50e5", "f8b96ce3"], "tele12": ["0b84ba25", "7c1bfe23"], "tele13": ["3c781786", "cb7b07a4"],
	"tele23": ["8bd72107", "06bb4145"], "tele123": ["2f46aacf", ""],
}
const BLINK_TIME := 0.5
const LINK_CHECK_TIME := 0.5     # Timeout(500, "LinkCheck")

const MYSTERY_MAP_MODEL := "f3e163c0"
const MYSTERY_MAPS := ["mysteryMap_power", "mysteryMap_powerTele", "mysteryMap_lab", "mysteryMap_labTele",
	"mysteryMap_garage", "mysteryMap_garageTele"]
# Script.Level.MysteryBoxes -> MysteryBoxMapTriggers -> pose of ASM f3e163c0
const BOX_MAP_ANIMS := {
	"MysteryBox_powerCourtyard": "98e0d59d",   # movedToPower
	"MysteryBox_powerTele": "d61f7aba",        # movedToPowerTeleporter
	"MysteryBox_garage": "34c6002a",           # movedToGarage
	"MysteryBox_lab": "630ff032",              # movedToLab
	"MysteryBox_labTele": "4d52111c",          # movedToLabTeleporter
	"MysteryBox_garageTele": "2af56d3c",       # movedToGarageTeleporter
}

const SEE_TRIGGER := "SeeTeleporterTrigger"
const SEE_ANGLE := 30.0
const STEAM := ["mainframeSteam1", "mainframeSteam2", "mainframeSteam3", "mainframeSteam4", "mainframeSteam5"]
const STEAM_DELAY := 3.0
const STEAM_TIME := 8.0
const STEAM_TEX := "81d92923"    # the bridge steam's sprite (bridge.gd)

var game: Game
var level: Level
var drop_doors := []         # [{entity, model, body, open}]
var tele_maps := []          # AnimationPlayer per board
var mystery_maps := []       # AnimationPlayer per board
var tele_map_state := ""     # "", "off", "tele", "tele1", ... (tests)
var tele_map_blinking := false
var mystery_map_pose := ""   # current pose (tests)
var see_teleporter_done := false
var resumed := false         # set by load_state (save_game.gd)
var steam := []
var start_log := []          # [seconds since begin, event] (tests)
var _blink_t := 0.0
var _blink_on := false
var _gen_electric := []
var _see_box := AABB()
var _see_timer := 0.0
var _begin_t := 0.0
var _clock := 0.0             # game time (the Lua timeouts run on it)


static func create(game_: Game) -> DerrieseExtras:
	if game_.level.level_name != "derriese":
		return null
	var x := DerrieseExtras.new()
	x.name = "DerrieseExtras"
	x.game = game_
	x.add_to_group(SaveGame.PROVIDER_GROUP)   # resumed game (save_game.gd)
	x.level = game_.level
	game_.level.nav_region.add_child(x)   # the dropping doors' colliders shape the navmesh
	x._build()
	return x


func _build() -> void:
	for n in DROPPING_DOORS:
		if level.has_entity(n):
			_build_drop_door(level.entity(n)["name"])
	for n in GEN_ELECTRIC:
		var node := level.static_root.find_child("ent_" + n, true, false) as Node3D
		if node:
			node.visible = level.power_on
			_gen_electric.append(node)
	for n in TELE_MAPS:
		var ap := _board(n, TELE_MAP_MODEL)
		if ap:
			tele_maps.append(ap)
	for n in MYSTERY_MAPS:
		var ap := _board(n, MYSTERY_MAP_MODEL)
		if ap:
			mystery_maps.append(ap)
	for b in level.boxes:
		b.moved.connect(_update_mystery_maps)
	if not level.boxes.is_empty():
		_update_mystery_maps(level.boxes[0].entity)
	if level.has_entity(SEE_TRIGGER):
		var e := level.entity(SEE_TRIGGER)
		if not (e["colliders"] as Array).is_empty():
			var c: Dictionary = e["colliders"][0]
			var lo := Vector3(c["min"][0], c["min"][1], c["min"][2]) * Level.UNITS
			var hi := Vector3(c["max"][0], c["max"][1], c["max"][2]) * Level.UNITS
			_see_box = level.entity_transform(SEE_TRIGGER) * AABB(lo, hi - lo)
	for n in STEAM:
		if level.has_entity(n):
			var xf := level.entity_transform(n)
			# the vents' +Z points up and out of the mainframe roof
			var p := WeaponFx.particles(STEAM_TEX, {"amount": 20, "lifetime": 2.0, "size": 0.5, "grow": 3.0,
				"speed": 1.8, "dir": xf.basis.z.normalized(), "spread": 14.0, "gravity": Vector3(0, 0.3, 0),
				"one_shot": false, "additive": false, "color": Color(0.85, 0.85, 0.85, 0.45), "damping": 0.6,
				"sphere": 0.15})
			p.emitting = false
			level.nav_region.add_child(p)
			p.global_position = xf.origin
			steam.append(p)
	if level.teleporters:
		level.teleporters.peer_state_changed.connect(_update_tele_maps)
		level.teleporters.arrived.connect(_on_teleport_arrived)
	_update_tele_maps()
	level.power_changed.connect(_on_power)
	if level.power_on:
		for d in drop_doors:
			_drop(d, true)
	level.navigation_ready.connect(_begin, CONNECT_ONE_SHOT)


# ------------------------------------------------------------------ start

# derriese.lua Begin: Timeout(500, "doorClose") -> "start" on the mainframe door,
# Timeout(2000, "paStartSound") -> pa_level_start, Timeout(4000, "PowerOnStartSound").
func _begin() -> void:
	_begin_t = _clock
	await get_tree().create_timer(0.5, false).timeout
	_log("doorClose")
	if level.teleporters:
		level.teleporters.close_at_start()
	if resumed:
		return   # derriese.lua Resume: no start announcements
	await get_tree().create_timer(2.0, false).timeout
	_log("pa_level_start")
	Sfx.instance.play("pa_level_start")
	await get_tree().create_timer(4.0, false).timeout
	_log("power_out")
	_vox("power_out%d" % randi_range(1, 2))   # PlayMultiplayerSound("power_out", true): power_out1/2


func _log(what: String) -> void:
	start_log.append([_clock - _begin_t, what])
	if OS.get_cmdline_user_args().has("--extras-log"):
		print("[extras] %.2f s %s" % [start_log[-1][0], what])


func _vox(line: String) -> void:
	# Game.PlayMultiplayerSound(line): Sfx.vox plays a variant of the line ("power_out1"
	# -> "power_out": "player0_power_out1/2" in solo) with its chance, priority and delay
	Sfx.instance.vox(line.rstrip("0123456789"))


# ------------------------------------------------------------------ power

func _on_power(on: bool) -> void:
	if not on:
		return
	for d in drop_doors:
		_drop(d)
	for node in _gen_electric:
		node.visible = true
	_update_tele_maps()   # "genTurnOn": the powered board


# ------------------------------------------------------------------ dropping doors

func _build_drop_door(entity: String) -> void:
	var e := level.entity(entity)
	var holder := Node3D.new()
	holder.name = "DropDoor_" + entity
	add_child(holder)
	holder.global_transform = Level.flag_transform(e["transform"])
	var model := level.dynamics_model(DROP_MODEL)
	if model == null:
		holder.queue_free()
		return
	holder.add_child(model)
	if not e["children"].is_empty():
		model.transform = Level.flag_transform(e["children"][-1])
	# blocker: the closed model's box (the Hanger's CIwColliderSpec is a 4.5 m use volume)
	var aabb := AABB()
	for mi in model.find_children("*", "MeshInstance3D", true, false) + ([model] if model is MeshInstance3D else []):
		var b: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb() if mi != model else (mi as MeshInstance3D).get_aabb()
		aabb = b if aabb.size == Vector3.ZERO else aabb.merge(b)
	var body := StaticBody3D.new()
	body.name = "Blocker"
	holder.add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var size := aabb.size + Vector3(DROP_SIDE_GROW * 2.0, 0.6, 0.0)
	size.z = maxf(size.z, DROP_MIN_DEPTH)
	box.size = size
	cs.shape = box
	cs.transform = model.transform * Transform3D(Basis(), aabb.get_center() + Vector3(0, 0.3, 0))
	body.add_child(cs)
	drop_doors.append({"entity": entity, "model": model, "body": body, "open": false, "holder": holder})


# ASM "genTurnOn" -> "opening": the door sinks DROP_DEPTH in DROP_TIME, then "open".
func _drop(d: Dictionary, instant := false) -> void:
	if d["open"]:
		return
	d["open"] = true
	var model: Node3D = d["model"]
	var target := model.position + Vector3.DOWN * DROP_DEPTH
	if is_instance_valid(d["body"]):
		d["body"].queue_free()
	if instant:
		model.position = target
		model.visible = false
		return
	Sfx.instance.play_at(DROP_SOUND, (d["holder"] as Node3D).global_transform * (model.position + Vector3(1.6, 1.0, 0)))
	var tw := create_tween()
	tw.tween_property(model, "position", target, DROP_TIME)
	tw.tween_callback(func(): model.visible = false)   # below the floor
	await get_tree().physics_frame
	await get_tree().physics_frame
	level.bake_navigation()


func door_blocking(entity: String) -> bool:
	for d in drop_doors:
		if d["entity"] == entity:
			return not d["open"]
	return false


# ------------------------------------------------------------------ map boards

func _board(entity: String, model_hash: String) -> AnimationPlayer:
	if not level.has_entity(entity):
		return null
	var model := level.dynamics_model(model_hash)
	if model == null:
		return null
	model.name = "Board_" + entity
	add_child(model)
	model.global_transform = Level.flag_transform(level.entity(entity)["transform"])
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aps := model.find_children("*", "AnimationPlayer")
	return aps[0] if not aps.is_empty() else null


static func _pose(ap: AnimationPlayer, a: String) -> void:
	if ap and a != "" and ap.has_animation(a):
		ap.play(a)
		ap.seek(0.0, true)
		ap.pause()


# UpdateTeleporterMaps: "tele" + the linked peers' numbers + "linked", then LinkCheck.
func _update_tele_maps() -> void:
	tele_map_blinking = false
	if not level.power_on or level.teleporters == null:
		tele_map_state = "off"
		for ap in tele_maps:
			_pose(ap, TELE_MAP_OFF)
		return
	var key := "tele"
	var pads: Array = level.teleporters.pads
	for i in pads.size():
		if pads[i].state == "linked":
			key += str(i + 1)
	tele_map_state = key
	for ap in tele_maps:
		_pose(ap, TELE_MAP_ANIMS[key][0])
	await get_tree().create_timer(LINK_CHECK_TIME, false).timeout
	_link_check(key)


# LinkCheck: a peer is linking -> "teleLinking" (no such transition once all three are linked)
func _link_check(key: String) -> void:
	if key != tele_map_state or TELE_MAP_ANIMS[key][1] == "":
		return
	if level.teleporters.pads.any(func(p): return p.state == "linking"):
		tele_map_blinking = true
		_blink_t = BLINK_TIME
		_blink_on = false


func _update_mystery_maps(box_entity: String) -> void:
	for n in BOX_MAP_ANIMS:
		if n.to_lower() == box_entity.to_lower():
			mystery_map_pose = BOX_MAP_ANIMS[n]
	for ap in mystery_maps:
		_pose(ap, mystery_map_pose)


# ------------------------------------------------------------------ teleport, look trigger

func _on_teleport_arrived() -> void:
	await get_tree().create_timer(STEAM_DELAY, false).timeout   # "MainframeSteamOn"
	for p in steam:
		p.emitting = true
	await get_tree().create_timer(STEAM_TIME, false).timeout    # "MainframeSteamOff"
	for p in steam:
		p.emitting = false


func steam_on() -> bool:
	return steam.any(func(p): return p.emitting)


# Trigger "SeeTeleporterTrigger": GeneratorOn false and IsPlayerLookingAt("packAPunch", "30")
func _check_see_teleporter() -> void:
	var p := game.player
	if p == null or p.dead or _see_box.size == Vector3.ZERO:
		return
	if not _see_box.grow(0.05).has_point(p.global_position + Vector3.UP * 0.1):
		return
	var cam: Camera3D = p._camera   # the player's view, not a debug camera
	if cam == null or not level.has_entity("packapunch"):
		return
	var to := level.entity_transform("packapunch").origin + Vector3.UP * 1.0 - cam.global_position
	if rad_to_deg((-cam.global_basis.z).angle_to(to)) < SEE_ANGLE:
		see_teleporter_done = true
		_vox("see_teleporter")


func _process(delta: float) -> void:
	_clock += delta
	if tele_map_blinking:
		_blink_t -= delta
		if _blink_t <= 0.0:
			_blink_t = BLINK_TIME
			_blink_on = not _blink_on
			for ap in tele_maps:
				_pose(ap, TELE_MAP_ANIMS[tele_map_state][1 if _blink_on else 0])
	if not see_teleporter_done and not level.power_on:
		_see_timer -= delta
		if _see_timer <= 0.0:
			_see_timer = 0.1
			_check_see_teleporter()


# ------------------------------------------------------------------ save provider (save_game.gd)
# Doors, boards and arcs follow the power, the teleporters and the box (restored by
# save_game.gd, which re-emits their signals); only the one-time look line is kept here.

func save_key() -> String:
	return "derriese_extras"


func save_state() -> Dictionary:
	return {"see_teleporter_done": see_teleporter_done}


func load_state(d: Dictionary) -> void:
	resumed = true
	see_teleporter_done = bool(d.get("see_teleporter_done", see_teleporter_done))
