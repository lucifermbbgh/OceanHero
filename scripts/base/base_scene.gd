extends Node2D
## 母港「翡翠港」。阶段一只做：修理、市场、出航、存档。

const MarketModel = preload("res://scripts/systems/market_model.gd")
const StatsLib = preload("res://scripts/systems/ship_stats.gd")
const Rarity = preload("res://scripts/ui/rarity.gd")
const CrewFactory = preload("res://scripts/systems/crew_factory.gd")
func _pid() -> StringName:
	return GameState.visit_port_id

var ui: CanvasLayer
var status_label: Label
var log_label: Label
var market_root: PanelContainer
var market_list: VBoxContainer
var yard_root: PanelContainer
var yard_list: VBoxContainer
var tavern_root: PanelContainer
var tavern_list: VBoxContainer
var build_root: PanelContainer
var build_list: VBoxContainer
var ex_tab := 0
var quest_root: PanelContainer
var quest_list: VBoxContainer
var save_root: PanelContainer
var save_list: VBoxContainer
var rep_root: PanelContainer
var rep_list: VBoxContainer
var help_root: PanelContainer
var help_list: VBoxContainer
var victory_root: PanelContainer
var victory_shown := false
var _log_timer := 0.0

func _ready() -> void:
	GameState.ensure_ship()
	_build_scenery()
	_build_camera()
	_build_ui()
	_build_close_button()
	_apply_fullscreen_layout()
	_sync_ship_state()
	if not EventBus.gold_changed.is_connected(_on_gold_changed):
		EventBus.gold_changed.connect(_on_gold_changed)
	_refresh()
	# 进入母港自动存档
	if GameState.gold > 0:
		SaveManager.auto_save()
	_show_victory_if_needed()

func _on_gold_changed(_v: int) -> void:
	_refresh()

func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(120, 60)
	cam.zoom = Vector2(1.0, 1.0)
	add_child(cam)
	cam.make_current()

# ---------------- 场景 ----------------

func _build_scenery() -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-2000, -2000, 6000, 6000), Color(0.06, 0.16, 0.21))
	# 岛屿
	draw_circle(Vector2(0, 120), 420.0, Color(0.30, 0.34, 0.20))
	draw_arc(Vector2(0, 120), 420.0, 0, TAU, 40, Color(0.45, 0.50, 0.30), 4.0)
	# 建筑：数据驱动（只画已建成的，位置来自 TownLayout 槽位）
	var tp = load("res://scripts/ui/town_panel.gd")
	var layout: Resource = tp.layout_for(GameState.home_port_tier)
	if layout != null:
		for slot in layout.slots:
			var sid := String(slot.get("id", ""))
			var bdef: Resource = null
			for cand in tp.buildings_for_tier(GameState.home_port_tier):
				if String(cand.slot_id) == sid:
					bdef = cand
					break
			if bdef == null:
				continue
			if GameState.building_level(StringName(String(bdef.id))) <= 0:
				continue
			# 布局坐标（1600×900 画布）映射到城镇世界坐标
			var sx := float(slot.get("x", 0.0))
			var sy := float(slot.get("y", 0.0))
			var sw := float(slot.get("w", 220.0))
			var sh := float(slot.get("h", 140.0))
			var world := Vector2((sx / 1600.0 - 0.5) * 760.0, (sy / 900.0 - 0.5) * 520.0 + 120.0)
			var size := Vector2(sw * 0.42, sh * 0.42)
			var col := Color(0.55, 0.45, 0.30) if String(bdef.category) == "民生" else Color(0.45, 0.42, 0.34)
			_building(world, size, col, String(bdef.display_name))

func _building(center: Vector2, size: Vector2, col: Color, label: String) -> void:
	draw_rect(Rect2(center - size * 0.5, size), col)
	draw_rect(Rect2(center - size * 0.5, size), Color(0.15, 0.12, 0.08), false, 2.0)
	var f := ThemeDB.fallback_font
	draw_string(f, center + Vector2(-size.x * 0.5 + 6, size.y * 0.5 + 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.8, 0.65))

# ---------------- UI ----------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# 顶栏
	var top := PanelContainer.new()
	top.position = Vector2(20, 16)
	top.custom_minimum_size = Vector2(820, 46)
	top.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(top)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	top.add_child(status_label)

	# 左侧按钮
	var left := PanelContainer.new()
	left.position = Vector2(20, 80)
	left.custom_minimum_size = Vector2(220, 680)
	left.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(left)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	left.add_child(vb)
	# 按母港等级显示入口（未解锁的服务不出现，而不是灰掉）
	_action_button(vb, "修理船只", _do_repair)
	_action_button(vb, "市场交易", _toggle_market)
	_action_button(vb, "酒馆招募", _toggle_tavern)
	_action_button(vb, "任务板", _toggle_quests)
	if GameState.visit_has("yard"):
		_action_button(vb, "船厂与装备", _toggle_yard)
	if GameState.visit_has("build"):
		_action_button(vb, "基地建设", _toggle_build)
	if GameState.visit_has("reputation"):
		_action_button(vb, "声望与战功", _toggle_rep)

	_action_button(vb, "船员名单", _toggle_crew_panel)
	_action_button(vb, "装备强化", _toggle_gear)
	_action_button(vb, "舰船", _toggle_ship)
	_action_button(vb, "势力声望", _toggle_factions)
	_action_button(vb, "仓库", _toggle_store)
	if GameState.is_home_visit():
		_action_button(vb, "建造", _toggle_construct)
		_action_button(vb, "经济总览", _toggle_overview)
	else:
		_action_button(vb, "投资", _toggle_invest)
	if GameState.visit_has("bank"):
		_action_button(vb, "银行", _toggle_bank)
	if GameState.visit_has("black"):
		_action_button(vb, "黑市", _toggle_black)

	if GameState.is_home_visit():
		_action_button(vb, "出航", _set_sail)
	else:
		_action_button(vb, "离港", _leave_town)
	_action_button(vb, "存档", _toggle_save)
	_action_button(vb, "帮助", _toggle_help)
	_action_button(vb, "返回主菜单", func(): SceneRouter.goto(&"menu"))

	# 底部日志
	log_label = Label.new()
	log_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_label.position = Vector2(24, -70)
	log_label.add_theme_font_size_override("font_size", 16)
	log_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	root.add_child(log_label)

	# 市场面板
	market_root = PanelContainer.new()
	market_root.position = Vector2(16, 72)
	market_root.custom_minimum_size = Vector2(1568, 812)
	market_root.add_theme_stylebox_override("panel", _panel_style())
	market_root.visible = false
	root.add_child(market_root)
	market_list = VBoxContainer.new()
	market_list.add_theme_constant_override("separation", 6)
	market_root.add_child(market_list)

	# 船厂面板
	yard_root = PanelContainer.new()
	yard_root.position = Vector2(280, 60)
	yard_root.custom_minimum_size = Vector2(760, 560)
	yard_root.add_theme_stylebox_override("panel", _panel_style())
	yard_root.visible = false
	root.add_child(yard_root)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(730, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	yard_root.add_child(scroll)
	yard_list = VBoxContainer.new()
	yard_list.add_theme_constant_override("separation", 5)
	yard_list.custom_minimum_size = Vector2(710, 0)
	scroll.add_child(yard_list)

	# 酒馆面板
	tavern_root = PanelContainer.new()
	tavern_root.position = Vector2(280, 60)
	tavern_root.custom_minimum_size = Vector2(720, 520)
	tavern_root.add_theme_stylebox_override("panel", _panel_style())
	tavern_root.visible = false
	root.add_child(tavern_root)
	var tscroll := ScrollContainer.new()
	tscroll.custom_minimum_size = Vector2(690, 490)
	tscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tavern_root.add_child(tscroll)
	tavern_list = VBoxContainer.new()
	tavern_list.add_theme_constant_override("separation", 5)
	tavern_list.custom_minimum_size = Vector2(670, 0)
	tscroll.add_child(tavern_list)

	# 基地建设面板
	build_root = PanelContainer.new()
	build_root.position = Vector2(280, 60)
	build_root.custom_minimum_size = Vector2(760, 560)
	build_root.add_theme_stylebox_override("panel", _panel_style())
	build_root.visible = false
	root.add_child(build_root)
	var bscroll := ScrollContainer.new()
	bscroll.custom_minimum_size = Vector2(730, 520)
	bscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	build_root.add_child(bscroll)
	build_list = VBoxContainer.new()
	build_list.add_theme_constant_override("separation", 5)
	build_list.custom_minimum_size = Vector2(710, 0)
	bscroll.add_child(build_list)

	# 任务板
	quest_root = PanelContainer.new()
	quest_root.position = Vector2(280, 60)
	quest_root.custom_minimum_size = Vector2(760, 520)
	quest_root.add_theme_stylebox_override("panel", _panel_style())
	quest_root.visible = false
	root.add_child(quest_root)
	var qscroll := ScrollContainer.new()
	qscroll.custom_minimum_size = Vector2(730, 480)
	qscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	quest_root.add_child(qscroll)
	quest_list = VBoxContainer.new()
	quest_list.add_theme_constant_override("separation", 5)
	quest_list.custom_minimum_size = Vector2(710, 0)
	qscroll.add_child(quest_list)

	# 商品详情弹窗
	goods_root = PanelContainer.new()
	goods_root.position = Vector2(16, 72)
	goods_root.custom_minimum_size = Vector2(1568, 812)
	goods_root.add_theme_stylebox_override("panel", _panel_style())
	goods_root.visible = false
	root.add_child(goods_root)
	var gscroll := ScrollContainer.new()
	gscroll.custom_minimum_size = Vector2(1530, 780)
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	goods_root.add_child(gscroll)
	goods_list = VBoxContainer.new()
	goods_list.add_theme_constant_override("separation", 6)
	goods_list.custom_minimum_size = Vector2(1510, 0)
	gscroll.add_child(goods_list)

	# 船员名单面板
	crew_root = PanelContainer.new()
	crew_root.position = Vector2(16, 72)
	crew_root.custom_minimum_size = Vector2(1568, 812)
	crew_root.add_theme_stylebox_override("panel", _panel_style())
	crew_root.visible = false
	root.add_child(crew_root)
	var crscroll := ScrollContainer.new()
	crscroll.custom_minimum_size = Vector2(1530, 780)
	crscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	crew_root.add_child(crscroll)
	crew_list = VBoxContainer.new()
	crew_list.add_theme_constant_override("separation", 4)
	crew_list.custom_minimum_size = Vector2(1510, 0)
	crscroll.add_child(crew_list)

	# 装备强化面板
	gear_root = PanelContainer.new()
	gear_root.position = Vector2(16, 72)
	gear_root.custom_minimum_size = Vector2(1568, 812)
	gear_root.add_theme_stylebox_override("panel", _panel_style())
	gear_root.visible = false
	root.add_child(gear_root)
	var grscroll := ScrollContainer.new()
	grscroll.custom_minimum_size = Vector2(1530, 780)
	grscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gear_root.add_child(grscroll)
	gear_list = VBoxContainer.new()
	gear_list.add_theme_constant_override("separation", 4)
	gear_list.custom_minimum_size = Vector2(1510, 0)
	grscroll.add_child(gear_list)

	# 船只改装面板
	mod_root = PanelContainer.new()
	mod_root.position = Vector2(16, 72)
	mod_root.custom_minimum_size = Vector2(1568, 812)
	mod_root.add_theme_stylebox_override("panel", _panel_style())
	mod_root.visible = false
	root.add_child(mod_root)
	var mrscroll := ScrollContainer.new()
	mrscroll.custom_minimum_size = Vector2(1530, 780)
	mrscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mod_root.add_child(mrscroll)
	mod_list = VBoxContainer.new()
	mod_list.add_theme_constant_override("separation", 4)
	mod_list.custom_minimum_size = Vector2(1510, 0)
	mrscroll.add_child(mod_list)

	# 投资面板（岛屿）
	invest_root = PanelContainer.new()
	invest_root.position = Vector2(16, 72)
	invest_root.custom_minimum_size = Vector2(1568, 812)
	invest_root.add_theme_stylebox_override("panel", _panel_style())
	invest_root.visible = false
	root.add_child(invest_root)
	var invscroll := ScrollContainer.new()
	invscroll.custom_minimum_size = Vector2(1530, 780)
	invscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	invest_root.add_child(invscroll)
	invest_list = VBoxContainer.new()
	invest_list.add_theme_constant_override("separation", 6)
	invest_list.custom_minimum_size = Vector2(1510, 0)
	invscroll.add_child(invest_list)

	# 舰船面板
	ship_root = PanelContainer.new()
	ship_root.position = Vector2(16, 72)
	ship_root.custom_minimum_size = Vector2(1568, 812)
	var ship_style := StyleBoxFlat.new()
	ship_style.bg_color = Color(0.05, 0.10, 0.13)
	ship_style.set_corner_radius_all(4)
	ship_root.add_theme_stylebox_override("panel", ship_style)
	ship_root.visible = false
	root.add_child(ship_root)
	var ship_hb := HBoxContainer.new()
	ship_hb.add_theme_constant_override("separation", 10)
	ship_root.add_child(ship_hb)
	var ship_left := VBoxContainer.new()
	ship_left.add_theme_constant_override("separation", 6)
	ship_hb.add_child(ship_left)
	var ship_tabs := HBoxContainer.new()
	ship_tabs.add_theme_constant_override("separation", 8)
	ship_left.add_child(ship_tabs)
	for spec in [["gear", "装备"], ["crew", "人员"]]:
		var tb := Button.new()
		tb.text = String(spec[1])
		tb.custom_minimum_size = Vector2(110, 34)
		var key := String(spec[0])
		tb.pressed.connect(func():
			ship_tab = key
			_rebuild_ship_panel())
		ship_tabs.add_child(tb)
	ship_area = Control.new()
	ship_area.custom_minimum_size = ship_area_size
	ship_area.size = ship_area_size
	ship_left.add_child(ship_area)
	var ship_right := VBoxContainer.new()
	ship_right.add_theme_constant_override("separation", 6)
	ship_right.custom_minimum_size = Vector2(360, 0)
	ship_hb.add_child(ship_right)
	_yard_title_to(ship_right, "舰船属性")
	ship_stats_box = VBoxContainer.new()
	ship_stats_box.add_theme_constant_override("separation", 8)
	ship_right.add_child(ship_stats_box)
	var ship_swap := Button.new()
	ship_swap.text = "更换船只"
	ship_swap.custom_minimum_size = Vector2(160, 32)
	ship_swap.pressed.connect(func(): _open_ship_swap())
	ship_right.add_child(ship_swap)
	var ship_close := Button.new()
	ship_close.text = "关闭"
	ship_close.custom_minimum_size = Vector2(120, 30)
	ship_close.pressed.connect(func(): ship_root.visible = false)
	ship_right.add_child(ship_close)

	# 声望兑换所面板
	exch_root = PanelContainer.new()
	exch_root.position = Vector2(16, 72)
	exch_root.custom_minimum_size = Vector2(1568, 812)
	exch_root.add_theme_stylebox_override("panel", _panel_style())
	exch_root.visible = false
	root.add_child(exch_root)
	var exscroll := ScrollContainer.new()
	exscroll.custom_minimum_size = Vector2(1530, 780)
	exscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	exch_root.add_child(exscroll)
	exch_list = VBoxContainer.new()
	exch_list.add_theme_constant_override("separation", 8)
	exch_list.custom_minimum_size = Vector2(1510, 0)
	exscroll.add_child(exch_list)

	# 势力声望面板
	fac_root = PanelContainer.new()
	fac_root.position = Vector2(16, 72)
	fac_root.custom_minimum_size = Vector2(1568, 812)
	fac_root.add_theme_stylebox_override("panel", _panel_style())
	fac_root.visible = false
	root.add_child(fac_root)
	var facscroll := ScrollContainer.new()
	facscroll.custom_minimum_size = Vector2(1530, 780)
	facscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fac_root.add_child(facscroll)
	fac_list = VBoxContainer.new()
	fac_list.add_theme_constant_override("separation", 6)
	fac_list.custom_minimum_size = Vector2(1510, 0)
	facscroll.add_child(fac_list)

	# 仓库面板
	store_root = PanelContainer.new()
	store_root.position = Vector2(16, 72)
	store_root.custom_minimum_size = Vector2(1568, 812)
	store_root.add_theme_stylebox_override("panel", _panel_style())
	store_root.visible = false
	root.add_child(store_root)
	var stscroll := ScrollContainer.new()
	stscroll.custom_minimum_size = Vector2(1530, 780)
	stscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	store_root.add_child(stscroll)
	store_list = VBoxContainer.new()
	store_list.add_theme_constant_override("separation", 4)
	store_list.custom_minimum_size = Vector2(1510, 0)
	stscroll.add_child(store_list)

	# 建造面板（材料提交）
	construct_root = PanelContainer.new()
	construct_root.position = Vector2(16, 72)
	construct_root.custom_minimum_size = Vector2(1568, 812)
	construct_root.add_theme_stylebox_override("panel", _panel_style())
	construct_root.visible = false
	root.add_child(construct_root)
	var cscroll := ScrollContainer.new()
	cscroll.custom_minimum_size = Vector2(1530, 780)
	cscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	construct_root.add_child(cscroll)
	construct_list = VBoxContainer.new()
	construct_list.add_theme_constant_override("separation", 6)
	construct_list.custom_minimum_size = Vector2(1510, 0)
	cscroll.add_child(construct_list)

	# 经济总览面板
	overview_root = PanelContainer.new()
	overview_root.position = Vector2(300, 90)
	overview_root.custom_minimum_size = Vector2(720, 500)
	overview_root.add_theme_stylebox_override("panel", _panel_style())
	overview_root.visible = false
	root.add_child(overview_root)
	var oscroll := ScrollContainer.new()
	oscroll.custom_minimum_size = Vector2(690, 470)
	oscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overview_root.add_child(oscroll)
	overview_list = VBoxContainer.new()
	overview_list.add_theme_constant_override("separation", 6)
	overview_list.custom_minimum_size = Vector2(670, 0)
	oscroll.add_child(overview_list)

	# 财政面板
	finance_root = PanelContainer.new()
	finance_root.position = Vector2(300, 100)
	finance_root.custom_minimum_size = Vector2(700, 420)
	finance_root.add_theme_stylebox_override("panel", _panel_style())
	finance_root.visible = false
	root.add_child(finance_root)
	var fscroll := ScrollContainer.new()
	fscroll.custom_minimum_size = Vector2(670, 390)
	fscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	finance_root.add_child(fscroll)
	finance_list = VBoxContainer.new()
	finance_list.add_theme_constant_override("separation", 6)
	finance_list.custom_minimum_size = Vector2(650, 0)
	fscroll.add_child(finance_list)

	# 银行面板
	bank_root = PanelContainer.new()
	bank_root.position = Vector2(280, 80)
	bank_root.custom_minimum_size = Vector2(760, 460)
	bank_root.add_theme_stylebox_override("panel", _panel_style())
	bank_root.visible = false
	root.add_child(bank_root)
	var bkscroll := ScrollContainer.new()
	bkscroll.custom_minimum_size = Vector2(730, 420)
	bkscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bank_root.add_child(bkscroll)
	bank_list = VBoxContainer.new()
	bank_list.add_theme_constant_override("separation", 6)
	bank_list.custom_minimum_size = Vector2(710, 0)
	bkscroll.add_child(bank_list)

	# 黑市面板
	black_root = PanelContainer.new()
	black_root.position = Vector2(280, 80)
	black_root.custom_minimum_size = Vector2(760, 460)
	black_root.add_theme_stylebox_override("panel", _panel_style())
	black_root.visible = false
	root.add_child(black_root)
	var kscroll := ScrollContainer.new()
	kscroll.custom_minimum_size = Vector2(730, 420)
	kscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	black_root.add_child(kscroll)
	black_list = VBoxContainer.new()
	black_list.add_theme_constant_override("separation", 6)
	black_list.custom_minimum_size = Vector2(710, 0)
	kscroll.add_child(black_list)

	# 存档面板
	save_root = PanelContainer.new()
	save_root.position = Vector2(340, 140)
	save_root.custom_minimum_size = Vector2(740, 400)

	# 声望与战功
	rep_root = PanelContainer.new()
	rep_root.position = Vector2(280, 60)
	rep_root.custom_minimum_size = Vector2(760, 560)
	rep_root.add_theme_stylebox_override("panel", _panel_style())
	rep_root.visible = false
	root.add_child(rep_root)
	rep_list = VBoxContainer.new()
	rep_list.add_theme_constant_override("separation", 5)
	rep_root.add_child(rep_list)

	# 帮助
	help_root = PanelContainer.new()
	help_root.position = Vector2(300, 80)
	help_root.custom_minimum_size = Vector2(720, 520)
	help_root.add_theme_stylebox_override("panel", _panel_style())
	help_root.visible = false
	root.add_child(help_root)
	help_list = VBoxContainer.new()
	help_list.add_theme_constant_override("separation", 5)
	help_root.add_child(help_list)

	# 通关结算
	victory_root = PanelContainer.new()
	victory_root.position = Vector2(380, 160)
	victory_root.custom_minimum_size = Vector2(620, 380)
	victory_root.add_theme_stylebox_override("panel", _panel_style())
	victory_root.visible = false
	root.add_child(victory_root)
	save_root.add_theme_stylebox_override("panel", _panel_style())
	save_root.visible = false
	root.add_child(save_root)
	save_list = VBoxContainer.new()
	save_list.add_theme_constant_override("separation", 6)
	save_root.add_child(save_list)

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.09, 0.12, 0.97)
	s.border_color = Color(0.55, 0.45, 0.2, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func _action_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(196, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

# ---------------- 逻辑 ----------------

func _sync_ship_state() -> void:
	GameState.ensure_ship()

func _refresh() -> void:
	var def := GameState.ship_def()
	var st: Dictionary = GameState.stats()
	var hull_max := float(st.get("hull_max", 400.0))
	var hull := GameState.hull_hp if GameState.hull_hp >= 0.0 else hull_max
	status_label.text = "%s · %s·%s · 金币 %d · 战功 %d · 船体 %.0f/%.0f · 货舱 %.0f/%.0f · %s" % [
		GameState.visit_port_name(),
		def.display_name, String(st.get("variant_name", "")), GameState.gold, GameState.commendation,
		hull, hull_max, GameState.cargo_used(), float(GameState.cargo_capacity()), TimeService.date_text(),
	]

func _log(text: String) -> void:
	log_label.text = text
	_log_timer = 4.0

func _repair_cost() -> int:
	var hull_max := GameState.hull_max()
	var hull := GameState.hull_hp if GameState.hull_hp >= 0.0 else hull_max
	var per: float = float(DataRegistry.balance_dict.get("repair_per_hull", 0.25))
	var cost := (hull_max - hull) * per
	cost += (1.0 - GameState.sail_pct) * 300.0
	cost += (1.0 - GameState.rudder_pct) * 200.0
	cost += (1.0 - GameState.crew_pct) * 150.0
	cost *= (1.0 - GameState.repair_discount())
	return int(ceil(cost))

func _do_repair() -> void:
	var cost := _repair_cost()
	if cost <= 0:
		_log("船只状况良好，无需修理")
		return
	if GameState.gold < cost:
		_log("金币不足，修理需要 %d 金" % cost)
		return
	GameState.add_gold(-cost)
	GameState.hull_hp = GameState.hull_max()
	GameState.sail_pct = 1.0
	GameState.rudder_pct = 1.0
	GameState.crew_pct = 1.0
	_log("修理完成，花费 %d 金" % cost)
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if goods_root != null and goods_root.visible:
				goods_root.visible = false
				get_viewport().set_input_as_handled()
				return
			if _any_panel_open():
				_close_all_panels()
				get_viewport().set_input_as_handled()

func _toggle_market() -> void:
	if market_root.visible:
		market_root.visible = false
		return
	yard_root.visible = false
	build_root.visible = false
	tavern_root.visible = false
	_rebuild_market()
	market_root.visible = true

var market_target := "ship"   # ship = 装船，warehouse = 存仓
var market_tab := "local"     # local = 本地市场，world = 世界市场
var market_cat := "food"      # 商品大类页签，默认食物
var expanded_cid: StringName = &""   # 展开明细的商品
var bank_root: PanelContainer = null
var bank_list: VBoxContainer = null
var black_root: PanelContainer = null
var black_list: VBoxContainer = null

func _toggle_market_target(t: String) -> void:
	market_target = t
	_rebuild_market()

func _rebuild_market() -> void:
	for c in market_list.get_children():
		market_list.remove_child(c)
		c.queue_free()
	var port: Resource = DataRegistry.get_port(_pid())
	var max_stock := GameState.visit_port_max_stock()
	var head := Label.new()
	head.text = "市场行情（每周库存会向满值回归）"
	head.add_theme_font_size_override("font_size", 18)
	market_list.add_child(head)

	# 本地市场 / 世界市场 页签
	var mtabs := HBoxContainer.new()
	mtabs.add_theme_constant_override("separation", 8)
	market_list.add_child(mtabs)
	var m_local := Button.new()
	m_local.text = "本地市场"
	m_local.custom_minimum_size = Vector2(120, 32)
	m_local.modulate = Color(1.0, 0.92, 0.6) if market_tab == "local" else Color(1, 1, 1)
	m_local.pressed.connect(func(): market_tab = "local"; _rebuild_market())
	mtabs.add_child(m_local)
	var m_world := Button.new()
	m_world.text = "世界市场"
	m_world.custom_minimum_size = Vector2(120, 32)
	m_world.modulate = Color(1.0, 0.92, 0.6) if market_tab == "world" else Color(1, 1, 1)
	m_world.pressed.connect(func(): market_tab = "world"; _rebuild_market())
	mtabs.add_child(m_world)
	var m_ev := Button.new()
	m_ev.text = "市场事件"
	m_ev.custom_minimum_size = Vector2(120, 32)
	m_ev.modulate = Color(1.0, 0.92, 0.6) if market_tab == "events" else Color(1, 1, 1)
	m_ev.pressed.connect(func(): market_tab = "events"; _rebuild_market())
	mtabs.add_child(m_ev)

	if market_tab == "world":
		_rebuild_world_market()
		return
	if market_tab == "events":
		_rebuild_events_tab()
		return

	# 商品大类页签
	var catrow := HBoxContainer.new()
	catrow.add_theme_constant_override("separation", 8)
	market_list.add_child(catrow)
	for cat in ["food", "raw", "consumer", "military", "precious"]:
		var cb := Button.new()
		cb.text = String(GameState.CATEGORY_NAMES.get(cat, cat))
		cb.custom_minimum_size = Vector2(120, 30)
		cb.modulate = Color(1.0, 0.92, 0.6) if market_cat == cat else Color(1, 1, 1)
		var cv := String(cat)
		cb.pressed.connect(func(): market_cat = cv; _rebuild_market())
		catrow.add_child(cb)
	# 表头
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	market_list.add_child(head_row)
	for spec in [["商品", 150], ["买价", 120], ["卖价", 120], ["周涨跌", 160],
			["库存", 130], ["船上", 120], ["仓库", 120]]:
		head_row.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))

	for id in GameState.commodities_of(market_cat):
		var c: Resource = DataRegistry.get_commodity(id)
		if c == null:
			continue
		var stock := GameState.ensure_stock(_pid(), id, max_stock)
		var demand := 1.0
		var production := 1.0
		if port != null:
			demand = float(port.demand.get(String(id), 1.0))
			production = float(port.production.get(String(id), 1.0))
		var mod := GameState.price_modifier(String(_pid()), id)
		var rep_disc := GameState.rep_discount()
		var bp := int(round(float(MarketModel.buy_price(c.base_price, stock, max_stock, demand))
			* mod * (1.0 - rep_disc)))
		var sp := int(round(float(MarketModel.sell_price(c.base_price, stock, max_stock, production))
			* (1.0 + GameState.sell_bonus()) * mod))
		var chg := GameState.price_change_pct(String(_pid()), id)
		var arrow := "→"
		if chg > 0.005:
			arrow = "↑+%d%%" % int(round(chg * 100.0))
		elif chg < -0.005:
			arrow = "↓%d%%" % int(round(chg * 100.0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		market_list.add_child(row)
		var have := int(GameState.cargo.get(id, 0))
		var in_wh := int(GameState.warehouse.get(id, 0))
		row.add_child(_cell_box(c.display_name, 150))
		row.add_child(_cell_box(str(bp), 120))
		row.add_child(_cell_box(str(sp), 120))
		var chg_text := "—"
		var chg_col := Color(0.55, 0.6, 0.6)
		if GameState.has_price_history(String(_pid()), id):
			if absf(chg) < 0.005:
				chg_text = "持平"
			elif chg > 0.0:
				# 上涨用红色（与中式行情一致）
				chg_text = "↑%d%%" % int(round(chg * 100.0))
				chg_col = Color(0.92, 0.45, 0.42)
			else:
				# 下跌用绿色
				chg_text = "↓%d%%" % int(round(chg * 100.0))
				chg_col = Color(0.45, 0.85, 0.55)
		row.add_child(_cell_box(chg_text, 160, chg_col))
		row.add_child(_cell_box(str(stock), 130))
		row.add_child(_cell_box(str(have), 120))
		row.add_child(_cell_box(str(in_wh), 120))
		var b_trade := Button.new()
		b_trade.text = "交易"
		b_trade.custom_minimum_size = Vector2(150, 30)
		var cid_t: StringName = id
		b_trade.pressed.connect(func(): _open_goods(cid_t))
		row.add_child(b_trade)
	_add_market_metrics(String(_pid()))

	# 船上货舱汇总：买的东西到底装在哪儿
	var sep := HSeparator.new()
	market_list.add_child(sep)
	var hold_head := Label.new()
	hold_head.text = "我船货舱  %.0f / %.0f" % [GameState.cargo_used(), float(GameState.cargo_capacity())]
	hold_head.add_theme_font_size_override("font_size", 17)
	hold_head.add_theme_color_override("font_color", Color(0.85, 0.78, 0.5))
	market_list.add_child(hold_head)
	var any := false
	for id in [&"grain", &"timber", &"rum", &"spice"]:
		var have := int(GameState.cargo.get(id, 0))
		if have <= 0:
			continue
		any = true
		var cc: Resource = DataRegistry.get_commodity(id)
		var line := Label.new()
		line.text = "　%s × %d" % [String(cc.display_name), have]
		line.add_theme_font_size_override("font_size", 15)
		market_list.add_child(line)
	if not any:
		var empty := Label.new()
		empty.text = "　（空载）"
		empty.add_theme_font_size_override("font_size", 15)
		market_list.add_child(empty)
	var wh_head := Label.new()
	wh_head.text = "港口仓库  %.0f / %.0f" % [GameState.warehouse_used(), float(GameState.warehouse_capacity())]
	wh_head.add_theme_font_size_override("font_size", 17)
	wh_head.add_theme_color_override("font_color", Color(0.72, 0.80, 0.86))
	market_list.add_child(wh_head)
	var wh_any := false
	for id in [&"grain", &"timber", &"rum", &"spice"]:
		var have_w := int(GameState.warehouse.get(id, 0))
		if have_w <= 0:
			continue
		wh_any = true
		var cw: Resource = DataRegistry.get_commodity(id)
		var lw := Label.new()
		lw.text = "　%s × %d" % [String(cw.display_name), have_w]
		lw.add_theme_font_size_override("font_size", 15)
		market_list.add_child(lw)
	if not wh_any:
		var empty_w := Label.new()
		empty_w.text = "　（空）"
		empty_w.add_theme_font_size_override("font_size", 15)
		market_list.add_child(empty_w)
	var tip := Label.new()
	tip.text = "「装船」时买到的货进船仓，「存仓」时进港口仓库；卖出同理。"
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
	market_list.add_child(tip)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 34)
	close.pressed.connect(func(): market_root.visible = false)
	market_list.add_child(close)

## 船 → 仓 转移
func _move_to_warehouse(cid: StringName) -> void:
	var c: Resource = DataRegistry.get_commodity(cid)
	var have := int(GameState.cargo.get(cid, 0))
	if have <= 0:
		_log("船上没有该商品")
		return
	if GameState.warehouse_free() < float(c.volume):
		_log("仓库空间不足")
		return
	var n := mini(10, mini(have, int(floor(GameState.warehouse_free() / float(c.volume)))))
	if n <= 0:
		return
	GameState.remove_cargo(cid, n)
	GameState.warehouse_add(cid, n)
	_log("已移入仓库：%s × %d" % [c.display_name, n])
	_rebuild_market()
	_refresh()

## 仓 → 船 转移
func _move_to_ship(cid: StringName) -> void:
	var c: Resource = DataRegistry.get_commodity(cid)
	var have := int(GameState.warehouse.get(cid, 0))
	if have <= 0:
		_log("仓库里没有该商品")
		return
	if GameState.cargo_free() < float(c.volume):
		_log("货舱空间不足")
		return
	var n := mini(10, mini(have, int(floor(GameState.cargo_free() / float(c.volume)))))
	if n <= 0:
		return
	GameState.warehouse_remove(cid, n)
	GameState.add_cargo(cid, n)
	_log("已装上船：%s × %d" % [c.display_name, n])
	_rebuild_market()
	_refresh()

## 港口 id → 显示名
func _port_display(key: String) -> String:
	if key == String(_pid()):
		return "翡翠港"
	var pd: Resource = DataRegistry.get_port(StringName(key))
	if pd != null:
		return String(pd.display_name)
	if GameState.port_registry.has(key):
		return String(GameState.port_registry[key].get("name", key))
	return key

## 市场事件页签
func _rebuild_events_tab() -> void:
	var tip := Label.new()
	tip.text = "本周影响市场的事件（决定价格波动的成因）"
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
	market_list.add_child(tip)
	if GameState.market_events.is_empty():
		market_list.add_child(_lbl("　（本周没有市场事件）", 400, Color(0.55, 0.6, 0.6)))
		return
	var ehead := HBoxContainer.new()
	ehead.add_theme_constant_override("separation", 12)
	market_list.add_child(ehead)
	for spec in [["港口", 180], ["事件", 120], ["影响商品", 110], ["影响幅度", 260], ["剩余", 100]]:
		ehead.add_child(_cell(String(spec[0]), int(spec[1]), Color(0.62, 0.72, 0.78)))
	market_list.add_child(HSeparator.new())
	for e in GameState.market_events:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		market_list.add_child(hb)
		hb.add_child(_cell(_port_display(String(e.get("port", ""))), 180))
		hb.add_child(_cell(String(e.get("name", "")), 120, Color(0.9, 0.82, 0.45)))
		var tgt := String(e.get("target", ""))
		hb.add_child(_cell("全部" if tgt == "" else tgt, 110))
		hb.add_child(_cell(String(e.get("desc", "")), 260, Color(0.8, 0.85, 0.7)))
		hb.add_child(_cell("剩 %d 周" % int(e.get("weeks", 0)), 100))

## 带边框的表格单元格
func _cell_box(text: String, width: int, col: Color = Color(0.86, 0.88, 0.86),
		header: bool = false) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.18, 0.19) if header else Color(0.09, 0.12, 0.13)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.28, 0.36, 0.38)
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(width, 30)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	pc.add_child(l)
	return pc

