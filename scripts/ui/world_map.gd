extends Control
## 1.5.5 世界地图（只读 + 交互增强）：悬停/选中/详情/缩放/拖拽/路线预览。

const MAP_RECT := Rect2(28, 76, 1180, 680)
const INFO_RECT := Rect2(1228, 76, 312, 680)
const NODE_R := 13.0

var _nodes := 0
var _hover := -1
var _selected := -1
var _route: Array = []
var _zoom := 1.0
var _offset := Vector2.ZERO
var _dragging := false
var _drag_moved := false
var _drag_from := Vector2.ZERO

func _ready() -> void:
	size = Vector2(1568, 812)
	position = Vector2(16, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

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
				_drag_from = event.position
			else:
				_dragging = false
				if not _drag_moved:
					var h2 := _hit(event.position)
					select_map(h2)

func _clamp_offset() -> void:
	_offset.x = clampf(_offset.x, -MAP_RECT.size.x * 0.35, MAP_RECT.size.x * 0.35)
	_offset.y = clampf(_offset.y, -MAP_RECT.size.y * 0.35, MAP_RECT.size.y * 0.35)

func _hit(p: Vector2) -> int:
	var best := -1
	var best_d := NODE_R * 1.6
	for i in range(1, 31):
		var m: Resource = DataRegistry.get_map(i)
		if m == null:
			continue
		var d := p.distance_to(_pos(m.world_pos))
		if d < best_d:
			best_d = d
			best = i
	return best

func _compute_route(from_i: int, to_i: int) -> Array:
	if from_i <= 0 or to_i <= 0 or from_i == to_i:
		return []
	if not GameState.is_map_explored(to_i):
		return []
	# 仅已探索且已解锁的节点参与寻路
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

	# 连线
	for i in range(1, 31):
		if not GameState.is_map_explored(i):
			continue
		var md: Resource = DataRegistry.get_map(i)
		if md == null:
			continue
		for nb in md.neighbors:
			var j := int(nb)
			if j <= i or j > 30 or not GameState.is_map_explored(j):
				continue
			var m2: Resource = DataRegistry.get_map(j)
			if m2 == null:
				continue
			draw_line(_pos(md.world_pos), _pos(m2.world_pos), Color(0.35, 0.45, 0.50, 0.55), 1.5)

	# 路线
	if _route.size() >= 2:
		for k in range(_route.size() - 1):
			var ma: Resource = DataRegistry.get_map(int(_route[k]))
			var mb: Resource = DataRegistry.get_map(int(_route[k + 1]))
			if ma != null and mb != null:
				draw_line(_pos(ma.world_pos), _pos(mb.world_pos), Color(1.0, 0.80, 0.30), 3.0)

	# 节点
	_nodes = 0
	var reachable := GameState.travel_options()
	for i2 in range(1, 31):
		var m: Resource = DataRegistry.get_map(i2)
		if m == null:
			continue
		_nodes += 1
		var p := _pos(m.world_pos)
		var explored: bool = GameState.is_map_explored(i2)
		if explored:
			var col: Color = GameState.NATION_COLORS.get(String(m.nation), Color(0.55, 0.55, 0.6))
			draw_circle(p, NODE_R, col)
			draw_circle(p, NODE_R, Color(0.95, 0.92, 0.80), false, 1.5)
			var lv := (i2 - 1) / 3 + 1
			var col_i := (i2 - 1) % 3 + 1
			draw_string(font, p + Vector2(16, 5), "%d-%d" % [lv, col_i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.92, 0.88))
			var is_reach := false
			for o in reachable:
				if int(o["index"]) == i2 and bool(o["unlocked"]):
					is_reach = true
			if is_reach:
				draw_arc(p, NODE_R + 6.0, 0.0, TAU, 24, Color(0.45, 0.95, 0.60), 1.5)
			if i2 == GameState.current_map:
				draw_arc(p, NODE_R + 9.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.35), 3.0)
			if i2 == _selected:
				draw_arc(p, NODE_R + 6.0, 0.0, TAU, 32, Color(0.40, 0.85, 1.0), 2.5)
			if i2 == _hover:
				draw_arc(p, NODE_R + 4.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0), 1.5)
		else:
			draw_circle(p, NODE_R - 3.0, Color(0.22, 0.24, 0.27))
			draw_circle(p, NODE_R - 3.0, Color(0.38, 0.40, 0.44), false, 1.0)
			draw_string(font, p + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.58, 0.62))

	# 右侧详情
	var ix := INFO_RECT.position.x + 16.0
	var iy := INFO_RECT.position.y + 30.0
	var show_i := _selected if _selected > 0 else _hover
	if show_i > 0 and GameState.is_map_explored(show_i):
		var sm: Resource = DataRegistry.get_map(show_i)
		if sm != null:
			var lv2 := (show_i - 1) / 3 + 1
			var col2 := (show_i - 1) % 3 + 1
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

	var explored_n := GameState.explored_maps.size()
	draw_string(font, Vector2(28, 790), "已探索 %d / 30　　当前海域：%d　　黄线 = 路线预览，绿环 = 可直接前往" % [explored_n, GameState.current_map], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.76, 0.74))
