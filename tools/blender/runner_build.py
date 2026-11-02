"""Candlesnuff Runner — Xylaria hypoxylon scout, roster reference.

Silhouette: a low, crooked charcoal root body on four sprawling pointed arms, with
five conspicuous antler-like fingers rising from its back. Mid scale: forked,
wrinkled black wood-like clubs with powder-white tips. Fine scale: longitudinal
fissures, tiny ashy granules. Material: dry, matte charcoal and chalky conidia.
Parts: one body rect and one shared branch rect. Data UV kind 0 body, 1 ground
arms, 2 upright clubs; weight rises along each branch. Shared branch atlas is
baked from a representative arm. Close/battle/distant use the same functions.
"""
import math, os, sys
import bpy
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.getcwd()
sys.path.insert(0, HERE)
from unitlib import export_glb, hide_from_rays, log, save_png, setup_cycles
from paintlib import (PI, TAU, Acc, bake_atlas, mix, pnoise, preview_render, ramp,
                      smooth, surface, sweep, texel_grid, tri_count, tube_points)
ARGS = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OPT = {a.split('=',1)[0].lstrip('-'): (a.split('=',1)[1] if '=' in a else True) for a in ARGS}
OUT = os.path.join(ROOT, 'art/runner')
SIZE = 1024
RECTS = {'body': (.006,.006,.40,.994), 'branch': (.41,.006,.994,.994)}
BODY_C = np.array([0., .43, 0.])
# The two X arms bear the established rocking gait. Two transverse arms make
# the low four-point stance; the dark upward clubs are exaggerated for RTS view.
ARMS = [
 [(-.08,.44,0),(-.34,.43,-.12),(-.68,.35,-.20),(-.93,.055,-.25)],
 [( .08,.44,0),( .33,.50, .12),( .67,.25, .22),( .96,.055, .26)],
 [(-.06,.43,0),(-.26,.43,-.31),(-.42,.22,-.49),(-.57,.045,-.66)],
 [( .04,.44,0),( .27,.43, .31),( .42,.22, .49),( .57,.045, .66)],
]
CLUBS = [
 [(-.15,.47,-.05),(-.30,.72,-.09),(-.39,.94,-.11),(-.35,1.17,-.12)],
 [(-.08,.49, .03),(-.02,.71, .04),(-.07,1.01,.03),(-.03,1.34,.03)],
 [( .09,.47, .02),( .22,.69, .04),( .34,.89,.08),( .46,1.09,.12)],
 [( .02,.48,-.06),( .21,.63,-.16),( .45,.78,-.25),( .66,.94,-.32)],
 [(-.02,.47, .07),(-.23,.63, .20),(-.42,.76,.31),(-.58,.89,.42)],
]
ARM_R = [.095,.075,.055,.045]
CLUB_R = [.085,.068,.052,.045]
FORKS = [
 [(-.28,.70,-.09),(-.42,.84,-.13),(-.50,1.00,-.15),(-.51,1.10,-.15)],
 [(.24,.72,.04),(.38,.85,.03),(.48,1.00,.01),(.49,1.10,.01)],
 [(-.02,.71,.04),(.08,.86,.10),(.11,1.02,.12),(.13,1.13,.12)],
]
FORK_R = [.055,.05,.042,.035]
def rounded(t): return .015 + .985 * smooth(1.0,.91,t)**.5
def body_point(a,t):
 th=PI*t
 r=np.sin(th)
 return BODY_C + np.stack((.25*r*np.cos(a), -.14*np.cos(th), .20*r*np.sin(a)),axis=-1), None
def relief(a,t,P):
 # Deep, narrow fissures run along the living branch axis; smooth 3D noise
 # gives the bark-shaped furrows physical scale, not atlas-sized noise.
 q=P*np.array([18.,5.,18.])
 crack=smooth(.09,.015,np.abs(pnoise(q,1.,2)))
 return -.0035*crack+.0015*pnoise(P,60.)
def branch_relief(t,a,P):
 return relief(a,t,P)
def body(acc,rows,cols,detail=False):
 surface(acc,body_point,BODY_C,rows,cols,RECTS['body'],0,relief=relief if detail else None)
def branch(acc,path,radii,sides,samples,kind,detail=False,group=0):
 sweep(acc,path,radii,sides,samples,RECTS['branch'],kind,group,lambda t:t,relief=branch_relief if detail else None,radius_fn=rounded)
def build_lod(lod):
 a=Acc(); body(a,*[(16,24),(10,16),(6,10)][lod])
 sides,samples=[(9,20),(6,11),(4,6)][lod]
 for i,path in enumerate(ARMS): branch(a,path,ARM_R,sides,samples,1,group=(0,1,1,0)[i])
 for path in CLUBS: branch(a,path,CLUB_R,sides,samples,2)
 for path in FORKS: branch(a,path,FORK_R,sides,samples,2)
 return a
