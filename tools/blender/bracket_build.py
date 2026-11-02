"""Rot Bracket â€” turkey tail (Trametes versicolor) on decaying wood.
Silhouette: a low rotten stump bearing overlapping thin fan-shaped shelves,
with waved, pale margins. Mid: concentric velvet bands of slate, rust, tan,
and cream radiate from each shelf's attachment; bark splits lengthwise. Fine:
pore surface under each shelf, subtle velvety radial fibres above, bark grain.
Materials: dry matte velvet and pale pores over rough weathered wood. Atlas:
one large repeated shelf rect and one stump rect; static single-surface mesh.
"""
import os,sys,math
import bpy
import numpy as np
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.getcwd(); sys.path.insert(0,HERE)
from unitlib import export_glb,hide_from_rays,log,save_png,setup_cycles
from paintlib import PI,TAU,Acc,bake_atlas,cells,mix,pnoise,preview_render,ramp,smooth,surface,sweep,texel_grid,tri_count,tube_points
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OPT={a.split('=',1)[0].lstrip('-'):(a.split('=',1)[1] if '=' in a else True) for a in ARGS}
OUT=os.path.join(ROOT,'art/bracket'); SIZE=1024
RECTS={'fan':(.006,.32,.994,.994),'wood':(.006,.006,.994,.31)}
WOOD=[(0.,0.,0.),(.02,.32,0.),(-.02,.70,.02),(0.,1.05,0.)]; WR=[.48,.46,.41,.32]
FANS=[((-.25,.32,-.08),1.15,3.4),((.22,.38,.02),1.15,.05),((0,.61,-.23),1.05,4.9),
      ((-.22,.78,.12),1.03,2.5),((.20,.91,.12),.94,.5),((-.10,1.08,-.08),.83,4.),((.12,1.24,.03),.70,1.3), ((-.18,.50,.18),.72,2.0), ((.16,.66,-.12),.82,5.6)]
def fan_local(a,t):
 # Disk tangent to the origin. Its radial coordinate is measured from the
 # attachment, so all colour bands remain concentric around the root.
 phi=PI*t; r=np.sin(phi)**.65; ca=np.cos(a/2); sa=np.sin(a/2)
 wave=1+.045*np.sin(5*a+.4)+.015*np.sin(9*a-.6)
 x=r*ca*ca*wave; z=r*ca*sa*1.35*wave
 top=smooth(.48,.52,t)
 y=(.015+.09*(1-r))*(2*top-1)+.012*r*np.sin(5*a+.4)
 return np.stack([x,y,z],axis=-1),None
def fan_fn(at,scale,ang):
 c,s=math.cos(ang),math.sin(ang)
 def fn(a,t):
  P,_=fan_local(a,t); x,z=P[...,0],P[...,2]; x=x*(1+.04*np.sin(3*a+ang)); z=z*(1+.05*np.sin(4*a+ang))
  return np.stack([at[0]+scale*(x*c-z*s),at[1]+scale*P[...,1],at[2]+scale*(x*s+z*c)],axis=-1),None
 return fn
def fan_relief(a,t,P):
 under=smooth(.48,.45,t); d,_,_=cells(P,.018)
 pores=-.0035*smooth(.40,.12,d)*under
 fib=.0017*np.sin(a*90+2*pnoise(P,9.,2))*(1-under)
 return (pores+fib+.001*pnoise(P,55.))*(1.-np.exp(-((t-.5)/.06)**2))
def wood_point(a,t):
 r=(.49-.16*t)*(1+.09*np.sin(5*a+1.4)+.04*np.sin(9*a+3*t))
 return np.stack([r*np.cos(a)+.035*np.sin(t*4),1.05*t,r*np.sin(a)],axis=-1),None
def wood_relief(a,t,P): return -.008*smooth(.08,.01,np.abs(pnoise(P*np.array([15.,2.,15.]),1.,2)))+.002*pnoise(P,55.)
def fan(acc,at,scale,ang,r,c,detail=False):
 surface(acc,fan_fn(at,scale,ang),np.array(at),r,c,RECTS['fan'],0,relief=fan_relief if detail else None)
def wood(acc,s,n,detail=False): surface(acc,wood_point,(0,.5,0),n,s,RECTS['wood'],1,relief=wood_relief if detail else None)
def build():
 a=Acc(); wood(a,20,18)
 for at,scale,ang in FANS: fan(a,at,scale,ang,16,52)
 return a