## 表格单元格
func _cell(text: String, width: int, col: Color = Color(0.86, 0.88, 0.86)) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	return l

## 展开/收起价格明细
func _toggle_detail(cid: StringName) -> void:
	expanded_cid = &"" if expanded_cid == cid else cid
	_rebuild_market()

## 价格明细区块
func _add_detail_block(cid: StringName, base_price: int, stock: int, max_stock: int, final_price: int) -> void:
	var ex = load("res://scripts/systems/econ_explain.gd")
	var pk := String(_pid())
	var me = load("res://scripts/systems/market_events.gd")
	var info: Dictionary = ex.price_breakdown(pk, cid, base_price, stock, max_stock,
		float(me.effect_at(GameState.market_events, pk, cid)),
		GameState.price_drift_of(pk, cid))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	market_list.add_child(box)
	for st in info.get("steps", []):
		var hl := HBoxContainer.new()
		hl.add_theme_constant_override("separation", 10)
		box.add_child(hl)
		hl.add_child(_cell("　　" + String(st.get("label", "")), 150, Color(0.7, 0.78, 0.8)))
		var v := int(st.get("value", 0))
		var sgn := "+%d" % v if v >= 0 else str(v)
		hl.add_child(_cell(sgn, 70, Color(0.9, 0.85, 0.6)))
		hl.add_child(_cell(String(st.get("note", "")), 380, Color(0.62, 0.7, 0.66)))
	var total := HBoxContainer.new()
	total.add_theme_constant_override("separation", 10)
	box.add_child(total)
	total.add_child(_cell("　　= 最终买价", 150, Color(0.85, 0.88, 0.6)))
	total.add_child(_cell(str(final_price), 70, Color(0.95, 0.88, 0.5)))

## 本周市场指标行
func _add_market_metrics(pk: String) -> void:
	var sep := HSeparator.new()
	market_list.add_child(sep)
	var title := Label.new()
	title.text = "本周市场指标"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.62, 0.8, 0.7))
	market_list.add_child(title)
	var em = load("res://scripts/systems/econ_math.gd")
	var parts: Array = []
	for cid in GameState.commodities_of(market_cat):
		var c: Resource = DataRegistry.get_commodity(cid)
		if c == null:
			continue
		var max_stock := GameState.visit_port_max_stock()
		var stock := GameState.ensure_stock(_pid(), cid, max_stock)
		var ratio := clampf(float(stock) / float(max_stock), 0.0, 1.0)
		parts.append("%s 弹性 %.2f（库存 %d%%）" % [String(c.display_name), em.piecewise_elasticity(ratio),
			int(ratio * 100.0)])
	market_list.add_child(_cell("　　" + "　｜　".join(parts), 1400, Color(0.72, 0.8, 0.76)))
	var line2 := "　　回归速度 25%%/周　｜　单周涨跌上限 ±15%%　｜　生效事件 %d 条" % GameState.market_events.size()
	market_list.add_child(_cell(line2, 1400, Color(0.72, 0.8, 0.76)))
	var line3 := "　　交叉弹性传导阈值 ±%d%%：涨跌幅超过该值才会影响关联商品（上限 ±%d%%）" % [
		int(GameState.CROSS_THRESHOLD * 100.0), int(GameState.CROSS_CAP * 100.0)]
	market_list.add_child(_cell(line3, 1400, Color(0.62, 0.7, 0.66)))
	market_list.add_child(_cell("　　声望折扣：%d%%（%s）" % [int(GameState.rep_discount() * 100.0),
		GameState.rep_discount_name()], 1400, Color(0.62, 0.7, 0.66)))
	market_list.add_child(_cell("　　关联：朗姆酒↔香料（互补 0.4）　｜　谷物→朗姆酒（替代 -0.3）　｜　木材↔铁矿（互补 0.2）",
		1400, Color(0.62, 0.7, 0.66)))

