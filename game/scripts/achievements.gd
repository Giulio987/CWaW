# Achievements of the original game.
#
# Data: fixed/achievements/{achievements,nacht_,verruckt_,shinonuma_,derriese_}
# achievements.group.bin (console.bin AllAchievementsGroupName), 106
# CAchievementResource dumped by tools/achievements.py to assets/achievements.json:
# id (the name Lua passes to Game.SetAchievement), list number, points, English
# name/description (localisation strings), condition class (Direct, GreaterEqu,
# LessEquGreaterEqu, WeaponExact, ...) with value/category/stat triples (stat names
# of the engine: session_wavereached, totalshotsfire, headlesszombie...) and the maps
# it can be earned on. Lua unlocks the Direct ones (radioSilence, ver_openwide,
# ver_yougotpowah, der_ElevateYourSenses, tutorAssist); the engine keeps the stats
# and checks the rest. The conditions below follow those triples (see _evaluate).
# An achievement of a map group (nacht_achievements...) only counts on that map.
#
# Popup: hud_acheivementFrame + acheivementLabel ("Achievement Unlocked"), shown
# AchievementMsgTimeMS = 5000 ms (console.bin) with AchievementSound "achievement".
# List: frontend "achievements" (CFrontendStateAchievements: overall + per map,
# LS_ACHIEVEMENT_OVERALL_TEXT), locked/unlocked icons from the HUD atlas (padlock,
# red tick). Unlocks and the overall stats persist in user://achievements.cfg
# (tests and debug captures use user://achievements_test.cfg).
#
# Most events are observed (zombie kills/gibs/states, perks, weapons, points of the
# player, rounds, areas, teleporters, traps, grenades); a few game scripts call
# Achievements.unlock()/event() (easter eggs, generator, power-ups, shots, repairs).
class_name Achievements
extends Node

signal unlocked_achievement(entry: Dictionary)

const DATA := "res://assets/achievements.json"
const SAVE := "user://achievements.cfg"
const SAVE_TEST := "user://achievements_test.cfg"
const MSG_TIME := 5.0            # console.bin AchievementMsgTimeMS
const SOUND := "achievement"     # console.bin AchievementSound
const ICON_DONE := Rect2(351, 476, 40, 30)   # HUD atlas (ui_art.gd): red tick
const ICON_LOCKED := Rect2(487, 614, 21, 27) # padlock
const GROUP_MAP := {"nacht_achievements": "nacht", "verruckt_achievements": "verruckt",
	"shinonuma_achievements": "shinonuma", "derriese_achievements": "derriese"}
const GROUP_TITLE := {"achievements": "Generali", "nacht_achievements": "Nacht der Untoten",
	"verruckt_achievements": "Verrückt", "shinonuma_achievements": "Shi No Numa", "derriese_achievements": "Der Riese"}
const FEET_50 := 15.24           # Eagle Eye: maxkilldistance 1524 cm
const TEN_MILES := 16093.44      # Running Man (m)
const SHOTGUNS := ["shotgun", "sawnoff", "trenchgun"]
# need something the remake does not have (co-op, tutorial)
# (magnum 73/78, Bouncing Betty 56, Bowie knife 101: betty.gd, bowie_knife.gd)
const UNAVAILABLE := [8, 15, 35, 36, 37, 38, 55, 74]

# Name / description of an entry in the current language: Italian from IT below, English the
# original's (lang.gd).
static func title_of(e: Dictionary) -> String:
	return String(e["en_name"] if Lang.is_en() else e["it_name"])


static func desc_of(e: Dictionary) -> String:
	return String(e["en_desc"] if Lang.is_en() else e["it_desc"])


