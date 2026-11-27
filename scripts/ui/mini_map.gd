extends Control
## 1.5.6 海上小地图：当前海域俯视图（岛屿/港口/玩家朝向）。

const BOX := 220.0
var world_size := 4000.0
var sea: Node = null
var _base: Texture2D = null
var _bboxes: Dictionary = {}
static var _CACHE := {}

func _ready() -> void:
	size = Vector2(BOX, BOX)
	position = Vector2(get_viewport_rect().size.x - BOX - 16.0, 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bp := "res://art/world_map/chart_base_game.png"
	if _CACHE.has(bp):
		_base = _CACHE[bp]
	elif ResourceLoader.exists(bp):
		_base = load(bp)
		_CACHE[bp] = _base
	else:
		var im := Image.new()
		if im.load(bp) == OK:
			_base = ImageTexture.create_from_image(im)
			_CACHE[bp] = _base
	var rp := "res://data/generated/world_regions.json"
	if FileAccess.file_exists(rp):
		var f := FileAccess.open(rp, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				for r in parsed.get("regions", []):
					var idx0: int = int(r.get("index", 0))
					var sr: Array = r.get("sea_rect", [])
					if sr.size() == 4:
						_bboxes[idx0] = Rect2(float(sr[0]), float(sr[1]), float(sr[2]), float(sr[3]))
						continue
					var xs: Array = []
					var ys: Array = []
					for p in r.get("polygon", []):
						xs.append(float(p[0]))
						ys.append(float(p[1]))
					if xs.is_empty():
						continue
					var x0: float = xs.min()
					var x1: float = xs.max()
					var y0: float = ys.min()
					var y1: float = ys.max()
					_bboxes[idx0] = Rect2(x0, y0, x1 - x0, y1 - y0)

func _tex(path: String) -> Texture2D:
	var full := "res://art/" + path
	if _CACHE.has(full):
		return _CACHE[full]
	var tex: Texture2D = null
	if ResourceLoader.exists(full):
		tex = load(full)
	else:
		var im := Image.new()
		if im.load(full) == OK:
			tex = ImageTexture.create_from_image(im)
	_CACHE[full] = tex
	return tex

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
	# 1.6.15：小地图 = 开阔海背景 + 与海面场景同源的岛屿精灵
	if _base != null:
		var tw0 := float(_base.get_width())
		var th0 := float(_base.get_height())
		var src0 := Rect2(tw0 * 0.34, th0 * 0.76, tw0 * 0.34, th0 * 0.22)
		draw_texture_rect_region(_base, area, src0)
	else:
		draw_rect(area, Color(0.10, 0.30, 0.40, 0.9))
	draw_rect(area, Color(0.55, 0.62, 0.60, 0.8), false, 1.0)
	var sc := map_scale()
	for isl in sea.islands:
		var wp: Vector2 = isl[0]
		var p := area.position + Vector2(wp.x, wp.y) * sc
		if isl.size() > 5 and String(isl[5]) != "" and float(isl[6]) > 0.0:
			var tex: Texture2D = _tex(String(isl[5]))
			if tex != null:
				var rw := float(isl[1]) * 2.4 / maxf(1.0, world_size) * area.size.x
				var asp := clampf(float(isl[7]) / maxf(0.01, float(isl[6])), 0.5, 2.0)
				var rh := rw * asp
				draw_texture_rect(tex, Rect2(p - Vector2(rw, rh) * 0.5, Vector2(rw, rh)), false)
		else:
			draw_circle(p, maxf(2.5, float(isl[1]) * sc), Color(0.82, 0.74, 0.55))
		var ppos: Vector2 = isl[8] if isl.size() > 8 else isl[0]
		var pd := area.position + Vector2(ppos.x, ppos.y) * sc
		draw_circle(pd, 2.5, Color(0.95, 0.75, 0.25))
	# 玩家
	if sea.player != null:
		var pp: Vector2 = area.position + Vector2(sea.player.global_position.x, sea.player.global_position.y) * sc
		var h: float = float(sea.player.heading)
		var fwd := Vector2(cos(h), sin(h))
		var side := Vector2(-fwd.y, fwd.x)
		var tri := PackedVector2Array([pp + fwd * 7.0, pp - fwd * 4.0 + side * 4.5, pp - fwd * 4.0 - side * 4.5])
		draw_colored_polygon(tri, Color(1.0, 0.92, 0.45))
