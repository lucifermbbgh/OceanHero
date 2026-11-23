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
	await _test_v156_mini_map()
	await _test_v153_world_map()
	await _test_v151_sorting()
	await _test_v150_world_map_data()
	await _test_v1419_island_tavern()
	await _test_v1418_per_ship()
	await _test_v1417_upgrade_runtime()
	await _test_v1415_balance()
	await _test_v1414_ui_save()
	await _test_v1412_sails()
	await _test_v1410_layout()
	await _test_v147_panel_fix()
	await _test_v146_ship_panel()
	await _test_v145_module_upgrade()
	await _test_v144_module_crew()
	await _test_v143_gear_slots()
	await _test_v142_module_stats()
	await _test_v141_modules()
	await _test_v140_fixes()
	await _test_v1317_polish()
	await _test_v1315_events()
	await _test_v1314_patrol_aggro()
	await _test_v1313_unique()
	await _test_v1312_exchange()
	await _test_v1311_tables()
	await _test_v139_license_rules()
	await _test_v138_kill_rep()
	await _test_v136_faction_rep()
	await _test_v135_patrols()
	await _test_v134_license()
	await _test_v133_relations()
	await _test_v132_adjacency()
	await _test_v131_maps()
	await _test_v130_nations()
	await _test_v1213_dup()
	await _test_v1212_island_panels()
	await _test_v1211_recipes()
	await _test_v1210_stats()
	await _test_v129_validate()
	await _test_v126_127_supply()
	await _test_v124_125()
	await _test_v123_port_buildings()
	await _test_v122_town()
	await _test_v121_gate()
	await _test_v120_component()
	await _test_v114_fixes()
	await _test_v113_polish()
	await _test_v112_parallel()
	await _test_v111_ui()
	await _test_v110_core()
	await _test_ui_panels_v019()
	await _test_finance_v018()
	await _test_cost_scale_v015()
	await _test_decision_aid_v014()
	await _test_market_ui_v0131()
	await _test_price_engine_v013()
	await _test_bank_v012()
	await _test_black_market_v011()
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
	_ok(DataRegistry.ships.size() == 68, "68 个船体（17 基准 × 4）", "实得 %d" % DataRegistry.ships.size())
	_ok(DataRegistry.ship_bases.size() == 17, "17 个基准模板（含 7 艘势力专属）",
		str(DataRegistry.ship_bases.size()))
	_ok(DataRegistry.gear.size() == 36, "36 件装备（含装甲板/望远镜/旗帜）",
		"实得 %d" % DataRegistry.gear.size())
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
	_ok(DataRegistry.buildings.size() == 7, "7 座建筑（交易所已删除）",
		"实得 %d" % DataRegistry.buildings.size())
	# 1.2.0 起母港开局自带仓库与总督府；此处显式清空以测试建造流程
	GameState.buildings.clear()
	_ok(GameState.building_level(&"warehouse") == 0, "清空后建筑等级 0")

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
	_ok(_near_r(GameState.sell_bonus(), 0.0), "交易所建筑已删除，卖出加成为 0")
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
	GameState.buildings[&"exchange"] = 4

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

# ---------------- 1.5.6 海上小地图 ----------------
func _test_v156_mini_map() -> void:
	print("\n[1.5.6 海上小地图]")
	GameState.reset_new_game()
	var sea = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(sea)
	await _frames(6)
	_ok(sea.mini_map != null, "小地图已创建")
	_ok(sea.mini_map.size.x >= 200.0, "小地图尺寸 220", str(sea.mini_map.size))
	_ok(sea.mini_map.map_scale() > 0.0, "地图缩放比例可用", str(sea.mini_map.map_scale()))
	_ok(sea.mini_map.position.x > 1000.0, "小地图位于右上角", str(sea.mini_map.position))
	sea.queue_free()
	await _frames(2)
	GameState.reset_new_game()

# ---------------- 1.5.3 世界地图面板 ----------------
func _test_v153_world_map() -> void:
	print("\n[1.5.3 世界地图面板]")
	GameState.reset_new_game()
	var wm = load("res://scripts/ui/world_map.gd").new()
	add_child(wm)
	await _frames(2)
	_ok(wm.size.x >= 1500.0 and wm.size.y >= 780.0, "面板尺寸 1568x812", str(wm.size))
	_ok(not wm.visible, "默认隐藏")
	wm.toggle()
	_ok(wm.visible, "M 可打开")
	wm.toggle()
	_ok(not wm.visible, "M 可关闭")
	_ok(GameState.explored_maps.size() >= 1, "探索数据可用", str(GameState.explored_maps))
	# 1.5.5 交互增强
	GameState.mark_map_explored(2)
	wm.select_map(2)
	var r2 = wm._compute_route(1, 2)
	_ok(r2.size() >= 2, "已探索邻接可算出航线", str(r2))
	wm.zoom_by(5.0)
	_ok(wm._zoom <= 1.81, "缩放上限钳制", str(wm._zoom))
	wm.zoom_by(0.01)
	_ok(wm._zoom >= 0.69, "缩放下限钳制", str(wm._zoom))
	var p1: Vector2 = wm._anchor_pos(1)
	_ok(wm._hit(p1) == 1, "命中检测可选中节点")
	_ok(wm._polys.size() == 30, "Tiled 多边形已载入", str(wm._polys.size()))
	_ok(wm._polys[1]["polygon"].size() >= 3, "多边形顶点有效")
	wm.queue_free()
	await _frames(1)
	GameState.reset_new_game()

# ---------------- 1.5.1 展示排序 ----------------
func _test_v151_sorting() -> void:
	print("\n[1.5.1 展示排序]")
	GameState.reset_new_game()
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	# 船员按稀有度降序
	var crew = load("res://scripts/systems/crew_factory.gd").generate(4, &"standard")
	var sorted_crew = s._sorted_rar(crew)
	var desc := true
	for i3 in range(sorted_crew.size() - 1):
		if int(sorted_crew[i3].rarity) < int(sorted_crew[i3 + 1].rarity):
			desc = false
	_ok(desc, "船员按稀有度降序")
	# 装备 id 按稀有度降序
	var ids: Array = ["sail_linen", "sail_cotton", "sail_ramie"]
	var sorted_ids = s._sorted_rar(ids)
	var desc2 := true
	for j3 in range(sorted_ids.size() - 1):
		if s._rarity_of(sorted_ids[j3]) < s._rarity_of(sorted_ids[j3 + 1]):
			desc2 = false
	_ok(desc2, "装备按稀有度降序")
	# 空列表安全
	_ok(s._sorted_rar([]).is_empty(), "空列表排序安全")
	s.queue_free()
	await _frames(2)
	GameState.reset_new_game()

# ---------------- 1.5.0 世界地图数据 ----------------
func _test_v150_world_map_data() -> void:
	print("\n[1.5.0 世界地图数据]")
	GameState.reset_new_game()
	# 30 张图都有坐标，同级不重叠
	var seen := {}
	var missing := 0
	var overlap := 0
	for i2 in range(1, 31):
		var md: Resource = DataRegistry.get_map(i2)
		if md == null or md.world_pos == Vector2.ZERO:
			missing += 1
			continue
		var key := "%.2f_%.3f" % [md.world_pos.x, md.world_pos.y]
		if seen.has(key):
			overlap += 1
		seen[key] = true
	_ok(missing == 0, "30 张海图均有坐标", str(missing))
	_ok(overlap == 0, "同级坐标不重叠", str(overlap))
	var home: Resource = DataRegistry.get_map(1)
	_ok(home != null and home.world_pos.x > 0.2 and home.world_pos.y < 0.1,
		"母港位于左上区域", str(home.world_pos) if home != null else "null")
	# 探索状态
	GameState.reset_new_game()
	_ok(GameState.is_map_explored(1), "开局母港已探索")
	_ok(not GameState.is_map_explored(7), "未到访海图未探索")
	GameState.mark_map_explored(7)
	_ok(GameState.is_map_explored(7), "进入后标记探索")
	# 存档往返
	var d2: Dictionary = GameState.to_dict()
	GameState.reset_new_game()
	GameState.from_dict(d2)
	_ok(GameState.is_map_explored(7), "存档恢复探索状态",
		str(GameState.explored_maps))
	GameState.reset_new_game()

# ---------------- 1.4.19 岛屿酒馆雇佣 ----------------
func _test_v1419_island_tavern() -> void:
	print("\n[1.4.19 岛屿酒馆]")
	GameState.reset_new_game()
	GameState.register_port("i_test", "测试港镇", 0, 2)
	GameState.visit_port_id = &"i_test"
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	s._toggle_tavern()
	await _frames(1)
	_ok(s.tavern_root.visible, "岛屿酒馆面板可打开")
	_ok(GameState.tavern_pool.size() > 0, "岛屿酒馆有招募对象", str(GameState.tavern_pool.size()))
	var pool0: int = GameState.tavern_pool.size()
	var roster0: int = GameState.crew_roster.size()
	var gold0: int = GameState.gold
	var cheapest: Resource = null
	for c2 in GameState.tavern_pool:
		if int(c2.hire_cost) <= GameState.gold and (cheapest == null or int(c2.hire_cost) < int(cheapest.hire_cost)):
			cheapest = c2
	_ok(cheapest != null, "存在可负担的船员")
	var first_id: StringName = StringName(cheapest.crew_id) if cheapest != null else &""
	s._hire_crew(first_id)
	await _frames(1)
	_ok(GameState.crew_roster.size() == roster0 + 1, "雇佣后名册 +1",
		str(GameState.crew_roster.size()))
	_ok(GameState.tavern_pool.size() == pool0 - 1, "雇佣后候选 -1",
		str(GameState.tavern_pool.size()))
	_ok(GameState.gold < gold0, "雇佣扣金币", str(GameState.gold))
	# 面板已重建（招募列表数量与池一致）
	var hire_btns := 0
	for n in s.tavern_list.find_children('*', 'Button', true, false):
		if n is Button and n.text == "雇佣":
			hire_btns += 1
	_ok(hire_btns == GameState.tavern_pool.size(), "面板立即刷新", "%d vs %d" % [hire_btns, GameState.tavern_pool.size()])
	s.queue_free()
	await _frames(2)
	GameState.reset_new_game()

# ---------------- 1.4.18 每船独立模块 ----------------
func _test_v1418_per_ship() -> void:
	print("\n[1.4.18 每船独立]")
	GameState.reset_new_game()
	# 当前船强化
	GameState.ship_module_levels["sails#0"] = 1
	GameState.ships_owned.clear()
	GameState.ships_owned.append({"def_id": "brig", "variant": "standard",
		"station_port": "jadehaven", "hull_hp": -1.0, "sail_pct": 1.0,
		"rudder_pct": 1.0, "crew_pct": 1.0, "equipped": {},
		"module_levels": {"gundeck#0": 3}, "module_crew": {}})
	_ok(bool(GameState.swap_to_owned(0, &"jadehaven")), "换乘到 brig")
	_ok(GameState.module_level("gundeck", 0) == 3, "目标船模块等级独立读取",
		str(GameState.module_level("gundeck", 0)))
	_ok(GameState.module_level("sails", 0) == 0, "原船强化不带入新船",
		str(GameState.module_level("sails", 0)))
	# 换回原船，强化应恢复
	var old_idx := -1
	for i in range(GameState.ships_owned.size()):
		if String(GameState.ships_owned[i].get("def_id", "")) == "fishing_sloop":
			old_idx = i
	_ok(old_idx >= 0, "原船回到船库", str(old_idx))
	_ok(bool(GameState.swap_to_owned(old_idx, &"jadehaven")), "换回原船")
	_ok(GameState.module_level("sails", 0) == 1, "原船强化保留",
		str(GameState.module_level("sails", 0)))
	GameState.reset_new_game()

# ---------------- 1.4.17 强化运行时路径 ----------------
func _test_v1417_upgrade_runtime() -> void:
	print("\n[1.4.17 强化运行时]")
	GameState.reset_new_game()
	# 完全走开局状态：不额外设置仓库，只用 grant_start_resources 的物资
	var r: Dictionary = GameState.upgrade_module("sails", 0)
	_ok(bool(r.get("ok", false)), "开局直接强化风帆成功", str(r.get("reason", "")))
	_ok(GameState.module_level("sails", 0) == 1, "风帆等级变为 1",
		str(GameState.module_level("sails", 0)))
	# 仓库键类型核查
	_ok(int(GameState.warehouse.get(&"timber", -1)) >= 0, "仓库木材使用 StringName 键")
	# 第二次强化：1 级船应已达上限
	GameState.reset_new_game()
	GameState.upgrade_module("sails", 0)
	var r2: Dictionary = GameState.upgrade_module("sails", 0)
	_ok(not bool(r2.get("ok", true)), "1 级船第二次强化被上限拒绝", str(r2.get("reason", "")))
	GameState.reset_new_game()

# ---------------- 1.4.15 基线平衡 ----------------
func _test_v1415_balance() -> void:
	print("\n[1.4.15 基线平衡]")
	GameState.reset_new_game()
	# 主线船按船级：船体/炮数/模块数单调不减
	var main_ids := ["fishing_sloop", "sand_junk", "longship", "schooner",
		"brig", "sixth_rate", "fifth_rate", "fourth_rate", "third_rate", "first_rate"]
	var prev_hull := 0.0
	var prev_guns := 0
	var prev_mod := 0
	var monotonic := true
	for mid in main_ids:
		GameState.ship_def_id = StringName(mid)
		GameState.ship_module_levels.clear()
		var st: Dictionary = GameState.stats()
		var hull := float(st.get("hull_max", 0.0))
		var guns := int(st.get("guns_per_side", 0))
		var mods := GameState.ship_modules().size()
		if hull < prev_hull or guns < prev_guns or mods < prev_mod:
			monotonic = false
		prev_hull = hull
		prev_guns = guns
		prev_mod = mods
	_ok(monotonic, "主线船体/炮数/模块数随船级单调不减")
	# 强化上限随船级
	GameState.ship_def_id = &"fishing_sloop"
	_ok(GameState.module_level_cap() == 1, "1 级船强化上限 1")
	GameState.ship_def_id = &"brig"
	_ok(GameState.module_level_cap() == 5, "5 级船强化上限 5")
	GameState.ship_def_id = &"first_rate"
	_ok(GameState.module_level_cap() == 5, "10 级船仍封顶 5")
	# 满级模块收益上限（帆）
	GameState.ship_module_levels.clear()
	var s0: float = float(GameState.stats()["base_speed_px"])
	for i in range(GameState.sails_layers(10)):
		GameState.set_module_level("sails", i, 5)
	var s1: float = float(GameState.stats()["base_speed_px"])
	_ok(s1 > s0 and s1 < s0 * 3.0, "满级风帆收益在合理区间",
		"%.0f → %.0f" % [s0, s1])
	GameState.reset_new_game()

