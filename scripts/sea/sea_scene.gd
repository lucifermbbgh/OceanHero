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

## 海域邻接表：从某条边出去会到哪张图（0 = 母港）
const MAP_NEIGHBORS := {
	1: {"west": 0, "east": 2},
	2: {"west": 1, "east": 3},
	3: {"west": 2, "south": 4},
	4: {"north": 3, "east": 5},
	5: {"west": 4, "east": 6},
	6: {"west": 5, "south": 7},
	7: {"north": 6, "east": 8},
	8: {"west": 7, "east": 9},
	9: {"west": 8},
}
const EDGE_TRIGGER := 110.0     # 进入这个宽度的边带即触发换图
const CrewFactory = preload("res://scripts/systems/crew_factory.gd")
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
var cur_port_island := 0        # 当前停靠的岛屿索引
var _port_tavern: Array = []    # 当前港口的招募候选
var port_tab := "local"         # local = 本地市场，world = 世界市场
var aggro_mult := 1.0           # 伪造旗帜：敌方索敌半径倍率
var port_ui: CanvasLayer
var world_map: Control
var mini_map: Control
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
## 岛屿三级：1 村 / 2 镇 / 3 城
const ISLAND_TIERS := {1: "港村", 2: "港镇", 3: "港城"}
const ISLAND_RADIUS := {1: Vector2(240, 320), 2: Vector2(360, 450), 3: Vector2(500, 620)}
const TIER_STOCK := {1: 40, 2: 90, 3: 160}          # 市场存货按等级
const SPECIALTIES := [&"iron", &"spice", &"rum"]    # 特产（谷物/木材永远有）
const PORT_RANGE_EXTRA := 160.0                     # 靠岸判定：岛半径 + 这个
## 特产价格随港口等级变化（小港贵、大城便宜）
const SPECIALTY_PRICE_MULT := {1: 1.20, 2: 1.00, 3: 0.85}
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
	map_index = clampi(GameState.current_map, 1, 30)
	GameState.mark_map_explored(map_index)
	map_def = DataRegistry.get_map(map_index)
	_generate_islands()
	_build_world()
	_spawn_player()
	_build_camera()
	_build_hud()
	EventBus.islands_upgraded.connect(_on_islands_upgraded)
	_build_port_ui()
	_spawn_patrols()
	if map_index == 1:
		var pd: Resource = DataRegistry.get_port(OUTPOST_ID)
		if pd != null:
			outpost_pos = _anchor_port_to_island(pd.position)
	else:
		# 其他海图没有哨站，移到屏幕外避免绘制与交互
		outpost_pos = Vector2(-8000, -8000)
	_apply_contraband_effects()
	_spawn_map_contents()
	_spawn_salvages()
	_spawn_escort_if_needed()
	var map_name := String(map_def.display_name) if map_def != null else "未知海域"
	hud.ticker("%s · 用 A/D 转舵，点击敌船锁定后自动开火" % map_name)

## 升格实时生效：把场景里的岛屿换成新等级，并播报
func _on_islands_upgraded(keys: Array) -> void:
	var changed := 0
	for i in range(islands.size()):
		var key := GameState.island_key(map_index, i)
		if not keys.has(key):
			continue
		var new_tier := GameState.island_tier_of(key, int(islands[i][2]))
		if new_tier == int(islands[i][2]):
			continue
		islands[i][2] = new_tier
		islands[i][3] = _island_name(i, new_tier)
		GameState.register_port(key, String(islands[i][3]), map_index, new_tier)
		hud.ticker("聚落升格：%s（%s）" % [String(islands[i][3]), String(ISLAND_TIERS.get(new_tier, "港口"))])
		changed += 1
	if changed > 0:
		if port_panel.visible:
			_rebuild_port()
		queue_redraw()

## 违禁品战斗效果：进海域时消耗对应物品
func _apply_contraband_effects() -> void:
	if int(GameState.contraband.get(&"forge_flag", 0)) > 0:
		GameState.contraband[&"forge_flag"] = int(GameState.contraband[&"forge_flag"]) - 1
		if int(GameState.contraband[&"forge_flag"]) <= 0:
			GameState.contraband.erase(&"forge_flag")
		aggro_mult = 0.5
		hud.ticker("伪造旗帜生效：敌方索敌 −50%")
	if int(GameState.contraband.get(&"stimulant", 0)) > 0:
		GameState.contraband[&"stimulant"] = int(GameState.contraband[&"stimulant"]) - 1
		if int(GameState.contraband[&"stimulant"]) <= 0:
			GameState.contraband.erase(&"stimulant")
		if player != null:
			player.crew_max *= 1.2
			player.crew_hp = player.crew_max
		hud.ticker("违禁药物生效：船员上限 +20%")

func _generate_islands() -> void:
	islands.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map_def.island_seed) * 7919 + map_index * 131
	var n := mini(8, 4 + (map_index % 3))
	var safe_center := Vector2(SEA_SIZE * 0.5, SEA_SIZE * 0.5 + 300)
	# 母港所在海图：前两座固定为近港的港城与港镇
	var fixed_spots := {
		0: Vector2(safe_center.x + 1200.0, safe_center.y - 700.0),
		1: Vector2(safe_center.x - 1300.0, safe_center.y + 600.0),
	}
	for i in range(n):
		var pos: Vector2
		if map_index == 0 and fixed_spots.has(i):
			pos = fixed_spots[i]
		else:
			pos = Vector2(rng.randf_range(1500.0, 6500.0), rng.randf_range(1500.0, 6500.0))
			if pos.distance_to(safe_center) < 900.0:
				pos = pos.lerp(Vector2(6600, 6600), 0.6)
		var tier := 1
		if i == 0:
			tier = 3
		elif i == 1:
			tier = 2
		var key := GameState.island_key(map_index, i)
		tier = GameState.island_tier_of(key, tier)
		var rr: Vector2 = ISLAND_RADIUS[tier]
		var specialty: StringName = SPECIALTIES[i % SPECIALTIES.size()]
		var nm := _island_name(i, tier)
		GameState.register_port(key, nm, map_index, tier)
		# [位置, 半径, 等级, 名称, 特产]
		islands.append([pos, rng.randf_range(rr.x, rr.y), tier, nm, specialty])

## 把港口贴到最近岛屿的岸边，而不是漂在海面
func _anchor_port_to_island(want: Vector2) -> Vector2:
	var best = null
	var best_d := 1.0e9
	for isl in islands:
		var d: float = Vector2(isl[0]).distance_to(want)
		if d < best_d:
			best_d = d
			best = isl
	if best == null:
		return want
	var c: Vector2 = best[0]
	var r: float = float(best[1])
	var dir: Vector2 = (want - c)
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	return c + dir.normalized() * (r + 96.0)

func _island_name(index: int, tier: int) -> String:
	var suffix := {1: "渔村", 2: "港镇", 3: "港城"}
	var seeds := ["白帆", "青礁", "黑砂", "落霞", "望潮", "鸣沙", "孤桅", "断锚", "碎浪"]
	return "%s%s" % [seeds[(index + map_index * 3) % seeds.size()], String(suffix.get(tier, "港"))]

