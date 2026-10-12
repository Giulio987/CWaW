# CoD Zombies (iOS 2010) – remake per uso personale

Sorgente: `Call_of_Duty__Zombies_1.5.0_ios_3.0.ipa` (armv6, motore Ideaworks **Airplay SDK 4.3**, logica in **Lua 5.1**).
Obiettivo: estrarre gli asset originali e ricostruire il gioco su un motore moderno (arm64 / iPhone attuale).

## Struttura
```
original/kiwi.app     bundle originale (non modificare)
extracted/            contenuto degli archivi .dz (gruppi *.group.bin)
game/assets/textures       PNG decodificate (per gruppo, nome = hash risorsa)
game/assets/sounds         WAV PCM 16 bit
game/assets/lua            script Lua decompilati (logica di gioco, ondate, mappe)
game/assets/lua_bytecode   bytecode originale
analysis/             note, dump, anteprime
tools/                estrattori (Python)
```

## Ricostruire gli asset
Serve: Python 3, ffmpeg, Java (per unluac), Godot 4.7.
```sh
tools/build_assets.sh          # original/kiwi.app -> extracted/ -> game/assets/
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
```
Anteprima di un modello: `Godot --path game -s res://tools/preview.gd -- res://assets/models/levels/nacht/environment.glb out.png 30 -45 0.7`

## Giocare (prototipo, Mac)
```sh
/Applications/Godot.app/Contents/MacOS/Godot --path game            # Nacht der Untoten
/Applications/Godot.app/Contents/MacOS/Godot --path game -- nacht --autotest 120   # bot + log + screenshot in analysis/autotest
```
Senza argomenti parte il menu principale (texture originali) per scegliere la mappa.
Comandi: WASD, mouse, clic sinistro spara, V coltello, R ricarica, Q cambia arma, E compra/ripara, Shift corre, Spazio salta, Esc pausa.
Su touch (iPhone): stick virtuale a sinistra, trascina a destra per guardare, pulsanti FUOCO/E/R/⇄/🔪.
Debug: `-- nacht --look <entità,...>`, `-- nacht --shots <armi,...>`, `-- nacht --spin` salvano screenshot in `analysis/preview`;
`-- nacht --stairs-test` apre le macerie e fa salire il giocatore al piano di sopra (stampa OK/FAIL);
con `--no-open` verifica che saltando non si superino le macerie. `--look Entità@gradi` inquadra di lato:
le viste frontali nascondono gli errori di rotazione. `tools/run_godot.sh <secondi> -- ...` esegue con un limite di tempo.

Gameplay in `game/scripts/`: `level.gd` (mappa, collisioni, navmesh, entità), `barricade.gd`, `debris.gd`,
`player.gd`, `zombie.gd`, `game.gd` (round da `waves.json` estratto dagli script Lua originali), `hud.gd`, `weapons.gd`.

