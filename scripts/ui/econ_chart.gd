extends Control
## 经济图表控件（0.19.1）

enum Kind { PRICE, MARGINAL, EQUILIBRIUM, ELASTICITY, PORT_SCALE }

var kind := Kind.PRICE
var data: Dictionary = {}
var title := ""

func setup(k: int, d: Dictionary, t: String) -> void:
	kind = k
	data = d
	title = t
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.09, 0.10, 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.35, 0.38), false, 1.0)
	var font := ThemeDB.fallback_font
	if title != "":
		draw_string(font, Vector2(10, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.7, 0.85, 0.78))
	var pad := 34.0
	var ox := pad
	var oy := h - pad
	var iw := w - pad * 2.0
	var ih := h - pad * 1.6
	if iw <= 10.0 or ih <= 10.0:
		return
	# 坐标轴
	draw_line(Vector2(ox, oy), Vector2(ox + iw, oy), Color(0.4, 0.5, 0.5), 1.0)
	draw_line(Vector2(ox, oy), Vector2(ox, oy - ih), Color(0.4, 0.5, 0.5), 1.0)
	match kind:
		Kind.PRICE:
			_draw_price(ox, oy, iw, ih, font)
		Kind.MARGINAL:
			_draw_marginal(ox, oy, iw, ih, font)
		Kind.EQUILIBRIUM:
			_draw_equilibrium(ox, oy, iw, ih, font)
		Kind.ELASTICITY:
			_draw_elasticity(ox, oy, iw, ih, font)
		Kind.PORT_SCALE:
			_draw_port_scale(ox, oy, iw, ih, font)

func _draw_price(ox: float, oy: float, iw: float, ih: float, font: Font) -> void:
	var hist: Array = data.get("history", [])
	draw_string(font, Vector2(ox - 26, oy - ih - 6), "价格", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.55, 0.62, 0.6))
	draw_string(font, Vector2(ox + iw - 40, oy + 18), "周期", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.55, 0.62, 0.6))
	if hist.size() < 2:
		draw_string(font, Vector2(ox + iw * 0.35, oy - ih * 0.5), "数据不足（至少 2 周）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.55, 0.55))
		return
	var lo: float = float(hist[0])
	var hi: float = float(hist[0])
	for v in hist:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span: float = maxf(1.0, hi - lo)
	var pts := PackedVector2Array()
	for i in range(hist.size()):
		var x: float = ox + iw * float(i) / float(hist.size() - 1)
		var y: float = oy - ih * ((float(hist[i]) - lo) / span)
		pts.append(Vector2(x, y))
	var up: bool = float(hist[hist.size() - 1]) >= float(hist[0])
	draw_polyline(pts, Color(0.92, 0.45, 0.42) if up else Color(0.45, 0.85, 0.55), 2.0)
	for p in pts:
		draw_circle(p, 2.0, Color(0.8, 0.85, 0.8))

func _draw_marginal(ox: float, oy: float, iw: float, ih: float, font: Font) -> void:
	var mc: Array = data.get("mc", [])
	var mr: float = float(data.get("mr", 0.0))
	if mc.is_empty():
		return
	var lo: float = mr
	var hi: float = mr
	for v in mc:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span: float = maxf(1.0, hi - lo)
	var mcy := PackedVector2Array()
	for i in range(mc.size()):
		var x: float = ox + iw * float(i) / float(mc.size() - 1)
		var y: float = oy - ih * ((float(mc[i]) - lo) / span)
		mcy.append(Vector2(x, y))
	draw_polyline(mcy, Color(0.9, 0.62, 0.5), 2.0)
	var ry: float = oy - ih * ((mr - lo) / span)
	draw_line(Vector2(ox, ry), Vector2(ox + iw, ry), Color(0.5, 0.85, 0.6), 2.0)
	draw_string(font, Vector2(ox + 6, ry - 6), "MR 边际收益", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.5, 0.85, 0.6))
	draw_string(font, Vector2(ox + 6, mcy[0].y - 6), "MC 边际成本", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.9, 0.62, 0.5))
	draw_string(font, Vector2(ox + iw - 60, oy + 18), "数量", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.55, 0.62, 0.6))
	draw_string(font, Vector2(ox + 8, oy - ih * 0.5), "（理论值，实际按整单单价成交）",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.5))