func _island_port_id(index: int) -> StringName:
	return StringName("m%d_island%d" % [map_index, index])

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
		e.home_pos = e.global_position
		e.obstacles = islands
		e.world_bounds = Rect2(0, 0, SEA_SIZE, SEA_SIZE)
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
		var tier := int(isl[2])
		var tcol := Color(0.62, 0.86, 0.66) if tier >= 3 else (Color(0.78, 0.86, 0.6) if tier == 2 else Color(0.72, 0.74, 0.68))
		draw_string(ThemeDB.fallback_font, isl[0] + Vector2(-60, -float(isl[1]) - 18),
			"%s·%s" % [String(isl[3]), String(ISLAND_TIERS.get(tier, "港口"))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, tcol)
		# 港口标记
		draw_circle(isl[0], 16.0, tcol)
	# 任务目标标记（运输/护航 → 哨站）
	for q in GameState.quests_active:
		var qt := String(q.get("type", ""))
		if qt != "transport" and qt != "escort":
			continue
		var pulse := 118.0
		draw_arc(outpost_pos, pulse, 0, TAU, 32, Color(0.95, 0.85, 0.35), 3.0)
		draw_string(ThemeDB.fallback_font, outpost_pos + Vector2(-40, -150), "任务",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.85, 0.35))

	# 打捞点：画得更醒目，并标注文字
	for sv in salvages:
		draw_circle(sv, 62.0, Color(0.95, 0.82, 0.35, 0.12))
		draw_arc(sv, 62.0, 0, TAU, 28, Color(0.95, 0.82, 0.35, 0.75), 4.0)
		draw_arc(sv, 44.0, 0, TAU, 20, Color(0.85, 0.70, 0.35), 3.0)
		draw_line(sv + Vector2(-24, 0), sv + Vector2(24, 0), Color(0.85, 0.7, 0.35), 3.0)
		draw_line(sv + Vector2(0, -24), sv + Vector2(0, 24), Color(0.85, 0.7, 0.35), 3.0)
		draw_string(ThemeDB.fallback_font, sv + Vector2(-38, -84), "打捞点",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.85, 0.4))

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
	player.add_to_group("player")
	add_child(player)
	player.obstacles = islands
	player.world_bounds = Rect2(0, 0, SEA_SIZE, SEA_SIZE)

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
	# 1.5.3 世界地图（放在独立 CanvasLayer，避免被相机变换影响）
	var map_ui := CanvasLayer.new()
	map_ui.layer = 12
	add_child(map_ui)
	world_map = load("res://scripts/ui/world_map.gd").new()
	map_ui.add_child(world_map)
	world_map.visible = false
	# 1.5.6 小地图
	var mini_ui := CanvasLayer.new()
	mini_ui.layer = 13
	add_child(mini_ui)
	mini_map = load("res://scripts/ui/mini_map.gd").new()
	mini_map.sea = self
	mini_map.world_size = float(SEA_SIZE)
	mini_ui.add_child(mini_map)


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
	port_panel.position = Vector2(16, 72)
	port_panel.custom_minimum_size = Vector2(1568, 812)
	port_panel.size = Vector2(1568, 812)
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
	var isl: Array = islands[clampi(cur_port_island, 0, islands.size() - 1)]
	var tier := int(isl[2])
	var pname := String(isl[3])
	var pid := _island_port_id(cur_port_island)
	var sp_id: StringName = isl[4]
	var sp_res: Resource = DataRegistry.get_commodity(sp_id)
	_p_title("%s（%s）—— 金币 %d · 货舱 %.0f/%.0f" % [pname,
		String(ISLAND_TIERS.get(tier, "港口")), GameState.gold,
		GameState.cargo_used(), float(GameState.cargo_capacity())])

	_p_title("市场 · 本岛特产：谷物 / 木材 / %s" % (sp_res.display_name if sp_res != null else "—"))
	# 市场页签
	var mtabs := HBoxContainer.new()
	mtabs.add_theme_constant_override("separation", 8)
	port_list.add_child(mtabs)
	var tb_local := Button.new()
	tb_local.text = "本地市场"
	tb_local.custom_minimum_size = Vector2(120, 30)
	tb_local.modulate = Color(1.0, 0.92, 0.6) if port_tab == "local" else Color(1, 1, 1)
	tb_local.pressed.connect(func(): port_tab = "local"; _rebuild_port())
	mtabs.add_child(tb_local)
	var tb_world := Button.new()
	tb_world.text = "世界市场"
	tb_world.custom_minimum_size = Vector2(120, 30)
	tb_world.modulate = Color(1.0, 0.92, 0.6) if port_tab == "world" else Color(1, 1, 1)
	tb_world.pressed.connect(func(): port_tab = "world"; _rebuild_port())
	mtabs.add_child(tb_world)

	if port_tab == "world":
		_p_title("世界市场（情报页，不成交）")
		var keys2: Array = GameState.port_registry.keys()
		if keys2.is_empty():
			port_list.add_child(_p_lbl("　（还没有探索过其他港口）", 400, Color(0.55, 0.6, 0.6)))
		for k2 in keys2:
			var meta: Dictionary = GameState.port_registry[k2]
			var row2 := HBoxContainer.new()
			row2.add_theme_constant_override("separation", 10)
			port_list.add_child(row2)
			row2.add_child(_p_lbl("%s · %s" % [String(meta.get("name", k2)),
				GameState.port_name(int(meta.get("tier", 1)))], 230))
			row2.add_child(_p_lbl("第 %d 图 · 距 %d" % [int(meta.get("map", 1)),
				absi(int(meta.get("map", 1)) - map_index)], 150, Color(0.8, 0.85, 0.9)))
			var cap2 := int(TIER_STOCK.get(int(meta.get("tier", 1)), 40))
			var parts2: Array = []
			for cid2 in [&"grain", &"timber", &"rum", &"spice"]:
				var c2: Resource = DataRegistry.get_commodity(cid2)
				if c2 == null:
					continue
				var st2 := GameState.ensure_stock(StringName(k2), cid2, cap2)
				if st2 <= 0:
					continue
				var bp2 := MarketModel.buy_price(int(c2.base_price), st2, cap2, 1.0)
				parts2.append("%s %d" % [String(c2.display_name), bp2])
			row2.add_child(_p_lbl(" / ".join(parts2) if not parts2.is_empty() else "（无货）", 360,
				Color(0.82, 0.86, 0.7)))
		var back_btn := Button.new()
		back_btn.text = "返回本地市场"
		back_btn.custom_minimum_size = Vector2(140, 26)
		back_btn.pressed.connect(func(): port_tab = "local"; _rebuild_port())
		port_list.add_child(back_btn)
		return

	# 投资状态
	var ikey := _island_key()
	var lv := GameState.island_level(ikey)
	var disc := GameState.island_discount(ikey)
	var invested := GameState.island_invested(ikey)
	var next_need := GameState.island_next_threshold(ikey)
	var prog = GameState.island_upgrade_progress(ikey)
	var marg_d: float = GameState.island_marginal_discount(ikey)
	var inv_line := "投资 %d / %d · 买入折扣 %d%%（边际 +%.2f%%/千金）" % [
		invested, next_need, disc, marg_d]
	if prog != null:
		inv_line += "　｜　升格进度：还差 %d 周 / 共 %d 周" % [int(prog.total) - int(prog.elapsed), int(prog.total)]
	elif tier >= 3:
		inv_line += "　｜　已为最高等级（分红中）"
	port_list.add_child(_p_lbl("　" + inv_line, 700, Color(0.85, 0.8, 0.55)))
	var exp_by_tier := {1: 0.90, 2: 1.00, 3: 1.15}
	var exp_v := float(exp_by_tier.get(tier, 1.0))
	var scale_txt := "递增" if exp_v > 1.001 else ("递减" if exp_v < 0.999 else "不变")
	port_list.add_child(_p_lbl("　规模报酬：%s（指数 %.2f）" % [scale_txt, exp_v], 700,
		Color(0.72, 0.82, 0.78)))
	var inv_hb := HBoxContainer.new()
	inv_hb.add_theme_constant_override("separation", 8)
	port_list.add_child(inv_hb)
	for amt in [1000, 5000, 20000]:
		var ab := Button.new()
		ab.text = "注资 %d" % amt
		ab.custom_minimum_size = Vector2(110, 26)
		ab.disabled = GameState.gold < amt
		var amt_v: int = int(amt)
		ab.pressed.connect(func(): _port_invest(amt_v))
		if amt == 20000:
			var dep_btn := Button.new()
			dep_btn.text = "用存款投资"
			dep_btn.custom_minimum_size = Vector2(130, 28)
			dep_btn.disabled = GameState.bank_deposited() <= 0
			dep_btn.pressed.connect(func(): _port_invest_deposit())
			inv_hb.add_child(dep_btn)
		inv_hb.add_child(ab)

	var max_stock := 400
	# 岛屿市场：展示全部商品（特产价另有加成）
	var goods: Array = []
	for cat in GameState.CATEGORIES:
		for gid2 in GameState.commodities_of(cat):
			goods.append(gid2)
	if goods.is_empty():
		goods = [&"grain", &"timber"]
	for cid in goods:
		var c: Resource = DataRegistry.get_commodity(cid)
		var stock := GameState.ensure_stock(pid, cid, max_stock)
		var demand := 1.0
		var production := 1.0
		var bp := MarketModel.buy_price(int(c.base_price), stock, max_stock, demand)
		var sp := MarketModel.sell_price(int(c.base_price), stock, max_stock, production)
		# 特产价格随港口等级差异化：小港贵、大城便宜
		if cid == sp_id:
			var mult: float = float(SPECIALTY_PRICE_MULT.get(tier, 1.0))
			bp = int(round(float(bp) * float(mult)))
			sp = int(round(float(sp) * float(mult)))
		# 投资折扣（只作用于买入）
		var buy_disc := GameState.island_discount(_island_key())
		if buy_disc > 0:
			bp = maxi(1, int(round(float(bp) * (1.0 - float(buy_disc) / 100.0))))
		# 阶梯溢价（只作用于卖出）：目标地图不产出才有跨度溢价
		sp = int(round(float(sp) * GameState.sale_multiplier_at(cid, map_index)))
		# 市场漂移与事件
		var pmod := GameState.price_modifier(String(pid), cid)
		bp = maxi(1, int(round(float(bp) * pmod)))
		sp = maxi(1, int(round(float(sp) * pmod)))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		port_list.add_child(hb)
		hb.add_child(_p_lbl(c.display_name, 80))
		hb.add_child(_p_lbl("买 %d / 卖 %d（库存 %d）" % [bp, sp, stock], 220))
		var cid_v: StringName = cid
		var b0 := Button.new()
		b0.text = "交易"
		b0.custom_minimum_size = Vector2(80, 26)
		var bp_v := bp
		var sp_v := sp
		var st_v := stock
		b0.pressed.connect(func(): _open_island_goods(cid_v, bp_v, sp_v, st_v))
		hb.add_child(b0)
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

	# ---- 乡镇及以上：船厂 ----
	if GameState.port_service_unlocked(tier, "shipyard"):
		_p_title("船厂（乡镇起开放）")
		var shown := 0
		for cid2 in DataRegistry.cannons.keys():
			if shown >= 3:
				break
			var cd: Resource = DataRegistry.get_cannon(cid2)
			if cd == null or int(cd.pound_class) > GameState.cannon_class_cap():
				continue
			if GameState.has_cannon(cid2):
				continue
			shown += 1
			var chb := HBoxContainer.new()
			chb.add_theme_constant_override("separation", 10)
			port_list.add_child(chb)
			chb.add_child(_p_lbl(String(cd.display_name), 140))
			chb.add_child(_p_lbl("伤害 %d · 射程 %d" % [int(cd.damage), int(cd.shot_range)], 190))
			var price_c := int(cd.get("price"))
			chb.add_child(_p_lbl("%d 金" % price_c, 90, Color(0.9, 0.82, 0.45)))
			var cid2v: StringName = cid2
			var buy_c := Button.new()
			buy_c.text = "购入并换装"
			buy_c.custom_minimum_size = Vector2(110, 26)
			buy_c.disabled = GameState.gold < price_c
			buy_c.pressed.connect(func(): _port_buy_cannon(cid2v, price_c))
			chb.add_child(buy_c)
		if shown == 0:
			port_list.add_child(_p_lbl("　（本级火炮都已拥有）", 400, Color(0.5, 0.55, 0.55)))

	# ---- 乡镇及以上：酒馆 ----
	if GameState.port_service_unlocked(tier, "tavern"):
		_p_title("酒馆（乡镇起开放）")
		if _port_tavern.is_empty():
			_port_tavern = CrewFactory.generate(3, GameState.ship_variant)
		for cw in _port_tavern:
			var thb := HBoxContainer.new()
			thb.add_theme_constant_override("separation", 10)
			port_list.add_child(thb)
			thb.add_child(_p_lbl(String(cw.display_name), 150))
			thb.add_child(_p_lbl("%s · %s" % [
				String(CrewFactory.ROLE_NAMES.get(StringName(cw.role), String(cw.role))),
				Rarity.name_of(int(cw.rarity))], 170))
			thb.add_child(_p_lbl("%d 金" % int(cw.hire_cost), 100, Color(0.9, 0.82, 0.45)))
			var cwv: Resource = cw
			var hb2 := Button.new()
			hb2.text = "雇佣"
			hb2.custom_minimum_size = Vector2(70, 26)
			hb2.disabled = GameState.gold < int(cw.hire_cost)
			hb2.pressed.connect(func(): _port_hire_crew(cwv))
			thb.add_child(hb2)

	# ---- 港口城市：拍卖行 ----
	if tier >= 3:
		_p_title("拍卖行（城市专属 · 一张图一座）")
		GameState.refresh_auctions(TimeService.total_weeks())
		if GameState.auctions.is_empty():
			port_list.add_child(_p_lbl("　（本周没有挂单，下周刷新）", 400, Color(0.55, 0.6, 0.6)))
		for i in range(GameState.auctions.size()):
			var lot: Dictionary = GameState.auctions[i]
			var lhb := HBoxContainer.new()
			lhb.add_theme_constant_override("separation", 10)
			port_list.add_child(lhb)
			var lead_txt := {"player": "你领先", "npc": "NPC 领先", "": "无人出价"}
			lhb.add_child(_p_lbl(String(lot.get("name", "货品")), 240))
			lhb.add_child(_p_lbl(String(lot.get("desc", "")), 260, Color(0.75, 0.8, 0.7)))
			lhb.add_child(_p_lbl("%d 金" % int(lot.get("price", 0)), 110, Color(0.9, 0.82, 0.45)))
			lhb.add_child(_p_lbl(String(lead_txt.get(String(lot.get("leader", "")), "—")), 90,
				Color(0.7, 0.9, 0.7) if String(lot.get("leader", "")) == "player" else Color(0.85, 0.7, 0.6)))
			lhb.add_child(_p_lbl("剩 %d 周" % int(lot.get("weeks", 0)), 90))
			var bid_amt := int(ceil(float(lot.get("price", 0)) * 1.05))
			var bb := Button.new()
			bb.text = "出价 %d" % bid_amt
			bb.custom_minimum_size = Vector2(120, 26)
			bb.disabled = GameState.gold < bid_amt
			var idx_v: int = i
			var amt_v2: int = bid_amt
			bb.pressed.connect(func(): _port_bid_auction(idx_v, amt_v2))
			lhb.add_child(bb)

	# ---- 港口城市：黑市 ----
	if tier >= 3:
		_p_title("黑市（城市专属 · 独立市场）")
		if not GameState.black_market_open():
			port_list.add_child(_p_lbl("　通缉度过高，黑市被海军盯上，本周关闭", 520, Color(0.9, 0.5, 0.45)))
		else:
			port_list.add_child(_p_lbl("　销赃价 = 合法市场价 60%% · 单次 ≤ %d 单位" % int(GameState.BLACK_SELL_LIMIT),
				560, Color(0.8, 0.75, 0.6)))
			# 销赃：列出货舱里能卖的三种
			for cid3 in [&"grain", &"timber", &"rum", &"spice"]:
				var have3 := int(GameState.cargo.get(cid3, 0))
				if have3 <= 0:
					continue
				var c3: Resource = DataRegistry.get_commodity(cid3)
				if c3 == null:
					continue
				var legal_sp := MarketModel.sell_price(int(c3.base_price), _port_max_stock(), _port_max_stock(), 1.0)
				var fence_price := int(round(float(legal_sp) * 0.60))
				var hb3 := HBoxContainer.new()
				hb3.add_theme_constant_override("separation", 10)
				port_list.add_child(hb3)
				hb3.add_child(_p_lbl("%s × %d" % [String(c3.display_name), have3], 200))
				hb3.add_child(_p_lbl("销赃 %d/件" % fence_price, 140, Color(0.9, 0.75, 0.5)))
				var cid3v: StringName = cid3
				var sp3 := legal_sp
				var fb := Button.new()
				fb.text = "销赃 10"
				fb.custom_minimum_size = Vector2(90, 26)
				fb.pressed.connect(func(): _port_fence(cid3v, 10, sp3))
				hb3.add_child(fb)
			# 违禁品
			_p_title("违禁品")
			for item_id in GameState.CONTRABAND.keys():
				var cdef: Dictionary = GameState.CONTRABAND[item_id]
				var ihb := HBoxContainer.new()
				ihb.add_theme_constant_override("separation", 10)
				port_list.add_child(ihb)
				ihb.add_child(_p_lbl(String(cdef.get("name", "")), 160))
				ihb.add_child(_p_lbl(String(cdef.get("desc", "")), 340, Color(0.78, 0.82, 0.72)))
				ihb.add_child(_p_lbl("%d 金" % int(cdef.get("price", 0)), 100, Color(0.9, 0.82, 0.45)))
				var have_n := int(GameState.contraband.get(item_id, 0))
				ihb.add_child(_p_lbl("持有 %d" % have_n, 80, Color(0.7, 0.78, 0.7)))
				var iid: StringName = item_id
				var ib := Button.new()
				ib.text = "购买"
				ib.custom_minimum_size = Vector2(70, 26)
				ib.disabled = GameState.gold < int(cdef.get("price", 0))
				ib.pressed.connect(func(): _port_buy_contraband(iid))
				ihb.add_child(ib)
			# 私掠许可证
			_p_title("私掠许可证")
			if GameState.has_privateer_license:
				port_list.add_child(_p_lbl("　已持有（%s）" % ("正规" if GameState.license_is_legal else "黑市"),
					400, Color(0.7, 0.9, 0.7)))
			else:
				var lprice := int(round(float(GameState.LEGAL_LICENSE_REP) * GameState.BLACK_LICENSE_MULT * 10.0))
				var lhb2 := HBoxContainer.new()
				lhb2.add_theme_constant_override("separation", 10)
				port_list.add_child(lhb2)
				lhb2.add_child(_p_lbl("黑市私掠证（无需声望）", 240))
				lhb2.add_child(_p_lbl("%d 金 · 通缉度 +%d" % [lprice, int(GameState.BLACK_LICENSE_NOTORIETY)],
					200, Color(0.9, 0.75, 0.5)))
				var lb := Button.new()
				lb.text = "购买"
				lb.custom_minimum_size = Vector2(70, 26)
				lb.disabled = GameState.gold < lprice
				lb.pressed.connect(func(): _port_buy_license())
				lhb2.add_child(lb)

	# ---- 港口城市：银行 ----
	if tier >= 3:
		_p_title("银行（城市专属 · 全城通存通取）")
		port_list.add_child(_p_lbl("　存款 %d（周息 0.1%%）· 现金 %d" % [
			GameState.bank_deposited(), GameState.gold], 560, Color(0.8, 0.85, 0.7)))
		var bkhb := HBoxContainer.new()
		bkhb.add_theme_constant_override("separation", 8)
		port_list.add_child(bkhb)
		for amt in [1000, 10000]:
			var db := Button.new()
			db.text = "存 %d" % amt
			db.custom_minimum_size = Vector2(90, 26)
			db.disabled = GameState.gold < int(amt)
			var av: int = int(amt)
			db.pressed.connect(func(): _port_bank_deposit(av))
			bkhb.add_child(db)
		var wb := Button.new()
		wb.text = "全取"
		wb.custom_minimum_size = Vector2(70, 26)
		wb.disabled = GameState.bank_deposited() <= 0
		wb.pressed.connect(func(): _port_bank_withdraw())
		bkhb.add_child(wb)
		port_list.add_child(_p_lbl("　未还 %d 笔 · 未还本息 %d" % [
			GameState.loan_count(), GameState.loan_exposure()], 560, Color(0.9, 0.82, 0.45)))
		for i in range(GameState.loans.size()):
			var l: Dictionary = GameState.loans[i]
			var lhb := HBoxContainer.new()
			lhb.add_theme_constant_override("separation", 10)
			port_list.add_child(lhb)
			lhb.add_child(_p_lbl("贷款 %d：%d 金 · 剩 %d 周" % [i + 1,
				int(l.get("amount", 0)), int(l.get("left", 0))], 260))
			var li2: int = i
			var rbtn := Button.new()
			rbtn.text = "还清"
			rbtn.custom_minimum_size = Vector2(70, 24)
			rbtn.pressed.connect(func(): _port_bank_repay_one(li2))
			lhb.add_child(rbtn)
		var tier_row := HBoxContainer.new()
		tier_row.add_theme_constant_override("separation", 6)
		port_list.add_child(tier_row)
		var term_names := {12: "一季", 26: "半年", 52: "一年"}
		for amount in [1000, 5000, 20000, 50000, 100000]:
			var weeks_list: Array = GameState.LOAN_TERMS[amount]
			var wk2: int = int(weeks_list[0])
			var chk2: Dictionary = GameState.can_take_loan(int(amount), wk2)
			var bb2 := Button.new()
			bb2.text = "借 %d %s" % [int(amount), String(term_names.get(wk2, ""))]
			bb2.custom_minimum_size = Vector2(120, 24)
			bb2.disabled = not bool(chk2.get("ok", false))
			var amt2: int = int(amount)
			bb2.pressed.connect(func(): _port_bank_borrow(amt2, wk2))
			tier_row.add_child(bb2)

	# ---- 港口城市：交易所 / 声望 ----
	if GameState.port_service_unlocked(tier, "exchange"):
		_p_title("交易所（城市开放）")
		port_list.add_child(_p_lbl("　本港行情：%s" % _port_price_line(pid, max_stock), 600,
			Color(0.8, 0.85, 0.7)))
	if GameState.port_service_unlocked(tier, "reputation"):
		_p_title("声望与战功（城市开放）")
		var rep_parts: Array = []
		for fid_hud in GameState.FACTIONS_V2:
			rep_parts.append("%s %d" % [String(GameState.FACTION_V2_NAMES.get(fid_hud, fid_hud)),
				GameState.faction_rep_of(fid_hud)])
		port_list.add_child(_p_lbl("　%s" % " · ".join(rep_parts), 700, Color(0.8, 0.85, 0.7)))
		port_list.add_child(_p_lbl("　战功 %d" % GameState.commendation, 300, Color(0.8, 0.85, 0.7)))

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