## 世界市场：跨港情报页（不参与交易）
func _rebuild_world_market() -> void:
	var note := Label.new()
	note.text = "跨港情报：港口 / 海域 / 距离 / 商品买价。世界市场不成交，请回本地市场买卖。"
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
	market_list.add_child(note)
	var catrow2 := HBoxContainer.new()
	catrow2.add_theme_constant_override("separation", 8)
	market_list.add_child(catrow2)
	for cat in ["food", "raw", "consumer", "military", "precious"]:
		var cb2 := Button.new()
		cb2.text = String(GameState.CATEGORY_NAMES.get(cat, cat))
		cb2.custom_minimum_size = Vector2(110, 28)
		cb2.modulate = Color(1.0, 0.92, 0.6) if market_cat == cat else Color(1, 1, 1)
		var cv2 := String(cat)
		cb2.pressed.connect(func(): market_cat = cv2; _rebuild_market())
		catrow2.add_child(cb2)
	var cur_map := GameState.current_map
	var keys: Array = GameState.port_registry.keys()
	if keys.is_empty():
		market_list.add_child(_lbl("　（还没有探索过其他港口）", 400, Color(0.55, 0.6, 0.6)))
		return
	for k in keys:
		var meta: Dictionary = GameState.port_registry[k]
		var pname := String(meta.get("name", k))
		var pmap := int(meta.get("map", 1))
		var ptier := int(meta.get("tier", 1))
		var dist := absi(pmap - cur_map)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		market_list.add_child(hb)
		hb.add_child(_lbl("%s · %s" % [pname, GameState.port_name(ptier)], 220))
		hb.add_child(_lbl("第 %d 图 · 距 %d" % [pmap, dist], 130, Color(0.8, 0.85, 0.9)))
		var stock_cap := int(TIER_STOCK_REF.get(ptier, 40))
		var parts: Array = []
		for cid in GameState.commodities_of(market_cat):
			var c: Resource = DataRegistry.get_commodity(cid)
			if c == null:
				continue
			var st := GameState.ensure_stock(StringName(k), cid, stock_cap)
			if st <= 0:
				continue
			var bp := MarketModel.buy_price(int(c.base_price), st, stock_cap, 1.0)
			parts.append("%s %d" % [String(c.display_name), bp])
		hb.add_child(_lbl(" / ".join(parts) if not parts.is_empty() else "（无货）", 340,
			Color(0.82, 0.86, 0.7)))
		# 边际提示：以谷物为例，按货舱余量与两地差价估算
		var em2 = load("res://scripts/systems/econ_math.gd")
		var local_buy := 0
		var there_buy := 0
		var cg: Resource = DataRegistry.get_commodity(&"grain")
		if cg != null:
			var lstock := GameState.ensure_stock(_pid(), &"grain", 400)
			local_buy = int(round(float(MarketModel.buy_price(cg.base_price, lstock, 400, 1.0))
				* GameState.price_modifier(String(_pid()), &"grain")))
			var tstock := GameState.ensure_stock(StringName(k), &"grain", stock_cap)
			there_buy = int(round(float(MarketModel.sell_price(cg.base_price, tstock, stock_cap, 1.0))
				* GameState.price_modifier(String(k), &"grain")))
		var cap_left: float = GameState.cargo_free()
		var mt: Dictionary = em2.marginal_trade(local_buy, there_buy, cap_left, float(cg.volume), 999999)
		var mtxt := "—"
		var mcol := Color(0.6, 0.65, 0.65)
		match String(mt.get("reason", "")):
			"ok":
				mtxt = "还能吃进 %d 件" % int(mt.get("count", 0))
				mcol = Color(0.5, 0.88, 0.6)
			"capacity":
				mtxt = "货舱已满"
			"unprofitable":
				mtxt = "不划算"
				mcol = Color(0.9, 0.55, 0.5)
			_:
				mtxt = "无可比价"
		hb.add_child(_lbl(mtxt, 180, mcol))

const TIER_STOCK_REF := {1: 40, 2: 90, 3: 160}

func _buy(cid: StringName, amount: int, price: int) -> void:
	GameState.record_purchase(cid, amount, price * amount)
	var c: Resource = DataRegistry.get_commodity(cid)
	var total := price * amount
	if GameState.gold < total:
		_log("金币不足，需要 %d 金" % total)
		return
	var to_wh := market_target == "warehouse"
	var free_space := GameState.warehouse_free() if to_wh else GameState.cargo_free()
	if free_space < float(c.volume) * amount:
		_log("仓库空间不足" if to_wh else "货舱空间不足")
		return
	var port: Resource = DataRegistry.get_port(_pid())
	var stock := GameState.ensure_stock(_pid(), cid, GameState.visit_port_max_stock())
	if stock < amount:
		_log("该港库存不足")
		return
	GameState.add_gold(-total)
	GameState.set_stock(_pid(), cid, stock - amount)
	if to_wh:
		GameState.warehouse_add(cid, amount)
	else:
		GameState.add_cargo(cid, amount)
	_log("买入 %d %s（%s），花费 %d 金" % [amount, c.display_name,
		"存入仓库" if to_wh else "装船", total])
	_rebuild_market()
	_refresh()

func _sell(cid: StringName, amount: int, price: int) -> void:
	GameState.record_sale(cid, amount, price * amount)
	var from_wh := market_target == "warehouse"
	var have := int(GameState.warehouse.get(cid, 0)) if from_wh else int(GameState.cargo.get(cid, 0))
	if have < amount:
		_log("仓库里没有足够的该商品" if from_wh else "货舱里没有足够的该商品")
		return
	var c: Resource = DataRegistry.get_commodity(cid)
	var port: Resource = DataRegistry.get_port(_pid())
	var stock := GameState.ensure_stock(_pid(), cid, GameState.visit_port_max_stock())
	if from_wh:
		GameState.warehouse_remove(cid, amount)
	else:
		GameState.remove_cargo(cid, amount)
	GameState.set_stock(_pid(), cid, stock + amount)
	# 关税：在非母港卖出按 5% 扣除
	var gross := price * amount
	var tax := 0
	if String(_pid()) != "jadehaven":
		tax = int(round(float(gross) * GameState.tariff_rate_for_port(_pid())))
		GameState.record_expense("关税", tax)
	GameState.add_gold(gross - tax)
	if tax > 0:
		_log("关税 %d（5%%）" % tax)
	var margin := maxi(0, gross - int(c.base_price) * amount)
	GameState.on_trade_profit(margin)
	_log("卖出 %d %s，得到 %d 金（利润 %d）" % [amount, c.display_name, price * amount, margin])
	_rebuild_market()
	_refresh()

# ---------------- 船厂 ----------------

func _toggle_yard() -> void:
	if yard_root.visible:
		yard_root.visible = false
		return
	market_root.visible = false
	tavern_root.visible = false
	build_root.visible = false
	_rebuild_yard()
	yard_root.visible = true

# ---------------- 声望 / 战功 / 帮助 / 通关 ----------------

func _close_all_panels() -> void:
	# 面板统一置前，避免被侧栏菜单遮挡
	for pname in FULL_PANELS:
		var p: Node = get(pname)
		if p != null and p is PanelContainer:
			p.visible = false

func _toggle_rep() -> void:
	if rep_root.visible:
		rep_root.visible = false
		return
	_close_all_panels()
	_rebuild_rep()
	rep_root.visible = true

func _buy_license_legal() -> void:
	var r: Dictionary = GameState.buy_license_legal(fac_current if fac_current != "youming" else "yunlan")
	if bool(r.get("ok", false)):
		_log("取得正规私掠许可证")
		_rebuild_rep()
		_refresh()
	else:
		_log(String(r.get("reason", "购买失败")))

func _rebuild_rep() -> void:
	for c in rep_list.get_children():
		rep_list.remove_child(c)
		c.queue_free()
	_yard_title_to(rep_list, "声望与战功 —— 战功 %d · 通缉度 %d" % [GameState.commendation, GameState.notoriety()])

	# 正规私掠许可证（声望交易）
	_yard_title_to(rep_list, "私掠许可证（声望交易）")
	if GameState.has_privateer_license:
		rep_list.add_child(_lbl("　已持有（%s）" % ("正规途径" if GameState.license_is_legal else "黑市途径"),
			400, Color(0.7, 0.9, 0.7)))
	else:
		var lhb := HBoxContainer.new()
		lhb.add_theme_constant_override("separation", 10)
		rep_list.add_child(lhb)
		lhb.add_child(_lbl("正规私掠证", 140))
		lhb.add_child(_lbl("需 %s 声望 51" % String(GameState.FACTION_V2_NAMES.get(fac_current, "云澜")), 220,
			Color(0.8, 0.85, 0.8)))
		var lprice := int(GameState.LEGAL_LICENSE_REP) * 2
		lhb.add_child(_lbl("%d 金" % lprice, 120, Color(0.9, 0.82, 0.45)))
		var lb := Button.new()
		lb.text = "购买"
		lb.custom_minimum_size = Vector2(80, 26)
		lb.disabled = GameState.faction_rep_of(fac_current) < 51 or GameState.gold < lprice
		lb.pressed.connect(func(): _buy_license_legal())
		lhb.add_child(lb)
		var hint := Label.new()
		hint.text = "　持有后劫掠敌对阵营商船不降海军声望"
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
		rep_list.add_child(hint)

	_yard_title_to(rep_list, "六国声望")
	var nhead := HBoxContainer.new()
	nhead.add_theme_constant_override("separation", 0)
	rep_list.add_child(nhead)
	for spec in [["国家", 160], ["声望", 140], ["关系", 120], ["说明", 360]]:
		nhead.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))
	for nation in GameState.NATIONS:
		var nrow := HBoxContainer.new()
		nrow.add_theme_constant_override("separation", 0)
		rep_list.add_child(nrow)
		var rel := GameState.nation_relation(nation)
		var rel_col := Color(0.55, 0.9, 0.6)
		if rel == "敌视" or rel == "冷淡":
			rel_col = Color(0.92, 0.55, 0.45)
		elif rel == "中立":
			rel_col = Color(0.85, 0.82, 0.6)
		nrow.add_child(_cell_box(String(GameState.NATION_NAMES.get(nation, nation)), 160))
		nrow.add_child(_cell_box(str(GameState.nation_rep_of(nation)), 140, Color(0.95, 0.9, 0.55)))
		nrow.add_child(_cell_box(rel, 120, rel_col))
		nrow.add_child(_cell_box("1.3.1 起用于港口归属与关税", 360, Color(0.66, 0.72, 0.7)))

	_yard_title_to(rep_list, "势力声望请在左侧「势力声望」面板查看")
	_yard_title_to(rep_list, "通缉度（>50 会被海军赏金猎人追捕）")
	var nb := Button.new()
	nb.text = "缴纳保释金 5000 金（通缉度 -20）"
	nb.disabled = GameState.gold < 5000 or GameState.notoriety() <= -100
	nb.custom_minimum_size = Vector2(320, 30)
	nb.pressed.connect(func(): _do_bail())
	rep_list.add_child(nb)

	_yard_title_to(rep_list, "战功商店")
	var shop := [
		["rep", "声望包（200 战功 → 海军声望 +100）"],
		["crew", "受勋船员（50 战功 → UR 船员）"],
		["gear", "独有装备（100 战功 → 随机未拥有的独有装备）"],
	]
	for item in shop:
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 8)
		rep_list.add_child(hb2)
		hb2.add_child(_lbl(String(item[1]), 420))
		var kind: String = String(item[0])
		var b2 := Button.new()
		b2.text = "兑换"
		b2.custom_minimum_size = Vector2(80, 26)
		b2.pressed.connect(func(): _do_spend(kind))
		hb2.add_child(b2)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 30)
	close.pressed.connect(func(): rep_root.visible = false)
	rep_list.add_child(close)

func _do_donate(fac: String) -> void:
	var res: Dictionary = GameState.donate(fac, 1000)
	if res.get("ok", false):
		_log("向%s捐赠 %d 金，声望 +%d" % [GameState.FACTION_NAMES.get(fac, fac), int(res.gold), int(res.rep)])
	else:
		_log(String(res.get("reason", "捐赠失败")))
	_rebuild_rep()
	_refresh()

func _do_bail() -> void:
	var res: Dictionary = GameState.post_bail(5000)
	if res.get("ok", false):
		_log("已缴纳保释金，当前通缉度 %d" % int(res.notoriety))
	else:
		_log(String(res.get("reason", "缴纳失败")))
	_rebuild_rep()
	_refresh()

func _do_spend(kind: String) -> void:
	var res: Dictionary = GameState.spend_commendation(kind)
	if res.get("ok", false):
		_log("兑换成功：%s" % String(res.get("text", "")))
	else:
		_log(String(res.get("reason", "兑换失败")))
	_rebuild_rep()
	_refresh()

func _toggle_help() -> void:
	if help_root.visible:
		help_root.visible = false
		return
	_close_all_panels()
	_rebuild_help()
	help_root.visible = true

func _rebuild_help() -> void:
	for c in help_list.get_children():
		help_list.remove_child(c)
		c.queue_free()
	_yard_title_to(help_list, "帮助 —— 操作与机制")
	var lines := [
		"【航行】W/S 调速，A/D 转舵，左键点海图自动航行",
		"【战斗】左键点敌船锁定，进入射程后自动开火，可换弹药",
		"　　　　实心弹打船体，链弹打帆，葡萄弹杀船员（为接舷铺路）",
		"【接舷】目标船体 ≤10% 时按钮亮起，跳帮成功可俘获整船",
		"【撤离】只有己方风帆与舵机都完好时才能脱离",
		"【航门】E 键：靠近母港航门返回、靠近前进航门进入下一图",
		"　　　　击败本图任意 Boss 才会开启下一张图的航门",
		"【时间】空格暂停，1/2/3 切换 1×/2×/4×；时间每周结算一次",
		"【经济】金币管日常，战功只从 Boss 掉落，用于兑换稀有物",
		"【声望】任务 / 捐赠 / 击杀敌对阵营可提升；>50 通缉度会被追捕",
		"【存档】进母港自动存档；母港「存档」面板可存 5 个手动档",
	]
	for l in lines:
		help_list.add_child(_lbl(String(l), 660, Color(0.82, 0.86, 0.82)))
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 30)
	close.pressed.connect(func(): help_root.visible = false)
	help_list.add_child(close)

func _show_victory_if_needed() -> void:
	if victory_shown or not GameState.game_cleared:
		return
	victory_shown = true
	for c in victory_root.get_children():
		victory_root.remove_child(c)
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	victory_root.add_child(vb)
	var t := Label.new()
	t.text = "★ 通关 ★"
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var body := Label.new()
	body.text = "你在王冠之海写下了自己的名字。\n\n击杀总数 %d · 击败 Boss %d\n金币 %d · 战功 %d\n\n航行仍在继续，海域永远向船长敞开。" % [
		GameState.stat_kills, GameState.stat_bosses, GameState.gold, GameState.commendation]
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(0.85, 0.88, 0.82))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(body)
	var b := Button.new()
	b.text = "继续航行"
	b.custom_minimum_size = Vector2(160, 34)
	b.pressed.connect(func(): victory_root.visible = false)
	vb.add_child(b)
	victory_root.visible = true

# ---------------- 交易所 ----------------


func _toggle_quests() -> void:
	if quest_root.visible:
		quest_root.visible = false
		return
	market_root.visible = false
	yard_root.visible = false
	tavern_root.visible = false
	build_root.visible = false
	if GameState.quests_available.is_empty():
		GameState.refresh_quests()
	_rebuild_quests()
	quest_root.visible = true

func _cancel_quest(index: int) -> void:
	if GameState.quest_cancel(index):
		_log("已放弃任务，它回到了任务板")
		_rebuild_quests()
		_refresh()

func _rebuild_quests() -> void:
	for c in quest_list.get_children():
		quest_list.remove_child(c)
		c.queue_free()
	_yard_title_to(quest_list, "任务板 —— 进行中 %d · 可接 %d · 通缉度 %d" % [
		GameState.quests_active.size(), GameState.quests_available.size(), GameState.notoriety()])

	_yard_title_to(quest_list, "进行中（可随时放弃，放弃后回到看板）")
	if GameState.quests_active.is_empty():
		quest_list.add_child(_lbl("　（没有进行中的任务）", 400, Color(0.5, 0.55, 0.55)))
	for i in range(GameState.quests_active.size()):
		var q: Dictionary = GameState.quests_active[i]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		quest_list.add_child(hb)
		hb.add_child(_lbl(String(q.get("title", "")), 340))
		hb.add_child(_lbl("%d / %d" % [int(q.get("progress", 0)), int(q.get("amount", 1))], 110,
			Color(0.75, 0.85, 0.6)))
		hb.add_child(_lbl("+%d 金" % int(q.get("reward_gold", 0)), 120, Color(0.9, 0.82, 0.45)))
		var qidx := i
		var cancel := Button.new()
		cancel.text = "放弃"
		cancel.custom_minimum_size = Vector2(76, 26)
		cancel.pressed.connect(func(): _cancel_quest(qidx))
		hb.add_child(cancel)

	_yard_title_to(quest_list, "可接任务（看板清空后于每周结算刷新 9 个）")
	if GameState.quests_available.is_empty():
		quest_list.add_child(_lbl("　（没有可接任务）", 400, Color(0.5, 0.55, 0.55)))
	for i in range(GameState.quests_available.size()):
		var q: Dictionary = GameState.quests_available[i]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		quest_list.add_child(hb)
		hb.add_child(_lbl(String(q.get("title", "")), 340))
		hb.add_child(_lbl("+%d 金 / +%d 经验" % [int(q.get("reward_gold", 0)), int(q.get("reward_xp", 0))],
			200, Color(0.9, 0.82, 0.45)))
		var idx := i
		var b := Button.new()
		b.text = "接受"
		b.custom_minimum_size = Vector2(80, 26)
		b.pressed.connect(func(): _accept_quest(idx))
		hb.add_child(b)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 32)
	close.pressed.connect(func(): quest_root.visible = false)
	quest_list.add_child(close)

func _accept_quest(idx: int) -> void:
	if GameState.quest_accept(idx):
		_log("已接受任务")
	else:
		_log("同时最多进行 3 个任务")
	_rebuild_quests()

func _toggle_build() -> void:
	if build_root.visible:
		build_root.visible = false
		return
	market_root.visible = false
	yard_root.visible = false
	tavern_root.visible = false
	_rebuild_build()
	build_root.visible = true

func _res_line() -> String:
	var r := GameState.resources
	return "木材 %d · 铁矿 %d · 粮食 %d · 硝石 %d" % [
		int(r.get("timber", 0)), int(r.get("iron", 0)),
		int(r.get("grain", 0)), int(r.get("saltpeter", 0)),
	]

func _start_parallel_upgrade(bid: StringName) -> void:
	var r: Dictionary = GameState.building_start_upgrade(bid)
	if bool(r.get("ok", false)):
		_log("开始升级，工期 2 周")
		_rebuild_build()
		_refresh()
		queue_redraw()
	else:
		_log(String(r.get("reason", "升级失败")))

func _rebuild_build() -> void:
	for c in build_list.get_children():
		build_list.remove_child(c)
		c.queue_free()
	_yard_title_to(build_list, "基地建设 —— " + _res_line())
	var prod: Dictionary = GameState.total_production()
	build_list.add_child(_lbl("每周产出：木材 +%d · 铁矿 +%d · 粮食 +%d · 硝石 +%d" % [
		int(prod.get("timber", 0)), int(prod.get("iron", 0)),
		int(prod.get("grain", 0)), int(prod.get("saltpeter", 0)),
	], 520, Color(0.6, 0.8, 0.65)))

	# 工坊生产
	var lv_ws := GameState.building_level(&"sailmaker")
	_yard_title_to(build_list, "工坊生产（每周上限 %d 批）" % maxi(1, lv_ws))
	var head_prod := HBoxContainer.new()
	head_prod.add_theme_constant_override("separation", 8)
	build_list.add_child(head_prod)
	for spec in [["产成品", 160], ["配方", 320], ["仓库成品", 120], ["状态", 160]]:
		head_prod.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))
	for cid3 in GameState.RECIPES.keys():
		var rec3: Dictionary = GameState.RECIPES[cid3]
		var cd3: Resource = DataRegistry.get_commodity(cid3)
		if cd3 == null:
			continue
		var in_parts: Array = []
		var can_make := true
		for m3 in rec3.get("in", {}).keys():
			var md3: Resource = DataRegistry.get_commodity(m3)
			var nm3: String = String(md3.display_name) if md3 != null else String(m3)
			var need3 := int(rec3["in"][m3])
			var have3 := int(GameState.warehouse.get(m3, 0))
			in_parts.append("%s×%d（有%d）" % [nm3, need3, have3])
			if have3 < need3:
				can_make = false
		var row3 := HBoxContainer.new()
		row3.add_theme_constant_override("separation", 8)
		build_list.add_child(row3)
		row3.add_child(_cell_box(String(cd3.display_name), 160))
		row3.add_child(_cell_box(" + ".join(in_parts), 320, Color(0.75, 0.8, 0.72)))
		row3.add_child(_cell_box(str(int(GameState.warehouse.get(cid3, 0))), 120))
		row3.add_child(_cell_box("可生产" if can_make else "原料不足", 160,
			Color(0.55, 0.9, 0.6) if can_make else Color(0.9, 0.55, 0.5)))

	# 并行升级（独立计时）
	_yard_title_to(build_list, "并行升级（每座独立计时）")
	var parallel_row := HBoxContainer.new()
	parallel_row.add_theme_constant_override("separation", 8)
	build_list.add_child(parallel_row)
	for bid2 in [&"drydock", &"warehouse", &"sawmill"]:
		var bd2: Resource = DataRegistry.get_building(bid2)
		if bd2 == null:
			continue
		var lv2 := GameState.building_level(bid2)
		var pb := Button.new()
		pb.text = "%s Lv%d → Lv%d" % [String(bd2.display_name), lv2, lv2 + 1]
		pb.custom_minimum_size = Vector2(200, 30)
		pb.disabled = lv2 >= int(bd2.max_level) or GameState.building_upgrades.has(bid2)
		var bidv: StringName = bid2
		pb.pressed.connect(func(): _start_parallel_upgrade(bidv))
		parallel_row.add_child(pb)

	if not GameState.build_queue.is_empty():
		_yard_title_to(build_list, "建造中")
		for q in GameState.build_queue:
			var bd: Resource = DataRegistry.get_building(StringName(q.get("id", "")))
			var nm: String = bd.display_name if bd != null else String(q.get("id", ""))
			build_list.add_child(_lbl("%s → Lv%d　剩余 %d 周" % [nm, int(q.get("target", 1)), int(q.get("weeks_left", 1))],
				460, Color(0.9, 0.85, 0.55)))

	_yard_title_to(build_list, "建筑（按槽位顺序）")
	var layout: Resource = load("res://scripts/ui/town_panel.gd").layout_for(GameState.home_port_tier)
	var ordered: Array = []
	for slot in layout.slots:
		for bdef in load("res://scripts/ui/town_panel.gd").buildings_for_tier(GameState.home_port_tier):
			if String(bdef.slot_id) == String(slot.get("id", "")):
				ordered.append(StringName(String(bdef.id)))
	var ids: Array = ordered if not ordered.is_empty() else DataRegistry.buildings.keys()
	for bid in ids:
		var b: Resource = DataRegistry.buildings[bid]
		var lv := GameState.building_level(bid)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		build_list.add_child(hb)
		hb.add_child(_lbl("%s  Lv%d/%d" % [b.display_name, lv, int(b.max_level)], 150,
			Color(0.9, 0.85, 0.7) if lv > 0 else Color(0.75, 0.75, 0.7)))
		hb.add_child(_lbl(String(b.effect_text), 260, Color(0.65, 0.72, 0.72)))
		if lv >= int(b.max_level):
			hb.add_child(_lbl("已满级", 260, Color(0.55, 0.75, 0.55)))
			continue
		var cost: Dictionary = b.cost_for(lv + 1)
		var txt := "%d 金 / 木 %d / 铁 %d / %d 周" % [
			int(cost.gold), int(cost.timber), int(cost.iron), int(cost.weeks)]
		var affordable: bool = GameState.has_resources(cost)
		hb.add_child(_lbl(txt, 250, Color(0.85, 0.82, 0.6) if affordable else Color(0.85, 0.5, 0.5)))
		var prog_txt := GameState.building_progress_text(StringName(bid))
		if prog_txt != "":
			hb.add_child(_lbl(prog_txt, 190, Color(0.95, 0.85, 0.5)))
		var bb := Button.new()
		var busy: bool = GameState.is_building(bid) or GameState.building_upgrades.has(StringName(bid))
		bb.text = "建造中" if busy else "升级"
		bb.disabled = busy or not affordable
		bb.custom_minimum_size = Vector2(80, 26)
		var target_id: StringName = StringName(bid)
		bb.pressed.connect(func(): _start_build(target_id))
		hb.add_child(bb)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 32)
	close.pressed.connect(func(): build_root.visible = false)
	build_list.add_child(close)

