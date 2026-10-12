# Easter eggs from the levels' Lua Trigger handlers (shootable CTriggerDamageSpec
# volumes driving CSoundEmitterSpec entities):
#  - Nacht (nacht.lua Trigger "RadioVolume"): each hit cycles RadioTrack1 -> 2 -> 3 -> off.
#  - Der Riese (derriese.lua Trigger "Radio<n>Trigger" -> RadioUpdate(name, ms)): the trigger
#    is disabled, Radio<n>Sound plays and a Timeout "Radio<n>Off" stops it after ms.
#  - Shi No Numa (shinonuma.lua Trigger, read from the bytecode: the decompile lost it):
#    the telephone (TelephoneNoiseTrigger) rings, then plays the song; afterwards each hit
#    toggles the song. StartRadio1..3: first two hit play static, the third the message.
#    StorageRadio / DoctorsRadio: one message each. MeteorTrigger: character line once.
#  - Verrückt (verruckt.lua "DentistChairVolume"): DentistWhizz once, stopped after 5.5 s.
# The sound each emitter plays is in its entity body (CSoundEmitterSpec: u32 sound spec,
# u8 mode, u8 one-shot, u32 range in units), not in entities.json, so it is listed here.
# Chained CIwSoundSpecs (spec field "next") play one after the other.
class_name RadioEggs
extends Node3D

const TRIGGER_LAYER := 16   # layer 5: damage triggers, only bullets look for them

# emitter -> [sound spec chain, mode, range units]. mode: "loop" (one-shot byte 0),
# "once" (one-shot byte 1), "ambient" (mode byte 1: plays now and then while enabled).
const EMITTERS := {
	"nacht": {
		# radio_start1..3: radio switch-on static (6534b79e) then the track
		"RadioTrack1": [["1e616a72", "8455ee3e"], "loop", 2000],
		"RadioTrack2": [["1e616a73", "0f5d28f7", "0f5d28f8"], "loop", 2000],
		"RadioTrack3": [["1e616a74", "14aa37e5", "14aa37e6"], "loop", 2000],
	},
	"derriese": {
		"Radio1Sound": [["870e1c5b"], "once", 800], "Radio2Sound": [["870e1c5c"], "once", 400],
		"Radio3Sound": [["870e1c5d"], "once", 400], "Radio4Sound": [["870e1c5e"], "once", 400],
		"Radio5Sound": [["870e1c5f"], "once", 400], "Radio6Sound": [["870e1c60"], "once", 400],
		"Radio7Sound": [["870e1c61"], "once", 400], "Radio8Sound": [["870e1c62"], "once", 400],
	},
	"shinonuma": {
		"TelephoneOffHookEmitter": [["57c899b3"], "ambient", 400],
		"TelephoneNoiseEmitter": [["b1183637", "6ff4492e"], "once", 400],
		"TelephoneMusicEmitter": [["be7ad6dc", "be7ad6dd"], "once", 2000],
		"TelephoneNoiseEmitter1": [["bbcb0eea"], "ambient", 1200],   # at the meteor
		"StartRadio1Static1": [["addc017e"], "loop", 400], "StartRadio1Static2": [["addc017f"], "loop", 400],
		"StartRadio1Message": [["870e1c5b"], "once", 400],
		"StartRadio2Static1": [["addc017e"], "loop", 400], "StartRadio2Static2": [["addc017f"], "loop", 400],
		"StartRadio2Message": [["870e1c5b"], "once", 400],
		"StartRadio3Static1": [["addc017e"], "loop", 400], "StartRadio3Static2": [["addc017f"], "loop", 400],
		"StartRadio3Message": [["870e1c5b"], "once", 400],
		"StorageRadioMessage": [["870e1c5d"], "once", 400],
		"DoctorsRadioMessage": [["870e1c5c"], "once", 400],
	},
	"verruckt": {
		"DentistWhizz": [["4a0242c2"], "once", 400],
	},
}
# emitters enabled when the level starts (the Lua only ever disables these)
const START_ON := ["TelephoneOffHookEmitter", "TelephoneNoiseEmitter1"]
# Shi No Numa radio triggers are CIwVolumeCylinder (radius, height in units) from the
# entity bodies; the other triggers are AABoxes (entities.json "colliders").
const CYLINDERS := {
	"StartRadio1Trigger": [400, 800], "StartRadio2Trigger": [399, 800], "StartRadio3Trigger": [400, 800],
	"StorageRadioTrigger": [238, 800], "DoctorsRadioTrigger": [240, 800],
}
# derriese.lua Trigger: RadioUpdate("Radio<n>", ms)
const DERRIESE_RADIO_MS := [41000, 29000, 45000, 104000, 105000, 27000, 59000, 105000]

var game: Game
var level: Level
var triggers := {}      # name -> DamageTrigger
var emitters := {}      # name -> Emitter
var radio_channel := 1  # nacht.lua Script.Level.RadioChannel
var telephone_state := "OffStart"
var meteor_shot := false
var start_radio_used := []
var storage_radio_used := false
var doctors_radio_used := false
var log_hits := []      # trigger names in hit order (tests)


