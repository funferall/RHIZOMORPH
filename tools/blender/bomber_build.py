"""Puffball Bomber, Morel Hollow roster, puffball (Lycoperdon) fruitbody.
Silhouette: large round pear-shaped cream spore sac with a short dark vent at
the raised front and four squat, splayed feet. Mid: irregular tan warts on the
sac, ringed stout legs, dark opening. Fine: pores and powder. Material: dry,
matte fungal skin, a dark fibrous vent. Body and shared leg have separate atlas
rects; UV2 kind 0 body/vent and kind 1 legs with alternating side groups and
weights from shoulder to foot, matching the established recoil and walk.
"""
import os,sys
import bpy
import numpy as np
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.getcwd(); sys.path.insert(0,HERE)
from unitlib import export_glb,hide_from_rays,log,save_png,setup_cycles
from paintlib import PI,TAU,Acc,bake_atlas,cells,ellipsoid,mix,pnoise,preview_render,ramp,smooth,surface,sweep,texel_grid,tri_count,tube_points
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OPT={a.split('=',1)[0].lstrip('-'):(a.split('=',1)[1] if '=' in a else True) for a in ARGS}
OUT=os.path.join(ROOT,'art/bomber'); SIZE=1024
RECTS={'body':(.006,.34,.994,.994),'leg':(.006,.006,.75,.33),'vent':(.76,.006,.994,.15),'toe':(.76,.16,.994,.33)}
C=np.array([0.,1.05,0.]); PATHS=[]
for side in (-1,1):
 for dx in (-1,1):
  PATHS.append([(dx*.36,.92,side*.32),(dx*.49,.65,side*.40),(dx*.58,.31,side*.48),(dx*.70,.09,side*.55)])
RAD=[.23,.24,.21,.13]
VENT=[(.30,1.57,0),(.39,1.69,0),(.43,1.76,0)]
VR=[.085,.075,.05]
def body_point(a,t):
 th=PI*t; r=np.sin(th)**.9
 return C+np.stack([.72*r*np.cos(a),-.69*np.cos(th),.61*r*np.sin(a)],axis=-1),None
def body_relief(a,t,P):
 d,_,cid=cells(P,.085); w=smooth(.40,.06,d)*(.5+.5*cid)
 return .015*w+.002*pnoise(P,55.)
