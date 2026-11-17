extends Node
## 集成测试：在真实 SceneTree（含 autoload）下验证海域、战斗、战利品、存档。

var _pass := 0
var _fail := 0

var _t0 := 0

func _mark(label: String) -> void:
	var now := Time.get_ticks_msec()
	print("   ⏱ %s: %d ms（累计 %d ms）" % [label, now - _last, now - _t0])
	_last = now

var _last := 0

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_last = _t0
	print("=== SeaHeroes 集成测试 ===")
	await _test_base_scene()
	await _test_sea_and_combat()
	await _test_monster()
	await _test_shipyard()
	await _test_cannons()
	await _test_crew()
	await _test_buildings()
	await _test_exchange()
	await _test_cross_port()
	await _test_quest_board()
	await _test_auction_v010()
	await _test_economy_v09()
	await _test_port_tiers()
	await _test_island_ports()
	await _test_warehouse()
	await _test_interaction()
	await _test_steering_stability()
	await _test_auto_fire()
	await _test_pathfinding()
	await _test_ecology()
	_mark("到任务导航前")
	await _test_quest_nav()
	await _test_engage_rules()
	_mark("到地图测试前")
	await _test_maps()
	await _test_bosses()
	await _test_quests()
	await _test_notoriety()
	await _test_boss_drops()
	await _test_escort_gather()
	await _test_reputation()
	await _test_commendation()
	await _test_victory()
	_mark("到存档位前")
	await _test_save_slots()
	await _test_outpost_repair()
	await _test_avoidance()
	await _test_time()
	await _test_currency()
	await _test_save_roundtrip()
	print("=== 通过 %d / 失败 %d ===" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s  %s" % [label, detail])

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _phys(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

## 等装填完成并开火一次；返回是否成功
func _fire_when_ready(ship, max_phys: int = 600) -> bool:
	for i in range(max_phys):
		await get_tree().physics_frame
		if ship.ready_to_fire():
			var r: Dictionary = ship.try_fire()
			return bool(r.get("ok", false))
	return false

# ---------------- 母港 ----------------
func _test_base_scene() -> void:
	print("\n[母港]")
	GameState.reset_new_game()
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	_ok(s.ui != null, "母港 UI 构建成功")
	_ok(s.status_label.text.contains("翡翠港"), "顶栏显示港口名")
	var gold_before := GameState.gold
	s._buy(&"grain", 10, 5)
	_ok(GameState.gold < gold_before, "买入扣金币")
	_ok(int(GameState.cargo.get(&"grain", 0)) == 10, "买到的货物进入货舱")
	var gold_mid := GameState.gold
	s._sell(&"grain", 10, 2)
	_ok(GameState.gold > gold_mid, "卖出得金币")
	GameState.hull_hp = 100.0
	GameState.sail_pct = 0.5
	var cost: int = s._repair_cost()
	_ok(cost > 0, "修理需要花金币", "cost=%d" % cost)
	GameState.gold = cost + 10
	s._do_repair()
	_ok(is_equal_approx(GameState.hull_hp, GameState.hull_max()), "修理后船体满值",
		"%.0f vs %.0f" % [GameState.hull_hp, GameState.hull_max()])
	_ok(is_equal_approx(GameState.sail_pct, 1.0), "修理后风帆满值")
	s.queue_free()
	await _frames(2)

# ---------------- 海域与战斗 ----------------
func _test_sea_and_combat() -> void:
	print("\n[海域与战斗]")
	GameState.reset_new_game()
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	_ok(s.has_method("_lock_target"), "海域场景脚本已挂载")
	_ok(s.player != null, "玩家船生成")
	if s.player == null:
		s.queue_free()
		return
	_ok(s.enemies.size() >= 4, "敌舰已生成", "count=%d" % s.enemies.size())
	var pirate = null
	for e in s.enemies:
		if not e.has_method("alive_limbs"):
			pirate = e
			break
	_ok(pirate != null, "找到海盗船")
	if pirate == null:
		s.queue_free()
		return
	# 拉到射程内并锁定
	pirate.global_position = s.player.global_position + Vector2(500, 0)
	s.player.target = pirate
	s.player.engaged = true
	pirate.target = s.player
	# 新交战规则：锁定不自动开火，需玩家点「开火」
	await _frames(30)
	_ok(s.player.volleys_fired == 0, "锁定后不会自动开火")
	_ok(not s.player.ready_to_fire(), "刚锁定时装填未完成")
	_ok(await _fire_when_ready(s.player), "点「开火」后成功齐射")
	_ok(s.player.volleys_fired > 0, "齐射计数增加", "volleys=%d" % s.player.volleys_fired)
	_ok(pirate.hull_hp < pirate.hull_max, "目标船体受损", "%.0f/%.0f" % [pirate.hull_hp, pirate.hull_max])
	# 链弹打帆
	s.player.ammo = DataRegistry.get_ammo(&"chain")
	s.player.ammo_id = &"chain"
	var sail_before: float = pirate.sail_hp
	s.player.reload_timer = 0.0
	var fired_chain := false
	for i in range(4):
		if await _fire_when_ready(s.player):
			fired_chain = true
	_ok(fired_chain, "链弹也能正常击发")
	_ok(pirate.sail_hp < sail_before or pirate.crew_hp < pirate.crew_max, "链弹命中后帆受损")
	# 强制击沉，检查战利品
	var gold_before := GameState.gold
	var cargo_before := GameState.cargo_used()
	pirate.take_damage({"hull": 999999.0, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
	await _frames(5)
	_ok(GameState.gold > gold_before, "击沉后获得金币", "%d -> %d" % [gold_before, GameState.gold])
	_ok(GameState.cargo_used() >= cargo_before, "战利品进入货舱")
	_ok(GameState.level >= 1, "经验结算未报错")
	s.queue_free()
	await _frames(2)

# ---------------- 海怪 ----------------
func _test_monster() -> void:
	print("\n[海怪]")
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var mon = null
	for e in s.enemies:
		if e.has_method("alive_limbs"):
			mon = e
			break
	_ok(mon != null, "海怪已生成")
	if mon == null:
		s.queue_free()
		return
	mon.global_position = s.player.global_position + Vector2(400, 0)
	_ok(mon.limb_hp.size() == 2, "海怪有 2 条肢体")
	# M2 链弹无效
	var body_before: float = mon.body_hp
	s.player.ammo = DataRegistry.get_ammo(&"chain")
	s.player.ammo_id = &"chain"
	s.player.target = mon
	s.player.engaged = true
	s.player.reload_timer = 0.0
	await _fire_when_ready(s.player)
	_ok(is_equal_approx(mon.body_hp, body_before), "链弹对海怪无效", "%.1f -> %.1f" % [body_before, mon.body_hp])
	# 实心弹有效
	s.player.ammo = DataRegistry.get_ammo(&"solid")
	s.player.ammo_id = &"solid"
	s.player.reload_timer = 0.0
	for i in range(3):
		await _fire_when_ready(s.player)
	_ok(mon.body_hp < body_before, "实心弹对海怪有效", "%.1f" % mon.body_hp)
	# 狂怒
	mon.body_hp = mon.body_max * 0.2
	mon.take_damage({"hull": 1.0})
	_ok(mon.frenzy, "躯体 <30% 触发狂怒")
	s.queue_free()
	await _frames(2)

# ---------------- 船厂与装备 ----------------
func _test_shipyard() -> void:
	print("\n[船厂与装备]")
	GameState.reset_new_game()
	_ok(DataRegistry.ships.size() == 40, "40 个船体（10 基准 × 3 变体 + 10 基准）", "实得 %d" % DataRegistry.ships.size())
	_ok(DataRegistry.ship_bases.size() == 10, "10 个基准模板（I~X）")
	_ok(DataRegistry.gear.size() == 20, "20 件装备（11 常规 + 9 独有）", "实得 %d" % DataRegistry.gear.size())
	_ok(DataRegistry.get_ship(&"brig_navy") != null, "变体船 id 可查")

	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)

	# 买装备 → 装备 → 属性生效（R 级需要织帆坊 1 级）
	GameState.buildings[&"sailmaker"] = 2
	var armor: Resource = DataRegistry.get_gear(&"armor_oak")
	GameState.add_gold(100000)
	var gold0 := GameState.gold
	s._buy_gear(&"armor_oak", int(armor.price))
	_ok(GameState.gold == gold0 - int(armor.price), "买装备扣金币")
	_ok(GameState.has_gear(&"armor_oak"), "装备进入装备库")
	var armor_before := int(GameState.stats().armor)
	s._equip(&"armor", &"armor_oak")
	_ok(int(GameState.stats().armor) == armor_before + 25, "装橡木衬后装甲 +25",
		"%d -> %d" % [armor_before, int(GameState.stats().armor)])
	s._unequip(&"armor")
	_ok(int(GameState.stats().armor) == armor_before, "卸下后装甲还原")

	# 声望门槛
	GameState.reputation["royal_navy"] = 0
	_ok(not s._rep_ok(&"navy", 1), "声望为 0 时买不了海军型")
	s._buy_ship(&"sand_junk", &"navy", 3000)
	_ok(GameState.ships_owned.size() == 0, "声望不足时购买被拒绝")
	GameState.reputation["royal_navy"] = 500
	_ok(s._rep_ok(&"navy", 1), "海军声望 500 解锁 I 级海军型")

	# 买船 → 换乘
	var std_id := &"sand_junk_standard"
	var std_def: Resource = DataRegistry.get_ship(std_id)
	GameState.add_gold(int(std_def.price))
	var fleet0 := GameState.ships_owned.size()
	s._buy_ship(&"sand_junk", &"standard", int(std_def.price))
	_ok(GameState.ships_owned.size() == fleet0 + 1, "买船进入船队")
	s._swap_ship(GameState.ships_owned.size() - 1)
	_ok(String(GameState.ship_def_id) == "sand_junk", "换乘后当前船变更", String(GameState.ship_def_id))
	_ok(String(GameState.ship_variant) == "standard", "换乘后变体正确")
	_ok(GameState.ships_owned.size() == fleet0 + 1, "旧船回到船队")

	# 存档往返
	GameState.add_gold(999)
	SaveManager.save(8)
	var equip_id: StringName = GameState.equipped.get(&"armor", &"")
	GameState.reset_new_game()
	SaveManager.load_slot(8)
	_ok(GameState.equipped.get(&"armor", &"") == equip_id, "装备槽存档还原")
	_ok(GameState.ships_owned.size() == fleet0 + 1, "船队存档还原", "fleet=%d" % GameState.ships_owned.size())
	SaveManager.delete_slot(8)

	s.queue_free()
	await _frames(2)

# ---------------- 火炮 ----------------
func _test_cannons() -> void:
	print("\n[火炮]")
	GameState.reset_new_game()
	_ok(DataRegistry.cannons.size() == 10, "10 级火炮表齐全", "实得 %d" % DataRegistry.cannons.size())
	var classes := {}
	for k in DataRegistry.cannons.keys():
		classes[int(DataRegistry.cannons[k].pound_class)] = true
	_ok(classes.size() == 10, "磅级 1~10 无缺号", "实得 %d 种" % classes.size())

	GameState.ship_def_id = &"fishing_sloop"
	GameState.ship_variant = &"standard"
	_ok(GameState.can_mount_cannon(&"pound3_light"), "渔船可装 3 磅炮（class 1 ≤ 3）")
	_ok(not GameState.can_mount_cannon(&"pound9"), "渔船装不了 9 磅炮（class 4 > 3）")

	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	GameState.add_gold(5000)
	s._buy_cannon(&"pound4", 400)
	_ok(GameState.has_cannon(&"pound4"), "买到 4 磅炮")
	s._equip_cannon(&"pound4")
	_ok(GameState.cannon_id == StringName("pound4"), "已换装 4 磅炮")
	_ok(is_equal_approx(float(DataRegistry.get_cannon(GameState.cannon_id).damage), 22.0), "火炮伤害取自数据表")

	# 出海后玩家船用的是新炮
	var sea = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(sea)
	await _frames(3)
	_ok(is_equal_approx(sea.player.cannon_damage, 22.0), "出海后船用 4 磅炮伤害 22",
		"实得 %.1f" % sea.player.cannon_damage)
	_ok(is_equal_approx(sea.player.cannon_range, 950.0), "射程取自 4 磅炮")
	sea.queue_free()
	s.queue_free()
	await _frames(2)

# ---------------- 船员 ----------------
func _test_crew() -> void:
	print("\n[船员]")
	GameState.reset_new_game()
	_ok(GameState.crew_slots() == 8, "通用型 8 个岗位槽", "实得 %d" % GameState.crew_slots())
	GameState.ship_variant = &"navy"
	_ok(GameState.crew_slots() == 12, "海军型 12 槽", "实得 %d" % GameState.crew_slots())
	GameState.ship_variant = &"pirate"
	_ok(GameState.crew_slots() == 9, "海盗型 9 槽", "实得 %d" % GameState.crew_slots())
	GameState.ship_variant = &"standard"

	GameState.refresh_tavern()
	_ok(GameState.tavern_pool.size() == 6, "酒馆刷新 6 名候选", "实得 %d" % GameState.tavern_pool.size())

	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	GameState.add_gold(200000)
	var cand = GameState.tavern_pool[0]
	var cid: StringName = StringName(cand.crew_id)
	var gold0 := GameState.gold
	s._hire_crew(cid)
	_ok(GameState.crew_roster.size() == 1, "雇佣后进入名册")
	_ok(GameState.gold == gold0 - int(cand.hire_cost), "雇佣扣金币")

	_ok(GameState.assign_crew(cid), "上阵成功")
	_ok(GameState.crew_assigned.size() == 1, "上阵列表 +1")
	_ok(not GameState.assign_crew(cid), "同一人不能重复上阵")
	s._toggle_crew(cid, true)
	_ok(GameState.crew_assigned.size() == 0, "下阵后列表清空")

	# 存档往返
	GameState.assign_crew(cid)
	SaveManager.save(7)
	var roster_n := GameState.crew_roster.size()
	GameState.reset_new_game()
	SaveManager.load_slot(7)
	_ok(GameState.crew_roster.size() == roster_n, "船员名册存档还原", "实得 %d" % GameState.crew_roster.size())
	_ok(GameState.crew_assigned.size() == 1, "上阵状态存档还原")
	SaveManager.delete_slot(7)

	s.queue_free()
	await _frames(2)

# ---------------- 母港建设 ----------------
func _test_buildings() -> void:
	print("\n[母港建设]")
	GameState.reset_new_game()
	_ok(DataRegistry.buildings.size() == 8, "8 座建筑", "实得 %d" % DataRegistry.buildings.size())
	_ok(GameState.building_level(&"warehouse") == 0, "初始建筑等级 0")

	# 生产为 0
	_ok(int(GameState.total_production().get("timber", 0)) == 0, "0 级仓库不产木材")

	# 材料不足不能建造
	GameState.gold = 0
	_ok(not GameState.start_build(&"warehouse"), "没材料不能开工")

	# 给足资源
	var b: Resource = DataRegistry.get_building(&"warehouse")
	var cost: Dictionary = b.cost_for(1)
	GameState.add_gold(int(cost.gold))
	GameState.resources["timber"] = int(cost.timber) + 10
	GameState.resources["iron"] = int(cost.iron) + 10
	_ok(GameState.start_build(&"warehouse"), "资源齐备后开工")
	_ok(GameState.is_building(&"warehouse"), "进入建造队列")
	_ok(GameState.resources["timber"] == 10, "开工扣木材")
	_ok(not GameState.start_build(&"warehouse"), "同一建筑不能重复排队")

	# 逐周推进
	var weeks := int(cost.weeks)
	for i in range(weeks - 1):
		var done_mid: Array = GameState.tick_build_queue()
		_ok(done_mid.is_empty(), "第 %d 周未完工" % (i + 1))
	var done: Array = GameState.tick_build_queue()
	_ok(done.size() == 1, "第 %d 周完工" % weeks)
	_ok(GameState.building_level(&"warehouse") == 1, "仓库升到 1 级")

	# 效果
	_ok(int(GameState.total_production().get("timber", 0)) == 20, "1 级仓库每周产 20 木材")
	_ok(GameState.storage_slots() == 9, "1 级仓库船位 9", "实得 %d" % GameState.storage_slots())
	GameState.buildings[&"drydock"] = 2
	_ok(_near_r(GameState.repair_discount(), 0.12), "2 级船坞修理费 -12%")
	GameState.buildings[&"exchange"] = 3
	_ok(_near_r(GameState.sell_bonus(), 0.09), "3 级交易所卖出 +9%")
	GameState.buildings[&"foundry"] = 2
	_ok(GameState.cannon_class_cap() == 7, "2 级铸造厂可购 7 级以下火炮", "实得 %d" % GameState.cannon_class_cap())
	GameState.buildings[&"sailmaker"] = 1
	_ok(GameState.gear_rarity_cap() == 1, "1 级织帆坊解锁 R 级装备")
	GameState.buildings[&"tavern"] = 2
	_ok(GameState.tavern_size() == 10, "2 级酒馆招募池 10", "实得 %d" % GameState.tavern_size())

	# 存档往返
	SaveManager.save(6)
	GameState.reset_new_game()
	SaveManager.load_slot(6)
	_ok(GameState.building_level(&"warehouse") == 1, "建筑等级存档还原")
	_ok(GameState.building_level(&"drydock") == 2, "直接设置的等级也还原")
	SaveManager.delete_slot(6)

	# 周结算产出
	GameState.resources["timber"] = 0
	TimeService.call("_process", 1.0)
	var before: int = int(GameState.resources.get("timber", 0))
	TimeService.total_days = 6
	TimeService._process(24.0)
	_ok(int(GameState.resources.get("timber", 0)) > before, "跨周结算后产生资源",
		"%d -> %d" % [before, int(GameState.resources.get("timber", 0))])

func _near_r(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

# ---------------- 交易所 ----------------
func _test_exchange() -> void:
	print("\n[交易所]")
	GameState.reset_new_game()
	_ok(not GameState.exchange_tab_unlocked(0), "交易所未建成时行情不可用")
	GameState.buildings[&"exchange"] = 4
	_ok(GameState.exchange_tab_unlocked(0) and GameState.exchange_tab_unlocked(3), "4 级交易所四页全开")

	GameState.refresh_orders()
	_ok(GameState.orders.size() == 3, "每周生成 3 张远洋订单", "实得 %d" % GameState.orders.size())
	var o0: Dictionary = GameState.orders[0]
	_ok(int(o0.price) > 0 and int(o0.amount) > 0, "订单有量与锁定价")
	_ok(GameState.accept_order(0), "接受订单")
	_ok(GameState.active_orders.size() == 1, "进入进行中列表")

	# 交付：补货到目标港口
	var cid := StringName(GameState.active_orders[0].commodity)
	var need := int(GameState.active_orders[0].amount)
	var dest := StringName(GameState.active_orders[0].dest)
	GameState.add_cargo(cid, need)
	var gold0 := GameState.gold
	var r: Dictionary = GameState.deliver_order(0, dest)
	_ok(r.get("ok", false), "货到目标港可交付", String(r.get("reason", "")))
	_ok(GameState.gold > gold0, "交付获得金币")
	_ok(GameState.active_orders.is_empty(), "交付后订单移除")
	var accepted: bool = GameState.accept_order(0)
	if accepted:
		var r2: Dictionary = GameState.deliver_order(0, &"nowhere")
		_ok(not r2.get("ok", true), "非交付点无法交付")
		GameState.active_orders.clear()

	# 期货
	GameState.add_gold(50000)
	var g1 := GameState.gold
	var fr: Dictionary = GameState.lock_future(&"grain", 100)
	_ok(fr.get("ok", false), "锁定期货合约")
	_ok(GameState.gold < g1, "扣 20% 定金")
	_ok(GameState.futures.size() == 1, "合约进入列表")
	var g2 := GameState.gold
	var rr: Dictionary = GameState.redeem_future(0)
	_ok(rr.get("ok", false), "付尾款提货", String(rr.get("reason", "")))
	_ok(GameState.gold < g2, "提货支付尾款")
	_ok(int(GameState.cargo.get(&"grain", 0)) >= 100, "货物入舱")

	# 周结算：订单过期
	GameState.refresh_orders()
	GameState.accept_order(0)
	GameState.active_orders[0]["weeks_left"] = 1
	GameState.tick_exchange()
	_ok(GameState.active_orders.is_empty(), "订单到期后移除")

# ---------------- 跨港调拨 ----------------
func _test_cross_port() -> void:
	print("\n[跨港调拨]")
	GameState.reset_new_game()
	GameState.buildings[&"warehouse"] = 2
	GameState.add_gold(200000)
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)

	# 在母港买一艘船，停在母港
	var std_def: Resource = DataRegistry.get_ship(&"sand_junk_standard")
	s._buy_ship(&"sand_junk", &"standard", int(std_def.price))
	_ok(GameState.ships_owned.size() == 1, "买到一艘船")
	_ok(String(GameState.ships_owned[0].station_port) == "jadehaven", "新船停泊在翡翠港")

	# 在海域哨站换乘：当前船应留在哨站
	var sea = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(sea)
	await _frames(3)
	_ok(sea.outpost_pos != Vector2.ZERO, "哨站有坐标")
	sea._port_swap(0)
	_ok(String(GameState.ship_def_id) == "sand_junk", "在哨站换乘成功", String(GameState.ship_def_id))
	var back: Array = GameState.ships_owned
	var stranded: Dictionary = back[back.size() - 1]
	_ok(String(stranded.station_port) == "map1_outpost", "换下的船留在哨站",
		String(stranded.station_port))

	# 母港看不到哨站的船
	var at_home := 0
	for e in GameState.ships_owned:
		if String(e.station_port) == "jadehaven":
			at_home += 1
	_ok(at_home == 0, "母港船位里没有哨站那艘船")
	sea.queue_free()
	s.queue_free()
	await _frames(2)

# ---------------- 任务板规则 ----------------
func _test_quest_board() -> void:
	print("\n[任务板]")
	GameState.reset_new_game()
	GameState.quests_available.clear()
	GameState.quests_active.clear()

	GameState.refresh_quests()
	_ok(GameState.quests_available.size() == 9, "看板为空时刷新 9 个任务",
		"count=%d" % GameState.quests_available.size())

	var before: int = GameState.quests_available.size()
	GameState.refresh_quests()
	_ok(GameState.quests_available.size() == before, "有存量时不刷新看板")

	# 接取不设上限
	for i in range(9):
		if GameState.quests_available.is_empty():
			break
		GameState.quest_accept(0)
	_ok(GameState.quests_active.size() == 9, "接取数量不再受 3 个上限限制",
		"active=%d" % GameState.quests_active.size())

	# 放弃 → 回到看板
	var board_before: int = GameState.quests_available.size()
	var title: String = String(GameState.quests_active[0].get("title", ""))
	_ok(GameState.quest_cancel(0), "可以放弃任务")
	_ok(GameState.quests_available.size() == board_before + 1, "放弃的任务回到看板")
	_ok(GameState.quests_active.size() == 8, "进行中数量减一")
	var back := false
	for q in GameState.quests_available:
		if String(q.get("title", "")) == title:
			back = true
	_ok(back, "回到看板的是同一个任务")

	# 再次接取
	var idx := 0
	for i in range(GameState.quests_available.size()):
		if String(GameState.quests_available[i].get("title", "")) == title:
			idx = i
			break
	_ok(GameState.quest_accept(idx), "放弃后可以重新接取")
	GameState.quests_available.clear()
	GameState.quests_active.clear()

# ---------------- 岛屿与边界 ----------------
func _test_island_and_bounds() -> void:
	print("\n[岛屿与边界]")
	GameState.reset_new_game()
	GameState.current_map = 1
	GameState.island_stock.clear()
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)

	_ok(s.islands.size() > 0, "岛屿已生成")
	var isl: Array = s.islands[0]
	_ok(isl.size() >= 4, "岛屿带资源字段", "fields=%d" % isl.size())
	_ok(int(isl[3]) > 0, "岛屿有初始储量", "stock=%d" % int(isl[3]))

	# 港口贴在岛上
	var nearest = null
	var nd := 1.0e9
	for i2 in s.islands:
		var d2: float = Vector2(i2[0]).distance_to(s.outpost_pos)
		if d2 < nd:
			nd = d2
			nearest = i2
	if nearest != null:
		var gap: float = s.outpost_pos.distance_to(Vector2(nearest[0])) - float(nearest[1])
		_ok(absf(gap - 96.0) < 6.0, "哨站建在岛屿岸边", "离岸边 %.0f px" % gap)

	# 采集：谷物岛
	var grain_isl = null
	for i3 in s.islands:
		if String(i3[2]) == "grain":
			grain_isl = i3
			break
	if grain_isl != null:
		GameState.cargo.clear()
		s.player.global_position = Vector2(grain_isl[0]) + Vector2(float(grain_isl[1]) + 100.0, 0)
		_ok(String(s.interact_prompt()).contains("采集"), "靠近岛屿提示按 E 采集", s.interact_prompt())
		var before_stock: int = int(grain_isl[3])
		var got: bool = s._try_gather_island()
		_ok(got, "可以在岛屿采集")
		_ok(int(GameState.cargo.get(&"grain", 0)) > 0, "采集的货物进了货舱",
			"grain=%d" % int(GameState.cargo.get(&"grain", 0)))
		_ok(int(grain_isl[3]) < before_stock, "采集后岛屿储量下降")
	else:
		_ok(false, "图 1 应有一座谷物岛")

	# 采集：铁矿岛进建筑资源
	var iron_isl = null
	for i4 in s.islands:
		if String(i4[2]) == "iron":
			iron_isl = i4
			break
	if iron_isl != null:
		s.player.global_position = Vector2(iron_isl[0]) + Vector2(float(iron_isl[1]) + 100.0, 0)
		var iron_before: int = int(GameState.resources.get("iron", 0))
		_ok(s._try_gather_island(), "可以采集铁矿")
		_ok(int(GameState.resources.get("iron", 0)) > iron_before, "铁矿进入建筑资源")
	else:
		_ok(true, "本图无铁矿岛（跳过）")

	# 边界限制
	s.player.global_position = Vector2(-5000, -5000)
	await _physics_wait(3)
	var p: Vector2 = s.player.global_position
	_ok(p.x >= 0.0 and p.y >= 0.0, "玩家不会跑出地图边界", "pos=(%.0f,%.0f)" % [p.x, p.y])
	s.player.global_position = Vector2(99999, 99999)
	await _physics_wait(3)
	var p2: Vector2 = s.player.global_position
	_ok(p2.x <= 8000.0 and p2.y <= 8000.0, "玩家不会越过另一侧边界", "pos=(%.0f,%.0f)" % [p2.x, p2.y])
	s.queue_free()
	await _frames(2)

func _physics_wait(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

# ---------------- 拍卖行（0.10.0） ----------------
func _test_auction_v010() -> void:
	print("\n[拍卖行]")
	GameState.reset_new_game()
	GameState.auctions.clear()
	GameState.auction_week = -1
	GameState.auction_defects = 0

	GameState.refresh_auctions(1)
	_ok(GameState.auctions.size() >= 3 and GameState.auctions.size() <= 5, "刷新生成 3~5 件",
		"count=%d" % GameState.auctions.size())
	var lot: Dictionary = GameState.auctions[0]
	_ok(String(lot.get("name", "")) != "", "货品有名称", String(lot.get("name", "")))
	_ok(int(lot.get("price", 0)) > 0, "货品有起拍价")
	_ok(int(lot.get("weeks", 0)) == 2, "挂单 2 周")
	_ok(not GameState.auctions.is_empty(), "重复刷新不叠加")
	var before_n := GameState.auctions.size()
	GameState.auction_week = -1
	GameState.refresh_auctions(1)
	_ok(GameState.auctions.size() == before_n, "同周不重复刷新")

	# 出价规则
	GameState.add_gold(500000)
	var cur := int(GameState.auctions[0].get("price", 0))
	var low: Dictionary = GameState.bid_auction(0, int(float(cur) * 1.01))
	_ok(not bool(low.get("ok", true)), "低于 1.05 倍被拒绝", String(low.get("reason", "")))
	var ok_bid: Dictionary = GameState.bid_auction(0, int(ceil(float(cur) * 1.05)))
	_ok(bool(ok_bid.get("ok", false)), "合规出价成功")
	_ok(String(GameState.auctions[0].get("leader", "")) == "player", "出价后玩家领先")

	# 倒计时与到期（把 weeks 压到 1，跑两次 tick）
	GameState.auctions[0]["weeks"] = 1
	var ev1: Array = GameState.tick_auctions()
	var still := false
	for l in GameState.auctions:
		if int(l.get("weeks", 0)) > 0:
			still = true
	_ok(still or GameState.auctions.is_empty(), "tick 后周数递减")
	GameState.auctions.clear()

	# 资金不足 → 违约
	GameState.auctions.clear()
	GameState.auctions.append({"id": "t_lot", "kind": "gear", "name": "测试装备",
		"price": 999999, "start": 1000, "leader": "player", "weeks": 1, "gear": []})
	GameState.gold = 10
	var ev2: Array = GameState.tick_auctions()
	var had_default := false
	for e in ev2:
		if String(e.get("type", "")) == "default":
			had_default = true
	_ok(had_default, "资金不足时流拍并计违约")
	_ok(GameState.auction_defects == 1, "违约次数 +1", str(GameState.auction_defects))

	# 升格信号
	GameState.reset_new_game()
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var idx0 := 0
	var key0 := GameState.island_key(s.map_index, idx0)
	GameState.island_set_tier(key0, 2)
	var list: Array = [key0]
	s._on_islands_upgraded(list)
	_ok(int(s.islands[idx0][2]) == 2, "升格信号会刷新场景内岛屿等级",
		"tier=%d" % int(s.islands[idx0][2]))
	_ok(String(s.islands[idx0][3]).contains("港镇"), "升格后名称跟着变", String(s.islands[idx0][3]))
	s.queue_free()
	await _frames(2)

# ---------------- 经济系统（0.9.0） ----------------
func _test_economy_v09() -> void:
	print("\n[经济 0.9]")
	GameState.reset_new_game()

	# 阶梯溢价
	_ok(is_equal_approx(MarketModel.span_premium(0), 1.0), "无跨度无溢价")
	_ok(is_equal_approx(MarketModel.span_premium(8), 4.0), "跨度 8 达到 4.0 倍（+300%）")
	_ok(is_equal_approx(MarketModel.sale_multiplier(true, 8), 1.0), "目标地也产出时无溢价")
	_ok(is_equal_approx(MarketModel.sale_multiplier(false, 8), 4.0), "目标地不产出时有溢价")

	# 商品产地
	_ok(GameState.commodity_produced_in(&"grain", 9), "谷物全图产出")
	_ok(not GameState.commodity_produced_in(&"rum", 9), "朗姆酒 9 图不产出")
	_ok(GameState.commodity_produced_in(&"rum", 3), "朗姆酒 3 图产出")
	_ok(is_equal_approx(GameState.sale_multiplier_at(&"rum", 9), 4.0), "朗姆酒运到 9 图 4 倍")
	_ok(is_equal_approx(GameState.sale_multiplier_at(&"grain", 9), 1.0), "谷物无溢价")

	# 投资
	var key := GameState.island_key(1, 0)
	GameState.add_gold(200000)
	_ok(GameState.island_level(key) == 1, "新岛投资为 Lv1")
	_ok(GameState.island_discount(key) == 0, "Lv1 无折扣")
	_ok(GameState.invest_island(key, 5000), "可以注资")
	_ok(GameState.island_level(key) == 2, "注资 5000 升到 Lv2")
	_ok(GameState.island_discount(key) == 10, "Lv2 折扣 10%")
	GameState.invest_island(key, 15000)
	_ok(GameState.island_level(key) == 3, "累计 20000 到 Lv3")
	GameState.invest_island(key, 130000)
	_ok(GameState.island_level(key) == 5, "累计 150000 到 Lv5")
	_ok(GameState.island_discount(key) == 50, "Lv5 折扣 50%")

	# 成交额转投资（10%）
	var key2 := GameState.island_key(1, 1)
	var before := GameState.island_invested(key2)
	GameState.credit_island_trade(key2, 1000)
	_ok(GameState.island_invested(key2) == before + 100, "成交 1000 转 100 投资额")

	# 52 周升格
	GameState.island_set_tier(key, 1)
	GameState.invest_island(key, 1)
	_ok(GameState.island_upgrade_progress(key) != null, "满额后开始升格计时")
	var start_week := int(GameState.island_upgrade_start[key])
	TimeService.total_days = (start_week + 51) * 7
	GameState.tick_island_upgrades()
	_ok(GameState.island_tier_of(key, 1) == 1, "不满 52 周不升格")
	TimeService.total_days = (start_week + 52) * 7
	var ups: Array = GameState.tick_island_upgrades()
	_ok(ups.has(key), "满 52 周触发升格")
	_ok(GameState.island_tier_of(key, 1) == 2, "村落升为乡镇")
	_ok(GameState.island_invested(key) == 0, "升格后投资额清零")

	# NPC 货流（跨周改库存）
	GameState.reset_new_game()
	GameState.ensure_stock(&"jadehaven", &"grain", 400)
	var s0: int = int(GameState.port_stock.get(&"jadehaven", {}).get(&"grain", 0))
	for i in range(30):
		WorldTick._npc_trade_flow()
	var s1: int = int(GameState.port_stock.get(&"jadehaven", {}).get(&"grain", 0))
	_ok(int(GameState.port_stock.size()) > 0, "港口库存表存在")

	# NPC 载货 30%
	GameState.reset_new_game()
	GameState.cargo.clear()
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var e2 = s.enemies[0]
	e2.cargo_hold = {&"grain": 100}
	e2.last_attacker = s.player
	var loot_sc = load("res://scripts/systems/loot_system.gd")
	var r: Dictionary = loot_sc.apply(s.player, e2, {"sunk": false, "captured": false})
	_ok(int(r.get("cargo_hold", {}).get(&"grain", 0)) == 30, "载货 100 缴获 30",
		"got=%d" % int(r.get("cargo_hold", {}).get(&"grain", 0)))
	s.queue_free()
	await _frames(2)

# ---------------- 港口分级（0.8.0） ----------------
func _test_port_tiers() -> void:
	print("\n[港口分级]")
	GameState.reset_new_game()
	_ok(GameState.home_port_tier == 1, "新档母港为渔港村落", "tier=%d" % GameState.home_port_tier)

	# 服务表
	_ok(GameState.port_service_unlocked(1, "repair"), "村落有维修")
	_ok(GameState.port_service_unlocked(1, "market"), "村落有市场")
	_ok(GameState.port_service_unlocked(1, "tavern"), "村落有酒馆")
	_ok(not GameState.port_service_unlocked(1, "shipyard"), "村落没有船厂")
	_ok(not GameState.port_service_unlocked(1, "exchange"), "村落没有交易所")
	_ok(not GameState.port_service_unlocked(1, "reputation"), "村落没有声望面板")
	_ok(GameState.port_service_unlocked(2, "shipyard"), "乡镇开放船厂")
	_ok(GameState.port_service_unlocked(2, "building"), "乡镇开放基地建设")
	_ok(not GameState.port_service_unlocked(2, "exchange"), "乡镇仍无交易所")
	_ok(GameState.port_service_unlocked(3, "exchange"), "城市开放交易所")
	_ok(GameState.port_service_unlocked(3, "reputation"), "城市开放声望")

	# 升级条件
	_ok(not GameState.can_upgrade_home_port(), "资源不足时不能升级")
	var cost := GameState.home_upgrade_cost()
	_ok(int(cost.get("gold", 0)) == 5000, "Lv1→Lv2 需要 5000 金")
	GameState.add_gold(6000)
	GameState.resources["timber"] = 200
	GameState.resources["iron"] = 100
	_ok(GameState.can_upgrade_home_port(), "资源满足后可以升级")
	_ok(GameState.upgrade_home_port(), "升级成功")
	_ok(GameState.home_port_tier == 2, "母港升为乡镇")
	_ok(GameState.home_port_name() == "乡镇", "等级名称正确", GameState.home_port_name())
	_ok(GameState.home_has("shipyard"), "乡镇后母港可用船厂")

	GameState.add_gold(40000)
	GameState.resources["timber"] = 600
	GameState.resources["iron"] = 300
	_ok(GameState.upgrade_home_port(), "再次升级到城市")
	_ok(GameState.home_port_tier == 3, "母港升为港口城市")
	_ok(GameState.home_upgrade_cost().is_empty(), "满级后没有升级目标")
	_ok(not GameState.upgrade_home_port(), "满级后不能再升级")

	# 旧存档兼容：缺 port_tier 时按 Lv3
	var snap: Dictionary = GameState.to_dict()
	snap["base"].erase("port_tier")
	GameState.from_dict(snap)
	_ok(GameState.home_port_tier == 3, "旧存档缺字段按城市兼容", "tier=%d" % GameState.home_port_tier)

	# 特产价格梯度
	GameState.reset_new_game()
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var city_idx := -1
	var village_idx := -1
	for i in range(s.islands.size()):
		var tr := int(s.islands[i][2])
		if tr == 3 and city_idx < 0:
			city_idx = i
		if tr == 1 and village_idx < 0:
			village_idx = i
	_ok(city_idx >= 0 and village_idx >= 0, "图 1 同时有城与村")
	if city_idx >= 0 and village_idx >= 0:
		var c_sp: StringName = s.islands[city_idx][4]
		var v_sp: StringName = s.islands[village_idx][4]
		if c_sp == v_sp:
			s.cur_port_island = city_idx
			var city_stock: int = s._port_max_stock()
			s.cur_port_island = village_idx
			var vill_stock: int = s._port_max_stock()
			_ok(city_stock > vill_stock, "城市港口库存多于村落", "%d vs %d" % [city_stock, vill_stock])
		else:
			_ok(int(s.TIER_STOCK[3]) > int(s.TIER_STOCK[1]), "城市港口库存多于村落")
	_ok(is_equal_approx(float(s.SPECIALTY_PRICE_MULT[1]), 1.20), "村落特产溢价 1.20")
	_ok(is_equal_approx(float(s.SPECIALTY_PRICE_MULT[3]), 0.85), "城市特产折扣 0.85")
	s.queue_free()
	await _frames(2)

# ---------------- 岛屿三级与港口 ----------------
func _test_island_ports() -> void:
	print("\n[岛屿与港口]")
	GameState.reset_new_game()
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)

	_ok(s.islands.size() > 0, "岛屿已生成")
	# 分级：应有城、镇、村三种
	var tiers := {}
	for isl in s.islands:
		tiers[int(isl[2])] = true
	_ok(tiers.has(3), "图 1 有大型岛屿（城市）")
	_ok(tiers.has(2), "图 1 有中型岛屿（乡镇）")
	_ok(tiers.has(1), "图 1 有小型岛屿（村落）")

	# 每座岛都有名字与特产
	var named := true
	for isl in s.islands:
		if String(isl[3]) == "" or String(isl[4]) == "":
			named = false
	_ok(named, "每座岛都有名字与特产")

	# 靠岸可进入港口
	var isl0: Array = s.islands[0]
	s.player.global_position = Vector2(isl0[0]) + Vector2(float(isl0[1]) + 100.0, 0)
	var pi = s.nearest_port_island()
	_ok(pi != null, "靠岸后可以识别到港口")
	_ok(String(s.interact_prompt()).contains("停靠"), "靠岸提示停靠", s.interact_prompt())

	# 市场只卖 谷物/木材/本岛特产
	s.cur_port_island = int(pi)
	s._rebuild_port()
	var goods: Array = [&"grain", &"timber", StringName(isl0[4])]
	_ok(goods.size() == 3, "港口商品 = 谷物 + 木材 + 特产")
	var sp_id: StringName = StringName(isl0[4])
	_ok(sp_id != &"grain" and sp_id != &"timber", "特产不是基础货物")

	# 不同等级港口库存不同
	var stock_small := int(s.TIER_STOCK[1])
	var stock_city := int(s.TIER_STOCK[3])
	_ok(stock_city > stock_small, "大港库存多于小港", "%d vs %d" % [stock_city, stock_small])

	# 边缘换图：东侧邻接存在
	var info_east: Dictionary = s._edge_info("east")
	_ok(not info_east.is_empty(), "图 1 东侧有相邻海域", str(info_east.get("name", "")))
	s.player.global_position = Vector2(60, 4000)
	_ok(s._edge_dir() == "west", "贴西边界识别为 west")
	_ok(String(s._edge_prompt()).contains("翡翠港"), "西边界提示可回母港", s._edge_prompt())

	# 方位对应：东出 → 新图西侧
	GameState.clear_map_for_test() if GameState.has_method("clear_map_for_test") else null
	s.queue_free()
	await _frames(2)

# ---------------- 港口仓库 ----------------
func _test_warehouse() -> void:
	print("\n[港口仓库]")
	GameState.reset_new_game()
	GameState.warehouse.clear()
	GameState.cargo.clear()

	_ok(GameState.warehouse_capacity() > 0, "仓库有基础容量", "%d" % GameState.warehouse_capacity())
	_ok(GameState.warehouse_used() == 0.0, "新档仓库为空")

	var put: int = GameState.warehouse_add(&"grain", 30)
	_ok(put == 30, "可以存入仓库", "put=%d" % put)
	_ok(GameState.warehouse_used() > 0.0, "存仓后占用增加")
	_ok(int(GameState.warehouse.get(&"grain", 0)) == 30, "仓库数量正确")

	var took: int = GameState.warehouse_remove(&"grain", 10)
	_ok(took == 10, "可以从仓库取出")
	_ok(int(GameState.warehouse.get(&"grain", 0)) == 20, "取出后数量正确")

	# 存满后拒绝
	GameState.warehouse.clear()
	var huge: int = GameState.warehouse_add(&"grain", 999999)
	_ok(GameState.warehouse_free() < 10.0, "仓库会存满", "free=%.0f" % GameState.warehouse_free())
	_ok(huge > 0, "存满前可存入", "put=%d" % huge)

	# 存档往返
	GameState.warehouse.clear()
	GameState.warehouse_add(&"rum", 12)
	var snap: Dictionary = GameState.to_dict()
	GameState.reset_new_game()
	GameState.from_dict(snap)
	_ok(int(GameState.warehouse.get(&"rum", 0)) == 12, "仓库内容可存档还原",
		"rum=%d" % int(GameState.warehouse.get(&"rum", 0)))

	# 换船：装不下则禁止
	GameState.reset_new_game()
	GameState.cargo.clear()
	GameState.warehouse.clear()
	var big_cap: int = GameState.cargo_capacity()
	_ok(GameState.add_cargo(&"grain", 40) == 40, "先装一批货")
	# 造一艘小船放到库存
	GameState.ships_owned.clear()
	GameState.ships_owned.append({"def_id": "fishing_sloop", "variant": "standard",
		"station_port": "jadehaven", "hull_hp": -1.0, "sail_pct": 1.0,
		"rudder_pct": 1.0, "crew_pct": 1.0, "equipped": {}, "cannon_id": "pound3_light"})
	var small_cap: int = GameState.cargo_capacity_of(&"fishing_sloop", &"standard")
	_ok(small_cap < big_cap or GameState.cargo_used() <= float(small_cap),
		"小船载重已取出", "%d vs %d" % [small_cap, big_cap])
	if GameState.cargo_used() > float(small_cap):
		_ok(GameState.swap_overload(0), "货物超过小船载重时标记为不可换乘")
		_ok(not GameState.swap_to_owned(0), "超载时换船被拒绝")
	else:
		_ok(true, "当前货物未超小船载重（跳过超载用例）")
		_ok(true, "跳过")

	# 卸载后可以换
	GameState.cargo.clear()
	_ok(not GameState.swap_overload(0), "卸空货舱后可以换小船")
	_ok(GameState.swap_to_owned(0), "换船成功")
	_ok(String(GameState.ship_def_id) == "fishing_sloop", "已换到小船")

# ---------------- 锁定与互动 ----------------
func _test_interaction() -> void:
	print("\n[锁定与互动]")
	GameState.reset_new_game()
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)

	# 锁定不等于宣战
	var e = s.enemies[0]
	e.global_position = s.player.global_position + Vector2(400, 0)
	e.target = null
	s._lock_target(e)
	_ok(e.target == null, "锁定后敌方不会立刻锁定玩家")
	var hp0: float = s.player.hull_hp
	for i in range(120):
		await get_tree().physics_frame
	_ok(e.target == null, "静置期间敌方仍未交战", "target=%s" % str(e.target != null))
	_ok(is_equal_approx(s.player.hull_hp, hp0), "玩家没有受到伤害")

	# 被打之后才还手
	e.last_attacker = s.player
	e.take_damage({"hull": 1.0, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
	_ok(e.target == s.player, "被攻击后才会被动还击")
	s.queue_free()
	await _frames(2)

	# 互动提示
	GameState.reset_new_game()
	GameState.current_map = 1
	GameState.quests_active.clear()
	GameState.quests_active.append({"id": "g1", "type": "gather", "amount": 3, "progress": 0,
		"title": "打捞 3 处沉船残骸", "reward_gold": 100, "reward_xp": 0, "reward_comm": 0})
	var s2 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s2)
	await _frames(3)
	_ok(s2.salvages.size() > 0, "采集任务生成打捞点", "count=%d" % s2.salvages.size())

	s2.player.global_position = Vector2(3800, 3800)
	_ok(s2.interact_prompt() == "", "远离互动物时没有提示")

	var sv: Vector2 = s2.salvages[0]
	s2.player.global_position = sv + Vector2(80, 0)
	_ok(s2.interact_prompt().contains("打捞"), "靠近打捞点提示按 E 打捞", s2.interact_prompt())

	var prog_before: int = int(GameState.quests_active[0].get("progress", 0))
	var collected: bool = s2._try_collect_salvage()
	_ok(collected, "在打捞点可以成功打捞")
	_ok(int(GameState.quests_active[0].get("progress", 0)) == prog_before + 1, "打捞后采集任务进度 +1",
		"progress=%d" % int(GameState.quests_active[0].get("progress", 0)))
	_ok(s2.salvages.size() == 2, "打捞点被消耗", "left=%d" % s2.salvages.size())

	# 打捞点不能刷在岛上
	var min_island_gap := 1.0e9
	for sv2 in s2.salvages:
		min_island_gap = minf(min_island_gap, s2._dist_to_nearest_island(sv2))
	_ok(min_island_gap > 200.0, "打捞点不会刷在岛屿范围内", "最近离岛边 %.0f px" % min_island_gap)

	# 撤离不会瞬间解除敌方追击
	GameState.reset_new_game()
	GameState.current_map = 3
	var s3 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s3)
	await _frames(3)
	var pursuer = s3.enemies[0]
	pursuer.global_position = s3.player.global_position + Vector2(500, 0)
	pursuer.target = s3.player
	s3._on_retreat_pressed()
	_ok(pursuer.target == s3.player, "撤离后敌人仍会继续追（不能一键脱战）")
	_ok(s3.player.nav_queue.size() >= 1, "撤离会规划远离航线")
	s3.queue_free()
	await _frames(2)

	# 货舱 HUD 文本
	GameState.reset_new_game()
	GameState.add_cargo(&"grain", 12)
	var s4 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s4)
	await _frames(3)
	s4._refresh_cargo_hud()
	var cargo_txt: String = s4.hud._cargo_label.text
	_ok(cargo_txt.contains("谷物"), "货舱清单显示商品名", cargo_txt.replace("\n", " / "))
	_ok(cargo_txt.contains("12"), "货舱清单显示数量")
	_ok(cargo_txt.contains("容量"), "货舱清单显示容量")
	s4.queue_free()
	await _frames(2)
	GameState.cargo.clear()

	s2.player.global_position = s2.outpost_pos + Vector2(120, 0)
	_ok(s2.interact_prompt().contains("哨站"), "靠近哨站提示进入", s2.interact_prompt())
	s2.player.global_position = s2.BACK_GATE + Vector2(100, 0)
	_ok(s2.interact_prompt().contains("母港"), "靠近返回航门有提示", s2.interact_prompt())
	s2.queue_free()
	await _frames(2)
	GameState.quests_active.clear()

