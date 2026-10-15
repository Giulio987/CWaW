# Weapon stats: the original iOS values, read from the CItemGun resources of the player
# group by tools/weapon_stats.py (field layout and damage formula documented there; full
# dump in analysis/weapon_stats.json). Names match the CItemGun resource names; costs
# come from the level's wall-buy entities; display names are the World at War ones.
#
#   damage, min       base damage per hit and the floor after falloff (CItemGun 0x84 / 0x78)
#   loc               hit-location multipliers: head, left arm, right arm, chest, pelvis, leg
#                     (the other leg has no entry: x1). "head" = loc[0], kept for old callers
#   mag, reserve      magazine and spare ammo (0x7c / 0x80, as in World at War: colt 8 + 80)
#   rate              seconds per shot: the fire state of the gun's CIsAnimStateMachine
#                     (+ the rechamber state for bolt actions and the trench gun's pump)
#   reload            the reload state (trench gun: per shell x magazine)
#   hits, pierce      a bullet goes through up to `hits` targets, each one already passed
#                     removes damage x pierce (0x54 / 0x64)
#   falloff_start, falloff   metres of full damage, damage lost per metre after (0x68 / 0x6c)
#   cone, lateral_start, lateral   shotguns: no pellets; every target inside a cone of
#                     `cone` degrees (full angle) is hit once, losing `lateral` damage per
#                     metre off the aim axis beyond lateral_start (0x60 / 0x70 / 0x74)
#   range             hitscan ray length (no limit found in the original: inferred)
# Confirmed in the executable: damage formula (CItemGun::GetDamage, see hit_damage()),
# field meanings above, the flamethrower (damage = damage per second, applied every
# FlamethrowerDamagePeriod 80 ms to everything within FlamethrowerMaxRange 2800 = 7 m;
# overheats after 4 s, 7 s upgraded), the Ray Gun (projectile whose impact spawns a
# CSplashEffect: 2450 to everything within 900 units = 2.25 m, no falloff).
# Inferred: hit-location names (order of the zombie's hit volumes), reserve = spare
# ammo, the shotgun's pierce order, the flamethrower's ammo model below.
class_name Weapons

