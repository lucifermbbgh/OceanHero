extends Node2D
## 母港「翡翠港」。阶段一只做：修理、市场、出航、存档。

const MarketModel = preload("res://scripts/systems/market_model.gd")
const StatsLib = preload("res://scripts/systems/ship_stats.gd")
const Rarity = preload("res://scripts/ui/rarity.gd")
const CrewFactory = preload("res://scripts/systems/crew_factory.gd")
const PORT_ID := &"jadehaven"

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
var ex_root: PanelContainer
var ex_list: VBoxContainer
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
	# 总督府 / 码头 / 船坞 三块建筑
	_building(Vector2(-40, -180), Vector2(130, 84), Color(0.55, 0.45, 0.30), "总督府")
	_building(Vector2(190, -110), Vector2(96, 64), Color(0.45, 0.40, 0.32), "船坞")
	_building(Vector2(60, 160), Vector2(110, 60), Color(0.50, 0.42, 0.28), "市场")

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
	if GameState.home_has("shipyard"):
		_action_button(vb, "船厂与装备", _toggle_yard)
	if GameState.home_has("building"):
		_action_button(vb, "基地建设", _toggle_build)
	if GameState.home_has("exchange"):
		_action_button(vb, "交易所", _toggle_exchange)
	if GameState.home_has("reputation"):
		_action_button(vb, "声望与战功", _toggle_rep)

	_action_button(vb, "建造", _toggle_construct)
	_action_button(vb, "经济总览", _toggle_overview)
	if GameState.home_port_tier >= 3:
		_action_button(vb, "银行", _toggle_bank)
		_action_button(vb, "黑市", _toggle_black)
	_action_button(vb, _port_upgrade_label(), _do_upgrade_port)
	_action_button(vb, "出航", _set_sail)
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

	# 交易所面板
	ex_root = PanelContainer.new()
	ex_root.position = Vector2(280, 60)
	ex_root.custom_minimum_size = Vector2(780, 560)
	ex_root.add_theme_stylebox_override("panel", _panel_style())
	ex_root.visible = false
	root.add_child(ex_root)
	var escroll := ScrollContainer.new()
	escroll.custom_minimum_size = Vector2(750, 520)
	escroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ex_root.add_child(escroll)
	ex_list = VBoxContainer.new()
	ex_list.add_theme_constant_override("separation", 5)
	ex_list.custom_minimum_size = Vector2(730, 0)
	escroll.add_child(ex_list)

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
	status_label.text = "翡翠港（%s）· %s·%s · 金币 %d · 战功 %d · 船体 %.0f/%.0f · 货舱 %.0f/%.0f · %s" % [
		GameState.home_port_name(),
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
	ex_root.visible = false
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
		c.queue_free()
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var max_stock := int(port.max_stock) if port != null else 800
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

	# 交易目标页签：买入存到哪 / 卖出从哪拿
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	market_list.add_child(tab_row)
	var tl := Label.new()
	tl.text = "交易目标："
	tl.custom_minimum_size = Vector2(84, 0)
	tab_row.add_child(tl)
	var b_ship := Button.new()
	b_ship.text = "装船" if market_target == "ship" else "装船"
	b_ship.custom_minimum_size = Vector2(96, 34)
	b_ship.modulate = Color(1.0, 0.92, 0.6) if market_target == "ship" else Color(1, 1, 1)
	b_ship.pressed.connect(func(): _toggle_market_target("ship"))
	tab_row.add_child(b_ship)
	var b_wh := Button.new()
	b_wh.text = "存仓"
	b_wh.custom_minimum_size = Vector2(96, 34)
	b_wh.modulate = Color(1.0, 0.92, 0.6) if market_target == "warehouse" else Color(1, 1, 1)
	b_wh.pressed.connect(func(): _toggle_market_target("warehouse"))
	tab_row.add_child(b_wh)
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
		var stock := GameState.ensure_stock(PORT_ID, id, max_stock)
		var demand := 1.0
		var production := 1.0
		if port != null:
			demand = float(port.demand.get(String(id), 1.0))
			production = float(port.production.get(String(id), 1.0))
		var mod := GameState.price_modifier(String(PORT_ID), id)
		var rep_disc := GameState.rep_discount()
		var bp := int(round(float(MarketModel.buy_price(c.base_price, stock, max_stock, demand))
			* mod * (1.0 - rep_disc)))
		var sp := int(round(float(MarketModel.sell_price(c.base_price, stock, max_stock, production))
			* (1.0 + GameState.sell_bonus()) * mod))
		var chg := GameState.price_change_pct(String(PORT_ID), id)
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
		if GameState.has_price_history(String(PORT_ID), id):
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
	_add_market_metrics(String(PORT_ID))

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
	if key == String(PORT_ID):
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
	var pk := String(PORT_ID)
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
	for cid in [&"grain", &"timber", &"rum", &"spice"]:
		var c: Resource = DataRegistry.get_commodity(cid)
		if c == null:
			continue
		var max_stock := 400
		var stock := GameState.ensure_stock(PORT_ID, cid, max_stock)
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
		for cid in [&"grain", &"timber", &"rum", &"spice"]:
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
			var lstock := GameState.ensure_stock(PORT_ID, &"grain", 400)
			local_buy = int(round(float(MarketModel.buy_price(cg.base_price, lstock, 400, 1.0))
				* GameState.price_modifier(String(PORT_ID), &"grain")))
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
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var stock := GameState.ensure_stock(PORT_ID, cid, int(port.max_stock))
	if stock < amount:
		_log("该港库存不足")
		return
	GameState.add_gold(-total)
	GameState.set_stock(PORT_ID, cid, stock - amount)
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
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var stock := GameState.ensure_stock(PORT_ID, cid, int(port.max_stock))
	if from_wh:
		GameState.warehouse_remove(cid, amount)
	else:
		GameState.remove_cargo(cid, amount)
	GameState.set_stock(PORT_ID, cid, stock + amount)
	# 关税：在非母港卖出按 5% 扣除
	var gross := price * amount
	var tax := 0
	if String(PORT_ID) != "jadehaven":
		tax = int(round(float(gross) * GameState.tariff_rate()))
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
	ex_root.visible = false
	_rebuild_yard()
	yard_root.visible = true

# ---------------- 声望 / 战功 / 帮助 / 通关 ----------------

func _close_all_panels() -> void:
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
	var r: Dictionary = GameState.buy_license_legal()
	if bool(r.get("ok", false)):
		_log("取得正规私掠许可证")
		_rebuild_rep()
		_refresh()
	else:
		_log(String(r.get("reason", "购买失败")))

func _rebuild_rep() -> void:
	for c in rep_list.get_children():
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
		lhb.add_child(_lbl("需海军声望 %d" % int(GameState.LEGAL_LICENSE_REP), 200,
			Color(0.8, 0.85, 0.8)))
		var lprice := int(GameState.LEGAL_LICENSE_REP) * 2
		lhb.add_child(_lbl("%d 金" % lprice, 120, Color(0.9, 0.82, 0.45)))
		var lb := Button.new()
		lb.text = "购买"
		lb.custom_minimum_size = Vector2(80, 26)
		lb.disabled = GameState.rep_of("royal_navy") < int(GameState.LEGAL_LICENSE_REP) or GameState.gold < lprice
		lb.pressed.connect(func(): _buy_license_legal())
		lhb.add_child(lb)
		var hint := Label.new()
		hint.text = "　持有后劫掠敌对阵营商船不降海军声望"
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
		rep_list.add_child(hint)

	_yard_title_to(rep_list, "三阵营声望（0~10000）")
	for fac in GameState.FACTIONS:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		rep_list.add_child(hb)
		hb.add_child(_lbl(String(GameState.FACTION_NAMES[fac]), 110, Color(0.8, 0.85, 0.8)))
		hb.add_child(_lbl("%d（%s）" % [GameState.rep_of(fac), GameState.rep_level_name(fac)], 180,
			Color(0.9, 0.82, 0.45)))
		var used := int(GameState.donated_week.get(fac, 0))
		var b := Button.new()
		b.text = "捐赠 1000 金"
		b.disabled = GameState.gold < 1000 or used >= 5000
		b.custom_minimum_size = Vector2(130, 26)
		var fac_v := String(fac)
		b.pressed.connect(func(): _do_donate(fac_v))
		hb.add_child(b)
		hb.add_child(_lbl("本周额度 %d/5000" % used, 150, Color(0.6, 0.65, 0.6)))

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

const EX_TABS := ["行情", "远洋订单", "大宗交易", "期货"]

func _toggle_quests() -> void:
	if quest_root.visible:
		quest_root.visible = false
		return
	market_root.visible = false
	yard_root.visible = false
	tavern_root.visible = false
	build_root.visible = false
	ex_root.visible = false
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

func _toggle_exchange() -> void:
	if ex_root.visible:
		ex_root.visible = false
		return
	market_root.visible = false
	yard_root.visible = false
	tavern_root.visible = false
	build_root.visible = false
	if GameState.orders.is_empty():
		GameState.refresh_orders()
	_rebuild_exchange()
	ex_root.visible = true

func _rebuild_exchange() -> void:
	for c in ex_list.get_children():
		c.queue_free()
	_yard_title_to(ex_list, "交易所 Lv%d —— 金币 %d" % [GameState.exchange_level(), GameState.gold])

	var tab_hb := HBoxContainer.new()
	tab_hb.add_theme_constant_override("separation", 8)
	ex_list.add_child(tab_hb)
	for i in range(EX_TABS.size()):
		var b := Button.new()
		var unlocked: bool = GameState.exchange_tab_unlocked(i)
		b.text = EX_TABS[i] if unlocked else "%s(Lv%d)" % [EX_TABS[i], i + 1]
		b.disabled = not unlocked
		if i == ex_tab:
			b.modulate = Color(1.2, 1.1, 0.7)
		b.custom_minimum_size = Vector2(160, 32)
		var idx := i
		b.pressed.connect(func(): _switch_ex_tab(idx))
		tab_hb.add_child(b)

	if not GameState.exchange_tab_unlocked(0):
		ex_list.add_child(_lbl("交易所尚未建成，先到「基地建设」把交易所升到 1 级。", 600, Color(0.8, 0.6, 0.4)))

	match ex_tab:
		0: _ex_quotes()
		1: _ex_orders()
		2: _ex_bulk()
		3: _ex_futures()

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 32)
	close.pressed.connect(func(): ex_root.visible = false)
	ex_list.add_child(close)

