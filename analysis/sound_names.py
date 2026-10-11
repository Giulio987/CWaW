import sys,struct,glob,itertools,json
sys.path.insert(0,'tools')
from group import Group
from iwhash import iw_hash,load_dictionary
from textures import group_dir
specs={}   # spec hash -> (group dir, data hash)
for p in glob.glob('extracted/**/*.group.bin',recursive=True):
    g=Group(p)
    for r in g.resources:
        if r.cls==iw_hash('CIwSoundSpec'):
            sh=struct.unpack_from('<I',r.body,0)[0]; dh=struct.unpack_from('<I',r.body,len(r.body)-4)[0]
            specs[sh]=(group_dir(p),dh)
targets=set(specs)|{v[1] for v in specs.values()}
d=load_dictionary('analysis/kiwi_strings.txt','analysis/lua_strings.txt')
W=["colt45","colt","m1911","kar98","kar98k","carbine","thompson","mp40","stg44","trenchgun","shotgun","doublebarrel","bar","garand","g43","ppsh","type100","mg42","raygun","ptrs","fg42","sawnoff","springfield","arisaka","browning","flamethrower","wunderwaffe","tesla","grenade","molotov","betty","knife","bowie","monkey","pistol","rifle","smg","lmg","sniper","weapon","gun","flame"]
A=["mag_in","mag_out","clip_in","clip_out","start","end","close","open","rechamber","fire","shot","shoot","reload","reload_start","reload_end","clipout","clipin","clip_out","clip_in","magout","magin","mag_out","mag_in","bolt","boltback","boltforward","bolt_back","bolt_forward","rechamber","pump","cock","empty","dryfire","dry","raise","lower","pullout","putaway","switch","pickup","loop","start","end","shell","shells","open","close","charge","click","hit","explode","explosion","throw","pin","bounce","swing","stab","slash","impact","1","2","3","4"]
Z=["board","boards","board_break","board_slam","board_rip","rip","tear","snap","break","slam","repair","rebuild","hammer","nail","plank","wood","splinter","window","barrier_rebuild","barrier_break","rebuild_board","box_open","box_close","box_music","box_lid","lid","music_box","musicbox","chest","weapon_cycle","cycle","spin","roll","weapon_box","randombox","random","wave_start","wave_end","start_wave","new_wave","wave","level_start","round_change","change","eerie","stinger","horror","zombie_attack","zombie_death","zombie_pain","zombie_vox","zombie_sprint","zombie_walk","zombie_ambient","zombie_spawn","zombie_hit","zombie_swipe","zombie_window","zombie_breath","vocal","vocals","moan","grunt","snarl","shriek","yell","sting","punch","swipe","claw","flesh","bodyfall","body","fall","impact_flesh","bullet_flesh","headpop","head","limb","arm","leg","torso","gore","purchase_fail","purchase_success","buy_weapon","weapon_buy","ammo_buy","chalk","wallbuy","perk_buy","cash_register","register","ching","kaching","spend","zombie","zombies","zom","dog","hellhound","player","plr","vox","pa","radio","box","mysterybox","mystery","teddy","bear","barrier","barricade","board","boards","window","door","debris","perk","jingle","jug","juggernog","revive","quickrevive","speedcola","doubletap","pap","packapunch","powerup","maxammo","max_ammo","instakill","insta_kill","doublepoints","double_points","nuke","kaboom","carpenter","round","roundstart","round_start","roundend","round_end","gameover","game_over","music","purchase","buy","cash","money","points","ammo","denied","deny","no","yes","teleport","trap","electric","zap","generator","power","fire","flytrap","radio","amb","ambience","ambient","wind","rain","thunder","fog","fly","flies","lightning","siren","alarm","step","footstep","land","jump","pain","death","die","melee","attack","growl","groan","scream","sprint","run","walk","crawl","spawn","rise","gib","headshot","blood","splat","bullet","whizby","ricochet","heartbeat","breath","breathing","laugh","sam","samantha","announcer","intro","outro","ui","menu","select","back","click","achievement","sting","stinger","barrel","barrels","explosive"]
S=["","1","2","3","4","5","6","7","8","9","01","02","03","04","05","_1","_2","_3","_4","_5","_6","_01","_02","_03","_04","a","b","c","_a","_b","_c"]
cands={}
def add(s):
    h=iw_hash(s)
    if h in targets and h not in cands: cands[h]=s
for w,a in itertools.product(W,A):
    for sep in ("_",""):
        for suf in S: add(w+sep+a+suf)
for z,a in itertools.product(Z,Z+A):
    for sep in ("_",""):
        for suf in S: add(z+sep+a+suf)
for z in Z+W:
    for suf in S: add(z+suf)
for h in targets:
    if h in d: cands.setdefault(h,d[h])
named={h:n for h,n in cands.items()}
print(len(named),'of',len(targets))
out={}
for sh,(gd,dh) in sorted(specs.items(),key=lambda x:x[1]):
    out[f'{sh:08x}']={'group':gd,'data':f'{dh:08x}','name':named.get(sh) or named.get(dh)}
json.dump(out,open('analysis/sound_specs.json','w'),indent=1)
for k,v in out.items():
    if v['name']: print(v['group'].split('/')[-1],k,v['name'])