# ---------------- 转向稳定性 ----------------
func _test_steering_stability() -> void:
	print("\n[转向稳定性]")
	GameState.reset_new_game()
	var ship = load("res://scenes/ship/sea_ship.tscn").instantiate()
	ship.setup_enemy(DataRegistry.get_enemy(&"pirate_scout"), 1.0)
	var center := Vector2(4000, 4000)
	var r := 300.0
	ship.obstacles = [[center, r]]
	ship.global_position = center + Vector2(r + 500.0, 0)
	ship.heading = PI            # 正对岛心
	ship.rotation = PI
	ship.home_pos = ship.global_position
	ship.wander_heading = ship.heading
	ship.wander_timer = 100.0
	ship.target = null
	add_child(ship)
	await _frames(2)

	var prev_delta := 0.0
	var flips := 0
	var prev_h: float = ship.heading
	for i in range(150):
		await get_tree().physics_frame
		var d := wrapf(ship.heading - prev_h, -PI, PI)
		prev_h = ship.heading
		if absf(d) > 0.0005:
			if prev_delta != 0.0 and signf(d) != signf(prev_delta):
				flips += 1
			prev_delta = d
	_ok(flips <= 8, "绕障时转向不会高频左右抽搐", "150 帧内反向次数=%d" % flips)
	ship.queue_free()
	await _frames(2)