func _start_build(bid: StringName) -> void:
	if not GameState.start_build(bid):
		_log("材料或金币不足，或该建筑已在建造中")
		return
	var b: Resource = DataRegistry.get_building(bid)
	_log("开始建造 %s" % b.display_name)
	_rebuild_build()
	_refresh()

func _toggle_tavern() -> void:
	if tavern_root.visible:
		tavern_root.visible = false
		return
	market_root.visible = false
	yard_root.visible = false
	build_root.visible = false
	if GameState.tavern_pool.is_empty():
		GameState.refresh_tavern()
	_rebuild_tavern()
	tavern_root.visible = true

func _rebuild_tavern() -> void:
	for c in tavern_list.get_children():
		tavern_list.remove_child(c)
		c.queue_free()
	var slots := GameState.crew_slots()
	_yard_title_to(tavern_list, "酒馆 —— 上阵 %d/%d" % [GameState.crew_assigned.size(), slots])

	_yard_title_to(tavern_list, "名册")
	if GameState.crew_roster.is_empty():
		tavern_list.add_child(_lbl("（还没有招募任何船员）", 420, Color(0.45, 0.5, 0.5)))
	for c in GameState.crew_roster:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		tavern_list.add_child(hb)
		hb.add_child(_lbl(c.display_name, 80, Rarity.color(int(c.rarity))))
		hb.add_child(_lbl(String(CrewFactory.ROLE_NAMES.get(StringName(c.role), String(c.role))), 80))
		hb.add_child(_lbl(Rarity.name_of(int(c.rarity)), 70, Rarity.color(int(c.rarity))))
		hb.add_child(_lbl("技能 %d" % int(c.stat), 80))
		hb.add_child(_lbl("薪酬 %d/周" % int(c.wage), 110))
		var on_board: bool = GameState.crew_assigned.has(StringName(c.crew_id))
		var cid: StringName = StringName(c.crew_id)
		var b := Button.new()
		b.text = "下阵" if on_board else "上阵"
		b.custom_minimum_size = Vector2(70, 26)
		b.pressed.connect(func(): _toggle_crew(cid, on_board))
		hb.add_child(b)
		var bd := Button.new()
		bd.text = "解雇"
		bd.custom_minimum_size = Vector2(70, 26)
		bd.pressed.connect(func(): _dismiss_crew(cid))
		hb.add_child(bd)

	_yard_title_to(tavern_list, "招募（本周结算后刷新）")
	for c in GameState.tavern_pool:
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 8)
		tavern_list.add_child(hb2)
		hb2.add_child(_lbl(c.display_name, 80, Rarity.color(int(c.rarity))))
		hb2.add_child(_lbl(String(CrewFactory.ROLE_NAMES.get(StringName(c.role), String(c.role))), 80))
		hb2.add_child(_lbl(Rarity.name_of(int(c.rarity)), 70, Rarity.color(int(c.rarity))))
		hb2.add_child(_lbl("技能 %d" % int(c.stat), 80))
		hb2.add_child(_lbl("雇佣 %d 金" % int(c.hire_cost), 130, Color(0.9, 0.82, 0.45)))
		var cid2: StringName = StringName(c.crew_id)
		var bh := Button.new()
		bh.text = "雇佣"
		bh.custom_minimum_size = Vector2(80, 26)
		bh.pressed.connect(func(): _hire_crew(cid2))
		hb2.add_child(bh)

	var rb := Button.new()
	rb.text = "花 500 金重新张贴告示"
	rb.custom_minimum_size = Vector2(220, 30)
	rb.pressed.connect(func(): _refresh_tavern_paid())
	tavern_list.add_child(rb)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 32)
	close.pressed.connect(func(): tavern_root.visible = false)
	tavern_list.add_child(close)

func _yard_title_to(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.88, 0.76, 0.42))
	parent.add_child(l)

func _toggle_crew(cid: StringName, on_board: bool) -> void:
	if on_board:
		GameState.unassign_crew(cid)
		_log("船员已下阵")
	elif not GameState.assign_crew(cid):
		_log("岗位已满或船员不存在")
	else:
		_log("船员已上阵")
	_rebuild_tavern()
	_refresh()

func _dismiss_crew(cid: StringName) -> void:
	GameState.dismiss_crew(cid)
	_log("已解雇该船员")
	_rebuild_tavern()

## 升级按钮文案：满级显示当前等级，否则显示所需资源
# ---------------- 经济总览（0.19.4 分页表格） ----------------

var overview_tab := "week_pnl"
const OVERVIEW_TABS := [
	["ytd_bs", "年资产负债表"],
	["ytd_pl", "年利润表"],
	["week_pnl", "周利润表"],
	["last_bs", "上年资产负债表"],
	["last_pl", "上年利润表"],
	["last_week", "上周利润表"],
]

func _stock_value() -> Dictionary:
	var cargo_v := 0
	for cid in GameState.cargo.keys():
		var c: Resource = DataRegistry.get_commodity(cid)
		if c != null:
			cargo_v += int(c.base_price) * int(GameState.cargo[cid])
	var wh_v := 0
	for c2k in GameState.warehouse.keys():
		var c2: Resource = DataRegistry.get_commodity(c2k)
		if c2 != null:
			wh_v += int(c2.base_price) * int(GameState.warehouse[c2k])
	var gear_v := 0
	for g in GameState.gear_owned:
		var gd: Resource = DataRegistry.get_gear(g)
		if gd != null:
			gear_v += int(gd.price)
	var ship_v := 0
	for sh in GameState.ships_owned:
		if sh is Resource and sh.get("price") != null:
			ship_v += int(sh.get("price"))
	return {"cargo": cargo_v, "wh": wh_v, "gear": gear_v, "ship": ship_v,
		"total": cargo_v + wh_v + gear_v + ship_v}

func _overview_table(headers: Array, widths: Array, rows: Array) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	overview_list.add_child(hb)
	for i in range(headers.size()):
		hb.add_child(_cell_box(String(headers[i]), int(widths[i]), Color(0.62, 0.78, 0.85), true))
	for rw in rows:
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 0)
		overview_list.add_child(hr)
		for i2 in range(rw.size()):
			var col := Color(0.86, 0.88, 0.86)
			var txt := String(rw[i2])
			if txt.begins_with("+"):
				col = Color(0.92, 0.55, 0.5)
			elif txt.begins_with("-"):
				col = Color(0.5, 0.85, 0.6)
			hr.add_child(_cell_box(txt, int(widths[i2]), col))

# ---------------- 经济总览与财报（0.17 / 0.18） ----------------

var overview_root: PanelContainer = null
var overview_list: VBoxContainer = null

func _toggle_overview() -> void:
	if overview_root.visible:
		overview_root.visible = false
		return
	_rebuild_overview()
	overview_root.visible = true

const INC_KINDS := ["贸易", "战利品", "任务", "利息"]
const EXP_KINDS := ["采购", "维护", "关税", "利息", "建造"]

func _pl_rows(income: Dictionary, expense: Dictionary, note: String) -> Array:
	var rows: Array = []
	var inc_total := 0
	rows.append(["营业收入", "", "大类"])
	for k in INC_KINDS:
		var v := int(income.get(k, 0))
		inc_total += v
		rows.append(["　　" + k, str(v), note])
	for k2 in income.keys():
		if INC_KINDS.has(String(k2)):
			continue
		var v2 := int(income[k2])
		inc_total += v2
		rows.append(["　　" + String(k2), str(v2), note])
	rows.append(["收入合计", str(inc_total), "全部收入细类之和"])
	var exp_total := 0
	rows.append(["营业成本", "", "大类"])
	for k3 in EXP_KINDS:
		var v3 := int(expense.get(k3, 0))
		exp_total += v3
		rows.append(["　　" + k3, str(v3), note])
	for k4 in expense.keys():
		if EXP_KINDS.has(String(k4)):
			continue
		var v4 := int(expense[k4])
		exp_total += v4
		rows.append(["　　" + String(k4), str(v4), note])
	rows.append(["成本合计", str(exp_total), "全部成本细类之和"])
	var net := inc_total - exp_total
	rows.append(["净利润", ("+%d" % net) if net >= 0 else str(net), "收入合计 − 成本合计"])
	return rows

func _bs_rows(cash: int, deposit: int, cargo: int, wh: int, gear: int, ship: int, debt: int) -> Array:
	var assets := cash + deposit + cargo + wh + gear + ship
	var rows: Array = []
	rows.append(["资产", "", "大类"])
	rows.append(["　　现金", str(cash), "身上持有"])
	rows.append(["　　银行存款", str(deposit), "全城通存通取"])
	rows.append(["　　船舱货物", str(cargo), "按商品基础价"])
	rows.append(["　　港口仓库", str(wh), "按商品基础价"])
	rows.append(["　　装备", str(gear), "按装备基础价"])
	rows.append(["　　船只", str(ship), "按购入价（船员不计入）"])
	rows.append(["资产合计", str(assets), "全部资产细类之和"])
	rows.append(["负债", "", "大类"])
	rows.append(["　　未还贷款", str(debt), "本息合计"])
	rows.append(["负债合计", str(debt), "全部负债细类之和"])
	rows.append(["净资产", str(assets - debt), "资产合计 − 负债合计"])
	return rows

func _rebuild_overview() -> void:
	for c in overview_list.get_children():
		overview_list.remove_child(c)
		c.queue_free()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	overview_list.add_child(tabs)
	for t in OVERVIEW_TABS:
		var tb := Button.new()
		tb.text = String(t[1])
		tb.custom_minimum_size = Vector2(150, 32)
		tb.modulate = Color(1.0, 0.92, 0.6) if String(t[0]) == overview_tab else Color(1, 1, 1)
		var key := String(t[0])
		tb.pressed.connect(func(): overview_tab = key; _rebuild_overview())
		tabs.add_child(tb)
	var s: Dictionary = GameState.finance_summary()
	var up: Dictionary = GameState.weekly_upkeep()
	var sv: Dictionary = _stock_value()
	match overview_tab:
		"ytd_bs":
			_yard_title_to(overview_list, "年资产负债表")
			_overview_table(["项目", "金额", "说明"], [300, 220, 620], _bs_rows(
				GameState.gold, GameState.bank_deposited(),
				int(sv["cargo"]), int(sv["wh"]), int(sv["gear"]), int(sv["ship"]),
				GameState.loan_exposure()))
		"ytd_pl":
			_yard_title_to(overview_list, "年利润表")
			_overview_table(["项目", "金额", "说明"], [300, 220, 620],
				_pl_rows(s["income"], s["expense"], "本年累计"))
		"week_pnl":
			var week_exp: Dictionary = GameState.week_expense.duplicate()
			week_exp["维护"] = int(week_exp.get("维护", 0)) + int(up.get("total", 0))
			_yard_title_to(overview_list, "周利润表（本周）")
			_overview_table(["项目", "金额", "说明"], [300, 220, 620],
				_pl_rows(GameState.week_income, week_exp, "本周"))
		"last_bs":
			_yard_title_to(overview_list, "上年资产负债表")
			if GameState.reports.is_empty():
				overview_list.add_child(_lbl("　（还没有跨年，暂无上年数据）", 500, Color(0.55, 0.6, 0.6)))
			else:
				var r0: Dictionary = GameState.reports[GameState.reports.size() - 1]
				_overview_table(["项目", "金额", "说明"], [300, 220, 620], _bs_rows(
					int(r0.get("cash", 0)), int(r0.get("deposit", 0)),
					int(r0.get("cargo", 0)), 0, 0, int(r0.get("fleet", 0)),
					int(r0.get("debt", 0))))
		"last_pl":
			_yard_title_to(overview_list, "上年利润表")
			if GameState.reports.is_empty():
				overview_list.add_child(_lbl("　（还没有跨年，暂无上年数据）", 500, Color(0.55, 0.6, 0.6)))
			else:
				var r1: Dictionary = GameState.reports[GameState.reports.size() - 1]
				_overview_table(["项目", "金额", "说明"], [300, 220, 620],
					_pl_rows(r1.get("income", {}), r1.get("expense", {}), "上年累计"))
		"last_week":
			_yard_title_to(overview_list, "上周利润表")
			_overview_table(["项目", "金额", "说明"], [300, 220, 620],
				_pl_rows(GameState.last_week_income, GameState.last_week_expense, "上周"))

# ---------------- 商品详情弹窗（0.19.1） ----------------

var goods_root: PanelContainer = null
var goods_list: VBoxContainer = null
var goods_cid: StringName = &""
var goods_qty := 1
var goods_chart_index := 0
var goods_chart: Control = null
var goods_qty_edit: LineEdit = null
const CHART_NAMES := ["价格走势", "边际分析", "价格与库存", "弹性价格", "规模经济"]

func _open_goods(cid: StringName) -> void:
	goods_cid = cid
	goods_qty = 1
	goods_chart_index = 0
	_rebuild_goods()
	goods_root.visible = true

func _close_goods() -> void:
	goods_root.visible = false

func _rebuild_goods() -> void:
	for c in goods_list.get_children():
		goods_list.remove_child(c)
		c.queue_free()
	var c: Resource = DataRegistry.get_commodity(goods_cid)
	if c == null:
		return
	var port: Resource = DataRegistry.get_port(_pid())
	var port2: Resource = DataRegistry.get_port(_pid())
	var max_stock := int(port2.max_stock) if port2 != null else 800
	var stock := GameState.ensure_stock(_pid(), goods_cid, max_stock)
	var demand := 1.0
	if port != null:
		demand = float(port.demand.get(String(goods_cid), 1.0))
	var mod := GameState.price_modifier(String(_pid()), goods_cid)
	var bp := int(round(float(MarketModel.buy_price(c.base_price, stock, max_stock, demand))
		* mod * (1.0 - GameState.rep_discount())))
	var sp := int(round(float(MarketModel.sell_price(c.base_price, stock, max_stock, 1.0))
		* (1.0 + GameState.sell_bonus()) * mod))
	var have := int(GameState.cargo.get(goods_cid, 0)) + int(GameState.warehouse.get(goods_cid, 0))

	_yard_title_to(goods_list, "%s —— 买 %d / 卖 %d" % [String(c.display_name), bp, sp])
	# 图表切换
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	goods_list.add_child(tabs)
	for i in range(CHART_NAMES.size()):
		var tb := Button.new()
		tb.text = String(CHART_NAMES[i])
		tb.custom_minimum_size = Vector2(120, 30)
		tb.modulate = Color(1.0, 0.92, 0.6) if i == goods_chart_index else Color(1, 1, 1)
		var idx: int = i
		tb.pressed.connect(func(): goods_chart_index = idx; _rebuild_goods())
		tabs.add_child(tb)
	# 图表
	goods_chart = load("res://scripts/ui/econ_chart.gd").new()
	goods_chart.custom_minimum_size = Vector2(1400, 240)
	goods_list.add_child(goods_chart)
	goods_chart.setup(goods_chart_index, _chart_data(goods_cid, int(c.base_price), stock, max_stock), "")

	# 指标明细表（大指标 → 明细，每项一行并带计算式）
	var em0 = load("res://scripts/systems/econ_math.gd")
	var ratio: float = clampf(float(stock) / maxf(1.0, float(max_stock)), 0.0, 1.0)
	var e: float = float(em0.piecewise_elasticity(ratio))
	var eq: float = float(c.base_price) * (1.0 + e * (1.0 - ratio))
	var cur: float = eq * GameState.price_drift_of(String(_pid()), goods_cid)
	var dev: float = (cur - eq) / maxf(0.01, eq)
	var step_v: float = (eq - cur) * 0.25
	var opp: int = int(round(float(bp * goods_qty) * 0.001 * 8.0))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	goods_list.add_child(head)
	head.add_child(_cell_box("指标", 190, Color(0.62, 0.78, 0.85), true))
	head.add_child(_cell_box("计算结果", 240, Color(0.62, 0.78, 0.85), true))
	head.add_child(_cell_box("计算过程 / 说明", 900, Color(0.62, 0.78, 0.85), true))
	var etype := "富有弹性" if e >= 0.70 else ("单位弹性附近" if e >= 0.40 else "缺乏弹性")
	var rows: Array = [
		["【弹性】供给弹性", "%.2f（%s）" % [e, etype],
			"库存比例 %.2f → 分段函数(%s) = %.2f" % [ratio,
				"高库存" if ratio > 0.7 else ("低库存" if ratio < 0.3 else "中库存"), e]],
		["【均衡】均衡价", "%.1f" % eq,
			"基础价 %d × (1 + %.2f × (1 − %.2f)) = %.1f" % [int(c.base_price), e, ratio, eq]],
		["【均衡】当前价", "%.1f" % cur, "均衡价 %.1f × 漂移 %.3f = %.1f" % [
			eq, GameState.price_drift_of(String(_pid()), goods_cid), cur]],
		["【均衡】偏离度", "%+.1f%%" % (dev * 100.0), "(当前价 − 均衡价) ÷ 均衡价"],
		["【均衡】本周回归步长", "%+.2f" % step_v, "(均衡价 − 当前价) × 25%"],
		["【边际】买价 MC", "%d" % bp, "第 1 件买价（含声望折扣 %d%%）" % int(GameState.rep_discount() * 100.0)],
		["【边际】卖出价 MR", "%d" % sp, "本港卖出价（含卖出加成）"],
		["【边际】单件边际利润", "%+d" % (sp - bp), "MR − MC"],
		["【成本】本次采购", "%d" % (bp * goods_qty), "%d 件 × %d" % [goods_qty, bp]],
		["【成本】机会成本", "%d" % opp, "采购额 × 0.1%%/周 × 8 周"],
		["【成本】合计", "%d" % (bp * goods_qty + opp), "采购 + 机会成本"],
		["【定价】声望折扣", "%d%%（%s）" % [int(GameState.rep_discount() * 100.0), GameState.rep_discount_name()],
			"按最高阵营声望分档，只作用于买价"],
		["【税收】关税", "5%%（跨海域）", "卖出所得扣除，同海域不扣"],
	]
	for rw in rows:
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 0)
		goods_list.add_child(hr)
		hr.add_child(_cell_box(String(rw[0]), 190))
		hr.add_child(_cell_box(String(rw[1]), 240, Color(0.95, 0.9, 0.55)))
		hr.add_child(_cell_box(String(rw[2]), 900, Color(0.7, 0.78, 0.72)))

	# 数量控件
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 8)
	goods_list.add_child(qrow)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(44, 30)
	minus.pressed.connect(func(): _goods_set_qty(goods_qty - 1, stock, have))
	qrow.add_child(minus)
	goods_qty_edit = LineEdit.new()
	goods_qty_edit.text = str(goods_qty)
	goods_qty_edit.custom_minimum_size = Vector2(110, 30)
	goods_qty_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	goods_qty_edit.text_submitted.connect(func(_t): _goods_set_qty(int(_t), stock, have))
	goods_qty_edit.focus_exited.connect(func(): _goods_set_qty(int(goods_qty_edit.text), stock, have))
	qrow.add_child(goods_qty_edit)
	var plus := Button.new()
	plus.text = "＋"
	plus.custom_minimum_size = Vector2(44, 30)
	plus.pressed.connect(func(): _goods_set_qty(goods_qty + 1, stock, have))
	qrow.add_child(plus)
	qrow.add_child(_lbl("上限：买 %d / 卖 %d" % [stock, have], 300, Color(0.62, 0.7, 0.66)))

	# 买卖
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	goods_list.add_child(brow)
	var buy_btn := Button.new()
	buy_btn.text = "买入 %d" % goods_qty
	buy_btn.custom_minimum_size = Vector2(150, 34)
	buy_btn.disabled = stock <= 0 or GameState.gold < bp * goods_qty
	buy_btn.pressed.connect(func(): _goods_choose_storage(bp))
	brow.add_child(buy_btn)
	var sell_btn := Button.new()
	sell_btn.text = "卖出 %d" % goods_qty
	sell_btn.custom_minimum_size = Vector2(150, 34)
	sell_btn.disabled = have <= 0
	sell_btn.pressed.connect(func(): _sell(goods_cid, goods_qty, sp); _goods_set_qty(goods_qty, stock, have))
	brow.add_child(sell_btn)
	var close_b := Button.new()
	close_b.text = "关闭"
	close_b.custom_minimum_size = Vector2(100, 34)
	close_b.pressed.connect(_close_goods)
	brow.add_child(close_b)