# Italian names and descriptions, by list number
const IT := {
	1: ["Silenzio radio?", "Colpisci la radio in Nacht der Untoten"],
	2: ["Il mio cuore in fiamme", "Ottieni il lanciafiamme"],
	3: ["Sa di pollo", "Arrostisci 4 zombie contemporaneamente"],
	4: ["Io, piromane", "Infliggi 50.000 punti di danno con il lanciafiamme"],
	5: ["Uscita di scena", "Muori con la tua granata portando con te 3 zombie"],
	6: ["Accaparratore", "Raggiungi e completa il round 5 usando solo 120 colpi"],
	7: ["Pistole all'alba", "Completa i primi 2 round usando solo la pistola e il coltello"],
	8: ["Du bist Wunderschön!", "Completa il tutorial senza che Richtofen spari a nessuno zombie per te"],
	9: ["Schnell, Schnell!", "Completa il round 1 in meno di 60 secondi"],
	10: ["Collezionista di teschi", "Raccogli 10 Uccisioni istantanee"],
	11: ["Decapitazione", "Fai esplodere 2 teste di zombie contemporaneamente"],
	12: ["Appena sfornata", "Uccidi 3 zombie con una granata tenuta in mano per almeno 2 secondi, senza morire"],
	13: ["Castità", "Accumula 2.000 punti riparando barricate"],
	14: ["Niente barriere, niente paura", "Raggiungi il round 6 senza riparare barricate"],
	15: ["Insieme, fratello mio!", "Unisciti a un amico in una partita cooperativa"],
	16: ["L'ora delle streghe", "Gioca durante l'ora delle streghe (da mezzanotte all'una)"],
	18: ["Esperto di munizioni I", "Spara 1.000 colpi (in totale)"],
	19: ["Esperto di munizioni II", "Spara 4.000 colpi (in totale)"],
	20: ["Esperto di munizioni III", "Spara 10.000 colpi (in totale)"],
	21: ["Il tritacarne I", "Smembra 50 nemici"],
	22: ["Il tritacarne II", "Smembra 200 nemici"],
	23: ["Il tritacarne III", "Smembra 400 nemici"],
	24: ["Teste che saltano I", "Fai saltare 25 teste di zombie"],
	25: ["Teste che saltano II", "Fai saltare 100 teste di zombie"],
	26: ["Teste che saltano III", "Fai saltare 250 teste di zombie"],
	27: ["Senza braccia...", "Stacca entrambe le braccia a 25 zombie"],
	28: ["...senza gambe", "Stacca le gambe a 35 zombie"],
	29: ["Occhio di falco", "Uccidi uno zombie da 15 metri (50 piedi) di distanza"],
	30: ["L'uomo che corre", "Percorri 16 km (10 miglia)"],
	31: ["Fammi saltare in aria", "Uccidi 20 zombie con i barili esplosivi"],
	32: ["Via dal mio prato!", "Sopravvivi a 2 round senza far entrare nemmeno uno zombie nell'edificio in Nacht der Untoten"],
	33: ["Lollercausto nucleare", "Raccogli 10 bombe atomiche"],
	34: ["Raddoppio", "Raccogli 10 Punti doppi"],
	35: ["Batti cinque, fratello!", "Accoltella in faccia il tuo compagno in cooperativa"],
	36: ["Prendi la mia mano", "Rianima un compagno a terra in cooperativa"],
	37: ["Il buon samaritano", "Rianima alleati a terra 10 volte"],
	38: ["Il boia sdraiato", "Uccidi 5 zombie mentre sei a terra in cooperativa"],
	39: ["Duro a morire", "Non subire danni per 5 round"],
	40: ["Questo è il mio bastone tonante!", "Sopravvivi a 5 round usando i fucili a pompa"],
	41: ["Mi piacciono queste probabilità", "Usa la scatola misteriosa 20 volte"],
	42: ["Uomo dello spazio!", "Ottieni la Ray Gun dalla scatola misteriosa"],
	43: ["Faccia laser", "Uccidi 100 zombie con la Ray Gun"],
	44: ["Investimenti eterni", "Spendi 50.000 punti (in totale)"],
	45: ["OK, credo di potercela fare...", "Raggiungi il round 5"],
	46: ["Ce la posso fare!", "Raggiungi il round 12"],
	47: ["Tostissimo", "Raggiungi il round 20"],
	48: ["Apra bene la bocca...", "Attiva la poltrona del dentista"],
	49: ["Iperattivo", "Bevi 10 Quick Revive"],
	50: ["Biglietti per lo show dei muscoli", "Bevi 10 Juggernog"],
	51: ["Quando posso fare il bis", "Bevi 10 Double Tap Root Beer"],
	52: ["Lesto di mano", "Bevi 10 Speed Cola"],
	53: ["Elettroshock", "Uccidi 50 zombie con le barriere elettriche"],
	54: ["Hai la corrente!", "Attiva il generatore"],
	55: ["Mani miracolose", "Rianima un compagno in cooperativa usando il Quick Revive"],
	56: ["Questa è per te, Betty!", "Uccidi 2 zombie insieme con una sola Bouncing Betty"],
	57: ["Sono carico, baby!", "Possiedi tutti i Perk-a-Cola contemporaneamente"],
	58: ["Das Ist Mein Haus", "Apri tutte le zone del manicomio"],
	59: ["Passatemi una camicia di forza", "Raggiungi il round 5 in Verrückt"],
	60: ["Rinchiudetemi...", "Raggiungi il round 12 in Verrückt"],
	61: ["...e buttate la chiave", "Raggiungi il round 20 in Verrückt"],
	62: ["E resta giù!", "Uccidi uno zombie mentre esce dal terreno"],
	63: ["La mia psichiatria", "Sopravvivi a 5 round usando solo il lanciafiamme in Verrückt"],
	64: ["Assaggia la mia lama", "Uccidi 15 zombie di fila solo con il coltello senza morire"],
	65: ["Credo di aver bisogno di aiuto", "Uccidi 30 zombie di fila solo con il coltello senza morire"],
	66: ["L'acciaio più freddo", "Uccidi 100 zombie con il coltello (in totale)"],
	68: ["Un colpo, quattro teste", "Fai a pezzi i senza cervello col tuo fucile a pompa (uccidi 4 zombie con un colpo)"],
	69: ["Linea morta", "Attiva il telefono"],
	70: ["Sciogli-facce", "Fulmina 8 zombie con un solo colpo della Wunderwaffe"],
	71: ["Arma di distruzione minima", "Uccidi un solo zombie con una bomba atomica"],
	72: ["Pezzo grosso", "Guadagna 20.000 punti in una sola partita"],
	73: ["Gran picchiatore", "Uccidi 30 zombie di fila solo con la magnum"],
	74: ["Sulla zucca", "Uccidi uno zombie con una granata rimbalzata su un compagno"],
	75: ["È una trappola!", "Uccidi almeno 1 zombie con il flagellatore e 1 con una barriera elettrica"],
	76: ["Il concimatore", "Uccidi 200 zombie in Shi No Numa"],
	77: ["Teste morte", "Uccidi 150 zombie con colpi alla testa in Shi No Numa"],
	78: ["Hong Kong Akimbo", "Possiedi entrambe le pistole contemporaneamente"],
	79: ["Bleah, le mie scarpe sono rovinate!", "Apri tutte le zone di Shi No Numa"],
	80: ["Inzuppato", "Raggiungi il round 5 in Shi No Numa"],
	81: ["Impantanato", "Raggiungi il round 12 in Shi No Numa"],
	82: ["Completamente sommerso", "Raggiungi il round 20 in Shi No Numa"],
	83: ["E resta sott'acqua!", "Uccidi uno zombie mentre emerge dalla palude"],
	84: ["Unico sopravvissuto", "Raggiungi il round 15 in Shi No Numa senza mai finire a terra"],
	85: ["Flagellatore", "Uccidi 10 zombie in un solo giro del flagellatore"],
	86: ["Fai il morto, bello!", "Uccidi 50 cani infernali"],
	87: ["Impiccato, sventrato...", "Stacca le braccia a uno zombie e poi fagli saltare le gambe"],
	88: ["...e squartato", "Stacca le braccia a uno zombie, fagli saltare le gambe e poi la testa"],
	89: ["Eleva i tuoi sensi", "Attiva l'acchiappamosche"],
	90: ["Scassinatore", "Apri tutte le porte di Der Riese (in una partita)"],
	91: ["Der Elektriker", "Collega tutti i teletrasporti prima del round 7"],
	92: ["Viaggiatore abituale", "Usa il teletrasporto 8 volte (in una partita)"],
	93: ["Pack-dipendente", "Potenzia 5 armi con il Pack-a-Punch (in una partita)"],
	94: ["La poesia della bistecca", "Uccidi 10 zombie con il teletrasporto"],
	95: ["Mein Shiny", "Potenzia un'arma"],
	96: ["Il tocco di Gott", "Possiedi 2 armi potenziate con il Pack-a-Punch contemporaneamente"],
	97: ["A testa alta", "Raggiungi il round 10 in Der Riese"],
	98: ["Contro Golia", "Raggiungi il round 20 in Der Riese"],
	99: ["Sulle spalle dei giganti", "Raggiungi il round 30 in Der Riese"],
	100: ["Il Wurst dei casi", "Uccidi 500 zombie in Der Riese"],
	101: ["40 coltelli", "Uccidi 40 zombie con il coltello Bowie (in una partita)"],
	102: ["La potenza della scimmia", "Usa la bomba scimmia"],
	103: ["Perkolisti anonimi", "Sopravvivi fino al round 20 senza comprare nessun Perk-a-Cola"],
	104: ["Armi da waffle", "Possiedi Ray Gun, Wunderwaffe DG-2 e bomba scimmia contemporaneamente"],
	105: ["Ora degli attrezzi", "Usa il martello del carpentiere 5 volte (in totale)"],
	106: ["Giustizia scimmiesca", "Uccidi 20 zombie o cani con le bombe scimmia"],
	107: ["E resta... su?", "Uccidi uno zombie mentre si arrampica"],
	108: ["Wunderkind", "Completa tutti gli easter egg e usa tutte le armi meravigliose (in partita)"],
}
# perk kind (perks.gd) -> drink stat of the original
const DRINK_STAT := {"revive": "revivesoda", "jugga": "juggernog", "dbtap": "doubletaprootbeer", "speed": "speedcola"}