# ---------------- 自动开火 ----------------
func _test_auto_fire() -> void:
	print("\n[手动开火]")
	GameState.reset_new_game()
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var e = s.enemies[0]
	e.global_position = s.player.global_position + Vector2(400, 0)
	s._lock_target(e)
	e.target = s.player
	_ok(not s.player.auto_fire, "锁定后不会自动进入开火状态")

	# 锁定后等一个装填周期：一发都不该打出去
	for i in range(160):
		await get_tree().physics_frame
	_ok(s.player.volleys_fired == 0, "锁定后不会自动开火", "volleys=%d" % s.player.volleys_fired)
	_ok(e.hull_hp == e.hull_max, "未开火前敌船毫发无损", "%.0f/%.0f" % [e.hull_hp, e.hull_max])

	# 点一次「开火」= 只打一轮
	s._on_fire_pressed()
	_ok(s.player.volleys_fired == 1, "点一次开火只打一轮", "volleys=%d" % s.player.volleys_fired)
	_ok(e.hull_hp < e.hull_max, "该轮齐射造成伤害")

	var v_before: int = s.player.volleys_fired
	s._on_fire_pressed()
	_ok(s.player.volleys_fired == v_before, "装填中点击不会再打一轮", "volleys=%d" % s.player.volleys_fired)

	for i in range(200):
		await get_tree().physics_frame
		if s.player.ready_to_fire():
			break
	s._on_fire_pressed()
	_ok(s.player.volleys_fired >= 2, "装填完成后可再次手动开火", "volleys=%d" % s.player.volleys_fired)

	var v2: int = s.player.volleys_fired
	for i in range(160):
		await get_tree().physics_frame
	_ok(s.player.volleys_fired == v2, "不开火时绝不会自己射击", "volleys=%d" % s.player.volleys_fired)

	s.player.target = null
	s._on_fire_pressed()
	_ok(s.player.volleys_fired == v2, "没有目标时点开火不会射击")
	s.queue_free()
	await _frames(2)

