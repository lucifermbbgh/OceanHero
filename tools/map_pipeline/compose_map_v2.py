from PIL import Image, ImageDraw, ImageFont, ImageFilter
import json, glob, re, math, random, os
W, H = 2048, 1152
random.seed(11)
FONT = None
for fp in ['/System/Library/Fonts/PingFang.ttc','/System/Library/Fonts/STHeiti Medium.ttc']:
    if os.path.exists(fp):
        FONT = fp
        break
def F(sz):
    return ImageFont.truetype(FONT, sz) if FONT else ImageFont.load_default()
COLORS = {'lan':(90,140,217),'chilin':(200,90,80),'shuangyu':(150,200,225),
 'xuanjiao':(140,115,166),'baijing':(225,225,235),'cangwu':(110,170,120),'youming':(120,95,150)}
NAMES = {'lan':'云澜','chilin':'赤鳞','shuangyu':'霜屿','xuanjiao':'玄礁','baijing':'白鲸','cangwu':'苍梧','youming':'幽溟'}
nations = {}
for p in glob.glob('data/maps/*.tres'):
    t = open(p, encoding='utf-8').read()
    m = re.search(r'^index = (\d+)$', t, re.M)
    n = re.search(r'^nation = &"([a-z_]+)"$', t, re.M)
    if m:
        nations[int(m.group(1))] = n.group(1) if n else ''
# 海面：羊皮纸 + 蓝色染色
paper = Image.open('art/world_map/tex_parchment_v1.png').convert('RGB').resize((W, H))
sea = Image.new('RGB', (W,H), (18,52,78))
sea = Image.blend(paper, sea, 0.62)
d = ImageDraw.Draw(sea, 'RGBA')
for k in range(160):
    y0 = random.randint(0, H)
    pts = [(x, y0 + math.sin(x/70.0 + k)*3) for x in range(0, W, 24)]
    d.line(pts, fill=(60,120,150,40), width=1)
img = sea.convert('RGBA')
# 大陆：羊皮纸填充 + 墨线
land_mask = Image.new('L', (W,H), 0)
ld = ImageDraw.Draw(land_mask)
def blob(cx, cy, rx, ry):
    pts = []
    for i in range(22):
        a = 2*math.pi*i/22
        rr = 0.85 + 0.3*random.random()
        pts.append((cx + math.cos(a)*rx*rr, cy + math.sin(a)*ry*rr))
    ld.polygon(pts, fill=255)
    return pts
centers = [(0.16,0.30,0.10,0.07),(0.27,0.54,0.055,0.045),(0.60,0.20,0.085,0.055),
 (0.80,0.44,0.11,0.08),(0.53,0.72,0.07,0.10),(0.88,0.80,0.055,0.05)]
land_polys = []
for cx, cy, rx, ry in centers:
    land_polys.append(blob(cx*W, cy*H, rx*W, ry*H))
light_paper = Image.blend(paper, Image.new('RGB',(W,H),(235,222,190)), 0.45)
img.paste(light_paper, (0,0), land_mask)
ldraw = ImageDraw.Draw(img)
for pts in land_polys:
    d2 = ImageDraw.Draw(img)
    d2.line(pts + [pts[0]], fill=(90,70,45,230), width=3)
# 30 区域填色
regions = json.load(open('data/generated/world_regions.json'))['regions']
ov = Image.new('RGBA', (W,H), (0,0,0,0))
od = ImageDraw.Draw(ov)
for r in regions:
    idx = int(r['index'])
    col = COLORS.get(nations.get(idx,''), (150,150,150))
    pts = [(p[0]*W, p[1]*H) for p in r['polygon']]
    od.polygon(pts, fill=col + (52,), outline=col + (200,))
img = Image.alpha_composite(img, ov)
d = ImageDraw.Draw(img)
# 区域编号
for r in regions:
    idx = int(r['index'])
    cx, cy = r['anchor'][0]*W, r['anchor'][1]*H
    lvl, ci = (idx-1)//3 + 1, (idx-1)%3 + 1
    d.text((cx-18, cy-9), '%d-%d' % (lvl, ci), fill=(255,250,235,235), font=F(16))
# 分级标注
for row in range(10):
    y = (0.08 + row*0.088)*H
    d.text((16, y-10), '%d级' % (row+1), fill=(245,232,195,220), font=F(18))
# 方向
for txt, pos in [('N',(W//2-8,14)),('S',(W//2-8,H-50)),('W',(18,H//2-14)),('E',(W-36,H//2-14))]:
    d.text(pos, txt, fill=(245,232,195,235), font=F(30))
# 罗盘（白底转透明）
cmp = Image.open('art/world_map/tex_compass_v1.png').convert('RGBA')
px = cmp.load()
for y in range(cmp.height):
    for x in range(cmp.width):
        r,g,b,a = px[x,y]
        if r > 235 and g > 230 and b > 220:
            px[x,y] = (r,g,b,0)
cmp = cmp.resize((260,260))
img.alpha_composite(cmp, (W-300, H-330))
# 标题饰框
tw, th = 380, 96
tx, ty = 40, 34
d.rectangle([tx, ty, tx+tw, ty+th], fill=(238,226,196,235), outline=(120,90,50,255), width=2)
d.text((tx+24, ty+14), '碧海英豪', fill=(70,50,30,255), font=F(34))
d.text((tx+24, ty+60), '万 海 航 图 · 第 1 版', fill=(90,70,45,255), font=F(16))
# 图例
x0, y0 = 40, H-88
for i, (nat, col) in enumerate(COLORS.items()):
    x = x0 + i*272
    d.ellipse([x, y0, x+30, y0+30], fill=col+(255,), outline=(245,232,195,255), width=2)
    d.text((x+40, y0+3), NAMES[nat], fill=(245,232,195,235), font=F(20))
# 外框
d.rectangle([8,8,W-9,H-9], outline=(180,150,100,220), width=4)
d.rectangle([16,16,W-17,H-17], outline=(120,95,60,160), width=1)
img.convert('RGB').save('art/world_map/composed_v2.png')
print('composed v2', img.size)