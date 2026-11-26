from PIL import Image, ImageDraw, ImageFilter
import numpy as np, json, math, os
W, H = 2048, 1152
rng = np.random.default_rng(20261206)
# 分形噪声（低分辨率起逐层放大）
small = rng.random((36, 64))
img = np.zeros((H, W, 3), dtype=np.float32)
base = np.array([14, 44, 66], dtype=np.float32)
img[:] = base
for octave in range(4):
    layer = Image.fromarray((small*255).astype(np.uint8)).resize((W//(2**octave), H//(2**octave)), Image.BILINEAR)
    layer = layer.resize((W, H), Image.BILINEAR)
    a = np.asarray(layer, dtype=np.float32) / 255.0
    amp = 14.0 / (2**octave)
    img[..., 0] += (a - 0.5) * amp * 0.6
    img[..., 1] += (a - 0.5) * amp * 1.2
    img[..., 2] += (a - 0.5) * amp * 1.5
sea = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
d = ImageDraw.Draw(sea, 'RGBA')
for k in range(140):
    y0 = (k*53) % H
    pts = [(x, y0 + math.sin(x/58.0 + k*0.8)*3.5) for x in range(0, W, 18)]
    d.line(pts, fill=(70, 130, 160, 26), width=1)
d.rectangle([12,12,W-13,H-13], outline=(170, 142, 96, 200), width=4)
sea.save('art/world_map/bg_sea.png')
# 陆地叠加层（透明底）
land = json.load(open('data/source/land_masses.json'))['land']
paper = Image.open('art/world_map/tex_parchment_v1.png').convert('RGB').resize((W,H))
warm = Image.blend(paper, Image.new('RGB',(W,H),(232,216,180)), 0.35)
mask = Image.new('L',(W,H),0); md = ImageDraw.Draw(mask)
polys = [[(p[0]*W, p[1]*H) for p in item['polygon']] for item in land]
for poly in polys: md.polygon(poly, fill=255)
overlay = Image.new('RGBA', (W,H), (0,0,0,0))
overlay.paste(warm, (0,0), mask)
od = ImageDraw.Draw(overlay)
for poly in polys:
    od.line(poly+[poly[0]], fill=(92, 70, 44, 255), width=4)
    od.line(poly+[poly[0]], fill=(255, 246, 220, 90), width=1)
overlay.save('art/world_map/land_overlay.png')
print('assets rebuilt', sea.size)