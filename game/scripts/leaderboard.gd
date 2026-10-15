# Local single-player leaderboard (original ig_local_leaderboard / fe_local_leaderboard:
# 5 rows per map, ranks with LS_RANK_FIRST/SECOND/THIRD/REST "st"/"nd"/"rd"/"th",
# "totalnumwavesurvived"). Kept per map in user://leaderboard.cfg (tests:
# user://leaderboard_test.cfg): rounds survived, then points.
class_name Leaderboard
extends RefCounted

const SAVE := "user://leaderboard.cfg"
const SAVE_TEST := "user://leaderboard_test.cfg"
const ROWS := 5


static func path() -> String:
	var a := Achievements.instance
	return SAVE_TEST if a and a.test_mode else SAVE


static func entries(map: String) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(path()) != OK:
		return []
	var v = cfg.get_value("maps", map, [])
	return v if v is Array else []


# Adds a game; returns its rank (1-based) or 0 if it is not in the top rows.
static func add(map: String, rounds: int, points: int, kills: int, headshots: int) -> int:
	var list := entries(map)
	var e := {"rounds": rounds, "points": points, "kills": kills, "headshots": headshots,
		"date": Time.get_date_string_from_system()}
	list.append(e)
	list.sort_custom(func(a, b): return a["rounds"] > b["rounds"] or (a["rounds"] == b["rounds"] and a["points"] > b["points"]))
	var rank := list.find(e) + 1
	list = list.slice(0, ROWS)
	var cfg := ConfigFile.new()
	cfg.load(path())
	cfg.set_value("maps", map, list)
	cfg.save(path())
	return rank if rank <= ROWS else 0


# LS_RANK_*: 1st, 2nd... in English; Italian ordinals are written 1°, 2°... (Lang.rank)
static func rank_text(n: int) -> String:
	return Lang.rank(n)