static func create(game_: Game) -> RadioEggs:
	var e := RadioEggs.new()
	e.name = "RadioEggs"
	e.game = game_
	e.level = game_.level
	game_.add_child(e)
	e._build()
	return e


func _build() -> void:
	var lvl := level.level_name
	for n in EMITTERS.get(lvl, {}):
		var ent := _ent(n)
		if ent.is_empty():
			continue
		var cfg: Array = EMITTERS[lvl][n]
		var em := Emitter.new()
		em.name = "Emitter_" + n
		em.chain = cfg[0]
		em.mode = cfg[1]
		em.range_m = float(cfg[2]) / 400.0
		add_child(em)
		em.global_position = Level._to_transform(ent["transform"]).origin
		emitters[n] = em
		if n in START_ON:
			em.enable()
	var names := []
	match lvl:
		"nacht":
			names = ["RadioVolume"]
		"derriese":
			for i in range(1, 9):
				names.append("Radio%dTrigger" % i)
		"shinonuma":
			names = ["TelephoneNoiseTrigger", "StartRadio1Trigger", "StartRadio2Trigger", "StartRadio3Trigger",
				"StorageRadioTrigger", "DoctorsRadioTrigger", "MeteorTrigger"]
		"verruckt":
			names = ["DentistChairVolume"]
	for n in names:
		var t := _make_trigger(n)
		if t:
			triggers[n] = t
	# nacht.lua GameOver: the radio goes quiet
	if game.player:
		game.player.died.connect(func():
			for n in ["RadioTrack1", "RadioTrack2", "RadioTrack3"]:
				_disable(n))
	# the Nacht tracks sit at the radio (their emitters are 9 m away, behind the wall)
	if triggers.has("RadioVolume"):
		for n in ["RadioTrack1", "RadioTrack2", "RadioTrack3"]:
			if emitters.has(n):
				emitters[n].global_position = triggers["RadioVolume"].centre()


# A bullet from `from` to `to` (where it stopped): damage the first trigger volume on the
# way. Triggers are on their own layer so they never stop bullets meant for zombies.
static func bullet(by: Player, from: Vector3, to: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, to, TRIGGER_LAYER)
	var hit := by.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"].has_method("trigger_damage"):
		hit["collider"].trigger_damage(by)


func _ent(n: String) -> Dictionary:
	var e := level.entity(n)
	if e.is_empty():
		e = level.entity(Sfx.iw_hash(n))   # names not recovered: entities.json keeps the hash
	return e


func _make_trigger(n: String) -> DamageTrigger:
	var ent := _ent(n)
	if ent.is_empty():
		return null
	var t := DamageTrigger.new()
	t.name = "Trigger_" + n
	t.trigger_name = n
	t.eggs = self
	var shape := CollisionShape3D.new()
	var at := Level._to_transform(ent["transform"]).origin
	if CYLINDERS.has(n):
		var c := CylinderShape3D.new()
		c.radius = float(CYLINDERS[n][0]) / 400.0
		c.height = float(CYLINDERS[n][1]) / 400.0
		shape.shape = c
		shape.position = Vector3(0, c.height * 0.5, 0)
	elif not (ent["colliders"] as Array).is_empty():
		var col: Dictionary = ent["colliders"][0]
		var lo := Vector3(col["min"][0], col["min"][1], col["min"][2]) / 400.0
		var hi := Vector3(col["max"][0], col["max"][1], col["max"][2]) / 400.0
		var b := BoxShape3D.new()
		b.size = (hi - lo).abs()
		shape.shape = b
		shape.position = (lo + hi) * 0.5
	else:
		return null
	t.add_child(shape)
	add_child(t)
	t.global_position = at
	return t


func _enable(n: String) -> void:
	if emitters.has(n):
		emitters[n].enable()


func _disable(n: String) -> void:
	if emitters.has(n):
		emitters[n].disable()


func _disable_trigger(n: String) -> void:
	if triggers.has(n):
		triggers[n].enabled = false


func _timeout(ms: int, f: Callable) -> void:
	get_tree().create_timer(ms / 1000.0, false).timeout.connect(f)


func _vox(line: String) -> void:
	# Game.PlayMultiplayerSound(line): the character's "player%d_<line>" (player 1 in solo)
	Sfx.instance.play(Sfx.iw_hash("player1_" + line))