func _goods_set_qty(v: int, stock: int, have: int) -> void:
	var cap := maxi(stock, have)
	if cap <= 0:
		cap = 1
	goods_qty = clampi(v, 1, cap)
	_rebuild_goods()

func _goods_choose_storage(price: int) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "存放位置"
	dlg.dialog_text = "买入 %d 件 %s：装船（货舱）还是存仓（港口仓库）？" % [goods_qty, String(goods_cid)]
	dlg.ok_button_text = "装船"
	dlg.add_button("存仓", true, "warehouse")
	add_child(dlg)
	dlg.confirmed.connect(func():
		_buy(goods_cid, goods_qty, price)
		dlg.queue_free()
		_rebuild_goods())
	dlg.custom_action.connect(func(action: StringName):
		if String(action) == "warehouse":
			GameState.record_purchase(goods_cid, goods_qty, price * goods_qty)
			GameState.add_gold(-price * goods_qty)
			GameState.warehouse[goods_cid] = int(GameState.warehouse.get(goods_cid, 0)) + goods_qty
			var port3: Resource = DataRegistry.get_port(_pid())
			var ms := int(port3.max_stock) if port3 != null else 800
			GameState.ensure_stock(_pid(), goods_cid, ms)
			GameState.port_stock[_pid()][goods_cid] = maxi(0, int(GameState.port_stock[_pid()][goods_cid]) - goods_qty)
			dlg.queue_free()
			_rebuild_goods())
	dlg.popup_centered()

func _chart_data(cid: StringName, base_price: int, stock: int, max_stock: int) -> Dictionary:
	var d := {}
	d["history"] = GameState.price_history_of(String(_pid()), cid)
	var em = load("res://scripts/systems/econ_math.gd")
	var mc: Array = []
	var steps := 40
	var per_step := maxf(1.0, float(stock) / float(steps))
	for i in range(0, steps + 1):
		var s := float(stock) - per_step * float(i)
		var r := clampf(maxf(0.0, s) / float(max_stock), 0.0, 1.0)
		mc.append(float(base_price) * (1.0 + em.piecewise_elasticity(r) * (1.0 - r)))
	d["mc"] = mc
	d["mr"] = float(MarketModel.sell_price(base_price, stock, max_stock, 1.0))
	# 价格-库存曲线：横轴库存量，纵轴买价
	var price_by_stock: Array = []
	for i in range(0, 41):
		var st2 := int(float(max_stock) * float(i) / 40.0)
		price_by_stock.append(float(base_price) * (1.0 + 0.55 * (1.0 - float(i) / 40.0)))
	d["price_by_stock"] = price_by_stock
	d["cur_stock"] = stock
	d["max_stock"] = max_stock
	d["eq_price"] = float(base_price) * (1.0 + 0.55 * (1.0 - clampf(float(stock) / float(max_stock), 0.0, 1.0)))
	var curve: Array = []
	for i in range(0, 41):
		var qq := 0.05 + float(i) / 40.0 * 2.0
		curve.append(float(base_price) * 1.2 / qq)
	d["curve"] = curve
	d["labels"] = ["渔村", "乡镇", "城市"]
	d["coefs"] = [1.20, 1.00, 0.85]
	d["vol"] = [40, 90, 160]
	return d

# ---------------- 船员 / 装备 / 改装面板（1.1.1） ----------------

var crew_root: PanelContainer = null
var crew_list: VBoxContainer = null
var gear_root: PanelContainer = null
var gear_list: VBoxContainer = null
var mod_root: PanelContainer = null
var mod_list: VBoxContainer = null

func _toggle_crew_panel() -> void:
	if crew_root.visible:
		crew_root.visible = false
		return
	_rebuild_crew_panel()
	crew_root.visible = true

func _rebuild_crew_panel() -> void:
	for c in crew_list.get_children():
		crew_list.remove_child(c)
		c.queue_free()
	_yard_title_to(crew_list, "船员名单 —— 在岗 %d 人" % GameState.crew_roster.size())
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	crew_list.add_child(head)
	for spec in [["姓名", 200], ["角色", 140], ["稀有度", 120], ["职级", 140], ["经验", 140], ["属性", 120]]:
		head.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))
	if GameState.crew_roster.is_empty():
		crew_list.add_child(_lbl("　（暂无船员，去酒馆招募）", 500, Color(0.55, 0.6, 0.6)))
		return
	for c in GameState.crew_roster:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		crew_list.add_child(row)
		var cid: StringName = c.crew_id
		row.add_child(_cell_box(String(c.display_name), 200))
		row.add_child(_cell_box(String(c.role), 140))
		row.add_child(_cell_box(str(int(c.rarity)), 120))
		row.add_child(_cell_box(GameState.crew_rank_name(cid), 140, Color(0.95, 0.9, 0.55)))
		row.add_child(_cell_box(str(int(GameState.crew_xp.get(cid, 0))), 140))
		row.add_child(_cell_box(str(int(c.stat)), 120))

func _toggle_gear() -> void:
	if gear_root.visible:
		gear_root.visible = false
		return
	_rebuild_gear()
	gear_root.visible = true

func _rebuild_gear() -> void:
	for c in gear_list.get_children():
		gear_list.remove_child(c)
		c.queue_free()
	_yard_title_to(gear_list, "装备强化与合成 —— 铁矿 %d" % int(GameState.warehouse.get(&"iron_ore", 0)))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	gear_list.add_child(head)
	for spec in [["装备", 260], ["部位", 140], ["稀有度", 120], ["强化", 100], ["操作", 260]]:
		head.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))
	if GameState.gear_owned.is_empty():
		gear_list.add_child(_lbl("　（暂无装备）", 400, Color(0.55, 0.6, 0.6)))
		return
	for gid in GameState.gear_owned:
		var gd: Resource = DataRegistry.get_gear(gid)
		if gd == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		gear_list.add_child(row)
		row.add_child(_cell_box(String(gd.display_name), 260))
		row.add_child(_cell_box(String(gd.slot), 140))
		row.add_child(_cell_box(str(int(gd.rarity)), 120))
		row.add_child(_cell_box("+%d" % GameState.gear_level_of(gid), 100, Color(0.95, 0.9, 0.55)))
		var op := PanelContainer.new()
		op.custom_minimum_size = Vector2(260, 30)
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 6)
		op.add_child(hb2)
		var up := Button.new()
		up.text = "强化"
		up.custom_minimum_size = Vector2(80, 26)
		var gid_v: StringName = gid
		up.pressed.connect(func(): _do_gear_upgrade(gid_v))
		hb2.add_child(up)
		var comb := Button.new()
		comb.text = "合成"
		comb.custom_minimum_size = Vector2(80, 26)
		var slot_v := StringName(gd.slot)
		var rar_v := int(gd.rarity)
		comb.pressed.connect(func(): _do_gear_combine(slot_v, rar_v))
		hb2.add_child(comb)
		row.add_child(op)

func _do_gear_upgrade(gid: StringName) -> void:
	var r: Dictionary = GameState.gear_upgrade(gid)
	if bool(r.get("ok", false)):
		_log("强化成功：+%d" % int(r.get("level", 0)))
		_rebuild_gear()
	else:
		_log(String(r.get("reason", "强化失败")))

func _do_gear_combine(slot: StringName, rarity: int) -> void:
	var r: Dictionary = GameState.gear_combine(slot, rarity)
	if bool(r.get("ok", false)):
		_log("合成成功")
		_rebuild_gear()
	else:
		_log(String(r.get("reason", "合成失败")))

func _toggle_mod() -> void:
	if mod_root.visible:
		mod_root.visible = false
		return
	_rebuild_mod()
	mod_root.visible = true

func _rebuild_mod() -> void:
	for c in mod_list.get_children():
		mod_list.remove_child(c)
		c.queue_free()
	_yard_title_to(mod_list, "船只改装 —— 现金 %d" % GameState.gold)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	mod_list.add_child(head)
	for spec in [["改装项", 260], ["等级", 120], ["当前加成", 220], ["下一级花费", 180], ["操作", 160]]:
		head.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))
	var sail_lv := int(GameState.ship_mods.get("sail_tier", 0))
	var can_lv := int(GameState.ship_mods.get("cannon_slots", 0))
	var rows: Array = [
		["帆具", str(sail_lv), "+%d%% 航速" % int(GameState.ship_sail_bonus() * 100.0),
			str(int(GameState.MOD_SAIL_COST[sail_lv + 1])) if sail_lv < 2 else "已满", "sail"],
		["火炮位", str(can_lv), "+%d 可装炮" % GameState.ship_cannon_bonus(),
			str(int(GameState.MOD_CANNON_COST[can_lv + 1])) if can_lv < 2 else "已满", "cannon"],
	]
	for rw in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		mod_list.add_child(row)
		row.add_child(_cell_box(String(rw[0]), 260))
		row.add_child(_cell_box(String(rw[1]), 120, Color(0.95, 0.9, 0.55)))
		row.add_child(_cell_box(String(rw[2]), 220, Color(0.7, 0.85, 0.75)))
		row.add_child(_cell_box(String(rw[3]), 180))
		var op := PanelContainer.new()
		op.custom_minimum_size = Vector2(160, 30)
		var btn := Button.new()
		btn.text = "改装"
		btn.custom_minimum_size = Vector2(100, 26)
		var kind := String(rw[4])
		btn.disabled = (sail_lv >= 2) if kind == "sail" else (can_lv >= 2)
		btn.pressed.connect(func(): _do_mod(kind))
		op.add_child(btn)
		row.add_child(op)

func _do_mod(kind: String) -> void:
	var r: Dictionary = GameState.mod_sail() if kind == "sail" else GameState.mod_cannon()
	if bool(r.get("ok", false)):
		_log("改装完成：%s Lv%d" % [kind, int(r.get("level", 0))])
		_rebuild_mod()
	else:
		_log(String(r.get("reason", "改装失败")))

## 离开他岛城镇，返回海面
func _leave_town() -> void:
	var pid := GameState.visit_port_id
	GameState.visit_port_id = &"jadehaven"
	close_all_and_goto_sea(pid)

func close_all_and_goto_sea(_pid: StringName) -> void:
	_close_all_panels()
	SceneRouter.goto(&"sea")

## 投资面板（岛屿）
func _toggle_invest() -> void:
	if invest_root.visible:
		invest_root.visible = false
		return
	_rebuild_invest()
	invest_root.visible = true