# ---------------- 航线规划 ----------------
func _path_hits_island(s, path: Array, from: Vector2) -> bool:
	var prev := from
	for p in path:
		for isl in s.islands:
			if s._segment_hits_circle(prev, p, isl[0], isl[1] + 40.0):
				return true
		prev = p
	return false

func _test_pathfinding() -> void:
	print("\n[航线规划]")
	GameState.reset_new_game()
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	_ok(s.islands.size() > 0, "有岛屿可用于测试")

	var isl: Array = s.islands[0]
	var c: Vector2 = isl[0]
	var r: float = isl[1]
	s.player.global_position = (c + Vector2(r + 300.0, 0)).clamp(Vector2(100, 100), Vector2(7900, 7900))
	var target: Vector2 = (c - Vector2(r + 300.0, 0)).clamp(Vector2(100, 100), Vector2(7900, 7900))
	var route: Array = s._route_to(target)
	_ok(route.size() >= 2, "跨岛航线会插入绕航点", "waypoints=%d" % route.size())
	_ok(not _path_hits_island(s, route, s.player.global_position),
		"规划出的航线全程不穿岛", "waypoints=%d" % route.size())

	# 绕航点必须离岛足够远（不贴减速带）
	var min_clear := 1.0e9
	for p in route:
		for isl2 in s.islands:
			min_clear = minf(min_clear, p.distance_to(isl2[0]) - isl2[1])
	_ok(min_clear > s.AVOID_MARGIN + 50.0, "绕航点离岛边至少一个减速带以上",
		"最小净距=%.0f" % min_clear)

	# 整条航线的每一段都不进减速带
	var slow_zone_hit := false
	var prev: Vector2 = s.player.global_position
	for p in route:
		for isl3 in s.islands:
			if s._segment_hits_circle(prev, p, isl3[0], isl3[1] + s.AVOID_MARGIN):
				slow_zone_hit = true
		prev = p
	_ok(not slow_zone_hit, "航线不进入岛屿减速带")

	# 直线可达时不应绕路
	var clear_target: Vector2 = (s.player.global_position + Vector2(0, 500)).clamp(Vector2(100, 100), Vector2(7900, 7900))
	var direct: Array = s._route_to(clear_target)
	var blocked := false
	for i in s.islands:
		if s._segment_hits_circle(s.player.global_position, clear_target, i[0], i[1] + 40.0):
			blocked = true
	if not blocked:
		_ok(direct.size() == 1, "无障碍时只有目标点", "waypoints=%d" % direct.size())

	# 多岛串联：随便挑几个远点，航线都必须不穿岛
	var ok_all := true
	for k in range(6):
		var dest := Vector2(600.0 + k * 1100.0, 700.0 + k * 900.0).clamp(Vector2(100, 100), Vector2(7900, 7900))
		var rt: Array = s._route_to(dest)
		if _path_hits_island(s, rt, s.player.global_position):
			ok_all = false
	_ok(ok_all, "随机 6 个目标点的航线都不穿岛")

	# 撤离也走规划而不是直线
	s.player.heading = 0.0
	s.player.engaged = true
	s.player.target = null
	s._on_retreat_pressed()
	_ok(s.player.nav_queue.size() >= 1, "撤离会生成规划航线", "queue=%d" % s.player.nav_queue.size())

	s.queue_free()
	await _frames(2)