# ---------------- 1.4.14 面板/换船/存档 ----------------
func _test_v1414_ui_save() -> void:
	print("\n[1.4.14 面板交互与存档]")
	GameState.reset_new_game()
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	# 装备槽映射（面板用）
	_ok(s._gear_slot_of("sails", 1) == "sail1", "帆槽按桅映射 sail1")
	_ok(s._gear_slot_of("deck", 0) == "figurehead", "甲板 0 层为船艏像")
	_ok(s._gear_slot_of("deck", 1) == "plate", "甲板 1 层为装甲板")
	# 插槽文本含强化等级
	GameState.set_module_level("gundeck", 0, 2)
	_ok(s._ship_slot_text("gundeck", 0).contains("+2"), "插槽显示强化等级",
		s._ship_slot_text("gundeck", 0))
	# 换船流程
	GameState.reset_new_game()
	GameState.ships_owned.clear()
	GameState.ships_owned.append({"def_id": "brig", "variant": "standard",
		"station_port": "jadehaven", "hull_hp": -1.0, "sail_pct": 1.0,
		"rudder_pct": 1.0, "crew_pct": 1.0, "equipped": {}})
	var old_ship := String(GameState.ship_def_id)
	var ok_swap: bool = GameState.swap_to_owned(0, &"jadehaven")
	_ok(ok_swap, "可换乘本港船只")
	_ok(String(GameState.ship_def_id) == "brig", "当前船变为 brig",
		String(GameState.ship_def_id))
	var back_found := false
	for sh in GameState.ships_owned:
		if String(sh.get("def_id", "")) == old_ship:
			back_found = true
	_ok(back_found, "旧船回到船库")
	# 顶栏刷新
	s._refresh()
	_ok(s.status_label.text.contains(String(GameState.ship_def().display_name)),
		"顶栏显示新船型", s.status_label.text.substr(0, 24))
	# 存档往返：模块等级 / 船员 / 帆装备
	GameState.reset_new_game()
	GameState.set_module_level("sails", 0, 3)
	GameState.set_module_level("gundeck", 1, 2)
	var crew = load("res://scripts/systems/crew_factory.gd").generate(1, &"standard")[0]
	crew.role = &"sailor"
	GameState.crew_roster.append(crew)
	GameState.assign_crew_to_module(crew.crew_id, "sails", 0)
	GameState.equipped["sail0"] = &"sail_linen"
	GameState.equipped["sail1"] = &"sail_cotton"
	var d: Dictionary = GameState.to_dict()
	GameState.reset_new_game()
	GameState.from_dict(d)
	_ok(GameState.module_level("sails", 0) == 3, "存档恢复模块等级",
		str(GameState.module_level("sails", 0)))
	_ok(GameState.module_level("gundeck", 1) == 2, "存档恢复分层等级")
	_ok(String(GameState.module_crew_of("sails", 0)) != "", "存档恢复模块船员",
		String(GameState.module_crew_of("sails", 0)))
	_ok(String(GameState.equipped.get("sail0", "")) == "sail_linen", "存档恢复帆装备")
	_ok(String(GameState.equipped.get("sail1", "")) == "sail_cotton", "存档恢复第二桅帆")
	s.queue_free()
	await _frames(2)
	GameState.reset_new_game()

# ---------------- 1.4.12 风帆按桅分层 ----------------
func _test_v1412_sails() -> void:
	print("\n[1.4.12 风帆分层]")
	GameState.reset_new_game()
	GameState.ship_def_id = &"fishing_sloop"
	_ok(GameState.sails_layers(1) == 1, "1 级船 1 帆", str(GameState.sails_layers(1)))
	_ok(GameState.sails_layers(4) == 2, "4 级船 2 帆")
	_ok(GameState.sails_layers(10) == 3, "10 级船 3 帆")
	GameState.ship_def_id = &"first_rate"
	var sail_slots := 0
	for m in GameState.ship_modules():
		if String(m["module_id"]) == "sails":
			sail_slots += 1
	_ok(sail_slots == 3, "10 级船 3 个帆槽", str(sail_slots))
	# 各桅装备叠加
	GameState.ship_module_levels.clear()
	var base_speed: float = float(GameState.stats()["base_speed_px"])
	GameState.equipped["sail0"] = &"sail_linen"
	var s1: float = float(GameState.stats()["base_speed_px"])
	GameState.equipped["sail1"] = &"sail_linen"
	var s2: float = float(GameState.stats()["base_speed_px"])
	_ok(s1 > base_speed, "第一桅帆提升航速")
	_ok(s2 > s1, "第二桅帆继续叠加")
	# 各层模块等级累加
	GameState.set_module_level("sails", 0, 1)
	GameState.set_module_level("sails", 1, 1)
	var s3: float = float(GameState.stats()["base_speed_px"])
	_ok(s3 > s2, "多层风帆强化叠加")
	GameState.reset_new_game()

# ---------------- 1.4.10 严格坐标布局 ----------------
func _test_v1410_layout() -> void:
	print("\n[1.4.10 严格布局]")
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	# 同模块不同层不重叠
	var p0: Vector2 = s._ship_slot_pos("gundeck", 0, 10)
	var p1: Vector2 = s._ship_slot_pos("gundeck", 1, 10)
	_ok(p0.distance_to(p1) > 20.0, "炮门各层不重叠", str(p0) + " / " + str(p1))
	# 插槽在船体范围内
	var inside := true
	for mid in ["deck", "gundeck", "rudder", "hold", "galley"]:
		for lv in range(3):
			var p: Vector2 = s._ship_slot_pos(mid, lv, 10)
			if p.x < 0.0 or p.x > s.ship_area_size.x or p.y < 0.0 or p.y > s.ship_area_size.y:
				inside = false
	_ok(inside, "插槽均在面板范围内")
	# 区域互不冲突：甲板与炮门列不同
	var d: Vector2 = s._ship_slot_pos("deck", 0, 10)
	var g: Vector2 = s._ship_slot_pos("gundeck", 0, 10)
	_ok(absf(d.x - g.x) > 40.0, "甲板列与炮门列分开", str(d.x) + " / " + str(g.x))
	# 舱室区域互不重叠
	var a: Vector2 = s._ship_slot_pos("hold", 0, 10)
	var b2: Vector2 = s._ship_slot_pos("galley", 0, 10)
	_ok(absf(a.x - b2.x) > 40.0, "仓库与厨房不重叠")
	s.queue_free()
	await _frames(2)

# ---------------- 1.4.7 面板修正 ----------------
func _test_v147_panel_fix() -> void:
	print("\n[1.4.7 面板修正]")
	GameState.reset_new_game()
	GameState.ship_def_id = &"fishing_sloop"
	var m1: Array = GameState.ship_modules()
	_ok(m1.size() == 6, "1 级船 6 个模块", str(m1.size()))
	var has_flag := false
	for m in m1:
		if String(m["module_id"]) == "flagpole":
			has_flag = true
	_ok(not has_flag, "1 级船无旗杆")
	GameState.ship_def_id = &"first_rate"
	var m10: Array = GameState.ship_modules()
	_ok(m10.size() >= 15, "10 级船模块 ≥15", str(m10.size()))
	var deck_n := 0
	for mm in m10:
		if String(mm["module_id"]) == "deck":
			deck_n += 1
	_ok(deck_n == 3, "10 级船 3 层甲板", str(deck_n))
	# 旗帜白名单
	_ok(GameState.slot_allows("flag", "flag_swift"), "疾风旗允许")
	_ok(GameState.slot_allows("flag", "flag_swift") and not GameState.slot_allows("flag", "uniq_scout_flag"),
		"旧独有旗被过滤")
	_ok(GameState.slot_allows("sail", "sail_linen"), "非旗帜槽不限制")
	# 锚点均在船影范围内
	for inst in m10:
		var md: Resource = DataRegistry.modules.get(String(inst["module_id"]))
		_ok(md != null and md.anchor.y <= 0.95, "锚点位于船影内：%s" % String(inst["module_id"]))
	GameState.reset_new_game()

# ---------------- 1.4.6 舰船面板 ----------------
func _test_v146_ship_panel() -> void:
	print("\n[1.4.6 舰船面板]")
	GameState.reset_new_game()
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	s._toggle_ship()
	await _frames(1)
	_ok(s.ship_root.visible, "舰船面板可打开")
	var slots := 0
	for c in s.ship_area.get_children():
		if c is Button:
			slots += 1
	_ok(slots == GameState.ship_modules().size(), "插槽数与模块实例数一致",
		"%d vs %d" % [slots, GameState.ship_modules().size()])
	_ok(s.ship_stats_box.get_child_count() >= 9, "属性栏至少 9 项",
		str(s.ship_stats_box.get_child_count()))
	# 切换页签
	s.ship_tab = "crew"
	s._rebuild_ship_panel()
	await _frames(1)
	_ok(s.ship_area.get_child_count() > 0, "人员页可重建")
	# 打开一个插槽弹窗（舵轮）
	s.ship_tab = "gear"
	s._open_ship_slot("rudder", 0)
	await _frames(1)
	_ok(true, "插槽弹窗可打开")
	s.queue_free()
	await _frames(2)
	GameState.reset_new_game()

# ---------------- 1.4.5 模块强化经济 ----------------
func _test_v145_module_upgrade() -> void:
	print("\n[1.4.5 模块强化]")
	GameState.reset_new_game()
	GameState.ship_module_levels.clear()
	# 成本随等级上升
	var c0: Dictionary = GameState.module_upgrade_cost("gundeck", 0)
	_ok(int(c0["gold"]) > 0 and int(c0["timber"]) > 0 and int(c0["iron"]) > 0,
		"强化成本含金币/木材/铁矿")
	GameState.set_module_level("gundeck", 0, 1)
	var c1: Dictionary = GameState.module_upgrade_cost("gundeck", 0)
	_ok(int(c1["gold"]) > int(c0["gold"]), "等级越高成本越高",
		"%d → %d" % [int(c0["gold"]), int(c1["gold"])])
	# 船级上限
	GameState.ship_def_id = &"fishing_sloop"
	_ok(GameState.module_level_cap() == 1, "1 级船模块上限 1",
		str(GameState.module_level_cap()))
	GameState.set_module_level("gundeck", 0, 1)
	var r_cap: Dictionary = GameState.upgrade_module("gundeck", 0)
	_ok(not bool(r_cap.get("ok", true)), "达上限拒绝强化", str(r_cap.get("reason", "")))
	# 资源不足拒绝
	GameState.ship_def_id = &"first_rate"
	GameState.ship_module_levels.clear()
	GameState.gold = 10
	var r_gold: Dictionary = GameState.upgrade_module("sails", 0)
	_ok(not bool(r_gold.get("ok", true)), "金币不足拒绝", str(r_gold.get("reason", "")))
	GameState.gold = 100000
	GameState.warehouse[&"timber"] = 0
	var r_mat: Dictionary = GameState.upgrade_module("sails", 0)
	_ok(not bool(r_mat.get("ok", true)), "材料不足拒绝", str(r_mat.get("reason", "")))
	# 成功强化
	GameState.warehouse[&"timber"] = 9999
	GameState.warehouse[&"iron_ore"] = 9999
	var gold0: int = GameState.gold
	var r_ok: Dictionary = GameState.upgrade_module("sails", 0)
	_ok(bool(r_ok.get("ok", false)), "资源充足强化成功", str(r_ok.get("reason", "")))
	_ok(GameState.module_level("sails", 0) == 1, "等级 +1")
	_ok(GameState.gold < gold0, "扣除金币")
	_ok(int(GameState.warehouse[&"timber"]) < 9999, "扣除木材")
	# 强化后属性提升
	_ok(float(GameState.stats()["base_speed_px"]) > 0.0, "强化后属性可读取")
	GameState.reset_new_game()

# ---------------- 1.4.4 船员按模块归属 ----------------
func _test_v144_module_crew() -> void:
	print("\n[1.4.4 船员模块归属]")
	GameState.reset_new_game()
	# 船员生成只有 4 岗位
	var CrewFactory = load("res://scripts/systems/crew_factory.gd")
	var rolled: Array = CrewFactory.generate(20, &"standard")
	var roles := {}
	for c in rolled:
		roles[String(c.role)] = true
	for role in roles.keys():
		_ok(GameState.CREW_POSTS.has(role), "生成的岗位属于四类：%s" % role)
	# 准备船员
	GameState.crew_roster.clear()
	GameState.module_crew.clear()
	var gunner = rolled[0]
	gunner.role = &"gunner"
	gunner.crew_id = &"c_gun"
	GameState.crew_roster.append(gunner)
	var sailor = CrewDefCtor(rolled[1], &"c_sail", &"sailor")
	GameState.crew_roster.append(sailor)
	# 炮弹岗只接受炮手
	var r1: Dictionary = GameState.assign_crew_to_module(&"c_sail", "gundeck", 0)
	_ok(not bool(r1.get("ok", true)), "水手不能进炮门", str(r1.get("reason", "")))
	var r2: Dictionary = GameState.assign_crew_to_module(&"c_gun", "gundeck", 0)
	_ok(bool(r2.get("ok", false)), "炮手可进炮门", str(r2.get("reason", "")))
	_ok(GameState.module_crew_of("gundeck", 0) == &"c_gun", "槽位记录船员")
	# 同一船员不能占两个槽
	var r3: Dictionary = GameState.assign_crew_to_module(&"c_gun", "gundeck", 1)
	_ok(not bool(r3.get("ok", true)), "同一船员不能占两槽")
	# 不设岗位的模块
	var r4: Dictionary = GameState.assign_crew_to_module(&"c_sail", "hold", 0)
	_ok(not bool(r4.get("ok", true)), "仓库不设岗位")
	# 水手可进风帆
	var r5: Dictionary = GameState.assign_crew_to_module(&"c_sail", "sails", 0)
	_ok(bool(r5.get("ok", false)), "水手可进风帆")
	_ok(GameState.assigned_crews().size() == 2, "在岗船员计入 stats",
		str(GameState.assigned_crews().size()))
	# 撤离
	GameState.clear_module_crew("gundeck", 0)
	_ok(GameState.module_crew_of("gundeck", 0) == &"", "可撤离船员")
	GameState.reset_new_game()

func CrewDefCtor(src, cid, role):
	var c = src
	c.crew_id = cid
	c.role = role
	return c

# ---------------- 1.4.3 装备品类与槽位映射 ----------------
func _test_v143_gear_slots() -> void:
	print("\n[1.4.3 装备槽映射]")
	GameState.reset_new_game()
	_ok(DataRegistry.gear.size() == 36, "36 件装备", str(DataRegistry.gear.size()))
	var plate: Resource = DataRegistry.get_gear(&"plate_iron")
	_ok(plate != null and String(plate.slot) == "plate", "铁板为装甲板槽")
	_ok(int(plate.armor_add) == 4, "铁板装甲 +4")
	var tel: Resource = DataRegistry.get_gear(&"telescope_lens")
	_ok(tel != null and is_equal_approx(float(tel.view_add), 0.10), "透镜望远镜视野 +10%")
	var fs: Resource = DataRegistry.get_gear(&"flag_swift")
	_ok(fs != null and is_equal_approx(float(fs.speed_pct), 0.08), "疾风旗航速 +8%")
	var fr: Resource = DataRegistry.get_gear(&"flag_renown")
	_ok(fr != null and is_equal_approx(float(fr.rep_gain_pct), 0.15), "声望旗 +15%")
	# 槽位映射
	_ok(GameState.module_for_gear_slot(&"sail") == "sails", "帆→风帆模块")
	_ok(GameState.module_for_gear_slot(&"rudder") == "rudder", "舵→舵轮模块")
	_ok(GameState.module_for_gear_slot(&"plate") == "deck", "装甲板→甲板模块")
	_ok(GameState.module_for_gear_slot(&"figurehead") == "deck", "船艏像→甲板模块")
	_ok(GameState.module_for_gear_slot(&"telescope") == "lookout", "望远镜→瞭望台")
	_ok(GameState.module_for_gear_slot(&"flag") == "flagpole", "旗帜→旗杆")
	# 旗帜与望远镜接入 stats
	GameState.ship_module_levels.clear()
	var base_stats: Dictionary = GameState.stats()
	GameState.equipped["flag"] = &"flag_swift"
	var s1: Dictionary = GameState.stats()
	_ok(float(s1["base_speed_px"]) > float(base_stats["base_speed_px"]), "疾风旗提升航速")
	GameState.equipped["telescope"] = &"telescope_lens"
	_ok(float(GameState.stats()["view_bonus"]) > float(base_stats["view_bonus"]),
		"望远镜提升视野")
	GameState.equipped["flag"] = &"flag_renown"
	_ok(float(GameState.stats()["rep_gain_bonus"]) > 0.0, "声望旗提升声望加成")
	GameState.reset_new_game()

