#!/usr/bin/env python3
"""Generate an original, self-contained glTF 2.0 lighting-studio demo. Standard library only."""
import json, math, struct
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'TestModels/Fixture Models/Lumen Studio.glb'
g = {'asset': {'version': '2.0', 'generator': 'glTF Inspector · Lumen Studio', 'copyright': 'Original procedural fixture, MIT license'}, 'scene': 0, 'scenes': [{'name': 'Lumen · lighting atelier', 'nodes': []}], 'nodes': [], 'meshes': [], 'materials': [], 'accessors': [], 'bufferViews': [], 'buffers': [], 'cameras': [], 'extensionsUsed': ['KHR_lights_punctual'], 'extensions': {'KHR_lights_punctual': {'lights': []}}}
binary = bytearray()
def accessor(values, typ, component=5126, target=None):
    while len(binary)%4: binary.append(0)
    offset=len(binary); fmt={5126:'f',5125:'I',5123:'H'}[component]
    flat=[x for row in values for x in row] if isinstance(values[0],(list,tuple)) else values
    binary.extend(struct.pack('<'+fmt*len(flat),*flat))
    view={'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset}
    if target: view['target']=target
    vi=len(g['bufferViews']); g['bufferViews'].append(view)
    a={'bufferView':vi,'componentType':component,'count':len(values),'type':typ}
    if typ=='VEC3': a.update(min=[min(v[i] for v in values) for i in range(3)],max=[max(v[i] for v in values) for i in range(3)])
    if typ=='SCALAR': a.update(min=[min(values)],max=[max(values)])
    ai=len(g['accessors']);g['accessors'].append(a);return ai

def mat(name,color,metal=0,rough=.4,emission=None):
    m={'name':name,'pbrMetallicRoughness':{'baseColorFactor':[*color,1],'metallicFactor':metal,'roughnessFactor':rough}}
    if emission: m['emissiveFactor']=emission
    g['materials'].append(m);return len(g['materials'])-1
chalk=mat('01 · Warm porcelain',[.79,.73,.62],rough=.58)
ink=mat('02 · Midnight enamel',[.025,.065,.075],.45,.24)
copper=mat('03 · Brushed champagne brass',[.64,.36,.13],.85,.28)
coral=mat('04 · Vermilion lacquer',[.62,.105,.055],.15,.28)
frost=mat('05 · Opal diffuser',[.96,.84,.62],rough=.32,emission=[.9,.59,.27])
black=mat('06 · Graphite rubber',[.027,.028,.034],rough=.7)
stone=mat('07 · Sandstone stage',[.35,.39,.38],rough=.85)
blue=mat('08 · Cool opal',[.63,.83,.92],rough=.25)

def node(name,parent=None,**kw):
    i=len(g['nodes']);g['nodes'].append({'name':name,**kw})
    if parent is None:g['scenes'][0]['nodes'].append(i)
    else:g['nodes'][parent].setdefault('children',[]).append(i)
    return i

def mesh(name,pos,norm,indices,material):
    prim={'attributes':{'POSITION':accessor(pos,'VEC3',target=34962),'NORMAL':accessor(norm,'VEC3',target=34962)},'indices':accessor(indices,'SCALAR',5125,34963),'material':material}
    i=len(g['meshes']);g['meshes'].append({'name':name,'primitives':[prim]});return i

def lathe(name,profile,material,segments=72):
    pos=[];norm=[];idx=[]
    for j,(r,y) in enumerate(profile):
        a=profile[max(0,j-1)];b=profile[min(len(profile)-1,j+1)];dr=b[0]-a[0];dy=b[1]-a[1];length=math.hypot(dr,dy) or 1
        for k in range(segments+1):
            t=k*math.tau/segments;c=math.cos(t);s=math.sin(t)
            pos.append([r*c,y,r*s]);norm.append([dy*c/length,-dr/length,dy*s/length])
    for j in range(len(profile)-1):
        for k in range(segments):
            a=j*(segments+1)+k;b=a+segments+1
            idx += [a,b,a+1,a+1,b,b+1]
    return mesh(name,pos,norm,idx,material)

def cylinder(name,r,h,material):return lathe(name,[(0,0),(r,0),(r,h),(0,h)],material)
def sphere(name,r,material):
    return lathe(name,[(max(0,r*math.sin(i*math.pi/40)),-r*math.cos(i*math.pi/40)) for i in range(41)],material)
def place(name,mesh_id,parent,xyz=(0,0,0),**kw):return node(name,parent,mesh=mesh_id,translation=list(xyz),**kw)
def aim(origin,target):
    # Camera local -Z points toward target; columns form a right-handed rotation.
    z=[origin[i]-target[i] for i in range(3)];l=math.sqrt(sum(v*v for v in z));z=[v/l for v in z]
    x=[z[2],0,-z[0]];l=math.sqrt(sum(v*v for v in x));x=[v/l for v in x]
    y=[z[1]*x[2]-z[2]*x[1],z[2]*x[0]-z[0]*x[2],z[0]*x[1]-z[1]*x[0]]
    m=[[x[i],y[i],z[i]] for i in range(3)];tr=sum(m[i][i] for i in range(3))
    if tr>0:
        s=math.sqrt(tr+1)*2;return [(m[2][1]-m[1][2])/s,(m[0][2]-m[2][0])/s,(m[1][0]-m[0][1])/s,s/4]
    i=max(range(3),key=lambda i:m[i][i]);j=(i+1)%3;k=(i+2)%3;s=math.sqrt(1+m[i][i]-m[j][j]-m[k][k])*2
    q=[0,0,0,0];q[i]=s/4;q[j]=(m[j][i]+m[i][j])/s;q[k]=(m[k][i]+m[i][k])/s;q[3]=(m[k][j]-m[j][k])/s;return q
# Compact collection: one lamp, one morphing pebble, one articulated ribbon.
atelier=node('Display')
stage=node('Plinth',atelier)
place('Porcelain disk',cylinder('Disk',1.65,.10,stone),stage,(0,-.12,0))
place('Brass rim',lathe('Rim',[(1.62,0),(1.65,0),(1.65,.012),(1.62,.012)],copper),stage,(0,-.018,0))
lamp=node('Lamp',atelier,translation=[-.65,0,-.25])
place('Foot',cylinder('Foot',.27,.08,chalk),lamp)
place('Stem',cylinder('Stem',.035,.85,copper),lamp,(0,.08,0))
place('Shade',lathe('Shade',[(.43,.72),(.42,.76),(.14,1.1),(.06,1.1),(.06,1.06),(.12,1.06),(.38,.75),(.43,.72)],ink),lamp)
place('Opal diffuser',sphere('Opal',.18,frost),lamp,(0,.77,0))
# Morphable ceramic pebble: analytic position + normal deltas, not a placeholder triangle.
forms=node('Forms',atelier)
pebble_mesh=sphere('Pebble',.34,coral)
prim=g['meshes'][pebble_mesh]['primitives'][0]
def read_float3(ai):
    a=g['accessors'][ai];v=g['bufferViews'][a['bufferView']];raw=binary[v['byteOffset']:v['byteOffset']+v['byteLength']]
    return list(struct.iter_unpack('<fff',raw))
positions=read_float3(prim['attributes']['POSITION']);normals=read_float3(prim['attributes']['NORMAL'])
scale=(1.3,.55,1.3)
delta=[[p[i]*(scale[i]-1) for i in range(3)] for p in positions]
normal_delta=[]
for n in normals:
    dst=[n[i]/scale[i] for i in range(3)];length=math.sqrt(sum(x*x for x in dst)) or 1
    normal_delta.append([dst[i]/length-n[i] for i in range(3)])
prim['targets']=[{'POSITION':accessor(delta,'VEC3',target=34962),'NORMAL':accessor(normal_delta,'VEC3',target=34962)}]
g['meshes'][pebble_mesh].update(weights=[.35],extras={'targetNames':['Squash']})
pebble=place('Pebble · morph',pebble_mesh,forms,(-.25,.35,.7))
place('Brass study',sphere('Brass study',.18,copper),forms,(.35,.18,.8))
# A tapered, skinned tube with two joints. Mesh is a scene root as glTF recommends.
pos=[];norm=[];indices=[];joints=[];weights=[]
for j in range(33):
    y=j/32*1.25;r=.12*(1-.5*j/32)
    if j in (0,32):r=0
    for k in range(25):
        t=k/24*math.tau
        pos.append([.85+r*math.cos(t),.05+y,-.35+r*math.sin(t)])
        norm.append([math.cos(t),.048,math.sin(t)])
        l=math.sqrt(sum(a*a for a in norm[-1]));norm[-1]=[a/l for a in norm[-1]]
        w=max(0,min(1,(y-.25)/.75));joints.append([0,1 if w>0 else 0,0,0]);weights.append([1-w,w,0,0])
for j in range(32):
    for k in range(24):
        a=j*25+k;b=a+25;indices.extend([a,b,a+1,a+1,b,b+1])
ribbon_mesh=mesh('Ribbon',pos,norm,indices,blue)
pr=g['meshes'][ribbon_mesh]['primitives'][0]
pr['attributes'].update(JOINTS_0=accessor(joints,'VEC4',5123,34962),WEIGHTS_0=accessor(weights,'VEC4',target=34962))
rig=node('Ribbon rig')
root_joint=node('Base joint',rig,translation=[.85,.05,-.35])
tip_joint=node('Tip joint',root_joint,translation=[0,.6,0],rotation=[0,0,math.sin(-.3/2),math.cos(-.3/2)])
def inverse_translation(x,y,z):return [1,0,0,0,0,1,0,0,0,0,1,0,-x,-y,-z,1]
ibm=accessor([inverse_translation(.85,.05,-.35),inverse_translation(.85,.65,-.35)],'MAT4')
g['skins']=[{'name':'Ribbon · two joints','joints':[root_joint,tip_joint],'skeleton':root_joint,'inverseBindMatrices':ibm}]
ribbon=node('Ribbon · skinned',mesh=ribbon_mesh,skin=0)
place('Ribbon socket',cylinder('Socket',.20,.06,black),forms,(.85,0,-.35))
# Real authored spot, point and directional lights, visible through native scene gizmos.
lights=node('Lights',atelier)
def light(name,typ,color,intensity,xyz,rotation=None,**extra):
    ls=g['extensions']['KHR_lights_punctual']['lights'];li=len(ls);ls.append({'name':name,'type':typ,'color':color,'intensity':intensity,**extra})
    return node(name,lights,translation=list(xyz),rotation=rotation or [0,0,0,1],extensions={'KHR_lights_punctual':{'light':li}})
light('Lamp · warm spot','spot',[1,.78,.52],10,(-.65,.7,-.25),[-math.sqrt(.5),0,0,math.sqrt(.5)],range=3,spot={'innerConeAngle':.4,'outerConeAngle':.9})
light('Fill · cool point','point',[.65,.8,1],4,(1.1,1.4,.6),range=4)
light('Key · soft daylight','directional',[1,.94,.86],1.3,(0,2,1),aim((2,4,3),(0,0,0)))
g['cameras']=[{'name':'Display camera','type':'perspective','perspective':{'yfov':math.radians(38),'znear':.01,'zfar':100}}]
cam=node('Display camera',atelier,camera=0,translation=[3,2.3,4.5],rotation=aim((3,2.3,4.5),(0,.5,0)))
# Both visible deformations are deliberately gentle and loop exactly at four seconds.
times=accessor([0.,1.,2.,3.,4.],'SCALAR')
morph=accessor([.35,1.,.35,0.,.35],'SCALAR')
rot=accessor([[0,0,math.sin(a/2),math.cos(a/2)] for a in [-.3,.5,-.3,-.6,-.3]],'VEC4')
g['animations']=[{'name':'Breathe & sway','samplers':[{'input':times,'output':morph,'interpolation':'LINEAR'},{'input':times,'output':rot,'interpolation':'LINEAR'}],'channels':[{'sampler':0,'target':{'node':pebble,'path':'weights'}},{'sampler':1,'target':{'node':tip_joint,'path':'rotation'}}]}]
g['scenes'][0]['name']='01 · Display'
# Alternate scene keeps the forms and rig, removes the lamp. Reuse meshes, materials and skin.
# Merge construction parts into a single multi-material mesh per finished object.
# The outliner describes objects, rather than the modelling steps used to build them.
import copy
def merge_children(group, name):
    primitives=[]
    for child in g['nodes'][group].get('children',[]):
        n=g['nodes'][child]
        if 'mesh' not in n:continue
        for source in g['meshes'][n['mesh']]['primitives']:
            pr=copy.deepcopy(source);offset=n.get('translation',[0,0,0])
            points=read_float3(pr['attributes']['POSITION'])
            pr['attributes']['POSITION']=accessor([[v[i]+offset[i] for i in range(3)] for v in points],'VEC3',target=34962)
            primitives.append(pr)
    mi=len(g['meshes']);g['meshes'].append({'name':name,'primitives':primitives})
    g['nodes'][group]['mesh']=mi;g['nodes'][group].pop('children',None)
merge_children(stage,'Plinth');merge_children(lamp,'Table lamp')
g['nodes'][lamp]['name']='Table lamp'
g['nodes'][forms]['name']='Studies'
g['nodes'][pebble]['name']='Pebble'
g['nodes'][ribbon]['name']='Ribbon'
g['nodes'][rig]['name']='Armature'
g['nodes'][root_joint]['name']='Base';g['nodes'][tip_joint]['name']='Tip'
g['nodes'][lights]['name']='Lighting'
g['skins'][0]['name']='Ribbon rig'
# Both scenes reuse parentless roots. One skin and one camera definition, no duplicate assets.
roots=[stage,lamp,forms,rig,ribbon,lights,cam]
g['scenes']=[{'name':'Studio','nodes':roots},{'name':'Studies','nodes':[stage,forms,rig,ribbon,lights,cam]}]
# Strip unreachable construction nodes, meshes, and materials from the delivered asset.
reachable=set()
def visit(i):
    if i in reachable:return
    reachable.add(i)
    for c in g['nodes'][i].get('children',[]):visit(c)
for scene in g['scenes']:
    for r in scene['nodes']:visit(r)
ids={old:new for new,old in enumerate(sorted(reachable))}
g['nodes']=[g['nodes'][i] for i in sorted(reachable)]
for n in g['nodes']:
    if 'children' in n:n['children']=[ids[c] for c in n['children']]
for scene in g['scenes']:scene['nodes']=[ids[r] for r in scene['nodes']]
for skin in g['skins']:
    skin['joints']=[ids[j] for j in skin['joints']];skin['skeleton']=ids[skin['skeleton']]
for animation in g['animations']:
    for c in animation['channels']:c['target']['node']=ids[c['target']['node']]
used_meshes=sorted({n['mesh'] for n in g['nodes'] if 'mesh' in n});mesh_ids={old:new for new,old in enumerate(used_meshes)}
g['meshes']=[g['meshes'][m] for m in used_meshes]
for n in g['nodes']:
    if 'mesh' in n:n['mesh']=mesh_ids[n['mesh']]
# Share a compact palette across the whole display.
for m in g['meshes']:
    for pr in m['primitives']:
        if pr['material']==black:pr['material']=ink
        if pr['material']==stone:pr['material']=chalk
used=sorted({pr['material'] for m in g['meshes'] for pr in m['primitives']})
material_ids={old:new for new,old in enumerate(used)}
g['materials']=[g['materials'][m] for m in used]
for m in g['materials']:m['name']=m['name'].split(' · ')[-1]
for m in g['meshes']:
    for pr in m['primitives']:pr['material']=material_ids[pr['material']]
# Drop superseded binary accessors from the JSON (the aligned binary payload stays valid).
used_accessors=set()
for m in g['meshes']:
    for pr in m['primitives']:
        used_accessors.update(pr['attributes'].values());used_accessors.add(pr['indices'])
        for target in pr.get('targets',[]):used_accessors.update(target.values())
for skin in g['skins']:used_accessors.add(skin['inverseBindMatrices'])
for anim in g['animations']:
    for sampler in anim['samplers']:used_accessors.update([sampler['input'],sampler['output']])
aids={old:new for new,old in enumerate(sorted(used_accessors))}
g['accessors']=[g['accessors'][a] for a in sorted(used_accessors)]
for m in g['meshes']:
    for pr in m['primitives']:
        pr['attributes']={k:aids[v] for k,v in pr['attributes'].items()};pr['indices']=aids[pr['indices']]
        for target in pr.get('targets',[]):
            for k in target:target[k]=aids[target[k]]
for skin in g['skins']:skin['inverseBindMatrices']=aids[skin['inverseBindMatrices']]
for anim in g['animations']:
    for sampler in anim['samplers']:
        for k in ('input','output'):sampler[k]=aids[sampler[k]]
views=sorted({a['bufferView'] for a in g['accessors']});vids={old:new for new,old in enumerate(views)}
g['bufferViews']=[g['bufferViews'][v] for v in views]
for a in g['accessors']:a['bufferView']=vids[a['bufferView']]
g['buffers']=[{'byteLength':len(binary)}]
js=json.dumps(g,separators=(',',':'),ensure_ascii=False).encode();js+=b' '*((-len(js))%4);binary+=b'\0'*((-len(binary))%4)
DEST.parent.mkdir(parents=True,exist_ok=True)
DEST.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary)
print(f'{DEST}: {len(g["scenes"])} scenes, {len(g["nodes"])} nodes, {len(g["meshes"])} meshes, one morph, one skin, one animation')
