from PIL import Image, ImageDraw
import math, os
W,H = 2048,1152
paper = Image.open('art/world_map/tex_parchment_v1.png').convert('RGB').resize((W,H))
sea = Image.blend(paper, Image.new('RGB',(W,H),(16,50,76)), 0.66)
d = ImageDraw.Draw(sea, 'RGBA')
for k in range(120):
    y0 = (k*41) % H
    pts = [(x, y0 + math.sin(x/64.0 + k)*3) for x in range(0, W, 20)]
    d.line(pts, fill=(70,130,160,34), width=1)
d.rectangle([14,14,W-15,H-15], outline=(180,150,100,200), width=4)
sea.save('art/world_map/bg_sea.png')
print('sea bg saved')