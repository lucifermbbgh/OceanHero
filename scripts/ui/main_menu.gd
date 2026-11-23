extends Control

var slot_box: VBoxContainer
var body: VBoxContainer

func _ready() -> void:
	# 1.5.4：应用显示名用中文，项目名/目录/仓库保持 OceanHero
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("碧海英豪")
		Engine.get_main_loop().get_root().title = "碧海英豪"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.12, 0.17)
	add_child(bg)

	body = VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_CENTER)
	body.position = Vector2(-260, -300)
	body.custom_minimum_size = Vector2(520, 600)
	body.add_theme_constant_override("separation", 12)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(body)

	var title := Label.new()
	title.text = "碧海英豪"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)

	var sub := Label.new()
	sub.text = "OceanHero · 2D 单机航海 RPG"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.6, 0.75, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sub)

	_button("新游戏", func():
		GameState.reset_new_game()
		TimeService.total_days = 0
		SceneRouter.goto(&"base"))

	var lbl := Label.new()
	lbl.text = "—— 存档 ——"
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.6))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(lbl)

	slot_box = VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 4)
	body.add_child(slot_box)
	_rebuild_slots()

	_button("退出", func(): get_tree().quit())

func _rebuild_slots() -> void:
	for c in slot_box.get_children():
		c.queue_free()
	for slot in SaveManager.all_slot_ids():
		var meta: Dictionary = SaveManager.slot_meta(slot)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		slot_box.add_child(hb)
		var tag := "自动" if int(slot) == 0 else "存档 %d" % int(slot)
		var text := "%s　空" % tag
		var col := Color(0.45, 0.5, 0.5)
		if bool(meta.get("exists", false)):
			var map_name := "母港"
			var m: Resource = DataRegistry.get_map(int(meta.get("map", 1)))
			if m != null:
				map_name = String(m.display_name)
			text = "%s　Lv.%d · 金币 %d · 战功 %d · %s" % [tag, int(meta.get("level", 1)),
				int(meta.get("gold", 0)), int(meta.get("commendation", 0)), map_name]
			col = Color(0.85, 0.85, 0.78)
		var l := Label.new()
		l.text = text
		l.custom_minimum_size = Vector2(400, 0)
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", col)
		hb.add_child(l)
		var b := Button.new()
		b.text = "读取"
		b.custom_minimum_size = Vector2(80, 28)
		b.disabled = not bool(meta.get("exists", false))
		var s_id := int(slot)
		b.pressed.connect(func(): _load_slot(s_id))
		hb.add_child(b)

func _load_slot(slot: int) -> void:
	if SaveManager.load_slot(slot):
		SceneRouter.goto(&"base")

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	body.add_child(b)
	return b