static var instance: Achievements

var entries: Array = []          # achievements.json order (list number)
var by_num := {}
var by_id := {}
var unlocked := {}               # id -> unix time
var stats := {}                  # overall stats "category.stat" -> number (saved)
var session := {}                # stats of the current game
var game: Game
var test_mode := false

var _path := SAVE
var _dirty := false
var _save_t := 0.0
var _check := false
var _queue: Array = []           # entries waiting for the popup
var _popup: Control
var _popup_t := 0.0
var _layer: CanvasLayer
# per game observation
var _last_points := 0
var _last_pos := Vector3.INF
var _last_round := 0
var _between := true
var _round_start_ms := 0
var _hit_this_round := false
var _since_hit := 0.0
var _zombie_inside := false
var _weapon_seen := {}          # inventory last frame: "name" or "name+" (upgraded) -> true
var _perks_seen := []
var _revive_grace := false
var _box_uses := {}
var _tele_used := 0
var _heads_frame := 0
var _shotgun_kills := {}        # physics frame -> kills with a shotgun
var _flogger_bout := {}         # trap -> kills since it was armed
var _hour_t := 0.0


static func unlock(id: String) -> void:
	if instance:
		instance._unlock_id(id)


# generic stat bump from game scripts: Achievements.event("global.repairpoints", 10)
static func event(key: String, amount := 1.0) -> void:
	if instance:
		instance._add(key, amount)


func _init() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	# tests and debug captures (--shots, --view, --walk, --look...) keep their own save
	test_mode = args.has("--autotest") or Array(args).any(func(a: String): return a.ends_with("-test") or a.ends_with("-look") \
			or a in ["--shots", "--view", "--walk", "--look", "--orient-probe", "--perk-reach", "--probe", "--menu-shot"])
	_path = SAVE_TEST if test_mode else SAVE
	_load_data()
	if args.has("--achievement-test"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST))
	load_progress()


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_layer = CanvasLayer.new()
	_layer.layer = 60
	add_child(_layer)


func _exit_tree() -> void:
	save()
	if instance == self:
		instance = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


func _load_data() -> void:
	if not FileAccess.file_exists(DATA):
		push_warning("achievements: %s missing (tools/achievements.py)" % DATA)
		return
	entries = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for e in entries:
		var n := int(e["num"])
		e["num"] = n
		e["points"] = int(e["points"])
		e["map"] = GROUP_MAP.get(e["group"], "")
		e["it_name"] = IT.get(n, [e["name"], e["desc"]])[0]
		e["it_desc"] = IT.get(n, [e["name"], e["desc"]])[1]
		e["en_name"] = String(e["name"])   # the original English name/description (achievements.json)
		e["en_desc"] = String(e["desc"])
		e["available"] = not n in UNAVAILABLE
		by_num[n] = e
		by_id[String(e["id"]).to_lower()] = e


