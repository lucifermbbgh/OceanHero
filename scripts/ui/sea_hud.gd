extends CanvasLayer
## 海域 HUD。全部用代码构建，避免手写 .tscn 的锚点错误。

signal ammo_selected(id: StringName)
signal fire_pressed
signal boarding_pressed
signal retreat_pressed
signal return_pressed

const BAR_W := 220

var _player_name: Label
var _player_bars := {}
var _target_panel: PanelContainer
var _target_name: Label
var _target_bars := {}
var _ticker: Label
var _hint: Label
var _clock: Label
var _ammo_buttons := {}
var _fire_btn: Button
var _board_btn: Button
var _retreat_btn: Button
var _ticker_timer := 0.0

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_player_panel(root)
	_build_target_panel(root)
	_build_command_bar(root)

	_clock = _make_label(root, "", 17)
	_clock.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_clock.position = Vector2(660, 26)
	_clock.custom_minimum_size = Vector2(340, 24)
	_clock.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_ticker = _make_label(root, "", 16)
	_ticker.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_ticker.position = Vector2(24, -80)
	_ticker.custom_minimum_size = Vector2(600, 24)
	_ticker.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))

	_hint = _make_label(root, "", 18)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-200, -140)
	_hint.custom_minimum_size = Vector2(400, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _make_label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _make_panel(root: Control, pos: Vector2, size: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.custom_minimum_size = size
	p.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.12, 0.82)
	style.border_color = Color(0.55, 0.45, 0.2, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", style)
	root.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	return vb

func _bar_row(parent: VBoxContainer, key: String, label: String, color: Color) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(46, 0)
	l.add_theme_font_size_override("font_size", 13)
	hb.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 100.0
	bar.custom_minimum_size = Vector2(BAR_W, 14)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bar.add_theme_stylebox_override("background", bg)
	hb.add_child(bar)
	_player_bars[key] = bar

func _build_player_panel(root: Control) -> void:
	var vb := _make_panel(root, Vector2(20, 18), Vector2(380, 150))
	_player_name = Label.new()
	_player_name.text = "船名"
	_player_name.add_theme_font_size_override("font_size", 16)
	vb.add_child(_player_name)
	_bar_row(vb, "hull", "船体", Color(0.72, 0.28, 0.28))
	_bar_row(vb, "sail", "风帆", Color(0.85, 0.82, 0.7))
	_bar_row(vb, "rudder", "舵机", Color(0.55, 0.7, 0.85))
	_bar_row(vb, "crew", "船员", Color(0.45, 0.72, 0.45))

func _build_target_panel(root: Control) -> void:
	_target_panel = PanelContainer.new()
	_target_panel.position = Vector2(1180, 18)
	_target_panel.custom_minimum_size = Vector2(320, 170)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.04, 0.04, 0.85)
	style.border_color = Color(0.65, 0.25, 0.25, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_target_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_target_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_target_panel.add_child(vb)
	_target_name = Label.new()
	_target_name.text = "目标"
	_target_name.add_theme_font_size_override("font_size", 16)
	vb.add_child(_target_name)
	for key in ["hull", "sail", "rudder", "crew"]:
		var hb := HBoxContainer.new()
		vb.add_child(hb)
		var l := Label.new()
		l.text = {"hull": "船体", "sail": "风帆", "rudder": "舵机", "crew": "船员"}[key]
		l.custom_minimum_size = Vector2(46, 0)
		l.add_theme_font_size_override("font_size", 13)
		hb.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.value = 100.0
		bar.custom_minimum_size = Vector2(BAR_W, 14)
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.75, 0.3, 0.3)
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.55)
		bar.add_theme_stylebox_override("background", bg)
		hb.add_child(bar)
		_target_bars[key] = bar
	_target_panel.visible = false