func _switch_ex_tab(idx: int) -> void:
	ex_tab = idx
	_rebuild_exchange()

func _ex_quotes() -> void:
	if not GameState.exchange_tab_unlocked(0):
		return
	_yard_title_to(ex_list, "各地行情")
	for pid in DataRegistry.ports.keys():
		var p: Resource = DataRegistry.ports[pid]
		ex_list.add_child(_lbl("· %s" % p.display_name, 400, Color(0.8, 0.85, 0.7)))
		for cid in DataRegistry.commodities.keys():
			var c: Resource = DataRegistry.get_commodity(cid)
			var stock := GameState.ensure_stock(pid, cid, int(p.max_stock))
			var demand := float(p.demand.get(String(cid), 1.0))
			var production := float(p.production.get(String(cid), 1.0))
			var bp := MarketModel.buy_price(int(c.base_price), stock, int(p.max_stock), demand)
			var sp := MarketModel.sell_price(int(c.base_price), stock, int(p.max_stock), production)
			ex_list.add_child(_lbl("    %s　买 %d / 卖 %d（库存 %d）" % [c.display_name, bp, sp, stock], 520,
				Color(0.75, 0.8, 0.75)))

func _ex_orders() -> void:
	if not GameState.exchange_tab_unlocked(1):
		return
	_yard_title_to(ex_list, "可接订单（每周刷新）")
	if GameState.orders.is_empty():
		ex_list.add_child(_lbl("　（本周没有订单）", 400, Color(0.5, 0.55, 0.55)))
	for i in range(GameState.orders.size()):
		var o: Dictionary = GameState.orders[i]
		var c: Resource = DataRegistry.get_commodity(StringName(o.commodity))
		var p: Resource = DataRegistry.get_port(StringName(o.dest))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		ex_list.add_child(hb)
		hb.add_child(_lbl("%s × %d → %s" % [c.display_name, int(o.amount), p.display_name], 300))
		hb.add_child(_lbl("锁定价 %d/单位" % int(o.price), 160, Color(0.9, 0.82, 0.45)))
		hb.add_child(_lbl("期限 %d 周" % int(o.weeks_left), 120))
		var idx := i
		var b := Button.new()
		b.text = "接受"
		b.custom_minimum_size = Vector2(80, 26)
		b.pressed.connect(func(): _accept_order(idx))
		hb.add_child(b)

	_yard_title_to(ex_list, "进行中的订单")
	if GameState.active_orders.is_empty():
		ex_list.add_child(_lbl("　（没有进行中的订单）", 400, Color(0.5, 0.55, 0.55)))
	for i in range(GameState.active_orders.size()):
		var o2: Dictionary = GameState.active_orders[i]
		var c2: Resource = DataRegistry.get_commodity(StringName(o2.commodity))
		var p2: Resource = DataRegistry.get_port(StringName(o2.dest))
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 10)
		ex_list.add_child(hb2)
		hb2.add_child(_lbl("%s × %d → %s" % [c2.display_name, int(o2.amount), p2.display_name], 300))
		hb2.add_child(_lbl("剩 %d 周" % int(o2.weeks_left), 120))
		var idx2 := i
		var b2 := Button.new()
		b2.text = "在本港交付"
		b2.custom_minimum_size = Vector2(110, 26)
		b2.pressed.connect(func(): _deliver_order(idx2, PORT_ID))
		hb2.add_child(b2)

