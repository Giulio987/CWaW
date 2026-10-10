import struct,sys,itertools
import numpy as np
sys.path.insert(0,'tools')
from model import Model
exec(open('analysis/skel_search.py').read().split('from scipy')[0])
sk=open('analysis/skin0.bin','rb').read()
m=Model(open('analysis/model0.bin','rb').read())
# unique verts with bias = first num_unique rows
U=m.verts[:m.num_unique].astype(float)
pos=16; pairs={}
nsets=struct.unpack_from('<I',sk,12)[0]
for s in range(nsets):
    cls,z,nv,size=struct.unpack_from('<IIII',sk,pos); pos+=16; start=pos
    bl=[]
    while sk[pos]!=0xff: bl.append(sk[pos]); pos+=1
    pos+=1
    if (pos-start)%2: pos+=1
    nb=len(bl)
    for v in range(nv):
        vi=struct.unpack_from('<H',sk,pos)[0]; pos+=2
        locs=[np.array(struct.unpack_from('<hhh',sk,pos+6*j),float) for j in range(nb)]; pos+=6*nb
        w=list(sk[pos:pos+nb]); pos+=nb+(nb%2)
        if nb==1: pairs.setdefault(bl[0],[]).append((locs[0],U[vi]))
    assert pos==start+size, (s,pos,start,size)
print('parsed skin ok; bones with rigid verts:',len(pairs))
# Procrustes per bone (with scale)
bind={}
for j,pl in pairs.items():
    A=np.array([p[0] for p in pl]); Bv=np.array([p[1] for p in pl])
    if len(A)<4: continue
    ca,cb=A.mean(0),Bv.mean(0); A0,B0=A-ca,Bv-cb
    Um,S,Vt=np.linalg.svd(A0.T@B0); d=np.sign(np.linalg.det(Um@Vt))
    D=np.diag([1,1,d]); R=(Um@D@Vt).T; sc=(S*np.diag(D)).sum()/(A0**2).sum()
    t=cb-sc*R@ca; err=np.abs((sc*(R@A.T)).T+t-Bv).max()
    bind[j]=(R,t,sc,err)
for j in sorted(bind)[:8]: R,t,sc,err=bind[j]; print(j,'scale',round(sc,4),'t',t.round(1),'maxerr',round(err,2),'det',round(np.linalg.det(R),3))
np.save('analysis/bind.npy',{j:(v[0],v[1],v[2]) for j,v in bind.items()},allow_pickle=True)
def qmat(q):
    x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
idx_of={bn[0]:i for i,bn in enumerate(bones)}
res=[]
for enc,layout,wfirst,conj,order in itertools.product(('off','tc'),('msb','lsb'),(False,True),(False,True),('pl','lp')):
    world={}
    for i,(name,parent,qu,p) in enumerate(bones):
        q=quat(qu,enc,layout,wfirst)
        if conj: q=q*np.array([-1,-1,-1,1])
        R=qmat(q)
        if parent in world:
            PR,Pt=world[parent]
            world[name]=((PR@R) if order=='pl' else (R@PR), Pt+PR@(p*0.25))
        else: world[name]=(R,p*0.25)
    err=0;terr=0
    for j,(Rb,tb,sc,_) in bind.items():
        R,t=world[bones[j][0]]
        err+=np.abs(R-Rb).max(); terr+=np.abs(t-tb).max()
    res.append((round(err,3),round(terr,1),enc,layout,wfirst,conj,order))
for r in sorted(res)[:6]: print(r)
