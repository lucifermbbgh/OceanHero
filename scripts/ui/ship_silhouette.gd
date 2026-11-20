extends Control
## 舰船侧视剪影：船级决定桅杆数与船体高度，纯代码绘制便于与插槽对齐。

var masts := 1
var tier := 1

func _draw() -> void:
	var w := size.x
	var h := size.y
	var top := 0.50
	var bottom := 0.74 + minf(0.06, float(tier) * 0.006)
	var hull := PackedVector2Array([
		Vector2(0.08, bottom - 0.06), Vector2(0.14, top), Vector2(0.55, top - 0.02),
		Vector2(0.82, top), Vector2(0.93, bottom - 0.06), Vector2(0.94, bottom - 0.01),
		Vector2(0.87, bottom + 0.03), Vector2(0.16, bottom + 0.03), Vector2(0.07, bottom - 0.01),
	])
	var pts := PackedVector2Array()
	for p in hull:
		pts.append(Vector2(p.x * w, p.y * h))
	draw_polygon(pts, PackedColorArray([Color(0.42, 0.30, 0.17)]))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.25, 0.17, 0.09), 3.0)
	draw_line(Vector2(0.11 * w, top + 0.04 * h), Vector2(0.01 * w, top - 0.02 * h), Color(0.30, 0.21, 0.12), 4.0)
	# 甲板线数量随船级
	var lines := 1 + clampi(tier / 3, 0, 3)
	for i in range(lines):
		var y := (top + 0.07 + float(i) * (bottom - top - 0.10) / maxf(1.0, float(lines - 1))) * h
		draw_line(Vector2(0.16 * w, y), Vector2(0.87 * w, y), Color(0.55, 0.42, 0.24), 2.0)
	# 桅杆与帆
	var xs: Array = [0.42]
	if masts == 2:
		xs = [0.32, 0.58]
	elif masts >= 3:
		xs = [0.28, 0.48, 0.68]
	var mast_bottom := top + 0.02
	for x in xs:
		var px := float(x) * w
		draw_line(Vector2(px, (mast_bottom - 0.36) * h), Vector2(px, mast_bottom * h), Color(0.24, 0.16, 0.09), 6.0)
		draw_rect(Rect2(px - 0.05 * w, (mast_bottom - 0.33) * h, 0.10 * w, 0.22 * h), Color(0.86, 0.82, 0.70))
		draw_rect(Rect2(px - 0.05 * w, (mast_bottom - 0.33) * h, 0.10 * w, 0.22 * h), Color(0.55, 0.5, 0.42), false, 2.0)