def paint(size):
 albedo=np.zeros((size,size,3)); orm=np.ones((size,size,4)); orm[...,1]=.82; orm[...,2]=0
 sl,u,v=texel_grid(RECTS['body'],size); P,_=body_point(u*TAU-PI,v)
 n=pnoise(P,7.,3); fiss=smooth(.09,.015,np.abs(pnoise(P*np.array([18.,5.,18.]),1.,2)))
 albedo[sl]=mix(ramp([(0,(.025,.022,.025)),(1,(.20,.16,.13))],np.clip(.48+n*.5,0,1)),(.025,.019,.019),fiss*.7)
 orm[sl+(1,)]=np.clip(.78+.12*n+.08*fiss,.6,.95)
 sl,u,v=texel_grid(RECTS['branch'],size); P=tube_points(ARMS[0],ARM_R,u,v,radius_fn=rounded)
 n=pnoise(P,8.,3); crack=smooth(.09,.015,np.abs(pnoise(P*np.array([18.,5.,18.]),1.,2)))
 dark=ramp([(0,(.025,.022,.026)),(.5,(.105,.084,.073)),(1,(.23,.19,.15))],np.clip(.48+n*.55,0,1))
 dark=mix(dark,(.018,.016,.019),crack*.75)
 # Conidia coat the distal ends, with an irregular boundary following the bark.
 tip=smooth(.75,.84,v+.035*pnoise(P,17.,2))
 pale=ramp([(0,(.57,.52,.43)),(1,(.97,.95,.87))],np.clip(.7+.4*n,0,1))
 albedo[sl]=mix(dark,pale,tip)
 orm[sl+(1,)]=np.clip(.73+.16*tip+.09*n+.06*crack,.55,.97)
 return albedo,orm
def main():
 os.makedirs(OUT,exist_ok=True); bpy.ops.wm.read_factory_settings(use_empty=True)
 setup_cycles('runner',bool(OPT.get('cpu')),ao_distance=.12)
 hi={}; lo={}
 a=Acc(); body(a,360,720,True); hi['body']=a.obj('hi_body')
 a=Acc(); branch(a,ARMS[0],ARM_R,240,320,1,True); hi['branch']=a.obj('hi_branch')
 a=Acc(); body(a,100,200); lo['body']=a.obj('lo_body')
 a=Acc(); branch(a,ARMS[0],ARM_R,40,100,1); lo['branch']=a.obj('lo_branch')
 for ob in lo.values(): hide_from_rays(ob)
 others=[]
 for p in ARMS[1:]+CLUBS+FORKS:
  a=Acc(); branch(a,p,ARM_R if p in ARMS else (CLUB_R if p in CLUBS else FORK_R),10,25,1); others.append(a.obj('ao_branch'))
 parts={n:{'low':lo[n],'normal_from':[hi[n]],'ao_from':list(hi.values())+others,
           'reach':(.012,.025),'poles':(.03,.97)} for n in lo}
 normal,ao,u,v,masks=bake_atlas(parts,RECTS,SIZE,'runner')
 albedo,orm=paint(SIZE); orm[...,0]=ao
 alb=np.ones((SIZE,SIZE,4),np.float32); alb[...,:3]=albedo
 save_png(os.path.join(OUT,'runner_albedo.png'),alb,False)
 save_png(os.path.join(OUT,'runner_normal.png'),normal,True)
 save_png(os.path.join(OUT,'runner_orm.png'),orm.astype(np.float32),True)
 for ob in list(hi.values())+list(lo.values())+others: bpy.data.objects.remove(ob,do_unlink=True)
 for lod,name in enumerate(('close','battle','distant')):
  ob=build_lod(lod).obj('Runner_'+name); log('runner','%s %d triangles'%(name,tri_count(ob)))
  export_glb([ob],os.path.join(OUT,'runner_'+name+'.glb'))
if OPT.get('mesh-only'):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 for lod,name in enumerate(('close','battle','distant')):
  ob=build_lod(lod).obj('Runner_'+name); log('runner','%s %d triangles'%(name,tri_count(ob))); export_glb([ob],os.path.join(OUT,'runner_'+name+'.glb'))
elif OPT.get('preview'):
 bpy.ops.wm.read_factory_settings(use_empty=True); ob=build_lod(0).obj('preview'); ob.color=(.16,.13,.12,1.)
 preview_render([ob],os.path.abspath(OPT['preview']),target=(0,.58,0),scale=2.5)
else: main()