func _draw_equilibrium(ox: float, oy: float, iw: float, ih: float, font: Font) -> void:
	var sp: Array = data.get("supply", [])
	var dp: Array = data.get("demand", [])
	if sp.size() < 2 or dp.size() < 2:
		return
	var lo: float = 1e9
	var hi: float = -1e9
	for v in sp + dp:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span: float = maxf(1.0, hi - lo)
	var s_pts := PackedVector2Array()
	for i in range(sp.size()):
		s_pts.append(Vector2(ox + iw * float(i) / float(sp.size() - 1),
			oy - ih * ((float(sp[i]) - lo) / span)))
	var d_pts := PackedVector2Array()
	for i in range(dp.size()):
		d_pts.append(Vector2(ox + iw * float(i) / float(dp.size() - 1),
			oy - ih * ((float(dp[i]) - lo) / span)))
	draw_polyline(s_pts, Color(0.9, 0.62, 0.5), 2.0)
	draw_polyline(d_pts, Color(0.55, 0.75, 0.95), 2.0)
	draw_string(font, Vector2(ox + 6, s_pts[0].y - 6), "供给", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.9, 0.62, 0.5))
	draw_string(font, Vector2(ox + iw - 46, d_pts[0].y - 6), "需求", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.55, 0.75, 0.95))
	draw_string(font, Vector2(ox + 6, oy - ih * 0.5), "需求曲线为模型近似，非实测数据",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.5))

func _draw_elasticity(ox: float, oy: float, iw: float, ih: float, font: Font) -> void:
	var pts_data: Array = data.get("curve", [])
	if pts_data.size() < 2:
		return
	var lo: float = 1e9
	var hi: float = -1e9
	for v in pts_data:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span: float = maxf(1.0, hi - lo)
	var pts := PackedVector2Array()
	for i in range(pts_data.size()):
		pts.append(Vector2(ox + iw * float(i) / float(pts_data.size() - 1),
			oy - ih * ((float(pts_data[i]) - lo) / span)))
	draw_polyline(pts, Color(0.85, 0.8, 0.6), 2.0)
	var mid := int(pts.size() / 2)
	draw_line(Vector2(ox, pts[mid].y), Vector2(ox + iw, pts[mid].y), Color(0.4, 0.5, 0.5), 1.0)
	draw_string(font, Vector2(ox + 6, pts[2].y - 6), "富有弹性区", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.6, 0.85, 0.7))
	draw_string(font, Vector2(ox + 6, pts[pts.size() - 3].y - 6), "缺乏弹性区",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.7, 0.55))

func _draw_port_scale(ox: float, oy: float, iw: float, ih: float, font: Font) -> void:
	var labels: Array = data.get("labels", ["村", "镇", "城"])
	var coefs: Array = data.get("coefs", [1.20, 1.00, 0.85])
	var vol: Array = data.get("vol", [40, 90, 160])
	var n := labels.size()
	if n == 0:
		return
	var bw := iw / float(n) * 0.35
	var max_c := 1.4
	var max_v := 200.0
	for i in range(n):
		var cx := ox + iw * (float(i) + 0.5) / float(n)
		var ch: float = ih * (float(coefs[i]) / max_c) * 0.8
		draw_rect(Rect2(Vector2(cx - bw, oy - ch), Vector2(bw, ch)), Color(0.85, 0.6, 0.45))
		var vh: float = ih * (float(vol[i]) / max_v) * 0.8
		draw_rect(Rect2(Vector2(cx, oy - vh), Vector2(bw, vh)), Color(0.5, 0.72, 0.9))
		draw_string(font, Vector2(cx - bw, oy + 16), String(labels[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.7, 0.78, 0.75))
	draw_string(font, Vector2(ox, oy - ih - 6), "橙=价格系数  蓝=吞吐量", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.6, 0.66, 0.64))
