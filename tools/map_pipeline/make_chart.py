from PIL import Image, ImageDraw, ImageFont
import json, glob, re, math, os
W,H=2048,1152
FONT=None
for fp in ['/System/Library/Fonts/PingFang.ttc','/System/Library/Fonts/STHeiti Medium.ttc']:
    if os.path.exists(fp): FONT=fp; break
def F(s): return ImageFont.truetype(FONT,s) if FONT else ImageFont.load_default()
DEEP=(27,74,107); MID=(38,92,128); SHALLOW=(191,217,226); LAND=(232,223,200)
COAST=(23,57,79); NODE=(232,178,58); ROUTE=(116,158,184); TXT=(240,235,215)
FAC={'lan':(92,142,214),'chilin':(198,84,74),'shuangyu':(150,204,228),'xuanjiao':(142,116,168),'baijing':(228,228,236),'cangwu':(108,168,120),'youming':(118,92,148)}
nations={}
for p in glob.glob('data/maps/*.tres'):
    t=open(p,encoding='utf-8').read()
    m=re.search(r'^index = (\d+)$',t,re.M); n=re.search(r'^nation = &"([a-z_]+)"$',t,re.M)
    if m: nations[int(m.group(1))]=n.group(1) if n else ''
img=Image.new('RGB',(W,H),DEEP)
d=ImageDraw.Draw(img)
# 海面细纹
for k in range(60):
    y=40+k*19
    for x in range(0,W,180):
        d.line([(x,y),(x+90,y)],fill=(34,84,116),width=1)
land=json.load(open('data/source/land_masses.json'))['land']
polys=[[(p[0]*W,p[1]*H) for p in it['polygon']] for it in land]
def centroid(poly):
    return (sum(p[0] for p in poly)/len(poly), sum(p[1] for p in poly)/len(poly))
# 浅滩环
for poly in polys:
    cx,cy=centroid(poly)
    ring=[(cx+(x-cx)*1.13, cy+(y-cy)*1.13) for x,y in poly]
    d.polygon(ring,fill=MID)
    ring2=[(cx+(x-cx)*1.07, cy+(y-cy)*1.07) for x,y in poly]
    d.polygon(ring2,fill=SHALLOW)
# 陆地
for poly in polys:
    d.polygon(poly,fill=LAND)
    d.line(poly+[poly[0]],fill=COAST,width=5)
# 区域边界虚线与节点
regions=json.load(open('data/generated/world_regions.json'))['regions']
def dashed(a,b,col,w=2,dash=10,gap=8):
    ax,ay=a; bx,by=b
    L=math.hypot(bx-ax,by-ay)
    if L<1: return
    ux,uy=(bx-ax)/L,(by-ay)/L
    t=0
    while t<L:
        e=min(t+dash,L)
        d.line([(ax+ux*t,ay+uy*t),(ax+ux*e,ay+uy*e)],fill=col,width=w)
        t=e+gap
for r in regions:
    pts=[(p[0]*W,p[1]*H) for p in r['polygon']]
    closed=pts+[pts[0]]
    for i in range(len(closed)-1):
        dashed(closed[i],closed[i+1],(60,110,140),1,8,8)
anchors={}
for r in regions:
    idx=int(r['index'])
    anchors[idx]=(r['anchor'][0]*W, r['anchor'][1]*H)
# 航线
for idx,(x,y) in anchors.items():
    md=None
    for p in glob.glob('data/maps/map%d.tres'%idx):
        t=open(p,encoding='utf-8').read()
        m=re.search(r'^neighbors = \[([^\]]*)\]',t,re.M)
        if m:
            md=[int(v) for v in re.findall(r'-?\d+',m.group(1))]
    if not md: continue
    for nb in md:
        if nb<=idx or nb not in anchors: continue
        ax,ay=anchors[nb]
        tier_a=(idx-1)//3; tier_b=(nb-1)//3
        if abs(tier_a-tier_b)>1:
            continue
        if abs(tier_a-tier_b)>=1:
            dashed((x,y),(ax,ay),ROUTE,2,12,9)
        else:
            d.line([(x,y),(ax,ay)],fill=ROUTE,width=3)


# 节点
for idx,(x,y) in anchors.items():
    fac=nations.get(idx,'')
    ring=FAC.get(fac,NODE)
    d.ellipse([x-15,y-15,x+15,y+15],fill=ring)
    d.ellipse([x-11,y-11,x+11,y+11],fill=NODE,outline=COAST,width=2)
    d.ellipse([x-4,y-4,x+4,y+4],fill=(255,244,214))
# 编号
for idx,(x,y) in anchors.items():
    label='%d-%d'%((idx-1)//3+1,(idx-1)%3+1)
    d.text((x+18,y-9),label,fill=(220,235,240),font=F(15))
# 标题饰框
d.rectangle([40,28,900,118],fill=LAND,outline=COAST,width=3)
d.text((64,40),'碧海英豪 · 万海航图',fill=COAST,font=F(34))
d.text((66,90),'THE AZURE REACHES  ·  NAVIGATION BOARD',fill=(70,95,110),font=F(16))
# 罗盘（小）
cmp=Image.open('art/world_map/tex_compass_v1.png').convert('RGBA')
px=cmp.load()
for yy in range(cmp.height):
    for xx in range(cmp.width):
        r,g,b,a=px[xx,yy]
        if r>235 and g>230 and b>220: px[xx,yy]=(r,g,b,0)
cmp=cmp.resize((120,120))
img=img.convert('RGBA')
img.alpha_composite(cmp.convert('RGBA'),(60,150))
img=img.convert('RGB')
d=ImageDraw.Draw(img)
# 图例
lx,ly=40,H-190
d.rectangle([lx,ly,lx+430,ly+150],fill=LAND,outline=COAST,width=3)
d.text((lx+18,ly+12),'图例 LEGEND',fill=COAST,font=F(20))
items=[('深海 DEEP OCEAN',DEEP),('浅滩 SHALLOWS',SHALLOW),('陆地 LAND',LAND),('常规航路 PASSAGE',ROUTE),('危险航路 PERILOUS',None),('海域节点 NODE',NODE)]
for i,(name,col) in enumerate(items):
    yy=ly+46+i*17
    if col is None:
        dashed((lx+18,yy+6),(lx+58,yy+6),(120,160,180),3,8,6)
    else:
        d.rectangle([lx+18,yy,lx+50,yy+12],fill=col,outline=COAST)
    d.text((lx+64,yy-2),name,fill=(40,66,80),font=F(13))
# 比例尺 + 方向
d.line([(W-300,H-52),(W-100,H-52)],fill=TXT,width=3)
for i in range(5):
    x=W-300+i*50
    d.line([(x,H-60),(x,H-44)],fill=TXT,width=2)
d.text((W-300,H-86),'0            10 里',fill=TXT,font=F(14))
d.text((W-60,30),'N',fill=TXT,font=F(28))
d.text((W-60,H-80),'S',fill=TXT,font=F(24))
d.text((24,H//2),'W',fill=TXT,font=F(24))
d.text((W-44,H//2),'E',fill=TXT,font=F(24))
# 外框
d.rectangle([8,8,W-9,H-9],outline=(150,190,205),width=6)
d.rectangle([18,18,W-19,H-19],outline=(60,110,140),width=2)
img.save('art/world_map/chart_design_v1.png')
print('chart saved')