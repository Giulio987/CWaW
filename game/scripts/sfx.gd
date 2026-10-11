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
var level_name := ""    # picks the level's variant of sounds that differ per level (index "levels")
var _music: AudioStreamPlayer
var _game: Node         # Game (parent): its round changes start the round music
var _last_round := 0
var _was_dead := false


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
	var path: String = _index.get("levels", {}).get(level_name, {}).get(h, _index["sounds"].get(h, ""))
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


# Music and jingles on one channel: a new one replaces the one playing.
# Keys: round_start, game_start, round_end, game_over, box_music, jingle_<perk> ...
func music(key: String, volume_db := 0.0) -> AudioStreamPlayer:
	var s := _stream(key)
	if s == null:
		return null
	if _music == null:
		_music = AudioStreamPlayer.new()
		add_child(_music)
	_music.stop()
	_music.stream = s
	_music.volume_db = volume_db
	_music.play()
	return _music


func stop_music() -> void:
	if _music:
		_music.stop()


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


# Round music without hooks in game.gd: follow Game.round_number. waves.lua StartWave
# plays start_game on round 1 (not on Der Riese: NoStartLaugh) and begin_wave after;
# dog rounds have their own sounds (game.gd).
func _follow_game() -> void:
	if _game == null:
		_game = get_parent()
		if not ("round_number" in _game):
			_game = self
			return
		level_name = String(_game.get("level_name"))
	if _game == self:
		return
	var r: int = _game.get("round_number")
	if r > _last_round:
		_last_round = r
		if not _game.get("dog_round"):
			if r == 1:
				if level_name != "derriese":
					music("game_start")
			else:
				music("round_start")
	var p = _game.get("player")
	var dead: bool = p != null and is_instance_valid(p) and p.get("dead") == true
	if dead and not _was_dead:
		stop_music()
		# Nacht's game-over intro is a short sting followed by gameover_start
		if level_name == "nacht":
			get_tree().create_timer(1.3).timeout.connect(play.bind("gameover_start"))
	_was_dead = dead


func _process(delta: float) -> void:
	_follow_game()
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