func load_progress() -> void:
	unlocked = {}
	stats = {}
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		return
	for k in cfg.get_section_keys("unlocked") if cfg.has_section("unlocked") else []:
		unlocked[k] = cfg.get_value("unlocked", k)
	for k in cfg.get_section_keys("stats") if cfg.has_section("stats") else []:
		stats[k] = cfg.get_value("stats", k)


func save() -> void:
	if not _dirty:
		return
	_dirty = false
	var cfg := ConfigFile.new()
	for k in unlocked:
		cfg.set_value("unlocked", k, unlocked[k])
	for k in stats:
		cfg.set_value("stats", k, stats[k])
	cfg.save(_path)


func is_unlocked(num: int) -> bool:
	return by_num.has(num) and unlocked.has(String(by_num[num]["id"]))


func total_points() -> Array:
	var got := 0
	var all := 0
	for e in entries:
		all += e["points"]
		if unlocked.has(String(e["id"])):
			got += e["points"]
	return [got, all]


# ------------------------------------------------------------------ unlocking

func _map() -> String:
	return game.level_name if game and is_instance_valid(game) else ""


# the map group (or the "maps" list of the global ones) limits where it counts
func _allowed(e: Dictionary) -> bool:
	if e["map"] != "" and e["map"] != _map():
		return false
	var maps: Array = e.get("maps", [])
	return maps.is_empty() or _map() in maps


func _unlock_id(id: String) -> void:
	var e: Dictionary = by_id.get(id.to_lower(), {})
	if not e.is_empty():
		_unlock(e["num"])


func _unlock(num: int) -> void:
	var e: Dictionary = by_num.get(num, {})
	if e.is_empty() or unlocked.has(String(e["id"])) or not _allowed(e) or Game.no_achievements():
		return
	unlocked[String(e["id"])] = int(Time.get_unix_time_from_system())
	_dirty = true
	save()
	print("[achievement] %d %s (%s)" % [num, e["id"], e["name"]])
	_queue.append(e)
	unlocked_achievement.emit(e)


func _c(num: int, cond: bool) -> void:
	if cond:
		_unlock(num)


func _add(key: String, amount := 1.0, overall := true) -> void:
	if overall and not Game.no_achievements():   # debug start (round 5, Ray Gun) and Recruit count nothing
		stats[key] = stats.get(key, 0) + amount
		_dirty = true
	session[key] = session.get(key, 0) + amount
	_check = true


func _set_max(key: String, v: float) -> void:
	if v > session.get(key, 0.0):
		session[key] = v
		_check = true


func _o(key: String) -> float:
	return stats.get(key, 0)


func _s(key: String) -> float:
	return session.get(key, 0)


