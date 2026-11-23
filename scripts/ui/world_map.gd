extends Control
## 1.6.1 世界地图（矢量区域版）：多边形海域 + 迷雾 + 悬停/选中/航线

const MAP_RECT := Rect2(28, 76, 1180, 680)
const INFO_RECT := Rect2(1228, 76, 312, 680)

var _nodes := 0
var _hover := -1
var _selected := -1
var _route: Array = []
var _zoom := 1.0
var _offset := Vector2.ZERO
var _dragging := false
var _drag_moved := false
var _bg: Texture2D = null

func _ready() -> void:
	size = Vector2(1568, 812)
	position = Vector2(16, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_load_polys()
	var bg_path := "res://art/world_map/world_map_bg.png"
	if ResourceLoader.exists(bg_path):
		_bg = load(bg_path)
	else:
		# 尚未导入时直接读原始 PNG
		var img := Image.new()
		if img.load(bg_path) == OK:
			_bg = ImageTexture.create_from_image(img)

func toggle() -> void:
	visible = not visible
	if visible:
		queue_redraw()

func refresh() -> void:
	queue_redraw()

func node_count() -> int:
	return _nodes

func select_map(idx: int) -> void:
	_selected = idx
	_route = _compute_route(GameState.current_map, idx)
	queue_redraw()

func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, 0.7, 1.8)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			_offset += event.relative
			_drag_moved = true
			_clamp_offset()
		else:
			var h := _hit(event.position)
			if h != _hover:
				_hover = h
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = false
			else:
				_dragging = false
				if not _drag_moved:
					select_map(_hit(event.position))

func _clamp_offset() -> void:
	_offset.x = clampf(_offset.x, -MAP_RECT.size.x * 0.35, MAP_RECT.size.x * 0.35)
	_offset.y = clampf(_offset.y, -MAP_RECT.size.y * 0.35, MAP_RECT.size.y * 0.35)

func _hit(p: Vector2) -> int:
	for i in range(1, 31):
		if Geometry2D.is_point_in_polygon(p, _cell_poly(i)):
			return i
	return -1

## 从 Tiled 构建产物读取归一化多边形；缺文件时回退到程序生成
var _polys: Dictionary = {}

