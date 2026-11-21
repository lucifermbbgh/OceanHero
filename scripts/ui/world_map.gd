extends Control
## 1.5.3 世界地图（只读）：已探索显示势力与名称，未探索仅灰点，M/Esc 关闭。

const MAP_RECT := Rect2(28, 76, 1180, 680)

var _nodes := 0

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

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.10, 0.97))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.40, 0.25), false, 2.0)
	draw_string(font, Vector2(24, 38), "世界地图（M 关闭，Esc 关闭）", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.82, 0.45))
	draw_string(font, Vector2(24, 60), "已探索海域显示势力与编号；未知海域仅显示灰点", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.68, 0.68))

	# 先画连线（仅两端都已探索）
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
			draw_line(_pos(md.world_pos), _pos(m2.world_pos), Color(0.35, 0.45, 0.50, 0.7), 1.5)

	# 再画节点
	_nodes = 0
	for i2 in range(1, 31):
		var m: Resource = DataRegistry.get_map(i2)
		if m == null:
			continue
		_nodes += 1
		var p := _pos(m.world_pos)
		var explored: bool = GameState.is_map_explored(i2)
		if explored:
			var col: Color = GameState.NATION_COLORS.get(String(m.nation), Color(0.55, 0.55, 0.6))
			draw_circle(p, 13.0, col)
			draw_circle(p, 13.0, Color(0.95, 0.92, 0.80), false, 1.5)
			var lv := (i2 - 1) / 3 + 1
			var col_i := (i2 - 1) % 3 + 1
			draw_string(font, p + Vector2(16, 5), "%d-%d" % [lv, col_i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.92, 0.88))
			if i2 == GameState.current_map:
				draw_arc(p, 19.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.35), 3.0)
		else:
			draw_circle(p, 10.0, Color(0.22, 0.24, 0.27))
			draw_circle(p, 10.0, Color(0.38, 0.40, 0.44), false, 1.0)
			draw_string(font, p + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.58, 0.62))

	# 图例
	var explored_n := GameState.explored_maps.size()
	draw_string(font, Vector2(28, 790), "已探索 %d / 30　　当前海域：%d　　灰点 = 未知海域" % [explored_n, GameState.current_map], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.76, 0.74))

func _pos(wp: Vector2) -> Vector2:
	return MAP_RECT.position + Vector2(wp.x * MAP_RECT.size.x, wp.y * MAP_RECT.size.y)