## 本港三件商品的价格摘要
func _port_price_line(pid: StringName, max_stock: int) -> String:
	var parts: Array = []
	var isl: Array = islands[cur_port_island]
	var goods: Array = [&"grain", &"timber", isl[4]]
	for cid in goods:
		var c: Resource = DataRegistry.get_commodity(cid)
		if c == null:
			continue
		var stock := GameState.ensure_stock(pid, cid, max_stock)
		var bp := MarketModel.buy_price(int(c.base_price), stock, max_stock, 1.0)
		parts.append("%s %d" % [String(c.display_name), bp])
	return " / ".join(parts)

## 港口船厂：购入并换装火炮
func _port_buy_cannon(cid: StringName, price: int) -> void:
	if GameState.gold < price:
		hud.ticker("金币不足")
		return
	if not GameState.can_mount_cannon(cid):
		hud.ticker("当前船炮位承载不足")
		return
	var cd: Resource = DataRegistry.get_cannon(cid)
	GameState.add_gold(-price)
	if not GameState.has_cannon(cid):
		GameState.cannons_owned.append(cid)
	GameState.cannon_id = cid
	hud.ticker("购入并换装 %s" % String(cd.display_name))
	_rebuild_port()

## 港口酒馆：雇佣船员
func _port_hire_crew(crew: Resource) -> void:
	if crew == null:
		return
	if GameState.gold < int(crew.hire_cost):
		hud.ticker("金币不足")
		return
	GameState.add_gold(-int(crew.hire_cost))
	GameState.hire_crew(crew)
	_port_tavern.erase(crew)
	hud.ticker("雇佣了 %s" % String(crew.display_name))
	_rebuild_port()

