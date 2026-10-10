import sys,itertools
sys.path.insert(0,'tools')
from group import Group
from iwhash import iw_hash
anims={r.name_hash for p in ('ger','jap') for r in Group(f'extracted/main/ingame/zombiesanims{p}/zombiesanims{p}.group.bin').resources if r.cls==iw_hash('CIwAnim')}
anims|={r.name_hash for r in Group('extracted/main/ingame/dogs/dog.group.bin').resources if r.cls==iw_hash('CIwAnim')}
vocab=['walk','run','sprint','crawl','attack','death','die','idle','climb','window','barrier','stand','turn','left','right','forward','back','hit','pain','react','fall','get','up','jump','over','in','out','taunt','scream','spawn','rise','ground','tear','board','pull','swipe','lunge','melee','head','arm','leg','legs','gib','shot','explode','explosion','burn','fire','electric','shock','tesla','wunder','monkey','dance','stagger','stumble','fast','slow','super','loop','start','end','intro','outro','jap','ger','traverse','mantle','vault','trap','knockdown','knock','push','grab','bite','eat','feed','sit','lie','prone','spin','fling','thundergun','fwd','bk','to','from','short','long','high','low','wall','floor','table','hole','drop','down','air','hand','hands','both','no','crawler','riese','rotate','l','r','f','b','v','alt','var','mid','front','side','base','large','small','big','reach','swing','claw','bash','stun','nova','gas','blast','flop','flail','knee','kneel','crouch','wake','emerge','dig','slide','skid','jog','shamble','limp','drag','pose','pain2','behind','through','reverse','damage','headshot','dog','hound','bark','howl','sniff','growl','leap','pounce','trot','gallop','zombie','zomb']
suf=['']+[str(i) for i in range(10)]+['a','b','c','d','01','02','03','04','05','06']
cand={}
def add(s):
    h=iw_hash(s)
    if h in anims and h not in cand: cand[h]=s
for pre in ('zombie_','dog_','zombie','dog','z_','zom_',''):
    for n in (1,2,3):
        for toks in itertools.product(vocab,repeat=n):
            base=pre+'_'.join(toks)
            for s in suf:
                add(base+s); add(base+'_'+s) if s else None
print(len(cand),'of',len(anims))
for h,s in sorted(cand.items(),key=lambda x:x[1]): print(f'{h:08x} {s}')
