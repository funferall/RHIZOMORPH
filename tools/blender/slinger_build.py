"""Elf-cup Slinger (Sarcoscypha), Morel Hollow roster.
Silhouette: broad, tilted goblet with an open red bowl and four curled pale
root-like supports. Mid: scarlet interior, thick cream rim, ochre flecks on
outer skin, fleshy curling feet. Fine: fine radial cup wrinkles, pores and
fibres. Material: moist satin red hymenium, matte fibrous cream exterior.
Parts/UV: cup and shared support rect; cup kind 0, support kind 2 with group
alternating by side and weight toward the tips. One 1024 atlas, three LODs.
"""
import os,sys
import bpy
import numpy as np
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.getcwd(); sys.path.insert(0,HERE)
from unitlib import export_glb,hide_from_rays,log,save_png,setup_cycles
from paintlib import PI,TAU,Acc,bake_atlas,cells,mix,pnoise,preview_render,ramp,smooth,surface,sweep,texel_grid,tri_count,tube_points
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OPT={a.split('=',1)[0].lstrip('-'):(a.split('=',1)[1] if '=' in a else True) for a in ARGS}
OUT=os.path.join(ROOT,'art/slinger'); SIZE=1024
RECTS={'cup':(.006,.31,.994,.994),'leg':(.006,.006,.994,.30)}
C=np.array([0.,.91,0.]); PATHS=[]
for side in (-1,1):
 for dx in (-1,1):
  PATHS.append([(dx*.06,.62,side*.05),(dx*.22,.37,side*.17),(dx*.43,.13,side*.34),(dx*.65,.09,side*.46),(dx*.70,.23,side*.49),(dx*.58,.32,side*.45)])
RAD=[.12,.105,.09,.055,.03,.004]
def cup_point(a,t):
 # t goes from exterior base, round the rolled lip, to the inner bottom.
 phi=PI*t; r=np.sin(phi)**.58
 x=.72*r*np.cos(a); z=.52*r*np.sin(a)
 outer=smooth(.51,.46,t)
 y=np.where(t<.5,.60+.64*r*r, .78+.46*r*r)
 y=y-.36*(.64*x+.77*z) + .018*np.sin(3*a+.5)*r + .018*np.sin(2*PI*(t-.5))*np.exp(-((t-.5)/.05)**2)
 return np.stack([x,y,z],axis=-1),None
def cup_relief(a,t,P):
 inner=smooth(.48,.53,t); lip=np.exp(-((t-.5)/.032)**2)
 radial=.002*np.sin(a*48+2*pnoise(P,8.,2))*smooth(.57,.75,t)*(1-smooth(.96,1.,t))
 return (inner*radial+.0008*pnoise(P,45.))*(1.-np.exp(-((t-.5)/.055)**2))
def leg_relief(t,a,P):
 d,_,_=cells(P,.065); return .002*smooth(.42,.1,d)+.001*pnoise(P,50.)
def cup(acc,r,c,detail=False): surface(acc,cup_point,C,r,c,RECTS['cup'],0,relief=cup_relief if detail else None)
def leg(acc,path,side,samples,group=0,detail=False):
 sweep(acc,path,RAD,side,samples,RECTS['leg'],2,group,lambda t:t,relief=leg_relief if detail else None)
def build_lod(lod):
 a=Acc(); cup(a,*[(28,48),(16,28),(8,16)][lod])
 side,samples=[(9,24),(6,14),(4,7)][lod]
 for i,p in enumerate(PATHS): leg(a,p,side,samples,i%2)
 return a
