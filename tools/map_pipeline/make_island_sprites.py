from PIL import Image, ImageFilter
import numpy as np, json, os, math
from collections import deque
W,H=2048,1152
S=2
SEA=8000.0
base=Image.open('art/world_map/chart_base_v3.png').convert('RGB').resize((W*S,H*S),Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=3,percent=140,threshold=2))
mask=Image.open('art/world_map/land_mask_v2.png').convert('L').resize((W,H),Image.NEAREST)
mask=np.asarray(mask)>127
data=json.load(open('data/generated/region_islands.json'))
os.makedirs('art/islands',exist_ok=True)
ds=4
def rad_est(rr): return 240.0+(620.0-240.0)*min(1.0,max(0.0,rr/0.3))
for key,entry in data.items():
    sr=entry.get('sea_rect')
    if not sr: continue
    x0,y0,sw,sh=int(sr[0]*W),int(sr[1]*H),int(sr[2]*W),int(sr[3]*H)
    sub=mask[y0:y0+sh, x0:x0+sw]
    bh,bw=sub.shape
    if bh<ds or bw<ds:
        entry['islands']=[]; continue
    small=sub[:bh//ds*ds,:bw//ds*ds].reshape(bh//ds,ds,bw//ds,ds).mean(axis=(1,3))>0.5
    SH,SW=small.shape
    lab=np.zeros(small.shape,dtype=np.int32); comps=[]
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
                if len(pts)>=12: comps.append(pts)
    recs=[]
    for pts in comps:
        pys=[p[0] for p in pts]; pxs=[p[1] for p in pts]
        cw=(max(pxs)-min(pxs)+1)*ds; ch=(max(pys)-min(pys)+1)*ds
        recs.append({'pts':pts,'r':max(cw,ch)/2.0/bw,'bx':min(pxs)*ds,'by':min(pys)*ds,'bw':cw,'bh':ch})
    recs.sort(key=lambda z:-z['r'])
    acc=[]; out=[]
    for rec in recs:
        if len(out)>=8: break
        cx=(rec['bx']+rec['bw']/2)/bw; cy=(rec['by']+rec['bh']/2)/bh
        ok=True
        for (axx,ayy,ar) in acc:
            if math.hypot((cx-axx)*SEA,(cy-ayy)*SEA) < ar+rad_est(rec['r'])+1500.0:
                ok=False; break
        if not ok: continue
        acc.append((cx,cy,rad_est(rec['r'])))
        k=len(out)
        pad=6
        bx0,by0,bx1,by1=max(0,rec['bx']-pad),max(0,rec['by']-pad),min(bw,rec['bx']+int(rec['bw'])+pad),min(bh,rec['by']+int(rec['bh'])+pad)
        cmask=sub[by0:by1,bx0:bx1]
        if cmask.mean()<0.04: continue
        rgb=base.crop(((x0+bx0)*S, (y0+by0)*S, (x0+bx1)*S, (y0+by1)*S))
        cm=Image.fromarray((cmask*255).astype('uint8')).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.5))
        cm=cm.resize((rgb.width, rgb.height), Image.LANCZOS)
        spr=Image.new('RGBA',rgb.size)
        spr.paste(rgb,(0,0),cm)
        name='isl_%s_%d.png'%(key,k)
        spr.save('art/islands/'+name)
        w=rec['bw']/bw; h=rec['bh']/bh
        rad=min(0.1125,max(0.025,max(w,h)*0.45))
        dx,dy=0.5-cx,0.5-cy
        L=math.hypot(dx,dy) or 1.0
        px_=cx+dx/L*rad*0.8; py_=cy+dy/L*rad*0.8
        out.append({'x':round(cx,4),'y':round(cy,4),'r':round(rec['r'],4),'w':round(w,4),'h':round(h,4),
            'rad':round(rad,4),'px':round(px_,4),'py':round(py_,4),'sprite':'islands/'+name})
    entry['islands']=out
json.dump(data,open('data/generated/region_islands.json','w'),ensure_ascii=False,indent=1)
print('sprites v2', sum(len(v['islands']) for v in data.values()))