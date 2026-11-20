extends Control
## 舰船侧视剪影：按 Penpot 设计稿的画布比例绘制。
## 画布归一化范围：x 0~1、y 0~1，模块锚点直接映射到同一坐标系。

const HULL_TOP := 0.46
const HULL_BOTTOM := 0.95

var masts := 3
var tier := 1
const MAST_X := [0.213, 0.463, 0.713]

func _draw() -> void:
	var w := size.x
	var h := size.y
	var top := HULL_TOP * h
	var bottom := HULL_BOTTOM * h
	var hull := PackedVector2Array([
		Vector2(0.02 * w, top + 0.05 * h), Vector2(0.10 * w, top),
		Vector2(0.55 * w, top - 0.01 * h), Vector2(0.92 * w, top),
		Vector2(1.02 * w, top + 0.06 * h), Vector2(1.02 * w, bottom - 0.03 * h),
		Vector2(0.94 * w, bottom), Vector2(0.10 * w, bottom), Vector2(0.01 * w, bottom - 0.03 * h),
	])
	draw_polygon(hull, PackedColorArray([Color(0.42, 0.30, 0.17)]))
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.25, 0.17, 0.09), 3.0)
	draw_line(Vector2(0.06 * w, top + 0.03 * h), Vector2(-0.02 * w, top - 0.03 * h),
		Color(0.30, 0.21, 0.12), 4.0)
	# 甲板线（与甲板行距一致）
	for i in range(3):
		var y := (0.52 + float(i) * 0.121) * h
		draw_line(Vector2(0.06 * w, y), Vector2(0.96 * w, y), Color(0.55, 0.42, 0.24), 2.0)
	# 桅杆与帆（按设计稿三桅位置）
	var xs: Array = [0.463]
	if masts == 2:
		xs = [0.213, 0.463]
	elif masts >= 3:
		xs = [0.213, 0.463, 0.713]
	for x in xs:
		var xf := float(x)
		var px := xf * w
		draw_line(Vector2(px, 0.02 * h), Vector2(px, top + 0.01 * h), Color(0.24, 0.16, 0.09), 6.0)
		draw_rect(Rect2(px - 0.065 * w, 0.14 * h, 0.13 * w, 0.26 * h), Color(0.86, 0.82, 0.70))
		draw_rect(Rect2(px - 0.065 * w, 0.14 * h, 0.13 * w, 0.26 * h), Color(0.55, 0.5, 0.42), false, 2.0)
