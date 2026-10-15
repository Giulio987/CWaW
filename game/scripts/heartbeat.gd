# The player's heartbeat after a hit, as the original player code:
#  - on every hit taken (kiwi file 0x205c28, after "player_pain") the timer is set to
#    HeartbeatDurationMS (console.bin/code default 5000 ms);
#  - every update (kiwi file 0x2070e4) while the timer runs, HeartbeatSound
#    (player_heartbeat) is started again whenever it is not playing, with volume
#    remap(timer, HeartbeatDurationMS..0 -> 0x1000..0x800) = 1.0 down to 0.5 (the sound
#    instance field +0x10, written by kiwi 0x12db10); at 0 the sound is stopped.
class_name Heartbeat
extends Node

const DURATION := 5.0        # HeartbeatDurationMS 5000
const SOUND := "player_heartbeat"
const MIN_VOLUME := 0.5      # 0x800 / 0x1000 at the end of the timer

var left := 0.0
var _player: AudioStreamPlayer


static func hit(owner_: Node) -> void:
	var h := owner_.get_node_or_null("Heartbeat") as Heartbeat
	if h == null:
		h = Heartbeat.new()
		h.name = "Heartbeat"
		owner_.add_child(h)
	h.left = DURATION


func _process(delta: float) -> void:
	if left <= 0.0:
		return
	if _player == null or not _player.playing:
		var s: AudioStream = Sfx.instance._stream(SOUND) if Sfx.instance else null
		if s == null:
			return
		if _player == null:
			_player = AudioStreamPlayer.new()
			add_child(_player)
		_player.stream = s
		_player.play()
	_player.volume_db = linear_to_db(lerpf(MIN_VOLUME, 1.0, clampf(left / DURATION, 0.0, 1.0)))
	left -= delta
	if left <= 0.0:
		left = 0.0
		_player.stop()
