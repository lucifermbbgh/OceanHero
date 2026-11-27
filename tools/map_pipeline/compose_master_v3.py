from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np, json, glob, re, math, os
from collections import deque
W,H=2048,1152
FONT=None
for fp in ['/System/Library/Fonts/PingFang.ttc','/System/Library/Fonts/STHeiti Medium.ttc']:
    if os.path.exists(fp): FONT=fp; break
def F(s): return ImageFont.truetype(FONT,s) if FONT else ImageFont.load_default()
COLORS={'lan':(92,142,214),'chilin':(198,84,74),'shuangyu':(150,204,228),'xuanjiao':(142,116,168),'baijing':(228,228,236),'cangwu':(108,168,120),'youming':(118,92,148)}
NAMES={'lan':'云澜','chilin':'赤鳞','shuangyu':'霜屿','xuanjiao':'玄礁','baijing':'白鲸','cangwu':'苍梧','youming':'幽溟'}
nations={}
for p in glob.glob('data/maps/*.tres'):
    t=open(p,encoding='utf-8').read()
    m=re.search(r'^index = (\d+)$',t,re.M); n=re.search(r'^nation = &"([a-z_]+)"$',t,re.M)
    if m: nations[int(m.group(1))]=n.group(1) if n else ''
img=Image.open('art/world_map/ai_map_try3.png').convert('RGB').resize((W,H),Image.LANCZOS)
a=np.asarray(img,dtype=np.int16)
R,G,B=a[...,0],a[...,1],a[...,2]
land=((R>G+8)&(R>140))|((G>R+8)&(B<100)&(G>80))
lm=Image.fromarray((land*255).astype('uint8')).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
lm.save('art/world_map/land_mask_v2.png')
mask=np.asarray(lm)>127
regions=json.load(open('data/generated/world_regions.json'))['regions']
def pip(x,y,poly):
    c=False; j=len(poly)-1
    for i in range(len(poly)):
        xi,yi=poly[i]; xj,yj=poly[j]
        if ((yi>y)!=(yj>y)) and (x < (xj-xi)*(y-yi)/(yj-yi+1e-9)+xi): c=not c
        j=i
    return c