## NPC 随机载货（1~2 种商品，数量按地图等级放大）
func _random_npc_cargo() -> Dictionary:
	var out: Dictionary = {}
	var pool: Array = [&"grain", &"timber", &"rum", &"spice"]
	var n := RngService.randi_range(1, 2)
	for i in range(n):
		var cid: StringName = pool[RngService.randi_range(0, pool.size() - 1)]
		out[cid] = int(out.get(cid, 0)) + RngService.randi_range(3, 8 + map_index * 2)
	return out

## 银行操作
func _port_bank_deposit(amount: int) -> void:
	if GameState.bank_deposit_gold(amount):
		hud.ticker("存入 %d 金" % amount)
		_rebuild_port()
	else:
		hud.ticker("金币不足")

func _port_bank_withdraw() -> void:
	var amt := GameState.bank_deposited()
	if GameState.bank_withdraw(amt):
		hud.ticker("取出 %d 金" % amt)
		_rebuild_port()

func _port_bank_borrow(amount: int, weeks: int) -> void:
	var r: Dictionary = GameState.bank_borrow(amount, weeks)
	if bool(r.get("ok", false)):
		hud.ticker("贷款到账，到期利息 %d" % int(r.get("interest", 0)))
		_rebuild_port()
	else:
		hud.ticker(String(r.get("reason", "贷款失败")))

