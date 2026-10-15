# Der Riese teleporter effects (derriese.lua Teleport, departure branch): the teleport
# start (kiwi 0x16f354) sends Event_Teleport(arrive = false), and the script does
#   Game.SpawnEntity("TeleporterPeer<X>_fxSpawn", "teleporterLeave")
#   Game.Timeout(750, "StartTeleportEffect") -> SpawnEntity("TeleporterMain_fxSpawn", "teleporterArrive")
# The effects-group entities (EffectEmitter, CRenderableEffectEmitterSpec values below):
#   teleporterLeave  = spec list eaf92f38 (flames 07e62fbd, 4 s) + CDeathActionSpawnSpec
#                      teleporterLeave2 = 3 x c85423be (rising sparks 2b12c691, 1 s)
#   teleporterArrive = eaf92f38 + death spawn teleporterArrive2 = 3 x 591931b2 (light
#                      beams cb716d85 shooting up, 0.8 s)
# (teleporterLeave2/Arrive2 list the emitter once and twice more in two child entities
# with an identity frame: three copies at the same place.)
class_name TeleFx
extends RefCounted

const ARRIVE_DELAY := 0.75   # Game.Timeout(750, "StartTeleportEffect")
const FLAMES := {   # eaf92f38
	"tex": "07e62fbd", "additive": true, "duration": 4000, "interval": [40, 50], "life": [200, 200],
	"size": [800, 800], "scale_rate": [0, 0], "col_rate": [40960, 40960], "angle": [-227, 227],
	"spin": [-2048, 2048], "pos": [Vector3(-400, 400, 0), Vector3(400, 700, 0)],
	"vel": [Vector3.ZERO, Vector3.ZERO], "accel": Vector3.ZERO,
}
const SPARKS := {   # c85423be
	"tex": "2b12c691", "additive": true, "duration": 1000, "interval": [60, 60], "life": [2500, 2700],
	"size": [20, 50], "scale_rate": [409, 819], "col_life": true, "angle": [0, 4096],
	"spin": [-4096, 4096], "pos": [Vector3(-400, 200, -400), Vector3(400, 1000, 400)],
	"vel": [Vector3(-100, 500, 100), Vector3(100, 1000, -100)], "accel": Vector3(0, 1000, 0),
}
const BEAMS := {    # 591931b2
	"tex": "cb716d85", "additive": true, "duration": 800, "interval": [80, 100], "life": [1000, 1100],
	"size": [1600, 1600], "scale_rate": [8192, 8192], "col_rate": [40960, 40960], "angle": [0, 0],
	"spin": [0, 0], "pos": [Vector3(0, 900, 0), Vector3(0, 900, 0)],
	"vel": [Vector3(0, 40000, 0), Vector3(0, 40000, 0)], "accel": Vector3(0, 40000, 0),
}
const PEER_SPAWN := {"TeleporterPeerA": "TeleporterPeerA_fxSpawn",
	"TeleporterPeerB": "TeleporterPeerB_fxSpawn", "TeleporterPeerC": "TeleporterPeerC_fxSpawn"}
const MAIN_SPAWN := "TeleporterMain_fxSpawn"

static var log := []   # [what, spawn point] for the tests


# The departure at the pad and, 750 ms later, the arrival at the mainframe.
static func teleport(level: Level, peer: String) -> void:
	var at: String = PEER_SPAWN.get(peer, "")
	if at != "":
		_effect(level, at, SPARKS, "teleporterLeave")
	var tree := level.get_tree()
	if tree:
		tree.create_timer(ARRIVE_DELAY, false).timeout.connect(func():
			if is_instance_valid(level):
				_effect(level, MAIN_SPAWN, BEAMS, "teleporterArrive"))


# entity "<name>": the flames, then (death action) three copies of `after`
static func _effect(level: Level, at: String, after: Dictionary, name: String) -> void:
	if not level.has_entity(at):
		return
	var xf := level.entity_transform(at)
	log.append([name, at])
	var e := EffectEmitter.spawn(level, xf, FLAMES)
	e.finished.connect(func():
		if is_instance_valid(level):
			log.append([name + "2", at])
			for i in 3:
				EffectEmitter.spawn(level, xf, after))
