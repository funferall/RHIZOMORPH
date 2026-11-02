"""Build a real skinned glTF 2.0 asset. Python + numpy + Pillow; no external DCC."""
from pathlib import Path
import numpy as np, math,json,struct,io,sys
LOD=int(sys.argv[1]) if len(sys.argv)>1 else 0
QUALITY=[1.0,.55,.22][LOD]
from PIL import Image,ImageFilter
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'art'/'destroying_angel';OUT.mkdir(exist_ok=True)
V=[];N=[];UV=[];C=[];J=[];W=[];F=[]
nodes=[];world=[];parents=[]
def bone(name,pos,parent=None):
 i=len(nodes);pos=np.array(pos,float);local=pos if parent is None else pos-world[parent]
 n={'name':name,'translation':local.tolist()}
 if parent is not None:nodes[parent].setdefault('children',[]).append(i)
 nodes.append(n);world.append(pos);parents.append(parent);return i
hips=bone('Hips',[0,1.13,0]);chest=bone('Stalk',[0,1.65,0],hips);head=bone('Hood',[0,2.04,0],chest)
legs=[];arms=[]
for sign,label in [(-1,'L'),(1,'R')]:
 h=bone('Thigh_'+label,[sign*.17,1.12,0],hips);k=bone('Shin_'+label,[sign*.48,.60,.23],h);f=bone('Foot_'+label,[sign*.84,.065,-.025],k);legs.append((h,k,f))
 a=bone('Arm_'+label,[sign*.22,1.84,0],chest);e=bone('Blade_'+label,[sign*.48,1.48,.07],a);arms.append((a,e))
def unit(x):
 x=np.asarray(x,float);return x/max(np.linalg.norm(x),1e-10)
def grid(fn,rows,sides,b,color,kind='wrap',blend=None):
 rows=max(2,round(rows*QUALITY));sides=max(4,round(sides*QUALITY))
 base=len(V)
 for i in range(rows+1):
  t=i/rows
  for j in range(sides+1):
   u=j/sides;p=np.array(fn(t,u));dt=np.array(fn(min(1,t+.0001),u))-np.array(fn(max(0,t-.0001),u));du=np.array(fn(t,u+.0001))-np.array(fn(t,u-.0001));n=unit(np.cross(du,dt))
   if fn.__name__ in ["stalk","fn"]:n=-n
   if np.linalg.norm(n)<.1:n=np.array([0,1 if t<.5 else -1,0.])
   V.append(p);N.append(n);UV.append([u,t]);C.append(list(color)+[1]);js=[b,0,0,0];ws=[1.,0,0,0]
   if blend:
    bb,amt=blend(t);js[1]=bb;ws=[1-amt,amt,0,0]
   J.append(js);W.append(ws)
 for i in range(rows):
  for j in range(sides):
   q=base+i*(sides+1)+j
   for tri in [(q,q+1,q+sides+2),(q,q+sides+2,q+sides+1)]:
    a,bb,c=[V[x] for x in tri];cross=np.cross(bb-a,c-a)
    if np.linalg.norm(cross)<1e-9:continue
    if np.dot(cross,np.sum([N[x] for x in tri],axis=0))<0:tri=(tri[0],tri[2],tri[1])
    F.append(tri)
def stalk(t,u):
 y=1.08+t*.93;a=u*math.tau
 # Single slender, flat-chested stalk. No paired chest geometry.
 rx=np.interp(t,[0,.15,.4,.7,1],[.15,.13,.085,.15,.075]);rz=np.interp(t,[0,.2,.55,1],[.13,.115,.085,.105])
 return [math.cos(a)*rx*(1+.025*math.sin(7*a+t*3)),y,math.sin(a)*rz-.035*math.sin(t*math.pi)]
grid(stalk,30,32,hips,[.93,.91,.83],blend=lambda t:(chest,float(np.clip((t-.35)/.35,0,1))))
def limb(start,end,r0,r1,b,side=16,rows=12,flatten=1):
 start=np.array(start);end=np.array(end);axis=unit(end-start);uu=unit(np.cross(axis,[0,0,1]));vv=np.cross(axis,uu)
 def fn(t,u):
  a=u*math.tau;r=(r0*(1-t)+r1*t)*(1+.075*math.sin(t*math.pi*3)+.035*math.sin(a*5+t*3))
  return start*(1-t)+end*t+r*(uu*math.cos(a)+vv*math.sin(a)*flatten)
 grid(fn,rows,side,b,[.94,.92,.85])
