extends Control
## 舰船侧视剪影：按船级决定桅杆数，纯代码绘制，便于与插槽锚点对齐。

var masts := 1

func _draw() -> void:
	var w := size.x
	var h := size.y
	var hull := PackedVector2Array([
		Vector2(0.08, 0.62), Vector2(0.14, 0.54), Vector2(0.55, 0.52),
		Vector2(0.82, 0.54), Vector2(0.93, 0.60), Vector2(0.94, 0.69),
		Vector2(0.87, 0.75), Vector2(0.16, 0.75), Vector2(0.07, 0.68),
	])
	var pts := PackedVector2Array()
	for p in hull:
		pts.append(Vector2(p.x * w, p.y * h))
	draw_polygon(pts, PackedColorArray([Color(0.42, 0.30, 0.17)]))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.25, 0.17, 0.09), 3.0)
	# 船艏斜桅
	draw_line(Vector2(0.11 * w, 0.56 * h), Vector2(0.01 * w, 0.50 * h), Color(0.30, 0.21, 0.12), 4.0)
	# 甲板线
	for i in range(3):
		var y := (0.57 + i * 0.06) * h
		draw_line(Vector2(0.16 * w, y), Vector2(0.87 * w, y), Color(0.55, 0.42, 0.24), 2.0)
	# 桅杆与帆
	var xs: Array = [0.42]
	if masts == 2:
		xs = [0.32, 0.58]
	elif masts >= 3:
		xs = [0.28, 0.48, 0.68]
	for x in xs:
		var px := float(x) * w
		draw_line(Vector2(px, 0.18 * h), Vector2(px, 0.55 * h), Color(0.24, 0.16, 0.09), 6.0)
		draw_rect(Rect2(px - 0.055 * w, 0.22 * h, 0.11 * w, 0.22 * h), Color(0.86, 0.82, 0.70))
		draw_rect(Rect2(px - 0.055 * w, 0.22 * h, 0.11 * w, 0.22 * h), Color(0.55, 0.5, 0.42), false, 2.0)