func _rebuild_invest() -> void:
	for c in invest_list.get_children():
		invest_list.remove_child(c)
		c.queue_free()
	var key := String(GameState.visit_port_id)
	var invested := int(GameState.island_investment.get(key, 0))
	_yard_title_to(invest_list, "投资 · %s（已投 %d）" % [GameState.visit_port_name(), invested])
	invest_list.add_child(_lbl("　买入折扣 %d%%　边际 +%.2f%%/千金" % [
		GameState.island_discount(key), GameState.island_marginal_discount(key)],
		700, Color(0.8, 0.85, 0.8)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	invest_list.add_child(row)
	for amt in [1000, 5000, 20000]:
		var bb := Button.new()
		bb.text = "注资 %d" % int(amt)
		bb.custom_minimum_size = Vector2(130, 30)
		bb.disabled = GameState.gold < int(amt)
		var av := int(amt)
		bb.pressed.connect(func(): _do_invest_cash(key, av))
		row.add_child(bb)
	var dep := Button.new()
	dep.text = "用存款投资"
	dep.custom_minimum_size = Vector2(130, 30)
	dep.disabled = GameState.bank_deposited() <= 0
	dep.pressed.connect(func(): _do_invest_deposit(key))
	row.add_child(dep)

func _do_invest_cash(key: String, amount: int) -> void:
	var r: Dictionary = GameState.invest_from("cash", key, amount)
	if bool(r.get("ok", false)):
		_rebuild_invest()
		_refresh()
	else:
		_log(String(r.get("reason", "投资失败")))

func _do_invest_deposit(key: String) -> void:
	var amount := int(GameState.bank_deposited() / 2)
	if amount <= 0:
		return
	var r: Dictionary = GameState.invest_from("deposit", key, amount)
	if bool(r.get("ok", false)):
		_rebuild_invest()
		_refresh()

## 更换船只：列出本港停泊的船
func _open_ship_swap() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "更换船只"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	dlg.add_child(vb)
	vb.add_child(_lbl("当前：%s" % String(GameState.ship_def().display_name) if GameState.ship_def() != null else "当前：未知", 420, Color(0.95, 0.9, 0.55)))
	var port := String(GameState.current_port)
	var shown := 0
	for i in range(GameState.ships_owned.size()):
		var entry: Dictionary = GameState.ships_owned[i]
		if String(entry.get("station_port", "")) != port:
			continue
		var edef: Resource = DataRegistry.get_ship(StringName(String(entry.get("def_id", ""))))
		if edef == null:
			continue
		shown += 1
		var btn := Button.new()
		btn.text = String(edef.display_name)
		btn.custom_minimum_size = Vector2(360, 30)
		var idx := i
		btn.pressed.connect(func():
			var ok := GameState.swap_to_owned(idx, StringName(port))
			_log("已换乘：" + String(edef.display_name) if ok else "换乘失败（货舱不足或船只不存在）")
			dlg.queue_free()
			_rebuild_ship_panel()
			_refresh())
		vb.add_child(btn)
	if shown == 0:
		vb.add_child(_lbl("本港没有其他船只。可前往港镇以上的船厂购买。", 460, Color(0.75, 0.75, 0.68)))
	add_child(dlg)
	dlg.popup_centered()

## 插槽绝对坐标（与船影同一套区域常量）
func _ship_slot_pos(mid: String, layer: int, tier: int) -> Vector2:
	var w := ship_area_size.x
	var h := ship_area_size.y
	var md: Resource = DataRegistry.modules.get(mid)
	if md == null:
		return Vector2(0.5 * w, 0.6 * h)
	var a: Vector2 = md.anchor
	# 分层模块按设计稿的行距向下步进
	var step := 0.0
	if mid == "deck":
		step = 0.121
	elif mid == "gundeck":
		step = 0.110
	return Vector2(a.x * w, (a.y + step * float(layer)) * h)

# ---------------- 舰船面板（1.4.6） ----------------

var ship_root: PanelContainer = null
var ship_area: Control = null
var ship_stats_box: VBoxContainer = null
var ship_tab := "gear"
var ship_area_size := Vector2(1150, 690)

func _toggle_ship() -> void:
	if ship_root.visible:
		ship_root.visible = false
		return
	_close_all_panels()
	_rebuild_ship_panel()
	_refresh()
	ship_root.visible = true
	ship_root.z_index = 20
	ship_root.move_to_front()

func _rebuild_ship_panel() -> void:
	for c in ship_area.get_children():
		ship_area.remove_child(c)
		c.queue_free()
	for c2 in ship_stats_box.get_children():
		ship_stats_box.remove_child(c2)
		c2.queue_free()
	# 船影（按船级决定桅杆数）
	var tier := int(GameState.ship_def().get("tier")) if GameState.ship_def() != null else 1
	var masts := 1 if tier <= 2 else (2 if tier <= 4 else 3)
	var sil := Control.new()
	sil.set_script(load("res://scripts/ui/ship_silhouette.gd"))
	sil.size = ship_area_size
	sil.masts = masts
	sil.tier = tier
	ship_area.add_child(sil)
	# 插槽
	for inst in GameState.ship_modules():
		var mid: String = String(inst["module_id"])
		var layer: int = int(inst["layer"])
		var md: Resource = DataRegistry.modules.get(mid)
		if md == null:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(38, 38)
		btn.size = btn.custom_minimum_size
		btn.position = _ship_slot_pos(mid, layer, tier) - btn.size * 0.5
		btn.text = _ship_slot_text(mid, layer)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", Color(0.15, 0.12, 0.05))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.95, 0.76, 0.29)
		style.set_corner_radius_all(19)
		style.border_color = Color(0.2, 0.15, 0.05)
		style.set_border_width_all(2)
		btn.add_theme_stylebox_override("normal", style)
		var midv := mid
		var lv := layer
		btn.pressed.connect(func(): _open_ship_slot(midv, lv))
		ship_area.add_child(btn)
	# 右侧属性
	var stt: Dictionary = GameState.stats()
	for pair in [
		["船体", "%d / %d" % [int(minf(GameState.hull_hp, float(stt.get("hull_max", 0.0))) if GameState.hull_hp >= 0.0 else float(stt.get("hull_max", 0.0))), int(stt.get("hull_max", 0.0))]],
		["航速", "%.0f" % float(stt.get("base_speed_px", 0.0))],
		["转向", "%.0f" % float(stt.get("turn_rate", 0.0))],
		["装甲", str(int(stt.get("armor", 0)))],
		["舷侧炮", str(int(stt.get("guns_per_side", 0)))],
		["货舱", str(int(stt.get("cargo_capacity", 0)))],
		["船员上限", "%.0f" % float(stt.get("crew_max", 0.0))],
		["接舷", str(int(stt.get("boarding", 0)))],
		["声望加成", "%+d%%" % int(round(float(stt.get("rep_gain_bonus", 0.0)) * 100.0))],
	]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		ship_stats_box.add_child(hb)
		hb.add_child(_lbl(String(pair[0]), 180, Color(0.66, 0.76, 0.82)))
		hb.add_child(_lbl(String(pair[1]), 160, Color(0.95, 0.9, 0.55)))

func _ship_slot_text(mid: String, layer: int) -> String:
	var md: Resource = DataRegistry.modules.get(mid)
	var short_name := String(md.display_name).substr(0, 1)
	if layer > 0 or mid == "sails":
		short_name += str(layer + 1)
	var lv := GameState.module_level(mid, layer)
	if lv > 0:
		short_name += "+%d" % lv
	return short_name

func _open_ship_slot(mid: String, layer: int) -> void:
	var md: Resource = DataRegistry.modules.get(mid)
	if md == null:
		return
	var dlg := AcceptDialog.new()
	dlg.title = "%s%s" % [String(md.display_name), "（第 %d 层）" % (layer + 1) if layer > 0 else ""]
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	dlg.add_child(vb)
	# 强化信息
	var lv := GameState.module_level(mid, layer)
	var cap := GameState.module_level_cap()
	var cost: Dictionary = GameState.module_upgrade_cost(mid, layer)
	var info := "等级 %d / %d　强化：%d 金 · 木 %d · 铁 %d" % [
		lv, cap, int(cost["gold"]), int(cost["timber"]), int(cost["iron"])]
	vb.add_child(_lbl(info, 520, Color(0.85, 0.85, 0.7)))
	if lv < cap:
		var ub := Button.new()
		ub.text = "强化"
		ub.custom_minimum_size = Vector2(120, 30)
		var midu := mid
		var lvu := layer
		ub.pressed.connect(func():
			var r: Dictionary = GameState.upgrade_module(midu, lvu)
			_log("强化成功：Lv%d" % int(r.get("level", 0)) if bool(r.get("ok", false)) else String(r.get("reason", "强化失败")))
			dlg.queue_free()
			_rebuild_ship_panel()
			_refresh())
		vb.add_child(ub)
	vb.add_child(HSeparator.new())
	if ship_tab == "gear":
		_add_gear_options(vb, mid, layer)
	else:
		_add_crew_options(vb, mid, layer)
	add_child(dlg)
	dlg.popup_centered()

func _gear_slot_of(mid: String, layer: int) -> String:
	if mid == "sails":
		return "sail%d" % layer
	if mid == "deck":
		return "figurehead" if layer == 0 else "plate"
	var md: Resource = DataRegistry.modules.get(mid)
	if md == null or md.gear_slots.is_empty():
		return ""
	return String(md.gear_slots[0])

func _add_gear_options(vb: VBoxContainer, mid: String, layer: int) -> void:
	var slot := _gear_slot_of(mid, layer)
	if slot == "" or slot == "cannon":
		vb.add_child(_lbl("该模块不设装备" if slot == "" else "火炮改装将在后续版本迁移", 420, Color(0.7, 0.7, 0.65)))
		return
	var current := String(GameState.equipped.get(slot, ""))
	vb.add_child(_lbl("当前：%s" % ("无" if current == "" else current), 420, Color(0.85, 0.88, 0.85)))
	for k in DataRegistry.gear.keys():
		var g: Resource = DataRegistry.gear[k]
		if g == null or String(g.slot) != slot:
			continue
		if not GameState.slot_allows(slot, String(g.id)):
			continue
		var btn := Button.new()
		var mark := "（已装）" if String(g.id) == current else ""
		btn.text = "%s%s  %s" % [String(g.display_name), mark, String(g.bonus_text())]
		btn.custom_minimum_size = Vector2(460, 28)
		var gid: StringName = g.id
		var s2 := slot
		btn.pressed.connect(func():
			GameState.equipped[s2] = gid
			_log("装备：%s" % String(g.display_name))
			_rebuild_ship_panel()
			_refresh())
		vb.add_child(btn)
	var off := Button.new()
	off.text = "卸下"
	off.custom_minimum_size = Vector2(120, 28)
	var s3 := slot
	off.pressed.connect(func():
		GameState.equipped.erase(s3)
		_rebuild_ship_panel()
		_refresh())
	vb.add_child(off)

func _add_crew_options(vb: VBoxContainer, mid: String, layer: int) -> void:
	var posts: Array = GameState.module_posts(mid)
	if posts.is_empty():
		vb.add_child(_lbl("该模块不设岗位", 360, Color(0.7, 0.7, 0.65)))
		return
	var cur: StringName = GameState.module_crew_of(mid, layer)
	vb.add_child(_lbl("当前：%s" % ("空缺" if String(cur) == "" else String(cur)), 360,
		Color(0.85, 0.88, 0.85)))
	for c in GameState.crew_roster:
		if not posts.has(c.role):
			continue
		var btn := Button.new()
		btn.text = "%s（%s · 属性 %d）" % [String(c.display_name),
			String(GameState.POST_NAMES.get(String(c.role), c.role)), int(c.stat)]
		btn.custom_minimum_size = Vector2(420, 28)
		var cid: StringName = c.crew_id
		var midc := mid
		var lvc := layer
		btn.pressed.connect(func():
			var r: Dictionary = GameState.assign_crew_to_module(cid, midc, lvc)
			_log("安排船员成功" if bool(r.get("ok", false)) else String(r.get("reason", "失败")))
			_rebuild_ship_panel()
			_refresh())
		vb.add_child(btn)
	if cur != &"":
		var off := Button.new()
		off.text = "撤下"
		off.custom_minimum_size = Vector2(120, 28)
		var midc2 := mid
		var lvc2 := layer
		off.pressed.connect(func():
			GameState.clear_module_crew(midc2, lvc2)
			_rebuild_ship_panel()
			_refresh())
		vb.add_child(off)

# ---------------- 声望兑换所（1.3.11） ----------------

var exch_root: PanelContainer = null
var exch_list: VBoxContainer = null

## 声望条着色：正绿、负红、零灰
func _tint_rep_bar(bar: ProgressBar, value: int) -> void:
	var sb := StyleBoxFlat.new()
	if value > 0:
		sb.bg_color = Color(0.35, 0.78, 0.45)
	elif value < 0:
		sb.bg_color = Color(0.85, 0.35, 0.32)
	else:
		sb.bg_color = Color(0.55, 0.58, 0.55)
	bar.add_theme_stylebox_override("fill", sb)

func _open_exchange(faction: String) -> void:
	_close_all_panels()
	_rebuild_exchange(faction)
	exch_root.visible = true

func _rebuild_exchange(faction: String) -> void:
	for c in exch_list.get_children():
		exch_list.remove_child(c)
		c.queue_free()
	var rep := GameState.faction_rep_of(faction)
	_yard_title_to(exch_list, "声望兑换所 · %s　　声望 %d（%s）　现金 %d" % [
		String(GameState.FACTION_V2_NAMES.get(faction, faction)), rep,
		GameState.faction_tier_name(faction), GameState.gold])
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	exch_list.add_child(grid)
	for row in GameState.exchange_offers(faction):
		var def: Dictionary = GameState.item_def(String(row["item"]))
		if def.is_empty():
			continue
		var need := int(row["rep_need"])
		var ok := rep >= need
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(250, 110)
		cell.text = "%s\n\n声望 %d" % [String(def["name"]), need]
		cell.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if ok else Color(0.95, 0.45, 0.4))
		if not ok:
			cell.tooltip_text = "声望不足，暂时无法兑换"
		cell.add_theme_font_size_override("font_size", 15)
		var item_id := String(row["item"])
		cell.pressed.connect(func(): _show_exchange_detail(item_id, faction))
		grid.add_child(cell)
	var back := Button.new()
	back.text = "关闭"
	back.custom_minimum_size = Vector2(140, 34)
	back.pressed.connect(func(): exch_root.visible = false)
	exch_list.add_child(back)

func _show_exchange_detail(item_id: String, faction: String) -> void:
	var def: Dictionary = GameState.item_def(item_id)
	if def.is_empty():
		return
	var row: Dictionary = {}
	for r in GameState.exchange_offers(faction):
		if String(r["item"]) == item_id:
			row = r
			break
	if row.is_empty():
		return
	var dlg := AcceptDialog.new()
	dlg.title = String(def["name"])
	var vb := VBoxContainer.new()
	dlg.add_child(vb)
	for line in [
		"类型：%s" % String(def["kind"]),
		"需求声望：%d（%s）" % [int(row["rep_need"]), GameState.faction_tier_name(faction)],
		"声望消耗：%d" % int(row["rep_cost"]),
		"金币价格：%d" % int(row["gold"]),
		"效果：%s" % String(def["desc"]),
	]:
		vb.add_child(_lbl(line, 360, Color(0.85, 0.88, 0.85)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var can_claim := GameState.faction_rep_of(faction) >= int(row["rep_need"])
	if not can_claim:
		vb.add_child(_lbl("声望不足，无法兑换", 360, Color(0.95, 0.45, 0.4)))
	var ok := Button.new()
	ok.text = "确认"
	ok.custom_minimum_size = Vector2(110, 30)
	ok.disabled = not can_claim
	var gold_need := int(row["gold"])
	var rep_cost := int(row["rep_cost"])
	ok.pressed.connect(func(): _do_exchange(item_id, faction, gold_need, rep_cost, dlg))
	hb.add_child(ok)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(110, 30)
	cancel.pressed.connect(func(): dlg.queue_free())
	hb.add_child(cancel)
	add_child(dlg)
	dlg.popup_centered()

func _do_exchange(item_id: String, faction: String, _gold_need: int, _rep_cost: int, dlg: Node) -> void:
	var r: Dictionary = GameState.exchange_item(faction, item_id)
	if bool(r.get("ok", false)):
		_log("兑换成功：%s" % String(r.get("name", item_id)))
		dlg.queue_free()
	else:
		dlg.queue_free()
		_show_message("兑换失败", String(r.get("reason", "兑换失败")))
	_rebuild_exchange(faction)
	_refresh()

## 通用提示弹窗（确定 / ESC 关闭）
func _show_message(title: String, body: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.dialog_text = body
	dlg.ok_button_text = "确定"
	add_child(dlg)
	dlg.popup_centered()

# ---------------- 势力声望面板（1.3.6） ----------------

var fac_root: PanelContainer = null
var fac_list: VBoxContainer = null
var fac_current: String = "yunlan"

func _toggle_factions() -> void:
	if fac_root.visible:
		fac_root.visible = false
		return
	_rebuild_factions()
	fac_root.visible = true

func _rebuild_factions() -> void:
	for c in fac_list.get_children():
		fac_list.remove_child(c)
		c.queue_free()
	_yard_title_to(fac_list, "势力声望")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	fac_list.add_child(tabs)
	var ov := Button.new()
	ov.text = "总览"
	ov.custom_minimum_size = Vector2(104, 32)
	ov.modulate = Color(1.0, 0.92, 0.55) if fac_current == "" else Color(1, 1, 1)
	ov.pressed.connect(func(): fac_current = ""; _rebuild_factions())
	tabs.add_child(ov)
	for fid in GameState.FACTIONS_V2:
		var tb := Button.new()
		tb.text = String(GameState.FACTION_V2_NAMES.get(fid, fid))
		tb.custom_minimum_size = Vector2(104, 32)
		tb.modulate = Color(1.0, 0.92, 0.55) if fid == fac_current else Color(1, 1, 1)
		var fv := String(fid)
		tb.pressed.connect(func(): fac_current = fv; _rebuild_factions())
		tabs.add_child(tb)
	if fac_current == "":
		_yard_title_to(fac_list, "七大势力总览")
		for fid0 in GameState.FACTIONS_V2:
			var row0 := HBoxContainer.new()
			row0.add_theme_constant_override("separation", 10)
			fac_list.add_child(row0)
			row0.add_child(_lbl(String(GameState.FACTION_V2_NAMES.get(fid0, fid0)), 120,
				Color(0.85, 0.88, 0.85)))
			var bar0 := ProgressBar.new()
			bar0.min_value = -100
			bar0.max_value = 100
			bar0.value = GameState.faction_rep_of(fid0)
			bar0.custom_minimum_size = Vector2(420, 20)
			bar0.show_percentage = false
			_tint_rep_bar(bar0, GameState.faction_rep_of(fid0))
			row0.add_child(bar0)
			row0.add_child(_lbl("%d（%s）" % [GameState.faction_rep_of(fid0),
				GameState.faction_tier_name(fid0)], 180, Color(0.9, 0.82, 0.45)))
		if not GameState.faction_events.is_empty():
			var ev_lines: Array = []
			for e in GameState.faction_events:
				var kname: String = {"war": "宣战", "peace": "停战", "alliance": "结盟", "embargo": "禁运"}.get(String(e["kind"]), String(e["kind"]))
				ev_lines.append("%s ⇄ %s %s（剩 %d 周）" % [
					String(GameState.FACTION_V2_NAMES.get(String(e["a"]), String(e["a"]))),
					String(GameState.FACTION_V2_NAMES.get(String(e["b"]), String(e["b"]))),
					kname, int(e["weeks_left"])])
			_yard_title_to(fac_list, "进行中的势力事件")
			for line in ev_lines:
				fac_list.add_child(_lbl("　%s" % String(line), 700, Color(0.9, 0.75, 0.5)))
		var lic_txt := "无"
		if GameState.has_privateer_license and GameState.privateer_nation != "":
			lic_txt = "%s私掠证" % String(GameState.FACTION_V2_NAMES.get(GameState.privateer_nation, GameState.privateer_nation))
		_yard_title_to(fac_list, "当前持有私掠证：%s" % lic_txt)
		return
	var v := GameState.faction_rep_of(fac_current)
	_yard_title_to(fac_list, "%s · 声望 %d（%s）" % [
		String(GameState.FACTION_V2_NAMES.get(fac_current, fac_current)),
		v, GameState.faction_tier_name(fac_current)])
	var bar := ProgressBar.new()
	bar.min_value = -100
	bar.max_value = 100
	bar.value = v
	bar.custom_minimum_size = Vector2(720, 26)
	bar.show_percentage = false
	_tint_rep_bar(bar, v)
	fac_list.add_child(bar)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	fac_list.add_child(head)
	head.add_child(_cell_box("声望等级", 180, Color(0.62, 0.78, 0.85), true))
	head.add_child(_cell_box("效果说明", 900, Color(0.62, 0.78, 0.85), true))
	var active_idx := GameState.faction_tier_index(fac_current)
	for i in range(GameState.FACTION_TIER_EFFECTS.size()):
		var row: Dictionary = GameState.FACTION_TIER_EFFECTS[i]
		var rrow := HBoxContainer.new()
		rrow.add_theme_constant_override("separation", 0)
		fac_list.add_child(rrow)
		var is_active := i == active_idx
		var col := Color(0.55, 0.95, 0.6) if is_active else Color(0.55, 0.58, 0.55)
		var nm_label := _cell_box(String(row["name"]), 180, col)
		var ef_label := _cell_box(String(row["effect"]), 900, col)
		if is_active:
			nm_label.add_theme_font_size_override("font_size", 19)
			ef_label.add_theme_font_size_override("font_size", 19)
		rrow.add_child(nm_label)
		rrow.add_child(ef_label)
	if fac_current != "youming" or true:
		var ex_btn := Button.new()
		ex_btn.text = "声望兑换所"
		ex_btn.custom_minimum_size = Vector2(180, 34)
		var fcur := String(fac_current)
		ex_btn.pressed.connect(func(): _open_exchange(fcur))
		fac_list.add_child(ex_btn)

# ---------------- 仓库面板（1.2.1） ----------------

var store_root: PanelContainer = null
var store_list: VBoxContainer = null
var store_tab := "all"

func _toggle_store() -> void:
	if store_root.visible:
		store_root.visible = false
		return
	_rebuild_store()
	store_root.visible = true

func _rebuild_store() -> void:
	for c in store_list.get_children():
		store_list.remove_child(c)
		c.queue_free()
	var cap_ship := GameState.cargo_capacity()
	var cap_wh: int = GameState.warehouse_capacity()
	var used_ship: float = GameState.cargo_used()
	var used_wh: float = GameState.warehouse_used()
	_yard_title_to(store_list, "仓库与货舱")
	var col_ship := Color(0.92, 0.55, 0.5) if used_ship > cap_ship else Color(0.8, 0.86, 0.82)
	var col_wh2 := Color(0.92, 0.55, 0.5) if used_wh > cap_wh else Color(0.8, 0.86, 0.82)
	store_list.add_child(_lbl("　货舱 %d / %d　　仓库 %d / %d" % [used_ship, cap_ship, used_wh, cap_wh],
		700, col_ship))
	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 8)
	store_list.add_child(tabrow)
	for spec in [["all", "全部"], ["ship", "货舱"], ["wh", "仓库"]]:
		var tb := Button.new()
		tb.text = String(spec[1])
		tb.custom_minimum_size = Vector2(110, 30)
		tb.modulate = Color(1.0, 0.92, 0.6) if store_tab == String(spec[0]) else Color(1, 1, 1)
		var key := String(spec[0])
		tb.pressed.connect(func(): store_tab = key; _rebuild_store())
		tabrow.add_child(tb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	store_list.add_child(head)
	for spec2 in [["商品", 180], ["分类", 110], ["货舱", 110], ["仓库", 110], ["单位体积", 120], ["占用", 110], ["操作", 260]]:
		head.add_child(_cell_box(String(spec2[0]), int(spec2[1]), Color(0.62, 0.78, 0.85), true))
	for cid in GameState.all_commodities():
		var cdef: Resource = DataRegistry.get_commodity(cid)
		if cdef == null:
			continue
		var in_ship := int(GameState.cargo.get(cid, 0))
		var in_wh := int(GameState.warehouse.get(cid, 0))
		if in_ship <= 0 and in_wh <= 0:
			continue
		if store_tab == "ship" and in_ship <= 0:
			continue
		if store_tab == "wh" and in_wh <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		store_list.add_child(row)
		row.add_child(_cell_box(String(cdef.display_name), 180))
		row.add_child(_cell_box(String(GameState.CATEGORY_NAMES.get(String(cdef.category), String(cdef.category))), 110))
		row.add_child(_cell_box(str(in_ship), 110, Color(0.95, 0.9, 0.55) if in_ship > 0 else Color(0.6, 0.6, 0.6)))
		row.add_child(_cell_box(str(in_wh), 110, Color(0.95, 0.9, 0.55) if in_wh > 0 else Color(0.6, 0.6, 0.6)))
		row.add_child(_cell_box("%.2f" % float(cdef.volume), 120))
		row.add_child(_cell_box("%.0f" % (float(in_ship + in_wh) * float(cdef.volume)), 110))
		var op := PanelContainer.new()
		op.custom_minimum_size = Vector2(260, 30)
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 6)
		op.add_child(hb2)
		var b1 := Button.new()
		b1.text = "装船"
		b1.custom_minimum_size = Vector2(90, 26)
		var cv1: StringName = cid
		b1.disabled = in_wh <= 0
		b1.pressed.connect(func(): _do_move(cv1, "to_ship"))
		hb2.add_child(b1)
		var b2 := Button.new()
		b2.text = "存仓"
		b2.custom_minimum_size = Vector2(90, 26)
		b2.disabled = in_ship <= 0
		b2.pressed.connect(func(): _do_move(cv1, "to_wh"))
		hb2.add_child(b2)
		row.add_child(op)

func _do_move(cid: StringName, dir: String) -> void:
	var moved := 0
	if dir == "to_ship":
		moved = GameState.move_warehouse_to_cargo(cid)
	else:
		moved = GameState.move_cargo_to_warehouse(cid)
	if moved > 0:
		_log("转移 %d" % moved)
	_rebuild_store()
	_refresh()

# ---------------- 建造与投资（1.1） ----------------


func _toggle_construct() -> void:
	if construct_root.visible:
		construct_root.visible = false
		return
	_rebuild_construct()
	construct_root.visible = true

func _rebuild_construct() -> void:
	for c in construct_list.get_children():
		construct_list.remove_child(c)
		c.queue_free()
	var tier := GameState.home_port_tier
	var tp = load("res://scripts/ui/town_panel.gd")
	_yard_title_to(construct_list, "建造 · %s（现金 %d）" % [
		GameState.town_name("翡翠", tier), GameState.gold])
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	construct_list.add_child(head)
	for spec in [["建筑", 180], ["分类", 100], ["等级", 90], ["花费", 300], ["状态", 140], ["操作", 140]]:
		head.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))
	for bdef in tp.buildings_for_tier(tier):
		var bid := StringName(String(bdef.id))
		var lv := GameState.building_level(bid)
		var maxlv := int(bdef.max_level)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		construct_list.add_child(row)
		row.add_child(_cell_box(String(bdef.display_name), 180))
		row.add_child(_cell_box(String(bdef.category), 100))
		row.add_child(_cell_box("Lv%d/%d" % [lv, maxlv], 90, Color(0.95, 0.9, 0.55)))
		var cost_txt := "—"
		var can := false
		if lv < maxlv:
			var cost: Dictionary = bdef.cost_for(lv + 1)
			cost_txt = "%d 金 / 木 %d / 铁 %d" % [int(cost.gold), int(cost.timber), int(cost.iron)]
			can = GameState.gold >= int(cost.gold)
		row.add_child(_cell_box(cost_txt, 300))
		var st := "已建成" if lv > 0 else "未建"
		if GameState.building_upgrades.has(bid):
			st = "升级中"
		row.add_child(_cell_box(st, 140, Color(0.6, 0.85, 0.7) if lv > 0 else Color(0.8, 0.75, 0.6)))
		var op := PanelContainer.new()
		op.custom_minimum_size = Vector2(140, 30)
		var btn := Button.new()
		btn.text = "升级" if lv > 0 else "建造"
		btn.custom_minimum_size = Vector2(100, 26)
		btn.disabled = (lv >= maxlv) or GameState.building_upgrades.has(bid) or not can
		var bidv: StringName = bid
		btn.pressed.connect(func(): _start_parallel_upgrade(bidv))
		op.add_child(btn)
		row.add_child(op)
	# 升级条件（逐条指示）
	_yard_title_to(construct_list, "港口升级条件：%s → %s" % [
		GameState.town_name("翡翠", tier), GameState.town_name("翡翠", mini(3, tier + 1))])
	if tier >= 3:
		construct_list.add_child(_lbl("　已是最高等级（港城）", 600, Color(0.75, 0.85, 0.7)))
	else:
		var reqs: Array = GameState.town_upgrade_requirements()
		var rhead := HBoxContainer.new()
		rhead.add_theme_constant_override("separation", 0)
		construct_list.add_child(rhead)
		for spec in [["建筑", 220], ["当前/需求", 200], ["状态", 160]]:
			rhead.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))
		for rq in reqs:
			var rrow := HBoxContainer.new()
			rrow.add_theme_constant_override("separation", 0)
			construct_list.add_child(rrow)
			rrow.add_child(_cell_box(String(rq["name"]), 220))
			rrow.add_child(_cell_box("Lv%d / Lv%d" % [int(rq["have"]), int(rq["need"])], 200,
				Color(0.55, 0.9, 0.6) if bool(rq["ok"]) else Color(0.92, 0.55, 0.45)))
			rrow.add_child(_cell_box("已完成" if bool(rq["ok"]) else "未完成", 160,
				Color(0.55, 0.9, 0.6) if bool(rq["ok"]) else Color(0.92, 0.55, 0.45)))
		var ready := GameState.town_upgrade_ready()
		var up := Button.new()
		up.text = "港口升级 → %s" % GameState.town_suffix(mini(3, tier + 1)) if ready else "港口升级（条件未达成）"
		up.custom_minimum_size = Vector2(260, 36)
		up.disabled = not ready
		up.modulate = Color(0.6, 1.0, 0.6) if ready else Color(1, 1, 1)
		up.pressed.connect(func(): _do_build_upgrade())
		construct_list.add_child(up)

