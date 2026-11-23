import json, math, random
random.seed(20261123)
W, H = 4096.0, 2304.0
xs = [0.20, 0.50, 0.80]
seeds = []
for row in range(10):
    for col in range(3):
        x = xs[col]*W + random.uniform(-160, 160)
        y = (0.08 + row*0.088)*H + random.uniform(-70, 70)
        seeds.append((x, y))
rect = [(20.0,20.0),(W-20.0,20.0),(W-20.0,H-20.0),(20.0,H-20.0)]
def clip(poly, nx, ny, c):
    out = []
    n = len(poly)
    for i in range(n):
        a = poly[i]; b = poly[(i+1)%n]
        da = nx*a[0]+ny*a[1]-c; db = nx*b[0]+ny*b[1]-c
        if da <= 0: out.append(a)
        if (da < 0 < db) or (db < 0 < da):
            t = da/(da-db)
            out.append((a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t))
    return out
objects=[]; idx=1
for i, s in enumerate(seeds):
    poly=list(rect)
    for j, t in enumerate(seeds):
        if i==j: continue
        nx, ny = t[0]-s[0], t[1]-s[1]
        c = 0.5*(t[0]*t[0]+t[1]*t[1]-s[0]*s[0]-s[1]*s[1])
        poly = clip(poly, nx, ny, c)
        if not poly: break
    poly = [(min(max(x,1),W-1), min(max(y,1),H-1)) for x,y in poly]
    objects.append({'id': idx,'name':'map%d'%idx,'type':'Region','x':0,'y':0,'width':0,'height':0,'rotation':0,'visible':True,
        'polygon':[{'x':round(x,1),'y':round(y,1)} for x,y in poly],
        'properties':[{'name':'region_id','type':'string','value':'map%d'%idx},{'name':'index','type':'int','value':idx}]})
    idx += 1
tmj={'type':'map','version':'1.10','tiledversion':'1.12.2','orientation':'orthogonal','renderorder':'right-down',
    'width':128,'height':72,'tilewidth':32,'tileheight':32,'infinite':False,'nextlayerid':2,'nextobjectid':idx,
    'layers':[{'type':'objectgroup','name':'Regions','id':1,'opacity':1,'visible':True,'objects':objects}]}
json.dump(tmj, open('data/source/world_regions.tmj','w'), ensure_ascii=False, indent=1)
print('regions', len(objects))