def paint(size):
 albedo=np.zeros((size,size,3)); orm=np.ones((size,size,4)); orm[...,1]=.75; orm[...,2]=0
 sl,u,v=texel_grid(RECTS['cup'],size); a=u*TAU-PI; P,_=cup_point(a,v)
 n=pnoise(P,8.,3); fine=pnoise(P,36.); inner=smooth(.49,.52,v)
 d,_,cid=cells(P,.07); flecks=smooth(.27,.10,d+.08*pnoise(P,18.,2))*smooth(.25,.85,cid)
 outer=ramp([(0,(.40,.23,.13)),(.45,(.76,.64,.48)),(1,(.98,.91,.75))],np.clip(.63+n*.5,0,1))
 outer=mix(outer,(.50,.24,.12),flecks*.7)
 folds=.5+.5*np.sin(a*48+2*pnoise(P,8.,2))
 red=ramp([(0,(.25,.012,.016)),(.5,(.68,.025,.025)),(1,(.95,.13,.075))],np.clip(.55+.25*n+.15*folds,0,1))
 red=mix(red,(.99,.79,.53),np.exp(-((v-.5)/.018)**2)*.75)
 albedo[sl]=mix(mix(outer,red,inner),(.96,.85,.69),np.exp(-((v-.50)/.025)**2)*.88); orm[sl+(1,)]=np.clip(.79-.43*inner+.08*n+.05*fine,.22,.95)
 sl,u,v=texel_grid(RECTS['leg'],size); P=tube_points(PATHS[0],RAD,u,v)
 n=pnoise(P,8.,3); d,_,cid=cells(P,.065); spots=smooth(.42,.1,d)*smooth(.15,.8,cid)
 base=ramp([(0,(.43,.29,.20)),(.55,(.78,.67,.53)),(1,(.98,.91,.78))],np.clip(.65+.5*n,0,1))
 albedo[sl]=mix(base,(.54,.25,.15),spots*.55); orm[sl+(1,)]=np.clip(.80+.08*n+.04*spots,.62,.96)
 return albedo,orm
def main():
 os.makedirs(OUT,exist_ok=True); bpy.ops.wm.read_factory_settings(use_empty=True); setup_cycles('slinger',bool(OPT.get('cpu')),ao_distance=.14)
 hi={}; lo={}
 a=Acc(); cup(a,400,800,True); hi['cup']=a.obj('hi_cup')
 a=Acc(); leg(a,PATHS[0],220,320,detail=True); hi['leg']=a.obj('hi_leg')
 a=Acc(); cup(a,120,240); lo['cup']=a.obj('lo_cup')
 a=Acc(); leg(a,PATHS[0],40,100); lo['leg']=a.obj('lo_leg')
 for ob in lo.values(): hide_from_rays(ob)
 others=[]
 for p in PATHS[1:]:
  a=Acc(); leg(a,p,12,32); others.append(a.obj('ao_leg'))
 parts={n:{'low':lo[n],'normal_from':[hi[n]],'ao_from':list(hi.values())+others,'reach':((.002,.004) if n == 'cup' else (.0015,.003)),'poles':(.03,.97)} for n in lo}
 normal,ao,u,v,masks=bake_atlas(parts,RECTS,SIZE,'slinger'); albedo,orm=paint(SIZE); orm[...,0]=ao
 alb=np.ones((SIZE,SIZE,4),np.float32); alb[...,:3]=albedo
 for name,img,linear in [('albedo',alb,False),('normal',normal,True),('orm',orm.astype(np.float32),True)]: save_png(os.path.join(OUT,'slinger_'+name+'.png'),img,linear)
 for ob in list(hi.values())+list(lo.values())+others: bpy.data.objects.remove(ob,do_unlink=True)
 for lod,name in enumerate(('close','battle','distant')):
  ob=build_lod(lod).obj('Slinger_'+name); log('slinger','%s %d triangles'%(name,tri_count(ob))); export_glb([ob],os.path.join(OUT,'slinger_'+name+'.glb'))
if OPT.get('preview'):
 bpy.ops.wm.read_factory_settings(use_empty=True); ob=build_lod(0).obj('preview'); ob.color=(.8,.56,.43,1)
 preview_render([ob],os.path.abspath(OPT['preview']),target=(0,.7,0),scale=2.35)
else: main()
