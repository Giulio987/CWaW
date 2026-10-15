# Languages: Italian (the remake's own texts) and English (the original game's texts).
#
# Every text shown to the player goes through Lang.t(<Italian text>): in Italian it comes
# back as is, in English it is looked up in EN. An EN value is either plain English (texts
# the original does not have) or a reference to the original English text, read at run time
# from the generated assets (assets/frontend_text.json, built by tools/frontend_text.py from
# the localisation/*.dat of the user's copy; the repository holds no original text):
#   "#xxxxxxxx"  localisation string by hash (frontend_text.json "loc")
#   "LS_NAME"    localisation string by its LS_ name (hash = IwHashString of the name)
#   "@key"       frontend_text.json "text" entry
# Format strings keep their placeholders in both languages (Lang.t(it) % args).
#
# Prompts depend on the device (Lang.prompt): on a Mac they name the key (E), with touch
# controls the hand button (the original iPhone prompt is the bare action, e.g. "Open Door
# [Cost: 1000]" - touch_controls.gd shows the hand only when there is something to use).
#
# Language: the "language" setting (settings.cfg, Options -> Language); its default is the
# build's (tools/build_ios.sh --lang: custom feature lang_en / lang_it of the export preset;
# English without one in an export), Italian when run from source on the Mac. `--lang en|it`
# on the command line overrides it for one run (tests, screenshots).
class_name Lang
extends RefCounted

const LANGS := ["it", "en"]
const NAMES := {"it": "Italiano", "en": "English"}

static var _override := ""
static var _override_read := false
static var _warned := {}


# The language of a build without a saved choice.
static func build_default() -> String:
	if OS.has_feature("lang_en"):
		return "en"
	if OS.has_feature("lang_it"):
		return "it"
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return "it"   # run from source on the Mac
	return "en"


static func code() -> String:
	if not _override_read:
		_override_read = true
		var args := OS.get_cmdline_user_args()
		var i := args.find("--lang")
		if i >= 0 and i + 1 < args.size() and args[i + 1] in LANGS:
			_override = args[i + 1]
	if _override != "":
		return _override
	var c := String(Settings.get_value("language"))
	return c if c in LANGS else build_default()


static func is_en() -> bool:
	return code() == "en"


# Saved by the caller with Settings.save(); menus rebuild their pages (pause_menu.gd relocalize).
static func set_language(c: String) -> void:
	_override = ""   # a --lang of the command line no longer applies
	_override_read = true
	Settings.set_value("language", c)


static func next_language() -> String:
	return LANGS[(LANGS.find(code()) + 1) % LANGS.size()]


# The touch controls are on (as hud.gd: a touch screen, or --touch-ui on a Mac).
static func touch() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch-ui")


# Italian text -> text of the current language.
static func t(it: String) -> String:
	if not is_en():
		return it
	if EN.has(it):
		return resolve(String(EN[it]), it)
	if not _warned.has(it):
		_warned[it] = true
		push_warning("[lang] no English text for '%s'" % it)
	return it


# As t(), for widgets that also get names or already translated text (menu rows, titles):
# a text without an English entry comes back unchanged and without a warning.
static func maybe(it: String) -> String:
	return resolve(String(EN[it]), it) if is_en() and EN.has(it) else it


# An EN value: a reference to an original text ("#hash", "LS_NAME", "@key") or plain text.
static func resolve(v: String, fallback := "") -> String:
	var d := ExtrasScreen.data()
	var r = null
	if v.begins_with("#") and v.length() == 9:
		r = d.get("loc", {}).get(v.substr(1))
	elif v.begins_with("LS_"):
		r = d.get("loc", {}).get("%08x" % iw_hash(v))
	elif v.begins_with("@"):
		r = d.get("text", {}).get(v.substr(1))
	else:
		return v
	if r == null:
		if not _warned.has(v):
			_warned[v] = true
			push_warning("[lang] original text %s missing (rebuild the assets: tools/frontend_text.py)" % v)
		return fallback if fallback != "" else v
	return String(r)