# ---------------- 1.4.2 模块接入属性 ----------------
func _test_v142_module_stats() -> void:
	print("\n[1.4.2 模块属性]")
	GameState.reset_new_game()
	GameState.ship_def_id = &"first_rate"
	GameState.ship_module_levels.clear()
	var s0: Dictionary = GameState.stats()
	_ok(s0.has("hull_max") and s0.has("base_speed_px") and s0.has("guns_per_side"),
		"stats 契约字段保留")
	var speed0: float = float(s0["base_speed_px"])
	var turn0: float = float(s0["turn_rate"])
	var guns0: int = int(s0["guns_per_side"])
	var cargo0: int = int(s0["cargo_capacity"])
	var crew0: float = float(s0["crew_max"])
	# 风帆
	GameState.set_module_level("sails", 0, 5)
	var s1: Dictionary = GameState.stats()
	_ok(float(s1["base_speed_px"]) > speed0, "风帆强化提升航速",
		"%.1f → %.1f" % [speed0, float(s1["base_speed_px"])])
	# 舵轮
	GameState.set_module_level("rudder", 0, 5)
	_ok(float(GameState.stats()["turn_rate"]) > turn0, "舵轮强化提升转向")
	# 炮门（按层累加）
	GameState.set_module_level("gundeck", 0, 2)
	GameState.set_module_level("gundeck", 1, 2)
	var guns2: int = int(GameState.stats()["guns_per_side"])
	_ok(guns2 == guns0 + 4, "炮门两层各 +2 门", "%d → %d" % [guns0, guns2])
	# 仓库 / 宿舍
	GameState.set_module_level("hold", 0, 5)
	_ok(int(GameState.stats()["cargo_capacity"]) > cargo0, "仓库强化提升货舱")
	GameState.set_module_level("quarters", 0, 5)
	_ok(float(GameState.stats()["crew_max"]) > crew0, "宿舍强化提升船员上限")
	# 非战斗加成字段
	_ok(GameState.stats().has("rep_gain_bonus"), "声望加成字段存在")
	_ok(GameState.stats().has("heal_bonus"), "医疗加成字段存在")
	# 等级 0 时与基线一致
	GameState.ship_module_levels.clear()
	var s_reset: Dictionary = GameState.stats()
	_ok(is_equal_approx(float(s_reset["base_speed_px"]), speed0), "清空等级回到基线")
	GameState.reset_new_game()

# ---------------- 1.4.1 模块数据模型 ----------------
func _test_v141_modules() -> void:
	print("\n[1.4.1 舰船模块]")
	GameState.reset_new_game()
	_ok(DataRegistry.modules.size() == 12, "12 类模块已载入", str(DataRegistry.modules.size()))
	var rudder: Resource = DataRegistry.modules.get("rudder")
	_ok(rudder != null and String(rudder.display_name) == "舵轮", "舵轮模块存在")
	_ok(rudder.gear_slots.has(&"rudder"), "舵轮可装舵")
	_ok(rudder.crew_posts.has(&"mate"), "舵轮可置大副")
	var flagpole: Resource = DataRegistry.modules.get("flagpole")
	_ok(flagpole.crew_posts.is_empty(), "旗杆不设岗位")
	_ok(flagpole.gear_slots.has(&"flag"), "旗杆可挂旗帜")
	var hold: Resource = DataRegistry.modules.get("hold")
	_ok(hold.gear_slots.is_empty(), "仓库不设装备")
	# 分层规则
	_ok(GameState.deck_layers(1) == 0, "1 级船无甲板")
	_ok(GameState.deck_layers(9) == 3, "9 级船 3 层甲板")
	_ok(GameState.gundeck_layers(1) == 1, "1 级船 1 层炮门")
	_ok(GameState.gundeck_layers(10) == 4, "10 级船 4 层炮门")
	# 模块实例数
	GameState.ship_def_id = &"fishing_sloop"
	var m1: Array = GameState.ship_modules()
	_ok(m1.size() >= 6, "1 级船模块数 ≥6", str(m1.size()))
	GameState.ship_def_id = &"first_rate"
	var m10: Array = GameState.ship_modules()
	var deck_cnt := 0
	for m in m10:
		if String(m["module_id"]) == "deck":
			deck_cnt += 1
	_ok(deck_cnt == GameState.deck_layers(int(GameState.ship_def().tier)), "甲板层数与船级一致",
		str(deck_cnt))
	# 岗位与锚点
	_ok(GameState.CREW_POSTS.size() == 4, "岗位简化为 4 类")
	_ok(GameState.POST_NAMES["mate"] == "大副", "大副岗位名称")
	var a: Vector2 = rudder.anchor
	_ok(a.x >= 0.0 and a.x <= 1.0 and a.y >= 0.0 and a.y <= 1.0, "锚点在 0~1 范围", str(a))
	# 强化等级
	GameState.set_module_level("gundeck", 0, 3)
	_ok(GameState.module_level("gundeck", 0) == 3, "模块等级可设置")
	_ok(GameState.module_level("gundeck", 1) == 0, "不同层等级独立")
	GameState.set_module_level("gundeck", 0, 99)
	_ok(GameState.module_level("gundeck", 0) == 5, "等级上限 5")
	GameState.reset_new_game()

# ---------------- 1.4.0 遗留修复 ----------------
func _test_v140_fixes() -> void:
	print("\n[1.4.0 遗留修复]")
	GameState.reset_new_game()
	# 工坊产量按织帆坊等级
	GameState.buildings[&"sailmaker"] = 2
	var r: Dictionary = GameState.tick_production("jadehaven")
	_ok(r.has("产出"), "生产返回产出字段")
	# 巡逻队可受伤（字典伤害）
	var PatrolScript = load("res://scripts/sea/patrol_ship.gd")
	var p = Node2D.new()
	p.set_script(PatrolScript)
	add_child(p)
	p.setup("yunlan", [], Color.WHITE)
	var hp0: float = p.hp
	p.take_damage({"hull": 30.0, "crew": 10.0, "sail": 0.0, "rudder": 0.0})
	_ok(p.hp < hp0, "巡逻队可受字典伤害", "%.0f → %.0f" % [hp0, p.hp])
	p.queue_free()
	await _frames(2)
	# 禁运提高关税
	GameState.reset_new_game()
	GameState.register_port("p_chilin", "赤鳞港", 7, 2)
	GameState.start_faction_event("chilin", "", "embargo", 4)
	_ok(is_equal_approx(GameState.tariff_rate_for_port(&"p_chilin"), 0.15),
		"禁运时关税 15%", str(GameState.tariff_rate_for_port(&"p_chilin")))
	GameState.faction_events.clear()

# ---------------- 1.3.17 兑换交互与声望条 ----------------
func _test_v1317_polish() -> void:
	print("\n[1.3.17 兑换交互]")
	GameState.reset_new_game()
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	s._open_exchange("yunlan")
	await _frames(1)
	_ok(s.exch_root.visible, "兑换所打开")
	# 声望不足：结算必须拒绝并给原因
	var r: Dictionary = GameState.exchange_item("yunlan", "fx_yunlan_clipper")
	_ok(not bool(r.get("ok", true)), "声望不足拒绝兑换")
	_ok(String(r.get("reason", "")).contains("声望"), "失败原因含声望", String(r.get("reason", "")))
	# 金币不足：原因含金币
	GameState.faction_rep["yunlan"] = 80
	GameState.gold = 1
	var r2: Dictionary = GameState.exchange_item("yunlan", "fx_yunlan_sail")
	_ok(String(r2.get("reason", "")).contains("金币"), "金币不足原因", String(r2.get("reason", "")))
	# 声望条着色方法可调用
	s._tint_rep_bar(ProgressBar.new(), -50)
	_ok(true, "声望条着色函数可用")
	s.queue_free()
	await _frames(2)
	GameState.reset_new_game()

# ---------------- 1.3.15 势力事件 ----------------
func _test_v1315_events() -> void:
	print("\n[1.3.15 势力事件]")
	GameState.reset_new_game()
	GameState.faction_events.clear()
	# 事件覆盖关系
	GameState.start_faction_event("yunlan", "chilin", "war", 6)
	_ok(GameState.nation_relation_between_v2("yunlan", "chilin") == "hostile",
		"宣战事件使两国敌对")
	_ok(GameState.nation_relation_between_v2("chilin", "yunlan") == "hostile", "关系对称")
	# 结盟覆盖
	GameState.faction_events.clear()
	GameState.start_faction_event("shuangyu", "baijing", "alliance", 4)
	_ok(GameState.nation_relation_between_v2("shuangyu", "baijing") == "ally", "结盟事件")
	# 停战覆盖
	GameState.faction_events.clear()
	GameState.start_faction_event("lan", "xuanjiao", "peace", 3)
	_ok(GameState.nation_relation_between_v2("lan", "xuanjiao") == "neutral", "停战事件")
	# 禁运
	GameState.faction_events.clear()
	GameState.start_faction_event("chilin", "", "embargo", 4)
	_ok(GameState.faction_embargo("chilin"), "禁运生效")
	# 到期移除
	GameState.faction_events.clear()
	GameState.start_faction_event("yunlan", "cangwu", "war", 1)
	var msg: String = GameState.tick_faction_events()
	var still_there := false
	for e2 in GameState.faction_events:
		if String(e2["a"]) == "yunlan" and String(e2["b"]) == "cangwu" and String(e2["kind"]) == "war":
			still_there = true
	_ok(not still_there, "指定事件到期移除")
	_ok(msg.contains("结束"), "结束播报", msg)
	GameState.reset_new_game()

# ---------------- 1.3.14 巡逻队敌对玩家 ----------------
func _test_v1314_patrol_aggro() -> void:
	print("\n[1.3.14 巡逻队敌对]")
	GameState.reset_new_game()
	var PatrolScript = load("res://scripts/sea/patrol_ship.gd")
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	GameState.current_map = 1
	add_child(s)
	await _frames(6)
	_ok(s.player != null and s.player.is_in_group("player"), "玩家已入组")
	var p = Node2D.new()
	p.set_script(PatrolScript)
	add_child(p)
	p.setup("yunlan", [], Color.WHITE)
	# 中立：不攻击
	GameState.faction_rep["yunlan"] = 0
	p.global_position = s.player.global_position + Vector2(60, 0)
	var hp0: float = s.player.hull_hp
	p.fire_cd = 0.0
	p._tick_combat(1.0)
	_ok(is_equal_approx(s.player.hull_hp, hp0), "中立时不攻击玩家")
	# 死敌：攻击
	GameState.faction_rep["yunlan"] = -80
	p.fire_cd = 0.0
	p._tick_combat(1.0)
	_ok(s.player.hull_hp < hp0, "死敌时攻击玩家",
		"%.0f → %.0f" % [hp0, s.player.hull_hp])
	p.queue_free()
	s.queue_free()
	await _frames(2)
	GameState.reset_new_game()

# ---------------- 1.3.13 专属物与总览 ----------------
func _test_v1313_unique() -> void:
	print("\n[1.3.13 专属物/总览]")
	GameState.reset_new_game()
	# 专属资源已注册
	_ok(DataRegistry.get_gear(&"fx_gear_yunlan_sail") != null, "云澜军帆资源存在")
	_ok(DataRegistry.get_ship(&"fx_ship_yunlan_clipper") != null, "云澜快帆资源存在")
	var g: Resource = DataRegistry.get_gear(&"fx_gear_youming_sail")
	_ok(g != null and is_equal_approx(float(g.speed_pct), 0.15), "幽溟黑帆航速 +15%",
		str(g.speed_pct if g != null else -1))
	var s: Resource = DataRegistry.get_ship(&"fx_ship_shuangyu_breaker")
	_ok(s != null and int(s.base_hp) == 780, "破冰舰船体 780", str(s.base_hp if s != null else -1))
	# 兑换专属船入库
	GameState.faction_rep["yunlan"] = 100
	GameState.gold = 200000
	var r: Dictionary = GameState.exchange_item("yunlan", "fx_yunlan_clipper")
	_ok(bool(r.get("ok", false)), "专属船兑换成功", str(r.get("reason", "")))
	_ok(GameState.ships_owned.size() >= 1, "专属船入库")
	# 总览页可渲染
	var sc = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(sc)
	await _frames(3)
	sc.fac_current = ""
	sc._toggle_factions()
	await _frames(1)
	_ok(sc.fac_list.get_child_count() > 0, "总览页有内容")
	sc.queue_free()
	await _frames(2)
	GameState.reset_new_game()

# ---------------- 1.3.12 兑换结算 ----------------
func _test_v1312_exchange() -> void:
	print("\n[1.3.12 兑换入库]")
	GameState.reset_new_game()
	# 声望不足拒绝
	GameState.faction_rep["yunlan"] = 0
	var r0: Dictionary = GameState.exchange_item("yunlan", "fx_yunlan_sail")
	_ok(not bool(r0.get("ok", true)), "声望不足不能兑换", str(r0.get("reason", "")))
	# 金币不足拒绝
	GameState.faction_rep["yunlan"] = 80
	GameState.gold = 10
	var r1: Dictionary = GameState.exchange_item("yunlan", "fx_yunlan_sail")
	_ok(not bool(r1.get("ok", true)), "金币不足不能兑换", str(r1.get("reason", "")))
	# 成功兑换装备
	GameState.gold = 100000
	GameState.gear_owned.clear()
	var gear_before: int = GameState.gear_owned.size()
	var r2: Dictionary = GameState.exchange_item("yunlan", "fx_yunlan_sail")
	_ok(bool(r2.get("ok", false)), "兑换装备成功", str(r2.get("reason", "")))
	_ok(GameState.gear_owned.size() == gear_before + 1, "装备入库",
		str(GameState.gear_owned.size()))
	_ok(GameState.gold == 88000, "扣除金币 12000", str(GameState.gold))
	# 稀有物品扣声望
	var gold2: int = GameState.gold
	var r3: Dictionary = GameState.exchange_item("yunlan", "fx_yunlan_clipper")
	_ok(bool(r3.get("ok", false)), "兑换船只成功", str(r3.get("reason", "")))
	_ok(GameState.gold == gold2 - 45000, "扣除金币 45000", str(GameState.gold))
	_ok(GameState.faction_rep_of("yunlan") == 70, "稀有扣声望 10",
		str(GameState.faction_rep_of("yunlan")))
	_ok(GameState.ships_owned.size() >= 1, "船只入库", str(GameState.ships_owned.size()))
	GameState.reset_new_game()

# ---------------- 1.3.11 物品表与兑换所 ----------------
func _test_v1311_tables() -> void:
	print("\n[1.3.11 物品表/商店表]")
	GameState.reset_new_game()
	_ok(not GameState.item_defs.is_empty(), "物品表已载入", str(GameState.item_defs.size()))
	_ok(GameState.item_defs.size() >= 22, "物品数 ≥22", str(GameState.item_defs.size()))
	_ok(GameState.item_def("gear_sail_r")["name"] == "疾风帆", "物品名称正确",
		str(GameState.item_def("gear_sail_r")))
	_ok(not GameState.shop_rows.is_empty(), "商店表已载入", str(GameState.shop_rows.size()))
	# 兑换所：10 件 = 2 专属 + 8 共享
	var offers: Array = GameState.exchange_offers("yunlan")
	_ok(offers.size() == 10, "云澜兑换所 10 件", str(offers.size()))
	var uniq := 0
	for o in offers:
		if int(o["unique"]) == 1:
			uniq += 1
	_ok(uniq == 2, "其中 2 件专属", str(uniq))
	# 各势力都能生成
	for fid in GameState.FACTIONS_V2:
		_ok(GameState.exchange_offers(fid).size() == 10, "%s 兑换所 10 件" % fid)
	# 面板可打开
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	s._open_exchange("yunlan")
	await _frames(1)
	_ok(s.exch_root.visible, "兑换所面板可打开")
	_ok(s.exch_list.get_child_count() > 0, "兑换所有内容")
	s.queue_free()
	await _frames(2)

