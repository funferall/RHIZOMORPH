"""Coral Binder — stationary Morel Hollow wall organism, roster reference.

Silhouette: a low row of overlapping ivory basal bulbs supporting dense, forked
coral branches, with conspicuous rounded amber tips and short outward barbs.
Each module is repeatable along a growing wall. Mid scale: cream stems, tan
creases at their branching bases, translucent honey-gold terminal beads. Fine:
longitudinal fibres, pores, and minute granular texture; the dark crevices and
light bulb rims distinguish forms at battle scale. Material: matte living flesh,
slightly waxy gold beads, no transparency. Atlas: branch, bead, bulb rects.
UV2 kind 0 static body and 1 flexible branches, weight = height along branch.
The root and wall modules use the same one-surface, three-LOD baked atlas.
"""
import math, os, sys
import bpy
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.getcwd() if os.path.exists('project.godot') else os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from unitlib import export_glb, hide_from_rays, log, save_png, setup_cycles
from paintlib import (PI, TAU, Acc, bake_atlas, cells, mix, pnoise, preview_render, ramp,
                      smooth, surface, sweep, texel_grid, tri_count, tube_points)
ARGS = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OPT = {a.split('=',1)[0].lstrip('-'): (a.split('=',1)[1] if '=' in a else True) for a in ARGS}
OUT = os.path.join(ROOT, 'art/binder'); SIZE = 1024
RECTS = {'stem': (.006,.006,.48,.994), 'bulb': (.49,.006,.70,.994), 'bead': (.71,.006,.994,.994)}
# Nine main arms and nine forks, deterministic geometry only. Every stem shares
# the representative stem's atlas. Group identifies parts but all grow as one.
def branches():
 out=[]
 for i in range(9):
  a=TAU*i/9+.17; r=.29+.08*(i%3); x,z=r*math.cos(a),r*math.sin(a)
  h=.57+.13*(i%4); lean=.38+.07*(i%3)
  p=[(x*.55,.16,z*.55),(x,.42,z),(x+lean*.38*math.cos(a+.20),h*.60,z+lean*.38*math.sin(a+.20)),
     (x+lean*math.cos(a),h,z+lean*math.sin(a))]
  out.append((p,[.082,.067,.040,.024],.055))
  q=p[2]; b=a+(.75 if i%2 else -.8)
  out.append(([(q[0],q[1],q[2]),(q[0]+.09*math.cos(b),q[1]+.10,q[2]+.09*math.sin(b)),
               (q[0]+.23*math.cos(b),q[1]+.24,q[2]+.23*math.sin(b)),
               (q[0]+.30*math.cos(b),q[1]+.30,q[2]+.30*math.sin(b))], [.045,.040,.028,.017],.043))
 return out
BRANCHES=branches(); STEM_PATH, STEM_RAD = BRANCHES[0][0],BRANCHES[0][1]
def barbs():
 out=[]
 for i in range(0, len(BRANCHES), 3):
  p=BRANCHES[i][0]; q=p[2]; a=math.atan2(q[2],q[0])+.32
  out.append(([(q[0],q[1],q[2]),(q[0]+.10*math.cos(a),q[1]+.04,q[2]+.10*math.sin(a)),
               (q[0]+.24*math.cos(a),q[1]+.11,q[2]+.24*math.sin(a))],[.032,.022,.001]))
 return out
BARBS=barbs()
BULBS=[((.26*math.cos(TAU*i/9),.12,.26*math.sin(TAU*i/9)),(.16,.14,.15)) for i in range(9)]
def ball_fn(c,r):
 c=np.array(c); r=np.array(r)
 def fn(a,t):
  th=PI*t; n=np.stack((np.sin(th)*np.cos(a),-np.cos(th),np.sin(th)*np.sin(a)),axis=-1)
  return c+n*r,None
 return fn
BULB_C,BULB_R=BULBS[0]; BEAD_C=BRANCHES[0][0][-1]; BEAD_R=(.055,.059,.055)
def stem_relief(t,a,P):
 # Folds run along the stem; speckles are sized in space, not atlas pixels.
 fibre=pnoise(P*np.array([24.,4.,24.]),1.,3)
 grooves=smooth(.11,.015,np.abs(fibre))
 return -.0012*grooves+.0007*pnoise(P,75.)
def bulb_relief(a,t,P):
 d,_,_=cells(P,.042); return -.0025*smooth(.42,.10,d)+.0007*pnoise(P,70.)
def bead_relief(a,t,P): return .0008*pnoise(P,65.)
def stem(acc,path,radii,sides,samples,detail=False):
 sweep(acc,path,radii,sides,samples,RECTS['stem'],1,0,lambda t:t,relief=stem_relief if detail else None)
def ball(acc,c,r,rect,kind,rows,cols,relief=None,group=0):
 surface(acc,ball_fn(c,r),c,rows,cols,rect,kind,group=group,relief=relief)
def build_lod(lod):
 acc=Acc(); sr,sc=[(8,15),(5,9),(3,5)][lod]; br,bc=[(8,12),(5,8),(3,5)][lod]
 for c,r in BULBS: ball(acc,c,r,RECTS['bulb'],0,br,bc)
 for i,(p,r,sz) in enumerate(BRANCHES):
  if lod == 2 and sz < .05: continue
  stem(acc,p,r,sr,sc)
  ball(acc,p[-1],(sz,sz*1.06,sz),RECTS['bead'],2,br,bc,group=i)
 # Distant LOD omits fork branches; retain only barbs on surviving main arms.
 for path,radii in (BARBS if lod < 2 else BARBS[::2]): stem(acc,path,radii,*[(5,6),(3,4),(3,4)][lod])
 return acc
