extends Control
## 8 周价格走势迷你折线

var values: Array = []
var line_color := Color(0.7, 0.8, 0.85)

func set_values(vals: Array, col: Color) -> void:
	values = vals
	line_color = col
	custom_minimum_size = Vector2(80, 24)
	queue_redraw()

func _draw() -> void:
	if values.size() < 2:
		draw_string(ThemeDB.fallback_font, Vector2(4, 16), "—", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.5, 0.55, 0.55))
		return
	var lo: float = float(values[0])
	var hi: float = float(values[0])
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span: float = maxf(1.0, hi - lo)
	var w: float = size.x
	var h: float = size.y - 6.0
	var pts := PackedVector2Array()
	for i in range(values.size()):
		var x: float = w * float(i) / float(values.size() - 1)
		var y: float = 4.0 + h * (1.0 - (float(values[i]) - lo) / span)
		pts.append(Vector2(x, y))
	draw_polyline(pts, line_color, 2.0)
	draw_circle(pts[pts.size() - 1], 2.5, line_color)