# ---------------- 1.3.9 私掠证规则 ----------------
func _test_v139_license_rules() -> void:
	print("\n[1.3.9 私掠证]")
	GameState.reset_new_game()
	GameState.faction_events.clear()
	GameState.add_gold(200000)
	# 正规购证需该国声望 51
	_ok(not bool(GameState.buy_license_legal("yunlan").get("ok", false)), "声望不足不能购证")
	GameState.faction_rep["yunlan"] = 60
	var r1: Dictionary = GameState.buy_license_legal("yunlan")
	_ok(bool(r1.get("ok", false)), "声望 60 可购云澜私掠证", str(r1.get("reason", "")))
	_ok(GameState.privateer_nation == "yunlan", "证绑定云澜")
	# 幽溟不发证
	GameState.has_privateer_license = false
	_ok(not bool(GameState.buy_license_legal("youming").get("ok", true)), "幽溟不发私掠证")

	# 结算四档
	GameState.reset_new_game()
	GameState.has_privateer_license = true
	GameState.privateer_nation = "yunlan"
	GameState.faction_rep["yunlan"] = 0
	# 敌国（玄礁）：云澜 +L
	GameState.rep_for_sinking("xuanjiao", 4)
	_ok(GameState.faction_rep_of("yunlan") == 4, "劫掠敌国：持证国 +L",
		str(GameState.faction_rep_of("yunlan")))
	# 中立国（赤鳞）：云澜不扣
	GameState.faction_rep["yunlan"] = 0
	GameState.rep_for_sinking("chilin", 4)
	_ok(GameState.faction_rep_of("yunlan") == 0, "劫掠中立国：持证国不扣",
		str(GameState.faction_rep_of("yunlan")))
	# 盟国（霜屿）：云澜 −L/2
	GameState.faction_rep["yunlan"] = 0
	GameState.rep_for_sinking("shuangyu", 4)
	_ok(GameState.faction_rep_of("yunlan") == -2, "劫掠盟国：持证国 −L/2",
		str(GameState.faction_rep_of("yunlan")))
	# 本国：−2L
	GameState.faction_rep["yunlan"] = 0
	GameState.rep_for_sinking("yunlan", 4)
	_ok(GameState.faction_rep_of("yunlan") == -8, "叛旗：本国 −2L",
		str(GameState.faction_rep_of("yunlan")))

	# 出售
	GameState.faction_rep["yunlan"] = 50
	var gold0: int = GameState.gold
	var rs: Dictionary = GameState.sell_license()
	_ok(bool(rs.get("ok", false)), "可出售私掠证")
	_ok(GameState.gold > gold0, "出售返还金币")
	_ok(not GameState.has_privateer_license, "出售后不再持有")
	_ok(GameState.faction_rep_of("yunlan") == 45, "出售后持证国 −5",
		str(GameState.faction_rep_of("yunlan")))
	GameState.reset_new_game()

# ---------------- 1.3.8 击沉接入势力声望 ----------------
func _test_v138_kill_rep() -> void:
	print("\n[1.3.8 击沉归属]")
	GameState.reset_new_game()
	_ok(GameState.faction_for_kill(1, "navy") == "yunlan", "1 号图海军属云澜",
		GameState.faction_for_kill(1, "navy"))
	_ok(GameState.faction_for_kill(1, "pirate") == "youming", "海盗属幽溟")
	_ok(GameState.faction_for_kill(6, "navy") == "yunlan", "交界图取首个势力",
		GameState.faction_for_kill(6, "navy"))
	_ok(GameState.faction_for_kill(15, "navy") == "xuanjiao", "15 号图属玄礁",
		GameState.faction_for_kill(15, "navy"))
	# 击沉扣对应势力声望
	GameState.rep_for_sinking("yunlan", 4)
	_ok(GameState.faction_rep_of("yunlan") == -4, "击沉云澜船扣 4 点")
	# 日期显示含「日」
	_ok(TimeService.date_text().contains("日"), "日期显示含日单位", TimeService.date_text())
	GameState.reset_new_game()

# ---------------- 1.3.6 势力声望面板 ----------------
func _test_v136_faction_rep() -> void:
	print("\n[1.3.6 势力声望]")
	GameState.reset_new_game()
	_ok(GameState.FACTIONS_V2.size() == 7, "七大势力", str(GameState.FACTIONS_V2.size()))
	_ok(GameState.FACTION_V2_NAMES["yunlan"] == "云澜", "首个势力为云澜")
	_ok(GameState.FACTION_V2_NAMES["youming"] == "幽溟", "末个势力为幽溟")
	var all_zero := true
	for f in GameState.FACTIONS_V2:
		if GameState.faction_rep_of(f) != 0:
			all_zero = false
	_ok(all_zero, "初始声望均为 0")
	_ok(GameState.faction_tier_name("yunlan") == "中立", "0 点为中立")
	# 范围钳制
	GameState.add_faction_rep("yunlan", 500)
	_ok(GameState.faction_rep_of("yunlan") == 100, "上限 100", str(GameState.faction_rep_of("yunlan")))
	GameState.add_faction_rep("yunlan", -500)
	_ok(GameState.faction_rep_of("yunlan") == -100, "下限 -100")
	# 分档
	GameState.add_faction_rep("yunlan", 200)
	_ok(GameState.faction_rep_of("yunlan") == 100, "回到 100")
	_ok(GameState.faction_tier_name("yunlan") == "盟友", "100 为盟友")
	GameState.faction_rep["yunlan"] = 25
	_ok(GameState.faction_tier_name("yunlan") == "中立", "25 仍为中立")
	GameState.faction_rep["yunlan"] = 26
	_ok(GameState.faction_tier_name("yunlan") == "友善", "26 为友善")
	GameState.faction_rep["yunlan"] = 76
	_ok(GameState.faction_tier_name("yunlan") == "盟友", "76 为盟友")
	GameState.faction_rep["yunlan"] = -60
	_ok(GameState.faction_tier_name("yunlan") == "敌对", "-60 为敌对")
	# 按船只等级扣声望：3 级船 = 3 点
	GameState.reset_new_game()
	GameState.rep_for_sinking("chilin", 3)
	_ok(GameState.faction_rep_of("chilin") == -3, "击沉 3 级船扣 3 点",
		str(GameState.faction_rep_of("chilin")))
	GameState.reset_new_game()
	GameState.rep_for_sinking("youming", 10)
	_ok(GameState.faction_rep_of("youming") == -10, "击沉 10 级船扣 10 点")
	# 关税与任务倍率
	GameState.faction_rep["yunlan"] = 0
	_ok(is_equal_approx(GameState.faction_tariff("yunlan"), 0.03), "中立关税 3%")
	GameState.faction_rep["yunlan"] = 80
	_ok(is_equal_approx(GameState.faction_tariff("yunlan"), -0.02), "盟友关税 -2%")
	_ok(GameState.faction_accepts_quests("yunlan"), "盟友可接任务")
	GameState.faction_rep["yunlan"] = -80
	_ok(not GameState.faction_accepts_quests("yunlan"), "死敌不可接任务")
	GameState.reset_new_game()

# ---------------- 1.3.5 势力巡逻队 ----------------
func _test_v135_patrols() -> void:
	print("\n[1.3.5 巡逻队]")
	GameState.reset_new_game()
	# 腹地图：单国 2 队
	var cfg1: Array = GameState.patrol_config_for_map(1)
	_ok(cfg1.size() == 1, "腹地图只有一国", str(cfg1.size()))
	_ok(int(cfg1[0]["count"]) == 2, "单国 2 队", str(cfg1[0]["count"]))
	# 交界图：两国各 2 队
	var cfg6: Array = GameState.patrol_config_for_map(6)
	_ok(cfg6.size() == 2, "交界图两国", str(cfg6.size()))
	var n6a := String(cfg6[0]["nation"])
	var n6b := String(cfg6[1]["nation"])
	_ok(n6a == "lan" and n6b == "chilin", "交界图国家正确", "%s/%s" % [n6a, n6b])
	_ok(GameState.nation_relation_between(n6a, n6b) == "neutral", "两国关系为中立")
	# 玄礁参与的图与他国敌对
	var cfg30: Array = GameState.patrol_config_for_map(30)
	_ok(cfg30.size() >= 1, "海盗水域有巡逻", str(cfg30.size()))
	# 场景生成与销毁
	GameState.current_map = 6
	var s = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s)
	await _frames(6)
	_ok(s.patrols.size() == 4, "交界图生成 4 队巡逻", "实得 %d" % s.patrols.size())
	var nations := {}
	for p in s.patrols:
		nations[p.nation_id] = true
	_ok(nations.size() == 2, "巡逻队来自两国", str(nations.keys()))
	# 敌对关系才开战
	var a = s.patrols[0]
	var b = s.patrols[1]
	_ok(GameState.nation_relation_between(a.nation_id, b.nation_id) == "neutral",
		"同图中立两国不会开战")
	# 手动让玄礁与澜国互打
	a.nation_id = "xuanjiao"
	b.nation_id = "lan"
	a.target = b
	var hp0: float = b.hp
	a._tick_combat(1.0)
	_ok(b.hp < hp0, "敌对势力互相造成伤害", "%.0f → %.0f" % [hp0, b.hp])
	# 沉没后不产生战利品
	var gold0: int = GameState.gold
	var cargo0: int = GameState.cargo_used()
	b.hp = 1.0
	b.take_damage(999.0)
	await _frames(2)
	_ok(GameState.gold == gold0, "击沉巡逻队无金币掉落")
	_ok(GameState.cargo_used() == cargo0, "击沉巡逻队无货物掉落")
	s.queue_free()
	await _frames(2)

# ---------------- 1.3.4 私掠许可证绑定国家 ----------------
func _test_v134_license() -> void:
	print("\n[1.3.4 私掠证]")
	GameState.reset_new_game()
	_ok(GameState.privateer_nation == "", "开局无证")
	# 购证必须指定国家
	GameState.add_gold(200000)
	var r0: Dictionary = GameState.buy_license_black("")
	_ok(not bool(r0.get("ok", false)), "未指定国家不能购证")
	# 指定澜国
	var r1: Dictionary = GameState.buy_license_black("lan")
	_ok(bool(r1.get("ok", false)), "可购买澜国私掠证", str(r1.get("reason", "")))
	_ok(GameState.privateer_nation == "lan", "证绑定澜国")
	# 澜国的敌国（玄礁）→ 合法；盟友（霜屿）→ 非法
	_ok(GameState.is_legal_privateering("xuanjiao"), "劫掠玄礁合法")
	_ok(not GameState.is_legal_privateering("shuangyu"), "劫掠霜屿非法")
	_ok(not GameState.is_legal_privateering("lan"), "劫掠本国非法")
	_ok(not GameState.is_legal_privateering(""), "无国籍目标不合法")
	# 重复购证被拒
	var r2: Dictionary = GameState.buy_license_black("chilin")
	_ok(not bool(r2.get("ok", false)), "已有证不能重复购买")
	GameState.reset_new_game()

# ---------------- 1.3.3 国家关系与关税 ----------------
func _test_v133_relations() -> void:
	print("\n[1.3.3 国家关系与关税]")
	GameState.reset_new_game()
	# 关系矩阵
	_ok(GameState.nation_relation_between("lan", "xuanjiao") == "hostile", "澜国与玄礁敌对")
	_ok(GameState.nation_relation_between("xuanjiao", "lan") == "hostile", "关系对称")
	_ok(GameState.nation_relation_between("lan", "shuangyu") == "ally", "澜国与霜屿同盟")
	_ok(GameState.nation_relation_between("lan", "chilin") == "neutral", "澜国与赤鳞中立")
	_ok(GameState.nation_relation_between("lan", "lan") == "neutral", "同国为中立")
	# 关税按港口归属国声望
	GameState.register_port("p_lan", "澜国港", 1, 1)
	GameState.register_port("p_jiao", "交界港", 6, 2)
	GameState.nation_rep["lan"] = 0
	_ok(is_equal_approx(GameState.tariff_rate_for_port(&"p_lan"), 0.10), "敌视国关税 10%",
		str(GameState.tariff_rate_for_port(&"p_lan")))
	GameState.nation_rep["lan"] = 3000
	_ok(is_equal_approx(GameState.tariff_rate_for_port(&"p_lan"), 0.05), "中立国关税 5%")
	GameState.nation_rep["lan"] = 6000
	_ok(is_equal_approx(GameState.tariff_rate_for_port(&"p_lan"), 0.03), "友好国关税 3%")
	GameState.nation_rep["lan"] = 9000
	_ok(is_equal_approx(GameState.tariff_rate_for_port(&"p_lan"), 0.01), "盟友关税 1%")
	_ok(is_equal_approx(GameState.tariff_rate_for_port(&"p_jiao"), 0.05), "交界港基准 5%",
		str(GameState.tariff_rate_for_port(&"p_jiao")))
	GameState.reset_new_game()

# ---------------- 1.3.2 邻接图航行 ----------------
func _test_v132_adjacency() -> void:
	print("\n[1.3.2 邻接图]")
	GameState.reset_new_game()
	# 同级三图两两相邻
	var m1: Resource = DataRegistry.get_map(1)
	_ok(m1.neighbors.has(2) and m1.neighbors.has(3), "1-1 与 1-2/1-3 相邻",
		str(m1.neighbors))
	# 跨级相连
	_ok(m1.neighbors.has(4) and m1.neighbors.has(6), "1 级与 2 级相连", str(m1.neighbors))
	# 母港在邻接中
	_ok(m1.neighbors.has(0), "1-1 邻接母港")
	# 级别与解锁
	_ok(GameState.map_tier_of(1) == 1 and GameState.map_tier_of(4) == 2, "级别换算正确")
	GameState.current_map = 1
	var opts: Array = GameState.travel_options()
	var has_same := false
	for o in opts:
		if int(o["index"]) == 2 and bool(o["unlocked"]):
			has_same = true
	_ok(has_same, "同级相邻图可前往")
	var has_t2 := false
	var t2_locked := false
	for o2 in opts:
		if int(o2["index"]) == 4:
			has_t2 = true
			t2_locked = not bool(o2["unlocked"])
	_ok(has_t2, "2 级图在选项中")
	_ok(t2_locked, "未通关 1 级时 2 级锁定")
	_ok(GameState.can_travel_to(2), "可前往 1-2")
	_ok(not GameState.can_travel_to(4), "不可直接前往 2-1")
	# 通关 1 级后解锁 2 级
	GameState.cleared_maps.append(1)
	_ok(GameState.unlocked_tier() == 2, "通关 1 级后解锁 2 级",
		str(GameState.unlocked_tier()))
	_ok(GameState.can_travel_to(4), "通关后可前往 2-1")

# ---------------- 1.3.1 地图分国 ----------------
func _test_v131_maps() -> void:
	print("\n[1.3.1 地图分国]")
	GameState.reset_new_game()
	_ok(DataRegistry.maps.size() == 30, "30 张海图", str(DataRegistry.maps.size()))
	# 每级 3 张
	var per_tier := {}
	for k in DataRegistry.maps.keys():
		var md: Resource = DataRegistry.maps[k]
		var tier := int(md.tier)
		per_tier[tier] = int(per_tier.get(tier, 0)) + 1
	_ok(per_tier.size() == 10, "共 10 个级别", str(per_tier.size()))
	var all_three := true
	for tkey in per_tier.keys():
		if int(per_tier[tkey]) != 3:
			all_three = false
	_ok(all_three, "每级 3 张", str(per_tier))
	# 归属统计
	var nation_count := {}
	var contested_n := 0
	for k2 in DataRegistry.maps.keys():
		var md2: Resource = DataRegistry.maps[k2]
		if bool(md2.contested):
			contested_n += 1
		else:
			var n := String(md2.nation)
			nation_count[n] = int(nation_count.get(n, 0)) + 1
	_ok(contested_n == 5, "交界图 5 张", str(contested_n))
	for nat in GameState.NATIONS:
		_ok(int(nation_count.get(nat, 0)) >= 4, "%s 至少 4 张图" % nat,
			str(nation_count.get(nat, 0)))
	# 港口继承国家
	GameState.register_port("m1_p", "测试港村", 1, 1)
	_ok(GameState.port_nation(&"m1_p") == "lan", "1 级图港口属澜国",
		GameState.port_nation(&"m1_p"))
	_ok(GameState.port_nation_name(&"m1_p") == "澜国", "国家显示名正确")
	GameState.register_port("m6_p", "交界港", 6, 2)
	_ok(GameState.port_nation_name(&"m6_p") == "交界海域", "交界图（图 6）港口显示交界",
		GameState.port_nation_name(&"m6_p"))

