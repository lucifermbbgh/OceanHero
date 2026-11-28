#!/usr/bin/env python3
"""1.6.21 舰船立绘：768x512 立绘 -> 384x256 图标，并派生 standard/navy/pirate 三变体。"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art", "source")
OUT = os.path.join(ROOT, "art", "icons", "ship")
os.makedirs(OUT, exist_ok=True)

BASES = [
    "fishing_sloop", "sand_junk", "longship", "schooner", "brig",
    "sixth_rate", "fifth_rate", "fourth_rate", "third_rate", "first_rate",
    "fx_ship_baijing_whale", "fx_ship_cangwu_hunter", "fx_ship_chilin_merchant",
    "fx_ship_shuangyu_breaker", "fx_ship_xuanjiao_night", "fx_ship_youming_ghost",
    "fx_ship_yunlan_clipper",
]
SIZE = (384, 256)
VARIANTS = {
    "navy": {"mul": (0.80, 0.93, 1.14), "overlay": (36, 72, 140, 0.14), "border": (74, 128, 196)},
    "pirate": {"mul": (1.14, 0.86, 0.80), "overlay": (128, 42, 32, 0.14), "border": (168, 72, 52)},
}


def grade(im: Image.Image, mul, overlay):
    r, g, b = im.split()
    r = r.point(lambda v: min(255, int(v * mul[0])))
    g = g.point(lambda v: min(255, int(v * mul[1])))
    b = b.point(lambda v: min(255, int(v * mul[2])))
    out = Image.merge("RGB", (r, g, b))
    if overlay is not None:
        ov = Image.new("RGB", out.size, overlay[:3])
        out = Image.blend(out, ov, overlay[3])
    return out


def border(im: Image.Image, color):
    d = ImageDraw.Draw(im)
    w, h = im.size
    d.rectangle([0, 0, w - 1, h - 1], outline=color, width=3)
    return im


made = 0
for base in BASES:
    src = os.path.join(SRC, "ship_%s.png" % base)
    im = Image.open(src).convert("RGB").resize(SIZE, Image.LANCZOS)
    im.save(os.path.join(OUT, "%s.png" % base), optimize=True)
    im.save(os.path.join(OUT, "%s_standard.png" % base), optimize=True)
    made += 2
    for vname, spec in VARIANTS.items():
        v = border(grade(im, spec["mul"], spec["overlay"]), spec["border"])
        v.save(os.path.join(OUT, "%s_%s.png" % (base, vname)), optimize=True)
        made += 1

# 联系表：17 张基础立绘
CELL = (192, 128)
COLS = 4
rows = (len(BASES) + COLS - 1) // COLS
GAP = 8
sheet = Image.new("RGB", (COLS * CELL[0] + (COLS + 1) * GAP, rows * CELL[1] + (rows + 1) * GAP), (18, 24, 28))
draw = ImageDraw.Draw(sheet)
for i, base in enumerate(BASES):
    im = Image.open(os.path.join(OUT, "%s.png" % base)).resize(CELL, Image.LANCZOS)
    x = GAP + (i % COLS) * (CELL[0] + GAP)
    y = GAP + (i // COLS) * (CELL[1] + GAP)
    sheet.paste(im, (x, y))
    draw.text((x + 4, y + 4), base.replace("fx_ship_", "fx_"), fill=(255, 230, 160))
sheet.save(os.path.join(OUT, "_contact.png"), optimize=True)
print("wrote", made, "ship icons")