# Conditions as in the original resources (value, category.stat, comparison).
func _evaluate() -> void:
	var m := _map()
	var wave := _s("session_wavereached")
	var used: Dictionary = session.get("weapons_used", {})
	_c(2, _o("flamethrower.purchased") >= 1)
	_c(3, _s("global.burningsimu") >= 4)
	_c(4, _o("flamethrower.totaldamage") >= 50000)
	_c(5, _s("grenade.suicidekills") >= 3)
	_c(6, wave >= 6 and _s("session_shotsfire") <= 120)
	_c(7, wave >= 3 and used.keys().all(func(w): return w in ["colt45", "knife"]))
	_c(9, _s("wave1_time_ms") > 0 and _s("wave1_time_ms") <= 60000)
	_c(10, _o("global.instakill") >= 10)
	_c(11, _s("global.zombieheadoffsimu") >= 2)
	_c(12, _s("grenade.cookedkills") >= 3)
	_c(13, _o("global.repairpoints") >= 2000)
	_c(14, wave >= 6 and _s("session_repairbarricade") <= 0)
	_c(16, _s("global.currenthour_zero") >= 1)
	_c(18, _o("global.totalshotsfire") >= 1000)
	_c(19, _o("global.totalshotsfire") >= 4000)
	_c(20, _o("global.totalshotsfire") >= 10000)
	_c(21, _o("global.gibs") >= 50)
	_c(22, _o("global.gibs") >= 200)
	_c(23, _o("global.gibs") >= 400)
	_c(24, _o("global.headlesszombie") >= 25)
	_c(25, _o("global.headlesszombie") >= 100)
	_c(26, _o("global.headlesszombie") >= 250)
	_c(27, _o("global.armlesszombie") >= 25)
	_c(28, _o("global.leglesszombie") >= 35)
	_c(29, _s("global.maxkilldistance") >= FEET_50)
	_c(30, _o("global.distancecovered") >= TEN_MILES)
	_c(31, _o("nacht.totalzombiebarrelkill") >= 20)   # Blow Me Away (barrels.gd)
	_c(32, _s("session_wavenozombieinside") >= 2)
	_c(33, _o("global.nuke") >= 10)
	_c(34, _o("global.doublePoints") >= 10)
	_c(39, _s("session_wavenodamage") >= 6)
	_c(40, wave >= 6 and used.keys().all(func(w): return w in SHOTGUNS + ["knife", "grenade"]))
	_c(41, _o("global.nummagicboxused") >= 20)
	_c(42, _o("raygun.purchased") >= 1)
	_c(43, _o("raygun.totalzombiekilled") >= 100)
	_c(44, _o("global.totalscorespent") >= 50000)
	for pair in [[45, 5], [46, 12], [47, 20], [59, 5], [60, 12], [61, 20], [80, 5], [81, 12], [82, 20],
			[97, 10], [98, 20], [99, 30]]:
		_c(pair[0], wave >= pair[1])
	_c(49, _o("global.revivesoda") >= 10)
	_c(50, _o("global.juggernog") >= 10)
	_c(51, _o("global.doubletaprootbeer") >= 10)
	_c(52, _o("global.speedcola") >= 10)
	_c(53, _o("verruckt.totalzombieelectroBarrierKill") >= 50)
	_c(57, _s("verruckt.totalallperksatonce") >= 1)
	_c(58, m == "verruckt" and _s("session_totalnumallareaopen") >= 1)
	_c(62, _o("verruckt.totalzombiekilledground") >= 1)
	_c(63, wave >= 6 and used.keys().all(func(w): return w in ["flamethrower", "knife", "grenade"]))
	_c(64, _s("knife.killsinarow") >= 15)
	_c(65, _s("knife.killsinarow") >= 30)
	_c(66, _o("knife.totalzombiekilled") >= 100)
	_c(68, _s("global.zombiescatteredkillssimu") >= 4)
	_c(70, _s("wunderwaffe.zombieskillssimu") >= 8)   # Face Melter: set by wunderwaffe.gd at the end of a shot
	_c(71, _s("nuke.onekill") >= 1)
	_c(72, _s("session_scoreacquired") >= 20000)
	_c(75, _s("shinonuma.floggerkills") >= 1 and _s("shinonuma.electrokills") >= 1)
	_c(76, _o("shinonuma.totalzombiekilled") >= 200)
	_c(77, _o("shinonuma.headlesszombie") >= 150)
	_c(79, m == "shinonuma" and _s("session_totalnumallareaopen") >= 1)
	_c(83, _o("shinonuma.totalzombiekilledground") >= 1)
	_c(84, wave >= 15 and _s("session_laststandcount") <= 0)
	_c(85, _s("shinonuma.floggerbout") >= 10)
	_c(86, _o("global.totaldogkilled") >= 50)
	_c(87, _o("global.armlessthenlegless") >= 1)
	_c(88, _o("global.armlessthenleglessthenheadless") >= 1)
	_c(90, m == "derriese" and _s("session_totalnumallareaopen") >= 1)
	_c(91, wave <= 6 and _s("session_teleporterslinked") >= 3)
	_c(92, _s("session_teleportertimesused") >= 8)
	_c(93, _s("session_packapunchused") >= 5)
	# The Poetry of Steak: derriese.totalzombieteleKill >= 10 (pads' CSplashEffectSpec stat "teleKill", teleporter.gd)
	_c(94, _o("derriese.totalzombieteleKill") >= 10)
	_c(95, _s("session_packapunchused") >= 1)
	_c(96, _s("upgradedatonce") >= 2)
	_c(100, _o("derriese.totalzombiekilled") >= 500)
	_c(103, wave >= 20 and _s("session_perksused") <= 0)
	_c(105, _o("global.carpenter") >= 5)
	_c(106, _o("monkeybomb.totalzombiekilled") + _o("monkeybomb.totaldogkilled") >= 20)
	_c(107, _o("derriese.totalzombiekilledclimbing") >= 1)
	# Big Brawler: WeaponKillInARow 30, weapon "magnum"; Hong Kong Akimbo: InventoryWeapon
	# colt45 + magnum; 40 Knives: bowieKnife.session_totalzombiekilled >= 40 (Der Riese)
	_c(73, _s("magnum.killsinarow") >= 30)
	if game and is_instance_valid(game) and game.player:
		var held: Array = game.player.weapons.map(func(w): return String(w["name"]))
		_c(78, "colt45" in held and "magnum" in held)
	_c(101, _s("bowieKnife.session_totalzombiekilled") >= 40)
	# Wunderkind (CAchievementWunder, any map): raygun, wunderwaffe and monkeybomb "purchased"
	# (overall stats: box, wall, grave) and the four easter eggs 89, 48, 69, 1 unlocked
	_c(108, _o("raygun.purchased") >= 1 and _o("wunderwaffe.purchased") >= 1 and _o("monkeybomb.purchased") >= 1
		and [89, 48, 69, 1].all(func(k): return is_unlocked(k)))


# progress of the counted ones, for the list: [current, target] or []
func progress(num: int) -> Array:
	var t := {18: ["global.totalshotsfire", 1000], 19: ["global.totalshotsfire", 4000], 20: ["global.totalshotsfire", 10000],
		21: ["global.gibs", 50], 22: ["global.gibs", 200], 23: ["global.gibs", 400],
		24: ["global.headlesszombie", 25], 25: ["global.headlesszombie", 100], 26: ["global.headlesszombie", 250],
		27: ["global.armlesszombie", 25], 28: ["global.leglesszombie", 35], 33: ["global.nuke", 10],
		34: ["global.doublePoints", 10], 10: ["global.instakill", 10], 13: ["global.repairpoints", 2000],
		41: ["global.nummagicboxused", 20], 43: ["raygun.totalzombiekilled", 100], 44: ["global.totalscorespent", 50000],
		4: ["flamethrower.totaldamage", 50000], 49: ["global.revivesoda", 10], 50: ["global.juggernog", 10],
		51: ["global.doubletaprootbeer", 10], 52: ["global.speedcola", 10], 53: ["verruckt.totalzombieelectroBarrierKill", 50],
		66: ["knife.totalzombiekilled", 100], 76: ["shinonuma.totalzombiekilled", 200], 77: ["shinonuma.headlesszombie", 150],
		86: ["global.totaldogkilled", 50], 100: ["derriese.totalzombiekilled", 500], 94: ["derriese.totalzombieteleKill", 10], 105: ["global.carpenter", 5],
		30: ["global.distancecovered", TEN_MILES], 31: ["nacht.totalzombiebarrelkill", 20]}
	if num == 106:
		return [_o("monkeybomb.totalzombiekilled") + _o("monkeybomb.totaldogkilled"), 20]
	if not t.has(num):
		return []
	return [_o(t[num][0]), t[num][1]]