func _accept_order(idx: int) -> void:
	if GameState.accept_order(idx):
		_log("已接受远洋订单")
		_rebuild_exchange()

func _deliver_order(idx: int, port_id: StringName) -> void:
	var res: Dictionary = GameState.deliver_order(idx, port_id)
	if res.get("ok", false):
		_log("交付完成，获得 %d 金" % int(res.gold))
	else:
		_log(String(res.get("reason", "交付失败")))
	_rebuild_exchange()
	_refresh()

func _ex_bulk() -> void:
	if not GameState.exchange_tab_unlocked(2):
		return
	_yard_title_to(ex_list, "大宗交易（满 100 单位享 5% 折扣）")
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var max_stock := int(port.max_stock)
	for cid in DataRegistry.commodities.keys():
		var c: Resource = DataRegistry.get_commodity(cid)
		var stock := GameState.ensure_stock(PORT_ID, cid, max_stock)
		var demand := float(port.demand.get(String(cid), 1.0))
		var bp := int(round(float(MarketModel.buy_price(int(c.base_price), stock, max_stock, demand)) * 0.95))
		var sp := int(round(float(MarketModel.sell_price(int(c.base_price), stock, max_stock,
			float(port.production.get(String(cid), 1.0)))) * (1.0 + GameState.sell_bonus())))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		ex_list.add_child(hb)
		hb.add_child(_lbl(c.display_name, 90))
		hb.add_child(_lbl("买 100：%d 金" % (bp * 100), 180, Color(0.9, 0.82, 0.45)))
		hb.add_child(_lbl("卖 100：%d 金" % (sp * 100), 180))
		var cid_v: StringName = cid
		var b1 := Button.new()
		b1.text = "买入 100"
		b1.custom_minimum_size = Vector2(90, 26)
		b1.pressed.connect(func(): _bulk_trade(cid_v, 100, bp, true))
		hb.add_child(b1)
		var b2 := Button.new()
		b2.text = "卖出 100"
		b2.custom_minimum_size = Vector2(90, 26)
		b2.pressed.connect(func(): _bulk_trade(cid_v, 100, sp, false))
		hb.add_child(b2)