def paint(size):
 albedo=np.zeros((size,size,3)); orm=np.ones((size,size,4)); orm[...,1]=.85; orm[...,2]=0
 sl,u,v=texel_grid(RECTS['fan'],size); a=u*TAU-PI; P,_=fan_fn(*FANS[0])(a,v); r=np.sin(PI*v)**.65
 n=pnoise(P,8.,3); under=smooth(.48,.45,v); bands=np.clip(r+.035*pnoise(P,3.,2)+.012*np.sin(a*4),0,1)
 col=ramp([(0,(.19,.15,.13)),(.12,(.42,.22,.16)),(.21,(.70,.49,.33)),(.28,(.24,.27,.29)),(.39,(.34,.36,.36)),(.46,(.66,.40,.27)),(.53,(.81,.67,.48)),(.59,(.24,.25,.27)),(.70,(.35,.37,.37)),(.78,(.57,.29,.20)),(.87,(.74,.55,.38)),(.96,(.90,.83,.69)),(1,(.97,.93,.80))],bands)
 stripe=.5+.5*np.sin(r*80+2*pnoise(P,4.,2)); col=col*(.85+.15*stripe[...,None]); col=mix(col,(.82,.70,.55),smooth(.94,.99,stripe)*.12)
 col=mix(col,(.97,.93,.80),smooth(.94,.995,r))
 d,_,cid=cells(P,.018); pores=mix((.87,.82,.68),(.62,.54,.42),smooth(.42,.1,d)*.55)
 albedo[sl]=mix(col,pores,under); orm[sl+(1,)]=np.clip(.84+.08*n+.06*under,.68,.98)
 sl,u,v=texel_grid(RECTS['wood'],size); P,_=wood_point(u*TAU-PI,v); n=pnoise(P,5.,3)
 crack=smooth(.08,.01,np.abs(pnoise(P*np.array([15.,2.,15.]),1.,2)))
 base=ramp([(0,(.10,.07,.05)),(.5,(.29,.19,.12)),(1,(.55,.40,.25))],np.clip(.50+.6*n,0,1))
 albedo[sl]=mix(base,(.055,.035,.025),crack*.8); orm[sl+(1,)]=np.clip(.77+.14*crack+.06*n,.62,.98)
 return albedo,orm
def main():
 os.makedirs(OUT,exist_ok=True); bpy.ops.wm.read_factory_settings(use_empty=True); setup_cycles('bracket',bool(OPT.get('cpu')),ao_distance=.18)
 hi={};lo={}
 a=Acc(); fan(a,*FANS[0],400,800,True); hi['fan']=a.obj('hi_fan')
 a=Acc(); wood(a,240,300,True); hi['wood']=a.obj('hi_wood')
 a=Acc(); fan(a,*FANS[0],120,240); lo['fan']=a.obj('lo_fan')
 a=Acc(); wood(a,48,100); lo['wood']=a.obj('lo_wood')
 for ob in lo.values(): hide_from_rays(ob)
 others=[]
 for at,scale,ang in FANS[1:]:
  a=Acc(); fan(a,at,scale,ang,16,32); others.append(a.obj('ao_fan'))
 parts={n:{'low':lo[n],'normal_from':[hi[n]],'ao_from':list(hi.values())+others,'reach':((.0025,.005) if n == 'fan' else (.008,.015)),'poles':(.03,.97)} for n in lo}
 normal,ao,u,v,masks=bake_atlas(parts,RECTS,SIZE,'bracket'); albedo,orm=paint(SIZE); orm[...,0]=ao
 alb=np.ones((SIZE,SIZE,4),np.float32); alb[...,:3]=albedo
 for name,img,linear in [('albedo',alb,False),('normal',normal,True),('orm',orm.astype(np.float32),True)]: save_png(os.path.join(OUT,'bracket_'+name+'.png'),img,linear)
 for ob in list(hi.values())+list(lo.values())+others: bpy.data.objects.remove(ob,do_unlink=True)
 ob=build().obj('RotBracket'); log('bracket','%d triangles'%tri_count(ob)); export_glb([ob],os.path.join(OUT,'bracket.glb'))
if OPT.get('preview'):
 bpy.ops.wm.read_factory_settings(use_empty=True); ob=build().obj('preview'); ob.color=(.55,.4,.3,1)
 preview_render([ob],os.path.abspath(OPT['preview']),target=(0,.6,0),scale=2.6)
else: main()