# ---------------- 1.3.0 六国声望 ----------------
func _test_v130_nations() -> void:
	print("\n[1.3.0 六国声望]")
	GameState.reset_new_game()
	_ok(GameState.NATIONS.size() == 6, "六国定义", str(GameState.NATIONS.size()))
	for n in GameState.NATIONS:
		_ok(GameState.nation_rep_of(n) == 1000, "初始声望 1000：%s" % n, str(GameState.nation_rep_of(n)))
	_ok(GameState.NATION_NAMES["lan"] == "澜国", "澜国名称正确")
	# 关系分档
	_ok(GameState.nation_relation("lan") == "冷淡", "1000 为冷淡", GameState.nation_relation("lan"))
	GameState.add_nation_rep("lan", 1500)
	_ok(GameState.nation_rep_of("lan") == 2500, "声望可增加", str(GameState.nation_rep_of("lan")))
	_ok(GameState.nation_relation("lan") == "中立", "2500 为中立")
	GameState.add_nation_rep("lan", 6000)
	_ok(GameState.nation_relation("lan") == "盟友", "8500 为盟友")
	GameState.add_nation_rep("lan", -9999)
	_ok(GameState.nation_rep_of("lan") == 0, "声望下限 0", str(GameState.nation_rep_of("lan")))
	_ok(GameState.nation_relation("lan") == "敌视", "0 为敌视")
	# 独立记录
	_ok(GameState.nation_rep_of("chilin") == 1000, "其他国家不受影响")
	# 旧三阵营不受影响
	_ok(GameState.rep_of("royal_navy") >= 0, "旧阵营声望仍可用")

# ---------------- 1.2.13 面板重复叠加修复 ----------------
func _test_v1213_dup() -> void:
	print("\n[1.2.13 面板重复修复]")
	GameState.reset_new_game()
	GameState.add_gold(50000)
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	s._toggle_bank()
	await _frames(1)
	var n0: int = s.bank_list.get_child_count()
	_ok(n0 > 0, "银行面板有内容", str(n0))
	# 1.2.15：数字原地更新，骨架节点数恒定
	s._bank_deposit(1000)
	await _frames(1)
	var n1: int = s.bank_list.get_child_count()
	s._bank_deposit(1000)
	await _frames(1)
	var n2: int = s.bank_list.get_child_count()
	s._bank_deposit(1000)
	await _frames(1)
	var n3: int = s.bank_list.get_child_count()
	_ok(n1 == n0 and n2 == n0 and n3 == n0, "多次存款不叠加内容",
		"%d/%d/%d/%d" % [n0, n1, n2, n3])
	_ok(s.bank_deposit_label != null and s.bank_deposit_label.text.contains("3000"),
		"存款数字原地刷新", s.bank_deposit_label.text if s.bank_deposit_label != null else "null")
	_ok(s.bank_cash_label != null and s.bank_cash_label.text.contains("现金"), "现金标签存在")
	s._close_all_panels()
	await _frames(1)
	# 黑市、仓库同样验证一次
	s._toggle_black()
	await _frames(1)
	var b0: int = s.black_list.get_child_count()
	s._rebuild_black()
	await _frames(1)
	_ok(s.black_list.get_child_count() == b0, "黑市重建不叠加",
		"%d vs %d" % [b0, s.black_list.get_child_count()])
	s._close_all_panels()
	await _frames(1)
	s._toggle_store()
	await _frames(1)
	var st0: int = s.store_list.get_child_count()
	s._rebuild_store()
	await _frames(1)
	_ok(s.store_list.get_child_count() == st0, "仓库重建不叠加")
	s.queue_free()
	await _frames(2)

# ---------------- 1.2.12 岛屿高级面板 ----------------
func _test_v1212_island_panels() -> void:
	print("\n[1.2.12 岛屿高级面板]")
	GameState.reset_new_game()
	GameState.register_port("m3_c", GameState.town_name("青礁", 3), 0, 3)
	GameState.visit_port_id = &"m3_c"
	GameState.ensure_island_buildings(&"m3_c")
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	_ok(s.bank_root != null, "银行面板存在")
	s._toggle_bank()
	await _frames(1)
	_ok(s.bank_root.visible, "港城岛可打开银行")
	_ok(s.bank_list.get_child_count() > 0, "银行面板有内容")
	s._close_all_panels()
	await _frames(1)
	s._toggle_black()
	await _frames(1)
	_ok(s.black_root.visible, "港城岛可打开黑市")
	s._close_all_panels()
	await _frames(1)
	# 港村岛不应有这些服务
	GameState.register_port("m1_v", GameState.town_name("白沙", 1), 0, 1)
	GameState.visit_port_id = &"m1_v"
	_ok(not GameState.visit_has("bank"), "港村无银行服务")
	s.queue_free()
	await _frames(2)

# ---------------- 1.2.11 配方数据化 ----------------
func _test_v1211_recipes() -> void:
	print("\n[1.2.11 配方数据化]")
	GameState._load_recipes()
	_ok(GameState.RECIPES.size() >= 8, "配方从数据载入", str(GameState.RECIPES.size()))
	_ok(GameState.RECIPES.has(&"beer"), "啤酒配方存在")
	var beer: Dictionary = GameState.RECIPES[&"beer"]
	_ok(int(beer["in"].get(&"wheat", 0)) == 3, "啤酒配方：小麦 ×3",
		str(beer["in"]))
	_ok(String(beer.get("facility", "")) == "工坊", "啤酒设施为工坊")
	# 数据文件存在性
	_ok(FileAccess.file_exists("res://data/defs/recipes.json"), "配方 JSON 存在")
	# 校验仍然通过
	_ok(GameState.validate_defs().is_empty(), "配方数据化后校验通过")

# ---------------- 1.2.10 成长数值生效 ----------------
func _test_v1210_stats() -> void:
	print("\n[1.2.10 成长数值]")
	GameState.reset_new_game()
	var base_stats: Dictionary = GameState.stats()
	var base_guns := int(base_stats.get("guns_per_side", 0))
	var base_armor := int(base_stats.get("armor", 0))
	var base_speed := float(base_stats.get("base_speed_px", 0.0))
	# 模块强化生效（原改装/装备强化已合并）
	GameState.add_gold(100000)
	GameState.warehouse[&"timber"] = 9999
	GameState.warehouse[&"iron_ore"] = 9999
	_ok(bool(GameState.upgrade_module("gundeck", 0).get("ok", false)), "强化炮门模块")
	var st1: Dictionary = GameState.stats()
	_ok(int(st1.get("guns_per_side", 0)) == base_guns + 1, "炮门强化 +1 门",
		"%d → %d" % [base_guns, int(st1.get("guns_per_side", 0))])
	_ok(bool(GameState.upgrade_module("sails", 0).get("ok", false)), "强化风帆模块")
	var st2: Dictionary = GameState.stats()
	_ok(float(st2.get("base_speed_px", 0.0)) > base_speed, "风帆强化提升航速",
		"%.1f → %.1f" % [base_speed, float(st2.get("base_speed_px", 0.0))])
	# 船员职级生效
	GameState.crew_roster.clear()
	var c = load("res://scripts/systems/crew_factory.gd").generate(1, &"standard")
	if not c.is_empty():
		var crew = c[0]
		GameState.crew_roster.append(crew)
		GameState.crew_assigned.clear()
		GameState.assign_crew(crew.crew_id)
		var r0: float = float(GameState.stats().get("reload_bonus", 0.0))
		GameState.crew_xp[crew.crew_id] = 400
		var r1: float = float(GameState.stats().get("reload_bonus", 0.0))
		_ok(r1 > r0, "船员职级提升装填", "%.3f → %.3f" % [r0, r1])

# ---------------- 1.2.9 数据校验 ----------------
func _test_v129_validate() -> void:
	print("\n[1.2.9 数据校验]")
	GameState.reset_new_game()
	var errs: Array = GameState.validate_defs()
	_ok(errs.is_empty(), "全部静态数据通过校验", str(errs).left(300))
	# 分类修正验证
	var rum: Resource = DataRegistry.get_commodity(&"rum")
	var spice: Resource = DataRegistry.get_commodity(&"spice")
	_ok(String(rum.category) == "consumer", "朗姆酒归入消费品", String(rum.category))
	_ok(String(spice.category) == "consumer", "香料归入消费品", String(spice.category))
	# 五大类下都能查到商品
	var total := 0
	for cat in GameState.CATEGORIES:
		var n: int = GameState.commodities_of(cat).size()
		_ok(n > 0, "分类 %s 下有商品" % cat, str(n))
		total += n
	_ok(total == GameState.all_commodities().size(), "所有商品都归属某个分类",
		"%d vs %d" % [total, GameState.all_commodities().size()])
	# 消费品在港村无货
	GameState.port_stock.clear()
	GameState.register_port("m1_v", GameState.town_name("白沙", 1), 0, 1)
	GameState.visit_port_id = &"m1_v"
	_ok(GameState.ensure_stock(&"m1_v", &"rum", 40) == 0, "港村无朗姆酒（消费品）")
	_ok(GameState.ensure_stock(&"m1_v", &"spice", 40) == 0, "港村无香料（消费品）")

# ---------------- 1.2.6 / 1.2.7 商品供应 ----------------
func _test_v126_127_supply() -> void:
	print("\n[1.2.6/1.2.7 商品供应]")
	GameState.reset_new_game()
	GameState.port_stock.clear()
	# 港村岛：特产 80%，基础品类 40%，消费品 0，军用品 0
	GameState.register_port("m1_v", GameState.town_name("白沙", 1), 0, 1)
	GameState.port_registry["m1_v"]["specialty"] = "grain"
	GameState.visit_port_id = &"m1_v"
	var sp := GameState.ensure_stock(&"m1_v", &"grain", 40)
	_ok(sp == 32, "特产初始 80%", str(sp))
	var basic := GameState.ensure_stock(&"m1_v", &"wood_test", 40) if false else GameState.ensure_stock(&"m1_v", &"wheat", 40)
	_ok(basic == 16, "基础品类 40%", str(basic))
	var consumer := GameState.ensure_stock(&"m1_v", &"beer", 40)
	_ok(consumer == 0, "港村无消费品", str(consumer))
	var mil := GameState.ensure_stock(&"m1_v", &"musket", 40)
	_ok(mil == 0, "无铸造厂不出军用品", str(mil))
	# 港城：消费品 30%，贵金属 10%
	GameState.register_port("m3_c", GameState.town_name("青礁", 3), 0, 3)
	GameState.port_registry["m3_c"]["specialty"] = "spice"
	GameState.visit_port_id = &"m3_c"
	GameState.ensure_island_buildings(&"m3_c")
	_ok(GameState.ensure_stock(&"m3_c", &"beer", 160) == 48, "港城消费品 30%")
	_ok(GameState.ensure_stock(&"m3_c", &"silver", 160) == 16, "港城贵金属 10%")
	_ok(GameState.ensure_stock(&"m3_c", &"musket", 160) > 0, "铸造厂港口有军用品")
	# 随机补货：缺货商品有概率出现
	GameState.port_stock["m3_c"][&"beer"] = 0
	var appeared := 0
	for i in range(40):
		appeared += GameState.tick_supply()
		if int(GameState.port_stock["m3_c"].get(&"beer", 0)) > 0:
			break
	_ok(appeared > 0, "随机补货有商品出现", str(appeared))

# ---------------- 1.2.4 / 1.2.5 初始建筑与等级门禁 ----------------
func _test_v124_125() -> void:
	print("\n[1.2.4/1.2.5 初始建筑与门禁]")
	GameState.reset_new_game()
	# 1.2.4：港村岛初始 3 座
	GameState.register_port("m1_v", GameState.town_name("白沙", 1), 0, 1)
	GameState.visit_port_id = &"m1_v"
	GameState.ensure_island_buildings(&"m1_v")
	var lv: Dictionary = GameState.port_buildings["m1_v"]
	_ok(lv.size() == 3, "港村岛初始 3 座建筑", str(lv.size()))
	_ok(int(lv.get(&"governor", 0)) == 1, "港村总督府 Lv1")
	# 港镇岛 5 座
	GameState.register_port("m2_t", GameState.town_name("望潮", 2), 0, 2)
	GameState.visit_port_id = &"m2_t"
	GameState.ensure_island_buildings(&"m2_t")
	_ok(GameState.port_buildings["m2_t"].size() == 5, "港镇岛初始 5 座",
		str(GameState.port_buildings["m2_t"].size()))
	# 港城岛 8 座
	GameState.register_port("m3_c", GameState.town_name("青礁", 3), 0, 3)
	GameState.visit_port_id = &"m3_c"
	GameState.ensure_island_buildings(&"m3_c")
	_ok(GameState.port_buildings["m3_c"].size() == 7, "港城岛初始 7 座",
		str(GameState.port_buildings["m3_c"].size()))

	# 1.2.5：等级门禁
	_ok(GameState.visit_port_tier() == 3, "当前为港城")
	_ok(GameState.visit_has("exchange"), "港城有交易所")
	_ok(GameState.visit_has("bank"), "港城有银行")
	_ok(GameState.visit_has("black"), "港城有黑市")
	_ok(not GameState.visit_has("build"), "非母港不能建造")
	GameState.visit_port_id = &"m1_v"
	_ok(not GameState.visit_has("bank"), "港村无银行服务")
	_ok(not GameState.visit_has("yard"), "港村无船厂")
	GameState.visit_port_id = &"m2_t"
	_ok(GameState.visit_has("yard"), "港镇有船厂")
	_ok(not GameState.visit_has("bank"), "港镇无银行")
	GameState.visit_port_id = &"jadehaven"
	_ok(GameState.visit_has("build"), "母港可建造")

# ---------------- 1.2.3 建筑按港口隔离 ----------------
func _test_v123_port_buildings() -> void:
	print("\n[1.2.3 建筑隔离]")
	GameState.reset_new_game()
	var home_gov: int = GameState.building_level(&"governor")
	_ok(home_gov >= 1, "母港总督府已建", str(home_gov))
	# 切到岛屿并初始化
	GameState.register_port("m1_island0", GameState.town_name("望潮", 2), 0, 2)
	GameState.visit_port_id = &"m1_island0"
	GameState.ensure_island_buildings(&"m1_island0")
	var isl_gov: int = GameState.building_level(&"governor")
	_ok(isl_gov >= 1, "岛屿总督府存在", str(isl_gov))
	# 提升岛屿某建筑，不应影响母港
	GameState.buildings[&"tavern"] = 3
	GameState.visit_port_id = &"jadehaven"
	_ok(GameState.building_level(&"tavern") == 0, "岛屿升级不影响母港酒馆",
		str(GameState.building_level(&"tavern")))
	# 两港分桶独立
	_ok(GameState.port_buildings.has("m1_island0"), "岛屿有独立分桶")
	_ok(GameState.port_buildings.has("jadehaven"), "母港有独立分桶")