for si,(h,k,f) in enumerate(legs):
 sign=-1 if si==0 else 1
 limb(world[h],world[k],.105,.064,h,20,18,.83)
 limb(world[k],world[f],.085,.006,k,18,18,.42)
 def foot(t,u,sign=sign):
  a=u*math.tau;r=math.sin(math.pi*t)
  return [sign*(.76+.16*t)+math.cos(a)*r*.035,.065-.055*t+math.sin(a)*r*.025,-.025+t*.16]
 grid(foot,14,12,f,[.70,.68,.58])
# Overlapping tapered knee/thigh husks break the cylindrical mannequin outline.
for si,(h,k,f) in enumerate(legs):
 sign=-1 if si==0 else 1
 for joint,length,spread in [(h,.42,.13),(k,.42,.10)]:
  def husk(t,u,joint=joint,length=length,spread=spread,sign=sign):
   a=u*math.tau;w=math.sin(math.pi*t)**.8*spread
   return world[joint]+np.array([sign*(.03+t*.23)+math.cos(a)*w,.12-length*t,-.04+math.sin(a)*w*.38])
  grid(husk,18,12,joint,[.92,.91,.86])
for si,(a,e) in enumerate(arms):
 sign=-1 if si==0 else 1
 limb(world[a],world[e],.061,.048,a,16,14,.8)
 # Broad, flattened organic scythes, tapering to a needle edge.
 def blade(t,u,sign=sign):
  phi=u*math.tau;width=.115*math.sin(t*math.pi)**.75+.0005
  return [sign*(.48+.39*t+.055*math.sin(t*math.pi))+math.cos(phi)*width,1.48-.90*t,.07+.23*t+math.sin(phi)*width*.16]
 grid(blade,28,12,e,[.98,.97,.93])
# Smooth joint burls close the limb cross-section joins in every pose.
for joint,radii in [(h,(.11,.13,.105)) for h,_,_ in legs]+[(b,(.085,.09,.08)) for _,b,_ in legs]+[(f,(.032,.035,.035)) for _,_,f in legs]+[(e,(.052,.053,.052)) for _,e in arms]:
 def burl(t,u,joint=joint,radii=np.array(radii)):
  a=u*math.tau;v=t*math.pi
  return world[joint]+radii*np.array([math.sin(v)*math.cos(a),math.cos(v),math.sin(v)*math.sin(a)])
 grid(burl,10,16,joint,[.93,.91,.84])
# Asymmetric hooked hood: high narrow peak toward the rear, long leading brim.
def hood(t,u):
 a=u*math.tau;r=math.sin(t*math.pi*.5);front=(math.sin(a)+1)/2
 x=math.cos(a)*r*.67*(1+.04*math.sin(3*a));z=-.14+math.sin(a)*r*.61
 y=2.51-.58*r**.85 + .065*math.cos(a)*r+.12*front*r**3+.16*math.cos(a)*r**2 + .035*math.sin(a*7)*r**8
 x-=.24*(1-r)**2
 z-=.16*(1-r)**2
 return [x,y,z]
grid(hood,24,64,head,[.98,.97,.91])
# Underside with a recessed fan of 30 thick gill ribs (shared skinned mesh).
for i in range(42):
 a=i*math.tau/42
 start=[math.cos(a)*.085,2.105,-.10+math.sin(a)*.09]
 end=np.array(hood(1,i/42))+[0,-.025,0]
 # Thin fleshy gill blade, closed elliptical section.
 def gill(t,u,a=a,start=np.array(start),end=np.array(end)):
  p=start*(1-t)+end*t;w=math.sin(math.pi*t)*.035+.002
  return p+np.array([-math.sin(a)*math.cos(u*math.tau)*.006, -math.sin(u*math.tau)*w,math.cos(a)*math.cos(u*math.tau)*.006])
 grid(gill,8,6,head,[.83,.77,.53])
# Three flowing mantle plates, attached to chest. Deliberate broad shapes.
for offset,length,width in [(-.32,.97,.20),(-.13,.76,.14),(0,1.17,.22),(.13,.85,.14),(.32,1.06,.20)]:
 def mantle(t,u,o=offset,l=length,w=width):
  a=u*math.tau;span=(math.sin(math.pi*t)**.85)*(1-t*.65)*w+.0005
  return [o*(1+1.55*t)+math.cos(a)*span,2.02-l*t,-.105-.36*t+math.sin(a)*.018*math.sin(t*math.pi)]
 grid(mantle,26,14,chest,[.91,.90,.82])
# Connect the stalk continuously to the hood; no floating head gap.
limb([0,1.93,-.02],[0,2.19,-.06],.085,.065,head,16,12,.9)
for ar,el in arms:
 def shoulder(t,u,ar=ar):
  a=u*math.tau;v=t*math.pi
  return world[ar]+np.array([.075*math.sin(v)*math.cos(a),.085*math.cos(v),.065*math.sin(v)*math.sin(a)])
 grid(shoulder,10,16,ar,[.94,.92,.85])
