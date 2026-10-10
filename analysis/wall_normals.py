import sys,json,struct
import numpy as np
sys.path.insert(0,'tools')
from group import Group
from model import Model
from iwhash import iw_hash
lvl=sys.argv[1]
g=Group(f'extracted/{lvl}/levels/{lvl}/environment/environment.group.bin')
ents={e['name']:e for e in json.load(open(f'game/assets/levels/{lvl}/entities.json'))}
offset={}
for e in ents.values():
    for h in [e['hash']]+e['models']:
        offset.setdefault(h, np.array(e['transform']['pos'],float))
skip={h for e in ents.values() if 'CBarricadeSpec' in e['components'] or 'CActionBuySpec' in e['components'] for h in e['models']}
tris=[]
for r in g.resources:
    h=f'{r.name_hash:08x}'
    if r.cls!=iw_hash('CIwModel') or h in skip: continue
    m=Model(r.body)
    if m.verts is None: continue
    for _,_,idx in m.trilists:
        idx=idx[:len(idx)//3*3].reshape(-1,3); tris.append(m.verts[idx].astype(float)+offset.get(h,0))
T=np.concatenate(tris)
n=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0]); area=np.linalg.norm(n,axis=1); n=n/np.maximum(area,1e-9)[:,None]
c=T.mean(1)
for name,e in ents.items():
    if 'CBarricadeSpec' not in e['components']: continue
    p=np.array(e['transform']['pos'],float)+np.array([0,500,0])
    sel=(np.abs(n[:,1])<0.3)&(np.linalg.norm((c-p)[:,[0,2]],axis=1)<500)&(np.abs(c[:,1]-p[1])<500)
    if sel.sum()==0: print(name,'no walls'); continue
    # dominant horizontal normal direction (mod 180)
    ang=np.arctan2(n[sel,0],n[sel,2])%np.pi
    hist,edges=np.histogram(ang,bins=36,range=(0,np.pi),weights=area[sel])
    a=(edges[hist.argmax()]+np.pi/36)
    ch=e['children'][-1] if e['children'] else None
    print(f"{name:32s} wall_normal_deg={np.degrees(a):6.1f} flags={e['transform']['flags']} child_flags={ch['flags'] if ch else None} child_pos={ch['pos'] if ch else None}")
