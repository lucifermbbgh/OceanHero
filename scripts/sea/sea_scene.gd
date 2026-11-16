extends Node2D
## 海域场景（阶段一：仅图 1）。

const ShipScene = preload("res://scenes/ship/sea_ship.tscn")
const MonsterScene = preload("res://scenes/ship/sea_monster.tscn")
const SeaHud = preload("res://scripts/ui/sea_hud.gd")
const LootSystem = preload("res://scripts/systems/loot_system.gd")
const CombatResolver = preload("res://scripts/systems/combat_resolver.gd")
const MarketModel = preload("res://scripts/systems/market_model.gd")
const Rarity = preload("res://scripts/ui/rarity.gd")
const StatsLib = preload("res://scripts/systems/ship_stats.gd")

const OUTPOST_ID := &"map1_outpost"

const SEA_SIZE := 8000.0
const BACK_GATE := Vector2(4000, 420)
const FORWARD_GATE := Vector2(4000, 7580)
const BOSS_PIRATE_POS := Vector2(6250, 2050)
const BOSS_MONSTER_POS := Vector2(1900, 6150)

var map_index := 1
var map_def: Resource = null
## 岛屿：[中心, 半径]，每张图按种子确定性生成
var islands: Array = []
const AVOID_MARGIN := 150.0
const PUSH_STRENGTH := 900.0
var ground_cooldown := 0.0

var player
var camera: Camera2D
var hud
var enemies: Array = []
var spawn_timer := 6.0
var outpost_pos := Vector2(3400, 5050)
var port_ui: CanvasLayer
var port_panel: PanelContainer
var port_list: VBoxContainer
## 同屏单位上限（超过就不再刷新，避免越打越多）
const MAX_UNITS := 28
## 阵营敌对关系
const FACTION_ENEMIES := {
	"navy": ["pirate"],
	"pirate": ["navy", "merchant", "player"],
	"merchant": [],
}
const AI_TICK := 0.6
## 刷新与密度控制
const SPAWN_MARGIN := 300.0
const PLAYER_SAFE_RADIUS := 1150.0   # 玩家出生点周围不刷怪（略大于 1 倍射程，避免一进场就挨打）
const NEAR_RING_MIN := 1150.0        # 视野边缘"迎接"单位的距离带
const NEAR_RING_MAX := 1650.0
const NEAR_UNITS := 3                # 出生点附近保留几个单位，避免一进场面对空海
const DENSITY_CELL := 2000.0         # 密度网格边长
const MAX_PER_CELL := 3              # 单个网格内的单位上限
const MAX_ATTACKERS_ON_PLAYER := 3   # 同时追打玩家的单位上限
## 采样：最小间距 + 迎接单位的扇区分层
const MIN_SEPARATION := 420.0
const NEAR_SECTORS := 6              # 环带按 6 个扇区分层，每个迎接单位占不同扇区

var hunter_timer := 45.0
var ai_timer := 0.0
var _near_sector := 0
var salvages: Array = []
var escort_ship = null
var boarded := false
var boarding_target = null
var boarding_tick := 0.0
var game_over := false

func _ready() -> void:
	GameState.ensure_ship()
	name = "SeaScene"
	map_index = clampi(GameState.current_map, 1, 9)
	map_def = DataRegistry.get_map(map_index)
	_generate_islands()
	_build_world()
	_spawn_player()
	_build_camera()
	_build_hud()
	_build_port_ui()
	var pd: Resource = DataRegistry.get_port(OUTPOST_ID)
	if pd != null:
		outpost_pos = pd.position
	_spawn_map_contents()
	_spawn_salvages()
	_spawn_escort_if_needed()
	var map_name := String(map_def.display_name) if map_def != null else "未知海域"
	hud.ticker("%s · 用 A/D 转舵，点击敌船锁定后自动开火" % map_name)

func _generate_islands() -> void:
	islands.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map_def.island_seed) * 7919 + map_index * 131
	var n := 4 + (map_index % 3)
	var safe_center := Vector2(SEA_SIZE * 0.5, SEA_SIZE * 0.5 + 300)
	for i in range(n):
		var pos := Vector2(rng.randf_range(1400.0, 6600.0), rng.randf_range(1400.0, 6600.0))
		if pos.distance_to(safe_center) < 800.0:
			pos = pos.lerp(Vector2(6600, 6600), 0.6)
		if pos.distance_to(BACK_GATE) < 500.0 or pos.distance_to(FORWARD_GATE) < 500.0:
			pos = pos.lerp(Vector2(1600, 4000), 0.5)
		islands.append([pos, rng.randf_range(260.0, 460.0)])

func _spawn_map_contents() -> void:
	var pirates := int(map_def.pirates) if map_def != null else 4
	var monsters := int(map_def.monsters) if map_def != null else 2
	for i in range(pirates):
		_spawn_pirate()
	for i in range(monsters):
		_spawn_monster()
	# Boss：同图各一只，已击败则不再刷新
	# 3 图以上加入生态：海军巡逻 + 中立商船
	if map_def != null and bool(map_def.hostile):
		_spawn_navy_patrol()
		_spawn_navy_patrol()
		_spawn_merchant()
		_spawn_merchant()
	if map_def != null:
		var pb: StringName = map_def.pirate_boss
		if String(pb) != "" and not GameState.is_boss_defeated(pb):
			_spawn_boss(pb, BOSS_PIRATE_POS, false)
		var mb: StringName = map_def.monster_boss
		if String(mb) != "" and not GameState.is_boss_defeated(mb):
			_spawn_boss(mb, BOSS_MONSTER_POS, true)

func _spawn_boss(enemy_id: StringName, pos: Vector2, is_monster: bool) -> void:
	var edef: Resource = DataRegistry.get_enemy(enemy_id)
	if edef == null:
		return
	if is_monster:
		var m = MonsterScene.instantiate()
		m.setup(edef)
		m.position = pos
		m.scale = Vector2(1.8, 1.8)
		m.is_boss = true
		m.loot_mult = _loot_mult()
		m.died.connect(_on_enemy_died)
		add_child(m)
		enemies.append(m)
	else:
		var e = ShipScene.instantiate()
		e.setup_enemy(edef, _map_scale())
		e.position = pos
		e.scale = Vector2(1.7, 1.7)
		e.is_boss = true
		e.loot_mult = _loot_mult()
		e.died.connect(_on_enemy_died)
		e.disengaged.connect(_on_enemy_disengaged)
		add_child(e)
		enemies.append(e)
	hud.ticker("发现 Boss：%s" % String(edef.display_name))