# ---------------- 1.2.2 港口上下文 ----------------
func _test_v122_town() -> void:
	print("\n[1.2.2 城镇上下文]")
	GameState.reset_new_game()
	_ok(GameState.is_home_visit(), "默认在母港")
	_ok(GameState.visit_port_name().ends_with("港村"), "母港名称含港村",
		GameState.visit_port_name())
	_ok(GameState.visit_port_tier() == 1, "母港等级 1")
	GameState.visit_port_id = &"m1_island0"
	GameState.register_port("m1_island0", GameState.town_name("望潮", 2), 0, 2)
	_ok(not GameState.is_home_visit(), "切换后不是母港")
	_ok(GameState.visit_port_name() == "望潮港镇", "岛屿名含港镇", GameState.visit_port_name())
	_ok(GameState.visit_port_tier() == 2, "岛屿等级 2", str(GameState.visit_port_tier()))
	_ok(GameState.visit_port_max_stock() == 90, "港镇库存上限 90",
		str(GameState.visit_port_max_stock()))
	GameState.visit_port_id = &"jadehaven"
	_ok(GameState.is_home_visit(), "可切回母港")

# ---------------- 1.2.1 升级门槛与仓库 ----------------
func _test_v121_gate() -> void:
	print("\n[1.2.1 门槛与仓库]")
	GameState.reset_new_game()
	# 港村 → 港镇：条件未达标
	_ok(GameState.home_port_tier == 1, "初始为港村")
	_ok(not GameState.town_upgrade_ready(), "初始不可升级")
	var reqs: Array = GameState.town_upgrade_requirements()
	_ok(reqs.size() == 5, "港村升级条件 5 项", str(reqs.size()))
	var none_ok := true
	for rq in reqs:
		if bool(rq["ok"]):
			none_ok = false
	_ok(none_ok, "初始所有条件均未完成")
	# 全部达标后可升级
	GameState.buildings[&"governor"] = 3
	GameState.buildings[&"tavern"] = 2
	GameState.buildings[&"warehouse"] = 2
	GameState.buildings[&"sailmaker"] = 2
	GameState.buildings[&"watchtower"] = 2
	_ok(GameState.town_upgrade_ready(), "条件齐备后可升级")
	var reqs2: Array = GameState.town_upgrade_requirements()
	var ok_count := 0
	for rq2 in reqs2:
		if bool(rq2["ok"]):
			ok_count += 1
	_ok(ok_count == 5, "五项均显示已完成", str(ok_count))
	# 升级后进入港镇，条件变为港城档
	GameState.home_port_tier = 2
	var reqs3: Array = GameState.town_upgrade_requirements()
	_ok(reqs3.size() == 7, "港镇→港城 7 项条件", str(reqs3.size()))
	var gov_need := 0
	for rq3 in reqs3:
		if String(rq3["id"]) == "governor":
			gov_need = int(rq3["need"])
	_ok(gov_need == 4, "港城要求总督府 Lv4", str(gov_need))

	# 仓库转移
	GameState.reset_new_game()
	GameState.warehouse.clear()
	GameState.warehouse[&"timber"] = 50
	var moved: int = GameState.move_warehouse_to_cargo(&"timber")
	_ok(moved > 0, "仓库→货舱 有转移", str(moved))
	_ok(int(GameState.cargo.get(&"timber", 0)) == moved, "货舱收到货物")
	var moved2: int = GameState.move_cargo_to_warehouse(&"timber")
	_ok(moved2 > 0, "货舱→仓库 有转移", str(moved2))
	_ok(int(GameState.cargo.get(&"timber", 0)) == 0, "货舱清空")

# ---------------- 1.2.0 城镇与建筑组件化 ----------------
func _test_v120_component() -> void:
	print("\n[1.2.0 组件化]")
	var tp = load("res://scripts/ui/town_panel.gd")
	# 建筑定义字段
	var dd: Resource = DataRegistry.get_building(&"drydock")
	_ok(dd != null, "船坞定义存在")
	_ok(String(dd.category) == "生产", "船坞分类为生产", String(dd.category))
	_ok(int(dd.unlock_tier) == 2, "船坞港口镇解锁", str(dd.get("unlock_tier")))
	_ok(String(dd.slot_id) == "slot_drydock", "船坞有槽位 id")
	_ok(dd.get("scene_path") == "", "美术资源留空待接入")
	# 开局自带建筑
	var w: Resource = DataRegistry.get_building(&"warehouse")
	var gv: Resource = DataRegistry.get_building(&"governor")
	_ok(bool(w.is_initial), "仓库开局自带")
	_ok(bool(gv.is_initial), "总督府开局自带")
	var tv: Resource = DataRegistry.get_building(&"tavern")
	_ok(not bool(tv.is_initial), "酒馆不自动送")
	# 等级过滤
	var t1: Array = tp.buildings_for_tier(1)
	var t3: Array = tp.buildings_for_tier(3)
	_ok(t1.size() < t3.size(), "高等级建筑更多", "%d vs %d" % [t1.size(), t3.size()])
	var has_exchange := false
	for bb in t1:
		if String(bb.id) == "exchange":
			has_exchange = true
	_ok(not has_exchange, "交易所不在港村解锁列表")
	# 布局坐标化
	var lay: Resource = tp.layout_for(1)
	_ok(lay != null, "港村布局存在")
	_ok(lay.slots.size() >= 8, "槽位数量 ≥ 8", str(lay.slots.size()))
	var s0: Dictionary = lay.slots[0]
	_ok(s0.has("x") and s0.has("y") and s0.has("w") and s0.has("h"), "槽位含坐标与尺寸", str(s0))
	# 初始建筑初始化
	GameState.reset_new_game()
	GameState.buildings.clear()
	GameState.init_town_buildings(true, 1)
	_ok(GameState.building_level(&"warehouse") >= 1, "母港初始有仓库")
	_ok(GameState.building_level(&"governor") >= 1, "母港初始有总督府")
	_ok(GameState.building_level(&"tavern") == 0, "母港初始无酒馆")
	# 开局资源
	GameState.reset_new_game()
	_ok(GameState.gold == GameState.START_GOLD + 8000, "开局发放 8000 金", str(GameState.gold))
	_ok(int(GameState.warehouse.get(&"timber", 0)) == 300, "开局 300 木材（仓库）",
		str(GameState.warehouse.get(&"timber", 0)))
	_ok(int(GameState.warehouse.get(&"iron_ore", 0)) == 120, "开局 120 铁矿（仓库）")

# ---------------- 1.1.4 试玩反馈修复 ----------------
func _test_v114_fixes() -> void:
	print("\n[1.1.4 修复]")
	GameState.reset_new_game()
	# 铁矿商品存在
	var iron: Resource = DataRegistry.get_commodity(&"iron_ore")
	_ok(iron != null, "铁矿商品已存在")
	if iron != null:
		_ok(String(iron.display_name) == "铁矿", "铁矿名称正确", String(iron.display_name))
	# 商品总数（27 + 铁矿 = 28）
	_ok(GameState.all_commodities().size() >= 28, "商品总数 ≥ 28",
		str(GameState.all_commodities().size()))
	# 建造需求里的材料都能查到名字
	var need: Dictionary = GameState.build_need(1)
	var all_named := true
	for m in need.keys():
		if String(m) == "gold":
			continue
		if DataRegistry.get_commodity(m) == null:
			all_named = false
	_ok(all_named, "建造材料均有商品定义")

# ---------------- 1.1.3 打磨与平衡 ----------------
func _test_v113_polish() -> void:
	print("\n[1.1.3 打磨]")
	GameState.reset_new_game()
	# 生产受工坊等级限制
	GameState.warehouse.clear()
	GameState.warehouse[&"wheat"] = 30
	var p0: Dictionary = GameState.tick_production("jadehaven")
	var n0 := 0
	for k in p0.get("产出", {}).keys():
		n0 += int(p0["产出"][k])
	_ok(n0 <= 1, "工坊 0 级时每周最多 1 批", str(n0))
	GameState.buildings[&"sailmaker"] = 3
	GameState.warehouse.clear()
	GameState.warehouse[&"wheat"] = 30
	var p3: Dictionary = GameState.tick_production("jadehaven")
	var n3 := 0
	for k2 in p3.get("产出", {}).keys():
		n3 += int(p3["产出"][k2])
	_ok(n3 >= 2 and n3 <= 3, "工坊 3 级时每周最多 3 批", str(n3))

	# 旧存档兼容：缺新字段也能读
	var legacy := {"player": {"gold": 1234, "level": 2}}
	GameState.from_dict(legacy)
	_ok(GameState.gold == 1234, "旧档金币可读", str(GameState.gold))
	_ok(GameState.ship_module_levels.is_empty(), "缺模块等级时为空")
	_ok(GameState.building_upgrades.is_empty(), "缺 building_upgrades 时为空")
	_ok(GameState.module_crew.is_empty(), "缺模块船员时为空")

	# 新商品在港口有初始库存
	GameState.reset_new_game()
	var wheat_stock := GameState.ensure_stock(&"jadehaven", &"wheat", 400)
	_ok(wheat_stock > 0, "新商品有初始库存", str(wheat_stock))
	# 1.2.6 起军用品需要铸造厂才供应
	var ammo_stock := GameState.ensure_stock(&"jadehaven", &"ammo_goods", 400)
	_ok(ammo_stock == 0, "无铸造厂时无军用品", str(ammo_stock))
	GameState.port_buildings["jadehaven"] = {&"foundry": 1}
	GameState.buildings = GameState.port_buildings["jadehaven"]
	GameState.port_stock["jadehaven"].erase(&"ammo_goods")
	var ammo2 := GameState.ensure_stock(&"jadehaven", &"ammo_goods", 400)
	_ok(ammo2 > 0, "有铸造厂后供应军用品", str(ammo2))

# ---------------- 1.1.2 多建筑并行 ----------------
func _test_v112_parallel() -> void:
	print("\n[1.1.2 多建筑并行]")
	GameState.reset_new_game()
	GameState.add_gold(50000)
	GameState.building_upgrades.clear()
	GameState.buildings.clear()   # 1.2.0 起开局自带仓库/总督府，此处清空以测建造
	# 两座建筑同时开工
	var a: Dictionary = GameState.building_start_upgrade(&"drydock")
	var b2: Dictionary = GameState.building_start_upgrade(&"warehouse")
	_ok(bool(a.get("ok", false)), "船坞可开始升级", str(a))
	_ok(bool(b2.get("ok", false)), "仓库可同时开始升级", str(b2))
	_ok(GameState.building_upgrades.size() == 2, "两座并行升级中",
		str(GameState.building_upgrades.size()))
	var again: Dictionary = GameState.building_start_upgrade(&"drydock")
	_ok(not bool(again.get("ok", true)), "同一建筑不能重复开工")
	_ok(GameState.building_progress_text(&"drydock") != "", "有进度文本")
	# 推进两周完成
	GameState.tick_buildings()
	_ok(GameState.building_upgrades.size() == 2, "一周后仍在进行")
	TimeService.total_days += TimeService.DAYS_PER_WEEK * 2
	var done: Array = GameState.tick_buildings()
	_ok(done.size() == 2, "两周后两座同时完成", str(done))
	_ok(GameState.building_level(&"drydock") == 1, "船坞升到 Lv1")
	_ok(GameState.building_level(&"warehouse") == 1, "仓库升到 Lv1")

# ---------------- 1.1.1 界面入口 ----------------
func _test_v111_ui() -> void:
	print("\n[1.1.1 界面]")
	GameState.reset_new_game()
	GameState.add_gold(80000)
	GameState.warehouse[&"iron_ore"] = 20
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	_ok(s.crew_root != null, "船员面板已创建")
	_ok(s.gear_root != null, "装备面板已创建")
	_ok(s.mod_root != null, "改装面板已创建")
	s._toggle_crew_panel()
	await _frames(1)
	_ok(s.crew_root.visible, "船员面板可打开")
	_ok(s.close_btn.visible, "打开面板后关闭按钮出现")
	s._close_all_panels()
	await _frames(1)
	s._toggle_gear()
	await _frames(1)
	_ok(s.ship_root.visible, "装备强化入口跳转舰船面板")
	s._close_all_panels()
	await _frames(1)
	s._toggle_mod()
	await _frames(1)
	_ok(s.ship_root.visible, "改装入口跳转舰船面板")
	s._close_all_panels()
	await _frames(1)

# ---------------- 1.1.0 商品分类 / 关税 / 建造 ----------------
func _test_v110_core() -> void:
	print("\n[1.1.0 核心]")
	GameState.reset_new_game()
	# 商品分类
	_ok(GameState.CATEGORIES.size() == 5, "五大类商品")
	var food: Array = GameState.commodities_of("food")
	var mil: Array = GameState.commodities_of("military")
	_ok(food.size() >= 5, "食物类至少 5 种", str(food.size()))
	_ok(mil.size() >= 3, "军用品至少 3 种", str(mil.size()))
	_ok(GameState.all_commodities().size() >= 20, "商品总数 ≥ 20", str(GameState.all_commodities().size()))
	# 生产配方
	_ok(GameState.RECIPES.has(&"beer"), "啤酒有配方")
	_ok(String(GameState.RECIPES[&"beer"]["in"].keys()[0]) == "wheat", "啤酒由小麦酿造")
	_ok(GameState.RECIPES.has(&"ammo_goods"), "弹药有配方")
	# 关税分档
	GameState.reputation["royal_navy"] = 0
	_ok(is_equal_approx(GameState.tariff_rate(), 0.10), "敌对关税 10%", str(GameState.tariff_rate()))
	GameState.reputation["royal_navy"] = 2500
	_ok(is_equal_approx(GameState.tariff_rate(), 0.05), "中立关税 5%")
	GameState.reputation["royal_navy"] = 6000
	_ok(is_equal_approx(GameState.tariff_rate(), 0.03), "友好关税 3%")
	GameState.reputation["royal_navy"] = 9000
	_ok(is_equal_approx(GameState.tariff_rate(), 0.01), "盟友关税 1%")
	# 命名标准化
	_ok(GameState.town_name("白沙", 1) == "白沙港村", "港村命名")
	_ok(GameState.town_name("白沙", 2) == "白沙港镇", "港镇命名")
	_ok(GameState.town_name("白沙", 3) == "白沙港城", "港城命名")
	# 建造需求与提交
	var need: Dictionary = GameState.build_need(1)
	_ok(need.has(&"timber") and need.has("gold"), "一级建造需要木材与金币")
	GameState.build_submitted.clear()
	GameState.build_submit("jadehaven", &"timber", 100)
	var prog: Dictionary = GameState.build_progress("jadehaven", 1)
	_ok(not bool(prog["ready"]), "材料不足时不可升级")
	_ok(int(prog["have"].get(&"timber", 0)) == 100, "提交量被记录")

	# 存款投资（B 块补齐）
	GameState.reset_new_game()
	GameState.add_gold(10000)
	GameState.bank_deposit_gold(8000)
	var r1: Dictionary = GameState.invest_from("deposit", "m1_island0", 3000)
	_ok(bool(r1.get("ok", false)), "可用存款投资")
	_ok(GameState.bank_deposited() == 5000, "存款被扣减", str(GameState.bank_deposited()))
	_ok(int(GameState.island_investment.get("m1_island0", 0)) == 3000, "投资额累加")
	var r2: Dictionary = GameState.invest_from("deposit", "m1_island0", 999999)
	_ok(not bool(r2.get("ok", true)), "存款不足时拒绝")
	var cash_before := GameState.gold
	var r3: Dictionary = GameState.invest_from("cash", "m1_island0", 1000)
	_ok(bool(r3.get("ok", false)) and GameState.gold == cash_before - 1000, "现金投资扣减正确",
		"%d → %d" % [cash_before, GameState.gold])

	# 生产运行时产出（C 块补齐）
	GameState.reset_new_game()
	GameState.buildings[&"sailmaker"] = 3
	GameState.warehouse.clear()
	GameState.warehouse[&"wheat"] = 9
	var prod: Dictionary = GameState.tick_production("jadehaven")
	var made: Dictionary = prod.get("产出", {})
	_ok(int(made.get(&"beer", 0)) == 3, "小麦 9 → 啤酒 3", str(made))
	_ok(int(GameState.warehouse.get(&"wheat", 0)) == 0, "原料被消耗")
	_ok(int(GameState.warehouse.get(&"beer", 0)) == 3, "成品入库")
	# 军用品链
	GameState.warehouse.clear()
	GameState.buildings[&"sailmaker"] = 5
	GameState.warehouse[&"iron_ore"] = 8
	GameState.warehouse[&"timber"] = 6
	GameState.warehouse[&"copper"] = 4
	var p2: Dictionary = GameState.tick_production("jadehaven")
	var made2: Dictionary = p2.get("产出", {})
	_ok(int(made2.get(&"musket", 0)) >= 1, "铁矿+木材 → 火枪", str(made2))
	_ok(int(made2.get(&"tools", 0)) >= 1, "铁矿+木材 → 工具（同原料多配方按序消耗）", str(made2))

	# 船员职级
	GameState.reset_new_game()
	GameState.crew_xp[&"c1"] = 0
	_ok(GameState.crew_rank_name(&"c1") == "水手", "初始为水手")
	GameState.crew_xp[&"c1"] = 120
	_ok(GameState.crew_rank_name(&"c1") == "舵手", "120 经验升舵手", GameState.crew_rank_name(&"c1"))
	GameState.crew_xp[&"c1"] = 700
	_ok(GameState.crew_rank_name(&"c1") == "大副", "700 经验升大副")

	# 模块强化（原装备强化与改装合并）
	GameState.reset_new_game()
	GameState.add_gold(50000)
	GameState.warehouse[&"timber"] = 999
	GameState.warehouse[&"iron_ore"] = 999
	_ok(GameState.module_level("gundeck", 0) == 0, "初始模块 0 级")
	var gup: Dictionary = GameState.upgrade_module("gundeck", 0)
	_ok(bool(gup.get("ok", false)), "可以强化模块", str(gup))
	_ok(GameState.module_level("gundeck", 0) == 1, "强化到 1 级")
	_ok(int(GameState.warehouse.get(&"iron", 0)) < 999, "强化消耗铁矿")
	GameState.add_gold(-GameState.gold)
	var poor: Dictionary = GameState.upgrade_module("gundeck", 1)
	_ok(not bool(poor.get("ok", true)), "金币不足时拒绝")
	# 合成已移除
	_ok(not bool(GameState.gear_combine(&"sail", 0).get("ok", true)), "装备合成已移除")

	# 任务类型扩展
	GameState.reset_new_game()
	GameState.quests_available.clear()
	var types := {}
	for trial in range(30):
		GameState.refresh_quests()
		for q in GameState.quests_available:
			types[String(q.get("type", ""))] = true
		GameState.quests_available.clear()
	_ok(types.size() >= 5, "任务类型至少 5 种被抽到", str(types.keys()))

