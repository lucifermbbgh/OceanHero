from PIL import Image, ImageDraw, ImageFont
import json, glob, re, math, os
W, H = 2048, 1152
FONT = None
for fp in ['/System/Library/Fonts/PingFang.ttc','/System/Library/Fonts/STHeiti Medium.ttc']:
    if os.path.exists(fp): FONT = fp; break
def F(s): return ImageFont.truetype(FONT, s) if FONT else ImageFont.load_default()
COLORS = {'lan':(90,140,217),'chilin':(200,90,80),'shuangyu':(150,200,225),
 'xuanjiao':(140,115,166),'baijing':(225,225,235),'cangwu':(110,170,120),'youming':(120,95,150)}
NAMES = {'lan':'云澜','chilin':'赤鳞','shuangyu':'霜屿','xuanjiao':'玄礁','baijing':'白鲸','cangwu':'苍梧','youming':'幽溟'}
nations = {}
for p in glob.glob('data/maps/*.tres'):
    t = open(p, encoding='utf-8').read()
    m = re.search(r'^index = (\d+)$', t, re.M); n = re.search(r'^nation = &"([a-z_]+)"$', t, re.M)
    if m: nations[int(m.group(1))] = n.group(1) if n else ''
paper = Image.open('art/world_map/tex_parchment_v1.png').convert('RGB').resize((W,H))
sea = Image.blend(paper, Image.new('RGB',(W,H),(18,52,78)), 0.62)
d = ImageDraw.Draw(sea, 'RGBA')
for k in range(120):
    y0 = (k*37) % H
    pts = [(x, y0 + math.sin(x/70.0 + k)*3) for x in range(0, W, 24)]
    d.line(pts, fill=(60,120,150,36), width=1)
img = sea.convert('RGBA')
regions = json.load(open('data/generated/world_regions.json'))['regions']
land = json.load(open('data/source/land_masses.json'))['land']
land_polys = [[(p[0]*W, p[1]*H) for p in item['polygon']] for item in land]
def inside(x, y, poly):
    c = False; j = len(poly)-1
    for i in range(len(poly)):
        xi, yi = poly[i]; xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj-xi)*(y-yi)/(yj-yi+1e-9)+xi): c = not c
        j = i
    return c
# 区域（先画）
ov = Image.new('RGBA',(W,H),(0,0,0,0)); od = ImageDraw.Draw(ov)
for r in regions:
    idx = int(r['index']); col = COLORS.get(nations.get(idx,''),(150,150,150))
    pts = [(p[0]*W, p[1]*H) for p in r['polygon']]
    od.polygon(pts, fill=col+(70,), outline=col+(210,))
img = Image.alpha_composite(img, ov)
# 陆地（后画，遮住区域色）
light = Image.blend(paper, Image.new('RGB',(W,H),(236,223,190)), 0.55)
mask = Image.new('L',(W,H),0); md = ImageDraw.Draw(mask)
for poly in land_polys: md.polygon(poly, fill=255)
img.paste(light, (0,0), mask)
d = ImageDraw.Draw(img)
for poly in land_polys:
    d.line(poly+[poly[0]], fill=(85,66,42,235), width=3)
# 区域编号（陆地上不画）
for r in regions:
    idx = int(r['index']); cx, cy = r['anchor'][0]*W, r['anchor'][1]*H
    if any(inside(cx, cy, poly) for poly in land_polys): continue
    d.text((cx-18, cy-9), '%d-%d' % ((idx-1)//3+1, (idx-1)%3+1), fill=(255,250,235,235), font=F(16))
# 分级 / 方向
for row in range(10):
    y = (0.08 + row*0.088)*H
    d.text((16, y-10), '%d级' % (row+1), fill=(245,232,195,220), font=F(18))
for txt, pos in [('N',(W//2-8,14)),('S',(W//2-8,H-50)),('W',(18,H//2-14)),('E',(W-36,H//2-14))]:
    d.text(pos, txt, fill=(245,232,195,235), font=F(30))
# 罗盘
cmp = Image.open('art/world_map/tex_compass_v1.png').convert('RGBA')
px = cmp.load()
for y in range(cmp.height):
    for x in range(cmp.width):
        r,g,b,a = px[x,y]
        if r>235 and g>230 and b>220: px[x,y]=(r,g,b,0)
cmp = cmp.resize((250,250))
img.alpha_composite(cmp, (W-290, H-310))
# 标题 / 图例 / 外框
d.rectangle([40,34,420,130], fill=(238,226,196,235), outline=(120,90,50,255), width=2)
d.text((64,48), '碧海英豪', fill=(70,50,30,255), font=F(34))
d.text((64,94), '万 海 航 图 · 第 1 版', fill=(90,70,45,255), font=F(16))
x0, y0 = 40, H-88
for i,(nat,col) in enumerate(COLORS.items()):
    x = x0 + i*272
    d.ellipse([x,y0,x+30,y0+30], fill=col+(255,), outline=(245,232,195,255), width=2)
    d.text((x+40,y0+3), NAMES[nat], fill=(245,232,195,235), font=F(20))
d.rectangle([8,8,W-9,H-9], outline=(180,150,100,220), width=4)
d.rectangle([16,16,W-17,H-17], outline=(120,95,60,160), width=1)
img.convert('RGB').save('art/world_map/composed_v3.png')
print('composed v3')