func _bulk_trade(cid: StringName, amount: int, price: int, buying: bool) -> void:
	if buying:
		_buy(cid, amount, price)
	else:
		_sell(cid, amount, price)
	_rebuild_exchange()

func _ex_futures() -> void:
	if not GameState.exchange_tab_unlocked(3):
		return
	_yard_title_to(ex_list, "期货（付 20% 定金锁定本周价格，1 周内提货）")
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var max_stock := int(port.max_stock)
	for cid in DataRegistry.commodities.keys():
		var c: Resource = DataRegistry.get_commodity(cid)
		var stock := GameState.ensure_stock(PORT_ID, cid, max_stock)
		var bp := MarketModel.buy_price(int(c.base_price), stock, max_stock)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		ex_list.add_child(hb)
		hb.add_child(_lbl(c.display_name, 90))
		hb.add_child(_lbl("现价 %d · 锁 100 单位定金 %d" % [bp, int(round(float(bp * 100) * 0.2))], 320))
		var cid_v: StringName = cid
		var b := Button.new()
		b.text = "锁定"
		b.custom_minimum_size = Vector2(80, 26)
		b.pressed.connect(func(): _lock_future(cid_v, 100))
		hb.add_child(b)

	_yard_title_to(ex_list, "我的合约")
	if GameState.futures.is_empty():
		ex_list.add_child(_lbl("　（没有合约）", 400, Color(0.5, 0.55, 0.55)))
	for i in range(GameState.futures.size()):
		var fu: Dictionary = GameState.futures[i]
		var c2: Resource = DataRegistry.get_commodity(StringName(fu.commodity))
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 10)
		ex_list.add_child(hb2)
		hb2.add_child(_lbl("%s × %d @ %d" % [c2.display_name, int(fu.amount), int(fu.price)], 280))
		hb2.add_child(_lbl("剩 %d 周" % int(fu.weeks_left), 120))
		var idx := i
		var b2 := Button.new()
		b2.text = "付尾款提货"
		b2.custom_minimum_size = Vector2(120, 26)
		b2.pressed.connect(func(): _redeem_future(idx))
		hb2.add_child(b2)