func _build_command_bar(root: Control) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hb.position = Vector2(-320, -76)
	hb.custom_minimum_size = Vector2(640, 44)
	root.add_child(hb)

	var ammo_names := {"solid": "实心弹", "chain": "链弹", "grape": "葡萄弹"}
	for id in ["solid", "chain", "grape"]:
		var b := Button.new()
		b.text = ammo_names[id]
		b.custom_minimum_size = Vector2(96, 38)
		b.pressed.connect(func(): ammo_selected.emit(StringName(id)))
		hb.add_child(b)
		_ammo_buttons[StringName(id)] = b

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(20, 0)
	hb.add_child(sep)

	_fire_btn = Button.new()
	_fire_btn.text = "开火"
	_fire_btn.custom_minimum_size = Vector2(110, 38)
	_fire_btn.disabled = true
	_fire_btn.pressed.connect(func(): fire_pressed.emit())
	hb.add_child(_fire_btn)

	_board_btn = Button.new()
	_board_btn.text = "接舷"
	_board_btn.custom_minimum_size = Vector2(96, 38)
	_board_btn.disabled = true
	_board_btn.pressed.connect(func(): boarding_pressed.emit())
	hb.add_child(_board_btn)

	_retreat_btn = Button.new()
	_retreat_btn.text = "撤离"
	_retreat_btn.custom_minimum_size = Vector2(96, 38)
	_retreat_btn.pressed.connect(func(): retreat_pressed.emit())
	hb.add_child(_retreat_btn)

	var ret := Button.new()
	ret.text = "返回母港"
	ret.custom_minimum_size = Vector2(110, 38)
	ret.pressed.connect(func(): return_pressed.emit())
	hb.add_child(ret)

func update_all(player, target) -> void:
	if player != null and is_instance_valid(player):
		_player_name.text = "%s   Lv.%d   金币 %d   战功 %d" % [
			player.display_name, GameState.level, GameState.gold, GameState.commendation,
		]
		_set_bar(_player_bars, "hull", player.hull_pct() * 100.0)
		_set_bar(_player_bars, "sail", player.sail_pct() * 100.0)
		_set_bar(_player_bars, "rudder", player.rudder_pct() * 100.0)
		_set_bar(_player_bars, "crew", player.crew_pct() * 100.0)
	if target != null and is_instance_valid(target) and target.alive:
		_target_panel.visible = true
		_target_name.text = target.display_name
		_set_bar(_target_bars, "hull", _pct_of(target, "hull") * 100.0)
		_set_bar(_target_bars, "sail", _pct_of(target, "sail") * 100.0)
		_set_bar(_target_bars, "rudder", _pct_of(target, "rudder") * 100.0)
		_set_bar(_target_bars, "crew", _pct_of(target, "crew") * 100.0)
	else:
		_target_panel.visible = false
	if _clock != null:
		_clock.text = "%s   %s" % [TimeService.date_text(), TimeService.speed_text()]

	if player != null and is_instance_valid(player):
		var t = player.target
		if t == null or not is_instance_valid(t) or not t.alive:
			_fire_btn.text = "开火"
			_fire_btn.disabled = true
		elif player.reload_timer > 0.0:
			_fire_btn.text = "装填 %.1fs" % player.reload_timer
			_fire_btn.disabled = true
		elif not player.can_target(t):
			_fire_btn.text = "超出射程"
			_fire_btn.disabled = true
		else:
			_fire_btn.text = "开火！"
			_fire_btn.disabled = false
	if player != null and is_instance_valid(player) and target != null and is_instance_valid(target):
		var near: bool = player.global_position.distance_to(target.global_position) <= 140.0
		var weak: bool = _pct_of(target, "hull") <= 0.10
		_board_btn.disabled = not (near and weak)
		_board_btn.text = "接舷" if _board_btn.disabled == false else ("接舷(需近身)" if weak else "接舷(需击弱)")
	else:
		_board_btn.disabled = true
		_board_btn.text = "接舷"
	_retreat_btn.disabled = player == null or not is_instance_valid(player) or not player.can_retreat()

func _pct_of(ship, key: String) -> float:
	match key:
		"hull": return ship.hull_pct() if ship.has_method("hull_pct") else 1.0
		"sail": return ship.sail_pct() if ship.has_method("sail_pct") else 1.0
		"rudder": return ship.rudder_pct() if ship.has_method("rudder_pct") else 1.0
		"crew": return ship.crew_pct() if ship.has_method("crew_pct") else 1.0
	return 1.0

func _set_bar(dict: Dictionary, key: String, v: float) -> void:
	if dict.has(key):
		dict[key].value = clampf(v, 0.0, 100.0)

func set_ammo_highlight(id: StringName) -> void:
	for k in _ammo_buttons.keys():
		_ammo_buttons[k].modulate = Color(1, 1, 1) if k == id else Color(0.6, 0.6, 0.6)

func ticker(text: String) -> void:
	_ticker.text = text
	_ticker_timer = 4.0

func set_hint(text: String) -> void:
	_hint.text = text

func _process(delta: float) -> void:
	if _ticker_timer > 0.0:
		_ticker_timer -= delta
		if _ticker_timer <= 0.0:
			_ticker.text = ""