func _map_name(index: int) -> String:
	if index <= 0:
		return "翡翠港"
	var m: Resource = DataRegistry.get_map(index)
	return String(m.display_name) if m != null else "海域 %d" % index

func _level_scale(level: int) -> float:
	return 1.0 + float(maxi(0, level - 1)) * 0.10

func _build_world() -> void:
	z_index = 0
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, SEA_SIZE, SEA_SIZE), Color(0.07, 0.19, 0.24))
	# 波纹（确定性位置，避免破坏随机序列）
	var wy := 300.0
	while wy < SEA_SIZE:
		var wx := 200.0
		while wx < SEA_SIZE:
			var off: float = sin(wx * 0.013 + wy * 0.007) * 26.0
			draw_arc(Vector2(wx + off, wy), 22.0, PI * 0.15, PI * 0.85, 8, Color(0.11, 0.27, 0.33), 2.0)
			wx += 460.0
		wy += 380.0
	# 网格
	var step := 500.0
	var grid_col := Color(0.10, 0.25, 0.31)
	var x := 0.0
	while x <= SEA_SIZE:
		draw_line(Vector2(x, 0), Vector2(x, SEA_SIZE), grid_col, 2.0)
		x += step
	var y := 0.0
	while y <= SEA_SIZE:
		draw_line(Vector2(0, y), Vector2(SEA_SIZE, y), grid_col, 2.0)
		y += step
	# 地图边界
	draw_rect(Rect2(40, 40, SEA_SIZE - 80, SEA_SIZE - 80), Color(0.30, 0.52, 0.58), false, 12.0)
	# 岛屿（避障区另一圈淡环，让玩家看得见"浅滩"范围）
	for isl in islands:
		draw_circle(isl[0], isl[1] + AVOID_MARGIN, Color(0.16, 0.30, 0.30, 0.35))
		draw_circle(isl[0], isl[1], Color(0.30, 0.34, 0.20))
		draw_circle(isl[0], isl[1] * 0.72, Color(0.36, 0.40, 0.24))
		draw_arc(isl[0], isl[1], 0, TAU, 40, Color(0.50, 0.55, 0.33), 5.0)
	# 任务目标标记（运输/护航 → 哨站）
	for q in GameState.quests_active:
		var qt := String(q.get("type", ""))
		if qt != "transport" and qt != "escort":
			continue
		var pulse := 118.0
		draw_arc(outpost_pos, pulse, 0, TAU, 32, Color(0.95, 0.85, 0.35), 3.0)
		draw_string(ThemeDB.fallback_font, outpost_pos + Vector2(-40, -150), "任务",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.85, 0.35))

	# 打捞点
	for sv in salvages:
		draw_arc(sv, 44.0, 0, TAU, 20, Color(0.75, 0.62, 0.35), 3.0)
		draw_line(sv + Vector2(-24, 0), sv + Vector2(24, 0), Color(0.7, 0.58, 0.3), 3.0)
		draw_line(sv + Vector2(0, -24), sv + Vector2(0, 24), Color(0.7, 0.58, 0.3), 3.0)

	# 后退航门
	var back_label := "母港航门" if map_index <= 1 else "返回 %s" % _map_name(map_index - 1)
	draw_circle(BACK_GATE, 130.0, Color(0.85, 0.72, 0.25, 0.16))
	draw_circle(BACK_GATE, 130.0, Color(0.85, 0.72, 0.25, 0.10))
	draw_arc(BACK_GATE, 130.0, 0, TAU, 40, Color(0.90, 0.76, 0.30), 6.0)
	draw_arc(BACK_GATE, 96.0, 0, TAU, 32, Color(0.90, 0.76, 0.30, 0.5), 3.0)
	draw_string(ThemeDB.fallback_font, BACK_GATE + Vector2(-90, -160), back_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.92, 0.82, 0.42))

	# 前进航门（未通关时锁闭）
	var opened := GameState.is_map_cleared(map_index) or map_index >= 9
	var gate_col := Color(0.45, 0.85, 0.55) if opened else Color(0.55, 0.35, 0.35)
	draw_circle(FORWARD_GATE, 130.0, Color(gate_col.r, gate_col.g, gate_col.b, 0.16))
	draw_arc(FORWARD_GATE, 130.0, 0, TAU, 40, gate_col, 6.0)
	draw_arc(FORWARD_GATE, 96.0, 0, TAU, 32, Color(gate_col.r, gate_col.g, gate_col.b, 0.5), 3.0)
	var fwd_label := "航道尽头" if map_index >= 9 else ("前往 %s" % _map_name(map_index + 1) if opened else "航门锁闭（击败本图 Boss）")
	draw_string(ThemeDB.fallback_font, FORWARD_GATE + Vector2(-120, 190), fwd_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, gate_col)
	# 浅湾哨站
	draw_circle(outpost_pos, 110.0, Color(0.35, 0.65, 0.55, 0.18))
	draw_arc(outpost_pos, 110.0, 0, TAU, 32, Color(0.5, 0.85, 0.7), 5.0)
	draw_rect(Rect2(outpost_pos + Vector2(-34, -14), Vector2(68, 28)), Color(0.42, 0.38, 0.26))
	draw_string(ThemeDB.fallback_font, outpost_pos + Vector2(-60, -130), "浅湾哨站",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.6, 0.9, 0.75))

func _spawn_player() -> void:
	player = ShipScene.instantiate()
	player.setup_player(GameState.ship_def())
	player.position = Vector2(SEA_SIZE * 0.5, SEA_SIZE * 0.5 + 300)
	if GameState.sea_position != Vector2.ZERO:
		player.position = GameState.sea_position
	player.died.connect(_on_player_died)
	add_child(player)

func _build_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(0.65, 0.65)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()

func _build_hud() -> void:
	hud = SeaHud.new()
	add_child(hud)
	hud.ammo_selected.connect(_on_ammo_selected)
	hud.quest_nav_pressed.connect(_on_quest_nav)
	hud.fire_pressed.connect(_on_fire_pressed)
	hud.boarding_pressed.connect(_on_boarding_pressed)
	hud.retreat_pressed.connect(_on_retreat_pressed)
	hud.return_pressed.connect(_return_to_base)
	hud.set_ammo_highlight(&"solid")


# ---------------- 哨站港口 ----------------