# Airplay IwHashString: djb2 over the lowercased string (tools/iwhash.py).
static func iw_hash(s: String) -> int:
	var h := 5381
	for c in s.to_lower().to_utf8_buffer():
		h = (h * 33 + c) & 0xFFFFFFFF
	return h


# Interaction prompt. it_action: the Italian action after "per" ("aprire la porta"); en: the
# English action, an original text when there is one (with or without its "\n[Cost: %d]");
# cost >= 0 adds the price; hold: the Mac text says to hold the key (the remake's wording).
#   Italian, Mac:   "Tieni premuto E per aprire la porta [1000]" / "Premi E per ..."
#   Italian, touch: "Tieni premuta la mano per aprire la porta [1000]" / "Tocca la mano per ..."
#   English, touch: the original iPhone text "Open Door\n[Cost: 1000]"
#   English, Mac:   "Hold E: Open Door [Cost: 1000]" / "Press E: ..."
static func prompt(it_action: String, en: String, cost := -1, hold := false) -> String:
	if not is_en():
		var head := ("Tieni premuta la mano per " if hold else "Tocca la mano per ") if touch() \
			else ("Tieni premuto E per " if hold else "Premi E per ")
		return head + it_action + (" [%d]" % cost if cost >= 0 else "")
	var s := resolve(en)
	if cost >= 0:
		if s.contains("%d"):
			s = s % cost
		else:   # an original with a fixed price ("Open Cabinet\n[Cost: 2000]") or none
			var i := s.find("\n[Cost:")
			s = (s.substr(0, i) if i >= 0 else s) + "\n[Cost: %d]" % cost
	if touch():
		return s
	return ("Hold E: " if hold else "Press E: ") + s.replace("\n", " ")


# Ordinal for leaderboards: "1°" / "1st" (LS_RANK_FIRST/SECOND/THIRD/REST).
static func rank(n: int) -> String:
	if not is_en():
		return "%d°" % n
	var k := "LS_RANK_REST"
	if n % 100 < 11 or n % 100 > 13:
		k = ["LS_RANK_REST", "LS_RANK_FIRST", "LS_RANK_SECOND", "LS_RANK_THIRD"][n % 10] if n % 10 <= 3 else k
	return "%d%s" % [n, resolve(k, "th")]


