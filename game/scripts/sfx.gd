# Sound playback from the original sounds (assets/sounds/index.json, built by
# tools/sound_index.py). Names are the ones recovered from hashes; everything
# else is addressed by its 8-digit hash.
class_name Sfx
extends Node

static var instance: Sfx

var _index: Dictionary
var _cache := {}
var _amb_timers := {}   # channel hash -> seconds to next sound
var _amb_players := {}  # channel hash -> the channel's sound playing now
var ambience := []      # active channel hashes (set to [] to silence them)
# Game.SetUsingPlayerVox: the character's voice lines (vox) are on only where the level
# script turns them on (shinonuma.lua / derriese.lua Begin+Resume: true; nacht.lua,
# verruckt.lua and ingame.lua: false)
var using_vox := false
const VOX_CHARACTER := 0   # solo: kiwi 0x192184 formats "player%d_<line>" with 0
var _vox_player: AudioStreamPlayer
var _vox_priority := 0     # priority of the line playing or waiting for its delay
var _vox_serial := 0
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


# Game.StopAmbience + Game.AddAmbienceChannel(c) for each channel. Channels that stay
# on keep playing (a dog round only drops "zombies"); the others are cut.
func start_ambience(channels: Array) -> void:
	var on := []
	for c in channels:
		var h := iw_hash(c)
		if not _amb_channel(h).is_empty():
			on.append(h)
	for h in ambience:
		if not h in on:
			_amb_stop(h)
	for h in on:
		if not h in ambience:
			_amb_timers[h] = _amb_gap(h)
	ambience = on


# CAmbienceChannel of the level's group (index "ambience_channels", tools/sound_index.py):
# weighted sounds, then a random gap of min..max ms after each one ends
func _amb_channel(h: String) -> Dictionary:
	var all: Dictionary = _index.get("ambience_channels", {})
	var c = all.get(level_name, {}).get(h, all.get("ingame", {}).get(h))
	if c == null and _index["ambience"].has(h):
		c = {"sounds": _index["ambience"][h].map(func(s): return [s, 1.0]), "min_ms": 5000, "max_ms": 14000, "flag": 1}
	return c if c is Dictionary else {}


func _amb_gap(h: String) -> float:
	var c := _amb_channel(h)
	return randf_range(float(c.get("min_ms", 5000)), float(c.get("max_ms", 14000))) / 1000.0


func _amb_stop(h: String) -> void:
	var p = _amb_players.get(h)
	if p != null and is_instance_valid(p):
		p.queue_free()
	_amb_players.erase(h)


func _amb_play(h: String) -> void:
	var c := _amb_channel(h)
	var sounds: Array = c.get("sounds", [])
	if sounds.is_empty() or listener == null:
		return
	var total := 0.0
	for s in sounds:
		total += float(s[1])
	var r := randf() * total
	var pick: String = sounds[-1][0]
	for s in sounds:
		r -= float(s[1])
		if r <= 0.0:
			pick = s[0]
			break
	var st := _stream(pick)
	if st == null:
		return
	var p: Node
	if int(c.get("flag", 0)) == 1:
		# "zombies" (flag 1): groans somewhere around the player, so they pan
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = st
		p3.volume_db = -6.0
		p3.unit_size = 6.0
		p3.max_distance = 40.0
		add_child(p3)
		p3.global_position = listener.global_position + \
			Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)).normalized() * randf_range(6.0, 14.0)
		p3.play()
		p = p3
	else:
		# wind, world, jungle and level beds: not placed
		var p2 := AudioStreamPlayer.new()
		p2.stream = st
		p2.volume_db = -8.0
		add_child(p2)
		p2.play()
		p = p2
	_amb_players[h] = p


func _update_ambience(delta: float) -> void:
	for h in _amb_players.keys():
		if not h in ambience:
			_amb_stop(h)   # silenced from outside (ambience = [])
	for h in ambience:
		var p = _amb_players.get(h)
		if p != null and is_instance_valid(p):
			if p.playing:
				continue
			_amb_stop(h)
			_amb_timers[h] = _amb_gap(h)   # the gap starts when the sound ends
		_amb_timers[h] = _amb_timers.get(h, 0.0) - delta
		if _amb_timers[h] <= 0.0:
			_amb_play(h)


# Game.PlayMultiplayerSound(line): a line of the player's character (vox table of the
# player entity, index "vox"). As kiwi 0x191f78/0x192184: nothing unless the level uses
# vox; the line's chance (%); skipped while a line of the same or higher priority is
# playing; a random variant "player0_<line><k>", after the line's delay.
func vox(line: String) -> bool:
	if not using_vox:
		return false
	var e = _index.get("vox", {}).get(line)
	if not e is Dictionary:
		return false
	if randi() % 100 > int(e["chance"]):
		return false
	var busy := (_vox_player != null and _vox_player.playing) or _vox_priority > 0
	if busy and _vox_priority >= int(e["priority"]):
		return false
	var variants: Array = e["variants"]
	var h: String = variants.pick_random()[VOX_CHARACTER]
	_vox_priority = int(e["priority"])
	_vox_serial += 1
	var serial := _vox_serial
	var go := func():
		if serial != _vox_serial:
			return   # replaced by a higher priority line
		var s := _stream(h)
		if s == null:
			_vox_priority = 0
			return
		if _vox_player == null:
			_vox_player = AudioStreamPlayer.new()
			add_child(_vox_player)
			_vox_player.finished.connect(func(): _vox_priority = 0)
		_vox_player.stop()
		_vox_player.stream = s
		_vox_player.play()
	if int(e["delay_ms"]) > 0:
		get_tree().create_timer(float(e["delay_ms"]) / 1000.0, false).timeout.connect(go)
	else:
		go.call()
	return true


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
	_update_ambience(delta)