# Script.Level.Trigger(name, player) of the level's Lua
func trigger(n: String, _by: Player) -> void:
	log_hits.append(n)
	if OS.get_cmdline_user_args().has("--egg-log"):
		print("[egg] trigger %s" % n)
	match n:
		"RadioVolume":
			Achievements.unlock("radioSilence")   # nacht.lua: Game.SetAchievement("radioSilence")
			var ch := radio_channel
			for k in [1, 2, 3]:
				if k != ch:
					_disable("RadioTrack%d" % k)
			if ch <= 3:
				_enable("RadioTrack%d" % ch)
			radio_channel = ch + 1 if ch < 4 else 1
		"DentistChairVolume":
			Achievements.unlock("ver_openwide")   # verruckt.lua: Game.SetAchievement("ver_openwide")
			_disable_trigger(n)
			_enable("DentistWhizz")
			_timeout(5500, _disable.bind("DentistWhizz"))
		"TelephoneNoiseTrigger":
			_telephone()
		"StartRadio1Trigger", "StartRadio2Trigger", "StartRadio3Trigger":
			_start_radio(n.trim_suffix("Trigger"))
		"StorageRadioTrigger":
			if not storage_radio_used:
				storage_radio_used = true
				_disable_trigger(n)
				_enable("StorageRadioMessage")
		"DoctorsRadioTrigger":
			if not doctors_radio_used:
				doctors_radio_used = true
				_disable_trigger(n)
				_enable("DoctorsRadioMessage")
		"MeteorTrigger":
			if not meteor_shot:
				_vox("meteor1")
				meteor_shot = true
		_:
			if n.begins_with("Radio") and n.ends_with("Trigger"):
				var i := int(n.trim_prefix("Radio").trim_suffix("Trigger"))
				var radio := "Radio%d" % i
				_disable_trigger(n)
				_enable(radio + "Sound")
				_timeout(DERRIESE_RADIO_MS[i - 1], _disable.bind(radio + "Sound"))


func _telephone() -> void:
	match telephone_state:
		"OffStart":
			Achievements.unlock("ea47fa40")   # "Dead Air": activate the phone (no Lua call: engine)
			_disable_trigger("TelephoneNoiseTrigger")
			_disable("TelephoneOffHookEmitter")
			_enable("TelephoneNoiseEmitter")
			_timeout(8000, func():   # Timeout "telephoneMusic"
				_disable("TelephoneNoiseEmitter")
				_enable("TelephoneMusicEmitter")
				_timeout(12000, func():   # Timeout "TurnOnRadio"
					if triggers.has("TelephoneNoiseTrigger"):
						triggers["TelephoneNoiseTrigger"].enabled = true
					telephone_state = "On"))
			_vox("easter_egg")
		"On":
			_disable("TelephoneMusicEmitter")
			telephone_state = "Off"
		"Off":
			_enable("TelephoneMusicEmitter")
			telephone_state = "On"


# shinonuma.lua StartRadioUpdate
func _start_radio(r: String) -> void:
	if r in start_radio_used or start_radio_used.size() >= 3:
		return
	start_radio_used.append(r)
	_disable_trigger(r + "Trigger")
	match start_radio_used.size():
		1:
			_enable(r + "Static1")
		2:
			_enable(r + "Static2")
		3:
			_disable(String(start_radio_used[0]) + "Static1")
			_disable(String(start_radio_used[1]) + "Static2")
			_enable(r + "Message")


# A shootable trigger volume (CHealthSpec + CTriggerDamageSpec): player.gd calls
# trigger_damage() when a bullet hits it.
class DamageTrigger extends StaticBody3D:
	var trigger_name := ""
	var eggs: RadioEggs
	var enabled := true

	func _ready() -> void:
		collision_layer = RadioEggs.TRIGGER_LAYER
		collision_mask = 0

	func trigger_damage(by: Player) -> void:
		if enabled:
			eggs.trigger(trigger_name, by)

	func centre() -> Vector3:
		for c in get_children():
			if c is CollisionShape3D:
				return (c as CollisionShape3D).global_position
		return global_position


# CSoundEmitterSpec: Enable/DisableSoundEmitter; plays its chain of sound specs.
class Emitter extends Node3D:
	var chain: Array = []
	var mode := "once"
	var range_m := 1.0
	var enabled := false
	var _player: AudioStreamPlayer3D
	var _step := 0
	var _wait := 0.0

	func _ready() -> void:
		_player = AudioStreamPlayer3D.new()
		_player.unit_size = maxf(range_m * 2.0, 2.0)
		_player.max_distance = 20.0 + range_m * 4.0
		add_child(_player)
		_player.finished.connect(_next)

	func enable() -> void:
		enabled = true
		_step = 0
		_wait = 0.0
		_play_step()

	func disable() -> void:
		enabled = false
		if _player:
			_player.stop()

	func playing() -> bool:
		return enabled and _player != null and _player.playing

	func _play_step() -> void:
		if _player == null or not enabled:
			return
		var s := Sfx.instance._stream(String(chain[_step]))
		if s == null:
			return
		_player.stream = s
		_player.play()

	func _next() -> void:
		if not enabled:
			return
		_step += 1
		if _step < chain.size():
			_play_step()
			return
		_step = 0
		match mode:
			"loop":
				_play_step()
			"ambient":
				_wait = randf_range(3.0, 9.0)
			_:
				enabled = false   # one-shot: done (DisableSoundEmitterOnSoundEnd)

	func _process(delta: float) -> void:
		if _wait > 0.0:
			_wait -= delta
			if _wait <= 0.0 and enabled:
				_play_step()