func _lock_future(cid: StringName, amount: int) -> void:
	var res: Dictionary = GameState.lock_future(cid, amount)
	if res.get("ok", false):
		_log("锁定合约，定金 %d 金" % int(res.deposit))
	else:
		_log(String(res.get("reason", "失败")))
	_rebuild_exchange()
	_refresh()

func _redeem_future(idx: int) -> void:
	var res: Dictionary = GameState.redeem_future(idx)
	if res.get("ok", false):
		_log("提货完成，支付尾款 %d 金" % int(res.gold))
	else:
		_log(String(res.get("reason", "失败")))
	_rebuild_exchange()
	_refresh()

func _toggle_build() -> void:
	if build_root.visible:
		build_root.visible = false
		return
	market_root.visible = false
	yard_root.visible = false
	tavern_root.visible = false
	ex_root.visible = false
	_rebuild_build()
	build_root.visible = true

func _res_line() -> String:
	var r := GameState.resources
	return "木材 %d · 铁矿 %d · 粮食 %d · 硝石 %d" % [
		int(r.get("timber", 0)), int(r.get("iron", 0)),
		int(r.get("grain", 0)), int(r.get("saltpeter", 0)),
	]

func _rebuild_build() -> void:
	for c in build_list.get_children():
		c.queue_free()
	_yard_title_to(build_list, "基地建设 —— " + _res_line())
	var prod: Dictionary = GameState.total_production()
	build_list.add_child(_lbl("每周产出：木材 +%d · 铁矿 +%d · 粮食 +%d · 硝石 +%d" % [
		int(prod.get("timber", 0)), int(prod.get("iron", 0)),
		int(prod.get("grain", 0)), int(prod.get("saltpeter", 0)),
	], 520, Color(0.6, 0.8, 0.65)))

	if not GameState.build_queue.is_empty():
		_yard_title_to(build_list, "建造中")
		for q in GameState.build_queue:
			var bd: Resource = DataRegistry.get_building(StringName(q.get("id", "")))
			var nm: String = bd.display_name if bd != null else String(q.get("id", ""))
			build_list.add_child(_lbl("%s → Lv%d　剩余 %d 周" % [nm, int(q.get("target", 1)), int(q.get("weeks_left", 1))],
				460, Color(0.9, 0.85, 0.55)))

	_yard_title_to(build_list, "建筑")
	var ids: Array = DataRegistry.buildings.keys()
	ids.sort()
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
		var bb := Button.new()
		var busy: bool = GameState.is_building(bid)
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
	ex_root.visible = false
	if GameState.tavern_pool.is_empty():
		GameState.refresh_tavern()
	_rebuild_tavern()
	tavern_root.visible = true