# 每区域：先求「海域矩形」（区域内海面像素 bbox），岛屿相对海域矩形定位
region_islands={}
for r in regions:
    idx=int(r['index'])
    poly=[(p[0]*W,p[1]*H) for p in r['polygon']]
    xs=[p[0] for p in poly]; ys=[p[1] for p in poly]
    bx0,by0,bx1,by1=int(min(xs)),int(min(ys)),int(max(xs)),int(max(ys))
    bw,bh=max(2,bx1-bx0),max(2,by1-by0)
    inside=np.zeros((bh,bw),bool)
    yy,xx=np.mgrid[by0:by1,bx0:bx1]
    for i in range(bh):
        for j in range(bw):
            inside[i,j]=pip(xx[i,j],yy[i,j],poly)
    sub_land=mask[by0:by1,bx0:bx1]&inside
    sub_sea=inside&(~mask[by0:by1,bx0:bx1])
    sea_frac=sub_sea.sum()/max(1,inside.sum())
    if sea_frac>0.25 and sub_sea.sum()>0:
        sy,sx=np.nonzero(sub_sea)
        rx0,rx1=sx.min(),sx.max(); ry0,ry1=sy.min(),sy.max()
    else:
        rx0,ry0,rx1,ry1=0,0,bw-1,bh-1
    rw,rh=max(2,rx1-rx0),max(2,ry1-ry0)
    # 海域矩形内的陆地连通域 = 岛屿
    isl_mask=sub_land[ry0:ry1,rx0:rx1]
    ds=4
    sh,sw=isl_mask.shape
    isl=[]
    if sh>=ds and sw>=ds:
        small=isl_mask[:sh//ds*ds,:sw//ds*ds].reshape(sh//ds,ds,sw//ds,ds).mean(axis=(1,3))>0.5
        lab=np.zeros(small.shape,dtype=np.int32)
        SH,SW=small.shape
        for i in range(SH):
            for j in range(SW):
                if small[i,j] and lab[i,j]==0:
                    q=deque([(i,j)]); lab[i,j]=1; pts=[]
                    while q:
                        y,x=q.popleft(); pts.append((y,x))
                        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
                            ny,nx=y+dy,x+dx
                            if 0<=ny<SH and 0<=nx<SW and small[ny,nx] and lab[ny,nx]==0:
                                lab[ny,nx]=1; q.append((ny,nx))
                    if len(pts)>=12:
                        pys=[p[0] for p in pts]; pxs=[p[1] for p in pts]
                        lx=(sum(pxs)/len(pxs))*ds/rw; ly=(sum(pys)/len(pys))*ds/rh
                        lr=min(0.45,(max(max(pxs)-min(pxs),max(pys)-min(pys))/2)*ds/rw)
                        isl.append({'x':round(lx,4),'y':round(ly,4),'r':round(lr,4)})
    isl.sort(key=lambda z:-z['r'])
    region_islands[str(idx)]={'sea_rect':[round((bx0+rx0)/W,5),round((by0+ry0)/H,5),round(rw/W,5),round(rh/H,5)],'islands':isl[:8]}
json.dump(region_islands, open('data/generated/region_islands.json','w'), ensure_ascii=False, indent=1)
tot=sum(len(v['islands']) for v in region_islands.values())
print('islands total', tot, {k:len(v['islands']) for k,v in list(region_islands.items())[:6]})

# 底图（无叠加）保存
img.save('art/world_map/chart_base_v3.png')
# 叠加层
img=img.convert('RGBA')
ov=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(ov,'RGBA')
def dashed(dr,p0,p1,col,w=1,dash=12,gap=9):
    ax,ay=p0; bx,by=p1
    L=math.hypot(bx-ax,by-ay)
    if L<1: return
    ux,uy=(bx-ax)/L,(by-ay)/L
    t=0
    while t<L:
        e=min(t+dash,L)
        dr.line([(ax+ux*t,ay+uy*t),(ax+ux*e,ay+uy*e)],fill=col,width=w)
        t=e+gap
anchors={}
for r in regions:
    idx=int(r['index'])
    ax,ay=r['anchor'][0]*W, r['anchor'][1]*H
    step=0
    while mask[int(ay),int(ax)] and step<90:
        step+=1
        ang=step*0.6
        ax=r['anchor'][0]*W+math.cos(ang)*step*14
        ay=r['anchor'][1]*H+math.sin(ang)*step*14
        ax=min(max(ax,12),W-12); ay=min(max(ay,12),H-12)
    anchors[idx]=(ax,ay)
    r['anchor']=[round(ax/W,5), round(ay/H,5)]
json.dump({'source':'world_regions.tmj','canvas':[float(W),float(H)],'regions':regions}, open('data/generated/world_regions.json','w'), ensure_ascii=False, indent=1)
for r in regions:
    pts=[(p[0]*W,p[1]*H) for p in r['polygon']]
    closed=pts+[pts[0]]
    for i in range(len(closed)-1):
        dashed(d,closed[i],closed[i+1],(235,240,245,55),1,10,10)
for r in regions:
    idx=int(r['index'])
    t=open('data/maps/map%d.tres'%idx,encoding='utf-8').read()
    m=re.search(r'^neighbors = \[([^\]]*)\]',t,re.M)
    if not m: continue
    for nb in [int(v) for v in re.findall(r'-?\d+',m.group(1))]:
        if nb<=idx or nb not in anchors: continue
        ta=(idx-1)//3; tb=(nb-1)//3
        if abs(ta-tb)>1: continue
        if abs(ta-tb)==1:
            dashed(d,anchors[idx],anchors[nb],(210,230,240,110),1,14,10)
        else:
            d.line([anchors[idx],anchors[nb]],fill=(210,230,240,130),width=2)
for idx,(x,y) in anchors.items():
    fac=nations.get(idx,'')
    ring=COLORS.get(fac,(232,178,58))
    d.ellipse([x-13,y-13,x+13,y+13],fill=ring+(235,))
    d.ellipse([x-9,y-9,x+9,y+9],fill=(232,178,58,255),outline=(30,50,66,255),width=2)
    d.ellipse([x-3,y-3,x+3,y+3],fill=(255,246,220,255))
for idx,(x,y) in anchors.items():
    d.text((x+17,y-8),'%d-%d'%((idx-1)//3+1,(idx-1)%3+1),fill=(252,252,248,240),font=F(15))
img=Image.alpha_composite(img,ov)
d=ImageDraw.Draw(img,'RGBA')
for row in range(10):
    y=(0.08+row*0.088)*H
    d.text((26,y-10),'%d级'%(row+1),fill=(250,244,222,200),font=F(17))
for t2,(x,y) in {'N':(W//2-8,10),'S':(W//2-8,H-44),'W':(14,H//2-14),'E':(W-32,H//2-14)}.items():
    d.text((x,y),t2,fill=(250,244,222,230),font=F(28))
cmp=Image.open('art/world_map/tex_compass_v1.png').convert('RGBA')
px=cmp.load()
for y in range(cmp.height):
    for x in range(cmp.width):
        r0,g0,b0,al=px[x,y]
        if r0>235 and g0>230 and b0>220: px[x,y]=(r0,g0,b0,0)
cmp=cmp.resize((150,150))
img.alpha_composite(cmp,(W-200,H-230))
d=ImageDraw.Draw(img,'RGBA')
d.rectangle([40,30,560,132],fill=(238,226,196,235),outline=(60,44,26,255),width=3)
d.rectangle([46,36,554,126],outline=(120,94,58,180),width=1)
d.text((66,44),'碧海英豪 · 万海航图',fill=(52,38,22,255),font=F(36))
d.text((68,96),'WAN HAI CHART · NAVIGATION BOARD',fill=(92,70,44,255),font=F(15))
lx,ly=40,H-176
d.rectangle([lx,ly,lx+470,ly+140],fill=(238,226,196,230),outline=(60,44,26,255),width=3)
d.text((lx+16,ly+10),'图例 LEGEND',fill=(52,38,22,255),font=F(19))
items=[('海域节点 / 势力环 NODE',(232,178,58)),('常规航路 PASSAGE',(150,180,195)),('跨级航路 PERILOUS',(150,180,195)),('陆地 / 浅滩 LAND',(210,190,150)),('区域边界 BOUNDARY',(235,240,245))]
for i,(name,col) in enumerate(items):
    yy=ly+40+i*19
    if i==2 or i==4:
        dashed(d,(lx+16,yy+6),(lx+52,yy+6),col+(230,),2 if i==2 else 1,8,6)
    else:
        d.ellipse([lx+22,yy,lx+46,yy+12],fill=col+(255,),outline=(60,44,26,200))
    d.text((lx+60,yy-3),name,fill=(52,38,22,255),font=F(13))
for i,(nat,col) in enumerate(COLORS.items()):
    x=560+i*190; y=H-46
    d.ellipse([x,y,x+24,y+24],fill=col+(255,),outline=(250,244,222,255),width=2)
    d.text((x+32,y+1),NAMES[nat],fill=(250,244,222,235),font=F(18))
d.line([(W-330,H-100),(W-130,H-100)],fill=(250,244,222,230),width=3)
for i in range(5):
    x=W-330+i*50
    d.line([(x,H-108),(x,H-92)],fill=(250,244,222,230),width=2)
d.text((W-330,H-132),'0            10 里',fill=(250,244,222,210),font=F(14))
d.rectangle([6,6,W-7,H-7],outline=(210,180,120,230),width=5)
d.rectangle([16,16,W-17,H-17],outline=(90,70,44,160),width=1)
img.convert('RGB').save('art/world_map/master_chart_v3.png')
print('master v3 + base + islands saved')