"""Puffball Bomber: procedural Blender game meshes and textures. +X forward, Y up."""
import os,sys,math,json
import bpy,numpy as np
from mathutils import Vector
sys.path.insert(0,os.path.dirname(__file__))
from unitlib import MeshData,grid_surface,data_uv,tube,export_glb,save_png
OUT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../art/bomber'))
os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
TAU=math.tau
stats=[]
for lod,(rows,sides,leg_sides) in enumerate([(68,128,20),(38,72,14),(18,32,8)]):
 md=MeshData()
 def body(i,j):
  a=i/sides*TAU; t=j/rows*math.pi
  n=Vector((math.sin(t)*math.cos(a),math.cos(t),math.sin(t)*math.sin(a)))
  bumps=(.009*math.sin(a*13+math.sin(t*17))*math.sin(t*24)+.006*math.sin(a*27-t*31))*math.sin(t)**2
  p=Vector((0,1.05,0))+Vector((n.x*.83,n.y*.70,n.z*.74))*(1+bumps)
  return p,n
 grid_surface(md,rows,sides,body,lambda i,j:(.02+.96*i/sides,.02+.46*j/rows),lambda i,j:data_uv(0))
 # Four stubby segmented legs, each carrying a diagonal gait phase.
 for sx in [-1,1]:
  for sz in [-1,1]:
   path=[(sx*.34,.79,sz*.30),(sx*.46,.62,sz*.41),(sx*.54,.39,sz*.49),(sx*.62,.20,sz*.56),(sx*.72,.10,sz*.59)]
   tube(md,path,[.25,.24,.215,.19,.07],leg_sides,rows,(.02,.51,.98,.74),1,lambda t:t,0 if sx==sz else 1,relief=lambda t,a,p:.016*math.sin(t*math.pi*8)*math.sin(math.pi*t))
   # A rounded foot pad surrounds the tapered ankle end and moves with the toes.
   pad_center=Vector((sx*.70,.105,sz*.59));pad_r=Vector((.18,.105,.19))
   def pad(i,j,center=pad_center,r=pad_r):
    a=i/leg_sides*TAU;t=j/12*math.pi;n=Vector((math.sin(t)*math.cos(a),math.cos(t),math.sin(t)*math.sin(a)))
    return center+Vector((n.x*r.x,n.y*r.y,n.z*r.z)),n
   grid_surface(md,12,leg_sides,pad,lambda i,j:(.03+.94*i/leg_sides,.52+.2*j/12),lambda i,j:data_uv(1,1.0,0 if sx==sz else 1))
   # Rounded toes create a planted contact rather than an open tube end.
   for k in [-1,0,1]:
    center=Vector((sx*.72,.095,sz*.59+k*.095));r=Vector((.16,.095,.10))
    def toe(i,j,center=center,r=r):
     a=i/leg_sides*TAU;t=j/10*math.pi;n=Vector((math.sin(t)*math.cos(a),math.cos(t),math.sin(t)*math.sin(a)))
     return center+Vector((n.x*r.x,n.y*r.y,n.z*r.z)),n
    grid_surface(md,10,leg_sides,toe,lambda i,j:(.03+.94*i/leg_sides,.52+.2*j/10),lambda i,j:data_uv(1,1.0,0 if sx==sz else 1))
 # Raised irregular ochre collar and dark pore on the upward-forward shoulder.
 vent=Vector((.43,1.69,0));axis=Vector((.52,.854,0));u=Vector((.854,-.52,0));v=Vector((0,0,1)); ring_sides=max(16,sides//2)
 def rim(i,j):
  a=i/ring_sides*TAU;phi=j/10*TAU; radial=u*math.cos(a)+v*math.sin(a)
  n=radial*math.cos(phi)+axis*math.sin(phi)
  return vent+radial*(.14+.012*math.sin(a*7))+n*.055,n
 grid_surface(md,10,ring_sides,rim,lambda i,j:(.02+.96*i/ring_sides,.76+.22*j/10),lambda i,j:data_uv(2))
 def pore(i,j):
  a=i/ring_sides*TAU;r=.14*j/8
  return vent+(u*math.cos(a)+v*math.sin(a))*r-axis*.015,axis
 grid_surface(md,8,ring_sides,pore,lambda i,j:(.5,.985),lambda i,j:data_uv(2))
 ob=md.obj('PuffballBomber_'+str(lod));name=['close','battle','distant'][lod]
 count=export_glb([ob],os.path.join(OUT,'bomber_'+name+'.glb'))
 stats.append({'lod':name,'triangles':count,'surfaces':1});bpy.data.objects.remove(ob,do_unlink=True)
# Cream, mottled and granular puffball skin, darker marks and pore in top atlas strip.
size=1024;y,x=np.mgrid[:size,:size];a=x/size;t=y/size
rng=np.random.default_rng(370);noise=rng.random((size,size))
from mathutils import noise as bnoise
# Irregular deterministic flecks with small clustered scales.
fleck=(np.repeat(np.repeat(rng.random((256,256)),4,axis=0),4,axis=1)>.94).astype(float)
for _ in range(3):
 fleck=(fleck+np.roll(fleck,1,0)+np.roll(fleck,-1,0)+np.roll(fleck,1,1)+np.roll(fleck,-1,1))/5
fiber=(np.sin(a*420+np.sin(t*80)*2)+1)*.5
base=np.stack([.91+.04*noise,.85+.055*noise,.72+.08*noise],axis=-1)
base*=1-.30*fleck[...,None]
leg=np.stack([.90+.015*fiber,.84+.02*fiber,.74+.025*fiber],axis=-1)
vent=np.stack([.54+.08*noise,.38+.08*noise,.20+.06*noise],axis=-1)
col=np.ones((size,size,4),np.float32)
col[:,:,:3]=np.where((t<.5)[...,None],base,np.where((t<.75)[...,None],leg,vent))
col[y>1002,:3]=(.12,.075,.035)
save_png(os.path.join(OUT,'bomber_albedo.png'),col,False)
height=noise*.018+fleck*.035+fiber*.006
gy,gx=np.gradient(height);n=np.stack([-gx*3,-gy*3,np.ones_like(gx)],axis=-1);n/=np.linalg.norm(n,axis=-1)[...,None]
norm=np.ones_like(col);norm[:,:,:3]=n*.5+.5
save_png(os.path.join(OUT,'bomber_normal.png'),norm,True)
with open(os.path.join(OUT,'stats.json'),'w') as f:json.dump(stats,f,indent=2)
print(stats)
