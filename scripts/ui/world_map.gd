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
var _land: Array = []
var _land_tex: Texture2D = null
var _mask_img: Image = null

func _ready() -> void:
	size = Vector2(1568, 812)
	position = Vector2(16, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_load_polys()
	_load_land()
	_bg = _load_tex("res://art/world_map/chart_base_game.png")
	var mp := "res://art/world_map/land_mask_game.png"
	if ResourceLoader.exists(mp):
		var mres = load(mp)
		if mres is Texture2D:
			_mask_img = mres.get_image()
	if _mask_img == null:
		var mi := Image.new()
		if mi.load(mp) == OK:
			_mask_img = mi

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
	if _in_land(p):
		return -1
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

static var _CACHE := {}

func _load_tex(path: String) -> Texture2D:
	if _CACHE.has(path):
		return _CACHE[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	_CACHE[path] = tex
	return tex

func _load_land() -> void:
	_land.clear()
	var path := "res://data/generated/land_masses.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for item in parsed.get("land", []):
		var pts: Array = []
		for p in item.get("polygon", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		_land.append(pts)

func _unpos(p: Vector2) -> Vector2:
	var c := MAP_RECT.position + MAP_RECT.size * 0.5
	return (p - c - _offset) / (MAP_RECT.size * _zoom) + Vector2(0.5, 0.5)

func _in_land(p: Vector2) -> bool:
	if _mask_img != null:
		var wp := _unpos(p)
		if wp.x < 0.0 or wp.y < 0.0 or wp.x > 1.0 or wp.y > 1.0:
			return false
		var mx := int(wp.x * float(_mask_img.get_width() - 1))
		var my := int(wp.y * float(_mask_img.get_height() - 1))
		return _mask_img.get_pixel(mx, my).r > 0.5
	for lp in _land:
		var pts := PackedVector2Array()
		for v in lp:
			pts.append(_pos(v))
		if pts.size() >= 3 and Geometry2D.is_point_in_polygon(p, pts):
			return true
	return false

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
	return c + (wp - Vector2(0.5, 0.5)) * MAP_RECT.size * _zoom + _offset

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.10, 0.97))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.40, 0.25), false, 2.0)
	draw_string(font, Vector2(24, 38), "世界地图（M 关闭，Esc 关闭）", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.82, 0.45))
	draw_string(font, Vector2(24, 60), "悬停查看、点击选中；滚轮缩放，拖拽平移", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.68, 0.68))
	draw_rect(INFO_RECT, Color(0.10, 0.12, 0.15, 0.9))
	draw_rect(INFO_RECT, Color(0.35, 0.40, 0.45), false, 1.0)

	# 海图底图（AI 艺术母版）
	draw_rect(MAP_RECT, Color(0.04, 0.16, 0.26))
	if _bg != null:
		var bg_rect := Rect2(_pos(Vector2.ZERO), MAP_RECT.size * _zoom)
		draw_texture_rect(_bg, bg_rect, false)

	# 区域：未探索=迷雾遮罩，已探索=细边界
	_nodes = 0
	for i in range(1, 31):
		var md: Resource = DataRegistry.get_map(i)
		if md == null:
			continue
		_nodes += 1
		var poly := _cell_poly(i)
		if poly.size() < 3:
			continue
		var closed := poly.duplicate()
		closed.append(poly[0])
		if not GameState.is_map_explored(i):
			draw_colored_polygon(poly, Color(0.02, 0.05, 0.08, 0.90))
			draw_polyline(closed, Color(0.25, 0.30, 0.34, 0.35), 1.0)
			continue
		var line := Color(0.90, 0.93, 0.95, 0.30)
		var wdt := 1.5
		var fill := Color(0, 0, 0, 0)
		if i == _selected:
			fill = Color(0.20, 0.55, 0.90, 0.18)
			line = Color(0.45, 0.90, 1.0, 0.95)
			wdt = 2.5
		elif i == _hover:
			fill = Color(1, 1, 1, 0.08)
			line = Color(1, 1, 1, 0.85)
			wdt = 2.0
		if fill.a > 0.0:
			draw_colored_polygon(poly, fill)
		draw_polyline(closed, line, wdt)
		if i == GameState.current_map:
			draw_polyline(closed, Color(1.0, 0.82, 0.35, 0.95), 3.0)

	# 节点与标签：已探索显示琥珀节点，未探索仅问号
	for i2 in range(1, 31):
		var md2: Resource = DataRegistry.get_map(i2)
		if md2 == null:
			continue
		var c := _anchor_pos(i2)
		if not GameState.is_map_explored(i2):
			draw_string(font, c + Vector2(-4, 4), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.60, 0.64))
			continue
		var fac: Color = GameState.NATION_COLORS.get(String(md2.nation), Color(0.9, 0.7, 0.2))
		draw_circle(c, 7.0, fac)
		draw_circle(c, 4.5, Color(0.91, 0.70, 0.23))
		draw_circle(c, 1.8, Color(1.0, 0.96, 0.86))
		draw_string(font, c + Vector2(11, 4), "%d-%d" % [(i2 - 1) / 3 + 1, (i2 - 1) % 3 + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.97, 0.97, 0.94))

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
