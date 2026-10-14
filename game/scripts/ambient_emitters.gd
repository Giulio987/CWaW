# Positional ambient sounds: the level's CSoundEmitterSpec entities that are on from the
# start (enabled byte 1; the others are switched by the level scripts: radios, perk hums,
# traps, fly trap...). Nacht: wind upstairs (wind_1 x3), f14c76c6 x2, sparks 105f1846;
# Verrückt: 983b03d2 x4, 360c877f x2, f8ec2453, f00abdd9; Shi No Numa: 91501f52 x30,
# b3e7c00b x11; Der Riese: f00abdd9. The Shi No Numa telephone emitters (also on from the
# start) belong to the easter egg (radio_egg.gd).
#
# As the original CSoundEmitter (update kiwi va 0x148c74, every SoundEmitterAttenuationTimer
# 250 ms; here every frame):
#   volume = spec vol max x distance factor x height factor
#   distance factor: 1 up to the spec's min distance, linear to 0 at its max distance
#     (kiwi va 0x227870; tools/sound_index.py "specs")
#   height factor: 1 - |listener y - emitter y| / emitter range (0 beyond; the range is
#     a height, so most emitters are heard only on their own floor)
# A stopped emitter starts its sound when the volume is above 0; when the sound ends it
# starts again (a loop) unless the emitter is one-shot; a spec with a "next" spec plays
# that one afterwards and the emitter keeps looping the last. Emitter fields from
# tools/entities.py "sound_emitters".
class_name AmbientEmitters
extends Node3D

const UNITS := 1.0 / 400.0

var level: Level
var emitters: Array[Emitter] = []


static func create(game: Game) -> AmbientEmitters:
	var a := AmbientEmitters.new()
	a.name = "AmbientEmitters"
	a.level = game.level
	game.add_child(a)
	a._build()
	return a


func _build() -> void:
	var skip := {}
	for n in RadioEggs.EMITTERS.get(level.level_name, {}):
		skip[String(n).to_lower()] = true
		skip[Sfx.iw_hash(n)] = true
	for n in level.entities:
		var e: Dictionary = level.entities[n]
		for se in e.get("sound_emitters", []):
			if int(se["start_on"]) != 1 or se.has("child"):
				continue
			if skip.has(String(n).to_lower()) or skip.has(String(e.get("hash", ""))):
				continue
			var em := Emitter.make(se)
			em.name = "Emitter_" + String(n)
			add_child(em)
			em.global_position = Level._to_transform(e["transform"]).origin
			em.enable()
			emitters.append(em)


# CIwSoundSpec parameters for the current level: [vol min, vol max, pitch min, pitch max
# (4096 = 1), dist min, dist max (units), next spec]
static func spec_params(h: String) -> Array:
	var specs: Dictionary = Sfx.instance._index.get("specs", {})
	var p = specs.get(Sfx.instance.level_name, {}).get(h, specs.get("ingame", {}).get(h))
	return p if p is Array else [4096, 4096, 4096, 4096, 0, 4000, ""]


# One CSoundEmitter. Also used for emitters the game switches on and off (trap.gd).
class Emitter extends Node3D:
	var spec := ""
	var range_m := 1.0         # height range
	var attenuate := true
	var one_shot := false
	var enabled := false
	var volume := 0.0          # linear, last computed
	var _cur := ""             # spec playing now (follows "next")
	var _params: Array = []
	var _player: AudioStreamPlayer3D

	static func make(se: Dictionary) -> Emitter:
		var em := Emitter.new()
		em.spec = String(se["spec"])
		em.range_m = float(se.get("range", 0)) * UNITS
		em.attenuate = int(se.get("attenuate", 1)) != 0
		em.one_shot = int(se.get("one_shot", 0)) != 0
		return em

	func _ready() -> void:
		_player = AudioStreamPlayer3D.new()
		_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED   # volume set below
		_player.max_distance = 0.0
		_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(_player)
		_player.finished.connect(_ended)

	func enable() -> void:
		enabled = true
		_set_spec(spec)

	func disable() -> void:
		enabled = false
		if _player:
			_player.stop()

	func playing() -> bool:
		return enabled and _player != null and _player.playing

	func _set_spec(h: String) -> void:
		_cur = h
		_params = AmbientEmitters.spec_params(h)
		if _player:
			_player.stream = Sfx.instance._stream(h)
			var p0 := float(_params[2]) / 4096.0
			var p1 := float(_params[3]) / 4096.0
			_player.pitch_scale = clampf(randf_range(p0, p1), 0.25, 4.0) if p1 > 0.0 else 1.0

	func _ended() -> void:
		if not enabled:
			return
		var nxt := String(_params[6]) if _params.size() > 6 else ""
		if nxt != "" and Sfx.instance._stream(nxt) != null:
			_set_spec(nxt)   # the chain goes on; the emitter keeps the last spec
		elif one_shot:
			enabled = false   # DisableSoundEmitterOnSoundEnd
			return
		if volume > 0.0:
			_player.play()

	func compute_volume(listener: Vector3) -> float:
		var v := float(_params[1]) / 4096.0 if _params.size() > 1 else 1.0
		if not attenuate:
			return v
		var dmin := float(_params[4]) * UNITS
		var dmax := float(_params[5]) * UNITS
		var d := listener.distance_to(global_position)
		if d > dmin:
			v *= 0.0 if d >= dmax or dmax <= dmin else 1.0 - (d - dmin) / (dmax - dmin)
		if range_m > 0.0:
			v *= maxf(0.0, 1.0 - absf(listener.y - global_position.y) / range_m)
		return v

	func _process(_delta: float) -> void:
		if not enabled or _player == null or _player.stream == null:
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		volume = compute_volume(cam.global_position)
		if volume <= 0.0:
			if _player.playing:
				_player.stream_paused = true   # silent: the original keeps it at volume 0
			return
		_player.volume_db = linear_to_db(volume)
		if _player.stream_paused:
			_player.stream_paused = false
		elif not _player.playing:
			_player.play()
