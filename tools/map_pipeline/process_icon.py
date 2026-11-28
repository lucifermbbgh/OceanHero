from PIL import Image
import numpy as np, os, sys
ids=sys.argv[1:]
for nm in ids:
    p='art/source/icon_%s.png'%nm
    if not os.path.exists(p): continue
    cell=Image.open(p).convert('RGB')
    a=np.asarray(cell,dtype=np.int16)
    lum=a.min(axis=2)
    alpha=np.clip((248-lum)*5,0,255).astype('uint8')
    rgba=np.dstack([a.astype('uint8'),alpha])
    im=Image.fromarray(rgba,'RGBA')
    bb=im.getbbox()
    if bb: im=im.crop(bb)
    im=im.resize((128,128),Image.LANCZOS)
    im.save('art/icons/commodity/%s.png'%nm)
print('processed', len(ids))