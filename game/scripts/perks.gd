# Perk-a-Cola data (World at War values). The machines are CActionBuyPerkSpec
# entities; which perk a machine sells is told by its model.
class_name Perks
extends RefCounted

const JUGG_HEALTH := 200.0     # Juggernog: PerkedPlayerHealth 40 / PlayerHealth 20 (x Player.HEALTH_SCALE): 100 -> 200 (Recruit 150 -> 300, Player.base_health)
const SPEED_RELOAD := 0.5      # Speed Cola: reload time x0.5 (original: the guns' reload states run at double speed)
const DBTAP_RATE := 0.5        # Double Tap: fire interval x0.5 (original: the fire states run at double speed, tools/weapon_stats.py)
const REVIVE_GRACE := 3.0      # Quick Revive (solo): seconds of invulnerability after getting up

# perk -> display name, HUD colour, icon index in the perk atlas, default cost
const INFO := {
	"jugga": {"name": "Juggernog", "color": Color(0.85, 0.15, 0.1), "icon": 0, "cost": 2500},
	"speed": {"name": "Speed Cola", "color": Color(0.2, 0.75, 0.2), "icon": 1, "cost": 3000},
	"dbtap": {"name": "Double Tap Root Beer", "color": Color(0.85, 0.6, 0.15), "icon": 2, "cost": 2000},
	"revive": {"name": "Quick Revive", "color": Color(0.35, 0.6, 0.95), "icon": 3, "cost": 1500},
}
const ORDER := ["jugga", "speed", "dbtap", "revive"]

# machine model hash -> perk (same models on derriese, shinonuma and verruckt)
const MODELS := {"9939d887": "jugga", "358a948b": "speed", "89f8e9c5": "dbtap", "cdc21f4b": "revive"}

# Perk icons: four 32x33 cells at the top right of a 256x256 UI atlas
# (red Juggernog, green Speed Cola, brown Double Tap, blue Quick Revive).
const ICON_ATLAS := "res://assets/textures/fixed/54f786f3.png"
const ICON_X := 125
const ICON_STEP := 33
const ICON_SIZE := Vector2(32, 33)

# Shi No Numa: every location has one machine entity per perk ("BuyPerk<perk><location>"
# in shinonuma.lua) and shows one of them.
const SHINO_LOCATIONS := ["Fishing", "Doctors", "Storage", "CommRoom"]
const SHINO_NAMES := {"jugga": "Jugga", "speed": "Speed", "dbtap": "DbTap", "revive": "Revive"}

static var _icons := {}


static func kind_of(e: Dictionary) -> String:
	for h in e.get("models", []):
		if MODELS.has(h):
			return MODELS[h]
	var n := String(e["name"]).to_lower()
	for k in SHINO_NAMES:
		if n.contains(String(SHINO_NAMES[k]).to_lower()):
			return k
	return ""


static func display(kind: String) -> String:
	return INFO[kind]["name"] if INFO.has(kind) else kind


static func icon(kind: String) -> Texture2D:
	if not INFO.has(kind) or not ResourceLoader.exists(ICON_ATLAS):
		return null
	if not _icons.has(kind):
		var t := AtlasTexture.new()
		t.atlas = load(ICON_ATLAS)
		t.region = Rect2(Vector2(ICON_X + ICON_STEP * int(INFO[kind]["icon"]), 0), ICON_SIZE)
		_icons[kind] = t
	return _icons[kind]