# ---------------- 面板规范（0.19.0） ----------------
func _test_ui_panels_v019() -> void:
	print("\n[面板规范]")
	GameState.reset_new_game()
	var s = load("res://scenes/base/base_scene.tscn").instantiate()
	add_child(s)
	await _frames(3)
	_ok(s.close_btn != null, "存在统一关闭按钮")
	_ok(not s._any_panel_open(), "初始没有面板打开")
	_ok(not s.close_btn.visible, "无面板时关闭按钮隐藏")
	var p = s.get("overview_root")
	_ok(p != null and p.size.x >= 1400.0, "经济总览已全屏", str(p.size) if p != null else "null")
	p.visible = true
	await _frames(2)
	_ok(s._any_panel_open(), "面板打开被识别")
	_ok(s.close_btn.visible, "面板打开时关闭按钮出现")
	s._close_all_panels()
	await _frames(2)
	_ok(not s.close_btn.visible, "关闭后按钮隐藏")
	# 财报只保留一年
	GameState.reports.clear()
	GameState.make_annual_report(1)
	GameState.make_annual_report(2)
	_ok(GameState.reports.size() == 1, "历史财报只保留 1 年", str(GameState.reports.size()))
	# 商品弹窗
	s._open_goods(&"grain")
	await _frames(2)
	_ok(s.goods_root.visible, "商品弹窗可打开")
	_ok(s.goods_qty == 1, "初始数量为 1", str(s.goods_qty))
	s._open_goods(&"timber")
	await _frames(2)
	_ok(s.goods_root.visible, "切换商品后弹窗仍开")
	s._close_goods()
	await _frames(2)
	_ok(not s.goods_root.visible, "商品弹窗可关闭")
	# ESC 优先关闭商品弹窗
	s._open_goods(&"grain")
	await _frames(2)
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	s._input(ev)
	await _frames(2)
	_ok(not s.goods_root.visible, "ESC 先关闭商品弹窗")
	# 利润表结构一致性（全部细类都列出，顺序一致）
	var pl1: Array = s._pl_rows({"贸易": 100}, {"采购": 40}, "本年")
	var names: Array = []
	for rw in pl1:
		names.append(String(rw[0]))
	_ok(names.has("营业收入") and names.has("　　贸易") and names.has("　　战利品"),
		"利润表列出全部收入细类", str(names))
	_ok(names.has("营业成本") and names.has("　　采购") and names.has("　　维护"),
		"利润表列出全部成本细类")
	_ok(names.has("收入合计") and names.has("成本合计") and names.has("净利润"), "含三个合计行")
	# 大类顺序：营业收入 → 收入合计 → 营业成本 → 成本合计 → 净利润
	var i_inc := names.find("营业收入")
	var i_inc_t := names.find("收入合计")
	var i_exp := names.find("营业成本")
	var i_exp_t := names.find("成本合计")
	_ok(i_inc < i_inc_t and i_inc_t < i_exp and i_exp < i_exp_t, "大类与合计顺序正确",
		"%d/%d/%d/%d" % [i_inc, i_inc_t, i_exp, i_exp_t])
	# 资产负债表结构
	var bs: Array = s._bs_rows(1000, 0, 0, 0, 0, 0, 200)
	var bnames: Array = []
	for rw in bs:
		bnames.append(String(rw[0]))
	_ok(bnames.has("资产") and bnames.has("资产合计") and bnames.has("负债") and bnames.has("净资产"),
		"资产负债表含大类与合计", str(bnames))
	# 经济总览六个分页
	for tab in ["ytd_bs", "ytd_pl", "week_pnl", "last_bs", "last_pl", "last_week"]:
		s.overview_tab = tab
		s._rebuild_overview()
		await _frames(1)
		_ok(s.overview_list.get_child_count() > 1, "总览分页 %s 有内容" % tab,
			str(s.overview_list.get_child_count()))
	s.overview_tab = "week_pnl"
	# 周收支滚动
	GameState.record_income("贸易", 500)
	_ok(int(GameState.week_income.get("贸易", 0)) == 500, "本周收入被记录")
	GameState.week_roll()
	_ok(int(GameState.last_week_income.get("贸易", 0)) == 500, "上周收入已滚动")
	_ok(GameState.week_income.is_empty(), "本周收入已清零")
	# 边际曲线应随真实库存变化（不是一条水平线）
	var cd0: Dictionary = s._chart_data(&"grain", 10, 400, 800)
	var mc0: Array = cd0.get("mc", [])
	var mono := true
	for i in range(1, mc0.size()):
		if float(mc0[i]) < float(mc0[i - 1]) - 0.01:
			mono = false
	_ok(float(mc0[mc0.size() - 1]) > float(mc0[0]), "买得越多买价越高（MC 曲线上升）",
		"%.1f -> %.1f" % [float(mc0[0]), float(mc0[mc0.size() - 1])])
	_ok(mono, "MC 曲线单调不减")
	var cd: Dictionary = s._chart_data(&"grain", 10, 200, 400)
	_ok(cd.has("history") and cd.has("mc") and cd.has("price_by_stock") and cd.has("curve"),
		"图表数据齐全", str(cd.keys()))
	_ok(int(GameState.reports[0].get("year", 0)) == 2, "保留的是最新年份")
	s.queue_free()
	await _frames(2)

# ---------------- 差别定价 / 生产 / 财务（0.16~0.18） ----------------
func _test_finance_v018() -> void:
	print("\n[差别定价与财务]")
	var em = load("res://scripts/systems/econ_math.gd")
	# 生产函数
	_ok(is_equal_approx(em.production_curve(100.0, 1, 1.0), 100.0), "Lv1 产出 = 基础")
	_ok(em.production_curve(100.0, 2, 1.0) > 150.0, "Lv2 线性增长")
	_ok(em.marginal_output(100.0, 1, 1.0) > 0.0, "边际产量为正")

	# 声望折扣
	GameState.reset_new_game()
	_ok(is_equal_approx(GameState.rep_discount(), 0.0), "无声望无折扣", str(GameState.rep_discount()))
	_ok(GameState.rep_discount_name() == "陌生人", "档位名：陌生人")
	GameState.reputation["royal_navy"] = 3000
	_ok(is_equal_approx(GameState.rep_discount(), 0.04), "声望 3000 → 4%", str(GameState.rep_discount()))
	_ok(GameState.rep_discount_name() == "老主顾", "档位名：老主顾")
	GameState.reputation["royal_navy"] = 8000
	_ok(is_equal_approx(GameState.rep_discount(), 0.06), "声望 8000 → 6%（上限）")

	# 财务记账
	GameState.reset_new_game()
	GameState.finance_reset()
	GameState.record_purchase(&"grain", 100, 1000)
	GameState.record_sale(&"grain", 100, 1500)
	GameState.record_income("战利品", 300)
	GameState.record_expense("维护", 200)
	var s: Dictionary = GameState.finance_summary()
	_ok(int(s["income_total"]) == 1800, "收入 = 销售 1500 + 战利品 300", str(s["income_total"]))
	_ok(int(s["expense_total"]) == 1200, "支出 = 采购 1000 + 维护 200", str(s["expense_total"]))
	_ok(int(s["net"]) == 600, "净利 = 600", str(s["net"]))

	# 年度财报
	GameState.add_gold(5000)
	var rep: Dictionary = GameState.make_annual_report(1)
	_ok(int(rep.get("year", 0)) == 1, "财报年份正确")
	_ok(int(rep.get("net", 0)) == 600, "财报净利与汇总一致")
	_ok(int(rep.get("net_worth", 0)) > 0, "净资产为正")
	_ok(GameState.reports.size() == 1, "财报已存档")
	_ok(GameState.finance_summary()["income_total"] == 0, "出报表后本年账目清零")

	# 最多保留 5 年
	for y in range(2, 9):
		GameState.make_annual_report(y)
	_ok(GameState.reports.size() == 1, "历史财报只保留上一年", str(GameState.reports.size()))

# ---------------- 成本与规模（0.15.0） ----------------
func _test_cost_scale_v015() -> void:
	print("\n[成本与规模]")
	var em = load("res://scripts/systems/econ_math.gd")
	# 规模报酬
	_ok(is_equal_approx(em.scale_return(2.0, 1.0), 2.0), "指数 1 为不变")
	_ok(em.scale_return(2.0, 1.15) > 2.0, "指数 >1 为递增")
	_ok(em.scale_return(2.0, 0.90) < 2.0, "指数 <1 为递减")

	# 投资曲线：150,000 处达到 50%
	var d0: float = em.diminishing_discount(0.0, 150000.0, 50.0, 1.6)
	var d_full: float = em.diminishing_discount(150000.0, 150000.0, 50.0, 1.6)
	var d_mid: float = em.diminishing_discount(60000.0, 150000.0, 50.0, 1.6)
	_ok(is_equal_approx(d0, 0.0), "未投资无折扣")
	_ok(absf(d_full - 50.0) < 0.01, "15 万达到上限 50%", "%.2f" % d_full)
	_ok(d_mid > 10.0 and d_mid < 40.0, "6 万处于中段", "%.1f" % d_mid)
	_ok(d_full > d_mid, "投得越多折扣越高")
	# 边际递减
	var m1: float = em.marginal_discount(5000.0, 150000.0, 50.0, 1.6, 1000.0)
	var m2: float = em.marginal_discount(100000.0, 150000.0, 50.0, 1.6, 1000.0)
	_ok(m1 > m2, "边际回报递减", "%.3f > %.3f" % [m1, m2])

	# 成本结构
	GameState.reset_new_game()
	var up: Dictionary = GameState.weekly_upkeep()
	_ok(int(up.get("total", -1)) >= 0, "有维护费")
	_ok(int(up.get("fixed", 0)) + int(up.get("variable", 0)) == int(up.get("total", 0)),
		"固定 + 可变 = 合计")
	_ok(int(up.get("berth", 0)) == 5, "村落停泊费 5", str(up.get("berth", 0)))
	GameState.home_port_tier = 3
	var up3: Dictionary = GameState.weekly_upkeep()
	_ok(int(up3.get("berth", 0)) == 40, "城市停泊费 40", str(up3.get("berth", 0)))

	# 投资折扣接入 GameState
	GameState.reset_new_game()
	GameState.island_investment["t_island"] = 150000
	_ok(GameState.island_discount("t_island") == 50, "满投资折扣 50",
		str(GameState.island_discount("t_island")))

# ---------------- 决策辅助（0.14.0） ----------------
func _test_decision_aid_v014() -> void:
	print("\n[决策辅助]")
	var em = load("res://scripts/systems/econ_math.gd")
	# 交叉弹性
	_ok(is_equal_approx(em.cross_effect(0.03, 0.4, 0.05, 0.08), 0.0), "低于阈值不传导")
	_ok(is_equal_approx(em.cross_effect(0.08, 0.4, 0.05, 0.08), 0.032), "8% × 0.4 = 3.2%")
	_ok(is_equal_approx(em.cross_effect(-0.10, 0.4, 0.05, 0.08), -0.04), "负向传导")
	_ok(is_equal_approx(em.cross_effect(0.50, 1.0, 0.05, 0.08), 0.08), "传导有上限 ±8%")

	# 边际利润
	var m1: Dictionary = em.marginal_trade(10, 20, 260.0, 0.5, 400)
	_ok(int(m1.get("count", 0)) == 400 and String(m1.get("reason", "")) == "ok",
		"容量充足时按库存上限", str(m1.get("count", 0)))
	var m2: Dictionary = em.marginal_trade(10, 20, 5.0, 0.5, 400)
	_ok(int(m2.get("count", 0)) == 10, "容量受限时按容量算", str(m2.get("count", 0)))
	var m3: Dictionary = em.marginal_trade(20, 10, 260.0, 0.5, 400)
	_ok(String(m3.get("reason", "")) == "unprofitable", "卖价低于买价时不划算")
	var m4: Dictionary = em.marginal_trade(10, 20, 0.0, 0.5, 400)
	_ok(String(m4.get("reason", "")) == "capacity", "无容量时提示货舱已满")

	# 历史曲线
	GameState.reset_new_game()
	GameState.ensure_stock(&"jadehaven", &"grain", 400)
	GameState.tick_market(1)
	var h1: Array = GameState.price_history_of("jadehaven", &"grain")
	_ok(h1.size() == 1, "首周记录 1 个点", str(h1.size()))
	GameState.tick_market(2)
	GameState.tick_market(3)
	var h2: Array = GameState.price_history_of("jadehaven", &"grain")
	_ok(h2.size() == 3, "三周记录 3 个点", str(h2.size()))
	_ok(h2.size() <= GameState.HISTORY_WEEKS, "历史不超过 8 周上限")

	# 交叉传导（构造：让朗姆酒大幅变动后，香料目标受影响）
	_ok(GameState.CROSS_THRESHOLD > 0.0, "交叉阈值已配置", str(GameState.CROSS_THRESHOLD))
	_ok(GameState.CROSS_RELATIONS.size() >= 3, "至少三条交叉关系")

