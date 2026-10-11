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


# Pack-a-Punch (Der Riese). mag/reserve are the original "<weapon>_upgrade" CItemGun
# values (player group); "mul" multiplies the damage above: the ratio of the upgraded
# to the normal gun's damage field where the original raises it, otherwise x1.5
# (World at War upgrades all do more damage). Names are the World at War ones.
const UPGRADES := {
	"colt45":       {"mag": 6,   "reserve": 40,  "mul": 5.0, "name": "Mustang & Sally"},
	"kar98":        {"mag": 8,   "reserve": 60,  "mul": 2.0, "name": "Armageddon"},
	"arisaka":      {"mag": 5,   "reserve": 50,  "mul": 1.5, "name": "Arisaka (potenziato)"},
	"springfield":  {"mag": 5,   "reserve": 50,  "mul": 1.5, "name": "Springfield (potenziato)"},
	"carbine":      {"mag": 15,  "reserve": 150, "mul": 1.5, "name": "Widdershins RC-1"},
	"garand":       {"mag": 12,  "reserve": 150, "mul": 1.5, "name": "M1000"},
	"g43":          {"mag": 12,  "reserve": 170, "mul": 1.5, "name": "G115 Compressor"},
	"thompson":     {"mag": 40,  "reserve": 300, "mul": 1.5, "name": "Gibs-O-Matic"},
	"mp40":         {"mag": 64,  "reserve": 192, "mul": 1.5, "name": "The Afterburner"},
	"type100":      {"mag": 60,  "reserve": 220, "mul": 1.5, "name": "1001 Samurais"},
	"stg44":        {"mag": 60,  "reserve": 300, "mul": 1.5, "name": "Spatz-447 +"},
	"ppsh":         {"mag": 115, "reserve": 700, "mul": 1.5, "name": "The Reaper"},
	"bar":          {"mag": 30,  "reserve": 180, "mul": 1.5, "name": "The Widow Maker"},
	"fg42":         {"mag": 64,  "reserve": 400, "mul": 1.5, "name": "Bauer Rifle"},
	"mg42":         {"mag": 125, "reserve": 750, "mul": 1.5, "name": "Barracuda FU-A11"},
	"browning":     {"mag": 125, "reserve": 750, "mul": 1.5, "name": "B115 Accelerator"},
	"shotgun":      {"mag": 2,   "reserve": 60,  "mul": 1.5, "name": "24 Bore Long Range"},
	"sawnoff":      {"mag": 2,   "reserve": 60,  "mul": 1.5, "name": "The Snuff Box"},
	"trenchgun":    {"mag": 6,   "reserve": 60,  "mul": 1.5, "name": "Gut Shot"},
	"ptrs":         {"mag": 8,   "reserve": 55,  "mul": 1.5, "name": "The Penetrator"},
	"flamethrower": {"mag": 100, "reserve": 300, "mul": 1.5, "name": "Dante's Inferno"},
	"raygun":       {"mag": 40,  "reserve": 200, "mul": 1.5, "name": "Porter's X2 Ray Gun"},
}


static func can_upgrade(name: String) -> bool:
	return UPGRADES.has(name)


# Stats of a held weapon ({name, mag, reserve, upgraded?}).
static func stats_of(w: Dictionary) -> Dictionary:
	var s := stats(w["name"])
	if not w.get("upgraded", false) or not UPGRADES.has(w["name"]):
		return s
	var u: Dictionary = UPGRADES[w["name"]]
	s = s.duplicate()
	s["damage"] = s["damage"] * u["mul"]
	s["mag"] = u["mag"]
	s["reserve"] = u["reserve"]
	return s


static func display_of(w: Dictionary) -> String:
	if w.get("upgraded", false) and UPGRADES.has(w["name"]):
		return UPGRADES[w["name"]]["name"]
	return display(w["name"])