func _do_build_upgrade() -> void:
	if GameState.home_port_tier >= 3:
		return
	if not GameState.town_upgrade_ready():
		_log("升级条件未达成")
		return
	GameState.home_port_tier += 1
	GameState.build_submitted.clear()
	_log("城镇升级完成：%s" % GameState.town_name("翡翠", GameState.home_port_tier))
	_rebuild_construct()
	_refresh()
	queue_redraw()

## 提交弹窗：船上 / 仓库 两个输入框
func _open_submit(mat: String, need: int, in_ship: int, in_wh: int) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "提交材料"
	dlg.ok_button_text = "提交"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	dlg.add_child(vb)
	vb.add_child(Label.new())
	((vb.get_child(0)) as Label).text = "需求 %d　船上可用 %d　仓库可用 %d" % [need, in_ship, in_wh]
	var row1 := HBoxContainer.new()
	vb.add_child(row1)
	row1.add_child(_lbl("船上提交", 110))
	# 自动分配：船上优先，不足部分由仓库补足，且都不超过各自可用量
	var auto_ship := mini(in_ship, need)
	var auto_wh := mini(in_wh, maxi(0, need - auto_ship))
	var e1 := LineEdit.new()
	e1.text = str(auto_ship)
	e1.custom_minimum_size = Vector2(120, 30)
	row1.add_child(e1)
	var row2 := HBoxContainer.new()
	vb.add_child(row2)
	row2.add_child(_lbl("仓库提交", 110))
	var e2 := LineEdit.new()
	e2.text = str(auto_wh)
	e2.custom_minimum_size = Vector2(120, 30)
	row2.add_child(e2)
	add_child(dlg)
	dlg.confirmed.connect(func():
		var a := clampi(int(e1.text), 0, in_ship)
		var b := clampi(int(e2.text), 0, in_wh)
		_apply_submit(mat, a, b)
		dlg.queue_free()
		_rebuild_construct())
	dlg.popup_centered()

func _apply_submit(mat: String, from_ship: int, from_wh: int) -> void:
	if mat == "gold":
		if from_ship > 0:
			GameState.add_gold(-from_ship)
		GameState.build_submit("jadehaven", &"gold", from_ship + from_wh)
		return
	var cid := StringName(mat)
	if from_ship > 0:
		GameState.remove_cargo(cid, from_ship)
	if from_wh > 0:
		GameState.warehouse_remove(cid, from_wh)
	GameState.build_submit("jadehaven", cid, from_ship + from_wh)

# ---------------- 面板统一规范（0.19） ----------------

const FULL_PANELS := ["market_root", "yard_root", "tavern_root", "build_root",
	"quest_root", "overview_root", "finance_root", "bank_root", "black_root",
	"save_root", "rep_root", "help_root", "victory_root", "construct_root", "goods_root",
	"crew_root", "gear_root", "mod_root", "store_root", "invest_root", "fac_root", "exch_root", "ship_root"]

var close_btn: Button = null
var construct_root: PanelContainer = null
var construct_list: VBoxContainer = null
var invest_root: PanelContainer = null
var invest_list: VBoxContainer = null

func _apply_fullscreen_layout() -> void:
	for pname in FULL_PANELS:
		var p: Node = get(pname)
		if p == null or not (p is PanelContainer):
			continue
		p.position = Vector2(16, 72)
		p.custom_minimum_size = Vector2(1568, 812)
		p.size = Vector2(1568, 812)

func _any_panel_open() -> bool:
	for pname in FULL_PANELS:
		var p: Node = get(pname)
		if p != null and p is PanelContainer and p.visible:
			return true
	return false

func _sync_close_btn() -> void:
	if close_btn == null:
		return
	close_btn.visible = _any_panel_open()

func _build_close_button() -> void:
	close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(40, 34)
	close_btn.position = Vector2(1540, 78)
	close_btn.visible = false
	close_btn.pressed.connect(_close_all_panels)
	add_child(close_btn)

# ---------------- 财政（0.15） ----------------

var finance_root: PanelContainer = null
var finance_list: VBoxContainer = null

func _toggle_finance() -> void:
	if finance_root.visible:
		finance_root.visible = false
		return
	_rebuild_finance()
	finance_root.visible = true

## 建筑产出（生产函数）
func _building_output_line(name: String, level: int, exponent: float) -> String:
	var em = load("res://scripts/systems/econ_math.gd")
	var out: float = em.production_curve(100.0, level, exponent)
	var marg: float = em.marginal_output(100.0, level, exponent)
	return "%s Lv%d · 产出 %.0f · 升级 +%.0f" % [name, level, out, marg]

func _rebuild_finance() -> void:
	for c in finance_list.get_children():
		finance_list.remove_child(c)
		c.queue_free()
	var up: Dictionary = GameState.weekly_upkeep()
	_yard_title_to(finance_list, "财政 —— 现金 %d · 本周维护 %d" % [GameState.gold, int(up.get("total", 0))])
	_yard_title_to(finance_list, "本周成本明细")
	for row in [["船体维护", int(up.get("hull", 0)), "固定 · 按船队估值 2%"],
			["停泊费", int(up.get("berth", 0)), "固定 · 按母港等级"],
			["船员薪酬", int(up.get("crew", 0)), "可变 · 按在岗船员"],
			["火炮维护", int(up.get("cannon", 0)), "可变 · 按装备火炮"]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		finance_list.add_child(hb)
		hb.add_child(_lbl(String(row[0]), 140))
		hb.add_child(_lbl("%d 金" % int(row[1]), 110, Color(0.9, 0.82, 0.45)))
		hb.add_child(_lbl(String(row[2]), 260, Color(0.7, 0.76, 0.72)))
	var tot := HBoxContainer.new()
	tot.add_theme_constant_override("separation", 12)
	finance_list.add_child(tot)
	tot.add_child(_lbl("合计", 140, Color(0.8, 0.9, 0.7)))
	tot.add_child(_lbl("%d 金" % int(up.get("total", 0)), 110, Color(0.95, 0.9, 0.5)))
	tot.add_child(_lbl("固定 %d + 可变 %d" % [int(up.get("fixed", 0)), int(up.get("variable", 0))],
		260, Color(0.7, 0.76, 0.72)))

	_yard_title_to(finance_list, "资产与负债")
	var assets := GameState.gold + GameState.bank_deposited()
	finance_list.add_child(_lbl("　现金+存款 %d　｜　未还贷款本息 %d　｜　净额 %d" % [
		assets, GameState.loan_exposure(), assets - GameState.loan_exposure()],
		700, Color(0.78, 0.85, 0.8)))
	finance_list.add_child(_lbl("　沉没成本：已花费的修理与建造费用不再计入决策，仅作记录",
		700, Color(0.62, 0.68, 0.66)))

# ---------------- 银行（0.12） ----------------

func _toggle_bank() -> void:
	if bank_root.visible:
		bank_root.visible = false
		return
	_rebuild_bank()
	bank_root.visible = true

func _rebuild_bank() -> void:
	_rebuild_bank_rows()

## 银行面板：顶部数字原地更新，列表部分重建（1.2.15 方案 A）
var bank_cash_label: Label = null
var bank_deposit_label: Label = null
var bank_loan_label: Label = null
var bank_list_box: VBoxContainer = null

func _rebuild_bank_rows() -> void:
	# 首次构建整块骨架
	if bank_cash_label == null or not is_instance_valid(bank_cash_label):
		_build_bank_skeleton()
	_refresh_bank_numbers()
	_rebuild_bank_body()

func _build_bank_skeleton() -> void:
	for c in bank_list.get_children():
		bank_list.remove_child(c)
		c.queue_free()
	bank_cash_label = Label.new()
	bank_cash_label.add_theme_font_size_override("font_size", 16)
	bank_list.add_child(bank_cash_label)
	bank_deposit_label = Label.new()
	bank_deposit_label.add_theme_font_size_override("font_size", 15)
	bank_list.add_child(bank_deposit_label)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bank_list.add_child(hb)
	for amt in [1000, 10000]:
		var db := Button.new()
		db.text = "存入 %d" % amt
		db.custom_minimum_size = Vector2(110, 30)
		var av: int = amt
		db.pressed.connect(func(): _bank_deposit(av))
		hb.add_child(db)
		db.name = "Deposit%d" % amt
	var wb := Button.new()
	wb.text = "全部取出"
	wb.custom_minimum_size = Vector2(110, 30)
	wb.pressed.connect(func(): _bank_withdraw_all())
	hb.add_child(wb)
	bank_loan_label = Label.new()
	bank_loan_label.add_theme_font_size_override("font_size", 15)
	bank_list.add_child(bank_loan_label)
	bank_list_box = VBoxContainer.new()
	bank_list_box.add_theme_constant_override("separation", 4)
	bank_list.add_child(bank_list_box)

## 只改文字，不重建控件
func _refresh_bank_numbers() -> void:
	if bank_cash_label == null:
		return
	bank_cash_label.text = "银行 —— 现金 %d · 全城通存通取" % GameState.gold
	bank_deposit_label.text = "存款 %d（周息 0.1%%，每月结算）" % GameState.bank_deposited()
	bank_loan_label.text = "未还贷款 %d / %d 笔 · 未还本息 %d" % [
		GameState.loan_count(), int(GameState.MAX_LOANS), GameState.loan_exposure()]

## 动态部分（贷款列表 + 可选贷款档位）才重建
func _rebuild_bank_body() -> void:
	if bank_list_box == null:
		return
	for c in bank_list_box.get_children():
		bank_list_box.remove_child(c)
		c.queue_free()
	if GameState.loans.is_empty():
		bank_list_box.add_child(_lbl("　（没有未还贷款）", 400, Color(0.5, 0.55, 0.55)))
	for i in range(GameState.loans.size()):
		var l: Dictionary = GameState.loans[i]
		var lhb := HBoxContainer.new()
		lhb.add_theme_constant_override("separation", 10)
		bank_list_box.add_child(lhb)
		lhb.add_child(_lbl("贷款 %d：%d 金" % [i + 1, int(l.get("amount", 0))], 200))
		lhb.add_child(_lbl("剩 %d 周 · 下次付息 %d" % [int(l.get("left", 0)),
			GameState.loan_monthly_due(l)], 220, Color(0.9, 0.82, 0.45)))
		var li := i
		var rbtn := Button.new()
		rbtn.text = "还清"
		rbtn.custom_minimum_size = Vector2(80, 26)
		rbtn.pressed.connect(func(): _bank_repay_one(li))
		lhb.add_child(rbtn)
	if GameState.loan_count() > 1:
		var ab := Button.new()
		ab.text = "全部还清"
		ab.custom_minimum_size = Vector2(120, 30)
		ab.pressed.connect(func(): _bank_repay())
		bank_list_box.add_child(ab)
	bank_list_box.add_child(_lbl("新增贷款（本息总额不得超过存款 %d）" % GameState.bank_deposited(),
		600, Color(0.85, 0.82, 0.6)))
	var term_names := {12: "一季", 26: "半年", 52: "一年"}
	for amount in GameState.LOAN_TIERS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		bank_list_box.add_child(row)
		row.add_child(_lbl("%d 金" % int(amount), 110))
		for weeks in GameState.LOAN_TERMS[amount]:
			var wk := int(weeks)
			var chk: Dictionary = GameState.can_take_loan(int(amount), wk)
			var bb := Button.new()
			bb.text = "借 %s（%d 息）" % [String(term_names.get(wk, "%d 周" % wk)),
				GameState.loan_interest_for(int(amount), wk)]
			bb.custom_minimum_size = Vector2(170, 28)
			bb.disabled = not bool(chk.get("ok", false))
			var amt_v: int = int(amount)
			bb.pressed.connect(func(): _bank_borrow_tier(amt_v, wk))
			row.add_child(bb)

func _bank_deposit(amount: int) -> void:

	if GameState.bank_deposit_gold(amount):
		_log("存入 %d 金" % amount)
		_rebuild_bank_rows()
		_refresh()

func _bank_withdraw_all() -> void:
	var amt := GameState.bank_deposited()
	if GameState.bank_withdraw(amt):
		_log("取出 %d 金" % amt)
		_rebuild_bank_rows()
		_refresh()

func _bank_borrow_tier(amount: int, weeks: int) -> void:
	var r: Dictionary = GameState.bank_borrow(amount, weeks)
	if bool(r.get("ok", false)):
		_log("贷款到账 %d 金，到期利息 %d" % [amount, int(r.get("interest", 0))])
		_rebuild_bank_rows()
		_refresh()
	else:
		_log(String(r.get("reason", "贷款失败")))

func _bank_repay_one(index: int) -> void:
	var r: Dictionary = GameState.bank_repay_one(index)
	if bool(r.get("ok", false)):
		_log("已还清该笔 %d 金" % int(r.get("paid", 0)))
		_rebuild_bank_rows()
		_refresh()
	else:
		_log(String(r.get("reason", "还款失败")))

func _bank_repay() -> void:
	var r: Dictionary = GameState.bank_repay()
	if bool(r.get("ok", false)):
		_log("已还清 %d 金" % int(r.get("paid", 0)))
		_rebuild_bank_rows()
		_refresh()
	else:
		_log(String(r.get("reason", "还款失败")))

# ---------------- 母港黑市（0.12） ----------------

func _toggle_black() -> void:
	if black_root.visible:
		black_root.visible = false
		return
	_rebuild_black()
	black_root.visible = true

func _sell_license() -> void:
	var r: Dictionary = GameState.sell_license()
	if bool(r.get("ok", false)):
		_log("出售私掠证，返还 %d 金" % int(r.get("gold", 0)))
	else:
		_log(String(r.get("reason", "出售失败")))
	_rebuild_black()
	_refresh()

func _buy_license_black_prompt() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "选择国家"
	var vb := VBoxContainer.new()
	dlg.add_child(vb)
	for fid in GameState.FACTIONS_V2:
		if fid == "youming":
			continue
		var btn := Button.new()
		btn.text = String(GameState.FACTION_V2_NAMES.get(fid, fid))
		btn.custom_minimum_size = Vector2(200, 30)
		var fv := String(fid)
		btn.pressed.connect(func(): _do_buy_black(fv))
		vb.add_child(btn)
	add_child(dlg)
	dlg.popup_centered()

func _do_buy_black(nation: String) -> void:
	var r: Dictionary = GameState.buy_license_black(nation)
	if bool(r.get("ok", false)):
		_log("取得%s私掠证（黑市）" % String(GameState.FACTION_V2_NAMES.get(nation, nation)))
	else:
		_log(String(r.get("reason", "购买失败")))
	_rebuild_black()
	_refresh()

func _rebuild_black() -> void:
	for c in black_list.get_children():
		black_list.remove_child(c)
		c.queue_free()
	_yard_title_to(black_list, "黑市 —— 现金 %d · 通缉度 %d" % [GameState.gold, GameState.notoriety()])
	if not GameState.black_market_open():
		black_list.add_child(_lbl("　通缉度过高，黑市本周关闭", 500, Color(0.9, 0.5, 0.45)))
		return
	# 1.3.9：私掠证买卖
	_yard_title_to(black_list, "私掠证")
	var lic_row := HBoxContainer.new()
	lic_row.add_theme_constant_override("separation", 10)
	black_list.add_child(lic_row)
	if GameState.has_privateer_license:
		lic_row.add_child(_lbl("持有：%s私掠证" % String(GameState.FACTION_V2_NAMES.get(GameState.privateer_nation, GameState.privateer_nation)), 300,
			Color(0.7, 0.9, 0.7)))
		var sell_b := Button.new()
		sell_b.text = "出售（返还 30%）"
		sell_b.custom_minimum_size = Vector2(160, 28)
		sell_b.pressed.connect(func(): _sell_license())
		lic_row.add_child(sell_b)
	else:
		lic_row.add_child(_lbl("　尚未持有私掠证", 240, Color(0.6, 0.65, 0.62)))
		var buy_b := Button.new()
		buy_b.text = "黑市购买（需指定国家）"
		buy_b.custom_minimum_size = Vector2(220, 28)
		buy_b.pressed.connect(func(): _buy_license_black_prompt())
		lic_row.add_child(buy_b)

	_yard_title_to(black_list, "销赃（合法价 60%）")
	for cid in [&"grain", &"timber", &"rum", &"spice"]:
		var have := int(GameState.cargo.get(cid, 0))
		if have <= 0:
			continue
		var c: Resource = DataRegistry.get_commodity(cid)
		if c == null:
			continue
		var legal := MarketModel.sell_price(int(c.base_price), 400, 400, 1.0)
		var fprice := int(round(float(legal) * 0.60))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		black_list.add_child(hb)
		hb.add_child(_lbl("%s × %d" % [String(c.display_name), have], 200))
		hb.add_child(_lbl("销赃 %d/件" % fprice, 140, Color(0.9, 0.75, 0.5)))
		var cidv: StringName = cid
		var fb := Button.new()
		fb.text = "销赃 10"
		fb.custom_minimum_size = Vector2(90, 26)
		fb.pressed.connect(func(): _black_fence(cidv, 10, legal))
		hb.add_child(fb)

	_yard_title_to(black_list, "违禁品")
	for iid in GameState.CONTRABAND.keys():
		var cdef: Dictionary = GameState.CONTRABAND[iid]
		var ihb := HBoxContainer.new()
		ihb.add_theme_constant_override("separation", 10)
		black_list.add_child(ihb)
		ihb.add_child(_lbl(String(cdef.get("name", "")), 160))
		ihb.add_child(_lbl(String(cdef.get("desc", "")), 330, Color(0.78, 0.82, 0.72)))
		ihb.add_child(_lbl("%d 金" % int(cdef.get("price", 0)), 100, Color(0.9, 0.82, 0.45)))
		ihb.add_child(_lbl("持有 %d" % int(GameState.contraband.get(iid, 0)), 80, Color(0.7, 0.78, 0.7)))
		var iidv: StringName = iid
		var ib := Button.new()
		ib.text = "购买"
		ib.custom_minimum_size = Vector2(70, 26)
		ib.disabled = GameState.gold < int(cdef.get("price", 0))
		ib.pressed.connect(func(): _black_buy(iidv))
		ihb.add_child(ib)

func _black_fence(cid: StringName, amount: int, legal: int) -> void:
	var r: Dictionary = GameState.fence_goods(cid, amount, legal)
	if bool(r.get("ok", false)):
		_log("销赃得 %d 金（通缉度 +2）" % int(r.get("gold", 0)))
		_rebuild_black()
		_refresh()
	else:
		_log(String(r.get("reason", "销赃失败")))

func _black_buy(iid: StringName) -> void:
	var r: Dictionary = GameState.buy_contraband(iid)
	if bool(r.get("ok", false)):
		_log("购得违禁品（通缉度 +2）")
		_rebuild_black()
		_refresh()
	else:
		_log(String(r.get("reason", "购买失败")))

func _port_upgrade_label() -> String:
	if GameState.home_upgrade_cost().is_empty():
		return "港口已达最高级"
	var c := GameState.home_upgrade_cost()
	return "升级港口 → %s（%d 金 / %d 木 / %d 铁）" % [
		GameState.port_name(GameState.home_port_tier + 1),
		int(c.get("gold", 0)), int(c.get("timber", 0)), int(c.get("iron", 0))]

func _do_upgrade_port() -> void:
	if GameState.home_upgrade_cost().is_empty():
		_log("母港已是最高等级")
		return
	if not GameState.can_upgrade_home_port():
		_log("资源不足，无法升级母港")
		return
	var before := GameState.home_port_tier
	if GameState.upgrade_home_port():
		_log("母港升级：%s → %s" % [GameState.port_name(before), GameState.home_port_name()])
		SceneRouter.goto(&"base")
	else:
		_log("升级失败")

func _hire_crew(cid: StringName) -> void:
	var crew: Resource = null
	for c in GameState.tavern_pool:
		if StringName(c.crew_id) == cid:
			crew = c
			break
	if crew == null:
		return
	if GameState.gold < int(crew.hire_cost):
		_log("金币不足，雇佣需要 %d 金" % int(crew.hire_cost))
		return
	GameState.add_gold(-int(crew.hire_cost))
	GameState.hire_crew(crew)
	GameState.tavern_pool.erase(crew)
	_log("雇佣了 %s" % crew.display_name)
	_rebuild_tavern()
	_refresh()

func _refresh_tavern_paid() -> void:
	if GameState.gold < 500:
		_log("金币不足")
		return
	GameState.add_gold(-500)
	GameState.refresh_tavern()
	_rebuild_tavern()
	_refresh()

func _lbl(text: String, width: float, color: Color = Color(0.85, 0.85, 0.8)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(width, 0)
	return l

func _yard_title(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.88, 0.76, 0.42))
	yard_list.add_child(l)

func _rebuild_yard() -> void:
	for c in yard_list.get_children():
		yard_list.remove_child(c)
		c.queue_free()
	var def: Resource = GameState.ship_def()
	var st: Dictionary = GameState.stats()

	_yard_title("船厂 —— %s·%s" % [def.display_name, String(st.get("variant_name", ""))])
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	info.add_child(_lbl("船体 %.0f" % float(st.get("hull_max", 0)), 110))
	info.add_child(_lbl("炮位 %d（单侧 %d）" % [int(def.cannon_slots), int(st.get("guns_per_side", 1))], 150))
	info.add_child(_lbl("航速 %.0f" % float(st.get("base_speed_px", 0)), 100))
	info.add_child(_lbl("转向 %.0f°/s" % float(st.get("turn_rate", 0)), 120))
	info.add_child(_lbl("载重 %d" % int(st.get("cargo_capacity", 0)), 100))
	info.add_child(_lbl("装甲 %d" % int(st.get("armor", 0)), 90))
	yard_list.add_child(info)

	# ---- 火炮 ----
	var cur_cannon: Resource = DataRegistry.get_cannon(GameState.cannon_id)
	_yard_title("火炮（当前：%s，单侧 %d 门）" % [cur_cannon.display_name, int(st.get("guns_per_side", 1))])
	var max_w := int(def.max_cannon_weight)
	var clist: Array = []
	for k in DataRegistry.cannons.keys():
		clist.append(DataRegistry.cannons[k])
	clist.sort_custom(func(a, b): return int(a.pound_class) < int(b.pound_class))
	var foundry_cap: int = GameState.cannon_class_cap()
	for c in clist:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		yard_list.add_child(hb)
		var ok_f: bool = int(c.pound_class) <= foundry_cap
		var ok_w: bool = int(c.pound_class) <= max_w
		var ok_all: bool = ok_f and ok_w
		hb.add_child(_lbl(c.display_name, 120, Color(0.85, 0.85, 0.8) if ok_all else Color(0.45, 0.45, 0.45)))
		hb.add_child(_lbl("伤害 %.0f" % float(c.damage), 90))
		hb.add_child(_lbl("装填 %.1fs" % float(c.reload_seconds), 100))
		hb.add_child(_lbl("射程 %.0f" % float(c.shot_range), 100))
		hb.add_child(_lbl("承载 %d/%d" % [int(c.pound_class), max_w], 100,
			Color(0.6, 0.75, 0.6) if ok_all else Color(0.8, 0.45, 0.45)))
		var cid: StringName = c.id
		if not ok_f:
			hb.add_child(_lbl("铸造厂 %d 级解锁" % (ceili(float(int(c.pound_class) - 3) / 2.0)), 160, Color(0.5, 0.45, 0.45)))
		elif not ok_w:
			hb.add_child(_lbl("炮位不足", 150, Color(0.5, 0.45, 0.45)))
		elif GameState.has_cannon(cid):
			var eqc: bool = GameState.cannon_id == cid
			var b := Button.new()
			b.text = "已装" if eqc else "装备"
			b.disabled = eqc
			b.custom_minimum_size = Vector2(80, 26)
			b.pressed.connect(func(): _equip_cannon(cid))
			hb.add_child(b)
		else:
			var bp := Button.new()
			bp.text = "购买 %d" % int(c.price)
			bp.custom_minimum_size = Vector2(110, 26)
			bp.pressed.connect(func(): _buy_cannon(cid, int(c.price)))
			hb.add_child(bp)

	# ---- 装备槽 ----
	_yard_title("装备槽")
	for slot in StatsLib.GEAR_SLOTS:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		yard_list.add_child(hb)
		var slot_name := {"sail": "风帆", "rudder": "船舵", "armor": "装甲", "figurehead": "船首像", "flag": "旗帜"}
		hb.add_child(_lbl(slot_name.get(String(slot), String(slot)), 90, Color(0.7, 0.8, 0.85)))
		var gid = GameState.equipped.get(slot, null)
		if gid == null:
			hb.add_child(_lbl("（空）", 360, Color(0.45, 0.5, 0.5)))
		else:
			var g: Resource = DataRegistry.get_gear(StringName(gid))
			var gl := _lbl("%s  %s" % [g.display_name, g.bonus_text()], 360, Rarity.color(int(g.rarity)))
			hb.add_child(gl)
			var b := Button.new()
			b.text = "卸下"
			b.custom_minimum_size = Vector2(70, 26)
			var s: StringName = slot
			b.pressed.connect(func(): _unequip(s))
			hb.add_child(b)

	# ---- 装备库 ----
	_yard_title("装备库（可购买 / 可装备）")
	var slot_names := {"sail": "风帆", "rudder": "船舵", "armor": "装甲", "figurehead": "船首像", "flag": "旗帜"}
	for slot in StatsLib.GEAR_SLOTS:
		for g in DataRegistry.gear_by_slot(slot):
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 8)
			yard_list.add_child(hb)
			hb.add_child(_lbl("[%s] %s" % [slot_names.get(String(slot), ""), g.display_name], 200, Rarity.color(int(g.rarity))))
			hb.add_child(_lbl(g.bonus_text(), 190, Color(0.75, 0.8, 0.8)))
			hb.add_child(_lbl("稀有度 %s" % Rarity.name_of(int(g.rarity)), 90, Color(0.6, 0.65, 0.65)))
			var gid: StringName = g.id
			var sl: StringName = slot
			if int(g.rarity) > GameState.gear_rarity_cap():
				hb.add_child(_lbl("织帆坊 %d 级解锁" % int(g.rarity), 160, Color(0.5, 0.45, 0.45)))
			elif GameState.has_gear(gid):
				var eq: bool = StringName(GameState.equipped.get(slot, &"")) == gid
				var b := Button.new()
				b.text = "已装备" if eq else "装备"
				b.disabled = eq
				b.custom_minimum_size = Vector2(80, 26)
				b.pressed.connect(func(): _equip(sl, gid))
				hb.add_child(b)
			else:
				var bp := Button.new()
				bp.text = "购买 %d" % int(g.price)
				bp.custom_minimum_size = Vector2(110, 26)
				bp.pressed.connect(func(): _buy_gear(gid, int(g.price)))
				hb.add_child(bp)

	# ---- 本港船队 ----
	_yard_title("本港船队（换乘）")
	var any_ship := false
	for i in range(GameState.ships_owned.size()):
		var entry: Dictionary = GameState.ships_owned[i]
		if String(entry.get("station_port", "")) != String(_pid()):
			continue
		any_ship = true
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		yard_list.add_child(hb)
		var edef: Resource = DataRegistry.get_ship(StringName(entry.get("def_id", "")))
		var vname := String(StatsLib.VARIANT_NAMES.get(StringName(entry.get("variant", "standard")), ""))
		hb.add_child(_lbl("%s·%s" % [edef.display_name, vname] if edef != null else "未知船", 320))
		var hp: float = float(entry.get("hull_hp", -1.0))
		hb.add_child(_lbl("船体 %s" % ("完好" if hp < 0.0 else "%.0f" % hp), 140, Color(0.7, 0.75, 0.7)))
		var idx := i
		var b := Button.new()
		b.text = "换乘"
		b.custom_minimum_size = Vector2(80, 26)
		b.pressed.connect(func(): _swap_ship(idx))
		hb.add_child(b)
	if not any_ship:
		yard_list.add_child(_lbl("（本港没有其它船）", 400, Color(0.45, 0.5, 0.5)))

	# ---- 购买船只 ----
	_yard_title("可购买船只（价格为变体价）")
	var defs: Array = []
	for k in DataRegistry.ships.keys():
		if DataRegistry.ship_bases.has(k):
			continue
		defs.append(DataRegistry.ships[k])
	defs.sort_custom(func(a, b):
		if int(a.tier) != int(b.tier):
			return int(a.tier) < int(b.tier)
		return String(a.variant) < String(b.variant))
	for d in defs:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		yard_list.add_child(hb)
		var vname2 := String(StatsLib.VARIANT_NAMES.get(StringName(d.variant), ""))
		var vcolor: Color = Color(0.85, 0.85, 0.8)
		if StringName(d.variant) == &"navy":
			vcolor = Color(0.55, 0.72, 0.92)
		elif StringName(d.variant) == &"pirate":
			vcolor = Color(0.9, 0.55, 0.5)
		hb.add_child(_lbl("%s·%s" % [d.display_name, vname2], 260, vcolor))
		hb.add_child(_lbl("炮 %d" % int(d.cannon_slots), 70))
		hb.add_child(_lbl("%d 金" % int(d.price), 110, Color(0.9, 0.82, 0.45)))
		var need := _rep_text(StringName(d.variant), int(d.tier))
		hb.add_child(_lbl(need, 170, Color(0.75, 0.6, 0.6) if need != "无门槛" else Color(0.55, 0.7, 0.55)))
		var b2 := Button.new()
		var ok: bool = _rep_ok(StringName(d.variant), int(d.tier))
		b2.text = "购买" if ok else "声望不足"
		b2.disabled = not ok
		b2.custom_minimum_size = Vector2(92, 26)
		var did: StringName = StringName(d.id)
		var var_id: StringName = StringName(d.variant)
		var pr: int = int(d.price)
		var base_did: StringName = StringName(String(d.id).trim_suffix("_" + String(d.variant)))
		b2.pressed.connect(func(): _buy_ship(base_did, var_id, pr))
		hb.add_child(b2)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 32)
	close.pressed.connect(func(): yard_root.visible = false)
	yard_list.add_child(close)