# English texts by Italian text (see the header for the references to original texts).
const EN := {
	# front end (fe_mainmenu, fe_singleplayer, fe_selectlevel, fe_extras, fe_options)
	"Menu principale": "#1ffc315c",                 # Main Menu
	"Giocatore singolo": "#eff62cb2",               # Single Player
	"Extra": "@extras",
	"Opzioni": "@options",
	"Obiettivi": "#004b0370",                       # Achievements
	"Classifiche": "@leaderboards",
	"Riconoscimenti": "@credits",
	"Informazioni": "@about",
	"Impostazioni": "#d0c4f294",                    # Settings
	"Aiuto": "@help",
	"Impostazioni predefinite": "@default_settings",
	"Lingua": "#182b5847",                          # Language
	"Difficoltà:": "#fa8f0a76",                     # Difficulty:
	"Nuova partita": "#f23a88a7",                   # New Game
	"Continua": "#7b2b462e",                        # Continue
	"Seleziona livello": "#940030bb",               # Select Level
	"Indietro": "#9080fdf4",                        # Back
	"Recluta": "#14fb7e68",                         # Recruit
	"Regolare": "#57cfca9f",                        # Regular
	"%s · round %d · %d punti": "%s · round %d · %d points",
	"DEBUG: round %d · Ray Gun · %d punti": "DEBUG: round %d · Ray Gun · %d points",
	"Gli obiettivi non si sbloccano in questa modalità": "Achievements can't be unlocked in this mode",
	# pause menu (ig_pause, ig_options) and its confirmations
	"PAUSA": "PAUSE",
	"Riprendi": "@resume",
	"Classifica locale": "@local_leaderboard",
	"Ricomincia livello": "@restart_level",
	"Modalità foto (debug)": "Photo mode (debug)",
	"Torna al menu principale": "@return_to_menu",
	"Tornare al menu principale?\nLa partita viene salvata: si riprende dal menu.":
		"Return to the Main Menu?\nThe game is saved: continue it from the menu.",
	"No": "No",
	"Sì": "Yes",
	"OPZIONI": "OPTIONS",
	"IMPOSTAZIONI": "SETTINGS",
	"Ricominciare il livello?\nI progressi andranno persi.": "@restart_confirm",
	"Ripristinare le impostazioni predefinite?": "@default_confirm",
	"Azzerare tutti gli obiettivi e le statistiche?\nNon si può annullare.":
		"Reset all achievements and statistics?\nThis cannot be undone.",
	"Sì, azzera": "Yes, reset",
	"Azzera obiettivi e statistiche": "Reset achievements and statistics",
	"FOTO (debug) · %s · round %d · pos (%.2f, %.2f, %.2f)%s · yaw %.0f° pitch %.0f° · trascina per girare · Esc o doppio tocco: torna":
		"PHOTO (debug) · %s · round %d · pos (%.2f, %.2f, %.2f)%s · yaw %.0f° pitch %.0f° · drag to turn · Esc or double tap: back",
	" · settore ": " · sector ",
	# settings (fe_settings / ig_settings and the remake's own)
	"Sensibilità mouse": "Mouse sensitivity",
	"Sensibilità touch": "Touch sensitivity",
	"Inverti asse Y": "#932f45c9",                  # Invert Y Axis
	"Sensibilità verticale": "Vertical sensitivity",
	"Campo visivo": "Field of view",
	"Mirino: clic per attivare": "Aim: click to toggle",
	"Mira assistita": "Auto-Aim",
	"Volume generale": "Master volume",
	"Volume effetti": "Effects volume",
	"Volume musica": "Music volume",
	"Luminosità": "#a9fbdabc",                      # Brightness
	"Difficoltà Recluta (prossima partita)": "Recruit difficulty (next game)",
	"Livello di dettaglio": "@detail_level",
	"Alto (più lento)": "@detail_high",
	"Medio": "@detail_medium",
	"Basso (più veloce)": "@detail_low",
	"Pausa automatica": "@auto_pause",
	"Dimensione schermo": "Screen size",
	"Schermo intero": "Full screen",
	# help, credits, about, leaderboards (extras_screen.gd)
	"Gioco": "@help_game",
	"Prestazioni": "@help_performance",
	"Punti": "#d6614140",                           # Points
	"Uccisioni": "#a14822e2",                       # Kills
	"Colpi alla testa": "#0cd72b06",                # Headshots
	"Testa": "Heads",
	"Data": "Date",
	"Nessuna partita registrata su questa mappa (le partite in Recluta e in modalità DEBUG non contano).":
		"No games recorded on this map (Recruit and DEBUG games don't count).",
	"Remake personale in Godot %s degli asset e degli script originali (iOS 1.5.0, Ideaworks Airplay SDK). Non distribuito.":
		"Personal remake in Godot %s of the original assets and scripts (iOS 1.5.0, Ideaworks Airplay SDK). Not distributed.",
	# achievements
	"Tutti": "All",
	"Generali": "#f538f463",                        # General
	"Punteggio:": "#51adce9e",                      # Score:
	"Completamento:": "#fe51745b",                  # Complete:
	"Totale": "#a1ee6a47",                          # Total
	"Completati": "#b833ca00",                      # Completed
	"(non disponibile in questa versione)": "(not available in this version)",
	"Sbloccato il %02d/%02d/%d": "Unlocked on %02d/%02d/%d",
	"Obiettivo sbloccato": "#f0ecef20",             # Achievement Unlocked
	# game over (ig_gameover)
	"Classifica · %s": "Leaderboard · %s",
	"RIPROVA": "RETRY",
	"MENU PRINCIPALE": "MAIN MENU",
	# HUD messages
	"Caricamento navigazione…": "Loading navigation…",
	"Munizioni al massimo!": "#d1b0045e",           # Max. Ammo!
	"Uccisione istantanea!": "#d5bd2979",           # Insta-Kill!
	"Munizioni finite": "#07d8bba9",                # No Ammo
	"Partita finita": "#7865e519",                  # Game Over
	"Versione:": "Version:",
	"Doppi punti!": "#40cd52a6",                    # Double Points!
	"Bomba atomica!": "#6e2e306b",                  # Atomic Bomb!
	"Carpentiere!": "#c57609d2",                    # Carpenter!
	"Tutte le aree sbloccate, ora trova la tomba!": "LS_WUNDERWAFFE_GAME_FIND",
	"Molotov x%d: premi T per selezionarle": "Molotov x%d: press T to select them",
	"Molotov x%d: doppio tocco sull'oggetto speciale": "Molotov x%d: double-tap the special item button",
	# messages instead of a prompt
	"Serve la corrente": "LS_GENERATOR_NEED_POWER",
	"Prima bisogna aprire la porta": "#bcf369e3",   # The door must be opened first
	"Trappola in ricarica": "Trap recharging",
	"Collegamento in corso": "LS_TELEPORTER_LINKING",
	"Il teletrasporto si sta ricaricando": "LS_TELEPORTER_TELEPORTING",
	"Temporaneamente non disponibile": "LS_TELEPORTER_TEMPUNAVAIL",
	"Collega i teletrasporti al mainframe": "Link the teleporters to the mainframe",
	"Arma già potenziata": "Weapon already upgraded",
	"La teleferica deve essere attivata prima": "#7e3fb08b",   # The zipline must be activated first
	# Pack-a-Punch names without a World at War name
	"Arisaka (potenziato)": "Arisaka (Upgraded)",
	"Springfield (potenziato)": "Springfield (Upgraded)",
	".357 Magnum (potenziata)": ".357 Magnum (Upgraded)",
}