# Small shoulder veils, not breast plates.
for sign in [-1,1]:
 def plate(t,u,sign=sign):
  a=u*math.tau;w=math.sin(t*math.pi)*.095+.001
  return [sign*(.18+.38*t)+math.cos(a)*w,1.96-.63*t,-.025+math.sin(a)*w*.32]
 grid(plate,16,12,chest,[.98,.96,.88])
V=np.asarray(V,np.float32);N=np.asarray(N,np.float32);UV=np.asarray(UV,np.float32);C=np.asarray(C,np.float32);J=np.asarray(J,np.uint16);W=np.asarray(W,np.float32);F=np.asarray(F,np.uint32)
# Deterministic smooth, fibrous cuticle texture and matching normal map.
rng=np.random.default_rng(197);noise=Image.fromarray(np.uint8(rng.random((256,256))*255)).resize((512,512)).filter(ImageFilter.GaussianBlur(2))
a=np.array(noise)/255.;yy,xx=np.mgrid[:512,:512];grain=(np.sin(xx*.65+np.sin(yy*.035)*2)+1)/2
height=a*.65+grain*.10;gy,gx=np.gradient(height);normal=np.stack([-gx*1.4,-gy*1.4,np.ones_like(a)],-1);normal/=np.linalg.norm(normal,axis=-1)[...,None]
color=np.stack([.91+a*.07,.89+a*.08,.81+a*.12],-1)
# Sparse small fungal freckles, restrained and cheap.
freck=(a<.31);color[freck]*=.88
tex=Image.fromarray(np.uint8(np.clip(color,0,1)*255));norm=Image.fromarray(np.uint8((normal*.5+.5)*255))
tex.save(OUT/'angel_skin.png');norm.save(OUT/'surface_detail.png')
blob=bytearray();views=[];access=[]
def data(arr,ctype,typ,target=None):
 arr=np.ascontiguousarray(arr);offset=len(blob);blob.extend(arr.tobytes());blob.extend(b'\0'*((-len(blob))%4));view={'buffer':0,'byteOffset':offset,'byteLength':arr.nbytes}
 if target:view['target']=target
 vi=len(views);views.append(view);ac={'bufferView':vi,'componentType':ctype,'count':len(arr),'type':typ}
 if typ in ['VEC3','SCALAR'] and ctype==5126:ac['min']=np.min(arr,axis=0).reshape(-1).tolist();ac['max']=np.max(arr,axis=0).reshape(-1).tolist()
 idx=len(access);access.append(ac);return idx
attrs={name:data(arr,ct,tp,34962) for name,arr,ct,tp in [('POSITION',V,5126,'VEC3'),('NORMAL',N,5126,'VEC3'),('TEXCOORD_0',UV,5126,'VEC2'),('COLOR_0',C,5126,'VEC4'),('JOINTS_0',J,5123,'VEC4'),('WEIGHTS_0',W,5126,'VEC4')]}
indices=data(F.reshape(-1),5125,'SCALAR',34963)
ib=[]
for p in world:
 m=np.eye(4,dtype=np.float32);m[:3,3]=-p;ib.append(m.T.reshape(16))
skin={'inverseBindMatrices':data(np.array(ib,np.float32),5126,'MAT4'),'joints':list(range(len(nodes))),'skeleton':0}
images=[]
for im in [tex,norm]:
 buf=io.BytesIO();im.save(buf,format='PNG');off=len(blob);blob.extend(buf.getvalue());blob.extend(b'\0'*((-len(blob))%4));images.append({'bufferView':len(views),'mimeType':'image/png'});views.append({'buffer':0,'byteOffset':off,'byteLength':len(buf.getvalue())})
def quat(x=0,y=0,z=0):
 # quaternion XYZ; current animations use one axis per track.
 axis=np.array([x,y,z]);angle=np.linalg.norm(axis)
 return [0,0,0,1] if angle<1e-8 else list(axis/angle*math.sin(angle/2))+[math.cos(angle/2)]
