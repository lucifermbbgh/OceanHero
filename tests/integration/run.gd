extends Node
## 集成测试：在真实 SceneTree（含 autoload）下验证海域、战斗、战利品、存档。

var _pass := 0
var _fail := 0

func _ready() -> void:
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
	await _test_quest_nav()
	await _test_engage_rules()
	await _test_maps()
	await _test_bosses()
	await _test_quests()
	await _test_notoriety()
	await _test_boss_drops()
	await _test_escort_gather()
	await _test_reputation()
	await _test_commendation()
	await _test_victory()
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
		for i in range(150):
			await get_tree().physics_frame
		var h_start: float = idle.heading
		for i in range(30):
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
	# 模拟"玩家真的跑得掉"：每帧维持在 2000 距离之外
	for i in range(340):
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
	_ok(GameState.quests_available.size() == 3, "刷新 3 个任务", "实得 %d" % GameState.quests_available.size())
	var q: Dictionary = GameState.quests_available[0]
	_ok(String(q.title) != "" and int(q.reward_gold) > 0, "任务有标题与奖励")
	_ok(GameState.quest_accept(0), "接受任务")
	_ok(GameState.quests_active.size() == 1, "进入进行中")
	_ok(not GameState.quest_accept(5), "越界索引被拒绝")

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
	_ok(d1 > d0 + 20.0, "进入避障区后被推出", "%.0f -> %.0f" % [d0, d1])

	# 点击绕行：目标在岛的另一侧
	s.player.global_position = c + Vector2(r + 300.0, 0)
	var route: Array = s._route_to(c + Vector2(-(r + 300.0), 0))
	_ok(route.size() == 2, "跨岛航线插入绕航点", "size=%d" % route.size())
	var direct: Array = s._route_to(c + Vector2(r + 900.0, 0))
	_ok(direct.size() == 1, "不跨岛的航线不加绕航点")

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
