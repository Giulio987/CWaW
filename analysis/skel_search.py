import struct,sys,itertools
import numpy as np
sys.path.insert(0,'tools')
from model import Model
b=open('analysis/skel_ger.bin','rb').read()
n=struct.unpack_from('<I',b,0)[0]
bones=[];pos=4
for i in range(n):
    cls,name,parent,qu=struct.unpack_from('<IIII',b,pos); p=struct.unpack_from('<hhh',b,pos+16)
    bones.append((name,parent,qu,np.array(p,float))); pos+=30
V=Model(open('analysis/model0.bin','rb').read()).verts.astype(float)
def qmul(a,b):
    x1,y1,z1,w1=a;x2,y2,z2,w2=b
    return np.array([w1*x2+x1*w2+y1*z2-z1*y2, w1*y2-x1*z2+y1*w2+z1*x2, w1*z2+x1*y2-y1*x2+z1*w2, w1*w2-x1*x2-y1*y2-z1*z2])
def rot(q,v):
    p=np.array([*v,0.0]); return qmul(qmul(q,p),q*np.array([-1,-1,-1,1]))[:3]
def quat(u,enc,layout,wfirst):
    idx=u>>30; raw=[(u>>20)&0x3ff,(u>>10)&0x3ff,u&0x3ff]
    if layout=='lsb': raw=raw[::-1]
    if enc=='off': v=[(x-512)/511*0.70710678 for x in raw]
    else: v=[(x-1024 if x>=512 else x)/511*0.70710678 for x in raw]
    w=max(0,1-sum(x*x for x in v))**0.5
    q=v[:idx]+[w]+v[idx:]
    if wfirst: q=q[1:]+q[:1]   # stored (w,x,y,z) -> (x,y,z,w)
    return np.array(q)
from scipy.spatial import cKDTree as T  # noqa
tree=T(V)
res=[]
for enc,layout,wfirst,conj,order in itertools.product(('off','tc'),('msb','lsb'),(False,True),(False,True),('pl','lp')):
    world={}
    for name,parent,qu,p in bones:
        q=quat(qu,enc,layout,wfirst)
        if conj: q=q*np.array([-1,-1,-1,1])
        if parent in world:
            pq,pp=world[parent]
            nq=qmul(pq,q) if order=='pl' else qmul(q,pq)
            world[name]=(nq, pp+rot(pq,p))
        else: world[name]=(q,p.copy())
    J=np.array([w[1] for w in world.values()])
    best=None
    for k in np.linspace(0.1,1.2,45):
        Jk=J*k; off=V.mean(0)-Jk.mean(0)
        dist=tree.query(Jk+off)[0].mean()
        if best is None or dist<best[0]: best=(dist,k)
    res.append((best[0],best[1],enc,layout,wfirst,conj,order))
for r in sorted(res)[:8]: print(r)
