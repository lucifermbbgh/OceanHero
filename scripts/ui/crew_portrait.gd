class_name CrewPortrait
extends RefCounted
## 1.6.20：船员头像。4 岗位 × 6 面孔（按姓名稳定选取），稀有度用色框区分。

const POSTS := ["mate", "gunner", "surgeon", "sailor"]
const LOOKS := 6
const POST_ALIAS := {"collector": "mate", "raider": "gunner"}

static var _CACHE := {}

## 同一船员始终同一张脸：姓名 + 船员 id 的哈希落在 0..5
static func look_of(c) -> int:
	var key := "%s|%s" % [String(c.display_name), String(c.crew_id)]
	return posmod(key.hash(), LOOKS)

static func path_of(c) -> String:
	var post := String(c.role)
	if POST_ALIAS.has(post):
		post = String(POST_ALIAS[post])
	if not POSTS.has(post):
		post = "sailor"
	return "res://art/icons/crew/crew_%s_%d.png" % [post, look_of(c)]

static func texture(c) -> Texture2D:
	var path := path_of(c)
	if _CACHE.has(path):
		return _CACHE[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		var im := Image.new()
		if im.load(path) == OK:
			tex = ImageTexture.create_from_image(im)
	_CACHE[path] = tex
	return tex

## 头像控件：稀有度色描边 + 圆形裁切的方形贴图
static func icon(c, px: float = 40.0) -> Control:
	var box := Panel.new()
	box.custom_minimum_size = Vector2(px, px)
	box.size = Vector2(px, px)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.11)
	sb.set_border_width_all(2)
	sb.border_color = Rarity.color(int(c.rarity))
	sb.set_corner_radius_all(3)
	box.add_theme_stylebox_override("panel", sb)
	var tex := texture(c)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 2.0
		tr.offset_top = 2.0
		tr.offset_right = -2.0
		tr.offset_bottom = -2.0
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
	return box