def leg_radius(t): return 1.+.055*np.sin(t*PI*6.)**2
def leg_relief(t,a,P): return -.006*np.exp(-(np.sin(t*PI*6.)/.13)**2)+.002*pnoise(P,45.)
def body(acc,r,c,detail=False): surface(acc,body_point,C,r,c,RECTS['body'],0,relief=body_relief if detail else None)
def leg(acc,p,s,n,g=0,detail=False): sweep(acc,p,RAD,s,n,RECTS['leg'],1,g,lambda t:t,relief=leg_relief if detail else None,radius_fn=leg_radius)
def vent(acc,s,n): sweep(acc,VENT,VR,s,n,RECTS['vent'],0,0,lambda t:t*0)
def build_lod(lod):
 a=Acc(); body(a,*[(28,48),(16,28),(8,16)][lod]); s,n=[(10,20),(6,12),(4,6)][lod]
 for i,p in enumerate(PATHS):
  leg(a,p,s,n,i%2)
  x,y,z=p[-1]; dx=1 if x>0 else -1
  for off in (-.10,0,.10):
   sweep(a,[(x-.05*dx,.11,z+off),(x+.10*dx,.08,z+off),(x+.19*dx,.07,z+off)],[.12,.10,.01],s,max(3,n//3),RECTS["toe"],1,i%2,lambda t:t*0+1)
 vent(a,*[(10,8),(6,5),(4,3)][lod]); ellipsoid(a,(.43,1.76,0),(.055,.055,.055),0,0,RECTS["vent"],*[ (8,12),(6,8),(4,6) ][lod]); return a
def paint(size):
 albedo=np.zeros((size,size,3)); orm=np.ones((size,size,4)); orm[...,1]=.82; orm[...,2]=0
 sl,u,v=texel_grid(RECTS['body'],size); P,_=body_point(u*TAU-PI,v)
 n=pnoise(P,5.,3); d,_,cid=cells(P,.085); wart=smooth(.40,.06,d)*(.5+.5*cid)
 base=ramp([(0,(.48,.35,.22)),(.5,(.78,.67,.49)),(1,(.98,.92,.78))],np.clip(.72+.5*n,0,1))
 albedo[sl]=mix(base,(.48,.32,.18),wart*.65); orm[sl+(1,)]=np.clip(.82+.08*n+.06*wart,.65,.96)
 sl,u,v=texel_grid(RECTS['leg'],size); P=tube_points(PATHS[0],RAD,u,v,radius_fn=leg_radius)
 n=pnoise(P,7.,3); crease=np.exp(-(np.sin(v*PI*6.)/.13)**2)
 base=ramp([(0,(.48,.34,.22)),(1,(.97,.89,.72))],np.clip(.72+.5*n,0,1))
 albedo[sl]=mix(base,(.57,.43,.29),crease*.28); orm[sl+(1,)]=np.clip(.78+.08*n+.10*crease,.6,.96)
 sl,u,v=texel_grid(RECTS['toe'],size); P=tube_points([(0,0,0),(.1,0,0),(.2,0,0)],[.10,.085,.003],u,v); n=pnoise(P,12.,2)
 albedo[sl]=ramp([(0,(.54,.39,.25)),(1,(.98,.90,.76))],np.clip(.7+.5*n,0,1)); orm[sl+(1,)]=np.clip(.80+.08*n,.65,.95)
 sl,u,v=texel_grid(RECTS['vent'],size); P=tube_points(VENT,VR,u,v); n=pnoise(P,18.,2)
 albedo[sl]=ramp([(0,(.07,.035,.02)),(1,(.42,.29,.17))],np.clip(.65+.4*n-.55*smooth(.75,1.,v),0,1)); orm[sl+(1,)]=.7+.12*smooth(.7,1.,v)
 return albedo,orm
def main():
 os.makedirs(OUT,exist_ok=True); bpy.ops.wm.read_factory_settings(use_empty=True); setup_cycles('bomber',bool(OPT.get('cpu')),ao_distance=.14)
 hi={}; lo={}
 a=Acc(); body(a,400,800,True); hi['body']=a.obj('hi_body')
 a=Acc(); leg(a,PATHS[0],220,320,detail=True); hi['leg']=a.obj('hi_leg')
 a=Acc(); body(a,120,240); lo['body']=a.obj('lo_body')
 a=Acc(); leg(a,PATHS[0],40,100); lo['leg']=a.obj('lo_leg')
 for ob in lo.values(): hide_from_rays(ob)
 others=[]
 for p in PATHS[1:]:
  a=Acc(); leg(a,p,12,32); others.append(a.obj('ao_leg'))
 parts={n:{'low':lo[n],'normal_from':[hi[n]],'ao_from':list(hi.values())+others,'reach':(.02,.035),'poles':(.03,.97)} for n in lo}
 normal,ao,u,v,masks=bake_atlas(parts,RECTS,SIZE,'bomber'); albedo,orm=paint(SIZE); orm[...,0]=ao
 alb=np.ones((SIZE,SIZE,4),np.float32); alb[...,:3]=albedo
 for name,img,linear in [('albedo',alb,False),('normal',normal,True),('orm',orm.astype(np.float32),True)]: save_png(os.path.join(OUT,'bomber_'+name+'.png'),img,linear)
 for ob in list(hi.values())+list(lo.values())+others: bpy.data.objects.remove(ob,do_unlink=True)
 for lod,name in enumerate(('close','battle','distant')):
  ob=build_lod(lod).obj('Bomber_'+name); log('bomber','%s %d triangles'%(name,tri_count(ob))); export_glb([ob],os.path.join(OUT,'bomber_'+name+'.glb'))
if OPT.get('preview'):
 bpy.ops.wm.read_factory_settings(use_empty=True); ob=build_lod(0).obj('preview'); ob.color=(.8,.7,.55,1)
 preview_render([ob],os.path.abspath(OPT['preview']),target=(0,.85,0),scale=2.5)
else: main()
