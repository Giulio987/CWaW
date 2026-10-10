import sys,collections,struct,re
sys.path.insert(0,'tools')
from group import Group
from iwhash import iw_hash,load_dictionary
d=load_dictionary('analysis/kiwi_strings.txt','analysis/lua_strings.txt')
# add numbered variants of lua names
base=set()
for l in open('analysis/lua_strings.txt'):
    t=l.strip(); base.add(re.sub(r'\d+$','',t))
for b in base:
    for i in range(0,40):
        for v in (f'{b}{i}', f'{b}{i:02d}', f'{b}_{i}'):
            d.setdefault(iw_hash(v),v)
lvl=sys.argv[1] if len(sys.argv)>1 else 'nacht'
g=Group(f'extracted/{lvl}/levels/{lvl}/environment/environment.group.bin')
E=iw_hash('CIwEntSpec')
pat=bytes.fromhex('001000000010000000100000')
for r in g.resources:
    if r.cls!=E: continue
    b=r.body
    comps=[]
    for i in range(len(b)-3):
        h=struct.unpack_from('<I',b,i)[0]
        n=d.get(h)
        if n and n[0]=='C' and n[1].isupper() and 'Spec' in n or (n in ('CEnt',)): comps.append(n.replace('Spec',''))
    xf=[]; i=0
    while True:
        i=b.find(pat,i)
        if i<0: break
        xf.append(struct.unpack_from('<iii',b,i-17)); i+=1
    print(d.get(r.name_hash,hex(r.name_hash)), len(b), xf[-1] if xf else None, ' '.join(dict.fromkeys(comps)))
