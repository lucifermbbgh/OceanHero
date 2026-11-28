from PIL import Image, ImageDraw
import numpy as np, os, glob
os.makedirs('art/icons/gear',exist_ok=True)
ids=[]
for p in sorted(glob.glob('art/source/gear_*.png')):
    nm=os.path.basename(p)[5:-4]
    ids.append(nm)
    cell=Image.open(p).convert('RGB')
    a=np.asarray(cell,dtype=np.int16)
    lum=a.min(axis=2)
    alpha=np.clip((248-lum)*5,0,255).astype('uint8')
    im=Image.fromarray(np.dstack([a.astype('uint8'),alpha]),'RGBA')
    bb=im.getbbox()
    if bb: im=im.crop(bb)
    im=im.resize((128,128),Image.LANCZOS)
    im.save('art/icons/gear/%s.png'%nm)
n=len(ids)
cols=6; rows=(n+cols-1)//cols
sheet=Image.new('RGB',(cols*140,rows*140),(40,40,40))
d=ImageDraw.Draw(sheet)
for i,nm in enumerate(ids):
    im=Image.open('art/icons/gear/%s.png'%nm).convert('RGBA')
    bg=Image.new('RGBA',(140,140),(60,60,60,255))
    bg.paste(im,(6,6),im)
    sheet.paste(bg.convert('RGB'),((i%cols)*140,(i//cols)*140))
    d.text(((i%cols)*140+4,(i//cols)*140+124),nm,fill=(255,255,255))
sheet.save('art/icons/gear/_contact.png')
print('gear icons', n)