# ------------------------------------------------------------------ Italian texts of original content
# The original's long texts (help pages, map and difficulty descriptions, notes) exist only in
# English (its Italian localisation is an untranslated copy): the Italian translations are here,
# the English ones are read from the assets (frontend_text.json). The credits stay original.

# ExtrasScreen.text(key) in Italian
const IT_TEXT := {
	"regular_desc": "In modalità Regolare le statistiche vengono registrate e gli obiettivi si possono sbloccare.\nAttenzione: cambiando difficoltà si perde la partita salvata",
	"recruit_desc": "In modalità Recluta i nemici sono più deboli e si possono subire più colpi, ma le statistiche non vengono salvate e gli obiettivi non si sbloccano. Attenzione: cambiando difficoltà si perde la partita salvata",
	"headphones": "Per un'esperienza audio migliore, gioca a COD: Zombies con le cuffie.",
	"help_support": "Per altre informazioni e assistenza visita\nwww.activision.com/support",
}

# Level select descriptions (CMapInfo), by map id
const IT_MAPS := {
	"nacht": "Li hai respinti fin nel cuore del Reich.\n\nLi credevi morti.\n\nTi sbagliavi. . .",
	"verruckt": "Terapia elettroconvulsiva.\n\nBevande di sintesi chimica.\n\nTrova la corrente per unire le forze e rimandarli nelle loro tombe!",
	"shinonuma": "Cadaveri brulicanti di vermi.\n\nUna palude infestata dagli insetti.\n\nCentinaia di soldati non morti dell'Esercito Imperiale.\n\nScegli la tua tattica e difendi la tua vita!",
	"derriese": "Il Gigante si risveglia.\nAffronta la potenza degli zombie nazisti nella loro terra.\nQui tutto è cominciato.\nQui ha preso forma il piano supremo.\nSarà qui che tutto finirà?",
}