func _port_bank_repay_one(index: int) -> void:
	var r: Dictionary = GameState.bank_repay_one(index)
	if bool(r.get("ok", false)):
		hud.ticker("已还清该笔 %d 金" % int(r.get("paid", 0)))
		_rebuild_port()
	else:
		hud.ticker(String(r.get("reason", "还款失败")))

## 黑市销赃
func _port_fence(cid: StringName, amount: int, legal_sell: int) -> void:
	var r: Dictionary = GameState.fence_goods(cid, amount, legal_sell)
	if bool(r.get("ok", false)):
		hud.ticker("销赃 %d 件，得 %d 金（通缉度 +2）" % [int(r.get("amount", 0)), int(r.get("gold", 0))])
		_rebuild_port()
	else:
		hud.ticker(String(r.get("reason", "销赃失败")))

## 黑市购买违禁品
func _port_buy_contraband(item_id: StringName) -> void:
	var r: Dictionary = GameState.buy_contraband(item_id)
	if bool(r.get("ok", false)):
		hud.ticker("购得违禁品（通缉度 +2）")
		_rebuild_port()
	else:
		hud.ticker(String(r.get("reason", "购买失败")))

## 黑市购买私掠许可证
func _port_buy_license() -> void:
	var r: Dictionary = GameState.buy_license_black()
	if bool(r.get("ok", false)):
		hud.ticker("取得私掠许可证（黑市途径）")
		_rebuild_port()
	else:
		hud.ticker(String(r.get("reason", "购买失败")))

## 拍卖行出价
func _port_bid_auction(index: int, price: int) -> void:
	var res: Dictionary = GameState.bid_auction(index, price)
	if bool(res.get("ok", false)):
		hud.ticker("出价 %d 金，暂时领先" % price)
		_rebuild_port()
	else:
		hud.ticker(String(res.get("reason", "出价失败")))

func _island_key() -> String:
	return GameState.island_key(map_index, cur_port_island)

func _port_max_stock() -> int:
	return int(TIER_STOCK.get(int(islands[cur_port_island][2]), 40))

## 对当前岛注资
## 岛屿市场商品详情弹窗
var goods_dlg: AcceptDialog = null

