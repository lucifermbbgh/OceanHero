from PIL import Image, ImageDraw
import numpy as np, os, glob
groups=[('module','art/icons/module'),('cannon','art/icons/cannon'),('ammo','art/icons/ammo')]
allids=[]
for pre,outd in groups:
    os.makedirs(outd,exist_ok=True)
    ids=[]
    for p in sorted(glob.glob('art/source/%s_*.png'%pre)):
        nm=os.path.basename(p)[len(pre)+1:-4]
        ids.append(nm)
        cell=Image.open(p).convert('RGB')
        a=np.asarray(cell,dtype=np.int16)
        lum=a.min(axis=2)
        alpha=np.clip((248-lum)*5,0,255).astype('uint8')
        im=Image.fromarray(np.dstack([a.astype('uint8'),alpha]),'RGBA')
        bb=im.getbbox()
        if bb: im=im.crop(bb)
        im=im.resize((128,128),Image.LANCZOS)
        im.save('%s/%s.png'%(outd,nm))
    allids+= [(pre,i) for i in ids]
    print(pre, len(ids))
cols=7; rows=(len(allids)+cols-1)//cols
sheet=Image.new('RGB',(cols*140,rows*140),(40,40,40))
d=ImageDraw.Draw(sheet)
for i,(pre,nm) in enumerate(allids):
    im=Image.open('art/icons/%s/%s.png'%(pre,nm)).convert('RGBA')
    bg=Image.new('RGBA',(140,140),(60,60,60,255))
    bg.paste(im,(6,6),im)
    sheet.paste(bg.convert('RGB'),((i%cols)*140,(i//cols)*140))
    d.text(((i%cols)*140+4,(i//cols)*140+124),nm,fill=(255,255,255))
sheet.save('art/icons/_contact_modcan.png')
print('total', len(allids))