const STATS := {
	"colt45":       {"damage": 30, "min": 20, "head": 3.5, "loc": [3.5, 0.85, 0.85, 1.25, 0.85, 0.85], "mag": 8, "reserve": 80,
		"rate": 0.25, "auto": false, "reload": 2.275, "hits": 10, "pierce": 0.7, "falloff_start": 6.35, "falloff": 2.93},
	# .357 Magnum: CItemGun "magnum" (mystery box only: MysteryWeapons<map> in console.bin lists
	# it on all four maps; no wall buy). Pierce 40/4096, falloff 3900 units / 252 per unit.
	"magnum":       {"damage": 1060, "min": 300, "head": 3.5, "loc": [3.5, 0.85, 0.85, 1.25, 0.85, 0.85], "mag": 6, "reserve": 80,
		"rate": 0.266, "auto": false, "reload": 3.0, "hits": 20, "pierce": 0.0098, "falloff_start": 9.75, "falloff": 24.609},
	"kar98":        {"damage": 150, "min": 100, "head": 8.0, "loc": [8.0, 1.0, 1.0, 1.0, 1.0, 1.0], "mag": 5, "reserve": 50,
		"rate": 1.432, "auto": false, "reload": 2.424, "hits": 20, "pierce": 0.1, "falloff_start": 30.48, "falloff": 0.781},
	"arisaka":      {"damage": 150, "min": 100, "head": 8.0, "loc": [8.0, 1.0, 1.0, 1.0, 1.0, 1.0], "mag": 5, "reserve": 50,
		"rate": 1.432, "auto": false, "reload": 2.272, "hits": 20, "pierce": 0.1, "falloff_start": 30.48, "falloff": 0.781},
	"springfield":  {"damage": 150, "min": 100, "head": 8.0, "loc": [8.0, 1.0, 1.1, 1.1, 1.0, 1.0], "mag": 5, "reserve": 50,
		"rate": 1.599, "auto": false, "reload": 2.583, "hits": 20, "pierce": 0.1, "falloff_start": 30.48, "falloff": 0.781},
	"carbine":      {"damage": 68, "min": 50, "head": 2.7, "loc": [2.7, 0.7, 0.7, 1.25, 1.0, 1.0], "mag": 15, "reserve": 120,
		"rate": 0.233, "auto": false, "reload": 2.694, "hits": 20, "pierce": 0.6, "falloff_start": 26.01, "falloff": 0.488},
	"garand":       {"damage": 68, "min": 50, "head": 2.7, "loc": [2.7, 0.7, 0.7, 1.25, 1.0, 1.0], "mag": 8, "reserve": 128,
		"rate": 0.26, "auto": false, "reload": 1.631, "hits": 20, "pierce": 0.6, "falloff_start": 26.01, "falloff": 0.488},
	"g43":          {"damage": 90, "min": 50, "head": 2.7, "loc": [2.7, 0.8, 0.8, 1.25, 1.0, 1.0], "mag": 10, "reserve": 120,
		"rate": 0.199, "auto": false, "reload": 2.722, "hits": 20, "pierce": 0.6, "falloff_start": 26.01, "falloff": 1.074},
	"thompson":     {"damage": 120, "min": 80, "head": 4.0, "loc": [4.0, 1.0, 1.0, 1.0, 1.0, 1.0], "mag": 20, "reserve": 200,
		"rate": 0.116, "auto": true, "reload": 1.638, "hits": 20, "pierce": 0.6, "falloff_start": 20.32, "falloff": 1.562},
	"mp40":         {"damage": 100, "min": 60, "head": 4.0, "loc": [4.0, 1.0, 1.0, 1.0, 1.0, 1.0], "mag": 32, "reserve": 192,
		"rate": 0.116, "auto": true, "reload": 2.805, "hits": 20, "pierce": 0.6, "falloff_start": 20.32, "falloff": 1.562},
	"type100":      {"damage": 120, "min": 80, "head": 4.0, "loc": [4.0, 1.0, 1.0, 1.0, 1.0, 1.0], "mag": 20, "reserve": 200,
		"rate": 0.099, "auto": true, "reload": 2.694, "hits": 20, "pierce": 0.6, "falloff_start": 20.32, "falloff": 1.562},
	"stg44":        {"damage": 100, "min": 70, "head": 2.7, "loc": [2.7, 0.5, 0.5, 1.0, 1.0, 1.0], "mag": 30, "reserve": 180,
		"rate": 0.183, "auto": true, "reload": 2.866, "hits": 20, "pierce": 0.4, "falloff_start": 26.01, "falloff": 0.781},
	"ppsh":         {"damage": 100, "min": 60, "head": 4.0, "loc": [4.0, 1.0, 1.0, 1.0, 1.0, 1.0], "mag": 71, "reserve": 355,
		"rate": 0.041, "auto": true, "reload": 2.599, "hits": 20, "pierce": 0.6, "falloff_start": 20.32, "falloff": 2.246},
	"bar":          {"damage": 250, "min": 85, "head": 2.7, "loc": [2.7, 1.7, 1.7, 2.0, 1.0, 1.0], "mag": 20, "reserve": 140,
		"rate": 0.199, "auto": true, "reload": 2.972, "hits": 20, "pierce": 0.1, "falloff_start": 26.01, "falloff": 0.391},
	"fg42":         {"damage": 250, "min": 85, "head": 2.7, "loc": [2.7, 1.7, 1.7, 2.0, 1.0, 1.0], "mag": 32, "reserve": 192,
		"rate": 0.066, "auto": true, "reload": 4.138, "hits": 20, "pierce": 0.1, "falloff_start": 26.01, "falloff": 0.391},
	"mg42":         {"damage": 250, "min": 90, "head": 3.0, "loc": [3.0, 1.0, 1.0, 1.0, 1.0, 1.0], "mag": 125, "reserve": 500,
		"rate": 0.051, "auto": true, "reload": 4.194, "hits": 20, "pierce": 0.1, "falloff_start": 26.01, "falloff": 1.074},
	"browning":     {"damage": 250, "min": 90, "head": 3.0, "loc": [3.0, 1.0, 1.0, 1.0, 1.0, 1.0], "mag": 125, "reserve": 500,
		"rate": 0.114, "auto": true, "reload": 7.444, "hits": 20, "pierce": 0.1, "falloff_start": 26.01, "falloff": 1.074},
	"shotgun":      {"damage": 1200, "min": 15, "head": 1.0, "mag": 2, "reserve": 60, "rate": 0.399, "auto": false,
		"reload": 2.638, "hits": 10, "pierce": 0.3, "falloff_start": 4.33, "falloff": 128.613,
		"cone": 9.93, "lateral_start": 0.14, "lateral": 39.941, "range": 30.0},
	"sawnoff":      {"damage": 1600, "min": 15, "head": 1.0, "mag": 2, "reserve": 60, "rate": 0.399, "auto": false,
		"reload": 2.638, "hits": 10, "pierce": 0.3, "falloff_start": 4.33, "falloff": 174.902,
		"cone": 9.93, "lateral_start": 0.14, "lateral": 39.941, "range": 30.0},
	"trenchgun":    {"damage": 960, "min": 15, "head": 1.0, "mag": 6, "reserve": 60, "rate": 1.25, "auto": false,
		"reload": 2.664, "hits": 10, "pierce": 0.3, "falloff_start": 4.33, "falloff": 102.539,
		"cone": 9.93, "lateral_start": 0.14, "lateral": 39.941, "range": 30.0},
	"ptrs":         {"damage": 1000, "min": 1000, "head": 10.0, "loc": [10.0, 2.0, 2.0, 2.25, 2.0, 1.0], "mag": 5, "reserve": 55,
		"rate": 0.899, "auto": false, "reload": 4.472, "hits": 20, "pierce": 0.6, "falloff_start": 101.6, "falloff": 0.0},
	# damage/dps = damage per second (936 every second, dealt in 80 ms ticks); no ammo in the
	# original (mag 1 / reserve 1) but a heat meter: 4 s of fire overheat it, then it cools
	# for as long. Modelled as a 4 s "magazine" (rate = the 80 ms tick), a 4 s "reload"
	# (cool-down) and endless reserve.
	"flamethrower": {"damage": 936, "dps": 936, "min": 936, "head": 1.0, "mag": 50, "reserve": 999, "rate": 0.08,
		"auto": true, "reload": 4.0, "hits": 1, "pierce": 0.0, "range": 7.0},
	# a projectile: the hit spawns a 2450 splash over 2.25 m (explosion.gd RAYGUN)
	"raygun":       {"damage": 2450, "min": 2450, "head": 1.0, "mag": 20, "reserve": 160, "rate": 0.433, "auto": false,
		"reload": 3.333, "hits": 1, "pierce": 0.0, "range": 100.0},
	# a projectile (the Ray Gun's) whose impact kills every zombie in a growing sphere,
	# up to 10 (wunderwaffe.gd: CRadialEffectWunderwaffe); "damage" is the gun's 2450
	"wunderwaffe":  {"damage": 2450, "min": 2450, "head": 1.0, "mag": 3, "reserve": 24, "rate": 0.599, "auto": false,
		"reload": 5.5, "hits": 1, "pierce": 0.0, "range": 100.0},
}

