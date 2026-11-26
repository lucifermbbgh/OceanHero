from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np, json, glob, re, math, os, random
from collections import deque
random.seed(21)
W,H=2048,1152
FONT=None
for fp in ['/System/Library/Fonts/PingFang.ttc','/System/Library/Fonts/STHeiti Medium.ttc']:
    if os.path.exists(fp): FONT=fp; break
def F(s): return ImageFont.truetype(FONT,s) if FONT else ImageFont.load_default()
t3=Image.open('art/world_map/ai_map_try3.png').convert('RGB')
t4=Image.open('art/world_map/ai_map_try4.png').convert('RGB')
oce=Image.open('art/world_map/spr_ocean.png').convert('RGB')
def classify(pil):
    a=np.asarray(pil,dtype=np.int16)
    R,G,B=a[...,0],a[...,1],a[...,2]
    land=((R>G+8)&(R>140))|((G>R+8)&(B<100)&(G>80))
    shallow=(B>150)&(G>170)&(R>90)&((R+G+B)>470)
    return (land|shallow)
m3=classify(t3); m4=classify(t4)
# 连通域（降采样 BFS）
def components(mask, src, min_frac=0.004):
    ds=4
    h,w=mask.shape
    small=mask[:h//ds*ds, :w//ds*ds].reshape(h//ds,ds,w//ds,ds).mean(axis=(1,3))>0.5
    lab=np.zeros(small.shape,dtype=np.int32); cur=0; out=[]
    SH,SW=small.shape
    for i in range(SH):
        for j in range(SW):
            if small[i,j] and lab[i,j]==0:
                cur+=1; q=deque([(i,j)]); lab[i,j]=cur; pts=[]
                while q:
                    y,x=q.popleft(); pts.append((y,x))
                    for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
                        ny,nx=y+dy,x+dx
                        if 0<=ny<SH and 0<=nx<SW and small[ny,nx] and lab[ny,nx]==0:
                            lab[ny,nx]=cur; q.append((ny,nx))
                if len(pts)*ds*ds >= min_frac*h*w:
                    ys=[p[0]*ds for p in pts]; xs=[p[1]*ds for p in pts]
                    out.append({'area':len(pts)*ds*ds,'bbox':(min(xs),min(ys),max(xs)+ds,max(ys)+ds),'src':src,'mask':mask})
    return out
comps=components(m3,t3)+components(m4,t4)
comps.sort(key=lambda c:-c['area'])
print('components', len(comps), [c['area'] for c in comps[:10]])
# 海面底
yy=np.linspace(0,1,H)[:,None]
arr=np.zeros((H,W,3),dtype=np.float32)
arr[...,0]=10+10*yy; arr[...,1]=48+16*yy; arr[...,2]=74+22*yy
base=Image.fromarray(np.clip(arr,0,255).astype('uint8'))
base=Image.blend(base, oce.resize((W,H),Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.6)), 0.30)
d=ImageDraw.Draw(base,'RGBA')
for k in range(70):
    y0=(k*61)%H
    d.line([(x,y0+math.sin(x/64.0+k)*3) for x in range(0,W,22)],fill=(120,180,195,18),width=1)
img=base.convert('RGBA')
def stamp(comp, cx, cy, size, rot=0, flip=False):
    x0,y0,x1,y1=comp['bbox']
    pad=10
    src=comp['src']; mk=comp['mask']
    rgb=src.crop((max(0,x0-pad),max(0,y0-pad),min(src.width,x1+pad),min(src.height,y1+pad)))
    am=Image.fromarray((mk[max(0,y0-pad):min(src.height,y1+pad), max(0,x0-pad):min(src.width,x1+pad)]*255).astype('uint8'))
    am=am.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
    if flip:
        rgb=rgb.transpose(Image.FLIP_LEFT_RIGHT); am=am.transpose(Image.FLIP_LEFT_RIGHT)
    if rot:
        rgb=rgb.rotate(rot,expand=True,fillcolor=(0,0,0)); am=am.rotate(rot,expand=True,fillcolor=0)
    rgb=rgb.resize(size,Image.LANCZOS); am=am.resize(size,Image.LANCZOS)
    img.paste(rgb,(int(cx*W-size[0]/2),int(cy*H-size[1]/2)),am)
slots=[((0.155,0.30),(470,330)),((0.27,0.545),(260,200)),((0.60,0.20),(380,260)),
 ((0.80,0.44),(500,350)),((0.53,0.72),(320,420)),((0.88,0.80),(260,210))]
for i,((cx,cy),size) in enumerate(slots):
    c=comps[i % len(comps)]
    stamp(c,cx,cy,size,random.choice([0,90,180,270]),random.random()<0.5)
for i in range(10):
    c=comps[min(len(comps)-1, 4+i%max(1,len(comps)-4))]
    s=random.randint(70,150)
    stamp(c, random.uniform(0.06,0.94), random.uniform(0.08,0.92), (s,s), random.choice([0,90,180,270]), random.random()<0.5)
img.convert('RGB').save('art/world_map/chart_base_v2.png')
lm=Image.fromarray((classify(img.convert('RGB'))*255).astype('uint8')).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(3))
lm.save('art/world_map/land_mask_v2.png')
print('v2 saved')