func _rebuild_tavern() -> void:
	for c in tavern_list.get_children():
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
		c.queue_free()
	var c: Resource = DataRegistry.get_commodity(goods_cid)
	if c == null:
		return
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var port2: Resource = DataRegistry.get_port(PORT_ID)
	var max_stock := int(port2.max_stock) if port2 != null else 800
	var stock := GameState.ensure_stock(PORT_ID, goods_cid, max_stock)
	var demand := 1.0
	if port != null:
		demand = float(port.demand.get(String(goods_cid), 1.0))
	var mod := GameState.price_modifier(String(PORT_ID), goods_cid)
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
	var cur: float = eq * GameState.price_drift_of(String(PORT_ID), goods_cid)
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
			eq, GameState.price_drift_of(String(PORT_ID), goods_cid), cur]],
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
			var port3: Resource = DataRegistry.get_port(PORT_ID)
			var ms := int(port3.max_stock) if port3 != null else 800
			GameState.ensure_stock(PORT_ID, goods_cid, ms)
			GameState.port_stock[PORT_ID][goods_cid] = maxi(0, int(GameState.port_stock[PORT_ID][goods_cid]) - goods_qty)
			dlg.queue_free()
			_rebuild_goods())
	dlg.popup_centered()

func _chart_data(cid: StringName, base_price: int, stock: int, max_stock: int) -> Dictionary:
	var d := {}
	d["history"] = GameState.price_history_of(String(PORT_ID), cid)
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

# ---------------- 建造与投资（1.1） ----------------


func _toggle_construct() -> void:
	if construct_root.visible:
		construct_root.visible = false
		return
	_rebuild_construct()
	construct_root.visible = true

func _rebuild_construct() -> void:
	for c in construct_list.get_children():
		c.queue_free()
	var tier := GameState.home_port_tier
	var prefix := "翡翠港"
	var next_tier := mini(3, tier + 1)
	_yard_title_to(construct_list, "建造 · %s → %s" % [
		GameState.town_name(prefix, tier), GameState.town_name(prefix, next_tier)])
	if tier >= 3:
		construct_list.add_child(_lbl("　已是最高等级（港城）", 500, Color(0.75, 0.85, 0.7)))
		return
	var prog: Dictionary = GameState.build_progress("jadehaven", tier)
	var need: Dictionary = prog["need"]
	var have: Dictionary = prog["have"]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	construct_list.add_child(head)
	for spec in [["项目", 200], ["需求", 140], ["船上", 140], ["仓库", 140], ["已提交", 140], ["操作", 160]]:
		head.add_child(_cell_box(String(spec[0]), int(spec[1]), Color(0.62, 0.78, 0.85), true))
	for m in need.keys():
		var mat := String(m)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		construct_list.add_child(row)
		var nm := "金币" if mat == "gold" else mat
		if mat != "gold":
			var cd: Resource = DataRegistry.get_commodity(StringName(mat))
			if cd != null:
				nm = String(cd.display_name)
		var in_ship := 0
		var in_wh := 0
		if mat == "gold":
			in_ship = GameState.gold
			in_wh = GameState.bank_deposited()
		else:
			in_ship = int(GameState.cargo.get(StringName(mat), 0))
			in_wh = int(GameState.warehouse.get(StringName(mat), 0))
		row.add_child(_cell_box(nm, 200))
		row.add_child(_cell_box(str(int(need[m])), 140, Color(0.95, 0.9, 0.55)))
		row.add_child(_cell_box(str(in_ship), 140))
		row.add_child(_cell_box(str(in_wh), 140))
		row.add_child(_cell_box(str(int(have.get(m, 0))), 140, Color(0.6, 0.85, 0.7)))
		var btn_box := PanelContainer.new()
		btn_box.custom_minimum_size = Vector2(160, 30)
		var sub := Button.new()
		sub.text = "提交"
		sub.custom_minimum_size = Vector2(120, 26)
		var mv := String(mat)
		var need_v := int(need[m])
		sub.pressed.connect(func(): _open_submit(mv, need_v, in_ship, in_wh))
		btn_box.add_child(sub)
		row.add_child(btn_box)
	var ready := bool(prog["ready"])
	var up := Button.new()
	up.text = "确认升级"
	up.custom_minimum_size = Vector2(180, 34)
	up.disabled = not ready
	up.pressed.connect(func(): _do_build_upgrade())
	construct_list.add_child(up)

