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

func _draw_equilibrium(ox: float, oy: float, iw: float, ih: float, font: Font) -> void:
	var pts_data: Array = data.get("price_by_stock", [])
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
	draw_polyline(pts, Color(0.95, 0.72, 0.45), 2.0)
	var cur: int = int(data.get("cur_stock", 0))
	var mx: int = maxi(1, int(data.get("max_stock", 1)))
	var idx: int = clampi(int(float(cur) / float(mx) * 40.0), 0, pts.size() - 1)
	var cp: Vector2 = pts[idx]
	draw_line(Vector2(cp.x, oy), Vector2(cp.x, cp.y), Color(0.5, 0.7, 0.85), 1.0)
	draw_circle(cp, 5.0, Color(0.55, 0.85, 1.0))
	draw_string(font, Vector2(cp.x - 40, cp.y - 10), "当前", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(0.6, 0.88, 1.0))
	draw_string(font, Vector2(ox - 30, oy - ih - 8), "买价", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.62, 0.7, 0.68))
	draw_string(font, Vector2(ox + iw - 60, oy + 20), "库存量", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.62, 0.7, 0.68))
	draw_string(font, Vector2(ox + 90, oy - ih + 16), "当前库存 %d：买价约 %d；库存越多价格越低" % [
		cur, int(round(float(pts_data[idx])))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.72, 0.82, 0.76))

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
	var mid_y: float = (pts[0].y + pts[pts.size() - 1].y) * 0.5
	draw_rect(Rect2(Vector2(ox, oy - ih), Vector2(iw, mid_y - (oy - ih))),
		Color(0.25, 0.45, 0.35, 0.35))
	draw_rect(Rect2(Vector2(ox, mid_y), Vector2(iw, oy - mid_y)), Color(0.45, 0.3, 0.2, 0.35))
	draw_polyline(pts, Color(0.98, 0.88, 0.55), 2.5)
	draw_line(Vector2(ox, mid_y), Vector2(ox + iw, mid_y), Color(0.7, 0.75, 0.6), 1.0)
	draw_string(font, Vector2(ox + 10, oy - ih + 24), "富有弹性（价格敏感）",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.72, 0.95, 0.78))
	draw_string(font, Vector2(ox + 10, oy - 44), "缺乏弹性（价格不敏感）",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.98, 0.8, 0.62))
	draw_string(font, Vector2(ox - 30, oy - ih - 8), "价格", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.62, 0.7, 0.68))
	draw_string(font, Vector2(ox + iw - 60, oy + 20), "数量", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.62, 0.7, 0.68))

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
		mcy.append(Vector2(ox + iw * float(i) / float(mc.size() - 1),
			oy - ih * ((float(mc[i]) - lo) / span)))
	var ry: float = oy - ih * ((mr - lo) / span)
	# MP 区域（MR 与 MC 之间）
	for i in range(mcy.size() - 1):
		var a: Vector2 = mcy[i]
		var b: Vector2 = mcy[i + 1]
		var top_y: float = minf(a.y, ry)
		var bot_y: float = maxf(a.y, ry)
		var col := Color(0.35, 0.55, 0.4, 0.35) if ry < a.y else Color(0.55, 0.3, 0.25, 0.35)
		draw_rect(Rect2(Vector2(a.x, top_y), Vector2(maxf(1.0, b.x - a.x), bot_y - top_y)), col)
	draw_polyline(mcy, Color(0.98, 0.66, 0.5), 2.5)
	draw_line(Vector2(ox, ry), Vector2(ox + iw, ry), Color(0.55, 0.92, 0.65), 2.5)
	draw_string(font, Vector2(ox + iw - 150, ry - 8), "MR 卖出价 %d" % int(mr),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.92, 0.65))
	draw_string(font, Vector2(ox + 8, mcy[0].y + 20), "MC 买价 %d" % int(mc[0]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.98, 0.66, 0.5))
	draw_string(font, Vector2(ox - 30, oy - ih - 8), "价格", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.62, 0.7, 0.68))
	draw_string(font, Vector2(ox + iw - 60, oy + 20), "数量", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.62, 0.7, 0.68))
	draw_string(font, Vector2(ox + 8, oy - ih + 20), "绿色区 = 边际利润为正（可买）　红色区 = 亏损",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.74))

func _draw_port_scale(ox: float, oy: float, iw: float, ih: float, font: Font) -> void:
	var labels: Array = data.get("labels", ["渔村", "乡镇", "城市"])
	var coefs: Array = data.get("coefs", [1.20, 1.00, 0.85])
	var vol: Array = data.get("vol", [40, 90, 160])
	var n := labels.size()
	if n == 0:
		return
	var bw := iw / float(n) * 0.22
	var max_c := 1.4
	var max_v := 200.0
	for i in range(n):
		var cx: float = ox + iw * (float(i) + 0.42) / float(n)
		var ch: float = ih * (float(coefs[i]) / max_c) * 0.75
		draw_rect(Rect2(Vector2(cx - bw, oy - ch), Vector2(bw, ch)), Color(0.9, 0.65, 0.45))
		draw_string(font, Vector2(cx - bw - 6, oy - ch - 6), "×%.2f" % float(coefs[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.8, 0.6))
		var vh: float = ih * (float(vol[i]) / max_v) * 0.75
		draw_rect(Rect2(Vector2(cx + 2, oy - vh), Vector2(bw, vh)), Color(0.5, 0.75, 0.95))
		draw_string(font, Vector2(cx + 2, oy - vh - 6), "%d" % int(vol[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.62, 0.82, 0.98))
		draw_string(font, Vector2(cx - 10, oy + 20), String(labels[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.78, 0.84, 0.8))
	draw_string(font, Vector2(ox + 4, oy - ih + 18), "橙=买入价格系数（越低越便宜）　蓝=港口库存上限",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.8, 0.74))
	draw_string(font, Vector2(ox + 4, oy - ih + 40), "结论：城市规模大 → 价格系数低、库存多，这是规模经济的简化体现",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.7, 0.66))