# ------------------------------------------------------------------ observation

func _on_node_added(n: Node) -> void:
	if n is Game:
		_begin_game(n)
	elif n is Zombie:
		(n as Zombie).killed.connect(_on_killed)
	elif n is Grenade:
		var g := n as Grenade
		g.add_to_group("ach_blasts")
		_weapon_used("grenade")
		g.set_meta("ach_cooked", Grenade.FUSE - g.fuse)   # spawn() sets the fuse left before adding it
		g.tree_exiting.connect(_on_grenade_gone.bind(g))
	elif n is MonkeyBomb:
		n.add_to_group("ach_blasts")
		_weapon_used("monkeybomb")
		unlock("mightOfTheMonkey")
		n.tree_exiting.connect(_on_monkey_gone.bind(n))


func _begin_game(g: Game) -> void:
	game = g
	session = {"weapons_used": {}}
	_last_points = -1
	_last_pos = Vector3.INF
	_last_round = 0
	_between = true
	_hit_this_round = false
	_since_hit = 0.0
	_zombie_inside = false
	_weapon_seen = {}
	_perks_seen = []
	_revive_grace = false
	_box_uses = {}
	_tele_used = 0
	_flogger_bout = {}
	_hour_t = 0.0
	g.tree_exiting.connect(func():
		save()
		if game == g:
			game = null)


func _weapon_used(w: String) -> void:
	var u: Dictionary = session.get("weapons_used", {})
	u[w] = true
	session["weapons_used"] = u
	_check = true


# shots fired (player.gd _fire): rounds of ammunition
func shot(weapon_name: String) -> void:
	_add("global.totalshotsfire")
	_add("session_shotsfire", 1, false)
	_weapon_used(weapon_name)


static func fired(weapon_name: String) -> void:
	if instance:
		instance.shot(weapon_name)


func _cause(z: Zombie, knife: bool) -> String:
	if knife:
		return "knife"
	if game and game.suppress_kill_points:
		return "trap"
	if game and game.get("_nuking"):
		return "nuke"
	for b in get_tree().get_nodes_in_group("ach_blasts"):
		if is_instance_valid(b) and b.get("_exploded"):
			return "monkeybomb" if b is MonkeyBomb else ("betty" if b is Betty else "grenade")
	if z.get_node_or_null("Burning") != null:
		return "flamethrower"
	if game and game.player and not game.player.weapons.is_empty():
		return String(game.player.weapon()["name"])
	return ""


func _on_killed(z: Zombie, headshot: bool, knife: bool) -> void:
	if game == null or not is_instance_valid(game) or z.get_parent() != game:
		return
	var m := _map()
	var cause := _cause(z, knife)
	var prev: int = z.get_meta("ach_state", Zombie.State.CHASE)
	if z is Dog:
		_add("global.totaldogkilled")
		if cause == "monkeybomb":
			pass   # counted from the bomb's result
	else:
		_add("global.totalzombiekilled")
		_add(m + ".totalzombiekilled")
		if cause in ["raygun", "knife", "flamethrower"]:
			_add(cause + ".totalzombiekilled")
		if prev == Zombie.State.RISING:
			_add(m + ".totalzombiekilledground")
		if prev == Zombie.State.CLIMBING:
			_add(m + ".totalzombiekilledclimbing")
	if cause == "trap":
		_trap_kill(z)
	# knife streak (Feel My Blade): any other kill by the player breaks it
	if cause == "knife":
		_add("knife.killsinarow", 1, false)
		if BowieKnife.damage_of(game.player) > 0.0:
			_add("bowieKnife.session_totalzombiekilled", 1, false)
	elif cause != "trap" and cause != "nuke":
		session["knife.killsinarow"] = 0
	# magnum streak (Big Brawler): any other kill by the player breaks it
	if cause == "magnum":
		_add("magnum.killsinarow", 1, false)
	elif cause != "trap" and cause != "nuke":
		session["magnum.killsinarow"] = 0
	if cause in SHOTGUNS:
		var f := Engine.get_physics_frames()
		_shotgun_kills = {f: _shotgun_kills.get(f, 0) + 1}
		_set_max("global.zombiescatteredkillssimu", _shotgun_kills[f])
	if game.player and cause != "trap" and cause != "nuke":
		var d := Vector2(z.global_position.x - game.player.global_position.x, z.global_position.z - game.player.global_position.z).length()
		_set_max("global.maxkilldistance", d)
	_check = true


func _trap_kill(z: Zombie) -> void:
	if game.level == null:
		return
	for t in game.level.traps:
		if t.armed and t.contains(z.global_position + Vector3.UP * 0.5):
			if t.kind == "flogger":
				_add("shinonuma.floggerkills", 1, false)
				_flogger_bout[t] = _flogger_bout.get(t, 0) + 1
				_set_max("shinonuma.floggerbout", _flogger_bout[t])
			else:
				_add(_map() + ".totalzombieelectroBarrierKill")
				_add("shinonuma.electrokills", 1, false)
			return


