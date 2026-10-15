# Points for repairing barricades, capped per round as in the original:
#  - waves.lua StartWave: Game.SetRepairQuota(min(GetWaveNumber() x 5, 50)) (bytecode 34-42,
#    after IncrementWaveNumber: 5 on round 1 ... 50 from round 10); StartDogWave does not
#    set it, so a dog round keeps what was left. Game.SetRepairPoints(10) (waves.lua 688).
#  - SetRepairQuota (kiwi va 0xa67f4) stores the count in the game object (+0x08), and
#    SetRepairPoints (va 0xaf488) the points (+0x0c). The barricade handler (kiwi file
#    0xfaf30, a board put back by the local player) does: if quota > 0 { quota -= 1;
#    AddPoints(points); stat "repairpoints" }, then always "session/total_repairbarricade". With the
#    quota used up the board is still repaired, for no points (the same handler then
#    appends "_only" to a name, not recovered: probably the prompt/icon "repair only").
# Loading tip LS (fcbbc0f9): "The total number of points awarded per round is capped /
# Each subsequent Round increases the points cap". Saved (provider) for a resumed dog round.
class_name RepairQuota
extends Node

const PER_ROUND := 5
const MAX_QUOTA := 50
const POINTS := 10        # Game.SetRepairPoints(10)

static var instance: RepairQuota


# The current game's quota, or null (no game, or one already freed).
static func current() -> RepairQuota:
	return instance if is_instance_valid(instance) else null


var quota := 0            # paid repairs left this round
var points := POINTS


static func create(g: Node) -> RepairQuota:
	var q := RepairQuota.new()
	q.name = "RepairQuota"
	g.add_child(q)
	instance = q
	return q


func _ready() -> void:
	add_to_group(SaveGame.PROVIDER_GROUP)


# waves.lua StartWave (not StartDogWave)
func start_wave(round_number: int) -> void:
	quota = mini(round_number * PER_ROUND, MAX_QUOTA)


# A board put back by the player: the points it pays (0 once the quota is used up).
func take() -> int:
	if quota <= 0:
		return 0
	quota -= 1
	return points


func save_state() -> Dictionary:
	return {"quota": quota}


func load_state(d: Dictionary) -> void:
	quota = int(d.get("quota", quota))
