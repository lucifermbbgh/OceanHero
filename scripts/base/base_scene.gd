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
	_action_button(vb, "修理船只", _do_repair)
	_action_button(vb, "市场交易", _toggle_market)
	_action_button(vb, "船厂与装备", _toggle_yard)
	_action_button(vb, "酒馆招募", _toggle_tavern)
	_action_button(vb, "基地建设", _toggle_build)
	_action_button(vb, "交易所", _toggle_exchange)
	_action_button(vb, "任务板", _toggle_quests)
	_action_button(vb, "声望与战功", _toggle_rep)
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
	market_root.position = Vector2(280, 80)
	market_root.custom_minimum_size = Vector2(560, 420)
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
	status_label.text = "翡翠港 · %s·%s · 金币 %d · 战功 %d · 船体 %.0f/%.0f · 货舱 %.0f/%.0f · %s" % [
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

func _rebuild_market() -> void:
	for c in market_list.get_children():
		c.queue_free()
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var max_stock := int(port.max_stock) if port != null else 800
	var head := Label.new()
	head.text = "市场行情（每周库存会向满值回归）"
	head.add_theme_font_size_override("font_size", 18)
	market_list.add_child(head)
	for id in [&"grain", &"timber", &"rum", &"spice"]:
		var c: Resource = DataRegistry.get_commodity(id)
		if c == null:
			continue
		var stock := GameState.ensure_stock(PORT_ID, id, max_stock)
		var demand := 1.0
		var production := 1.0
		if port != null:
			demand = float(port.demand.get(String(id), 1.0))
			production = float(port.production.get(String(id), 1.0))
		var bp := MarketModel.buy_price(c.base_price, stock, max_stock, demand)
		var sp := int(round(float(MarketModel.sell_price(c.base_price, stock, max_stock, production))
			* (1.0 + GameState.sell_bonus())))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		market_list.add_child(row)
		var name_l := Label.new()
		name_l.text = c.display_name
		name_l.custom_minimum_size = Vector2(90, 0)
		row.add_child(name_l)
		var price_l := Label.new()
		var have := int(GameState.cargo.get(id, 0))
		price_l.text = "买 %d / 卖 %d   港口库存 %d｜船上 %d" % [bp, sp, stock, have]
		price_l.custom_minimum_size = Vector2(240, 0)
		row.add_child(price_l)
		var b_buy := Button.new()
		b_buy.text = "买10"
		b_buy.custom_minimum_size = Vector2(72, 32)
		var cid: StringName = id
		b_buy.pressed.connect(func(): _buy(cid, 10, bp))
		row.add_child(b_buy)
		var b_sell := Button.new()
		b_sell.text = "卖10"
		b_sell.custom_minimum_size = Vector2(72, 32)
		b_sell.pressed.connect(func(): _sell(cid, 10, sp))
		row.add_child(b_sell)
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
	var tip := Label.new()
	tip.text = "买到的货物直接装船，随船航行；卖货请到目标港口。"
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
	market_list.add_child(tip)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(120, 34)
	close.pressed.connect(func(): market_root.visible = false)
	market_list.add_child(close)

func _buy(cid: StringName, amount: int, price: int) -> void:
	var c: Resource = DataRegistry.get_commodity(cid)
	var total := price * amount
	if GameState.gold < total:
		_log("金币不足，需要 %d 金" % total)
		return
	if GameState.cargo_free() < float(c.volume) * amount:
		_log("货舱空间不足")
		return
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var stock := GameState.ensure_stock(PORT_ID, cid, int(port.max_stock))
	if stock < amount:
		_log("该港库存不足")
		return
	GameState.add_gold(-total)
	GameState.set_stock(PORT_ID, cid, stock - amount)
	GameState.add_cargo(cid, amount)
	_log("买入 %d %s，花费 %d 金" % [amount, c.display_name, total])
	_rebuild_market()
	_refresh()

func _sell(cid: StringName, amount: int, price: int) -> void:
	var have := int(GameState.cargo.get(cid, 0))
	if have < amount:
		_log("货舱里没有足够的该商品")
		return
	var c: Resource = DataRegistry.get_commodity(cid)
	var port: Resource = DataRegistry.get_port(PORT_ID)
	var stock := GameState.ensure_stock(PORT_ID, cid, int(port.max_stock))
	GameState.remove_cargo(cid, amount)
	GameState.set_stock(PORT_ID, cid, stock + amount)
	GameState.add_gold(price * amount)
	var margin := maxi(0, price * amount - int(c.base_price) * amount)
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
	market_root.visible = false
	yard_root.visible = false
	tavern_root.visible = false
	build_root.visible = false
	ex_root.visible = false
	quest_root.visible = false
	save_root.visible = false
	rep_root.visible = false
	help_root.visible = false

func _toggle_rep() -> void:
	if rep_root.visible:
		rep_root.visible = false
		return
	_close_all_panels()
	_rebuild_rep()
	rep_root.visible = true

func _rebuild_rep() -> void:
	for c in rep_list.get_children():
		c.queue_free()
	_yard_title_to(rep_list, "声望与战功 —— 战功 %d · 通缉度 %d" % [GameState.commendation, GameState.notoriety()])

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

func _rebuild_quests() -> void:
	for c in quest_list.get_children():
		c.queue_free()
	_yard_title_to(quest_list, "任务板 —— 进行中 %d/3 · 通缉度 %d" % [
		GameState.quests_active.size(), GameState.notoriety()])

	_yard_title_to(quest_list, "进行中")
	if GameState.quests_active.is_empty():
		quest_list.add_child(_lbl("　（没有进行中的任务）", 400, Color(0.5, 0.55, 0.55)))
	for q in GameState.quests_active:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		quest_list.add_child(hb)
		hb.add_child(_lbl(String(q.get("title", "")), 340))
		hb.add_child(_lbl("%d / %d" % [int(q.get("progress", 0)), int(q.get("amount", 1))], 110,
			Color(0.75, 0.85, 0.6)))
		hb.add_child(_lbl("+%d 金" % int(q.get("reward_gold", 0)), 120, Color(0.9, 0.82, 0.45)))

	_yard_title_to(quest_list, "可接任务（每周刷新）")
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
	if _log_timer > 0.0:
		_log_timer -= delta
		if _log_timer <= 0.0:
			log_label.text = ""
