import json, math
W, H = 4096.0, 2304.0
centers = [(0.16,0.30,0.10,0.07),(0.27,0.54,0.055,0.045),(0.60,0.20,0.085,0.055),
 (0.80,0.44,0.11,0.08),(0.53,0.72,0.07,0.10),(0.88,0.80,0.055,0.05)]
polys = []
for cx, cy, rx, ry in centers:
    pts = []
    n = 14
    for i in range(n):
        a = 2*math.pi*i/n
        # 半径平滑变化，保持凸形
        k = 1.0 + 0.06*math.sin(i*1.7)
        x = (cx + math.cos(a)*rx*k)
        y = (cy + math.sin(a)*ry*k)
        pts.append([round(x, 5), round(y, 5)])
    polys.append(pts)
json.dump({'land': [{'polygon': p} for p in polys]}, open('data/source/land_masses.json','w'), ensure_ascii=False, indent=1)
print('land', len(polys))