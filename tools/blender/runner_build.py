"""Build Candlesnuff Runner meshes: two-armed rolling carbon-black fungal scout. +X forward, Y up."""
import os,sys,math,json,bpy,numpy as np
from mathutils import Vector
sys.path.insert(0,os.path.dirname(__file__))
from unitlib import MeshData,grid_surface,data_uv,tube,export_glb,save_png
OUT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../art/runner'));os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
TAU=math.tau;stats=[]
for lod,(sides,rows) in enumerate([(20,36),(12,20),(8,10)]):
 md=MeshData();body=(.02,.02,.98,.46);foot=(.02,.52,.48,.98);branch=(.52,.52,.98,.98)
 def orb(center,radii):
  c=Vector(center);r=Vector(radii)
  def point(i,j):
   a=i/sides*TAU;t=j/rows*math.pi;n=Vector((math.sin(t)*math.cos(a),math.cos(t),math.sin(t)*math.sin(a)))
   return c+Vector((n.x*r.x,n.y*r.y,n.z*r.z)),n
  grid_surface(md,rows,sides,point,lambda i,j:(.02+.96*i/sides,.02+.44*j/rows),lambda i,j:data_uv(0))
 orb((0,.40,0),(.32,.19,.25))
 # Two long, opposite weight-bearing arms: the body rocks over one, then rises.
 # The endpoint is tapered to the ground and the root is buried in the central mass.
 for sx in [-1,1]:
  path=[(sx*.13,.44,0),(sx*.34,.43,sx*.025),(sx*.58,.34,sx*.06),(sx*.78,.17,sx*.09),(sx*.94,.025,sx*.12)]
  tube(md,path,[.135,.125,.105,.065,.005],sides,rows,foot,1,lambda t:t,0 if sx<0 else 1,relief=lambda t,a,p:.009*math.sin(a*7+t*31)*math.sin(math.pi*t))
 # Charred antler-like ascocarps; white ends are the pale asexual spore dust.
 branches=[
  [(-.18,.49,-.10),(-.30,.70,-.14),(-.39,.92,-.12),(-.35,1.14,-.11)],
  [(-.08,.51,.03),(-.11,.74,.04),(-.04,1.02,.04),(-.06,1.30,.03)],
  [(0,.50,-.08),(.13,.69,-.15),(.24,.95,-.20),(.24,1.22,-.22)],
  [(.10,.49,.08),(.29,.60,.12),(.49,.78,.14),(.62,1.02,.17)],
  [(.16,.46,-.02),(.35,.52,-.09),(.56,.63,-.13),(.78,.75,-.16)],
  [(-.23,.49,.07),(-.38,.62,.12),(-.56,.80,.19),(-.60,.98,.23)] ]
 for i,path in enumerate(branches):
  tube(md,path,[.105,.085,.055,.018],sides,rows,branch,2,lambda t:t,i%2,relief=lambda t,a,p:.008*math.sin(a*6+t*24)*math.sin(math.pi*t))
 # A small fork, with its base buried in the central antler.
 tube(md,[(.14,.73,-.16),(.03,.85,-.19),(-.04,1.03,-.22)], [.055,.045,.015],sides,rows,branch,2,lambda t:.5+.5*t,0)
 ob=md.obj('CandlesnuffRunner_'+str(lod));name=['close','battle','distant'][lod]
 count=export_glb([ob],os.path.join(OUT,'runner_'+name+'.glb'));stats.append({'lod':name,'triangles':count,'surfaces':1});bpy.data.objects.remove(ob,do_unlink=True)
# Two atlas strips: dark woody body, branches and feet with ivory-white tips.
size=512;y,x=np.mgrid[:size,:size];v=y/size;rng=np.random.default_rng(819);noise=rng.random((size,size))
fiber=(np.sin(x*.19+np.sin(y*.035)*2)+1)*.5
black=np.stack([.045+.024*noise+.018*fiber,.043+.022*noise+.017*fiber,.041+.020*noise+.016*fiber],-1)
# Branch UVs span the upper half; blend to powdery ivory at their last 16%.
t=np.clip((v-.52)/.46,0,1); start=np.where(x/size>.5,.43,.81);white=np.clip((t-start)/.27,0,1);white=white*white*(3-2*white);white*=np.clip(.75+noise*.42,0,1)
cream=np.stack([.78+.20*noise,.78+.20*noise,.75+.21*noise],-1)
col=np.ones((size,size,4),np.float32);col[:,:,:3]=black*(1-white[...,None])+cream*white[...,None]
save_png(os.path.join(OUT,'runner_albedo.png'),col,False)
h=noise*.012+fiber*.018;gy,gx=np.gradient(h);n=np.stack([-gx*2,-gy*2,np.ones_like(gx)],-1);n/=np.linalg.norm(n,axis=-1)[...,None]
nm=np.ones_like(col);nm[:,:,:3]=n*.5+.5;save_png(os.path.join(OUT,'runner_normal.png'),nm,True)
with open(os.path.join(OUT,'stats.json'),'w') as f:json.dump(stats,f,indent=2)
print(stats)
