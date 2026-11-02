"""Build Elf-cup Slinger LODs in Blender. +X faces the target; Y is up.
Run: blender -b --factory-startup -P tools/blender/slinger_build.py
"""
import os, sys, math, json
import bpy
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
from unitlib import MeshData, grid_surface, data_uv, tube, export_glb, save_png
OUT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../art/slinger'))
os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
TAU=math.tau
axis=Vector((.68,.733,0)); u=Vector((.733,-.68,0)); v=Vector((0,0,1))
center=Vector((0,1.04,0))
def uv(kind,a,t): return (.02+.96*a, (kind+.03+.94*t)/4)
def bowl(t,a,inside):
 r=.76*t*(1+.045*math.sin(a*3)+.026*math.cos(a*5))
 depth=-.44*(1-t*t)+.055*math.sin(3*a+.4)*t**4
 if not inside: depth-=.065*(1-.6*t)
 rib=.003*math.sin(a*54+2*t)*math.sin(math.pi*t)
 p=center+(u*math.cos(a)+v*math.sin(a))*(r+rib)+axis*depth
 # Surface normals of the paraboloid, with inward-facing red cavity.
 n=(axis-(u*math.cos(a)+v*math.sin(a))*1.15*t).normalized()
 return p,n if inside else -n
stats=[]
for lod,(rows,sides,tubes) in enumerate([(30,112,18),(18,64,12),(8,28,7)]):
 md=MeshData()
 for kind,inside in [(0,False),(1,True)]:
  grid_surface(md,rows,sides,lambda i,j,inside=inside:bowl(max(.0001,j/rows),i/sides*TAU,inside),lambda i,j,kind=kind:uv(kind,i/sides,j/rows),lambda i,j,kind=kind:data_uv(kind))
 # Rolled ivory lip, continuous around the entire red hymenium.
 def rim(i,j):
  a=i/sides*TAU; phi=j/8*TAU
  p,_=bowl(1,a,True); radial=u*math.cos(a)+v*math.sin(a)
  n=radial*math.cos(phi)+axis*math.sin(phi)
  return p+n*.033-axis*.015,n
 grid_surface(md,8,sides,rim,lambda i,j:uv(2,i/sides,j/8),lambda i,j:data_uv(2))
 # Short neck rooted in the underside and three muscular, curling supports.
 tube(md,[(-.40,.61,0),(-.38,.43,0),(-.20,.25,0)],[.115,.18,.17],tubes,rows,(.02,.76,.98,.99),0,lambda t:0,0)
 for sign in [-1,1]:
  path=[(-.37,.43,sign*.10),(-.10,.32,sign*.37),(.10,.13,sign*.61),(.39,.17,sign*.73),(.51,.40,sign*.72),(.39,.58,sign*.67),(.25,.54,sign*.63)]
  tube(md,path,[.16,.17,.155,.13,.10,.07,.002],tubes,rows*2,(.02,.76,.98,.99),3,lambda t:t,0 if sign<0 else 1,relief=lambda t,a,p:.007*math.sin(a*9+t*18)*math.sin(math.pi*t))
 path=[(-.38,.43,0),(-.48,.27,0),(-.74,.15,0),(-.88,.28,0),(-.85,.59,0),(-.64,.69,0),(-.53,.55,0),(-.62,.48,0)]
 tube(md,path,[.17,.16,.135,.12,.10,.075,.045,.002],tubes,rows*2,(.02,.76,.98,.99),3,lambda t:t,1)
 ob=md.obj('ElfCupSlinger_'+str(lod))
 name=['close','battle','distant'][lod]
 count=export_glb([ob],os.path.join(OUT,'slinger_'+name+'.glb'))
 stats.append({'lod':name,'triangles':count,'surfaces':1})
 bpy.data.objects.remove(ob,do_unlink=True)
# Shared atlas: coral-orange exterior, wet scarlet hymenium, pale rim and stalks.
size=1024; y,x=np.mgrid[:size,:size]; a=x/size; t=(y%(size//4))/(size//4); kind=y//(size//4)
rng=np.random.default_rng(282); noise=rng.random((size,size))
fiber=(np.sin(a*TAU*90+np.sin(t*18)*1.6)+1)*.5
freck=((np.sin(a*473+t*177)*np.sin(a*281-t*391))>.91).astype(float)
col=np.ones((size,size,4),np.float32)
cream=np.stack([.94+.02*fiber,.87+.025*fiber,.75+.035*fiber],axis=-1)
cream*= (1-.44*freck[...,None]); cream*= (.97+.03*noise[...,None])
red=np.stack([.56+.32*t+.025*fiber,.012+.035*t+.006*fiber,.018+.016*t],axis=-1)
# The outer cup is warmer and slightly lighter than the scarlet interior.
coral=np.stack([.83+.10*t+.015*fiber,.13+.10*t+.012*fiber,.035+.035*t],axis=-1)
coral*= (.97+.03*noise[...,None])*(1-.15*freck[...,None])
col[:,:,:3]=np.where((kind==1)[...,None],red,np.where((kind==0)[...,None],coral,cream))
save_png(os.path.join(OUT,'slinger_albedo.png'),col,False)
height=fiber*.008+noise*.006+freck*.012
h_y,h_x=np.gradient(height); norm=np.stack([-h_x*7,-h_y*7,np.ones_like(height)],axis=-1);norm/=np.linalg.norm(norm,axis=-1)[...,None]
nmap=np.ones_like(col); nmap[:,:,:3]=norm*.5+.5
save_png(os.path.join(OUT,'slinger_normal.png'),nmap,True)
with open(os.path.join(OUT,'stats.json'),'w') as f:json.dump(stats,f,indent=2)
print(stats)
