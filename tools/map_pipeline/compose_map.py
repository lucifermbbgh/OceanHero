from PIL import Image, ImageDraw, ImageFont
import os as _os
import json, glob, re, math, os
BG = 'art/world_map/world_map_bg.png'
REG = 'data/generated/world_regions.json'
OUT = 'art/world_map/composed_v1.png'
W, H = 2048, 1152
_font = None
for _fp in ['/System/Library/Fonts/PingFang.ttc','/System/Library/Fonts/STHeiti Medium.ttc','/System/Library/Fonts/Hiragino Sans GB.ttc']:
    if _os.path.exists(_fp):
        _font = _fp
        break
def F(sz):
    return ImageFont.truetype(_font, sz) if _font else ImageFont.load_default()
COLORS = {
 'lan': (90,140,217), 'chilin': (217,102,89), 'shuangyu': (153,204,230),
 'xuanjiao': (140,115,166), 'baijing': (217,217,230), 'cangwu': (115,179,128),
 'youming': (110,90,140),
}
NAMES = {'lan':'云澜','chilin':'赤鳞','shuangyu':'霜屿','xuanjiao':'玄礁',
 'baijing':'白鲸','cangwu':'苍梧','youming':'幽溟'}
nations = {}
for p in glob.glob('data/maps/*.tres'):
    t = open(p, encoding='utf-8').read()
    m = re.search(r'^index = (\d+)$', t, re.M)
    n = re.search(r'^nation = &"([a-z_]+)"$', t, re.M)
    if m:
        nations[int(m.group(1))] = n.group(1) if n else ''
img = Image.open(BG).convert('RGBA')
ov = Image.new('RGBA', img.size, (0,0,0,0))
d = ImageDraw.Draw(ov)
data = json.load(open(REG))
for r in data['regions']:
    idx = int(r['index'])
    nat = nations.get(idx, '')
    col = COLORS.get(nat, (120,120,120))
    pts = [(p[0]*W, p[1]*H) for p in r['polygon']]
    d.polygon(pts, fill=col + (70,), outline=col + (220,))
    cx = r['anchor'][0]*W; cy = r['anchor'][1]*H
    lvl = (idx-1)//3 + 1; col_i = (idx-1)%3 + 1
    d.text((cx-16, cy-9), '%d-%d' % (lvl, col_i), fill=(255,250,235,255), font=F(16))
img = Image.alpha_composite(img, ov)
d = ImageDraw.Draw(img)
# 方向标注
for txt, pos in [('N',(W//2,26)),('S',(W//2,H-52)),('W',(30,H//2-10)),('E',(W-44,H//2-10))]:
    d.text(pos, txt, fill=(250,238,200,230), font=F(30))
# 分级区标注
for row in range(10):
    y = (0.08 + row*0.088)*H
    d.text((14, y-10), '%d级' % (row+1), fill=(250,238,200,210), font=F(18))
# 势力图例 + 徽标
x0, y0 = 40, H-92
for i, (nat, col) in enumerate(COLORS.items()):
    x = x0 + i*270
    d.ellipse([x, y0, x+34, y0+34], fill=col+(255,), outline=(250,238,200,255), width=2)
    cxx, cyy = x+17, y0+17
    if nat == 'lan':
        for k in range(3):
            d.arc([cxx-10, cyy-8+k*5, cxx+10, cyy+8+k*5], 200, 340, fill=(255,255,255,230), width=2)
    elif nat == 'chilin':
        d.polygon([(cxx,cyy-10),(cxx+9,cyy+8),(cxx-9,cyy+8)], outline=(255,255,255,230))
    elif nat == 'shuangyu':
        for k in range(3):
            a = math.pi*k/3
            d.line([(cxx-math.cos(a)*9, cyy-math.sin(a)*9), (cxx+math.cos(a)*9, cyy+math.sin(a)*9)], fill=(255,255,255,230), width=2)
    elif nat == 'xuanjiao':
        d.polygon([(cxx,cyy-9),(cxx+8,cyy-3),(cxx+8,cyy+5),(cxx,cyy+10),(cxx-8,cyy+5),(cxx-8,cyy-3)], outline=(255,255,255,230))
    elif nat == 'baijing':
        d.arc([cxx-9,cyy-4,cxx+9,cyy+10], 300, 120, fill=(255,255,255,230), width=2)
        d.line([(cxx,cyy-6),(cxx,cyy+2)], fill=(255,255,255,230), width=2)
    elif nat == 'cangwu':
        d.polygon([(cxx,cyy-10),(cxx+8,cyy+4),(cxx,cyy+2),(cxx-8,cyy+4)], outline=(255,255,255,230))
    else:
        d.arc([cxx-8,cyy-8,cxx+8,cyy+8], 0, 300, fill=(255,255,255,230), width=2)
    d.text((x+42, y0+5), NAMES.get(nat, nat), fill=(250,238,200,230), font=F(22))
d.text((W-300, H-38), 'OCEAN HERO WORLD CHART', fill=(250,238,200,150), font=F(16))
os.makedirs('art/world_map', exist_ok=True)
img.convert('RGB').save(OUT)
print('composed', img.size)