func _open_island_goods(cid: StringName, bp: int, sp: int, stock: int) -> void:
	var c: Resource = DataRegistry.get_commodity(cid)
	if c == null:
		return
	if goods_dlg != null and is_instance_valid(goods_dlg):
		goods_dlg.queue_free()
	goods_dlg = AcceptDialog.new()
	goods_dlg.title = String(c.display_name)
	goods_dlg.ok_button_text = "关闭"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	goods_dlg.add_child(vb)
	var max_stock := int(c.base_price) * 0 + 400
	var ratio := clampf(float(stock) / float(max_stock), 0.0, 1.0)
	var em = load("res://scripts/systems/econ_math.gd")
	var e: float = float(em.piecewise_elasticity(ratio))
	var etype := "富有弹性" if e >= 0.70 else ("单位弹性附近" if e >= 0.40 else "缺乏弹性")
	var eq: float = float(c.base_price) * (1.0 + e * (1.0 - ratio))
	var cur: float = float(bp)
	var dev: float = (cur - eq) / maxf(0.01, eq)
	var etype_l := Label.new()
	etype_l.text = "供给弹性 %.2f（%s）　库存 %d/%d\n均衡价 %.1f　当前买价 %d　偏离 %+.1f%%\n关税 %d%%（按声望）" % [
		e, etype, stock, max_stock, eq, bp, dev * 100.0,
		int(round(GameState.tariff_rate_for_port(GameState.visit_port_id) * 100.0))]
	vb.add_child(etype_l)
	var qrow := HBoxContainer.new()
	vb.add_child(qrow)
	qrow.add_child(Label.new())
	(qrow.get_child(0) as Label).text = "数量"
	var qty := LineEdit.new()
	qty.text = "10"
	qty.custom_minimum_size = Vector2(100, 30)
	qrow.add_child(qty)
	var brow := HBoxContainer.new()
	vb.add_child(brow)
	var cid_v: StringName = cid
	var buy_b := Button.new()
	buy_b.text = "买入"
	buy_b.custom_minimum_size = Vector2(120, 32)
	buy_b.pressed.connect(func():
		var n := clampi(int(qty.text), 1, maxi(1, stock))
		_port_buy(cid_v, n, bp)
		goods_dlg.queue_free())
	brow.add_child(buy_b)
	var sell_b := Button.new()
	sell_b.text = "卖出"
	sell_b.custom_minimum_size = Vector2(120, 32)
	sell_b.pressed.connect(func():
		var have := int(GameState.cargo.get(cid_v, 0))
		var n := clampi(int(qty.text), 1, maxi(1, have))
		_port_sell(cid_v, n, sp)
		goods_dlg.queue_free())
	brow.add_child(sell_b)
	add_child(goods_dlg)
	goods_dlg.popup_centered()

## 用存款投资
func _port_invest_deposit() -> void:
	var key := _island_key()
	var amount := int(GameState.bank_deposited() / 2)
	if amount <= 0:
		hud.ticker("银行存款不足")
		return
	var r: Dictionary = GameState.invest_from("deposit", key, amount)
	if bool(r.get("ok", false)):
		hud.ticker("存款注资 %d，投资累计 %d" % [amount, int(r.get("total", 0))])
		_rebuild_port()
	else:
		hud.ticker(String(r.get("reason", "投资失败")))

func _port_invest(amount: int) -> void:
	if GameState.invest_island(_island_key(), amount):
		hud.ticker("已注资 %d 金，投资 Lv%d" % [amount, GameState.island_level(_island_key())])
		_rebuild_port()
	else:
		hud.ticker("金币不足")

func _port_buy(cid: StringName, amount: int, price: int) -> void:
	var pid := _island_port_id(cur_port_island)
	var c: Resource = DataRegistry.get_commodity(cid)
	if GameState.gold < price * amount:
		hud.ticker("金币不足")
		return
	if GameState.cargo_free() < float(c.volume) * amount:
		hud.ticker("货舱空间不足")
		return
	var stock := GameState.ensure_stock(pid, cid, _port_max_stock())
	if stock < amount:
		hud.ticker("本港库存不足")
		return
	GameState.add_gold(-price * amount)
	GameState.add_cargo(cid, amount)
	GameState.set_stock(pid, cid, stock - amount)
	GameState.credit_island_trade(_island_key(), price * amount)
	hud.ticker("买入 %d %s" % [amount, c.display_name])
	_rebuild_port()

func _port_sell(cid: StringName, amount: int, price: int) -> void:
	if int(GameState.cargo.get(cid, 0)) < amount:
		hud.ticker("货舱里没有足够的该商品")
		return
	var pid := _island_port_id(cur_port_island)
	GameState.remove_cargo(cid, amount)
	var stock := GameState.ensure_stock(pid, cid, _port_max_stock())
	GameState.set_stock(pid, cid, stock + amount)
	GameState.add_gold(price * amount)
	GameState.credit_island_trade(_island_key(), price * amount)
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
		salvages.append(_clear_water_pos())

## 找一个"既不在岛上、也不贴着岛"的海面位置（打捞点专用）
func _clear_water_pos() -> Vector2:
	for attempt in range(60):
		var p: Vector2 = _random_spawn_pos()
		if _dist_to_nearest_island(p) > 260.0:
			return p
	# 兜底：全图找最远离岛的格子中心
	var best: Vector2 = Vector2(SEA_SIZE * 0.5, SEA_SIZE * 0.5)
	var best_d := -1.0
	for gx in range(1, 8):
		for gy in range(1, 8):
			var q := Vector2(float(gx) * SEA_SIZE / 8.0, float(gy) * SEA_SIZE / 8.0)
			var d: float = _dist_to_nearest_island(q)
			if d > best_d:
				best_d = d
				best = q
	return best

## 到最近岛屿边缘的距离（正数表示在岛外）
func _dist_to_nearest_island(p: Vector2) -> float:
	var best := 1.0e9
	for isl in islands:
		best = minf(best, p.distance_to(isl[0]) - float(isl[1]))
	return best

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
	e.cargo_hold = _random_npc_cargo()
	e.position = _random_spawn_pos(enemies.size() < NEAR_UNITS)
	e.died.connect(_on_enemy_died)
	e.disengaged.connect(_on_enemy_disengaged)
	add_child(e)
	e.home_pos = e.global_position
	e.obstacles = islands
	e.world_bounds = Rect2(0, 0, SEA_SIZE, SEA_SIZE)
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
	e.obstacles = islands
	e.world_bounds = Rect2(0, 0, SEA_SIZE, SEA_SIZE)
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
	e.cargo_hold = _random_npc_cargo()
	e.position = _random_spawn_pos()
	e.died.connect(_on_enemy_died)
	e.disengaged.connect(_on_enemy_disengaged)
	add_child(e)
	e.home_pos = e.global_position
	e.obstacles = islands
	e.world_bounds = Rect2(0, 0, SEA_SIZE, SEA_SIZE)
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
				# 越靠里越慢：边缘基本不减速，深处才明显拖慢
				n.terrain_slow = minf(float(n.terrain_slow), lerpf(1.0, 0.45, push))
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
	hud.set_prompt(interact_prompt())
	_refresh_cargo_hud()
	_refresh_hint()
	_refresh_nav_hint()
	if not game_over and port_panel != null and not port_panel.visible:
		_try_edge_travel()
	if camera != null and player != null and is_instance_valid(player):
		camera.position = player.position
	# 互动提示统一由 interact_prompt() 提供，这里不再重复一套

