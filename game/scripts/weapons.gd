# Weapon stats. damage/head (headshot multiplier) are community-tested World at War
# values (GameFAQs zombie weapon lists, Call of Duty wiki); the iOS values live in the
# compiled engine and were not recovered. Names match the CItemGun resource names; costs come from the
# level's wall-buy entities.
class_name Weapons

const STATS := {
	"colt45":       {"damage": 20,  "head": 3.5, "mag": 8,   "reserve": 32,  "rate": 0.18, "auto": false, "pellets": 1, "reload": 1.6, "range": 60.0},
	"kar98":        {"damage": 100, "head": 3.5, "mag": 5,   "reserve": 50,  "rate": 1.0,  "auto": false, "pellets": 1, "reload": 2.4, "range": 120.0},
	"arisaka":      {"damage": 100, "head": 3.5, "mag": 5,   "reserve": 50,  "rate": 1.0,  "auto": false, "pellets": 1, "reload": 2.4, "range": 120.0},
	"springfield":  {"damage": 100, "head": 2.0, "mag": 5,   "reserve": 50,  "rate": 1.0,  "auto": false, "pellets": 1, "reload": 2.4, "range": 120.0},
	"carbine":      {"damage": 120,  "head": 2.7, "mag": 15,  "reserve": 120, "rate": 0.16, "auto": false, "pellets": 1, "reload": 2.0, "range": 90.0},
	"garand":       {"damage": 68,  "head": 2.7, "mag": 8,   "reserve": 128, "rate": 0.2,  "auto": false, "pellets": 1, "reload": 2.2, "range": 110.0},
	"g43":          {"damage": 90,  "head": 2.7, "mag": 10,  "reserve": 120, "rate": 0.2,  "auto": false, "pellets": 1, "reload": 2.4, "range": 110.0},
	"thompson":     {"damage": 120,  "head": 4.0, "mag": 20,  "reserve": 160, "rate": 0.08, "auto": true,  "pellets": 1, "reload": 2.5, "range": 60.0},
	"mp40":         {"damage": 100,  "head": 4.0, "mag": 32,  "reserve": 192, "rate": 0.1,  "auto": true,  "pellets": 1, "reload": 2.5, "range": 60.0},
	"type100":      {"damage": 100,  "head": 4.0, "mag": 30,  "reserve": 180, "rate": 0.08, "auto": true,  "pellets": 1, "reload": 2.5, "range": 60.0},
	"stg44":        {"damage": 100,  "head": 2.7, "mag": 30,  "reserve": 180, "rate": 0.1,  "auto": true,  "pellets": 1, "reload": 2.6, "range": 90.0},
	"ppsh":         {"damage": 100,  "head": 4.0, "mag": 71,  "reserve": 284, "rate": 0.05, "auto": true,  "pellets": 1, "reload": 3.0, "range": 60.0},
	"bar":          {"damage": 100,  "head": 2.7, "mag": 20,  "reserve": 140, "rate": 0.13, "auto": true,  "pellets": 1, "reload": 2.8, "range": 100.0},
	"fg42":         {"damage": 130,  "head": 2.7, "mag": 20,  "reserve": 160, "rate": 0.08, "auto": true,  "pellets": 1, "reload": 2.8, "range": 100.0},
	"mg42":         {"damage": 130,  "head": 3.0, "mag": 125, "reserve": 500, "rate": 0.05, "auto": true,  "pellets": 1, "reload": 5.0, "range": 100.0},
	"browning":     {"damage": 180,  "head": 2.0, "mag": 125, "reserve": 500, "rate": 0.1,  "auto": true,  "pellets": 1, "reload": 5.0, "range": 100.0},
	"shotgun":      {"damage": 200,  "head": 1.5, "mag": 2,   "reserve": 60,  "rate": 0.3,  "auto": false, "pellets": 8, "reload": 2.2, "range": 20.0},
	"sawnoff":      {"damage": 200,  "head": 1.5, "mag": 2,   "reserve": 60,  "rate": 0.3,  "auto": false, "pellets": 8, "reload": 2.2, "range": 15.0},
	"trenchgun":    {"damage": 160,  "head": 1.5, "mag": 6,   "reserve": 60,  "rate": 0.8,  "auto": false, "pellets": 8, "reload": 3.0, "range": 20.0},
	"ptrs":         {"damage": 3000, "head": 1.0, "mag": 5,   "reserve": 60,  "rate": 1.2,  "auto": false, "pellets": 1, "reload": 3.5, "range": 150.0},
	"flamethrower": {"damage": 30,  "head": 1.0, "mag": 100, "reserve": 300, "rate": 0.05, "auto": true,  "pellets": 1, "reload": 3.0, "range": 8.0},
	"raygun":       {"damage": 1000, "head": 1.0, "mag": 20,  "reserve": 160, "rate": 0.25, "auto": false, "pellets": 1, "reload": 2.5, "range": 100.0},
}

const DISPLAY := {
	"colt45": "M1911", "kar98": "Kar98k", "carbine": "M1A1 Carbine", "thompson": "Thompson", "shotgun": "Double-Barreled Shotgun",
	"sawnoff": "Sawed-Off Shotgun", "trenchgun": "M1897 Trench Gun", "bar": "BAR", "flamethrower": "M2 Flamethrower",
	"mp40": "MP40", "stg44": "STG-44", "type100": "Type 100", "garand": "M1 Garand", "g43": "Gewehr 43", "ppsh": "PPSh-41",
	"mg42": "MG42", "browning": "Browning M1919", "fg42": "FG42", "ptrs": "PTRS-41", "springfield": "Springfield", "raygun": "Ray Gun",
}


static func stats(name: String) -> Dictionary:
	return STATS.get(name, STATS["colt45"])


static func display(name: String) -> String:
	return DISPLAY.get(name, name.capitalize())
