"""Pilobolus sniper, Blender-generated opaque and transparent LODs. +X forward, Y up."""
import os,sys,math,json,bpy,numpy as np
from mathutils import Vector
sys.path.insert(0,os.path.dirname(__file__))
from unitlib import MeshData,grid_surface,data_uv,tube,export_glb,save_png
OUT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../art/sniper'));os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
TAU=math.tau
stats=[]
for lod,(sides,rows) in enumerate([(24,36),(14,20),(8,12)]):
 opaque=MeshData();gel=MeshData();md=opaque
 def orb(center,radii,kind,rect,detail=1):
  c=Vector(center);r=Vector(radii); nr=max(8,int(rows*detail));ns=max(8,int(sides*detail))
  def point(i,j):
   a=i/ns*TAU;t=j/nr*math.pi;n=Vector((math.sin(t)*math.cos(a),math.cos(t),math.sin(t)*math.sin(a)))
   p=c+Vector((n.x*r.x,n.y*r.y,n.z*r.z));return p,Vector((n.x/max(r.x,.001),n.y/max(r.y,.001),n.z/max(r.z,.001))).normalized()
  grid_surface(md,nr,ns,point,lambda i,j:(rect[0]+(rect[2]-rect[0])*i/ns,rect[1]+(rect[3]-rect[1])*j/nr),lambda i,j:data_uv(kind))
 dark=(.02,.02,.98,.24);amber=(.02,.27,.98,.49);black=(.02,.52,.98,.74);gold=(.02,.77,.98,.99)
 # Four jointed, tapered dark stilts. Overlap upper ends inside the golden hub.
 orb((0,.53,0),(.16,.16,.16),3,gold,.6)
 for sx in [-1,1]:
  for sz in [-1,1]:
   path=[(sx*.07,.56,sz*.09),(sx*.23,.64,sz*.25),(sx*.39,.93,sz*.40),(sx*.52,.55,sz*.55),(sx*.70,.06,sz*.72)]
   tube(md,path,[.045,.043,.041,.032,.005],sides,rows*2,dark,1,lambda t:t,0 if sx==sz else 1)
 # Clear stalk and water-filled vesicle form their own blended surface.
 md=gel
 tube(md,[(0,.53,0),(-.04,.78,0),(-.09,1.03,0),(-.14,1.20,0),(-.12,1.31,0),(-.08,1.47,0),(-.06,1.62,0),(-.05,1.73,0),(-.045,1.78,0)], [.075,.062,.05,.055,.115,.16,.14,.085,.004],sides,rows*3,amber,2,lambda t:0,0)
 # Opaque black sporangium sits directly atop the vesicle.
 md=opaque
 orb((-.045,1.805,0),(.16,.065,.13),3,black,1)
 md=gel
 for i,(x,y,z,r) in enumerate([(-.09,.72,-.14,.055),(.04,.92,.11,.047),(-.14,1.07,-.105,.04),(.03,.68,.16,.04)]):
  orb((x,y,z),(r,r,r),2,gold,.4)
 ob=opaque.obj('Opaque');glass=gel.obj('Gel');name=['close','battle','distant'][lod]
 count=export_glb([ob,glass],os.path.join(OUT,'sniper_'+name+'.glb'));stats.append({'lod':name,'triangles':count,'surfaces':2});bpy.data.objects.remove(ob,do_unlink=True);bpy.data.objects.remove(glass,do_unlink=True)
size=512;y,x=np.mgrid[:size,:size];t=y/size;rng=np.random.default_rng(91);noise=rng.random((size,size))
col=np.ones((size,size,4),np.float32)
dark=np.stack([.07+.025*noise,.045+.025*noise,.026+.015*noise],-1)
amber=np.stack([.94+.03*noise,.68+.08*noise,.30+.08*noise],-1)
black=np.stack([.04+.025*noise,.035+.025*noise,.025+.02*noise],-1)
gold=np.stack([.93+.05*noise,.65+.10*noise,.18+.06*noise],-1)
col[:,:,:3]=np.where((t<.25)[...,None],dark,np.where((t<.5)[...,None],amber,np.where((t<.75)[...,None],black,gold)))
save_png(os.path.join(OUT,'sniper_albedo.png'),col,False)
n=np.ones_like(col);n[:,:,:3]=(.5,.5,1.0);save_png(os.path.join(OUT,'sniper_normal.png'),n,True)
with open(os.path.join(OUT,'stats.json'),'w') as f:json.dump(stats,f,indent=2)
print(stats)