func _update_bounty_hunters(delta: float) -> void:
	hunter_timer -= delta
	if hunter_timer > 0.0:
		return
	# 伪造通行证：本次免检，消耗一个
	if int(GameState.contraband.get(&"forge_pass", 0)) > 0:
		GameState.contraband[&"forge_pass"] = int(GameState.contraband[&"forge_pass"]) - 1
		if int(GameState.contraband[&"forge_pass"]) <= 0:
			GameState.contraband.erase(&"forge_pass")
		hunter_timer = 45.0
		hud.ticker("伪造通行证生效：本次免于海军盘查")
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
	e.obstacles = islands
	e.world_bounds = Rect2(0, 0, SEA_SIZE, SEA_SIZE)
	enemies.append(e)
	hud.ticker("赏金猎人编队出现！（通缉度 %d）" % GameState.notoriety())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and world_map != null and world_map.visible:
			world_map.visible = false
			return
		if event.keycode == KEY_ESCAPE and port_panel != null and port_panel.visible:
			port_panel.visible = false
			return
		if event.keycode == KEY_M:
			if world_map != null:
				world_map.visible = not world_map.visible
				world_map.refresh()
			return
		if event.keycode == KEY_E:
			if port_panel != null and port_panel.visible:
				port_panel.visible = false
				return
			if player == null:
				return
			if nearest_port_island() != null:
				_toggle_island_port()
			elif _try_collect_salvage():
				pass
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
				# 比减速区（岛半径 + AVOID_MARGIN）再外扩 110px，避免刚出航线就进减速带
				var r: float = isl[1] + AVOID_MARGIN + 110.0
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
	# 1.4.0：势力巡逻队也可被锁定攻击
	for p in patrols:
		if not is_instance_valid(p) or not p.alive:
			continue
		var dp: float = p.position.distance_to(world)
		if dp < best_d:
			best_d = dp
			best = p
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
		var best_d := 1100.0 * aggro_mult
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

## 当前可做的 E 互动（用于 HUD 提示）
func interact_prompt() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	if player.global_position.distance_to(outpost_pos) < 240.0:
		if escort_ship != null and is_instance_valid(escort_ship) and escort_ship.alive:
			return "按 E 让商船靠港 / 进入浅湾哨站"
		return "按 E 进入浅湾哨站"
	var pi = nearest_port_island()
	if pi != null:
		var isl: Array = islands[int(pi)]
		return "按 E 停靠 %s（%s）" % [String(isl[3]), String(ISLAND_TIERS.get(int(isl[2]), "港口"))]
	# 航门与打捞点重叠时，取更近的那个
	var gate_d: float = player.global_position.distance_to(BACK_GATE)
	var salv_d: float = _nearest_salvage_dist()
	if gate_d < 240.0 and gate_d <= salv_d:
		return "按 E 返回母港"
	if salv_d < 250.0:
		return "按 E 打捞沉船残骸"
	if gate_d < 240.0:
		return "按 E 返回母港"
	if player.global_position.distance_to(FORWARD_GATE) < 240.0:
		if map_index >= 9:
			return "已是航道尽头"
		if GameState.is_map_cleared(map_index):
			return "按 E 前往下一海域"
		return "航门锁闭 · 击败本图 Boss 才能开启"
	return ""

func _nearest_salvage_dist() -> float:
	var best := 1.0e9
	for sv in salvages:
		best = minf(best, player.global_position.distance_to(sv))
	return best

## 把货舱内容推给 HUD
func _refresh_cargo_hud() -> void:
	var lines: Array = []
	for cid in GameState.cargo:
		var amount := int(GameState.cargo[cid])
		if amount <= 0:
			continue
		var c: Resource = DataRegistry.get_commodity(cid)
		if c == null:
			continue
		lines.append("%s × %d（占 %.0f 单位）" % [String(c.display_name), amount,
			float(amount) * float(c.volume)])
	var body := "空载" if lines.is_empty() else "\n".join(lines)
	hud.update_cargo("容量 %.0f / %.0f\n%s" % [GameState.cargo_used(),
		float(GameState.cargo_capacity()), body])

## 交战状态提示：被追击距离 / 脱离进度
func _refresh_hint() -> void:
	if player == null or not is_instance_valid(player):
		return
	var chaser = null
	var min_d := 1.0e9
	for e in enemies:
		if not is_instance_valid(e) or not e.get("alive"):
			continue
		if e.get("target") != player:
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d < min_d:
			min_d = d
			chaser = e
	if chaser == null:
		hud.set_combat_hint("")
		return
	var need: float = player.DISENGAGE_DIST
	if min_d >= need:
		var left: float = maxf(0.0, float(player.DISENGAGE_TIME) - float(chaser.get("disengage_timer")))
		hud.set_combat_hint("脱离中 · 保持距离 %.0f 秒" % left)
	else:
		hud.set_combat_hint("被追击 · 距离 %d / 需拉开 %d" % [int(min_d), int(need)])

# ---------------- 岛屿采集 ----------------

## 玩家身边可停靠的岛屿索引（从岛边算距离），没有则 null
func nearest_port_island():
	if player == null or not is_instance_valid(player):
		return null
	var best = -1
	var best_edge := 1.0e9
	for idx in range(islands.size()):
		var edge: float = player.global_position.distance_to(islands[idx][0]) - float(islands[idx][1])
		if edge <= PORT_RANGE_EXTRA and edge < best_edge:
			best_edge = edge
			best = idx
	return null if best < 0 else best

## 进入当前靠岸岛屿的港口
func _toggle_island_port() -> void:
	var idx = nearest_port_island()
	if idx == null:
		return
	if port_panel.visible:
		port_panel.visible = false
		return
	cur_port_island = int(idx)
	player.throttle = 0.0
	player.nav_target = null
	player.nav_queue.clear()
	# 1.2.2：停泊即进入城镇（复用母港面板）
	var key := GameState.island_key(map_index, int(idx))
	GameState.visit_port_id = StringName(key)
	GameState.ensure_island_buildings(StringName(key))
	GameState.last_sea_map = map_index
	SceneRouter.goto(&"base")

## 顶部罗盘：告诉玩家下一片海域怎么走
func _refresh_nav_hint() -> void:
	if player == null or not is_instance_valid(player) or hud == null:
		return
	var ep := _edge_prompt()
	if ep != "":
		hud.set_nav_hint(ep)
		return
	if GameState.is_map_cleared(map_index):
		hud.set_nav_hint("驶向任意海域边界即可离开本图")
	else:
		hud.set_nav_hint("击败本图 Boss 后可驶出边界前往下一片海域")

# ---------------- 边缘换图 ----------------

func _edge_dir() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var p: Vector2 = player.global_position
	if p.x < EDGE_TRIGGER:
		return "west"
	if p.x > SEA_SIZE - EDGE_TRIGGER:
		return "east"
	if p.y < EDGE_TRIGGER:
		return "north"
	if p.y > SEA_SIZE - EDGE_TRIGGER:
		return "south"
	return ""