func _load_polys() -> void:
	_polys.clear()
	var path := "res://data/generated/world_regions.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for r in parsed.get("regions", []):
		var pts: Array = []
		for p in r.get("polygon", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		_polys[int(r.get("index", 0))] = {"polygon": pts,
			"anchor": Vector2(float(r["anchor"][0]), float(r["anchor"][1]))}

func _anchor_pos(idx: int) -> Vector2:
	if _polys.has(idx):
		return _pos(_polys[idx]["anchor"])
	var md: Resource = DataRegistry.get_map(idx)
	return _pos(md.world_pos) if md != null else Vector2.ZERO

## 以 world_pos 为中心生成「切角矩形」海域多边形（地图局部坐标）
func _cell_poly(idx: int) -> PackedVector2Array:
	if _polys.has(idx):
		# 向质心内缩 8%，让海域之间露出底图（更接近海图观感）
		var center: Vector2 = _polys[idx]["anchor"]
		var out := PackedVector2Array()
		for p in _polys[idx]["polygon"]:
			var pv: Vector2 = p
			var inset: Vector2 = center + (pv - center) * 1.0
			out.append(_pos(inset))
		return out
	var md: Resource = DataRegistry.get_map(idx)
	if md == null:
		return PackedVector2Array()
	var c := _pos(md.world_pos)
	var w := 300.0 * _zoom
	var h := 56.0 * _zoom
	var bx := w * 0.5
	var by := h * 0.5
	var cut := minf(18.0 * _zoom, minf(bx, by) * 0.5)
	var pts := PackedVector2Array([
		c + Vector2(-bx + cut, -by), c + Vector2(bx - cut, -by),
		c + Vector2(bx, -by + cut), c + Vector2(bx, by - cut),
		c + Vector2(bx - cut, by), c + Vector2(-bx + cut, by),
		c + Vector2(-bx, by - cut), c + Vector2(-bx, -by + cut),
	])
	return pts

func _compute_route(from_i: int, to_i: int) -> Array:
	if from_i <= 0 or to_i <= 0 or from_i == to_i:
		return []
	if not GameState.is_map_explored(to_i):
		return []
	var dist := {}
	var prev := {}
	var open: Array = [from_i]
	for i in range(1, 31):
		dist[i] = 1e9
	dist[from_i] = 0
	while not open.is_empty():
		var cur := int(open.pop_front())
		var md: Resource = DataRegistry.get_map(cur)
		if md == null:
			continue
		for nb in md.neighbors:
			var nx := int(nb)
			if nx <= 0 or nx > 30:
				continue
			if not GameState.is_map_explored(nx):
				continue
			if GameState.map_tier_of(nx) > GameState.unlocked_tier():
				continue
			var nd := float(dist[cur]) + 1.0
			if nd < float(dist.get(nx, 1e9)):
				dist[nx] = nd
				prev[nx] = cur
				open.append(nx)
	if float(dist.get(to_i, 1e9)) >= 1e9:
		return []
	var path: Array = [to_i]
	var c := to_i
	while c != from_i:
		c = int(prev.get(c, from_i))
		path.push_front(c)
	return path

func _pos(wp: Vector2) -> Vector2:
	var c := MAP_RECT.position + MAP_RECT.size * 0.5
	return c + (wp - Vector2(0.5, 0.45)) * MAP_RECT.size * _zoom + _offset

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.10, 0.97))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.40, 0.25), false, 2.0)
	draw_string(font, Vector2(24, 38), "世界地图（M 关闭，Esc 关闭）", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.82, 0.45))
	draw_string(font, Vector2(24, 60), "悬停查看、点击选中；滚轮缩放，拖拽平移", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.68, 0.68))
	draw_rect(INFO_RECT, Color(0.10, 0.12, 0.15, 0.9))
	draw_rect(INFO_RECT, Color(0.35, 0.40, 0.45), false, 1.0)

	# 海域底图
	draw_rect(MAP_RECT, Color(0.04, 0.16, 0.26))
	if _bg != null:
		var bg_rect := Rect2(_pos(Vector2.ZERO), MAP_RECT.size * _zoom)
		draw_texture_rect(_bg, bg_rect, false)
	for wv in range(14):
		var y0 := MAP_RECT.position.y + 24.0 + float(wv) * 48.0
		var pts := PackedVector2Array()
		for sx in range(0, 40):
			var x := MAP_RECT.position.x + float(sx) * (MAP_RECT.size.x / 39.0)
			pts.append(Vector2(x, y0 + sin(float(sx) * 0.7 + float(wv)) * 3.0))
		draw_polyline(pts, Color(0.12, 0.35, 0.48, 0.25), 1.0)

	# 区域多边形
	_nodes = 0
	for i in range(1, 31):
		var md: Resource = DataRegistry.get_map(i)
		if md == null:
			continue
		_nodes += 1
		var poly := _cell_poly(i)
		if poly.size() < 3:
			continue
		var explored: bool = GameState.is_map_explored(i)
		var fill := Color(0.02, 0.05, 0.08, 0.20)
		var line := Color(0.30, 0.36, 0.40, 0.35)
		if explored:
			var base_col: Color = GameState.NATION_COLORS.get(String(md.nation), Color(0.45, 0.55, 0.6))
			fill = Color(base_col.r, base_col.g, base_col.b, 0.22)
			line = Color(base_col.r * 1.2, base_col.g * 1.2, base_col.b * 1.2, 0.9)
		if i == _selected:
			fill = Color(0.20, 0.55, 0.90, 0.55)
			line = Color(0.45, 0.90, 1.0)
		if i == _hover:
			line = Color(1, 1, 1)
		draw_colored_polygon(poly, fill)
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, line, 2.0)
		if i == GameState.current_map:
			draw_polyline(closed, Color(1.0, 0.82, 0.35), 3.0)
		var c := _anchor_pos(i)
		if explored:
			draw_string(font, c + Vector2(-18, 5), "%d-%d" % [(i - 1) / 3 + 1, (i - 1) % 3 + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.95, 0.9))
		else:
			draw_string(font, c + Vector2(-4, 4), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.50, 0.54))

	# 航线（虚线）
	if _route.size() >= 2:
		for k in range(_route.size() - 1):
			var ma: Resource = DataRegistry.get_map(int(_route[k]))
			var mb: Resource = DataRegistry.get_map(int(_route[k + 1]))
			if ma == null or mb == null:
				continue
			_dashed_line(_anchor_pos(int(_route[k])), _anchor_pos(int(_route[k + 1])), Color(1.0, 0.80, 0.30), 3.0)

	# 右侧详情
	var ix := INFO_RECT.position.x + 16.0
	var iy := INFO_RECT.position.y + 30.0
	var show_i := _selected if _selected > 0 else _hover
	if show_i > 0 and GameState.is_map_explored(show_i):
		var sm: Resource = DataRegistry.get_map(show_i)
		if sm != null:
			draw_string(font, Vector2(ix, iy), String(sm.display_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.88, 0.60))
			iy += 30
			draw_string(font, Vector2(ix, iy), "势力：%s" % String(GameState.NATION_NAMES.get(String(sm.nation), "争夺")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.82, 0.86, 0.84))
			iy += 24
			draw_string(font, Vector2(ix, iy), "危险：劫掠 %d · 海兽 %d" % [int(sm.pirates), int(sm.monsters)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.82, 0.86, 0.84))
			iy += 24
			draw_string(font, Vector2(ix, iy), "级别：%d 级" % int(sm.tier), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.82, 0.86, 0.84))
			iy += 30
			if _route.size() >= 2:
				draw_string(font, Vector2(ix, iy), "航线：%d 步" % (_route.size() - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.82, 0.35))
			else:
				draw_string(font, Vector2(ix, iy), "航线：无已知航路", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.55, 0.5))
	else:
		draw_string(font, Vector2(ix, iy), "未知海域", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.65, 0.68, 0.70))
		iy += 30
		draw_string(font, Vector2(ix, iy), "尚未探索，无法查看信息", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.58, 0.60))

	draw_string(font, Vector2(28, 790), "已探索 %d / 30　　当前海域：%d　　金框 = 当前，黄虚线 = 航线" % [GameState.explored_maps.size(), GameState.current_map], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.76, 0.74))

func _dashed_line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var d := b - a
	var len := d.length()
	if len <= 0.0:
		return
	var dir := d / len
	var seg := 14.0
	var x := 0.0
	while x < len:
		var e := minf(x + seg, len)
		draw_line(a + dir * x, a + dir * e, col, w)
		x = e + 8.0