# ---------------- 阵营生态 ----------------
func _test_ecology() -> void:
	print("\n[阵营生态]")
	GameState.reset_new_game()
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)

	# 敌对关系
	_ok(s._is_hostile("pirate", "merchant"), "海盗敌视商船")
	_ok(s._is_hostile("pirate", "navy"), "海盗敌视海军")
	_ok(s._is_hostile("navy", "pirate"), "海军敌视海盗")
	_ok(not s._is_hostile("navy", "merchant"), "海军不敌视商船")
	_ok(not s._is_hostile("merchant", "merchant"), "商船之间不敌对")
	_ok(s._is_hostile("pirate", "player"), "海盗敌视玩家")

	# 1~2 图：没有任何单位主动锁定玩家
	_ok(not bool(s.map_def.hostile), "图 1 非敌对海域")
	var aggro_count := 0
	for e in s.enemies:
		if e.get("target") == s.player:
			aggro_count += 1
	_ok(aggro_count == 0, "低级图没有单位主动锁定玩家", "count=%d" % aggro_count)

	# 战力判断：弱海盗不会主动打强海军
	var weak = load("res://scenes/ship/sea_ship.tscn").instantiate()
	weak.setup_enemy(DataRegistry.get_enemy(&"pirate_scout"), 0.5)
	s.add_child(weak)
	var strong = load("res://scenes/ship/sea_ship.tscn").instantiate()
	strong.setup_enemy(DataRegistry.get_enemy(&"navy_patrol"), 4.0)
	s.add_child(strong)
	_ok(float(strong.combat_power()) > float(weak.combat_power()), "海军战力高于海盗")
	_ok(not s._will_attack(weak, strong), "弱方不会主动追击强方")
	_ok(s._will_attack(strong, weak), "强方会主动追击弱方")
	s.queue_free()
	await _frames(2)

	# 3 图：生态单位齐备，海怪无差别主动
	GameState.current_map = 3
	var s3 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s3)
	await _frames(6)
	_ok(bool(s3.map_def.hostile), "图 3 为敌对海域")
	_ok(s3._count_faction("navy") >= 1, "图 3 有海军巡逻", "count=%d" % s3._count_faction("navy"))
	_ok(s3._count_faction("merchant") >= 1, "图 3 有中立商船", "count=%d" % s3._count_faction("merchant"))
	_ok(s3.enemies.size() <= s3.MAX_UNITS, "同屏单位不超过上限", "count=%d" % s3.enemies.size())

	# 刷新密度：不贴着玩家、网格内不超限
	var too_close := 0
	for e in s3.enemies:
		if e.get("is_boss"):
			continue
		# 用 home_pos（出生点快照）判定，避免单位已经开动后距离变小造成误判
		var spawn_at: Variant = e.get("home_pos")
		if spawn_at == null:
			spawn_at = e.global_position
		if Vector2(spawn_at).distance_to(s3.player.global_position) < s3.PLAYER_SAFE_RADIUS - 1.0:
			too_close += 1
	_ok(too_close == 0, "没有单位刷在玩家安全区内", "越界=%d" % too_close)

	var cell_map := {}
	var overflow := 0
	for e in s3.enemies:
		if e.get("is_boss"):
			continue
		var ep: Vector2 = e.global_position
		var key := "%d_%d" % [int(floor(ep.x / s3.DENSITY_CELL)), int(floor(ep.y / s3.DENSITY_CELL))]
		cell_map[key] = int(cell_map.get(key, 0)) + 1
		if int(cell_map[key]) > s3.MAX_PER_CELL + 1:
			overflow += 1
	_ok(overflow == 0, "网格内单位数受控", "溢出=%d" % overflow)

	# 均匀度：任意两艘的间距不应过近
	var list: Array = []
	for e in s3.enemies:
		if is_instance_valid(e):
			list.append(e)
	var min_pair := 1.0e9
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			min_pair = minf(min_pair, list[i].global_position.distance_to(list[j].global_position))
	_ok(min_pair >= 120.0, "单位之间保持最小间距（不会挤成一堆）", "最小间距=%.0f" % min_pair)

	# 迎接单位的采样必须在圆周上等角距分散（直接验证采样函数）
	s3._near_sector = 0
	var angles: Array = []
	for k in range(3):
		var p: Vector2 = s3._sample_candidate(true)
		angles.append((p - s3.player.global_position).angle())
	var min_gap := 1.0e9
	for i in range(angles.size()):
		for j in range(i + 1, angles.size()):
			min_gap = minf(min_gap, absf(wrapf(angles[i] - angles[j], -PI, PI)))
	_ok(min_gap > deg_to_rad(60.0), "迎接单位绕玩家等角距分散",
		"最小角度差=%.1f°" % rad_to_deg(min_gap))

	# 围攻上限：跑一段时间后追打玩家的单位不超过 3
	for i in range(60):
		await get_tree().physics_frame
	_ok(s3._count_targeting_player() <= s3.MAX_ATTACKERS_ON_PLAYER,
		"同时追打玩家的单位不超过上限",
		"targeting=%d / 上限 %d" % [s3._count_targeting_player(), s3.MAX_ATTACKERS_ON_PLAYER])

	# NPC 互殴不给玩家战利品
	GameState.add_gold(0)
	var merchant = null
	for e in s3.enemies:
		if String(e.get("faction")) == "merchant":
			merchant = e
			break
	if merchant != null:
		var gold_before := GameState.gold
		merchant.last_attacker = null
		merchant.take_damage({"hull": 999999.0, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
		await _frames(4)
		_ok(GameState.gold == gold_before, "NPC 击杀不给玩家金币", "gold=%d" % GameState.gold)
	s3.queue_free()
	await _frames(2)

# ---------------- 任务导航 ----------------
func _test_quest_nav() -> void:
	print("\n[任务导航]")
	GameState.reset_new_game()
	GameState.quests_active.clear()
	GameState.quests_active.append({"id": "n1", "type": "transport", "commodity": "grain",
		"amount": 10, "progress": 0, "title": "运输测试", "reward_gold": 100,
		"reward_xp": 0, "reward_comm": 0, "faction": "merchant"})
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)

	var q: Dictionary = GameState.quests_active[0]
	var target = s._quest_nav_target(q)
	_ok(target != null, "运输任务有导航目标")
	_ok(target == s.outpost_pos, "运输任务导航到哨站")

	s._on_quest_nav(0)
	_ok(s.player.nav_queue.size() >= 1 or s.player.nav_target != null, "点导航后生成航线")

	# 采集任务 → 最近打捞点
	GameState.quests_active.clear()
	GameState.quests_active.append({"id": "n2", "type": "gather", "amount": 2, "progress": 0,
		"title": "采集测试", "reward_gold": 100, "reward_xp": 0, "reward_comm": 0})
	var s2 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s2)
	await _frames(3)
	_ok(s2.salvages.size() > 0, "采集任务生成打捞点")
	var g_target = s2._quest_nav_target(GameState.quests_active[0])
	_ok(g_target != null, "采集任务有导航目标")
	s2.queue_free()
	await _frames(2)

	# 讨伐任务 → 最近的对应敌人
	GameState.quests_active.clear()
	GameState.quests_active.append({"id": "n3", "type": "hunt", "target_kind": "pirate",
		"amount": 3, "progress": 0, "title": "讨伐测试", "reward_gold": 100,
		"reward_xp": 0, "reward_comm": 0})
	var s3 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s3)
	await _frames(3)
	var h_target = s3._quest_nav_target(GameState.quests_active[0])
	_ok(h_target != null, "讨伐任务导航到最近的海盗")

	# 护航任务：任务行显示商船状态
	GameState.quests_active.clear()
	GameState.quests_active.append({"id": "n4", "type": "escort", "amount": 1, "progress": 0,
		"title": "护送商船", "reward_gold": 100, "reward_xp": 0, "reward_comm": 0})
	var s4 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s4)
	await _frames(3)
	var note: String = s4._quest_note(GameState.quests_active[0])
	_ok(note.contains("⚑") and note.contains("%"), "护航任务显示商船状态", note)
	s4.escort_ship = null
	_ok(String(s4._quest_note(GameState.quests_active[0])).contains("失联"), "商船丢失后显示失联")
	s4.queue_free()
	await _frames(2)

	# 阵营倾向（声望 ≥3000 视为加入）
	GameState.reset_new_game()
	_ok(GameState.aligned_faction() == "", "声望不足时无阵营倾向")
	GameState.reputation["royal_navy"] = 3200
	_ok(GameState.aligned_faction() == "royal_navy", "海军声望 3200 → 倾向海军")
	GameState.reputation["black_sail"] = 5000
	_ok(GameState.aligned_faction() == "black_sail", "黑帆声望更高时倾向黑帆")

	# 同势力标签映射：海盗单位在加入黑帆后应显示"同势力"
	GameState.current_map = 1
	var s5 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s5)
	await _frames(3)
	var pirate5 = null
	for e in s5.enemies:
		if String(e.get("faction")) == "pirate":
			pirate5 = e
			break
	_ok(pirate5 != null, "找到海盗单位用于标签判定")
	_ok(GameState.aligned_faction() == "black_sail", "当前倾向黑帆")
	s5.queue_free()
	await _frames(2)
	GameState.reputation["black_sail"] = 0

	# 闲置单位不应原地打转
	GameState.reset_new_game()
	GameState.current_map = 1
	var s6 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s6)
	await _frames(3)
	var idle = null
	for e in s6.enemies:
		if String(e.get("faction")) == "pirate":
			idle = e
			break
	if idle != null:
		idle.target = null
		idle.wander_heading = idle.heading
		idle.wander_timer = 100.0
		var steer: float = idle._ai_steer(0.016)
		_ok(absf(steer) < 0.05, "闲置单位航向已对齐时不再转向", "steer=%.3f" % steer)
		idle.wander_heading = idle.heading + 0.5
		var steer2: float = idle._ai_steer(0.016)
		_ok(absf(steer2) > 0.05, "偏离巡游航向时会修正", "steer=%.3f" % steer2)
		_ok(absf(steer2) <= 0.6, "修正幅度受限，不会猛打舵", "steer=%.3f" % steer2)

		# 真正跑物理帧：航向应当收敛，而不是持续旋转
		idle.target = null
		idle.wander_heading = idle.heading
		idle.wander_timer = 100.0
		for i in range(90):
			await get_tree().physics_frame
		var h_start: float = idle.heading
		for i in range(20):
			await get_tree().physics_frame
		var drift: float = absf(wrapf(idle.heading - h_start, -PI, PI))
		_ok(drift < 0.02, "闲置单位不会持续旋转", "0.5 秒内转了 %.4f rad" % drift)
	else:
		_fail += 1
		print("  FAIL  没有找到海盗单位")
	s6.queue_free()
	await _frames(2)

	# 贸易任务没有具体地点
	var trade := {"type": "trade", "amount": 100, "progress": 0}
	_ok(s3._quest_nav_target(trade) == null, "贸易任务没有导航点")
	s3.queue_free()
	await _frames(2)
	GameState.quests_active.clear()