# Start pistol: the Lua scripts call Game.AddPlayerWeapon("colt45", 32) (40 after a death)
const START_RESERVE := 32

const DISPLAY := {
	"colt45": "M1911", "kar98": "Kar98k", "carbine": "M1A1 Carbine", "thompson": "Thompson", "shotgun": "Double-Barreled Shotgun",
	"sawnoff": "Sawed-Off Shotgun", "trenchgun": "M1897 Trench Gun", "bar": "BAR", "flamethrower": "M2 Flamethrower",
	"mp40": "MP40", "stg44": "STG-44", "type100": "Type 100", "garand": "M1 Garand", "g43": "Gewehr 43", "ppsh": "PPSh-41",
	"mg42": "MG42", "browning": "Browning M1919", "fg42": "FG42", "ptrs": "PTRS-41", "springfield": "Springfield", "raygun": "Ray Gun",
	"wunderwaffe": "Wunderwaffe DG-2", "magnum": ".357 Magnum",
	"arisaka": "Arisaka",
}

const LOC_HEAD := 0
const LOC_LEFT_ARM := 1
const LOC_RIGHT_ARM := 2
const LOC_CHEST := 3
const LOC_PELVIS := 4
const LOC_LEG := 5

const RANGE := 100.0   # default hitscan range (m)