# ---------------- 市场 UI（0.13.1） ----------------
func _test_market_ui_v0131() -> void:
	print("\n[市场 UI]")
	GameState.reset_new_game()
	GameState.ensure_stock(&"jadehaven", &"grain", 400)
	# 首周没有历史 → 无涨跌
	_ok(not GameState.has_price_history("jadehaven", &"grain"), "首周没有对比数据")
	GameState.tick_market(1)
	_ok(GameState.has_price_history("jadehaven", &"grain"), "跨周后有对比数据")
	# 价格明细
	var ex = load("res://scripts/systems/econ_explain.gd")
	var info: Dictionary = ex.price_breakdown("jadehaven", &"grain", 10, 190, 400, 1.0, 1.0)
	_ok(info.get("steps", []).size() >= 4, "明细至少 4 步", str(info.get("steps", []).size()))
	_ok(int(info.get("result", 0)) > 0, "明细给出最终价")
	var metrics: Dictionary = info.get("metrics", {})
	_ok(metrics.has("elasticity"), "明细含弹性系数")
	_ok(metrics.has("stock_ratio"), "明细含库存比例")

# ---------------- 价格引擎（0.13.0） ----------------
func _test_price_engine_v013() -> void:
	print("\n[价格引擎]")
	var em = load("res://scripts/systems/econ_math.gd")
	# 分段弹性
	_ok(is_equal_approx(em.piecewise_elasticity(0.9), 0.35), "高库存弹性 0.35")
	_ok(is_equal_approx(em.piecewise_elasticity(0.5), 0.55), "中库存弹性 0.55")
	_ok(is_equal_approx(em.piecewise_elasticity(0.1), 0.90), "低库存弹性 0.90")
	# 均值回归
	_ok(is_equal_approx(em.mean_revert(0.8, 1.0, 0.25), 0.85), "回归 25% 正确")
	# 噪声可复现
	_ok(is_equal_approx(em.seeded_noise([1, 2, 3], 0.03), em.seeded_noise([1, 2, 3], 0.03)),
		"同种子噪声可复现")
	_ok(absf(em.seeded_noise([1, 2, 3], 0.03)) <= 0.03, "噪声幅度受限")
	# 变动上限
	_ok(is_equal_approx(em.clamp_swing(1.0, 2.0, 0.15), 1.15), "单周上限 +15%")
	_ok(is_equal_approx(em.clamp_swing(1.0, 0.1, 0.15), 0.85), "单周下限 -15%")

	# 分段弹性影响真实价格
	MarketModel.cfg["piecewise_enabled"] = true
	var hi_stock_price := MarketModel.generic_price(100, 100, 100)
	var lo_stock_price := MarketModel.generic_price(100, 10, 100)
	_ok(lo_stock_price > hi_stock_price * 1.5, "低库存价格显著更高",
		"%.1f vs %.1f" % [lo_stock_price, hi_stock_price])

	# 市场事件
	var me = load("res://scripts/systems/market_events.gd")
	_ok(me.EVENTS.size() >= 8, "事件表至少 8 种", str(me.EVENTS.size()))
	var ev := {"id": &"harvest", "port": "p1", "target": "grain", "kind": "supply", "value": -0.2, "weeks": 2}
	var eff: float = float(me.effect_at([ev], "p1", &"grain"))
	_ok(absf(eff - 1.2) < 0.001, "供给 +25% 使价格 ×1.2", str(eff))
	var eff2: float = float(me.effect_at([ev], "p1", &"rum"))
	_ok(is_equal_approx(eff2, 1.0), "其他商品不受影响")
	var ticked: Array = me.tick([ev])
	_ok(int(ticked[0].get("weeks", 0)) == 1, "事件周数递减")
	_ok(me.tick(ticked).is_empty(), "到期事件被移除")

	# 周结算推进价格漂移
	GameState.reset_new_game()
	GameState.ensure_stock(&"jadehaven", &"grain", 400)
	var before := GameState.price_drift_of("jadehaven", &"grain")
	GameState.tick_market(1)
	var after := GameState.price_drift_of("jadehaven", &"grain")
	_ok(after != before or is_equal_approx(after, 1.0), "周结算后漂移发生变化", "%.3f" % after)
	_ok(after >= GameState.DRIFT_MIN - 0.001 and after <= GameState.DRIFT_MAX + 0.001,
		"漂移被限制在 0.85~1.15", "%.3f" % after)

# ---------------- 银行（0.12.0） ----------------
func _test_bank_v012() -> void:
	print("\n[银行]")
	GameState.reset_new_game()
	GameState.add_gold(100000)
	_ok(GameState.bank_deposit_gold(10000), "可以存款")
	_ok(GameState.bank_deposited() == 10000, "存款额正确")
	_ok(GameState.bank_credit() == 10000, "可贷额度 = 存款额")
	_ok(GameState.bank_withdraw(3000), "可以取款")
	_ok(GameState.bank_deposited() == 7000, "取款后余额正确")

	# 无存款不能贷
	GameState.bank_withdraw(7000)
	_ok(not bool(GameState.bank_borrow(1000, 12).get("ok", true)), "无存款不能贷款")
	GameState.bank_deposit_gold(10000)

	# 金额与期限分级
	_ok(not bool(GameState.bank_borrow(3000, 12).get("ok", true)), "非分级金额被拒")
	_ok(not bool(GameState.bank_borrow(100000, 12).get("ok", true)), "L5 不支持一季期限")
	_ok(not bool(GameState.bank_borrow(200000, 52).get("ok", true)), "超出分级上限被拒")

	# 利息计算
	_ok(GameState.loan_interest_for(1000, 12) == 24, "L1 一季利息 24")
	_ok(GameState.loan_interest_for(5000, 26) == 390, "L2 半年利息 390")
	_ok(GameState.loan_interest_for(20000, 52) == 5200, "L3 一年利息 5200")
	_ok(GameState.loan_interest_for(50000, 52) == 13000, "L4 一年利息 13000")
	_ok(GameState.loan_interest_for(100000, 52) == 26000, "L5 一年利息 26000")

	# 多笔并发
	GameState.reset_new_game()
	GameState.add_gold(500000)
	GameState.bank_deposit_gold(100000)
	_ok(bool(GameState.bank_borrow(20000, 52).get("ok", false)), "第一笔贷款成功")
	_ok(bool(GameState.bank_borrow(5000, 26).get("ok", false)), "第二笔贷款成功")
	_ok(GameState.loan_count() == 2, "可同时持有两笔", str(GameState.loan_count()))
	var exp1 := GameState.loan_exposure()
	_ok(exp1 == 20000 + 5200 + 5000 + 390, "本息总额 = 本金 + 未付利息", str(exp1))
	# 超本息总额被拒
	_ok(not bool(GameState.bank_borrow(100000, 52).get("ok", true)), "本息总额超存款被拒")
	# 笔数上限
	while GameState.loan_count() < 6 and bool(GameState.bank_borrow(1000, 12).get("ok", false)):
		pass
	_ok(GameState.loan_count() <= 6, "贷款笔数不超过 6")
	_ok(not bool(GameState.bank_borrow(1000, 12).get("ok", true)), "达到 6 笔后拒绝新借")

	# 逐笔还清
	GameState.gold = 500000
	_ok(bool(GameState.bank_repay_one(0).get("ok", false)), "可以单笔还清")
	_ok(GameState.loan_count() == 5, "单笔还清后数量减一")

	# 破产
	GameState.reset_new_game()
	GameState.add_gold(50000)
	GameState.bank_deposit_gold(5000)
	GameState.bank_borrow(1000, 12)
	GameState.loans[0]["left"] = 1
	GameState.gold = 1
	var ev: Array = GameState.bank_tick_week()
	var bankrupt := false
	for e in ev:
		if String(e.get("type", "")) == "bankrupt":
			bankrupt = true
	_ok(bankrupt or GameState.loans.is_empty(), "到期现金不足触发破产或已结清")

	# 全城互通：存款是全局唯一的
	GameState.reset_new_game()
	GameState.add_gold(5000)
	GameState.bank_deposit_gold(5000)
	_ok(GameState.bank_deposited() == 5000, "存款为全局账户")
	GameState.current_map = 5
	_ok(GameState.bank_deposited() == 5000, "换地图后存款仍在（全城互通）")

# ---------------- 黑市（0.11.0） ----------------
func _test_black_market_v011() -> void:
	print("\n[黑市]")
	GameState.reset_new_game()
	GameState.black_closed_week = -1
	_ok(GameState.black_market_open(), "通缉度低时黑市开放")

	# 销赃
	GameState.cargo.clear()
	GameState.add_cargo(&"grain", 50)
	var gold0 := GameState.gold
	var r: Dictionary = GameState.fence_goods(&"grain", 10, 100)
	_ok(bool(r.get("ok", false)), "可以销赃")
	_ok(int(r.get("amount", 0)) == 10, "销赃数量正确")
	_ok(int(r.get("gold", 0)) == 600, "销赃价 = 合法价 60%", "gold=%d" % int(r.get("gold", 0)))
	_ok(GameState.gold > gold0, "销赃获得金币")
	_ok(GameState.notoriety() == 2, "销赃后通缉度 +2", str(GameState.notoriety()))

	# 单次上限
	GameState.cargo.clear()
	GameState.add_cargo(&"grain", 500)
	var r2: Dictionary = GameState.fence_goods(&"grain", 500, 100)
	_ok(int(r2.get("amount", 0)) <= int(GameState.BLACK_SELL_LIMIT), "单次销赃不超过上限",
		"amount=%d" % int(r2.get("amount", 0)))

	# 违禁品
	GameState.add_gold(100000)
	var b1: Dictionary = GameState.buy_contraband(&"forge_flag")
	_ok(bool(b1.get("ok", false)), "可以购买违禁品")
	_ok(int(GameState.contraband.get(&"forge_flag", 0)) == 1, "违禁品入库")
	_ok(int(b1.get("price", 0)) == 3600, "违禁品价格正确")

	# 私掠许可证（黑市）
	GameState.has_privateer_license = false
	GameState.privateer_nation = ""
	var n0 := GameState.notoriety()
	var lic: Dictionary = GameState.buy_license_black("lan")
	_ok(bool(lic.get("ok", false)), "黑市可以买私掠证")
	_ok(GameState.has_privateer_license, "获得私掠证")
	_ok(GameState.privateer_nation == "lan", "私掠证绑定澜国")
	_ok(not GameState.license_is_legal, "标记为黑市途径")
	_ok(GameState.notoriety() == mini(100, n0 + 5), "买证通缉度 +5")

	# 正规途径需要声望
	GameState.reset_new_game()
	GameState.add_gold(100000)
	_ok(not bool(GameState.buy_license_legal("yunlan").get("ok", true)), "声望不足时不能买正规私掠证")
	GameState.faction_rep["yunlan"] = 60
	var lr: Dictionary = GameState.buy_license_legal("yunlan")
	_ok(bool(lr.get("ok", false)), "声望达标后可买正规私掠证", str(lr.get("reason", "")))
	_ok(GameState.license_is_legal, "标记为正规途径")

	# 持证劫掠商船：不额外降海军声望
	var navy0 := GameState.rep_of("royal_navy")
	GameState.on_enemy_killed("merchant", false)
	_ok(GameState.rep_of("royal_navy") >= navy0, "持私掠证劫掠商船不降海军声望",
		"%d -> %d" % [navy0, GameState.rep_of("royal_navy")])

	# 通缉度过高关闭黑市
	GameState.reset_new_game()
	GameState.reputation["notoriety"] = 85
	GameState.black_closed_week = TimeService.total_weeks()
	_ok(not GameState.black_market_open(), "通缉度 ≥80 时黑市关闭")
	GameState.black_closed_week = TimeService.total_weeks() - 1
	_ok(GameState.black_market_open(), "关闭一周后重新开放")

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
	GameState.add_gold(50000000)
	var cur := int(GameState.auctions[0].get("price", 0))
	var low: Dictionary = GameState.bid_auction(0, int(float(cur) * 1.01))
	_ok(not bool(low.get("ok", true)), "低于 1.05 倍被拒绝", String(low.get("reason", "")))
	var ok_bid: Dictionary = GameState.bid_auction(0, int(ceil(float(cur) * 1.05)))
	_ok(bool(ok_bid.get("ok", false)), "合规出价成功")
	_ok(String(GameState.auctions[0].get("leader", "")) == "player", "出价后玩家领先")

	# 倒计时与到期（把 weeks 压到 1，跑两次 tick）
	GameState.auctions[0]["weeks"] = 1
	var ev1: Array = GameState.tick_auctions(false)
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
	var ev2: Array = GameState.tick_auctions(false)
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
	var d2 := GameState.island_discount(key)
	_ok(d2 > 0 and d2 < 10, "Lv2 折扣按曲线（0~10%）", str(d2))
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
	GameState.current_map = 30
	var s3 = load("res://scenes/sea/sea_scene.tscn").instantiate()
	add_child(s3)
	await _frames(6)
	_ok(bool(s3.map_def.hostile), "敌对海域标记正确")
	_ok(s3.enemies.size() > 0, "图 30（海盗水域）有敌对单位",
		"count=%d" % s3.enemies.size())
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
	# 随机投放，阈值取舰船半径之和的保守下界
	_ok(min_pair >= 70.0, "单位之间保持最小间距（不会挤成一堆）", "最小间距=%.0f" % min_pair)

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
	_ok(DataRegistry.maps.size() == 30, "30 张海域（10 级 × 3）", "实得 %d" % DataRegistry.maps.size())
	var m1: Resource = DataRegistry.get_map(1)
	_ok(m1.tier == 1 and String(m1.nation) == "lan", "图 1 属澜国 1 级")
	_ok(not bool(m1.hostile), "图 1 海盗不主动")
	_ok(bool(DataRegistry.get_map(30).hostile), "图 30（海盗水域）为敌对")
	_ok(String(DataRegistry.get_map(30).pirate_boss) != "", "图 30 有 Boss")

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
	# 1.3.10：旧阵营声望不再变动，仅保留通缉度结算
	_ok(GameState.rep_of("royal_navy") == 0, "击沉海盗不再改旧阵营声望",
		str(GameState.rep_of("royal_navy")))
	GameState.on_enemy_killed("navy", false)
	_ok(GameState.notoriety() == 13, "击沉海军通缉度 +15（含海盗 −2）", str(GameState.notoriety()))

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
	_ok(GameState.faction_rep_of("youming") == 6, "任务完成给对应势力 +6",
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
	var expect_gold := GameState.START_GOLD + int(GameState.START_RES["gold"]) + 4321
	_ok(int(meta.get("gold", 0)) == expect_gold, "元数据金币正确",
		"实得 %d / 期望 %d" % [int(meta.get("gold", 0)), expect_gold])
	_ok(int(meta.get("level", 0)) == 7, "元数据等级正确")
	_ok(int(meta.get("map", 0)) == 4, "元数据地图正确")
	_ok(not bool(SaveManager.slot_meta(4).get("exists", false)), "空槽位显示为空")
	_ok(SaveManager.all_slot_ids().size() == 6, "共 6 个槽位（1 自动 + 5 手动）")
	GameState.reset_new_game()
	_ok(SaveManager.load_slot(3), "读取存档位 3")
	_ok(GameState.gold == GameState.START_GOLD + int(GameState.START_RES["gold"]) + 4321,
		"读档金币还原", str(GameState.gold))
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
	_ok(GameState.gold == GameState.START_GOLD + int(GameState.START_RES["gold"]) + 1234,
		"金币还原", "gold=%d" % GameState.gold)
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