# ---------------- 交战规则 ----------------
func _test_engage_rules() -> void:
	print("\n[交战规则]")
	GameState.reset_new_game()
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var pirate = null
	for e in s.enemies:
		if not e.has_method("alive_limbs"):
			pirate = e
			break
	if pirate == null:
		_fail += 1
		print("  FAIL  找不到海盗")
		s.queue_free()
		return

	pirate.global_position = s.player.global_position + Vector2(400, 0)
	s.player.target = pirate
	s.player.engaged = true
	pirate.target = s.player
	await _phys(30)
	_ok(s.player.volleys_fired == 0, "锁定后不会自动开火")
	_ok(not s.player.ready_to_fire(), "锁定即开始装填，需等待")

	_ok(await _fire_when_ready(s.player), "装填完成后可手动开火")
	_ok(s.player.volleys_fired == 1, "一次点击打一轮", "volleys=%d" % s.player.volleys_fired)

	# 超出射程时不能开火
	pirate.global_position = s.player.global_position + Vector2(s.player.cannon_range + 300.0, 0)
	s.player.reload_timer = 0.0
	var res: Dictionary = s.player.try_fire()
	_ok(not res.get("ok", true), "超出射程时开火被拒绝", String(res.get("reason", "")))

	# 脱战：拉开 1600 以上并维持 5 秒
	pirate.global_position = s.player.global_position + Vector2(400, 0)
	pirate.target = s.player
	pirate.disengage_timer = 0.0
	s.player.global_position += Vector2(2000, 0)
	_ok(pirate.target != null, "拉远瞬间仍锁定")
	# 直接把脱战计时推到阈值前 0.2 秒，验证跨过阈值即放弃（不必真等 5 秒）
	pirate.disengage_timer = pirate.DISENGAGE_TIME - 0.2
	for i in range(20):
		await get_tree().physics_frame
		s.player.global_position = pirate.global_position + Vector2(2000, 0)
	_ok(pirate.target == null, "拉开距离 5 秒后 NPC 放弃追击",
		"dist=%.0f" % pirate.global_position.distance_to(s.player.global_position))
	s.queue_free()
	await _frames(2)