func _on_grenade_gone(g: Grenade) -> void:
	var res: Dictionary = Grenade.last_result   # set by explode() just before queue_free
	if not g._exploded or res.is_empty() or g.by == null or not is_instance_valid(g.by):
		return
	var kills := int(res.get("killed", 0))
	if g.by.dead and float(res.get("player", 0.0)) > 0.0:
		_set_max("grenade.suicidekills", kills)
	elif float(g.get_meta("ach_cooked", 0.0)) >= 2.0:
		_set_max("grenade.cookedkills", kills)


func _on_monkey_gone(b: MonkeyBomb) -> void:
	if b._exploded:
		_add("monkeybomb.totalzombiekilled", int(MonkeyBomb.last_result.get("killed", 0)))


# power-ups (game.gd apply_powerup)
static func powerup(kind: String) -> void:
	if instance == null:
		return
	var key: String = {"instakill": "global.instakill", "doublepoints": "global.doublePoints", "nuke": "global.nuke",
		"carpenter": "global.carpenter"}.get(kind, "")
	if key != "":
		instance._add(key)
	if kind == "nuke" and instance.game:
		var alive := instance.game.get_children().filter(func(n): return n is Zombie and not n is Dog and n.state != Zombie.State.DEAD)
		if alive.size() == 1:
			instance._add("nuke.onekill", 1, false)


# player points (player.gd add_points)
static func points(n: int) -> void:
	if instance == null:
		return
	if n > 0:
		instance._add("global.totalscoreacquired", n)
		instance._add("session_scoreacquired", n, false)
	elif n < 0:
		instance._add("global.totalscorespent", -n)
		instance._add("session_scorespent", -n, false)


# barricade board repaired by the player (player.gd interact)
static func repaired(points_: int) -> void:
	if instance:
		instance._add("global.repairpoints", points_)
		instance._add("session_repairbarricade", 1, false)


func _process(delta: float) -> void:
	_update_popup(delta)
	if game and is_instance_valid(game) and not get_tree().paused:
		_observe(delta)
	if _check:
		_check = false
		if game and is_instance_valid(game):
			_evaluate()
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 5.0
		save()


func _observe(delta: float) -> void:
	var p := game.player
	if p == null or not is_instance_valid(p):
		return
	# Witching Hour: currenthour == 0
	_hour_t -= delta
	if _hour_t <= 0.0:
		_hour_t = 30.0
		if Time.get_datetime_dict_from_system()["hour"] == 0:
			_add("global.currenthour_zero", 1, false)
	# distance covered (horizontal, on the ground; teleports/ziplines excluded)
	if not p.dead:
		var pos := p.global_position
		if _last_pos != Vector3.INF and p.is_on_floor():
			var d := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
			if d < 1.0:
				stats["global.distancecovered"] = _o("global.distancecovered") + d
				_dirty = true
				if int(_o("global.distancecovered")) % 100 == 0:
					_check = true
		_last_pos = pos
	# damage taken / last stand (Quick Revive)
	var since: float = p.get("_since_hit")
	if since < _since_hit:
		_hit_this_round = true
	_since_hit = since
	var grace: bool = float(p.get("_revive_grace")) > 0.0
	if grace and not _revive_grace:
		_add("session_laststandcount", 1, false)
	_revive_grace = grace
	if p.dead:
		session["knife.killsinarow"] = 0
	# rounds
	var r := game.round_number
	if r != _last_round:
		_last_round = r
		_round_start_ms = Time.get_ticks_msec()
		session["session_wavereached"] = r
		# session_wavenodamage: 1 + rounds in a row without being hit
		session["session_wavenodamage"] = (_s("session_wavenodamage") + 1) if (r > 1 and not _hit_this_round) else 1
		_hit_this_round = false
		_zombie_inside = false
		_check = true
	var between: bool = game.get("_between_rounds")
	if between and not _between and r > 0:
		if r == 1 and not game.dog_round:
			session["wave1_time_ms"] = Time.get_ticks_msec() - _round_start_ms
		if not _zombie_inside and not game.dog_round:
			_add("session_wavenozombieinside", 1, false)
		_check = true
	_between = between
	_observe_zombies()
	_observe_player(p)
	_observe_level()


func _observe_zombies() -> void:
	var heads := 0
	var burning := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z is Zombie or z is Dog or z.get_parent() != game:
			continue
		if z.state != Zombie.State.DEAD:
			var prev: int = z.get_meta("ach_state", -1)
			if prev == Zombie.State.CLIMBING and z.state == Zombie.State.CHASE:
				_zombie_inside = true
			z.set_meta("ach_state", z.state)
			var b := z.get_node_or_null("Burning")
			if b and b.is_processing():
				burning += 1
		# dismemberment, in the order it happens
		var g: Dictionary = z.get_meta("ach_gibs", {})
		var arms: int = (z.get("_arms_lost") as Dictionary).size()
		var legs: bool = z.crawler
		var neck = g.get("neck_node")
		if neck == null and z.get("_model") != null:
			neck = z.call("_part", "neck")
			g["neck_node"] = neck if neck else false
		var head_off: bool = neck is MeshInstance3D and is_instance_valid(neck) and not (neck as MeshInstance3D).visible
		if arms > g.get("arms", 0) or (legs and not g.get("legs", false)) or (head_off and not g.get("head", false)):
			if not g.get("gibbed", false):
				g["gibbed"] = true
				_add("global.gibs")
			if arms >= 2 and g.get("arms", 0) < 2:
				_add("global.armlesszombie")
			if legs and not g.get("legs", false):
				_add("global.leglesszombie")
				if g.get("arms", 0) >= 2 or arms >= 2:
					g["armless_first"] = true
					_add("global.armlessthenlegless")
			if head_off and not g.get("head", false):
				heads += 1
				_add("global.headlesszombie")
				_add(_map() + ".headlesszombie")
				if g.get("armless_first", false) and g.get("legs", false):
					_add("global.armlessthenleglessthenheadless")
			g["arms"] = arms
			g["legs"] = legs
			g["head"] = head_off
			z.set_meta("ach_gibs", g)
		elif g.is_empty():
			z.set_meta("ach_gibs", g)
	if heads > 0:
		_set_max("global.zombieheadoffsimu", heads)
	if burning > 0:
		_set_max("global.burningsimu", burning)


