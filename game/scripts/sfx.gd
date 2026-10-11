# Sound playback from the original sounds (assets/sounds/index.json, built by
# tools/sound_index.py). Names are the ones recovered from hashes; everything
# else is addressed by its 8-digit hash.
class_name Sfx
extends Node

static var instance: Sfx

var _index: Dictionary
var _cache := {}
var _amb_timers := {}   # channel hash -> seconds to next sound
var ambience := []      # active channel hashes
var listener: Node3D


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_index = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sounds/index.json"))


static func iw_hash(s: String) -> String:
	var h := 5381
	for c in s.to_lower().to_ascii_buffer():
		h = (h * 33 + c) & 0xFFFFFFFF
	return "%08x" % h


func _stream(key: String) -> AudioStream:
	var h: String = key
	var n = _index["names"].get(key)
	if n is String:
		h = n
	elif n is Array and not n.is_empty():
		h = n.pick_random()
	var path: String = _index["sounds"].get(h, "")
	if OS.get_cmdline_user_args().has("--sfx-log"):
		print("[sfx] %s -> %s" % [key, path if path != "" else "MISSING"])
	if path == "":
		return null
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


# 2D (player/UI) sound
func play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s := _stream(key)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# positional sound in the world
func play_at(key: String, pos: Vector3, volume_db := 0.0) -> void:
	var s := _stream(key)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.unit_size = 6.0
	p.max_distance = 40.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func weapon_fire(weapon: String) -> void:
	play(_index["guns"].get(weapon, ""), -4.0, randf_range(0.97, 1.03))


# timed sound sequence named after the animation it goes with (e.g. thompson_reload)
func sequence(name: String) -> void:
	var steps: Array = _index["sequences"].get(iw_hash(name), [])
	for st in steps:
		get_tree().create_timer(float(st[0]) / 1000.0, false).timeout.connect(play.bind(String(st[1]), -4.0))


func start_ambience(channels: Array) -> void:
	ambience = []
	for c in channels:
		var h := iw_hash(c)
		if _index["ambience"].has(h):
			ambience.append(h)
			_amb_timers[h] = randf_range(2.0, 6.0)


func _process(delta: float) -> void:
	for h in ambience:
		_amb_timers[h] -= delta
		if _amb_timers[h] <= 0.0:
			_amb_timers[h] = randf_range(5.0, 14.0)
			var list: Array = _index["ambience"][h]
			if list.is_empty() or listener == null:
				continue
			# somewhere around the player, so it pans like distant noise
			var off := Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)).normalized() * randf_range(6.0, 14.0)
			play_at(list.pick_random(), listener.global_position + off, -6.0)