## Stato
| Componente | Stato | Note |
|---|---|---|
| Archivi `.dz` (DTRZ, LZMA) | ✅ | `tools/dz_extract.py` |
| Gruppi `.group.bin` | ✅ 68/68 | `tools/group.py`; hash = djb2 lowercase (`tools/iwhash.py`) |
| Texture (PVRTC, RGB/RGBA, palette) | ✅ 384/384 | `tools/textures.py` |
| Suoni (IMA ADPCM / PCM) | ✅ 499/499 | sample rate dedotto da blockAlign |
| Script Lua | ✅ 15 script, ~10.8k righe | unluac |
| Modelli `CIwModel` | ✅ 1324/1324 | `tools/model.py`, export glTF `tools/export_gltf.py`; 4 mappe complete |
| Materiali | ✅ | texture base + lightmap (UV2, in `extras.lightmap`, non ancora applicata in Godot) |
| Scheletri / skin / animazioni tipo 3 | ✅ | zombie (72 anim), cani (29), alcuni oggetti; `tools/anim.py`, `tools/export_characters.py` |
| Animazioni tipo 2 (giocatore/armi, oggetti) | ✅ | posizioni per osso SoA con bias; scala posizioni per scheletro |
| Braccia + armi in prima persona | ✅ | arma agganciata all'osso 22 delle braccia, animazioni accoppiate (`tools/pair_arms.py`) |
| Menu principale | ✅ | texture originali, scelta mappa |
| Parti dei personaggi | 🔶 | mesh divise per parte; nomi noti: body, legs, neck, leftarm, rightarm, leftelbow, rightelbow, headb, sleevel, sleever |
| Entità livello | 🔶 | nomi, trasformazioni, componenti, costi e armi (`tools/entities.py`); dettagli dei componenti non ancora |
| Tabelle ondate | ✅ | `tools/lua/dump_waves.lua` → `waves.json` (eseguite dagli script Lua originali) |
| Collisioni / navmesh | ✅ | generate in Godot dalla geometria; su Shi No Numa il `CIwNavMesh` originale (`tools/navmesh.py` → `navmesh.json`, flag 4 = scale/rampe, 2 = sotto l'acqua) aggiunge un pavimento solo per zombie/cani dove la geometria non ne ha (ponti di assi e scale senza collisione, terreno oltre le quinte della giungla) |
| Gameplay Nacht | 🔶 | round, spawn, finestre, scavalcamento, inseguimento, attacco, armi a muro, macerie, coltello, punti, lightmap |
| Altre mappe | 🔶 | aree/collegamenti dagli script Lua (`level.json`); spawn come in `AvailableSpawns` (spawn *n* → finestra *n*, finestre del cortile di Verrückt, zombie della palude senza finestra su Shi No Numa, spawn locale vicino al giocatore su Shi No Numa); aree aperte da trigger Lua con link "NA" (Der Riese, Shi No Numa) e dal generatore; nomi delle entità note solo per hash recuperati da `tools/resolve_names.py` → `names.json`; test `--reach-test [--from Entità] [--probe x1,z1,x2,z2]` |
| Cani (hellhound) | ✅ | Shi No Numa e Der Riese, da `waves.lua`: round dei cani dopo più di 2 round (1 su 3, sempre dopo 4), 6/12/16… cani (difficoltà), 300 hp × n° round cani, al massimo 2 vivi, spawn con fulmine nell'area del giocatore, nebbia, Max Ammo dall'ultimo; metà sono cani infuocati (`flame_dogSpawn`: fiamme sulla schiena, esplosione di fuoco innocua alla morte); `scripts/dog.gd`, test `--dog-test`, `--dog-look [--flame]` |
| Trappole | ✅ | elettriche (Verrückt, Der Riese, capanne di Shi No Numa) e flogger: 30 s attive, uccidono zombie/cani (senza punti) e feriscono il giocatore (si accendono 2,3 s dopo l'acquisto, animazione della leva), poi 30 s di ricarica (+2 s di animazioni, dall'ASM `2b8efeb7`); serve la corrente dove c'è il generatore; volume dalle entità `<trappola>Effect<n>`, su Verrückt dalla geometria; `scripts/trap.gd`, test `--trap-test` (`--trap-debug`) |
| Teletrasporti / Pack-a-Punch | ✅ | Der Riese: con la corrente si attiva un pad e lo si collega al mainframe; ogni collegamento apre la porta del mainframe, al terzo si apre il Pack-a-Punch (5000: caricatore/riserva dei `*_upgrade` originali, danno ×1.5, nomi WaW); teletrasporto 1500 con ricarica, power-up o cani all'arrivo; `scripts/teleporter.gd`, `scripts/pack_a_punch.gd`, test `--tele-test`, `--pap-test` |
| Verrückt | ✅ | partenza divisa: a caso metà tedesca o americana (`--start german|american`), la porta `StartDoorLink` si apre con la corrente |
| Orientamento barricate/macerie | 🔶 | macerie: le trasformazioni con quaternione identità tengono i quarti di giro nel byte "flags" (0x10 = −90°, 0x04 = 180° attorno a Y, `Level.flag_transform`), anche per la trasformazione figlia del modello; il collider è nel sistema dell'entità; test `-- <mappa> --debris-test [--shot Entità@gradi]`. Barricate: direzione dal muro, interno/esterno dai settori (`tools/wall_yaw.py`); casse/perk non usano ancora i flags |
| Settori e LOD | ✅ | `CIwSGSectorBuilder` → `sectors.json`; `CIwLODControllerCameraVolume` mostra la variante del settore della telecamera |
| Mystery box | ✅ | 950 punti, coperchio animato originale, armi che girano, offerta 12 s; test `--box-test` |
| Perk-a-Cola | ✅ | Juggernog (250 hp), Speed Cola (ricarica ×0.5), Double Tap (cadenza ×0.75), Quick Revive (solo: si rialza una volta, perde i perk); corrente dal `GeneratorSwitch` su Der Riese/Verrückt (`--power` la accende subito), Shi No Numa un perk casuale per postazione; icone originali nell'HUD; `scripts/perk_machine.gd`, `scripts/perks.gd`, test `--perk-test` |
| Suoni in gioco | ✅ | `tools/sound_index.py`: nomi ricostruiti, sequenze di ricarica originali, sparo da `CItemGun`, canali ambientali; `scripts/sfx.gd` |
| Der Riese: ponte e acchiappamosche | ✅ | ponte levatoio che si abbassa con la corrente (vapore, suoni, collisione `col_Link_pC_pC`), `scripts/bridge.gd`, test `--bridge-test`; acchiappamosche da colpire con un'arma Pack-a-Punch: anello di scintille, voci, poi 3 oggetti da trovare e colpire, `scripts/flytrap.gd`, test `--flytrap-test` |
| Shi No Numa | ✅ | palude guadabile: l'acqua (texture `72339cb6`) si vede ma non è solida, si cammina sul fondale del navmesh originale (0,3–1 m sotto la superficie; giocatore, zombie, cani, granate, proiettili; fondo di riserva a −1,25 m dove il navmesh non arriva), il giocatore nell'acqua va a metà velocità (`WaterMoveSpeedModifier` 2048/4096 in `console.bin`); zombie della palude (`<Area>ZombieSwampSpawn<n>`, template `_water`: escono dall'acqua con spruzzi e suono `9c17d777`); spawn dietro le quinte della giungla: lo zombie entra a piedi fino al navmesh; teleferica (`ZipLine`, `CZiplineSpec`): leva `ZiplineDoctorSwitch` vicino alla capanna del dottore (attiva gratis, apre il cancello `ZipLineDoorLink` e l'area `ledge`, poi "chiama" per 1500), corsa di 6 s (`ZiplineMovementTime`) per 1500 in entrambe le direzioni, 30 s di attesa all'arrivo, uccide gli zombie sul percorso; `scripts/zipline.gd`, test `--swamp-test map|rise|spawns|walk|wade|zipline` (`scripts/swamp_tests.gd`) |
| Armi (valori originali) | ✅ | `tools/weapon_stats.py` → `analysis/weapon_stats.json`: layout di `CItemGun` da `CItemGun::Serialise` (ARM, va 0x2132c0), danno da `CItemGun::GetDamage` (va 0x238a40: penetrazione, moltiplicatori per zona colpita, calo con la distanza, cono dei fucili a pompa, danno minimo), cadenza/ricarica dagli stati di `CIsAnimStateMachine`, splash di Ray Gun/granate da `CSplashEffectSpec`; usati in `scripts/weapons.gd` |
| Passi del giocatore | ✅ | come nel codice originale (aggiornamento del giocatore, kiwi `0x1a1f88`): un passo quando scade il timer e ci si muove, i suoni di `WalkingFootstepSounds` (`player_footstep_walk3/4`) o, sull'acqua, `WalkingFootstepWaterSounds` (`water_walk1/2`) a turno; intervallo = `FootstepSpeedMultiplier` / (\|vx\|+\|vz\|) nel riferimento del giocatore (in acqua, a metà velocità, il doppio); volume/pitch dalle `CIwSoundSpec` (0x599, 0x0c00); niente passi degli zombie (l'originale non li ha); test `--footstep-test` (nacht, shinonuma) |
| Obiettivi | ✅ | i 106 `CAchievementResource` di `fixed/achievements/*.group.bin` (`tools/achievements.py` → `assets/achievements.json`: id, punti, nomi/descrizioni dalla localizzazione, classe di condizione e statistiche originali); sbloccati come negli script (Lua `Game.SetAchievement`: radio, poltrona del dentista, generatore, acchiappamosche; telefono) e dalle statistiche (uccisioni, smembramenti, round, perk, Pack-a-Punch, teletrasporti, trappole, granate...); popup 5 s (`AchievementMsgTimeMS`) col suono `achievement`, salvataggio in `user://achievements.cfg` (i test usano `achievements_test.cfg`), elenco dal menu principale e dalla pausa con nomi/descrizioni in italiano; 17 non ottenibili qui (co-op, tutorial, Wunderwaffe, magnum, Betty, Bowie, barili); `scripts/achievements.gd`, test `--achievement-test` |
| Mancano | ⏳ | spostamento della mystery box (orsacchiotto), musica, build iOS |

## Formati – appunti
- Risorsa nel gruppo: `u32 size, u32 nameHash, body`. Le classi polimorfiche (es. `CIwSoundData`) hanno invece `u32 subclassHash` al posto del nome, e il nome è il primo u32 del body.
- Formati dettagliati nei docstring di `tools/model.py`, `tools/anim.py`, `tools/textures.py`, `tools/sounds.py`.
- `CItemGun` (gruppo player, `<arma>` e `<arma>_upgrade`): campi in ordine di serializzazione documentati in `tools/weapon_stats.py` (es. 0x7c caricatore, 0x80 riserva, 0x84 danno, 0x78 danno minimo, 0x68/0x6c inizio/calo per unità della caduta di danno, 0x54 bersagli attraversati, 0x64 perdita per bersaglio attraversato, 0x60 cono dei fucili a pompa, tabella zona→moltiplicatore in fondo, poi il nome). Distanze in unità mondo (le distanze dei designer sono pollici WaW ×10,16).
- Scala: 400 unità = 1 m; UV s16 con 4096 = 1.0; tempi animazione in 1/4096 s; quaternioni "smallest three" 3×10 bit.


/Applications/Godot.app/Contents/MacOS/Godot --path ~/Desktop/Giulio/CoDZombiesRemake/game