## 这条边是否有相邻海域（含是否已解锁）
func _edge_info(dir: String) -> Dictionary:
	var nb: Dictionary = MAP_NEIGHBORS.get(map_index, {})
	if not nb.has(dir):
		return {}
	var target := int(nb[dir])
	var unlocked := target <= map_index or GameState.is_map_cleared(map_index)
	var nm := "翡翠港" if target == 0 else _map_name(target)
	return {"target": target, "name": nm, "unlocked": unlocked}

func _edge_prompt() -> String:
	var dir := _edge_dir()
	if dir == "":
		return ""
	var info := _edge_info(dir)
	if info.is_empty():
		return ""
	var dname := {"east": "东", "west": "西", "north": "北", "south": "南"}
	if not bool(info.get("unlocked", false)):
		return "向%s是 %s · 击败本图 Boss 才能通航" % [String(dname.get(dir)), String(info.get("name"))]
	return "向%s继续航行即可进入 %s" % [String(dname.get(dir)), String(info.get("name"))]

func _try_edge_travel() -> void:
	if not SceneRouter.has_host():
		return
	# 只有靠近前进航门才弹航线选择（否则每帧都会弹）
	if player == null or not is_instance_valid(player):
		return
	if player.global_position.distance_to(FORWARD_GATE) > 240.0:
		return
	if travel_panel != null and is_instance_valid(travel_panel):
		return
	# 1.3.2：邻接图航行，前进门打开航线选择
	var opts: Array = GameState.travel_options()
	var usable: Array = []
	for o in opts:
		if int(o["index"]) != 0:
			usable.append(o)
	if usable.is_empty():
		hud.ticker("没有可前往的相邻海域")
		return
	_open_travel_panel(usable)

var travel_panel: AcceptDialog = null

func _open_travel_panel(options: Array) -> void:
	if travel_panel != null and is_instance_valid(travel_panel):
		travel_panel.queue_free()
	travel_panel = AcceptDialog.new()
	travel_panel.title = "选择航线"
	travel_panel.ok_button_text = "取消"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	travel_panel.add_child(vb)
	for o in options:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)
		var nm := Label.new()
		nm.text = String(o["name"])
		nm.custom_minimum_size = Vector2(260, 0)
		row.add_child(nm)
		var lv := Label.new()
		lv.text = "%d 级" % int(o["tier"])
		lv.custom_minimum_size = Vector2(90, 0)
		row.add_child(lv)
		var btn := Button.new()
		btn.text = "前往" if bool(o["unlocked"]) else "未解锁"
		btn.disabled = not bool(o["unlocked"])
		btn.custom_minimum_size = Vector2(110, 30)
		var target := int(o["index"])
		btn.pressed.connect(func(): _do_travel(target))
		row.add_child(btn)
	add_child(travel_panel)
	travel_panel.popup_centered()

func _do_travel(target: int) -> void:
	if travel_panel != null and is_instance_valid(travel_panel):
		travel_panel.queue_free()
	if not GameState.can_travel_to(target):
		hud.ticker("该海域尚未解锁")
		return
	_sync_to_game_state()
	GameState.current_map = target
	GameState.sea_position = Vector2(SEA_SIZE * 0.5, SEA_SIZE * 0.5)
	var nmd: Resource = DataRegistry.get_map(target)
	hud.ticker("驶入 %s" % (String(nmd.display_name) if nmd != null else str(target)))
	SceneRouter.goto(&"sea")

# ---------------- 势力巡逻队（1.3.5） ----------------

const PatrolShipScript = preload("res://scripts/sea/patrol_ship.gd")
var patrols: Array = []

## 按海图归属生成巡逻队（仅在当前海图存在，离图即销毁）
func _spawn_patrols() -> void:
	for p in patrols:
		if is_instance_valid(p):
			p.queue_free()
	patrols.clear()
	var cfg: Array = GameState.patrol_config_for_map(map_index)
	for entry in cfg:
		var nation: String = GameState.faction_id_of(String(entry["nation"]))
		var count: int = int(entry["count"])
		var col: Color = GameState.NATION_COLORS.get(nation, Color(0.7, 0.7, 0.7))
		for i in range(count):
			var ship := Node2D.new()
			ship.set_script(PatrolShipScript)
			add_child(ship)
			var route := _patrol_route(i, count, nation)
			ship.setup(nation, route, col)
			ship.add_to_group("patrols")
			patrols.append(ship)

## 巡逻航线：本国沿海岸线绕行，交界图则穿越中央
func _patrol_route(idx: int, total: int, nation: String) -> Array:
	var cx := SEA_SIZE * 0.5
	var cy := SEA_SIZE * 0.5
	var side := 1.0 if idx % 2 == 0 else -1.0
	var radius := 900.0 + float(idx) * 180.0
	var points: Array = []
	for k in range(4):
		var ang := TAU * float(k) / 4.0 + side * 0.4
		points.append(Vector2(cx + cos(ang) * radius * 1.6, cy + sin(ang) * radius))
	return points

func _tick_patrols(_delta: float) -> void:
	if patrols.is_empty():
		return
	var alive_list: Array = []
	for p in patrols:
		if is_instance_valid(p) and p.alive:
			alive_list.append(p)
	patrols = alive_list

# ---------------- 势力巡逻队生成结束 ----------------
func _lock_target(enemy) -> void:
	player.auto_fire = false
	player.target = enemy
	player.engaged = true
	# 锁定只是"瞄准/观察"，不强迫对方开战。
	# 敌方是否还击由它自己的 AI 决定；只有真的打疼它，它才会被动还手（见 take_damage）
	hud.ticker("锁定：%s" % enemy.display_name)

# ---------------- HUD 回调 ----------------

func _on_fire_pressed() -> void:
	if player == null:
		return
	var t = player.target
	if t == null or not is_instance_valid(t) or not t.alive:
		hud.ticker("先锁定一个目标")
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
	# 撤离 = 自动驶离当前目标，但不免除"必须真的拉开距离"这条规则：
	# 敌人仍会追，直到满足 1600px / 5 秒的脱战条件
	var away_dir: Vector2 = Vector2.RIGHT.rotated(player.heading)
	if t != null and is_instance_valid(t):
		away_dir = (player.global_position - t.global_position).normalized()
	player.target = null
	player.engaged = false
	var flee: Vector2 = (player.position + away_dir * 1800.0).clamp(
		Vector2(100, 100), Vector2(SEA_SIZE - 100, SEA_SIZE - 100))
	player.nav_queue = _route_to(flee)
	player.nav_target = null
	player.dodging = true
	player.dodge_timer = 8.0
	hud.ticker("撤离中：甩开追击 5 秒即可脱战")
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
	# 1.3.8：击沉结算势力声望（阵营 → 势力 id，等级取船只等级）
	var fid: String = GameState.faction_for_kill(map_index, String(ship.get("faction")))
	var shp_level := clampi(int(ceil(float(map_index) / 3.0)), 1, 10)
	GameState.apply_ship_rep(fid, shp_level)
	if by_player:
		hud.ticker("%s 声望 %+d" % [String(GameState.FACTION_V2_NAMES.get(fid, fid)), -shp_level])
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

## 兼容旧接口：航门逻辑已被边缘换图取代
func _go_back() -> void:
	return

func _go_back_unused() -> void:
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
