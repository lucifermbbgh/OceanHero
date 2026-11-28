from PIL import Image
import numpy as np, os
names1=['wheat','rice','grain','potato','fruit','fish','meat','spice','sugarcane','cotton','flax','timber','stone','clay','iron_ore','copper']
names2=['silver','goldb','gem','cloth','pottery','tools','rum','beer','musket','cannon_goods','ammo_goods','saltpeter']
os.makedirs('art/icons/commodity',exist_ok=True)
def slice_sheet(path, names):
    img=Image.open(path).convert('RGB')
    W,H=img.size
    cw,ch=W//4,H//4
    out=[]
    for i,nm in enumerate(names):
        cx,cy=i%4,i//4
        cell=img.crop((cx*cw,cy*ch,(cx+1)*cw,(cy+1)*ch))
        a=np.asarray(cell,dtype=np.int16)
        # 白底→透明，保留阴影边缘
        lum=a.min(axis=2)
        alpha=np.clip((250-lum)*4,0,255).astype('uint8')
        rgba=np.dstack([a.astype('uint8'),alpha])
        im=Image.fromarray(rgba,'RGBA')
        # 裁到内容 bbox
        bb=im.getbbox()
        if bb: im=im.crop(bb)
        im=im.resize((128,128),Image.LANCZOS)
        im.save('art/icons/commodity/%s.png'%nm)
        out.append((nm, alpha.mean()))
    return out
r1=slice_sheet('art/source/commodity_sheet1.png',names1)
r2=slice_sheet('art/source/commodity_sheet2.png',names2)
empty=[n for n,m in r1+r2 if m<8]
print('sliced', len(r1)+len(r2), 'suspect-empty', empty)
# 校验图
from PIL import ImageDraw
ids=[n for n,_ in r1]+[n for n,_ in r2]
sheet=Image.new('RGB',(8*140,4*140),(30,30,30))
d=ImageDraw.Draw(sheet)
for i,nm in enumerate(ids):
    im=Image.open('art/icons/commodity/%s.png'%nm).convert('RGBA')
    bg=Image.new('RGBA',(140,140),(52,52,52,255))
    bg.paste(im,(6,6),im)
    sheet.paste(bg.convert('RGB'),((i%8)*140,(i//8)*140))
    d.text(((i%8)*140+4,(i//8)*140+124),nm,fill=(255,255,255))
sheet.save('art/icons/commodity/_contact.png')
print('contact saved')