animations=[]
for name,duration in [('Idle',2.4),('Walk',1.2),('Attack',.95)]:
 times=np.linspace(0,duration,49,dtype=np.float32);samplers=[];channels=[]
 def track(node,path,fn):
  vals=np.array([fn(float(t)/duration) for t in times],np.float32);samplers.append({'input':data(times,5126,'SCALAR'),'output':data(vals,5126,'VEC4' if path=='rotation' else 'VEC3'),'interpolation':'LINEAR'});channels.append({'sampler':len(samplers)-1,'target':{'node':node,'path':path}})
 if name=='Idle':
  track(chest,'rotation',lambda t:quat(x=.018*math.sin(t*math.tau)))
  track(head,'rotation',lambda t:quat(y=.025*math.sin(t*math.tau)))
 if name=='Walk':
  track(hips,'translation',lambda t:world[hips]+[0,.025*(1-math.cos(t*math.tau*2)),0])
  for si,(h,k,f) in enumerate(legs):
   ph=si*math.pi
   track(h,'rotation',lambda t,ph=ph:quat(x=.40*math.sin(t*math.tau+ph)))
   track(k,'rotation',lambda t,ph=ph:quat(x=-.50*max(0,math.sin(t*math.tau+ph))))
   track(f,'rotation',lambda t,ph=ph:quat(x=.13*math.sin(t*math.tau+ph)))
  for si,(ar,el) in enumerate(arms):track(ar,'rotation',lambda t,si=si:quat(x=-.16*math.sin(t*math.tau+si*math.pi)))
  track(chest,'rotation',lambda t:quat(x=.035,z=.025*math.sin(t*math.tau)))
  track(head,'rotation',lambda t:quat(y=-.025*math.sin(t*math.tau)))
 if name=='Attack':
  # Hold the anticipation; cross the target in 0.11 s, then settle deliberately.
  keys=[0,.28,.36,.43,.50,.64,1]
  def pose(t,values):return float(np.interp(t,keys,values))
  track(hips,'translation',lambda t:world[hips]+[0,pose(t,[0,-.08,-.10,-.13,-.10,-.06,0]),pose(t,[0,-.12,-.10,.48,.51,.30,0])])
  track(chest,'rotation',lambda t:quat(x=pose(t,[0,-.08,.02,.24,.28,.12,0]),y=pose(t,[0,-.48,-.55,.40,.58,.28,0])))
  track(head,'rotation',lambda t:quat(y=pose(t,[0,.20,.25,-.18,-.25,-.10,0])))
  for si,(h,k,f) in enumerate(legs):
   track(h,'rotation',lambda t,si=si:quat(x=pose(t,[0,-.12,-.15,.25,.28,.16,0])*(-1 if si==0 else 1)))
   track(k,'rotation',lambda t:quat(x=pose(t,[0,-.12,-.15,-.25,-.25,-.12,0])))
  for si,(ar,el) in enumerate(arms):
   sign=-1 if si==0 else 1
   track(ar,'rotation',lambda t,sign=sign:quat(x=pose(t,[0,-.55,-.7,-1.25,-1.15,-.7,0]),z=sign*pose(t,[0,.65,.75,-.80,-.95,-.45,0])))
   track(el,'rotation',lambda t,sign=sign:quat(y=sign*pose(t,[0,-.35,-.4,.5,.6,.25,0]),z=sign*pose(t,[0,.15,.20,-.35,-.4,-.2,0])))
 animations.append({'name':name,'samplers':samplers,'channels':channels})
mesh_node=len(nodes);nodes.append({'name':'DestroyingAngel','mesh':0,'skin':0})
gltf={'asset':{'version':'2.0','generator':'RHIZOMORPH Angel kit procedural authoring'},'scene':0,'scenes':[{'nodes':[0,mesh_node]}],'nodes':nodes,'skins':[skin],'meshes':[{'name':'DestroyingAngel','primitives':[{'attributes':attrs,'indices':indices,'material':0}]}],'materials':[{'name':'IvoryFungalSkin','doubleSided':True,'pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicFactor':0,'baseColorFactor':[.70,.70,.70,1.0],'roughnessFactor':.82},'normalTexture':{'index':1,'scale':.42}}],'textures':[{'source':0,'sampler':0},{'source':1,'sampler':0}],'images':images,'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}],'animations':animations,'accessors':access,'bufferViews':views,'buffers':[{'byteLength':len(blob)}]}
s=json.dumps(gltf,separators=(',',':')).encode();s+=b' '*((-len(s))%4);out=struct.pack('<4sII',b'glTF',2,12+8+len(s)+8+len(blob))+struct.pack('<I4s',len(s),b'JSON')+s+struct.pack('<I4s',len(blob),b'BIN\0')+blob
(OUT/(['destroying_angel.glb','destroying_angel_battle.glb','destroying_angel_distant.glb'][LOD])).write_bytes(out)
print(json.dumps({'triangles':len(F),'vertices':len(V),'bones':len(world),'surfaces':1,'animations':[a['name'] for a in animations]},indent=2))

(OUT/(['stats_close.json','stats_battle.json','stats_distant.json'][LOD])).write_text(json.dumps({'triangles':len(F),'vertices':len(V),'bones':len(world),'surfaces':1},indent=2)+'\n')