def paint(size):
 albedo=np.zeros((size,size,3)); orm=np.ones((size,size,4)); orm[...,1]=.8; orm[...,2]=0
 sl,u,v=texel_grid(RECTS['stem'],size); P=tube_points(STEM_PATH,STEM_RAD,u,v)
 n=pnoise(P,7.,3); fibre=smooth(.11,.015,np.abs(pnoise(P*np.array([24.,4.,24.]),1.,3)))
 base=ramp([(0,(.38,.22,.13)),(.45,(.73,.57,.36)),(1,(.97,.90,.72))],np.clip(.70+n*.45+.18*v,0,1))
 albedo[sl]=mix(base,(.48,.30,.15),fibre*.12); orm[sl+(1,)]=np.clip(.76+.10*n+.06*fibre,.58,.96)
 sl,u,v=texel_grid(RECTS['bulb'],size); P,_=ball_fn(BULB_C,BULB_R)(u*TAU-PI,v)
 n=pnoise(P,9.,3); d,_,cid=cells(P,.042); spots=smooth(.38,.10,d)*(.6+.4*cid)
 base=ramp([(0,(.51,.35,.22)),(.5,(.82,.70,.52)),(1,(.98,.92,.78))],np.clip(.72+n*.5,0,1))
 albedo[sl]=mix(base,(.58,.37,.19),spots*.35); orm[sl+(1,)]=np.clip(.80+.10*n+.05*spots,.60,.96)
 sl,u,v=texel_grid(RECTS['bead'],size); P,_=ball_fn(BEAD_C,BEAD_R)(u*TAU-PI,v)
 n=pnoise(P,12.,3); grain=pnoise(P,52.)
 albedo[sl]=ramp([(0,(.50,.23,.025)),(.38,(.85,.46,.035)),(.72,(1.,.72,.14)),(1,(1.,.94,.52))],np.clip(.70+.38*n+.08*grain-.30*v,0,1))
 orm[sl+(1,)]=np.clip(.28+.10*n,.16,.48); orm[sl+(2,)]=.1
 return albedo,orm
def main():
 os.makedirs(OUT,exist_ok=True); bpy.ops.wm.read_factory_settings(use_empty=True); setup_cycles('binder',bool(OPT.get('cpu')),ao_distance=.10)
 hi={};lo={}
 a=Acc(); stem(a,STEM_PATH,STEM_RAD,260,320,True); hi['stem']=a.obj('hi_stem')
 a=Acc(); ball(a,BULB_C,BULB_R,RECTS['bulb'],0,280,360,bulb_relief); hi['bulb']=a.obj('hi_bulb')
 a=Acc(); ball(a,BEAD_C,BEAD_R,RECTS['bead'],1,220,300,bead_relief); hi['bead']=a.obj('hi_bead')
 a=Acc(); stem(a,STEM_PATH,STEM_RAD,40,100); lo['stem']=a.obj('lo_stem')
 a=Acc(); ball(a,BULB_C,BULB_R,RECTS['bulb'],0,70,120); lo['bulb']=a.obj('lo_bulb')
 a=Acc(); ball(a,BEAD_C,BEAD_R,RECTS['bead'],1,60,100); lo['bead']=a.obj('lo_bead')
 for ob in lo.values(): hide_from_rays(ob)
 others=[]
 for p,r,sz in BRANCHES[1:]:
  a=Acc(); stem(a,p,r,10,24); others.append(a.obj('ao_stem'))
 for path,radii in BARBS:
  a=Acc(); stem(a,path,radii,6,12); others.append(a.obj('ao_barb'))
 for c,r in BULBS[1:]:
  a=Acc(); ball(a,c,r,RECTS['bulb'],0,8,12); others.append(a.obj('ao_bulb'))
 all_hi=list(hi.values())+others
 parts={n:{'low':lo[n],'normal_from':[hi[n]],'ao_from':all_hi,'reach':(.004,.009),'poles':(.03,.97)} for n in lo}
 normal,ao,u,v,masks=bake_atlas(parts,RECTS,SIZE,'binder'); albedo,orm=paint(SIZE); orm[...,0]=ao
 alb=np.ones((SIZE,SIZE,4),np.float32); alb[...,:3]=albedo
 for name,img,linear in [('albedo',alb,False),('normal',normal,True),('orm',orm.astype(np.float32),True)]: save_png(os.path.join(OUT,'binder_'+name+'.png'),img,linear)
 for ob in all_hi+list(lo.values()): bpy.data.objects.remove(ob,do_unlink=True)
 for lod,name in enumerate(('close','battle','distant')):
  ob=build_lod(lod).obj('Binder_'+name); log('binder','%s %d triangles'%(name,tri_count(ob))); export_glb([ob],os.path.join(OUT,'binder_'+name+'.glb'))
if OPT.get('mesh-only'):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 for lod,name in enumerate(('close','battle','distant')):
  ob=build_lod(lod).obj('Binder_'+name); log('binder','%s %d triangles'%(name,tri_count(ob))); export_glb([ob],os.path.join(OUT,'binder_'+name+'.glb'))
elif OPT.get('preview'):
 bpy.ops.wm.read_factory_settings(use_empty=True); ob=build_lod(0).obj('preview'); ob.color=(.85,.78,.62,1)
 preview_render([ob],os.path.abspath(OPT['preview']),target=(0,.6,0),scale=2.3)
else: main()