func _do_build_upgrade() -> void:
	if GameState.home_port_tier >= 3:
		return
	GameState.home_port_tier += 1
	GameState.build_submitted.clear()
	_log("建造完成：白帆%s" % GameState.town_suffix(GameState.home_port_tier))
	_rebuild_construct()

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
	var e1 := LineEdit.new()
	e1.text = str(mini(in_ship, need))
	e1.custom_minimum_size = Vector2(120, 30)
	row1.add_child(e1)
	var row2 := HBoxContainer.new()
	vb.add_child(row2)
	row2.add_child(_lbl("仓库提交", 110))
	var e2 := LineEdit.new()
	e2.text = "0"
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

const FULL_PANELS := ["market_root", "yard_root", "tavern_root", "build_root", "ex_root",
	"quest_root", "overview_root", "finance_root", "bank_root", "black_root",
	"save_root", "rep_root", "help_root", "victory_root", "construct_root", "goods_root"]

var close_btn: Button = null
var construct_root: PanelContainer = null
var construct_list: VBoxContainer = null

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
	for c in bank_list.get_children():
		c.queue_free()
	_rebuild_bank_rows()

func _rebuild_bank_rows() -> void:
	_yard_title_to(bank_list, "银行 —— 现金 %d · 全城通存通取" % GameState.gold)
	_yard_title_to(bank_list, "存款 %d（周息 0.1%%，每月结算）" % GameState.bank_deposited())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bank_list.add_child(hb)
	for amt in [1000, 10000]:
		var db := Button.new()
		db.text = "存入 %d" % amt
		db.custom_minimum_size = Vector2(110, 30)
		db.disabled = GameState.gold < amt
		var av: int = amt
		db.pressed.connect(func(): _bank_deposit(av))
		hb.add_child(db)
	var wb := Button.new()
	wb.text = "全部取出"
	wb.custom_minimum_size = Vector2(110, 30)
	wb.disabled = GameState.bank_deposited() <= 0
	wb.pressed.connect(func(): _bank_withdraw_all())
	hb.add_child(wb)

	_yard_title_to(bank_list, "未还贷款 %d / %d 笔 · 未还本息 %d" % [
		GameState.loan_count(), int(GameState.MAX_LOANS), GameState.loan_exposure()])
	if GameState.loans.is_empty():
		bank_list.add_child(_lbl("　（没有未还贷款）", 400, Color(0.5, 0.55, 0.55)))
	for i in range(GameState.loans.size()):
		var l: Dictionary = GameState.loans[i]
		var lhb := HBoxContainer.new()
		lhb.add_theme_constant_override("separation", 10)
		bank_list.add_child(lhb)
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
		bank_list.add_child(ab)

	_yard_title_to(bank_list, "新增贷款（本息总额不得超过存款 %d）" % GameState.bank_deposited())
	var term_names := {12: "一季", 26: "半年", 52: "一年"}
	for amount in GameState.LOAN_TIERS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		bank_list.add_child(row)
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

func _rebuild_black() -> void:
	for c in black_list.get_children():
		c.queue_free()
	_yard_title_to(black_list, "黑市 —— 现金 %d · 通缉度 %d" % [GameState.gold, GameState.notoriety()])
	if not GameState.black_market_open():
		black_list.add_child(_lbl("　通缉度过高，黑市本周关闭", 500, Color(0.9, 0.5, 0.45)))
		return
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
		if String(entry.get("station_port", "")) != String(PORT_ID):
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
	ex_root.visible = false
	quest_root.visible = false
	_rebuild_save()
	save_root.visible = true

func _rebuild_save() -> void:
	for c in save_list.get_children():
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