func _observe_player(p: Player) -> void:
	# points (acquired / spent) are reported by add_points; weapons and perks are seen here
	# a weapon name new in the inventory was bought/received; "name+" appearing = Pack-a-Punch
	var upgraded := 0
	var now := {}
	for w in p.weapons:
		var up: bool = w.get("upgraded", false)
		var key := String(w["name"]) + ("+" if up else "")
		now[key] = true
		if not _weapon_seen.has(key):
			if up:
				_add("session_packapunchused", 1, false)
			elif not _weapon_seen.has(key + "+"):
				_add(String(w["name"]) + ".purchased")
		if up:
			upgraded += 1
	_weapon_seen = now
	_set_max("upgradedatonce", upgraded)
	# Acquire Waffle Weapons (Direct, Der Riese): Ray Gun, Wunderwaffe and Monkey Bombs held together
	if now.has("raygun") or now.has("raygun+"):
		if (now.has("wunderwaffe") or now.has("wunderwaffe+")) and MonkeyBelt.of(p) and MonkeyBelt.of(p).count > 0:
			_unlock_id("acquireWaffleWeapons")
	for k in p.perks:
		if not k in _perks_seen:
			_add("session_perksused", 1, false)
			if DRINK_STAT.has(k):
				_add("global." + DRINK_STAT[k])
	_perks_seen = p.perks.duplicate()
	if _map() == "verruckt" and p.perks.size() >= 4:
		_set_max("verruckt.totalallperksatonce", 1)


func _observe_level() -> void:
	var lv := game.level
	if lv == null:
		return
	for b in lv.boxes:
		if not is_instance_valid(b):
			continue
		var u: int = b.uses
		if _box_uses.has(b) and u > _box_uses[b]:
			_add("global.nummagicboxused", u - _box_uses[b])
		_box_uses[b] = u
	if lv.teleporters:
		var t := lv.teleporters
		if t.teleports > _tele_used:
			_add("session_teleportertimesused", t.teleports - _tele_used, false)
			_tele_used = t.teleports
		_set_max("session_teleporterslinked", t.linked_count())
	for t in lv.traps:
		if not t.armed and _flogger_bout.has(t):
			_flogger_bout.erase(t)
	var areas: Dictionary = game.get("_areas")
	if not areas.is_empty() and areas.keys().all(func(a): return a in game.open_areas):
		_set_max("session_totalnumallareaopen", 1)


# ------------------------------------------------------------------ popup

func _update_popup(delta: float) -> void:
	if _popup:
		_popup_t += delta
		var k := 1.0
		if _popup_t < 0.35:
			k = _popup_t / 0.35
		elif _popup_t > MSG_TIME - 0.5:
			k = clampf((MSG_TIME - _popup_t) / 0.5, 0.0, 1.0)
		_popup.modulate.a = k
		_popup.position.y = lerpf(-_popup.size.y, 18.0, k)
		if _popup_t >= MSG_TIME:
			_popup.queue_free()
			_popup = null
	if _popup == null and not _queue.is_empty():
		_show_popup(_queue.pop_front())


func _show_popup(e: Dictionary) -> void:
	if Sfx.instance:
		Sfx.instance.play(SOUND)
	_popup_t = 0.0
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.03, 0.82)
	sb.border_color = Color(0.55, 0.05, 0.03)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	frame.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UiArt.region(ICON_DONE)
	icon.custom_minimum_size = Vector2(52, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var title := Label.new()
	title.text = Lang.t("Obiettivo sbloccato")
	title.add_theme_font_override("font", UiArt.font())
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiArt.RED.lightened(0.15))
	col.add_child(title)
	var label := Label.new()
	label.text = "%s  (%d)" % [title_of(e), e["points"]]
	label.add_theme_font_override("font", UiArt.font())
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	col.add_child(label)
	var desc := Label.new()
	desc.text = desc_of(e)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	col.add_child(desc)
	_layer.add_child(frame)
	frame.reset_size()
	var vw := get_viewport().get_visible_rect().size.x
	frame.position = Vector2((vw - frame.size.x) * 0.5, -frame.size.y)
	_popup = frame
	# hud_acheivementFrame's achievementButton ("viewachievement"): touching the popup opens
	# ig_viewachievement for it (achievements_screen.gd view, the game paused)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed:
			open_view(String(e["id"])))


func open_view(id: String) -> AchievementsScreen:
	for n in get_tree().root.get_children():
		if n is AchievementsScreen:
			return null
	if _popup:
		_popup.queue_free()
		_popup = null
	var v := AchievementsScreen.view(id)
	get_tree().root.add_child(v)
	return v
