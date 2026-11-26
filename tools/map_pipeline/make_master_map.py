from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np, json, glob, re, math, os
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
# 海面渐变
yy=np.linspace(0,1,H)[:,None]; xx=np.linspace(0,1,W)[None,:]
arr=np.zeros((H,W,3),dtype=np.float32)
arr[...,0]=7+9*yy; arr[...,1]=38+17*yy; arr[...,2]=62+24*yy
rng=np.random.default_rng(5)
noise=rng.random((24,42))
nimg=Image.fromarray((noise*255).astype('uint8')).resize((W,H),Image.BICUBIC)
na=np.asarray(nimg,dtype=np.float32)/255.0
arr+=((na-0.5)*10)[...,None]
img=Image.fromarray(np.clip(arr,0,255).astype('uint8')).convert('RGBA')
d=ImageDraw.Draw(img,'RGBA')
for cx,cy in [(W*0.5,H*0.5),(W*0.85,H*0.8)]:
    for k in range(16):
        a=math.pi*2*k/16
        d.line([(cx,cy),(cx+math.cos(a)*2600,cy+math.sin(a)*2600)],fill=(90,150,175,16),width=1)
for k in range(90):
    y0=(k*71)%H
    d.line([(x,y0+math.sin(x/60.0+k)*3) for x in range(0,W,20)],fill=(80,140,170,20),width=1)
# 区域（海面层）
regions=json.load(open('data/generated/world_regions.json'))['regions']
for r in regions:
    idx=int(r['index']); col=COLORS.get(nations.get(idx,''),(140,140,140))
    pts=[(p[0]*W,p[1]*H) for p in r['polygon']]
    d.polygon(pts, fill=col+(26,))
    d.line(pts+[pts[0]], fill=col+(120,), width=2)
# 陆地（阴影 + 羊皮纸 + 双线）
land=json.load(open('data/source/land_masses.json'))['land']
polys=[[(p[0]*W,p[1]*H) for p in it['polygon']] for it in land]
paper=Image.open('art/world_map/tex_parchment_v1.png').convert('RGB').resize((W,H))
paper=Image.blend(paper,Image.new('RGB',(W,H),(236,222,188)),0.4)
mask=Image.new('L',(W,H),0); md=ImageDraw.Draw(mask)
for poly in polys: md.polygon(poly,fill=255)
shadow=Image.new('RGBA',(W,H),(0,0,0,0)); sd=ImageDraw.Draw(shadow)
for poly in polys: sd.polygon([(x+6,y+7) for x,y in poly],fill=(0,0,0,95))
shadow=shadow.filter(ImageFilter.GaussianBlur(4))
img=Image.alpha_composite(img,shadow)
img.paste(paper,(0,0),mask)
d=ImageDraw.Draw(img, 'RGBA')
for poly in polys:
    d.line(poly+[poly[0]],fill=(68,50,30,255),width=5)
    d.line(poly+[poly[0]],fill=(250,240,214,120),width=2)
# 徽标
def badge(cx,cy,R,nat):
    col=COLORS[nat]
    d.ellipse([cx-R,cy-R,cx+R,cy+R],fill=col+(255,),outline=(232,205,140,255),width=3)
    if nat=='lan':
        for k in range(3): d.arc([cx-R*0.55,cy-R*0.3+k*8,cx+R*0.55,cy+R*0.3+k*8],200,340,fill=(255,255,255,230),width=3)
    elif nat=='chilin':
        for k in range(3): d.polygon([(cx-R*0.5+k*12,cy+R*0.35),(cx-R*0.1+k*12,cy-R*0.35),(cx+R*0.3+k*12,cy+R*0.35)],outline=(255,255,255,220))
    elif nat=='shuangyu':
        for k in range(6):
            a=math.pi*k/3
            d.line([(cx-math.cos(a)*R*0.55,cy-math.sin(a)*R*0.55),(cx+math.cos(a)*R*0.55,cy+math.sin(a)*R*0.55)],fill=(255,255,255,230),width=3)
    elif nat=='xuanjiao':
        d.polygon([(cx+R*0.55*math.cos(a),cy+R*0.55*math.sin(a)) for a in [math.pi/6+math.pi*k/3 for k in range(6)]],outline=(255,255,255,230))
    elif nat=='baijing':
        d.arc([cx-R*0.5,cy-R*0.15,cx+R*0.5,cy+R*0.6],300,120,fill=(255,255,255,230),width=3)
        d.line([(cx,cy-R*0.45),(cx,cy+R*0.05)],fill=(255,255,255,230),width=3)
    elif nat=='cangwu':
        d.line([(cx,cy+R*0.45),(cx,cy-R*0.05)],fill=(255,255,255,230),width=3)
        d.polygon([(cx,cy-R*0.55),(cx+R*0.45,cy-R*0.05),(cx,cy-R*0.1),(cx-R*0.45,cy-R*0.05)],outline=(255,255,255,230))
    else:
        for k in range(3): d.arc([cx-R*0.5+k*6,cy-R*0.5+k*6,cx+R*0.5+k*6,cy+R*0.5+k*6],0,300,fill=(255,255,255,210),width=2)
for i,(nat,col) in enumerate(COLORS.items()):
    cx=70+i*280; cy=H-70
    badge(cx,cy,24,nat)
    d.text((cx+34,cy-12),NAMES[nat],fill=(240,228,196,255),font=F(22))
for row in range(10):
    y=(0.08+row*0.088)*H
    d.text((26,y-10),'%d级'%(row+1),fill=(238,224,188,210),font=F(17))
for t,(x,y) in {'N':(W//2-8,12),'S':(W//2-8,H-44),'W':(16,H//2-14),'E':(W-34,H//2-14)}.items():
    d.text((x,y),t,fill=(238,224,188,235),font=F(30))
cmp=Image.open('art/world_map/tex_compass_v1.png').convert('RGBA')
px=cmp.load()
for y in range(cmp.height):
    for x in range(cmp.width):
        r,g,b,a=px[x,y]
        if r>235 and g>230 and b>220: px[x,y]=(r,g,b,0)
cmp=cmp.resize((220,220))
img.alpha_composite(cmp,(W-270,H-290))
d=ImageDraw.Draw(img, 'RGBA')
d.rectangle([44,40,470,150],fill=(236,222,188,235),outline=(110,82,46,255),width=2)
d.text((72,58),'碧海英豪',fill=(66,46,26,255),font=F(38))
d.text((72,108),'万 海 航 图 · 母 版 v1',fill=(92,70,44,255),font=F(17))
d.line([(W-320,H-52),(W-120,H-52)],fill=(238,224,188,230),width=3)
for i in range(5):
    x=W-320+i*50
    d.line([(x,H-60),(x,H-44)],fill=(238,224,188,230),width=2)
d.text((W-320,H-84),'0            10 里',fill=(238,224,188,210),font=F(14))
d.rectangle([8,8,W-9,H-9],outline=(178,148,98,230),width=5)
d.rectangle([20,20,W-21,H-21],outline=(120,94,58,180),width=1)
bg=Image.new('RGBA',(W,H),(10,40,62,255))
out=Image.alpha_composite(bg,img)
out.convert('RGB').save('art/world_map/master_map_v1.png')
print('master v2 saved')