func _build_port_ui() -> void:
	port_ui = CanvasLayer.new()
	port_ui.layer = 11
	add_child(port_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port_ui.add_child(root)
	port_panel = PanelContainer.new()
	port_panel.position = Vector2(360, 80)
	port_panel.custom_minimum_size = Vector2(760, 520)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.12, 0.97)
	style.border_color = Color(0.5, 0.75, 0.6, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	port_panel.add_theme_stylebox_override("panel", style)
	port_panel.visible = false
	root.add_child(port_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(730, 490)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	port_panel.add_child(scroll)
	port_list = VBoxContainer.new()
	port_list.add_theme_constant_override("separation", 5)
	port_list.custom_minimum_size = Vector2(710, 0)
	scroll.add_child(port_list)

func _toggle_outpost() -> void:
	if port_panel.visible:
		port_panel.visible = false
		return
	player.throttle = 0.0
	player.nav_target = null
	player.nav_queue.clear()
	_rebuild_port()
	port_panel.visible = true

func _p_lbl(text: String, width: float, color: Color = Color(0.85, 0.85, 0.8)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(width, 0)
	return l

func _p_title(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.55, 0.88, 0.7))
	port_list.add_child(l)

func _rebuild_port() -> void:
	for c in port_list.get_children():
		c.queue_free()
	var pd: Resource = DataRegistry.get_port(OUTPOST_ID)
	_p_title("%s —— 金币 %d · 货舱 %.0f/%.0f" % [pd.display_name, GameState.gold,
		GameState.cargo_used(), float(GameState.cargo_capacity())])

	_p_title("市场")
	var max_stock := int(pd.max_stock)
	for cid in DataRegistry.commodities.keys():
		var c: Resource = DataRegistry.get_commodity(cid)
		var stock := GameState.ensure_stock(OUTPOST_ID, cid, max_stock)
		var demand := float(pd.demand.get(String(cid), 1.0))
		var production := float(pd.production.get(String(cid), 1.0))
		var bp := MarketModel.buy_price(int(c.base_price), stock, max_stock, demand)
		var sp := MarketModel.sell_price(int(c.base_price), stock, max_stock, production)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		port_list.add_child(hb)
		hb.add_child(_p_lbl(c.display_name, 80))
		hb.add_child(_p_lbl("买 %d / 卖 %d（库存 %d）" % [bp, sp, stock], 220))
		var cid_v: StringName = cid
		var b1 := Button.new()
		b1.text = "买10"
		b1.custom_minimum_size = Vector2(70, 26)
		b1.pressed.connect(func(): _port_buy(cid_v, 10, bp))
		hb.add_child(b1)
		var b2 := Button.new()
		b2.text = "卖10"
		b2.custom_minimum_size = Vector2(70, 26)
		b2.pressed.connect(func(): _port_sell(cid_v, 10, sp))
		hb.add_child(b2)

	_p_title("船坞")
	var cost := _port_repair_cost()
	var rhb := HBoxContainer.new()
	rhb.add_theme_constant_override("separation", 10)
	port_list.add_child(rhb)
	rhb.add_child(_p_lbl("船况 船体 %.0f%% · 帆 %.0f%% · 舵 %.0f%%" % [
		GameState.hull_pct_like() * 100.0, GameState.sail_pct * 100.0, GameState.rudder_pct * 100.0], 380))
	rhb.add_child(_p_lbl("维修 %d 金" % cost, 140, Color(0.9, 0.82, 0.45)))
	var rb := Button.new()
	rb.text = "维修"
	rb.disabled = cost <= 0 or GameState.gold < cost
	rb.custom_minimum_size = Vector2(80, 26)
	rb.pressed.connect(func(): _port_repair(cost))
	rhb.add_child(rb)

	_p_title("任务（交付 / 进度）")
	var any_q := false
	for q in GameState.quests_active:
		var qt := String(q.get("type", ""))
		var line := "%s　%d / %d" % [String(q.get("title", "")), int(q.get("progress", 0)), int(q.get("amount", 1))]
		port_list.add_child(_p_lbl("　" + line, 560, Color(0.8, 0.85, 0.7)))
		any_q = true
		if qt == "transport":
			var cid_q := StringName(q.get("commodity", ""))
			var need := int(q.get("amount", 0))
			var have := int(GameState.cargo.get(cid_q, 0))
			if have >= need:
				var qb := Button.new()
				qb.text = "交付货物"
				qb.custom_minimum_size = Vector2(110, 26)
				qb.pressed.connect(func(): _port_deliver_quest(StringName(q.commodity)))
				port_list.add_child(qb)
	if not any_q:
		port_list.add_child(_p_lbl("　（没有进行中的任务）", 400, Color(0.5, 0.55, 0.55)))

	_p_title("本港船只（换乘）")
	var any := false
	for i in range(GameState.ships_owned.size()):
		var e: Dictionary = GameState.ships_owned[i]
		if String(e.get("station_port", "")) != String(OUTPOST_ID):
			continue
		any = true
		var edef: Resource = DataRegistry.get_ship(StringName(e.get("def_id", "")))
		var hp: float = float(e.get("hull_hp", -1.0))
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 10)
		port_list.add_child(hb2)
		hb2.add_child(_p_lbl("%s·%s" % [edef.display_name, String(StatsLib.VARIANT_NAMES.get(
			StringName(e.get("variant", "standard")), ""))] if edef != null else "未知船", 300))
		hb2.add_child(_p_lbl("船体 %s" % ("完好" if hp < 0.0 else "%.0f" % hp), 120))
		var idx := i
		var b := Button.new()
		b.text = "换乘"
		b.custom_minimum_size = Vector2(80, 26)
		b.pressed.connect(func(): _port_swap(idx))
		hb2.add_child(b)
	if not any:
		port_list.add_child(_p_lbl("　（本港没有其它船）", 400, Color(0.5, 0.55, 0.55)))

	_p_title("远洋订单（本港为交付点）")
	var any_o := false
	for i in range(GameState.active_orders.size()):
		var o: Dictionary = GameState.active_orders[i]
		if StringName(o.get("dest", "")) != OUTPOST_ID:
			continue
		any_o = true
		var c2: Resource = DataRegistry.get_commodity(StringName(o.commodity))
		var hb3 := HBoxContainer.new()
		hb3.add_theme_constant_override("separation", 10)
		port_list.add_child(hb3)
		hb3.add_child(_p_lbl("%s × %d" % [c2.display_name, int(o.amount)], 260))
		hb3.add_child(_p_lbl("剩 %d 周" % int(o.weeks_left), 100))
		var idx2 := i
		var b3 := Button.new()
		b3.text = "交付"
		b3.custom_minimum_size = Vector2(80, 26)
		b3.pressed.connect(func(): _port_deliver(idx2))
		hb3.add_child(b3)
	if not any_o:
		port_list.add_child(_p_lbl("　（没有以本港为交付点的订单）", 400, Color(0.5, 0.55, 0.55)))

	var close := Button.new()
	close.text = "离港"
	close.custom_minimum_size = Vector2(120, 32)
	close.pressed.connect(func(): port_panel.visible = false)
	port_list.add_child(close)

func _port_repair_cost() -> int:
	var hull_max: float = GameState.hull_max()
	var hull: float = GameState.hull_hp if GameState.hull_hp >= 0.0 else hull_max
	var per: float = float(DataRegistry.balance_dict.get("repair_per_hull", 0.25))
	var cost := (hull_max - hull) * per
	cost += (1.0 - GameState.sail_pct) * 300.0
	cost += (1.0 - GameState.rudder_pct) * 200.0
	cost += (1.0 - GameState.crew_pct) * 150.0
	cost *= (1.0 - GameState.repair_discount())
	return int(ceil(cost))

func _port_repair(cost: int) -> void:
	if cost <= 0 or GameState.gold < cost:
		hud.ticker("金币不足")
		return
	GameState.add_gold(-cost)
	GameState.hull_hp = GameState.hull_max()
	GameState.sail_pct = 1.0
	GameState.rudder_pct = 1.0
	GameState.crew_pct = 1.0
	if player != null and is_instance_valid(player):
		player.hull_hp = GameState.hull_max()
		player.sail_hp = player.sail_max
		player.rudder_hp = player.rudder_max
		player.crew_hp = player.crew_max
		player.queue_redraw()
	hud.ticker("维修完成，花费 %d 金" % cost)
	_rebuild_port()

func _port_deliver_quest(cid: StringName) -> void:
	var q := {}
	for qq in GameState.quests_active:
		if String(qq.get("type", "")) == "transport" and StringName(qq.get("commodity", "")) == cid:
			q = qq
			break
	if q.is_empty():
		return
	var need := int(q.get("amount", 0))
	if GameState.remove_cargo(cid, need) < need:
		hud.ticker("货物不足")
		return
	GameState.on_deliver(cid, need)
	hud.ticker("任务货物已交付")
	_rebuild_port()

func _port_buy(cid: StringName, amount: int, price: int) -> void:
	var pd: Resource = DataRegistry.get_port(OUTPOST_ID)
	var c: Resource = DataRegistry.get_commodity(cid)
	if GameState.gold < price * amount:
		hud.ticker("金币不足")
		return
	if GameState.cargo_free() < float(c.volume) * amount:
		hud.ticker("货舱空间不足")
		return
	GameState.add_gold(-price * amount)
	GameState.add_cargo(cid, amount)
	var stock := GameState.ensure_stock(OUTPOST_ID, cid, int(pd.max_stock))
	GameState.set_stock(OUTPOST_ID, cid, stock - amount)
	hud.ticker("买入 %d %s" % [amount, c.display_name])
	_rebuild_port()

func _port_sell(cid: StringName, amount: int, price: int) -> void:
	if int(GameState.cargo.get(cid, 0)) < amount:
		hud.ticker("货舱里没有足够的该商品")
		return
	var pd: Resource = DataRegistry.get_port(OUTPOST_ID)
	GameState.remove_cargo(cid, amount)
	var stock := GameState.ensure_stock(OUTPOST_ID, cid, int(pd.max_stock))
	GameState.set_stock(OUTPOST_ID, cid, stock + amount)
	GameState.add_gold(price * amount)
	hud.ticker("卖出 %d 件，得 %d 金" % [amount, price * amount])
	_rebuild_port()

func _port_swap(idx: int) -> void:
	if not GameState.swap_to_owned(idx, OUTPOST_ID):
		hud.ticker("换乘失败")
		return
	hud.ticker("已在本港换乘 %s" % GameState.ship_def().display_name)
	_rebuild_port()

func _port_deliver(idx: int) -> void:
	var res: Dictionary = GameState.deliver_order(idx, OUTPOST_ID)
	if res.get("ok", false):
		hud.ticker("交付完成，获得 %d 金" % int(res.gold))
	else:
		hud.ticker(String(res.get("reason", "交付失败")))
	_rebuild_port()

# ---------------- 生成 ----------------

func _spawn_salvages() -> void:
	salvages.clear()
	if not _has_quest("gather"):
		return
	for i in range(3):
		salvages.append(_random_spawn_pos())

func _has_quest(type_name: String) -> bool:
	for q in GameState.quests_active:
		if String(q.get("type", "")) == type_name:
			return true
	return false

func _spawn_escort_if_needed() -> void:
	if not _has_quest("escort"):
		return
	var e = ShipScene.instantiate()
	e.setup_enemy(DataRegistry.get_enemy(&"pirate_scout"), 1.4)
	e.is_player = false
	e.faction = "merchant"
	e.display_name = "受护商船"
	e.position = player.position + Vector2(180, 120)
	e.hull_max *= 1.6
	e.hull_hp = e.hull_max
	e.died.connect(_on_escort_died)
	add_child(e)
	escort_ship = e
	hud.ticker("商船已加入编队 · 护送它抵达浅湾哨站")

func _on_escort_died(_ship, _info) -> void:
	escort_ship = null
	GameState.on_escort_lost()

func _update_escort() -> void:
	if escort_ship == null or not is_instance_valid(escort_ship):
		return
	if not escort_ship.alive:
		escort_ship = null
		return
	escort_ship.nav_target = player.global_position + Vector2(140, 0)

func _try_collect_salvage() -> bool:
	for i in range(salvages.size()):
		if player.global_position.distance_to(salvages[i]) < 170.0:
			salvages.remove_at(i)
			GameState.on_salvage()
			hud.ticker("打捞到沉船残骸")
			queue_redraw()
			return true
	return false

func _map_scale() -> float:
	return 1.0 + float(map_index - 1) * 0.35

## 战利品按图号指数增长：船价每级 ×2.5，收入必须跟上，否则后期只能靠刷低级图
func _loot_mult() -> float:
	return pow(2.4, float(map_index - 1))

func _spawn_pirate() -> void:
	if enemies.size() >= MAX_UNITS:
		return
	var cap := int(map_def.pirates) if map_def != null else 4
	if _count_kind("pirate") >= cap:
		return
	var e = ShipScene.instantiate()
	e.setup_enemy(DataRegistry.get_enemy(&"pirate_scout"), _map_scale())
	e.loot_mult = _loot_mult()
	e.position = _random_spawn_pos(enemies.size() < NEAR_UNITS)
	e.died.connect(_on_enemy_died)
	e.disengaged.connect(_on_enemy_disengaged)
	add_child(e)
	e.home_pos = e.global_position
	enemies.append(e)

func _spawn_monster() -> void:
	if enemies.size() >= MAX_UNITS:
		return
	var cap := int(map_def.monsters) if map_def != null else 2
	if _count_kind("monster") >= cap:
		return
	var m = MonsterScene.instantiate()
	m.setup(DataRegistry.get_enemy(&"reef_crab"), _map_scale())
	m.loot_mult = _loot_mult()
	m.position = _random_spawn_pos(enemies.size() < NEAR_UNITS)
	m.died.connect(_on_enemy_died)
	add_child(m)
	enemies.append(m)

## 海军巡逻队：不主动找玩家，只打海盗
func _spawn_navy_patrol() -> void:
	if enemies.size() >= MAX_UNITS or _count_faction("navy") >= 2:
		return
	var e = ShipScene.instantiate()
	e.setup_enemy(DataRegistry.get_enemy(&"navy_patrol"), _map_scale())
	e.loot_mult = _loot_mult()
	e.position = _random_spawn_pos()
	e.died.connect(_on_enemy_died)
	e.disengaged.connect(_on_enemy_disengaged)
	add_child(e)
	e.home_pos = e.global_position
	enemies.append(e)

## 中立商船：被海盗追，不还手
func _spawn_merchant() -> void:
	if enemies.size() >= MAX_UNITS or _count_faction("merchant") >= 2:
		return
	var e = ShipScene.instantiate()
	e.setup_enemy(DataRegistry.get_enemy(&"pirate_scout"), _map_scale() * 0.8)
	e.faction = "merchant"
	e.display_name = "中立商船"
	e.loot_mult = _loot_mult()
	e.position = _random_spawn_pos()
	e.died.connect(_on_enemy_died)
	e.disengaged.connect(_on_enemy_disengaged)
	add_child(e)
	e.home_pos = e.global_position
	enemies.append(e)

func _count_kind(kind: String) -> int:
	var n := 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if kind == "monster" and e.has_method("alive_limbs"):
			n += 1
		elif kind == "pirate" and not e.has_method("alive_limbs"):
			n += 1
	return n

## 在整张图里找一个"不挤、不贴着玩家"的落点
## 落点采样：先严格，再逐步放宽，最后才兜底
func _random_spawn_pos(near: bool = false) -> Vector2:
	# 1) 严格：最小间距 + 网格密度
	for attempt in range(60):
		var p := _sample_candidate(near)
		if _is_spot_free(p, MIN_SEPARATION):
			return p
	# 2) 放宽间距到一半再试
	for attempt in range(60):
		var p := _sample_candidate(near)
		if _is_spot_free(p, MIN_SEPARATION * 0.5):
			return p
	# 3) 兜底：找全图最空、离玩家最远的格子中心
	return _fallback_spot()

## 候选点：迎接单位按扇区分层（保证绕玩家一圈分散），其余全图均匀采样
func _sample_candidate(near: bool) -> Vector2:
	if near and player != null and is_instance_valid(player):
		# 按 NEAR_UNITS 等分圆周，再叠 ±20° 抖动：
		# 保证几个"迎接"单位绕玩家分散，不会全挤在一侧
		var idx := _near_sector % maxi(1, NEAR_UNITS)
		_near_sector += 1
		var ang := float(idx) * TAU / float(maxi(1, NEAR_UNITS)) + RngService.randf_range(-0.35, 0.35)
		var dist := RngService.randf_range(NEAR_RING_MIN, NEAR_RING_MAX)
		return (player.global_position + Vector2.RIGHT.rotated(ang) * dist).clamp(
			Vector2(SPAWN_MARGIN, SPAWN_MARGIN), Vector2(SEA_SIZE - SPAWN_MARGIN, SEA_SIZE - SPAWN_MARGIN))
	return Vector2(
		RngService.randf_range(SPAWN_MARGIN, SEA_SIZE - SPAWN_MARGIN),
		RngService.randf_range(SPAWN_MARGIN, SEA_SIZE - SPAWN_MARGIN))

## 这个点是否满足：不贴玩家、网格不超限、与已有单位保持 min_sep
func _is_spot_free(p: Vector2, min_sep: float) -> bool:
	if player != null and is_instance_valid(player):
		if p.distance_to(player.global_position) < PLAYER_SAFE_RADIUS - 1.0:
			return false
	if _units_in_cell(p) >= MAX_PER_CELL:
		return false
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.global_position.distance_to(p) < min_sep:
			return false
	return true

## 兜底：挑一个离其他单位最远、且格子里没人的位置
func _fallback_spot() -> Vector2:
	var best := Vector2(SEA_SIZE * 0.5, SEA_SIZE * 0.5)
	var best_score := -1.0
	for gx in range(1, 8):
		for gy in range(1, 8):
			var p := Vector2(float(gx) * SEA_SIZE / 8.0, float(gy) * SEA_SIZE / 8.0)
			if player != null and is_instance_valid(player):
				if p.distance_to(player.global_position) < PLAYER_SAFE_RADIUS:
					continue
			var score := 1.0e9
			for e in enemies:
				if is_instance_valid(e):
					score = minf(score, e.global_position.distance_to(p))
			if score > best_score:
				best_score = score
				best = p
	return best

func _units_in_cell(p: Vector2) -> int:
	var cell := Vector2(floor(p.x / DENSITY_CELL), floor(p.y / DENSITY_CELL))
	var n := 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var ep: Vector2 = e.global_position
		if Vector2(floor(ep.x / DENSITY_CELL), floor(ep.y / DENSITY_CELL)) == cell:
			n += 1
	return n

# ---------------- 主循环 ----------------

## 岛屿软约束：在子节点的 _physics_process 之前写入斥力
func _physics_process(delta: float) -> void:
	if game_over:
		return
	var ships: Array = []
	if player != null and is_instance_valid(player) and player.alive:
		ships.append(player)
	for e in enemies:
		if is_instance_valid(e) and e.get("alive"):
			ships.append(e)
	# 3 级以上海图海盗主动索敌
	if map_def != null and bool(map_def.hostile):
		for e in enemies:
			if not is_instance_valid(e) or not e.get("alive"):
				continue
			if e.has_method("alive_limbs") or e.get("is_boss"):
				continue
			if String(e.get("faction")) != "pirate":
				continue
			if e.get("target") == null and player != null and is_instance_valid(player):
				if e.global_position.distance_to(player.global_position) < 1200.0:
					e.set("target", player)
					e.set("engaged", true)

	for n in ships:
		if n.get("external_push") == null:
			continue
		for isl in islands:
			var c: Vector2 = isl[0]
			var r: float = isl[1]
			var avoid_r: float = r + AVOID_MARGIN
			var to_ship: Vector2 = n.global_position - c
			var d: float = to_ship.length()
			if d < 0.01 or d >= avoid_r:
				continue
			var push: float = 1.0 - d / avoid_r
			n.external_push += to_ship.normalized() * push * PUSH_STRENGTH
			if n.get("terrain_slow") != null:
				n.terrain_slow = minf(float(n.terrain_slow), 0.55)
			# 实质压到岛上 → 搁浅
			if d < r + 20.0 and n == player and ground_cooldown <= 0.0:
				ground_cooldown = 1.5
				n.take_damage({"hull": n.hull_max * 0.02, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
				if hud != null:
					hud.ticker("搁浅！船体受损")

func _process(delta: float) -> void:
	ground_cooldown = maxf(0.0, ground_cooldown - delta)
	if hud == null:
		return
	hud.update_all(player, player.target if player != null else null)
	if game_over:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = 8.0
		_spawn_pirate()
		if RngService.chance(0.4):
			_spawn_monster()
	_update_boarding(delta)
	_update_bounty_hunters(delta)
	_update_escort()
	_faction_ai(delta)
	_refresh_quest_hud()
	if camera != null and player != null and is_instance_valid(player):
		camera.position = player.position
	if hud != null and player != null:
		var near_back: bool = player.position.distance_to(BACK_GATE) < 240.0
		var near_fwd: bool = player.position.distance_to(FORWARD_GATE) < 240.0
		var near_out: bool = player.position.distance_to(outpost_pos) < 240.0
		if near_out:
			hud.set_hint("按 E 进入浅湾哨站  ·  市场 / 换船 / 交付订单")
		elif near_back:
			hud.set_hint("按 E %s" % ("返回母港" if map_index <= 1 else "返回 %s" % _map_name(map_index - 1)))
		elif near_fwd:
			if map_index >= 9:
				hud.set_hint("航道尽头 · 王冠之海")
			elif GameState.is_map_cleared(map_index):
				hud.set_hint("按 E 前往 %s" % _map_name(map_index + 1))
			else:
				hud.set_hint("航门锁闭 · 击败本图 Boss 才能开启")
		else:
			hud.set_hint("")

func _update_bounty_hunters(delta: float) -> void:
	hunter_timer -= delta
	if hunter_timer > 0.0:
		return
	hunter_timer = 45.0
	if not GameState.bounty_active():
		return
	if _count_faction("navy") >= 2:
		return
	_spawn_navy()

func _count_faction(fac: String) -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and String(e.get("faction")) == fac:
			n += 1
	return n

func _spawn_navy() -> void:
	var e = ShipScene.instantiate()
	e.setup_enemy(DataRegistry.get_enemy(&"navy_patrol"), maxf(1.0, _map_scale()))
	e.position = player.global_position + Vector2.RIGHT.rotated(RngService.randf() * TAU) * 900.0
	e.target = player
	e.engaged = true
	e.died.connect(_on_enemy_died)
	e.disengaged.connect(_on_enemy_disengaged)
	add_child(e)
	e.home_pos = e.global_position
	enemies.append(e)
	hud.ticker("赏金猎人编队出现！（通缉度 %d）" % GameState.notoriety())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if port_panel != null and port_panel.visible:
				port_panel.visible = false
				return
			if player == null:
				return
			if player.global_position.distance_to(outpost_pos) < 240.0:
				if escort_ship != null and is_instance_valid(escort_ship) and escort_ship.alive:
					GameState.on_escort_arrived()
					escort_ship.queue_free()
					escort_ship = null
					hud.ticker("商船安全抵达，护航完成")
				_toggle_outpost()
			elif _try_collect_salvage():
				pass
			elif player.global_position.distance_to(BACK_GATE) < 240.0:
				_go_back()
			elif player.global_position.distance_to(FORWARD_GATE) < 240.0:
				_go_forward()
			return
		if event.keycode == KEY_SPACE:
			TimeService.paused = not TimeService.paused
			_ticker("时间已暂停" if TimeService.paused else "时间继续")
			return
		if event.keycode == KEY_1:
			TimeService.speed = 1.0
			_ticker("时间 1×")
			return
		if event.keycode == KEY_2:
			TimeService.speed = 2.0
			_ticker("时间 2×")
			return
		if event.keycode == KEY_3:
			TimeService.speed = 4.0
			_ticker("时间 4×")
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hud != null and hud.get_viewport().gui_get_hovered_control() != null:
			return
		# 必须由事件自身坐标换算，get_global_mouse_position() 在合成输入下不可靠
		var world: Vector2 = get_canvas_transform().affine_inverse() * event.position
		var picked = _pick_enemy(world)
		if picked != null:
			_lock_target(picked)
		elif player != null:
			var dest: Vector2 = world.clamp(Vector2(100, 100), Vector2(SEA_SIZE - 100, SEA_SIZE - 100))
			player.nav_queue = _route_to(dest)
			player.nav_target = null
			player.target = null
			player.engaged = false

## 求绕开圆的一个切点：从 from 出发绕 open 圈走、且尽量靠近 toward
func _tangent_point(from: Vector2, c: Vector2, r: float, toward: Vector2) -> Vector2:
	var d := from.distance_to(c)
	if d <= r + 1.0:
		# 已经压在圈里：沿远离圆心的方向先走出去
		var out_dir := (from - c)
		if out_dir.length() < 0.01:
			out_dir = Vector2.RIGHT
		return c + out_dir.normalized() * (r + 80.0)
	var alpha := acos(clampf(r / d, -1.0, 1.0))
	var theta := (from - c).angle()
	var cand_a := c + Vector2.RIGHT.rotated(theta + alpha) * (r + 60.0)
	var cand_b := c + Vector2.RIGHT.rotated(theta - alpha) * (r + 60.0)
	return cand_a if cand_a.distance_to(toward) < cand_b.distance_to(toward) else cand_b

## 规划航线：逐段检查，遇到岛屿就插入切点，直到整条路线都不穿岛（最多 8 次修正）
func _route_to(target: Vector2) -> Array:
	if player == null:
		return [target]
	var start: Vector2 = player.global_position
	var pts: Array = [start, target]
	for iteration in range(8):
		var inserted := false
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			for isl in islands:
				var c: Vector2 = isl[0]
				var r: float = isl[1] + AVOID_MARGIN * 0.75
				if not _segment_hits_circle(a, b, c, r):
					continue
				var wp := _tangent_point(a, c, r, b)
				# 防止原地插入同一个点导致死循环
				if wp.distance_to(a) > 30.0:
					pts.insert(i + 1, wp)
					inserted = true
					break
			if inserted:
				break
		if not inserted:
			break
	return pts.slice(1)

func _segment_hits_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r

func _pick_enemy(world: Vector2):
	var best = null
	var best_d := 90.0
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: float = e.position.distance_to(world)
		if d < best_d:
			best_d = d
			best = e
	return best

func _ticker(text: String) -> void:
	if hud != null:
		hud.ticker(text)

func _on_enemy_disengaged(ship) -> void:
	if player != null and player.target == ship:
		player.target = null
		player.engaged = false
	hud.ticker("已脱离 %s 的追击" % String(ship.get("display_name")))

# ---------------- 任务导航 ----------------

## 任务的导航目标位置；没有可去的地方时返回 null
func _quest_nav_target(q: Dictionary) -> Variant:
	match String(q.get("type", "")):
		"transport", "escort":
			return outpost_pos
		"gather":
			var best = null
			var best_d := INF
			for sv in salvages:
				var d: float = player.global_position.distance_to(sv)
				if d < best_d:
					best_d = d
					best = sv
			return best
		"hunt":
			var kind := String(q.get("target_kind", "pirate"))
			var best_e = null
			var best_ed := INF
			for e in enemies:
				if not is_instance_valid(e) or not e.get("alive"):
					continue
				var is_mon: bool = e.has_method("alive_limbs")
				if kind == "monster" and not is_mon:
					continue
				if kind == "pirate" and is_mon:
					continue
				var d2: float = player.global_position.distance_to(e.global_position)
				if d2 < best_ed:
					best_ed = d2
					best_e = e.global_position
			return best_e
	return null

func _on_quest_nav(index: int) -> void:
	if index < 0 or index >= GameState.quests_active.size():
		return
	var q: Dictionary = GameState.quests_active[index]
	var t = _quest_nav_target(q)
	if t == null:
		hud.ticker("该任务暂时没有可导航的目标")
		return
	player.nav_queue = _route_to(t)
	player.nav_target = null
	player.target = null
	player.engaged = false
	hud.ticker("已设定航线：%s" % String(q.get("title", "")))

func _refresh_quest_hud() -> void:
	var can_nav: Array = []
	var notes: Array = []
	for q in GameState.quests_active:
		can_nav.append(_quest_nav_target(q) != null)
		notes.append(_quest_note(q))
	hud.update_quests(GameState.quests_active, can_nav, notes)

## 任务行的附加状态（目前只有护航任务显示商船情况）
func _quest_note(q: Dictionary) -> String:
	if String(q.get("type", "")) != "escort":
		return ""
	if escort_ship == null or not is_instance_valid(escort_ship):
		return "　⚑ 失联"
	if not escort_ship.alive:
		return "　⚑ 已损毁"
	var pct := int(escort_ship.hull_pct() * 100.0)
	var dist := int(player.global_position.distance_to(escort_ship.global_position))
	return "　⚑ %d%% · %dm" % [pct, dist]

# ---------------- 阵营生态 ----------------

func _is_hostile(a: String, b: String) -> bool:
	if a == b:
		return false
	return (FACTION_ENEMIES.get(a, []) as Array).has(b)

## 战力判断：打得过才主动追击，打不过只被动还击
func _will_attack(attacker, victim) -> bool:
	if not attacker.has_method("combat_power") or not victim.has_method("combat_power"):
		return true
	return float(attacker.combat_power()) > float(victim.combat_power()) * 1.25

func _all_units() -> Array:
	var out: Array = []
	if player != null and is_instance_valid(player) and player.alive:
		out.append(player)
	for e in enemies:
		if is_instance_valid(e) and e.get("alive"):
			out.append(e)
	return out

func _faction_ai(delta: float) -> void:
	ai_timer -= delta
	if ai_timer > 0.0:
		return
	ai_timer = AI_TICK
	var hostile_map: bool = map_def != null and bool(map_def.hostile)
	var units := _all_units()

	for e in units:
		if e == player:
			continue
		var is_mon: bool = e.has_method("alive_limbs")
		# 1~2 图：谁都不主动
		if not hostile_map:
			continue
		# 已有有效目标就跳过
		var cur = e.get("target")
		if cur != null and is_instance_valid(cur) and cur.get("alive"):
			continue
		# 海怪：3 图以上无差别攻击（不看战力），但仍受围攻上限约束
		if is_mon:
			if player != null and is_instance_valid(player) 				and _count_targeting_player() < MAX_ATTACKERS_ON_PLAYER 				and e.global_position.distance_to(player.global_position) < 1100.0:
				e.set("target", player)
			continue
		var fac := String(e.get("faction"))
		# 商船只逃不打
		if fac == "merchant":
			continue
		var best = null
		var best_d := 1100.0
		for o in units:
			if o == e:
				continue
			if not _is_hostile(fac, String(o.get("faction"))):
				continue
			var d: float = e.global_position.distance_to(o.global_position)
			if d < best_d:
				best_d = d
				best = o
		if best == null:
			continue
		# 围攻上限：避免整张图的敌人一起扑向玩家
		if best == player and _count_targeting_player() >= MAX_ATTACKERS_ON_PLAYER:
			continue
		if _will_attack(e, best):
			e.set("target", best)
			e.set("engaged", true)

## 调试用：把规划出的航线转成可打印的坐标数组
func debug_route(dest: Vector2) -> Array:
	var out: Array = []
	for p in _route_to(dest):
		out.append([int(p.x), int(p.y)])
	return out

## 调试/记录用：当前海域的密度快照
func debug_stats() -> Dictionary:
	var near := 0
	var min_d := 1.0e9
	var cells := {}
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		min_d = minf(min_d, d)
		if d < 1200.0:
			near += 1
		var ep: Vector2 = e.global_position
		var k := "%d_%d" % [int(floor(ep.x / DENSITY_CELL)), int(floor(ep.y / DENSITY_CELL))]
		cells[k] = int(cells.get(k, 0)) + 1
	# 两两最近距离：衡量是否"挤成一堆"
	var min_pair := 1.0e9
	var units_list: Array = []
	for e in enemies:
		if is_instance_valid(e):
			units_list.append(e)
	for i in range(units_list.size()):
		for j in range(i + 1, units_list.size()):
			min_pair = minf(min_pair, units_list[i].global_position.distance_to(units_list[j].global_position))
	return {
		"units": enemies.size(),
		"within_1200": near,
		"nearest": min_d,
		"min_pair": min_pair,
		"targeting_player": _count_targeting_player(),
		"max_cell": cells.values().max() if not cells.is_empty() else 0,
		"fps": Engine.get_frames_per_second(),
	}

func _count_targeting_player() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.get("target") == player:
			n += 1
	return n

func _lock_target(enemy) -> void:
	player.target = enemy
	player.engaged = true
	enemy.target = player
	enemy.engaged = true
	hud.ticker("锁定：%s" % enemy.display_name)

# ---------------- HUD 回调 ----------------

func _on_fire_pressed() -> void:
	if player == null:
		return
	var res: Dictionary = player.try_fire()
	if not res.get("ok", false):
		hud.ticker(String(res.get("reason", "无法开火")))

func _on_ammo_selected(id: StringName) -> void:
	var a: Resource = DataRegistry.get_ammo(id)
	if a == null:
		return
	player.ammo = a
	player.ammo_id = id
	hud.set_ammo_highlight(id)
	hud.ticker("换弹：%s" % a.display_name)

func _on_retreat_pressed() -> void:
	if player == null or not player.can_retreat():
		hud.ticker("风帆或舵机已毁，无法撤离")
		return
	var t = player.target
	player.target = null
	player.engaged = false
	var flee: Vector2 = (player.position + Vector2.RIGHT.rotated(player.heading) * 1400.0).clamp(
		Vector2(100, 100), Vector2(SEA_SIZE - 100, SEA_SIZE - 100))
	player.nav_queue = _route_to(flee)
	player.nav_target = null
	if t != null and is_instance_valid(t):
		t.target = null
		t.engaged = false
	hud.ticker("已脱离战斗")

func _on_boarding_pressed() -> void:
	var t = player.target
	if t == null or not is_instance_valid(t) or t.has_method("alive_limbs"):
		return
	if not CombatResolver.can_board(t.hull_hp, t.hull_max):
		hud.ticker("目标船体过厚，无法接舷")
		return
	if player.position.distance_to(t.position) > 160.0:
		hud.ticker("距离太远，先靠近")
		return
	boarded = true
	boarding_target = t
	boarding_tick = 0.0
	hud.ticker("跳帮中……")

func _update_boarding(delta: float) -> void:
	if not boarded or boarding_target == null or not is_instance_valid(boarding_target):
		return
	if not boarding_target.alive or not player.alive:
		boarded = false
		return
	boarding_tick -= delta
	if boarding_tick > 0.0:
		return
	boarding_tick = 0.5
	# 线性衰减（带常数项），否则双方按比例掉血会无限逼近 0 而不结束
	var player_power: float = (player.crew_hp * 0.15 + 3.0 + float(player.boarding_bonus)) \
		* (1.0 + float(player.boarding_pct))
	var target_power: float = boarding_target.crew_hp * 0.15 + 3.0
	# 被打破的船士气崩溃：船体 ≤10% 时守方战力 -30%
	target_power *= 0.7
	boarding_target.last_attacker = player
	boarding_target.take_crew_damage(player_power)
	if not boarding_target.alive:
		boarded = false
		return
	player.take_crew_damage(target_power)

# ---------------- 死亡与结算 ----------------

func _on_enemy_died(ship, info: Dictionary) -> void:
	# 只有玩家打死的才给战利品；NPC 互殴不产出（避免捡漏刷钱）
	var by_player: bool = ship.get("last_attacker") == player
	if by_player:
		var result := LootSystem.apply(player, ship, info)
		hud.ticker(LootSystem.describe(result))
	else:
		hud.ticker("%s 被击沉" % String(ship.get("display_name")))
	var eid_raw: Variant = ship.get("enemy_id")
	var eid := StringName(eid_raw) if eid_raw != null else &""
	if String(eid) != "":
		var ug: Variant = ship.get("unique_gear")
		if ug != null and String(ug) != "":
			GameState.grant_unique_gear(StringName(ug))
		var ucn: Variant = ship.get("unique_crew_name")
		if ucn != null and String(ucn) != "":
			GameState.grant_unique_crew(String(ucn), StringName(ship.get("unique_crew_role")), int(ship.get("unique_crew_stat")))
		var unlocked := GameState.record_boss_defeat(eid, map_index)
		if unlocked:
			hud.ticker("击破 Boss！航门开启，可前往 %s" % _map_name(map_index + 1))
			queue_redraw()
		if GameState.check_victory():
			hud.ticker("★ 通关！你在王冠之海写下了自己的名字")
	if player != null and is_instance_valid(player) and player.target == ship:
		player.target = null
		player.engaged = false
	enemies.erase(ship)
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(ship):
		ship.queue_free()

func _on_player_died(ship, info: Dictionary) -> void:
	if game_over:
		return
	game_over = true
	var txt := "你的船沉没了" if info.get("sunk", false) else "船员全部阵亡，船被夺走"
	if info.get("captured", true) and not info.get("sunk", false):
		GameState.cargo.clear()
		EventBus.cargo_changed.emit(0.0, GameState.cargo_capacity())
	hud.ticker("%s —— 2 秒后返回母港" % txt)
	await get_tree().create_timer(2.0).timeout
	GameState.hull_hp = 0.0
	GameState.sail_pct = 1.0
	GameState.rudder_pct = 1.0
	GameState.crew_pct = 1.0
	GameState.sea_position = Vector2.ZERO
	SceneRouter.goto(&"base")

func _return_to_base() -> void:
	if game_over and player != null and player.alive:
		return
	_sync_to_game_state()
	SceneRouter.goto(&"base")

func _go_back() -> void:
	_sync_to_game_state()
	if map_index <= 1:
		SceneRouter.goto(&"base")
		return
	GameState.current_map = map_index - 1
	GameState.sea_position = Vector2.ZERO
	hud.ticker("驶向 %s" % _map_name(map_index - 1))
	SceneRouter.goto(&"sea")

func _go_forward() -> void:
	if map_index >= 9:
		hud.ticker("已是航道尽头 · 王冠之海")
		return
	if not GameState.is_map_cleared(map_index):
		hud.ticker("航门锁闭：击败本图 Boss 才能开启")
		return
	_sync_to_game_state()
	GameState.current_map = map_index + 1
	GameState.sea_position = Vector2.ZERO
	hud.ticker("驶向 %s" % _map_name(map_index + 1))
	SceneRouter.goto(&"sea")

func _sync_to_game_state() -> void:
	if player == null or not is_instance_valid(player):
		return
	GameState.hull_hp = player.hull_hp
	GameState.sail_pct = player.sail_pct()
	GameState.rudder_pct = player.rudder_pct()
	GameState.crew_pct = player.crew_pct()
	GameState.sea_position = player.position
	GameState.current_map = 1
