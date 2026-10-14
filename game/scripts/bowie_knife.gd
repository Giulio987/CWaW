# Bowie knife (Der Riese). Original:
#   - wall buy "BuyWeaponBowie" (a2ee0fb5 = iw_hash("BuyWeaponBowie")): a CActionBuyWeaponSpec
#     whose weapon is 9c52b068 = iw_hash("bowieKnife"), cost 3000 (entities.json); only on
#     Der Riese (the hash is in the derriese environment group only)
#   - CItemKnife "bowieKnife" (player group, CItemKnife::Serialise va 0xfef00, see
#     tools/weapon_stats.py knives): damage 1000 (knife 200, shovel 400), first-person model
#     a507b242 (knife: 78cd240c, lod1 a50d6778 / 78d2d941)
#   - player vox line "weapon_bowie" when bought (vox table of the player entity)
#   - achievement 101 "40 Knives" (200e86a9): 40 kills with the Bowie in one game,
#     condition bowieKnife.session_totalzombiekilled (achievements.gd)
# The slash is the remake's procedural knife slash (viewmodel.gd) with the bowie model; the
# base knife keeps its 150.
# Node under the player (like GrenadeBelt): owned flag, wall buy and save state.
class_name BowieKnife
extends Node

const WEAPON_HASH := "9c52b068"   # CActionBuyWeaponSpec weapon of BuyWeaponBowie
const DAMAGE := 1000.0            # CItemKnife bowieKnife
const MODEL := "a507b242"         # CItemKnife bowieKnife model (player.glb node)
# the model's blade runs down -Y from the knuckle guard (origin at the pommel, 0.61 m
# long in the export): turned so the blade is along +X like knife_lod1, scaled to ~0.3 m
# (knife_lod1 is 0.28 m)
const FIX_SCALE := 0.5
const GRIP := 0.035

var player: Player
var owned := false


static func of(p: Node) -> BowieKnife:
	return p.get_node_or_null("BowieKnife") as BowieKnife if p else null


static func damage_of(p: Node) -> float:
	var b := of(p)
	return DAMAGE if b and b.owned else -1.0


func _ready() -> void:
	name = "BowieKnife"
	player = get_parent() as Player
	add_to_group(SaveGame.PROVIDER_GROUP)
	_setup_buys.call_deferred()


func _setup_buys() -> void:
	if player.game == null or player.game.level == null:
		return
	# the generic wall-buy list (game.gd) would sell "9c52b068" as a gun: the bowie has its own buy
	for b in player.game.wall_buys.duplicate():
		if String(b.get("weapon", "")) == WEAPON_HASH:
			player.game.wall_buys.erase(b)
			var buy := BowieBuy.new()
			buy.name = "BowieBuy"
			buy.cost = int(b.get("cost", 3000))
			buy.use_point = b["position"]
			player.game.level.add_child(buy)
			buy.global_position = buy.use_point
			player.game.level.interactables.append(buy)
	var s := SaveGame.resumed_state(self)
	if not s.is_empty() and not has_meta("save_loaded"):
		set_meta("save_loaded", true)
		load_state(s)


func give() -> void:
	owned = true
	_apply()
	Sfx.instance.vox("weapon_bowie")


func _apply() -> void:
	var vm := player.get("_viewmodel") as Viewmodel
	if vm == null:
		return
	if owned:
		# -Y (blade) -> +X, then a quarter turn about the blade so its flat side faces the camera
		var fix := Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.BACK, PI / 2)
		vm.set_knife_model(MODEL, fix.scaled(Vector3.ONE * FIX_SCALE), GRIP)
	else:
		vm.set_knife_model(Viewmodel.KNIFE_MODEL)


func save_key() -> String:
	return "bowie_knife"


func save_state() -> Dictionary:
	return {"owned": owned}


func load_state(d: Dictionary) -> void:
	owned = bool(d.get("owned", false))
	_apply()
