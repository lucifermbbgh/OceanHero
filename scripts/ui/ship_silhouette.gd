extends Control
## 舰船侧视剪影。与插槽共用 ShipLayout 常量，保证严格对齐。

const HULL_TOP := 0.50
const HULL_BOTTOM := 0.80
const MAST_TOP := 0.14

var masts := 1
var tier := 1

func _draw() -> void:
	var w := size.x
	var h := size.y
	var top := HULL_TOP * h
	var bottom := HULL_BOTTOM * h
	var hull := PackedVector2Array([
		Vector2(0.08 * w, top + 0.05 * h), Vector2(0.15 * w, top),
		Vector2(0.55 * w, top - 0.015 * h), Vector2(0.82 * w, top),
		Vector2(0.92 * w, top + 0.05 * h), Vector2(0.93 * w, bottom - 0.02 * h),
		Vector2(0.86 * w, bottom), Vector2(0.18 * w, bottom), Vector2(0.07 * w, bottom - 0.02 * h),
	])
	draw_polygon(hull, PackedColorArray([Color(0.42, 0.30, 0.17)]))
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.25, 0.17, 0.09), 3.0)
	# 船艏斜桅（贴在船首前方）
	draw_line(Vector2(0.10 * w, top + 0.04 * h), Vector2(0.02 * w, top - 0.02 * h),
		Color(0.30, 0.21, 0.12), 4.0)
	# 甲板线
	var lines := 1 + clampi(tier / 3, 0, 3)
	for i in range(lines):
		var y := top + 0.06 * h + float(i) * (bottom - top - 0.12 * h) / maxf(1.0, float(lines - 1))
		draw_line(Vector2(0.15 * w, y), Vector2(0.86 * w, y), Color(0.55, 0.42, 0.24), 2.0)
	# 桅杆与帆
	var xs: Array = [0.42]
	if masts == 2:
		xs = [0.32, 0.58]
	elif masts >= 3:
		xs = [0.28, 0.48, 0.68]
	for x in xs:
		var px := float(x) * w
		draw_line(Vector2(px, MAST_TOP * h), Vector2(px, top + 0.01 * h),
			Color(0.24, 0.16, 0.09), 6.0)
		draw_rect(Rect2(px - 0.05 * w, (MAST_TOP + 0.05) * h, 0.10 * w, 0.24 * h),
			Color(0.86, 0.82, 0.70))
		draw_rect(Rect2(px - 0.05 * w, (MAST_TOP + 0.05) * h, 0.10 * w, 0.24 * h),
			Color(0.55, 0.5, 0.42), false, 2.0)