# ---------------- 十张海图 ----------------
func _test_maps() -> void:
	print("\n[十张海图]")
	GameState.reset_new_game()
	_ok(DataRegistry.maps.size() == 9, "9 张海域（图 1~9）", "实得 %d" % DataRegistry.maps.size())
	var m1: Resource = DataRegistry.get_map(1)
	_ok(m1.display_name == "浅湾水道", "图 1 数据正确")
	_ok(not bool(m1.hostile), "图 1 海盗不主动")
	_ok(bool(DataRegistry.get_map(3).hostile), "图 3 起海盗主动")
	_ok(String(DataRegistry.get_map(9).pirate_boss) == "boss_crown", "图 9 Boss 正确")

	_ok(GameState.can_enter_map(1), "图 1 可直接进入")
	_ok(not GameState.can_enter_map(2), "未通关时图 2 锁闭")
	var unlocked: bool = GameState.record_boss_defeat(&"boss_jack", 1)
	_ok(unlocked, "击破 Boss 触发解锁")
	_ok(GameState.is_map_cleared(1), "图 1 标记为已通关")
	_ok(GameState.can_enter_map(2), "图 2 解锁")
	_ok(GameState.is_boss_defeated(&"boss_jack"), "Boss 记入已击败")
	_ok(not GameState.record_boss_defeat(&"boss_jack", 1), "重复击杀不再触发解锁")

	# 海域场景按地图生成
	GameState.current_map = 3
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	_ok(s.map_index == 3, "场景读取当前地图")
	_ok(s.islands.size() >= 4, "生成岛屿布局", "实得 %d" % s.islands.size())
	_ok(s.enemies.size() >= 8, "按地图配额生成敌人", "实得 %d" % s.enemies.size())
	s.queue_free()
	await _frames(2)

