# Character voice lines (Game.PlayMultiplayerSound / kiwi 0x192184 via Sfx.vox: only on the
# maps whose script turns vox on, Shi No Numa and Der Riese; chance, priority and delay come
# from the vox table) that the original game code plays by itself, for the local player:
#  - ammo_out / ammo_low (after each shot, kiwi va 0x20fdc0): "low" is (clip + reserve) x 100 /
#    the gun's clip size <= LowClipPercentage (35, console.bin; kiwi va 0x223dac). A shot that
#    makes the gun low says ammo_low; once low, the shot that leaves no ammo at all says
#    ammo_out (priority 4000).
#  - been_hit: the player's health component takes damage from a zombie (attacker entity
#    flag 0x4000; kiwi va 0x2023c8 .. 0x202570). Called by zombie.gd / dog.gd.
#  - close_kill (30 %): a zombie or dog killed by the player with the knife (damage type 3),
#    or with any other weapon within CloseKillDistanceSq 160000 units² = 1 m (kiwi va
#    0x20c54c: 0x20c84c knife branch, 0x20c768 distance check).
#  - mystery box (kiwi va 0x11e700..0x11ec7c): "teddy" when the bear comes out; when the
#    weapon has risen, weapon_bad for the guns whose CItemGun "bad" byte (0x141) is set;
#    when the player takes it, weapon_good for those with the "good" byte (0x140)
#    (tools/weapon_stats.py flag_140 / flag_141). Called by mystery_box.gd.
#  - packapunch: the player takes the upgraded gun (kiwi va 0x1210b8). pack_a_punch.gd.
class_name VoxLines
extends Node

const LOW_CLIP_PERCENT := 35       # console.bin LowClipPercentage
const CLOSE_KILL_DIST := 1.0       # CloseKillDistanceSq 160000 (400 units)
# CItemGun byte 0x140 ("good") / 0x141 ("bad"), analysis/weapon_stats.json
const GOOD := ["trenchgun", "shotgun", "bar", "mg42", "raygun", "fg42", "sawnoff", "browning"]
const BAD := ["kar98", "carbine", "garand", "g43", "springfield", "arisaka"]

static var instance: VoxLines
var game: Game
var _weapon := ""
var _total := -1
var log_lines: Array = []          # tests: lines asked for ([line, played])


static func create(g: Game) -> VoxLines:
	var v := VoxLines.new()
	v.name = "VoxLines"
	v.game = g
	g.add_child(v)
	instance = v
	g.get_tree().node_added.connect(v._on_node_added)
	return v


static func say(line: String) -> bool:
	var played := Sfx.instance != null and Sfx.instance.vox(line)
	if instance and instance.log_lines.size() < 200:
		instance.log_lines.append([line, played])
	return played


static func box_shown(weapon: String) -> void:
	if weapon in BAD:
		say("weapon_bad")


static func box_taken(weapon: String) -> void:
	if weapon in GOOD:
		say("weapon_good")


# Headshot streak of 3 / 5 / 7 (HeadshotAnnounceCount, kiwi file 0x1309b4: with player vox the
# line "killstreak%d" via the vox function 0x191184, player.gd head_popped). The vox table
# keeps these three lines under their hash (cd0c35ec..ee = killstreak1..3, variants
# player0_killstreak<n> 29ae5d08..0a).
static func killstreak(n: int) -> void:
	say(Sfx.iw_hash("killstreak%d" % n))


static func hit_by_enemy() -> void:
	if instance and instance.game and instance.game.player and not instance.game.player.dead:
		say("been_hit")


func _on_node_added(n: Node) -> void:
	if n is Zombie:   # dogs too
		(n as Zombie).killed.connect(_on_killed)


func _on_killed(z: Zombie, _headshot: bool, knife: bool) -> void:
	if game == null or not is_instance_valid(game) or game.player == null or game.player.dead:
		return
	if game.suppress_kill_points or game.get("_nuking"):
		return   # traps and the nuke: not the player's kill
	if knife or game.player.global_position.distance_to(z.global_position) <= CLOSE_KILL_DIST:
		say("close_kill")


static func is_low(mag: int, reserve: int, clip: int) -> bool:
	return clip > 0 and (mag + reserve) * 100 / clip <= LOW_CLIP_PERCENT


func _process(_delta: float) -> void:
	var p := game.player if game else null
	if p == null or p.weapons.is_empty():
		return
	var w: Dictionary = p.weapon()
	var key := "%s%s" % [w.get("name", ""), "+" if w.get("upgraded", false) else ""]
	var total := int(w.get("mag", 0)) + int(w.get("reserve", 0))
	if key == _weapon and total < _total:
		var clip := int(Weapons.stats_of(w).get("mag", 0))
		var was_low := is_low(_total, 0, clip)
		if was_low:
			if total == 0:
				say("ammo_out")
		elif is_low(total, 0, clip):
			say("ammo_low")
	_weapon = key
	_total = total
