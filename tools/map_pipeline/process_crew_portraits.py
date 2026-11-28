#!/usr/bin/env python3
"""1.6.20 船员头像：512x640 立绘 -> 256x256 方形头像 + 6x4 联系表."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art", "source")
OUT = os.path.join(ROOT, "art", "icons", "crew")
os.makedirs(OUT, exist_ok=True)

POSTS = ["mate", "gunner", "surgeon", "sailor"]
LOOKS = 6
SIZE = 256
# 512x640 立绘：头部大致居中偏上，裁 512x512 方形（留出肩部）
CROP = (0, 40, 512, 552)

made = []
for post in POSTS:
    for look in range(LOOKS):
        path = os.path.join(SRC, "crew_%s_%d.png" % (post, look))
        im = Image.open(path).convert("RGB")
        im = im.crop(CROP).resize((SIZE, SIZE), Image.LANCZOS)
        dst = os.path.join(OUT, "crew_%s_%d.png" % (post, look))
        im.save(dst, optimize=True)
        made.append(dst)

# 联系表 6 列 x 4 行
CELL, GAP = 128, 8
W = LOOKS * CELL + (LOOKS + 1) * GAP
H = len(POSTS) * CELL + (len(POSTS) + 1) * GAP
sheet = Image.new("RGB", (W, H), (18, 24, 28))
draw = ImageDraw.Draw(sheet)
for r, post in enumerate(POSTS):
    for c in range(LOOKS):
        im = Image.open(os.path.join(OUT, "crew_%s_%d.png" % (post, c))).resize((CELL, CELL), Image.LANCZOS)
        x = GAP + c * (CELL + GAP)
        y = GAP + r * (CELL + GAP)
        sheet.paste(im, (x, y))
        draw.text((x + 4, y + 4), "%s_%d" % (post, c), fill=(255, 230, 160))
sheet.save(os.path.join(OUT, "_contact.png"), optimize=True)
print("wrote", len(made), "portraits + contact sheet")