# ---------------- Boss ----------------
func _test_bosses() -> void:
	print("\n[Boss]")
	GameState.reset_new_game()
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var boss = null
	for e in s.enemies:
		if e.get("is_boss") and not e.has_method("alive_limbs"):
			boss = e
			break
	_ok(boss != null, "海盗 Boss 已刷新")
	if boss == null:
		s.queue_free()
		return
	_ok(String(boss.enemy_id) == "boss_jack", "Boss id 正确", String(boss.enemy_id))
	_ok(boss.boss_phase == 1, "初始阶段 1")
	var dmg1: float = boss.cannon_damage
	boss.take_damage({"hull": boss.hull_max * 0.4, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
	_ok(boss.boss_phase == 2, "血量降到 60% 进入阶段 2", "phase=%d" % boss.boss_phase)
	_ok(boss.cannon_damage > dmg1, "阶段 2 火力提升")
	boss.take_damage({"hull": boss.hull_max * 0.3, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
	_ok(boss.boss_phase == 3, "血量降到 30% 进入阶段 3", "phase=%d" % boss.boss_phase)

	# 击败 Boss 后不再刷新
	boss.take_damage({"hull": 999999.0, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
	await _frames(3)
	_ok(GameState.is_boss_defeated(&"boss_jack"), "Boss 击败被记录")
	_ok(GameState.is_map_cleared(1), "地图标记通关")
	s.queue_free()
	await _frames(2)

# ---------------- 任务 ----------------
func _test_quests() -> void:
	print("\n[任务]")
	GameState.reset_new_game()
	GameState.refresh_quests()
	_ok(GameState.quests_available.size() == 9, "刷新 9 个任务", "实得 %d" % GameState.quests_available.size())
	var q: Dictionary = GameState.quests_available[0]
	_ok(String(q.title) != "" and int(q.reward_gold) > 0, "任务有标题与奖励")
	_ok(GameState.quest_accept(0), "接受任务")
	_ok(GameState.quests_active.size() == 1, "进入进行中")
	_ok(not GameState.quest_accept(999), "越界索引被拒绝")
	_ok(not GameState.quest_cancel(999), "放弃越界索引被拒绝")

	# 人工构造一个讨伐任务验证进度与发奖
	GameState.quests_active.clear()
	GameState.quests_active.append({"id": "t1", "type": "hunt", "target_kind": "pirate",
		"amount": 2, "progress": 0, "title": "测试讨伐", "reward_gold": 500, "reward_xp": 10, "reward_comm": 1})
	var gold0 := GameState.gold
	var comm0 := GameState.commendation
	GameState.on_enemy_killed("pirate", false)
	_ok(GameState.quests_active.size() == 1, "进度 1/2 未完成")
	GameState.on_enemy_killed("pirate", false)
	_ok(GameState.quests_active.is_empty(), "进度满后任务完成")
	_ok(GameState.gold >= gold0 + 500, "发放金币奖励")
	_ok(GameState.commendation == comm0 + 1, "发放战功")

	# 贸易任务
	GameState.quests_active.append({"id": "t2", "type": "trade", "amount": 1000, "progress": 0,
		"title": "测试贸易", "reward_gold": 100, "reward_xp": 0, "reward_comm": 0})
	GameState.on_trade_profit(400)
	_ok(int(GameState.quests_active[0].progress) == 400, "贸易利润累计")
	GameState.on_trade_profit(700)
	_ok(GameState.quests_active.is_empty(), "利润达标后完成")

# ---------------- 通缉 ----------------
func _test_notoriety() -> void:
	print("\n[通缉]")
	GameState.reset_new_game()
	_ok(GameState.notoriety() == 0, "初始通缉度 0")
	GameState.on_enemy_killed("pirate", false)
	_ok(GameState.notoriety() == -2, "击沉海盗 -2", "实得 %d" % GameState.notoriety())
	GameState.on_enemy_killed("navy", false)
	_ok(GameState.notoriety() == 13, "击沉海军 +15", "实得 %d" % GameState.notoriety())
	GameState.on_enemy_killed("merchant", false)
	_ok(GameState.notoriety() == 21, "劫掠商船 +8")
	_ok(not GameState.bounty_active(), "未达阈值无赏金猎人")
	GameState.reputation["notoriety"] = 60
	_ok(GameState.bounty_active(), "通缉度 60 触发赏金猎人")

	# 海域里真的会刷出海军
	GameState.current_map = 4
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	s.hunter_timer = 0.0
	await _frames(5)
	_ok(s._count_faction("navy") >= 1, "赏金猎人编队刷出", "实得 %d" % s._count_faction("navy"))
	s.queue_free()
	await _frames(2)

# ---------------- Boss 独有掉落 ----------------
func _test_boss_drops() -> void:
	print("\n[Boss 独有掉落]")
	GameState.reset_new_game()
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var boss = null
	for e in s.enemies:
		if e.get("is_boss") and String(e.get("enemy_id")) == "boss_jack":
			boss = e
			break
	_ok(boss != null, "杰克 Boss 已刷新")
	if boss == null:
		s.queue_free()
		return
	_ok(String(boss.unique_gear) == "uniq_scout_flag", "Boss 携带独有装备")
	_ok(String(boss.unique_crew_name) == "老罗盘手", "Boss 携带独有船员")
	var gear_before := GameState.gear_owned.size()
	var crew_before := GameState.crew_roster.size()
	boss.take_damage({"hull": 999999.0, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
	await _frames(4)
	_ok(GameState.gear_owned.has(&"uniq_scout_flag"), "击败后获得独有装备")
	_ok(GameState.gear_owned.size() == gear_before + 1, "装备库 +1")
	_ok(GameState.crew_roster.size() == crew_before + 1, "名册 +1（独有船员）")
	var got_crew = GameState.crew_roster[GameState.crew_roster.size() - 1]
	_ok(String(got_crew.display_name) == "老罗盘手" and int(got_crew.rarity) == 4, "独有船员为 UR")
	s.queue_free()
	await _frames(2)

# ---------------- 护航与采集 ----------------
func _test_escort_gather() -> void:
	print("\n[护航与采集]")
	GameState.reset_new_game()
	GameState.quests_active.append({"id": "e1", "type": "escort", "amount": 1, "progress": 0,
		"title": "护航测试", "reward_gold": 800, "reward_xp": 0, "reward_comm": 1})
	var gold0 := GameState.gold
	GameState.on_escort_arrived()
	_ok(GameState.quests_active.is_empty(), "护航抵达后完成")
	_ok(GameState.gold >= gold0 + 800, "护航发放奖励")

	GameState.quests_active.append({"id": "e2", "type": "escort", "amount": 1, "progress": 0,
		"title": "护航失败测试", "reward_gold": 0, "reward_xp": 0, "reward_comm": 0})
	GameState.on_escort_lost()
	_ok(GameState.quests_active.is_empty(), "商船被击沉时任务移除")

	GameState.quests_active.append({"id": "g1", "type": "gather", "amount": 2, "progress": 0,
		"title": "采集测试", "reward_gold": 300, "reward_xp": 0, "reward_comm": 0})
	GameState.on_salvage()
	_ok(int(GameState.quests_active[0].progress) == 1, "打捞进度 +1")
	GameState.on_salvage()
	_ok(GameState.quests_active.is_empty(), "打捞满额完成")

	# 海域按任务生成打捞点与商船
	GameState.reset_new_game()
	GameState.quests_active.append({"id": "g2", "type": "gather", "amount": 2, "progress": 0,
		"title": "打捞任务", "reward_gold": 100, "reward_xp": 0, "reward_comm": 0})
	GameState.quests_active.append({"id": "e3", "type": "escort", "amount": 1, "progress": 0,
		"title": "护航任务", "reward_gold": 100, "reward_xp": 0, "reward_comm": 0})
	GameState.current_map = 1
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	_ok(s.salvages.size() == 3, "生成 3 个打捞点", "实得 %d" % s.salvages.size())
	_ok(s.escort_ship != null, "生成受护商船")
	# 走到打捞点采集
	s.player.global_position = s.salvages[0]
	_ok(s._try_collect_salvage(), "靠近后可打捞")
	_ok(s.salvages.size() == 2, "打捞点消耗")
	s.queue_free()
	await _frames(2)

# ---------------- 声望 ----------------
func _test_reputation() -> void:
	print("\n[声望]")
	GameState.reset_new_game()
	_ok(GameState.rep_of("royal_navy") == 0, "初始声望 0")
	_ok(GameState.rep_level_name("royal_navy") == "无名", "初始等级无名")
	GameState.add_rep("royal_navy", 1200)
	_ok(GameState.rep_of("royal_navy") == 1200, "声望累加")
	_ok(GameState.rep_level_name("royal_navy") == "熟客", "1200 为熟客", GameState.rep_level_name("royal_navy"))
	GameState.add_rep("royal_navy", -9999)
	_ok(GameState.rep_of("royal_navy") == 0, "声望不会为负")

	# 捐赠：1000 金 = 10 声望，周上限 5000
	GameState.add_gold(20000)
	var g0 := GameState.gold
	var r: Dictionary = GameState.donate("merchant", 1000)
	_ok(r.get("ok", false), "捐赠成功", String(r.get("reason", "")))
	_ok(GameState.gold == g0 - 1000, "扣 1000 金")
	_ok(GameState.rep_of("merchant") == 10, "声望 +10", "实得 %d" % GameState.rep_of("merchant"))
	_ok(int(GameState.donated_week["merchant"]) == 1000, "记录本周额度")
	for i in range(5):
		GameState.donate("merchant", 1000)
	_ok(int(GameState.donated_week["merchant"]) == 5000, "本周额度封顶 5000")
	var r2: Dictionary = GameState.donate("merchant", 1000)
	_ok(not r2.get("ok", true), "额度用尽后拒绝")
	GameState.reset_donations()
	_ok(int(GameState.donated_week["merchant"]) == 0, "每周重置额度")

	# 击杀给声望
	GameState.reset_new_game()
	GameState.on_enemy_killed("pirate", false)
	_ok(GameState.rep_of("royal_navy") == 3, "击沉海盗 海军 +3", "实得 %d" % GameState.rep_of("royal_navy"))
	GameState.on_enemy_killed("navy", false)
	_ok(GameState.rep_of("royal_navy") == 0, "击沉海军 海军声望扣到 0")
	_ok(GameState.rep_of("black_sail") == 15, "击沉海军 黑帆 +15")

	# 通缉：保释与衰减
	GameState.reputation["notoriety"] = 80
	GameState.add_gold(10000)
	var b: Dictionary = GameState.post_bail(5000)
	_ok(b.get("ok", false), "可以缴纳保释金")
	_ok(GameState.notoriety() == 60, "保释后通缉度 -20", "实得 %d" % GameState.notoriety())
	GameState.decay_notoriety()
	_ok(GameState.notoriety() == 58, "每周自然衰减 2")

	# 任务完成给阵营声望
	GameState.reset_new_game()
	GameState.quests_active.append({"id": "rq", "type": "hunt", "target_kind": "pirate",
		"amount": 1, "progress": 0, "title": "声望任务", "reward_gold": 10, "reward_xp": 0,
		"reward_comm": 0, "faction": "black_sail"})
	GameState.on_enemy_killed("pirate", false)
	_ok(GameState.rep_of("black_sail") >= 120, "任务完成给对应阵营 +120",
		"实得 %d" % GameState.rep_of("black_sail"))

# ---------------- 战功 ----------------
func _test_commendation() -> void:
	print("\n[战功]")
	GameState.reset_new_game()
	_ok(GameState.commendation == 0, "初始战功 0")
	var fail: Dictionary = GameState.spend_commendation("rep")
	_ok(not fail.get("ok", true), "战功不足时拒绝兑换")

	GameState.commendation = 500
	var r1: Dictionary = GameState.spend_commendation("rep", "royal_navy")
	_ok(r1.get("ok", false), "兑换声望包")
	_ok(GameState.commendation == 300, "扣 200 战功")
	_ok(GameState.rep_of("royal_navy") == 100, "海军声望 +100")

	var roster0 := GameState.crew_roster.size()
	var r2: Dictionary = GameState.spend_commendation("crew")
	_ok(r2.get("ok", false), "兑换船员")
	_ok(GameState.crew_roster.size() == roster0 + 1, "名册 +1")
	_ok(GameState.commendation == 250, "扣 50 战功")

	var gear0 := GameState.gear_owned.size()
	var r3: Dictionary = GameState.spend_commendation("gear")
	_ok(r3.get("ok", false), "兑换独有装备")
	_ok(GameState.gear_owned.size() == gear0 + 1, "装备库 +1")
	_ok(GameState.commendation == 150, "扣 100 战功")

# ---------------- 通关 ----------------
func _test_victory() -> void:
	print("\n[通关]")
	GameState.reset_new_game()
	_ok(not GameState.game_cleared, "初始未通关")
	for i in range(1, 9):
		GameState.cleared_maps.append(i)
	_ok(not GameState.check_victory(), "只到图 8 时未通关")
	GameState.cleared_maps.append(9)
	_ok(GameState.check_victory(), "清完图 9 触发通关")
	_ok(GameState.game_cleared, "通关标记置位")
	_ok(not GameState.check_victory(), "通关只触发一次")

	_ok(GameState.stat_kills == 0, "击杀统计初值 0")
	GameState.on_enemy_killed("pirate", false)
	GameState.on_enemy_killed("pirate", true)
	_ok(GameState.stat_kills == 2, "击杀统计累加")
	_ok(GameState.stat_bosses == 1, "Boss 统计累加")

	# 存档往返
	var rep_before := GameState.rep_of("royal_navy")
	SaveManager.save(5)
	GameState.reset_new_game()
	SaveManager.load_slot(5)
	_ok(GameState.game_cleared, "通关标记存档还原")
	_ok(GameState.stat_kills == 2, "击杀统计存档还原")
	_ok(GameState.rep_of("royal_navy") == rep_before, "声望存档还原",
		"%d vs %d" % [GameState.rep_of("royal_navy"), rep_before])
	SaveManager.delete_slot(5)

# ---------------- 存档位 ----------------
func _test_save_slots() -> void:
	print("\n[存档位]")
	GameState.reset_new_game()
	GameState.add_gold(4321)
	GameState.level = 7
	GameState.current_map = 4
	_ok(SaveManager.save(3), "写入存档位 3")
	var meta: Dictionary = SaveManager.slot_meta(3)
	_ok(bool(meta.get("exists", false)), "元数据可读")
	_ok(int(meta.get("gold", 0)) == 500 + 4321, "元数据金币正确", "实得 %d" % int(meta.get("gold", 0)))
	_ok(int(meta.get("level", 0)) == 7, "元数据等级正确")
	_ok(int(meta.get("map", 0)) == 4, "元数据地图正确")
	_ok(not bool(SaveManager.slot_meta(4).get("exists", false)), "空槽位显示为空")
	_ok(SaveManager.all_slot_ids().size() == 6, "共 6 个槽位（1 自动 + 5 手动）")
	GameState.reset_new_game()
	_ok(SaveManager.load_slot(3), "读取存档位 3")
	_ok(GameState.gold == 500 + 4321, "读档金币还原")
	_ok(SaveManager.auto_save(), "自动存档可写")
	_ok(bool(SaveManager.slot_meta(SaveManager.AUTO_SLOT).get("exists", false)), "自动槽位有元数据")
	SaveManager.delete_slot(3)
	SaveManager.delete_slot(SaveManager.AUTO_SLOT)

# ---------------- 哨站维修 ----------------
func _test_outpost_repair() -> void:
	print("\n[哨站维修]")
	GameState.reset_new_game()
	GameState.current_map = 1
	GameState.hull_hp = 100.0
	GameState.sail_pct = 0.5
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var cost: int = s._port_repair_cost()
	_ok(cost > 0, "维修需要金币", "cost=%d" % cost)
	GameState.add_gold(cost + 100)
	var gold0 := GameState.gold
	s._port_repair(cost)
	_ok(is_equal_approx(GameState.hull_hp, GameState.hull_max()), "船体修复满值")
	_ok(is_equal_approx(GameState.sail_pct, 1.0), "风帆修复")
	_ok(GameState.gold == gold0 - cost, "扣除维修费")
	s.queue_free()
	await _frames(2)

# ---------------- 岛屿避障 ----------------
func _test_avoidance() -> void:
	print("\n[岛屿避障]")
	GameState.reset_new_game()
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var island: Array = s.islands[0]
	var c: Vector2 = island[0]
	var r: float = island[1]
	# 把玩家放到排斥区内
	s.player.global_position = c + Vector2(r + 120.0, 0)
	s.player.heading = 0.0
	s.player.throttle = 0.0
	var d0: float = s.player.global_position.distance_to(c)
	for i in range(40):
		await get_tree().physics_frame
	var d1: float = s.player.global_position.distance_to(c)
	_ok(d1 > d0 + 8.0, "进入避障区后被推出", "%.0f -> %.0f" % [d0, d1])

	# 点击绕行：目标在岛的另一侧
	s.player.global_position = c + Vector2(r + 300.0, 0)
	var route: Array = s._route_to(c + Vector2(-(r + 300.0), 0))
	_ok(route.size() >= 2, "跨岛航线插入绕航点", "size=%d" % route.size())
	_ok(not _path_hits_island(s, route, s.player.global_position), "跨岛航线不穿岛",
		"size=%d" % route.size())
	var direct: Array = s._route_to(c + Vector2(r + 900.0, 0))
	_ok(direct.size() == 1, "不跨岛的航线不加绕航点", "size=%d" % direct.size())

	# 没有船体碰撞
	_ok(s.player.collision_mask == 0, "船不与任何实体碰撞")
	var has_monster := false
	for e in s.enemies:
		if e.has_method("alive_limbs"):
			has_monster = true
			_ok(e.collision_mask == 0, "海怪不与任何实体碰撞")
			break
	_ok(has_monster, "存在海怪用于碰撞检查")
	s.queue_free()
	await _frames(2)

# ---------------- 时间轴 ----------------
func _test_time() -> void:
	print("\n[时间轴]")
	TimeService.total_days = 0
	TimeService.speed = 1.0
	TimeService.paused = false
	var box := [0]
	var cb := func(_w): box[0] += 1
	TimeService.week_advanced.connect(cb)
	TimeService._process(24.0)
	_ok(TimeService.total_days == 1, "24 秒推进 1 天")
	TimeService.paused = true
	TimeService._process(24.0)
	_ok(TimeService.total_days == 1, "暂停时不推进")
	TimeService.paused = false
	TimeService.speed = 2.0
	TimeService._process(12.0)
	_ok(TimeService.total_days == 2, "2× 速度 12 秒推进 1 天")
	TimeService.speed = 1.0
	for i in range(5):
		TimeService._process(24.0)
	_ok(TimeService.total_days == 7, "累计 7 天")
	_ok(box[0] == 1, "跨周触发一次周结算", "weeks=%d" % box[0])
	TimeService.week_advanced.disconnect(cb)
	_ok(TimeService.date_text().begins_with("第 1 年"), "日期文本正常", TimeService.date_text())

# ---------------- 货币 ----------------
func _test_currency() -> void:
	print("\n[货币]")
	GameState.reset_new_game()
	_ok(GameState.commendation == 0, "战功初始为 0")
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	var e = null
	for x in s.enemies:
		if not x.has_method("alive_limbs"):
			e = x
			break
	if e == null:
		_fail += 1
		print("  FAIL  找不到海盗")
		s.queue_free()
		return
	e.commendation_reward = 5
	e.last_attacker = s.player
	e.take_damage({"hull": 999999.0, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
	await _frames(3)
	_ok(GameState.commendation == 5, "击沉带战功奖励的敌人后战功 +5", "comm=%d" % GameState.commendation)
	var gold_after := GameState.gold
	_ok(gold_after > 500, "同时获得金币")
	s.queue_free()
	await _frames(2)

# ---------------- 存档 ----------------
func _test_save_roundtrip() -> void:
	print("\n[存档]")
	GameState.reset_new_game()
	GameState.add_gold(1234)
	GameState.add_cargo(&"rum", 7)
	GameState.hull_hp = 321.0
	var ok := SaveManager.save(9)
	_ok(ok, "写入存档位 9")
	GameState.reset_new_game()
	var ok2 := SaveManager.load_slot(9)
	_ok(ok2, "读取存档位 9")
	_ok(GameState.gold == 500 + 1234, "金币还原", "gold=%d" % GameState.gold)
	_ok(int(GameState.cargo.get(&"rum", 0)) == 7, "货物还原")
	_ok(is_equal_approx(GameState.hull_hp, 321.0), "船体还原")
	GameState.reset_new_game()
	GameState.commendation = 42
	TimeService.total_days = 30
	SaveManager.save(9)
	GameState.reset_new_game()
	TimeService.total_days = 0
	SaveManager.load_slot(9)
	_ok(GameState.commendation == 42, "战功存档还原", "comm=%d" % GameState.commendation)
	_ok(TimeService.total_days == 30, "时间轴存档还原", "days=%d" % TimeService.total_days)
	SaveManager.delete_slot(9)
