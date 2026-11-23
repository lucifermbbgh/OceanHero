from PIL import Image, ImageDraw, ImageFilter
import math, random, os
random.seed(7)
W, H = 2048, 1152
img = Image.new('RGB', (W, H), (9, 38, 62))
d = ImageDraw.Draw(img, 'RGBA')
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(9+8*t), int(40+18*t), int(66+26*t)))
def land(cx, cy, rx, ry):
    pts = []
    n = 26
    for i in range(n):
        a = 2*math.pi*i/n
        rr = 0.85 + 0.25*random.random()
        pts.append((cx + math.cos(a)*rx*rr, cy + math.sin(a)*ry*rr))
    d.polygon(pts, fill=(206, 188, 146, 255))
    d.line(pts + [pts[0]], fill=(120, 96, 58, 255), width=3)
land(W*0.16, H*0.28, 210, 130)
land(W*0.27, H*0.52, 110, 80)
land(W*0.60, H*0.20, 160, 100)
land(W*0.80, H*0.42, 230, 150)
land(W*0.53, H*0.72, 140, 190)
land(W*0.88, H*0.80, 110, 90)
for _ in range(80):
    x, y = random.randint(0, W), random.randint(0, H)
    r = random.randint(2, 5)
    d.ellipse([x-r, y-r, x+r, y+r], fill=(210, 196, 150, 220))
cx, cy, R = int(W*0.5), int(H*0.5), 80
d.ellipse([cx-R, cy-R, cx+R, cy+R], outline=(220, 205, 160, 130), width=2)
for i in range(8):
    a = math.pi*i/4
    d.line([(cx, cy), (cx+math.cos(a)*R, cy+math.sin(a)*R)], fill=(220, 205, 160, 100), width=2)
d.rectangle([16, 16, W-16, H-16], outline=(210, 190, 140, 120), width=3)
os.makedirs('art/world_map', exist_ok=True)
img.save('art/world_map/world_map_bg.png')
print('bg regenerated')