static func stats(name: String) -> Dictionary:
	return STATS.get(name, STATS["colt45"])


static func display(name: String) -> String:
	return DISPLAY.get(name, name.capitalize())


# Pack-a-Punch (Der Riese): the original "<weapon>_upgrade" CItemGun. "stats" are the
# values that differ from the normal gun (everything else is identical in the original:
# the Thompson, PPSh, carbine... only get more ammo / a faster fire state). Names are the
# World at War ones.
const UPGRADES := {
	# Mustang & Sally: the original explosive projectile (1000 damage, 4.25 m splash,
	# mustang_bolt.gd, fired by WeaponFx.fire); the stats below are unused by it.
	"colt45":       {"mag": 6,   "reserve": 40,  "name": "Mustang & Sally",
		"stats": {"damage": 1000, "min": 1000, "head": 1.0, "loc": [], "hits": 1, "pierce": 0.0, "falloff": 0.0}},
	"kar98":        {"mag": 8,   "reserve": 60,  "name": "Armageddon", "stats": {"damage": 300}},
	"arisaka":      {"mag": 5,   "reserve": 50,  "name": "Arisaka (potenziato)", "stats": {}},
	"springfield":  {"mag": 5,   "reserve": 50,  "name": "Springfield (potenziato)", "stats": {}},
	"carbine":      {"mag": 15,  "reserve": 150, "name": "Widdershins RC-1", "stats": {"rate": 0.07, "auto": true}},
	"garand":       {"mag": 12,  "reserve": 150, "name": "M1000", "stats": {"damage": 80}},
	"g43":          {"mag": 12,  "reserve": 170, "name": "G115 Compressor", "stats": {"damage": 120}},
	"thompson":     {"mag": 40,  "reserve": 300, "name": "Gibs-O-Matic", "stats": {}},
	"mp40":         {"mag": 64,  "reserve": 192, "name": "The Afterburner", "stats": {"rate": 0.077}},
	"type100":      {"mag": 60,  "reserve": 220, "name": "1001 Samurais", "stats": {"rate": 0.066}},
	"stg44":        {"mag": 60,  "reserve": 300, "name": "Spatz-447 +", "stats": {"rate": 0.122}},
	"ppsh":         {"mag": 115, "reserve": 700, "name": "The Reaper", "stats": {}},
	"bar":          {"mag": 30,  "reserve": 180, "name": "The Widow Maker", "stats": {"rate": 0.133}},
	"fg42":         {"mag": 64,  "reserve": 400, "name": "Bauer Rifle", "stats": {"damage": 300}},
	"mg42":         {"mag": 125, "reserve": 750, "name": "Barracuda FU-A11", "stats": {"damage": 300, "rate": 0.038}},
	"browning":     {"mag": 125, "reserve": 750, "name": "B115 Accelerator", "stats": {"damage": 300, "rate": 0.081}},
	"shotgun":      {"mag": 2,   "reserve": 60,  "name": "24 Bore Long Range", "stats": {"damage": 1800, "falloff": 100.0}},
	"sawnoff":      {"mag": 2,   "reserve": 60,  "name": "The Snuff Box", "stats": {}},
	"trenchgun":    {"mag": 10,  "reserve": 60,  "name": "Gut Shot", "stats": {"damage": 1400, "reload": 4.44}},
	"ptrs":         {"mag": 8,   "reserve": 55,  "name": "The Penetrator", "stats": {"damage": 1200}},
	# 7 s to overheat (CItemGun 0x100 = 7.0)
	"flamethrower": {"mag": 87,  "reserve": 999, "name": "Dante's Inferno", "stats": {"damage": 1200, "dps": 1200, "reload": 7.0}},
	"raygun":       {"mag": 40,  "reserve": 200, "name": "Porter's X2 Ray Gun", "stats": {}},
	# wunderwaffe_upgrade: damage 3000, reload state 4714 ms; a bigger sphere (wunderwaffe.gd)
	"wunderwaffe":  {"mag": 6,   "reserve": 30,  "name": "Wunderwaffe DG-3 JZ", "stats": {"damage": 3000, "reload": 4.714}},
	# magnum_upgrade: damage 1500, same 6 + 80 (CItemGun); no WaW name known for it
	"magnum":       {"mag": 6,   "reserve": 80,  "name": ".357 Magnum (potenziata)", "stats": {"damage": 1500}},
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
	s.merge(u.get("stats", {}), true)
	s["mag"] = u["mag"]
	s["reserve"] = u["reserve"]
	return s


static func display_of(w: Dictionary) -> String:
	if w.get("upgraded", false) and UPGRADES.has(w["name"]):
		return UPGRADES[w["name"]]["name"]
	return display(w["name"])


# Damage of one bullet / shotgun-cone hit (CItemGun::GetDamage, va 0x238a40):
#   d = damage - damage * pierce * pierced        (targets the bullet already went through)
#   d *= loc[loc]                                  (if the location has a multiplier)
#   d -= (dist - falloff_start) * falloff          (beyond falloff_start)
#   d -= (lateral - lateral_start) * lateral       (shotguns: distance off the aim axis)
#   max(d, min)
static func hit_damage(s: Dictionary, dist: float, pierced := 0, loc := -1, lateral := 0.0) -> float:
	var base := float(s["damage"])
	var d := base - floorf(base * float(s.get("pierce", 0.0))) * pierced
	var locs: Array = s.get("loc", [])
	if loc >= 0 and loc < locs.size():
		d *= float(locs[loc])
	elif loc == LOC_HEAD:
		d *= float(s.get("head", 1.0))
	var start := float(s.get("falloff_start", 0.0))
	if dist > start:
		d -= (dist - start) * float(s.get("falloff", 0.0))
	var lstart := float(s.get("lateral_start", 0.0))
	if absf(lateral) > lstart:
		d -= (absf(lateral) - lstart) * float(s.get("lateral", 0.0))
	return maxf(d, float(s.get("min", 0.0)))


# Hit location of a shot landing at world position p on zombie z (the original picks
# the hit volume: head sphere, arm / chest / pelvis / leg cylinders). Heights are the
# remake zombie's (origin at the feet).
static func location(z: Zombie, p: Vector3, head: bool) -> int:
	if head:
		return LOC_HEAD
	if z is Dog or z.crawler:
		return LOC_CHEST
	var y := z.to_local(p).y
	if y < Zombie.LEG_HIT_HEIGHT:
		return LOC_LEG
	match z.arm_at(p):
		"left":
			return LOC_LEFT_ARM
		"right":
			return LOC_RIGHT_ARM
	return LOC_PELVIS if y < 1.15 else LOC_CHEST


# Aiming down the sights, per gun (CItemGun fields, tools/weapon_stats.py):
#   0xc4  aim FOV in iwangle units (4096 = 360 deg), across the average screen dimension
#         like ViewportFOV (kiwi 0xcb340: AimModeFOV is "0" = use the gun's 0xc4).
#         512 = 45 deg (SMGs), 386 = 33.9 deg (bolt actions), 364 = 32 deg (PTRS)
#   0x94..0xa8  six angles, read here as bullet spread (full cone, iwangle units):
#         [hip max, hip min, 0, hip max (moving?), aimed max, aimed min]. Inferred, not
#         confirmed in the code: zero for the shotguns (their cone replaces it) and the
#         flamethrower, small for the projectile guns (Ray Gun, Mustang & Sally), large
#         for bolt actions from the hip and the PTRS, ~1 deg aimed for every gun.
const AIM := {
	"colt45": [534, [125, 68, 0, 125, 22, 11]],
	"kar98": [386, [159, 147, 0, 159, 0, 11]],
	"arisaka": [386, [159, 147, 0, 159, 0, 11]],
	"springfield": [386, [159, 147, 0, 159, 0, 11]],
	"carbine": [409, [113, 45, 0, 113, 0, 11]],
	"garand": [409, [113, 34, 0, 113, 34, 22]],
	"g43": [409, [113, 45, 0, 113, 0, 11]],
	"thompson": [512, [125, 68, 0, 125, 22, 11]],
	"mp40": [512, [125, 56, 0, 125, 22, 11]],
	"type100": [512, [125, 68, 0, 125, 22, 11]],
	"stg44": [512, [125, 56, 0, 125, 22, 11]],
	"ppsh": [512, [125, 68, 0, 125, 22, 11]],
	"bar": [512, [136, 68, 0, 136, 22, 11]],
	"fg42": [432, [159, 147, 0, 170, 22, 11]],
	"mg42": [512, [147, 91, 0, 147, 22, 11]],
	"browning": [512, [147, 91, 0, 147, 22, 11]],
	"shotgun": [477, [0, 0, 0, 0, 0, 0]],
	"sawnoff": [477, [0, 0, 0, 0, 0, 0]],
	"trenchgun": [477, [0, 0, 0, 0, 0, 0]],
	"ptrs": [364, [193, 182, 0, 193, 22, 11]],
	"flamethrower": [546, [0, 0, 0, 0, 0, 0]],
	"raygun": [534, [45, 34, 0, 45, 11, 11]],
	"wunderwaffe": [534, [45, 34, 0, 45, 11, 11]],
	"magnum": [534, [113, 56, 0, 113, 22, 11]],
}
const AIM_UPGRADED := {"colt45": [534, [45, 34, 0, 45, 11, 11]]}   # colt45_upgrade (Mustang & Sally)


# Aim FOV in degrees (original ViewportFOV units) of a held weapon.
static func aim_fov(w: Dictionary) -> float:
	var a: Array = AIM_UPGRADED.get(w["name"]) if w.get("upgraded", false) and AIM_UPGRADED.has(w["name"]) else AIM.get(w["name"], AIM["colt45"])
	return float(a[0]) * 360.0 / 4096.0


# Bullet spread (full cone, degrees) of a held weapon: heat 0..1 goes from the minimum
# to the maximum (continuous fire), aimed or from the hip.
static func spread(w: Dictionary, aimed: bool, heat: float) -> float:
	var a: Array = AIM_UPGRADED.get(w["name"]) if w.get("upgraded", false) and AIM_UPGRADED.has(w["name"]) else AIM.get(w["name"], AIM["colt45"])
	var v: Array = a[1]
	var lo: float = v[5] if aimed else v[1]
	var hi: float = maxf(v[4], v[5]) if aimed else v[0]
	return lerpf(lo, hi, clampf(heat, 0.0, 1.0)) * 360.0 / 4096.0
