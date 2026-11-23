extends Control
## 1.5.6 海上小地图：当前海域俯视图（岛屿/港口/玩家朝向）。

const BOX := 220.0
var world_size := 4000.0
var sea: Node = null

func _ready() -> void:
	size = Vector2(BOX, BOX)
	position = Vector2(get_viewport_rect().size.x - BOX - 16.0, 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	if visible:
		queue_redraw()

func map_rect() -> Rect2:
	return Rect2(6.0, 24.0, BOX - 12.0, BOX - 30.0)

func map_scale() -> float:
	return minf(map_rect().size.x, map_rect().size.y) / maxf(1.0, world_size)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.09, 0.12, 0.82))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.55, 0.55, 0.9), false, 1.5)
	draw_string(font, Vector2(8, 17), "本海域", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.80, 0.55))
	var area := map_rect()
	draw_rect(area, Color(0.08, 0.16, 0.20, 0.85))
	if sea == null:
		return
	var sc := map_scale()
	# 岛屿
	for isl in sea.islands:
		var wp: Vector2 = isl[0]
		var p := area.position + Vector2(wp.x, wp.y) * sc
		var rr: float = maxf(2.5, float(isl[1]) * sc)
		draw_circle(p, rr, Color(0.35, 0.32, 0.26))
		draw_circle(p, rr, Color(0.85, 0.72, 0.40), false, 1.0)
	# 玩家
	if sea.player != null:
		var pp: Vector2 = area.position + Vector2(sea.player.global_position.x, sea.player.global_position.y) * sc
		var h: float = float(sea.player.heading)
		var fwd := Vector2(cos(h), sin(h))
		var side := Vector2(-fwd.y, fwd.x)
		var tri := PackedVector2Array([pp + fwd * 7.0, pp - fwd * 4.0 + side * 4.5, pp - fwd * 4.0 - side * 4.5])
		draw_colored_polygon(tri, Color(1.0, 0.92, 0.45))
