"""Build a clustered, deliquescing Inkcap Bed for Godot. +Y is up."""
import os,sys,math,json,bpy,numpy as np
from mathutils import Vector
sys.path.insert(0,os.path.dirname(__file__))
from unitlib import MeshData,grid_surface,data_uv,tube,export_glb,save_png
OUT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../art/inkcap_bed'));os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
TAU=math.tau;md=MeshData();sides=28;rows=20
stem=(.02,.02,.98,.23);cream=(.02,.27,.98,.48);ink=(.02,.52,.98,.73)
# Arranged cluster: position, overall height, cap radius, mature almost-black cap.
mushrooms=[(0,0,2.05,.37,False),(.60,.23,1.72,.34,False),(-.56,.18,1.58,.33,False),(.28,-.62,1.38,.29,False),(-.55,-.53,1.27,.27,False),(.77,-.44,1.23,.27,False),(-.08,.72,1.75,.37,True)]
for idx,(x,z,h,R,mature) in enumerate(mushrooms):
 brim=h*(.72 if mature else .56); cap_h=h*(.16 if mature else .43)
 # Pale stems stay slender; they end inside the cap.
 tube(md,[(x,.02,z),(x-.025,brim*.40,z),(x+.01,brim*.78,z),(x,brim+.12,z)],[.085,.075,.07,.055],12,22,stem,0,lambda t:0,0)
 def cap(t,a):
  r=R*math.sin(t*math.pi*.5)**.52*(1+.025*math.sin(a*7+idx))
  y=brim+cap_h*(1-(t*t if mature else t))-.045*t**6*(.5+.5*math.sin(a*9+idx))
  p=Vector((x+math.cos(a)*r,y,z+math.sin(a)*r));n=Vector((math.cos(a)*.85,.46,math.sin(a)*.85)).normalized()
  return p,n
 uv=ink if mature else cream;kind=2 if mature else 1
 grid_surface(md,rows,sides,lambda i,j:cap(max(.0001,j/rows),i/sides*TAU),lambda i,j:(uv[0]+(uv[2]-uv[0])*i/sides,uv[1]+(uv[3]-uv[1])*j/rows),lambda i,j:data_uv(kind))
 # A dark under-rim and uneven, visibly hanging black ink threads.
 def underside(i,j):
  a=i/sides*TAU;r=R*j/5
  return Vector((x+math.cos(a)*r,brim-.012,z+math.sin(a)*r)),Vector((0,-1,0))
 grid_surface(md,5,sides,underside,lambda i,j:(.02+.96*i/sides,.52+.21*j/5),lambda i,j:data_uv(2))
 if not mature:
  # Short overlapping, tapered scales: four uneven tiers of shaggy shingles.
  for tier in range(5):
   for k in range(14):
    a=(k+.5*(tier%2)+.13*idx+.11*math.sin(k*4+idx))*TAU/14
    start=.10+tier*.155+.045*math.sin(k*3+idx);end=min(start+.16+.08*(.5+.5*math.sin(k*7+idx)),.99)
    def scale(i,j,a=a,start=start,end=end):
     f=j/6;across=i/4*2-1
     width=(.11+.04*(.5+.5*math.sin(a*23+idx)))*math.sin(math.pi*f)**.65+.0005
     angle=a+across*width
     p,n=cap(start+(end-start)*f,angle)
     radial=Vector((math.cos(angle),0,math.sin(angle)))
     p+=radial*(.008+.028*math.sin(math.pi*f))+Vector((0,-.025*f*f,0))
     return p,n
    grid_surface(md,6,4,scale,lambda i,j:(.03+.92*i/4,.30+.08*j/6),lambda i,j:data_uv(1),wrap=False)
 for k in range(4):
  a=(k+.23*idx)*TAU/4;edge=cap(1,a)[0];length=.10+.17*((k*7+idx*3)%9)/9
  p0=edge+Vector((0,.025,0));p1=edge+Vector((.01*math.cos(a),-length*.5,.01*math.sin(a)));p2=edge+Vector((.02*math.cos(a),-length,.02*math.sin(a)))
  tube(md,[p0,p1,p2],[.025,.018,.008],7,10,ink,2,lambda t:0,0)
  # Droplets fall through a short looping path, with staggered phases in UV2.
  nr=8;ns=8
  def drop(i,j,c=p2):
   ang=i/ns*TAU;t=j/nr*math.pi;n=Vector((math.sin(t)*math.cos(ang),math.cos(t),math.sin(t)*math.sin(ang)))
   return c+Vector((n.x*.025,n.y*.042,n.z*.025)),n
  grid_surface(md,nr,ns,drop,lambda i,j:(.02+.96*i/ns,.52+.21*j/nr),lambda i,j:data_uv(3,0,((idx*4+k)*.137)%1.0))
ob=md.obj('InkcapBed');count=export_glb([ob],os.path.join(OUT,'inkcap_bed.glb'))
size=512;y,x=np.mgrid[:size,:size];v=y/size;rng=np.random.default_rng(159);noise=rng.random((size,size));fiber=(np.sin(x*.30+np.sin(y*.047)*3)+1)*.5
stemcol=np.stack([.83+.10*noise,.82+.10*noise,.77+.11*noise],-1)
capcol=np.stack([.79+.09*noise+.035*fiber,.78+.09*noise+.035*fiber,.74+.10*noise+.03*fiber],-1)
t=np.clip((v-.27)/.21,0,1);top=1-np.clip(t/.17,0,1);bottom=np.clip((t-.83)/.14,0,1)
brown=np.stack([.30+.08*noise,.27+.07*noise,.23+.07*noise],-1);black=np.stack([.015+.012*noise,.013+.010*noise,.012+.009*noise],-1)
capcol=capcol*(1-top[...,None])+brown*top[...,None];capcol=capcol*(1-bottom[...,None])+black*bottom[...,None]
rgba=np.ones((size,size,4),np.float32);rgba[:,:,:3]=np.where((v<.25)[...,None],stemcol,np.where((v<.5)[...,None],capcol,black));save_png(os.path.join(OUT,'inkcap_bed_albedo.png'),rgba,False)
height=noise*.013+fiber*.022;gy,gx=np.gradient(height);nm=np.stack([-gx*2,-gy*2,np.ones_like(gx)],-1);nm/=np.linalg.norm(nm,axis=-1)[...,None];normal=np.ones_like(rgba);normal[:,:,:3]=nm*.5+.5;save_png(os.path.join(OUT,'inkcap_bed_normal.png'),normal,True)
with open(os.path.join(OUT,'stats.json'),'w') as f:json.dump({'triangles':count,'surfaces':1,'mushrooms':len(mushrooms),'falling_droplets':len(mushrooms)*4},f,indent=2)
print('inkcap bed triangles:',count)