# Help pages (fe_helpgame, fe_helpperformance): [heading, bullets]
const IT_HELP := {
	"game": [
		["Generale", "• Uccidere gli zombie fa guadagnare punti\n• Con i punti si comprano armi e oggetti e si aprono nuove aree\n• Il gioco procede a round\n• Un round finisce quando viene ucciso l'ultimo zombie\n• Gli zombie subiscono danni diversi a seconda di dove vengono colpiti: i colpi alla testa sono particolarmente devastanti\n• Modi diversi di colpire gli zombie danno punti diversi\n• Il tuo obiettivo: sopravvivere il più a lungo possibile . . ."],
		["Barricate", "• Gli zombie abbattono le barricate per raggiungerti\n• Riparare le barricate fa guadagnare punti\n• I punti per le riparazioni hanno un tetto per ogni round\n• Il tetto aumenta a ogni round"],
		["Comprare armi e oggetti", "• Armi e oggetti si comprano con i punti dalle sagome di gesso o dalle scatole misteriose\n• Dopo l'acquisto, le munizioni di un'arma si comprano dalla sua sagoma di gesso\n• Si possono portare solo due armi alla volta\n• Comprando una nuova arma si sostituisce quella in mano\n• Se dalla scatola misteriosa esce un orsacchiotto, la scatola si sposta in un altro punto della mappa: per usarla di nuovo dovrai ritrovarla!\n• Le trappole proteggono per un po' una zona uccidendo gli zombie che ci passano: attento a non finirci dentro tu!\n• Le trappole hanno bisogno di tempo per ricaricarsi prima di poterle usare di nuovo"],
		["Aprire nuove aree", "• Le nuove aree si aprono in cambio di punti\n• Aprire un'area aumenta i punti d'ingresso da cui possono entrare gli zombie"],
		["Bonus", "• Doppi punti: tutti i punti guadagnati valgono il doppio per un tempo limitato\n• Uccisione istantanea: ogni colpo uccide, per un tempo limitato\n• Bomba atomica: uccide tutti gli zombie vivi al momento dell'esplosione\n• Munizioni al massimo: ricarica tutte le munizioni\n• Nelle partite multigiocatore i bonus valgono per tutti i giocatori"],
		["Ultima resistenza", "• Nelle partite multigiocatore, se vieni colpito troppe volte cadi a terra invece di morire subito: è l'Ultima resistenza\n• Durante l'Ultima resistenza puoi usare una pistola per difendere te e i tuoi compagni\n• Un compagno può rimetterti in piedi, ma mentre lo fa è vulnerabile"],
		["Perk", "• In alcune mappe ci sono distributori Perk-a-Cola che vendono bevande di sintesi chimica che danno abilità speciali\n• Una volta bevuti, i perk durano finché non vieni messo a terra\n• Si può avere un solo perk di ogni tipo alla volta\n• Il Juggernog aumenta la salute\n• La Quick Revive aiuta a rianimare più in fretta i compagni a terra\n• La Speed Cola rende più veloci le ricariche\n• La Double Tap Root Beer fa sparare più velocemente"],
		["Nuove mappe", "• Nell'originale i pacchetti di nuove mappe si scaricavano dalla sezione NUOVE MAPPE del menu principale\n• I pacchetti contengono nuovi livelli, armi e funzioni di gioco\n• Si poteva scaricare una versione di prova (fino al round 2) o la versione completa"],
	],
	"performance": [
		["Questi consigli possono migliorare le prestazioni del gioco:", "• Abbassare il Livello di dettaglio nelle opzioni migliora le prestazioni sui dispositivi meno potenti\n• Quando giochi in giocatore singolo, attiva la modalità aereo\n• Evita di giocare mentre il dispositivo è collegato a un computer\n• Se non giochi in multigiocatore Bluetooth, disattiva il Bluetooth\n• Imposta la luminosità del dispositivo al massimo per vedere meglio (dalle Impostazioni del dispositivo)"],
	],
}


# Help page sections in the current language.
static func help(which: String) -> Array:
	if not is_en() and IT_HELP.has(which):
		return IT_HELP[which]
	return ExtrasScreen.data().get("help", {}).get(which, [])


# Map description of the level select screen in the current language.
static func map_desc(id: String) -> String:
	if not is_en() and IT_MAPS.has(id):
		return IT_MAPS[id]
	return String(ExtrasScreen.data().get("maps", {}).get(id, {}).get("desc", ""))