func _rep_ok(variant: StringName, tier: int) -> bool:
	var gate: Dictionary = StatsLib.reputation_gate(variant, tier)
	for k in gate.keys():
		if int(GameState.reputation.get(k, 0)) < int(gate[k]):
			return false
	return true

func _rep_text(variant: StringName, tier: int) -> String:
	var gate: Dictionary = StatsLib.reputation_gate(variant, tier)
	if gate.is_empty():
		return "无门槛"
	var parts: Array = []
	for k in gate.keys():
		var nm: String = {"royal_navy": "海军", "black_sail": "黑帆"}.get(String(k), String(k))
		parts.append("%s %d" % [nm, int(gate[k])])
	return "需 " + " / ".join(parts)

func _buy_ship(def_id: StringName, variant: StringName, price: int) -> void:
	var d: Resource = DataRegistry.get_ship(StringName("%s_%s" % [String(def_id), String(variant)]))
	var tier := int(d.tier) if d != null else 1
	if not _rep_ok(variant, tier):
		_log("声望不足，无法购买该型号")
		return
	if GameState.ships_owned.size() + 1 > GameState.storage_slots():
		_log("船位已满（%d/%d），升级仓库可扩容" % [GameState.ships_owned.size(), GameState.storage_slots()])
		return
	if GameState.gold < price:
		_log("金币不足，需要 %d 金" % price)
		return
	GameState.add_gold(-price)
	GameState.add_owned_ship(def_id, variant, price)
	_log("购入 %s·%s，已停泊在翡翠港" % [d.display_name, String(StatsLib.VARIANT_NAMES.get(variant, ""))])
	_rebuild_yard()
	_refresh()

func _swap_ship(index: int) -> void:
	if GameState.swap_overload(index):
		var other: Dictionary = GameState.ships_owned[index]
		var cap := GameState.cargo_capacity_of(StringName(other.get("def_id", "")), StringName(other.get("variant", "standard")))
		_log("货舱容量不足：当前货物 %.0f 单位，该船仅容 %d · 请先卸货到港口仓库或出售" % [GameState.cargo_used(), cap])
		return
	if not GameState.swap_to_owned(index):
		_log("换乘失败")
		return
	_log("已换乘 %s" % GameState.ship_def().display_name)
	_rebuild_yard()
	_refresh()

func _buy_gear(gid: StringName, price: int) -> void:
	var g0: Resource = DataRegistry.get_gear(gid)
	if g0 != null and int(g0.rarity) > GameState.gear_rarity_cap():
		_log("需要织帆坊 %d 级才能购买%s" % [int(g0.rarity), Rarity.name_of(int(g0.rarity))])
		return
	if GameState.gold < price:
		_log("金币不足，需要 %d 金" % price)
		return
	GameState.add_gold(-price)
	GameState.gear_owned.append(gid)
	var g: Resource = DataRegistry.get_gear(gid)
	_log("购入装备：%s" % g.display_name)
	_rebuild_yard()
	_refresh()

func _buy_cannon(cid: StringName, price: int) -> void:
	var c0: Resource = DataRegistry.get_cannon(cid)
	if c0 != null and int(c0.pound_class) > GameState.cannon_class_cap():
		_log("铸造厂等级不足，暂无法购入该磅级")
		return
	if GameState.gold < price:
		_log("金币不足，需要 %d 金" % price)
		return
	GameState.add_gold(-price)
	GameState.cannons_owned.append(cid)
	var c: Resource = DataRegistry.get_cannon(cid)
	_log("购入火炮：%s" % c.display_name)
	_rebuild_yard()
	_refresh()

func _equip_cannon(cid: StringName) -> void:
	if not GameState.can_mount_cannon(cid):
		_log("当前船炮位承载不足")
		return
	GameState.cannon_id = cid
	var c: Resource = DataRegistry.get_cannon(cid)
	_log("已换装 %s" % c.display_name)
	_rebuild_yard()
	_refresh()

func _equip(slot: StringName, gid: StringName) -> void:
	GameState.equip_gear(slot, gid)
	var g: Resource = DataRegistry.get_gear(gid)
	_log("已装备 %s" % g.display_name)
	_rebuild_yard()
	_refresh()

func _unequip(slot: StringName) -> void:
	GameState.equip_gear(slot, &"")
	_log("已卸下该槽位装备")
	_rebuild_yard()
	_refresh()

func _set_sail() -> void:
	GameState.sea_position = Vector2.ZERO
	SceneRouter.goto(&"sea")

func _toggle_save() -> void:
	if save_root.visible:
		save_root.visible = false
		return
	market_root.visible = false
	yard_root.visible = false
	tavern_root.visible = false
	build_root.visible = false
	quest_root.visible = false
	_rebuild_save()
	save_root.visible = true

func _rebuild_save() -> void:
	for c in save_list.get_children():
		save_list.remove_child(c)
		c.queue_free()
	_yard_title_to(save_list, "存档 —— 点击保存 / 读取")
	for slot in SaveManager.all_slot_ids():
		if int(slot) == SaveManager.AUTO_SLOT:
			continue
		var meta: Dictionary = SaveManager.slot_meta(int(slot))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		save_list.add_child(hb)
		var text := "存档 %d　空" % int(slot)
		var col := Color(0.45, 0.5, 0.5)
		if bool(meta.get("exists", false)):
			var map_name := "母港"
			var m: Resource = DataRegistry.get_map(int(meta.get("map", 1)))
			if m != null:
				map_name = String(m.display_name)
			text = "存档 %d　Lv.%d · %d 金 · %s" % [int(slot), int(meta.get("level", 1)),
				int(meta.get("gold", 0)), map_name]
			col = Color(0.85, 0.85, 0.78)
		var sl := Label.new()
		sl.text = text
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size = Vector2(320, 0)
		sl.add_theme_font_size_override("font_size", 14)
		sl.add_theme_color_override("font_color", col)
		hb.add_child(sl)
		var sid := int(slot)
		var b_save := Button.new()
		b_save.text = "保存"
		b_save.custom_minimum_size = Vector2(70, 26)
		b_save.pressed.connect(func(): _save_slot(sid))
		hb.add_child(b_save)
		var b_load := Button.new()
		b_load.text = "读取"
		b_load.custom_minimum_size = Vector2(70, 26)
		b_load.disabled = not bool(meta.get("exists", false))
		b_load.pressed.connect(func(): _load_slot(sid))
		hb.add_child(b_load)
	var ameta: Dictionary = SaveManager.slot_meta(SaveManager.AUTO_SLOT)
	var auto_text := "自动存档　空"
	if bool(ameta.get("exists", false)):
		auto_text = "自动存档　Lv.%d · %d 金" % [int(ameta.get("level", 1)), int(ameta.get("gold", 0))]
	save_list.add_child(_lbl(auto_text, 460, Color(0.7, 0.75, 0.7)))
	var ab := Button.new()
	ab.text = "读取自动存档"
	ab.custom_minimum_size = Vector2(150, 28)
	ab.disabled = not bool(ameta.get("exists", false))
	ab.pressed.connect(func(): _load_slot(SaveManager.AUTO_SLOT))
	save_list.add_child(ab)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 30)
	close.pressed.connect(func(): save_root.visible = false)
	save_list.add_child(close)

func _save_slot(slot: int) -> void:
	if SaveManager.save(slot):
		_log("已保存到存档位 %d" % slot)
		_rebuild_save()
	else:
		_log("保存失败")

func _load_slot(slot: int) -> void:
	if not SaveManager.load_slot(slot):
		_log("读取失败")
		return
	save_root.visible = false
	_rebuild_yard()
	_rebuild_market()
	_refresh()
	_log("已读取存档位 %d" % slot)

func _process(delta: float) -> void:
	_sync_close_btn()
	if _log_timer > 0.0:
		_log_timer -= delta
		if _log_timer <= 0.0:
			log_label.text = ""
