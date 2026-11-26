import json, os, sys
src = 'data/source/world_regions.tmj'
dst = 'data/generated/world_regions.json'
W, H = 4096.0, 2304.0
data = json.load(open(src))
regions = []
for layer in data.get('layers', []):
    if layer.get('type') != 'objectgroup':
        continue
    for obj in layer.get('objects', []):
        props = {p['name']: p.get('value') for p in obj.get('properties', [])}
        idx = int(props.get('index', 0))
        pts = obj.get('polygon', [])
        if idx <= 0 or len(pts) < 3:
            continue
        poly = []
        for p in pts:
            x = (obj.get('x', 0) + p['x']) / W
            y = (obj.get('y', 0) + p['y']) / H
            poly.append([round(x, 5), round(y, 5)])
        cx = sum(p[0] for p in poly) / len(poly)
        cy = sum(p[1] for p in poly) / len(poly)
        regions.append({'index': idx, 'polygon': poly, 'anchor': [round(cx, 5), round(cy, 5)]})
regions.sort(key=lambda r: r['index'])
os.makedirs('data/generated', exist_ok=True)
json.dump({'source': 'world_regions.tmj', 'canvas': [W, H], 'regions': regions}, open(dst, 'w'), ensure_ascii=False, indent=1)
print('regions', len(regions))
# 陆地蒙板（供运行时绘制与命中排除）
import shutil
if os.path.exists('data/source/land_masses.json'):
    shutil.copyfile('data/source/land_masses.json', 'data/generated/land_masses.json')
    print('land copied')
