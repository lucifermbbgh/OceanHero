extends Node
## 唯一的可存档状态。场景与 UI 只读，修改一律走这里的公开方法。

const StatsLib = preload("res://scripts/systems/ship_stats.gd")
const CrewFactory = preload("res://scripts/systems/crew_factory.gd")
const MarketModel = preload("res://scripts/systems/market_model.gd")
const CRes = preload("res://scripts/systems/combat_resolver.gd")
const CrewDefScript = preload("res://scripts/data/crew_def.gd")
const AuctionFactory = preload("res://scripts/systems/auction_factory.gd")

const START_GOLD := 500
const START_SHIP := &"fishing_sloop"

var player_name: String = "无名船长"
var gold: int = START_GOLD
var commendation: int = 0          # 战功：硬通货，只从 Boss / 精英 / 主线获得
var level: int = 1
var xp: int = 0

# --- 当前船只状态 ---
var ship_def_id: StringName = START_SHIP
var ship_variant: StringName = &"standard"
var hull_hp: float = -1.0          # -1 表示未初始化，按 ShipDef 补满
var sail_pct: float = 1.0
var rudder_pct: float = 1.0
var crew_pct: float = 1.0

# --- 装备 ---
var equipped: Dictionary = {}       # slot(StringName) -> gear_id(StringName)
var gear_owned: Array = []          # 装备库（StringName 列表）

# --- 火炮（整船同一型号，受 ShipDef.max_cannon_weight 限制） ---
var cannon_id: StringName = &"pound3_light"
var cannons_owned: Array = [&"pound3_light"]

# --- 母港建设 ---
var buildings: Dictionary = {}      # id(StringName) -> level
var resources: Dictionary = {"timber": 0, "iron": 0, "grain": 0, "saltpeter": 0}
var build_queue: Array = []         # [{id, target, weeks_left}]

const RESOURCE_NAMES := {"timber": "木材", "iron": "铁矿", "grain": "粮食", "saltpeter": "硝石"}

# --- 声望与统计 ---
var donated_week: Dictionary = {"royal_navy": 0, "merchant": 0, "black_sail": 0}
var stat_kills: int = 0
var stat_bosses: int = 0
var game_cleared: bool = false

const FACTIONS := ["royal_navy", "merchant", "black_sail"]
const FACTION_NAMES := {"royal_navy": "王权海军", "merchant": "自由商会", "black_sail": "黑帆同盟"}
const REP_LEVELS := [0, 1000, 3000, 6000, 9000]
const REP_LEVEL_NAMES := ["无名", "熟客", "盟友", "贵宾", "传奇"]

# --- 任务 ---
var quests_available: Array = []
var quests_active: Array = []

# --- 交易所 ---
var orders: Array = []          # 本周可接的远洋订单
var active_orders: Array = []   # 已接、待交付
var futures: Array = []         # 期货合约

# --- 船员 ---
var crew_roster: Array = []         # [CrewDef] 已雇佣
var crew_assigned: Array = []       # [StringName] 上阵船员的 crew_id
var tavern_pool: Array = []         # 酒馆当前可雇佣（不存档，进港刷新）

# --- 其它船只（停在别的港口） ---
var ships_owned: Array = []         # [{def_id, variant, station_port, hull_hp, sail_pct, rudder_pct, crew_pct, equipped}]
var current_port: StringName = &"jadehaven"   # 当前船停靠/出发的港口

# --- 货舱 ---
var cargo: Dictionary = {}          # StringName -> int（船上货舱）
var warehouse: Dictionary = {}      # StringName -> int（母港仓库）
var island_stock: Dictionary = {}   # 兼容保留（岛屿采集已废弃）
## 母港成长等级：1 渔港村落 / 2 乡镇 / 3 港口城市
var home_port_tier := 1

# --- 世界 ---
var current_map: int = 1
var sea_position: Vector2 = Vector2(0, 0)
var cleared_maps: Array = []
var boss_defeated: Array = []

# --- 声望 ---
var reputation: Dictionary = {
	"royal_navy": 0, "merchant": 0, "black_sail": 0, "notoriety": 0,
}

# --- 港口商品库存：port_id -> {commodity_id -> int} ---
var port_stock: Dictionary = {}

# 时钟由 TimeService 单独持有，不进 GameState。

func ship_def() -> Resource:
	return DataRegistry.get_ship(ship_def_id)

## 当前船的最终属性（基准 × 变体 × 装备）
func stats() -> Dictionary:
	var d := ship_def()
	if d == null:
		return {"hull_max": 400.0, "cargo_capacity": 200}
	return StatsLib.compute(d, ship_variant, equipped, assigned_crews())

# ---------------- 母港建设 ----------------

# ---------------- 关卡推进 ----------------

func is_boss_defeated(id: StringName) -> bool:
	return boss_defeated.has(String(id))

func is_map_cleared(index: int) -> bool:
	return cleared_maps.has(index)

func can_enter_map(index: int) -> bool:
	if index <= 1:
		return true
	return is_map_cleared(index - 1)

## 记录一次 Boss 击杀；若由此开启新海域则返回 true
func record_boss_defeat(id: StringName, map_index: int) -> bool:
	var sid := String(id)
	if String(id).begins_with("boss_") and not boss_defeated.has(sid):
		boss_defeated.append(sid)
		if not cleared_maps.has(map_index):
			cleared_maps.append(map_index)
			return true
	return false

func building_level(id: StringName) -> int:
	return int(buildings.get(id, 0))

func total_production() -> Dictionary:
	var out := {"timber": 0, "iron": 0, "grain": 0, "saltpeter": 0}
	for bid in DataRegistry.buildings.keys():
		var b: Resource = DataRegistry.buildings[bid]
		var lv := building_level(bid)
		if lv <= 0:
			continue
		for res in b.production.keys():
			out[String(res)] = int(out.get(String(res), 0)) + int(b.production[res]) * lv
	return out

func has_resources(cost: Dictionary) -> bool:
	if GameState.gold < int(cost.get("gold", 0)):
		return false
	for r in ["timber", "iron"]:
		if int(resources.get(r, 0)) < int(cost.get(r, 0)):
			return false
	return true

func spend_resources(cost: Dictionary) -> void:
	add_gold(-int(cost.get("gold", 0)))
	resources["timber"] = maxi(0, int(resources.get("timber", 0)) - int(cost.get("timber", 0)))
	resources["iron"] = maxi(0, int(resources.get("iron", 0)) - int(cost.get("iron", 0)))

func is_building(id: StringName) -> bool:
	for q in build_queue:
		if StringName(q.get("id", "")) == id:
			return true
	return false

func start_build(id: StringName) -> bool:
	var b: Resource = DataRegistry.get_building(id)
	if b == null or is_building(id):
		return false
	var lv := building_level(id)
	if lv >= int(b.max_level):
		return false
	var cost: Dictionary = b.cost_for(lv + 1)
	if not has_resources(cost):
		return false
	spend_resources(cost)
	build_queue.append({"id": String(id), "target": lv + 1, "weeks_left": int(cost.weeks)})
	return true

## 周结算：推进建造，返回本周完工的建筑名
func tick_build_queue() -> Array:
	var done: Array = []
	var still: Array = []
	for q in build_queue:
		q["weeks_left"] = int(q.weeks_left) - 1
		if int(q.weeks_left) <= 0:
			var id := StringName(q.get("id", ""))
			var b: Resource = DataRegistry.get_building(id)
			buildings[id] = mini(int(q.get("target", 1)), int(b.max_level) if b != null else 5)
			done.append(String(b.display_name) if b != null else String(id))
		else:
			still.append(q)
	build_queue = still
	return done

# ---------------- 声望 ----------------

func rep_of(faction: String) -> int:
	return int(reputation.get(faction, 0))

func rep_level(faction: String) -> int:
	var v := rep_of(faction)
	var lv := 0
	for i in range(REP_LEVELS.size()):
		if v >= int(REP_LEVELS[i]):
			lv = i
	return lv

func rep_level_name(faction: String) -> String:
	return REP_LEVEL_NAMES[rep_level(faction)]

func add_rep(faction: String, amount: int) -> void:
	if not reputation.has(faction):
		return
	reputation[faction] = clampi(rep_of(faction) + amount, 0, 10000)

## 捐赠：1,000 金 = 10 声望，每周每阵营上限 50 声望
func donate(faction: String, gold: int) -> Dictionary:
	var cap := 5000 - int(donated_week.get(faction, 0))
	var spend := mini(gold, cap)
	if spend <= 0:
		return {"ok": false, "reason": "本周捐赠额度已满"}
	if gold > self.gold:
		return {"ok": false, "reason": "金币不足"}
	spend_resources({"gold": spend})
	donated_week[faction] = int(donated_week.get(faction, 0)) + spend
	var gain := spend / 100
	add_rep(faction, gain)
	return {"ok": true, "gold": spend, "rep": gain}

func reset_donations() -> void:
	for f in FACTIONS:
		donated_week[f] = 0

# ---------------- 通缉 ----------------

func post_bail(amount: int = 5000) -> Dictionary:
	if notoriety() <= -100:
		return {"ok": false, "reason": "通缉度已是最低"}
	if gold < amount:
		return {"ok": false, "reason": "金币不足"}
	spend_resources({"gold": amount})
	reputation["notoriety"] = maxi(-100, notoriety() - 20)
	return {"ok": true, "gold": amount, "notoriety": notoriety()}

func decay_notoriety() -> void:
	var n := notoriety()
	if n > 0:
		reputation["notoriety"] = maxi(0, n - 2)
	elif n < 0:
		reputation["notoriety"] = mini(0, n + 2)

# ---------------- 战功 ----------------

## 战功商店：fame → 声望 / 船员 / 装备
func spend_commendation(kind: String, arg: String = "") -> Dictionary:
	match kind:
		"rep":
			if commendation < 200:
				return {"ok": false, "reason": "战功不足（需 200）"}
			if arg == "":
				arg = "royal_navy"
			commendation -= 200
			add_rep(arg, 100)
			return {"ok": true, "text": "%s 声望 +100" % FACTION_NAMES.get(arg, arg)}
		"crew":
			if commendation < 50:
				return {"ok": false, "reason": "战功不足（需 50）"}
			commendation -= 50
			var c = CrewDefScript.new()
			c.crew_id = StringName("fame_%d_%d" % [Time.get_ticks_usec(), RngService.randi_range(100, 999)])
			c.display_name = "受勋船员"
			c.role = CrewFactory.ROLES[RngService.randi_range(0, CrewFactory.ROLES.size() - 1)]
			c.rarity = 4
			c.stat = RngService.randi_range(40, 50)
			c.wage = int(c.stat * 4)
			c.hire_cost = 0
			crew_roster.append(c)
			return {"ok": true, "text": "获得 UR 船员" }
		"gear":
			if commendation < 100:
				return {"ok": false, "reason": "战功不足（需 100）"}
			var pool: Array = []
			for k in DataRegistry.gear.keys():
				var g: Resource = DataRegistry.gear[k]
				if String(g.id).begins_with("uniq_") and not gear_owned.has(g.id):
					pool.append(g.id)
			if pool.is_empty():
				return {"ok": false, "reason": "已集齐全部独有装备"}
			commendation -= 100
			var pick: StringName = pool[RngService.randi_range(0, pool.size() - 1)]
			gear_owned.append(pick)
			return {"ok": true, "text": "获得 %s" % DataRegistry.get_gear(pick).display_name}
	return {"ok": false, "reason": "未知商品"}

# ---------------- 统计与通关 ----------------

func stat_add_kill(is_boss: bool) -> void:
	stat_kills += 1
	if is_boss:
		stat_bosses += 1

func check_victory() -> bool:
	if game_cleared:
		return false
	if is_map_cleared(9):
		game_cleared = true
		return true
	return false

# ---------------- 任务 ----------------

## 接取任务。接取数量不设上限，看板存量也不设上限
func quest_accept(index: int) -> bool:
	if index < 0 or index >= quests_available.size():
		return false
	var q: Dictionary = quests_available[index]
	quests_available.remove_at(index)
	quests_active.append(q)
	return true

## 放弃任务：放回看板，可以再次接取
func quest_cancel(index: int) -> bool:
	if index < 0 or index >= quests_active.size():
		return false
	var q: Dictionary = quests_active[index]
	quests_active.remove_at(index)
	q["progress"] = 0
	quests_available.append(q)
	return true

## 每周看板刷新：只在看板**没有存量任务**时补满 9 个；有存量则不动
func refresh_quests() -> void:
	if not quests_available.is_empty():
		return
	quests_available.clear()
	var comms: Array = DataRegistry.commodities.keys()
	for i in range(9):
		var t: String = ["hunt", "trade", "transport", "escort", "gather", "raid", "treasure"][RngService.randi_range(0, 6)]
		var q := {"id": "q_%d_%d" % [Time.get_ticks_usec(), i], "type": t, "progress": 0,
			"reward_xp": 40 + level * 12, "reward_comm": 1,
			"faction": FACTIONS[RngService.randi_range(0, FACTIONS.size() - 1)]}
		match t:
			"hunt":
				var kind := "pirate" if RngService.chance(0.6) else "monster"
				q["target_kind"] = kind
				q["amount"] = RngService.randi_range(3, 6) + int(level / 6)
				q["title"] = "讨伐 %d 个%s" % [int(q.amount), "海盗" if kind == "pirate" else "海怪"]
				q["reward_gold"] = 180 * int(q.amount) + level * 40
			"trade":
				q["amount"] = 600 + level * 150
				q["title"] = "赚取 %d 金贸易利润" % int(q.amount)
				q["reward_gold"] = int(q.amount / 2)
			"transport":
				var cid: StringName = comms[RngService.randi_range(0, comms.size() - 1)]
				var c: Resource = DataRegistry.get_commodity(cid)
				q["commodity"] = String(cid)
				q["amount"] = RngService.randi_range(15, 45)
				q["dest"] = "map1_outpost"
				q["title"] = "运送 %d 份%s到浅湾哨站" % [int(q.amount), c.display_name]
				q["reward_gold"] = 60 * int(q.amount)
			"escort":
				q["amount"] = 1
				q["target_port"] = "map1_outpost"
				q["title"] = "护送商船到浅湾哨站"
				q["reward_gold"] = 1200 + level * 120
			"gather":
				q["amount"] = RngService.randi_range(2, 4)
				q["title"] = "打捞 %d 处沉船残骸" % int(q.amount)
				q["reward_gold"] = 500 + level * 80
			"raid":
				q["target_kind"] = "merchant"
				q["amount"] = RngService.randi_range(2, 4)
				q["title"] = "劫掠 %d 艘敌对商船" % int(q.amount)
				q["reward_gold"] = 900 + level * 90
			"treasure":
				q["amount"] = 1
				q["treasure_map"] = 1 + RngService.randi_range(0, 2)
				q["title"] = "在第 %d 图海域打捞宝藏" % int(q["treasure_map"])
				q["reward_gold"] = 1500 + level * 150
		quests_available.append(q)

func _quest_finish(index: int) -> void:
	var q: Dictionary = quests_active[index]
	add_gold(int(q.get("reward_gold", 0)))
	xp += int(q.get("reward_xp", 0))
	commendation += int(q.get("reward_comm", 0))
	while xp >= CRes.xp_to_next(level):
		xp -= CRes.xp_to_next(level)
		level += 1
	var fac := String(q.get("faction", ""))
	if fac != "":
		add_rep(fac, 120)
	quests_active.remove_at(index)
	EventBus.ticker.emit("任务完成：%s（+%d 金%s）" % [String(q.get("title", "")), int(q.get("reward_gold", 0)),
		"，%s +120" % FACTION_NAMES.get(fac, "") if fac != "" else ""])

func _quest_check() -> void:
	var i := 0
	while i < quests_active.size():
		var q: Dictionary = quests_active[i]
		if int(q.get("progress", 0)) >= int(q.get("amount", 1)):
			_quest_finish(i)
		else:
			i += 1

func on_enemy_killed(kind: String, is_boss: bool) -> void:
	# 通缉度
	var noto := int(reputation.get("notoriety", 0))
	if kind == "pirate" or kind == "monster":
		noto = maxi(-100, noto - (5 if is_boss else 2))
	elif kind == "navy":
		noto = mini(100, noto + 15)
		add_rep("royal_navy", -30)
		add_rep("black_sail", 15)
	elif kind == "merchant":
		noto = mini(100, noto + 8)
		add_rep("merchant", -40)
		add_rep("black_sail", 15)
		# 持私掠许可证的合法劫掠：不对敌国商船额外扣海军声望
		if has_privateer_license:
			add_rep("royal_navy", 5)
	reputation["notoriety"] = noto
	if kind == "pirate":
		add_rep("royal_navy", 8 if is_boss else 3)
		add_rep("black_sail", -3)
	elif kind == "monster":
		add_rep("royal_navy", 5 if is_boss else 2)
	stat_add_kill(is_boss)
	# 讨伐任务进度
	for q in quests_active:
		var qt := String(q.get("type", ""))
		if (qt == "hunt" or qt == "raid") and String(q.get("target_kind", "")) == kind:
			q["progress"] = int(q.get("progress", 0)) + 1
	_quest_check()

func on_trade_profit(amount: int) -> void:
	if amount <= 0:
		return
	for q in quests_active:
		if String(q.get("type", "")) == "trade":
			q["progress"] = int(q.get("progress", 0)) + amount
	_quest_check()

func grant_unique_gear(gid: StringName) -> bool:
	if String(gid) == "" or gear_owned.has(gid):
		return false
	gear_owned.append(gid)
	var g: Resource = DataRegistry.get_gear(gid)
	if g != null:
		EventBus.ticker.emit("获得独有装备：%s" % g.display_name)
	return true

func grant_unique_crew(nm: String, role: StringName, stat: int) -> bool:
	if nm == "":
		return false
	var c = CrewDefScript.new()
	c.crew_id = StringName("uniq_%d_%d" % [Time.get_ticks_usec(), RngService.randi_range(100, 999)])
	c.display_name = nm
	c.role = role
	c.rarity = 4
	c.stat = stat
	c.wage = int(stat * 4)
	c.hire_cost = 0
	crew_roster.append(c)
	EventBus.ticker.emit("独有船员加入：%s" % nm)
	return true

func on_escort_arrived() -> void:
	for q in quests_active:
		if String(q.get("type", "")) == "escort":
			q["progress"] = 1
	_quest_check()

func on_escort_lost() -> void:
	var i := 0
	while i < quests_active.size():
		if String(quests_active[i].get("type", "")) == "escort":
			EventBus.ticker.emit("护航任务失败：商船被击沉")
			quests_active.remove_at(i)
		else:
			i += 1

func on_salvage() -> void:
	for q in quests_active:
		if String(q.get("type", "")) == "gather":
			q["progress"] = int(q.get("progress", 0)) + 1
	_quest_check()

func on_deliver(commodity: StringName, amount: int) -> void:
	for q in quests_active:
		if String(q.get("type", "")) == "transport" and StringName(q.get("commodity", "")) == commodity:
			q["progress"] = int(q.get("progress", 0)) + amount
	_quest_check()

## 玩家当前最亲近的阵营（声望 ≥ 3000 才算"加入"），用于单位标识
func aligned_faction() -> String:
	var best := ""
	var best_v := 3000
	for f in FACTIONS:
		if rep_of(f) >= best_v and rep_of(f) > best_v - 1:
			best_v = rep_of(f)
			best = f
	return best

func notoriety() -> int:
	return int(reputation.get("notoriety", 0))

func bounty_active() -> bool:
	return notoriety() >= 50

# ---------------- 交易所 ----------------

func exchange_level() -> int:
	return building_level(&"exchange")

## 标签页解锁：行情 1 / 订单 2 / 大宗 3 / 期货 4
func exchange_tab_unlocked(tab: int) -> bool:
	return exchange_level() >= tab + 1

func refresh_orders() -> void:
	orders.clear()
	var ports: Array = DataRegistry.ports.keys()
	var comms: Array = DataRegistry.commodities.keys()
	for i in range(3):
		var cid: StringName = comms[RngService.randi_range(0, comms.size() - 1)]
		var c: Resource = DataRegistry.get_commodity(cid)
		var dest: StringName = ports[RngService.randi_range(0, ports.size() - 1)]
		if dest == &"jadehaven" and ports.size() > 1:
			dest = ports[(ports.find(dest) + 1) % ports.size()]
		var amount := RngService.randi_range(50, 200)
		var premium := 1.25 + RngService.randf() * 0.35
		orders.append({
			"id": "%d_%d" % [Time.get_ticks_usec(), i],
			"commodity": String(cid),
			"amount": amount,
			"dest": String(dest),
			"price": int(round(float(c.base_price) * 1.35 * premium)),
			"weeks_left": RngService.randi_range(2, 4),
		})

func accept_order(index: int) -> bool:
	if index < 0 or index >= orders.size():
		return false
	var o: Dictionary = orders[index]
	orders.remove_at(index)
	active_orders.append(o)
	return true

func deliver_order(index: int, port_id: StringName) -> Dictionary:
	if index < 0 or index >= active_orders.size():
		return {"ok": false, "reason": "订单不存在"}
	var o: Dictionary = active_orders[index]
	if StringName(o.get("dest", "")) != port_id:
		return {"ok": false, "reason": "不是本港的交付点"}
	var cid: StringName = StringName(o.get("commodity", ""))
	var need := int(o.get("amount", 0))
	if int(cargo.get(cid, 0)) < need:
		return {"ok": false, "reason": "货舱里没有足够的货"}
	remove_cargo(cid, need)
	var pay := int(o.get("price", 0)) * need
	add_gold(pay)
	active_orders.remove_at(index)
	return {"ok": true, "gold": pay, "commodity": String(cid), "amount": need}

func lock_future(cid: StringName, amount: int) -> Dictionary:
	var c: Resource = DataRegistry.get_commodity(cid)
	if c == null:
		return {"ok": false, "reason": "商品不存在"}
	var port: Resource = DataRegistry.get_port(&"jadehaven")
	var stock := ensure_stock(&"jadehaven", cid, int(port.max_stock) if port != null else 800)
	var price := MarketModel.buy_price(int(c.base_price), stock, int(port.max_stock) if port != null else 800)
	var deposit := int(round(float(price * amount) * 0.2))
	if gold < deposit:
		return {"ok": false, "reason": "定金不足"}
	add_gold(-deposit)
	futures.append({
		"commodity": String(cid), "amount": amount, "price": price,
		"weeks_left": 1, "deposit": deposit,
	})
	return {"ok": true, "deposit": deposit, "price": price}

func redeem_future(index: int) -> Dictionary:
	if index < 0 or index >= futures.size():
		return {"ok": false, "reason": "合约不存在"}
	var f: Dictionary = futures[index]
	var cid: StringName = StringName(f.get("commodity", ""))
	var amount := int(f.get("amount", 0))
	var rest := int(f.get("price", 0)) * amount - int(f.get("deposit", 0))
	if gold < rest:
		return {"ok": false, "reason": "尾款不足"}
	if cargo_free() < float(DataRegistry.get_commodity(cid).volume) * amount:
		return {"ok": false, "reason": "货舱空间不足"}
	add_gold(-rest)
	add_cargo(cid, amount)
	futures.remove_at(index)
	return {"ok": true, "gold": rest}

## 周结算：订单与期货推进/过期
func tick_exchange() -> void:
	refresh_orders()
	var keep_active: Array = []
	for o in active_orders:
		o["weeks_left"] = int(o.weeks_left) - 1
		if int(o.weeks_left) > 0:
			keep_active.append(o)
	active_orders = keep_active
	var keep_fut: Array = []
	for f in futures:
		f["weeks_left"] = int(f.weeks_left) - 1
		if int(f.weeks_left) > 0:
			keep_fut.append(f)
	futures = keep_fut

func pay_crew_wages() -> int:
	var total := 0
	for c in assigned_crews():
		total += int(c.wage)
	if total <= 0:
		return 0
	var paid := mini(total, gold)
	add_gold(-paid)
	return paid

func assigned_wages() -> int:
	var total := 0
	for c in assigned_crews():
		total += int(c.wage)
	return total

# ---- 建筑效果 ----
func repair_discount() -> float:
	return 0.06 * float(building_level(&"drydock"))

func sell_bonus() -> float:
	return 0.03 * float(building_level(&"exchange"))

func cannon_class_cap() -> int:
	return 3 + 2 * building_level(&"foundry")

func gear_rarity_cap() -> int:
	return building_level(&"sailmaker")

func tavern_size() -> int:
	return 6 + 2 * building_level(&"tavern")

func storage_slots() -> int:
	return 3 + 2 * building_level(&"warehouse") + 4

# ---------------- 船员 ----------------

func crew_slots() -> int:
	return int(stats().get("crew_slots", 8))

func assigned_crews() -> Array:
	var out: Array = []
	for id in crew_assigned:
		var c := find_crew(id)
		if c != null:
			out.append(c)
	return out

func find_crew(id: StringName) -> Resource:
	for c in crew_roster:
		if StringName(c.crew_id) == id:
			return c
	return null

func assign_crew(id: StringName) -> bool:
	if crew_assigned.has(id):
		return false
	if crew_assigned.size() >= crew_slots():
		return false
	if find_crew(id) == null:
		return false
	crew_assigned.append(id)
	return true

func unassign_crew(id: StringName) -> void:
	crew_assigned.erase(id)

func dismiss_crew(id: StringName) -> void:
	crew_assigned.erase(id)
	for i in range(crew_roster.size()):
		if StringName(crew_roster[i].crew_id) == id:
			crew_roster.remove_at(i)
			return

func hire_crew(c: Resource) -> void:
	crew_roster.append(c)

func refresh_tavern() -> void:
	tavern_pool = CrewFactory.generate(tavern_size(), ship_variant)

func hull_pct_like() -> float:
	var m := hull_max()
	if m <= 0.0:
		return 0.0
	return clampf((hull_hp if hull_hp >= 0.0 else m) / m, 0.0, 1.0)

func hull_max() -> float:
	return float(stats().get("hull_max", 400.0))

func cargo_capacity() -> int:
	return int(stats().get("cargo_capacity", 200))

## 换乘到 ships_owned 里的一艘船（调用方负责校验港口）
func swap_to_owned(index: int, port_id: StringName = &"jadehaven") -> bool:
	if index < 0 or index >= ships_owned.size():
		return false
	# 新船装不下当前货物则禁止换乘（船→大船平迁没问题，大→小会被拦）
	if swap_overload(index):
		return false
	var other: Dictionary = ships_owned[index]
	# 把当前船存回库存（停泊在换乘的港口）
	ships_owned.append({
		"def_id": String(ship_def_id), "variant": String(ship_variant),
		"station_port": String(port_id),
		"hull_hp": hull_hp, "sail_pct": sail_pct,
		"rudder_pct": rudder_pct, "crew_pct": crew_pct,
		"equipped": equipped.duplicate(),
		"cannon_id": String(cannon_id),
	})
	ships_owned.remove_at(index)
	ship_def_id = StringName(other.get("def_id", String(START_SHIP)))
	ship_variant = StringName(other.get("variant", "standard"))
	hull_hp = float(other.get("hull_hp", -1.0))
	sail_pct = float(other.get("sail_pct", 1.0))
	rudder_pct = float(other.get("rudder_pct", 1.0))
	crew_pct = float(other.get("crew_pct", 1.0))
	equipped = other.get("equipped", {}).duplicate()
	cannon_id = StringName(other.get("cannon_id", "pound3_light"))
	ensure_ship()
	return true

## 购买一艘船（金币在调用方扣除）
func add_owned_ship(def_id: StringName, variant: StringName, price: int) -> void:
	ships_owned.append({
		"def_id": String(def_id), "variant": String(variant),
		"station_port": "jadehaven",
		"hull_hp": -1.0, "sail_pct": 1.0, "rudder_pct": 1.0, "crew_pct": 1.0,
		"equipped": {},
		"cannon_id": "pound3_light",
	})

## 装备/卸下
func equip_gear(slot: StringName, gear_id: StringName) -> void:
	if gear_id == &"":
		equipped.erase(slot)
	else:
		equipped[slot] = gear_id

func has_gear(gear_id: StringName) -> bool:
	return gear_owned.has(gear_id) or equipped.values().has(gear_id)

func has_cannon(id: StringName) -> bool:
	return cannons_owned.has(id) or cannon_id == id

## 当前船能否装这门炮（受 max_cannon_weight 限制）
func can_mount_cannon(id: StringName) -> bool:
	var c: Resource = DataRegistry.get_cannon(id)
	var d := ship_def()
	if c == null or d == null:
		return false
	return int(c.pound_class) <= int(d.max_cannon_weight)

func cargo_used() -> float:
	var used := 0.0
	for id in cargo.keys():
		var c := DataRegistry.get_commodity(id)
		if c != null:
			used += float(c.volume) * float(cargo[id])
	return used

func cargo_free() -> float:
	return maxf(0.0, float(cargo_capacity()) - cargo_used())

# ---------------- 差别定价与财务（0.16~0.18） ----------------

## 声望折扣：按最高阵营声望给买价优惠
const REP_DISCOUNTS := [0.0, 0.02, 0.04, 0.06]
const REP_THRESHOLDS := [0, 1000, 3000, 6000]

func best_rep() -> int:
	var best := 0
	for f in FACTIONS:
		best = maxi(best, rep_of(f))
	return best

func rep_discount() -> float:
	var r := best_rep()
	if r >= REP_THRESHOLDS[3]:
		return REP_DISCOUNTS[3]
	if r >= REP_THRESHOLDS[2]:
		return REP_DISCOUNTS[2]
	if r >= REP_THRESHOLDS[1]:
		return REP_DISCOUNTS[1]
	return REP_DISCOUNTS[0]

func rep_discount_name() -> String:
	var r := best_rep()
	if r >= REP_THRESHOLDS[3]:
		return "自家人"
	if r >= REP_THRESHOLDS[2]:
		return "老主顾"
	if r >= REP_THRESHOLDS[1]:
		return "熟客"
	return "陌生人"

# ---- 财务记账（按自然年） ----

var finance: Dictionary = {}      # {purchases:{cid:{qty,cost}}, sales:{cid:{qty,revenue}}, income:{}, expense:{}}
var week_income: Dictionary = {}
var week_expense: Dictionary = {}
var last_week_income: Dictionary = {}
var last_week_expense: Dictionary = {}

## 周结算结束时滚动本周账目
func week_roll() -> void:
	last_week_income = week_income.duplicate(true)
	last_week_expense = week_expense.duplicate(true)
	week_income = {}
	week_expense = {}
var reports: Array = []           # 历年财报
var report_year := 0              # 已出过财报的年份

func _fin_year_reset() -> void:
	finance = {"purchases": {}, "sales": {}, "income": {}, "expense": {}}

func finance_reset() -> void:
	_fin_year_reset()
	reports.clear()
	report_year = 0

func record_purchase(cid: StringName, qty: int, cost: int) -> void:
	if not finance.has("purchases"):
		_fin_year_reset()
	var e: Dictionary = finance["purchases"].get(String(cid), {"qty": 0, "cost": 0})
	e["qty"] = int(e["qty"]) + qty
	e["cost"] = int(e["cost"]) + cost
	finance["purchases"][String(cid)] = e
	record_expense("采购", cost)

func record_sale(cid: StringName, qty: int, revenue: int) -> void:
	if not finance.has("sales"):
		_fin_year_reset()
	var e: Dictionary = finance["sales"].get(String(cid), {"qty": 0, "revenue": 0})
	e["qty"] = int(e["qty"]) + qty
	e["revenue"] = int(e["revenue"]) + revenue
	finance["sales"][String(cid)] = e
	record_income("贸易", revenue)

func record_income(kind: String, amount: int) -> void:
	if not finance.has("income"):
		_fin_year_reset()
	finance["income"][kind] = int(finance["income"].get(kind, 0)) + maxi(0, amount)
	week_income[kind] = int(week_income.get(kind, 0)) + maxi(0, amount)

func record_expense(kind: String, amount: int) -> void:
	if not finance.has("expense"):
		_fin_year_reset()
	finance["expense"][kind] = int(finance["expense"].get(kind, 0)) + maxi(0, amount)
	week_expense[kind] = int(week_expense.get(kind, 0)) + maxi(0, amount)

## 汇总：{income_total, expense_total, net, income:{}, expense:{}}
func finance_summary() -> Dictionary:
	if not finance.has("income"):
		_fin_year_reset()
	var inc := 0
	for k in finance.get("income", {}).keys():
		inc += int(finance["income"][k])
	var exp := 0
	for k in finance.get("expense", {}).keys():
		exp += int(finance["expense"][k])
	return {"income_total": inc, "expense_total": exp, "net": inc - exp,
		"income": finance.get("income", {}).duplicate(),
		"expense": finance.get("expense", {}).duplicate()}

## 生成年度财报（跨年时调用）
func make_annual_report(year: int) -> Dictionary:
	var s := finance_summary()
	var assets := gold + bank_deposited()
	var fleet_value := 0
	for sh in ships_owned:
		if sh is Resource and sh.get("price") != null:
			fleet_value += int(sh.get("price"))
	var cargo_value := 0
	for cid in cargo.keys():
		var c: Resource = DataRegistry.get_commodity(cid)
		if c != null:
			cargo_value += int(c.base_price) * int(cargo[cid])
	var debt := loan_exposure()
	var rep_dict := {
		"year": year, "income": s["income"], "expense": s["expense"],
		"income_total": s["income_total"], "expense_total": s["expense_total"],
		"net": s["net"], "purchases": finance.get("purchases", {}).duplicate(),
		"sales": finance.get("sales", {}).duplicate(),
		"cash": gold, "deposit": bank_deposited(), "fleet": fleet_value,
		"cargo": cargo_value, "debt": debt,
		"assets": assets + fleet_value + cargo_value,
		"net_worth": assets + fleet_value + cargo_value - debt,
	}
	reports.clear()
	reports.append(rep_dict)
	report_year = year
	_fin_year_reset()
	return rep_dict

# ---------------- 成本结构（0.15） ----------------

## 每周维护费明细：{hull, berth, crew, cannon, total, fixed, variable}
func weekly_upkeep() -> Dictionary:
	var hull := 0
	for s in ships_owned:
		var p := 5000.0
		if s is Resource and s.get("price") != null:
			p = float(s.get("price"))
		hull += int(round(p * 0.02))
	var berth := 0
	match home_port_tier:
		1: berth = 5
		2: berth = 15
		3: berth = 40
	var crew := assigned_wages()
	var cannon := 0
	for g in gear_owned:
		var gd: Resource = DataRegistry.get_gear(g)
		if gd != null and String(gd.get("slot")) == "cannon":
			cannon += 8
	var fixed := hull + berth
	var variable := crew + cannon
	return {"hull": hull, "berth": berth, "crew": crew, "cannon": cannon,
		"fixed": fixed, "variable": variable, "total": fixed + variable}

# ---------------- 价格漂移与市场事件（0.13） ----------------

const EconMath = preload("res://scripts/systems/econ_math.gd")
const MarketEvents = preload("res://scripts/systems/market_events.gd")

const DRIFT_MIN := 0.85
const DRIFT_MAX := 1.15
const DRIFT_SPEED := 0.25
const DRIFT_NOISE := 0.03

var price_drift: Dictionary = {}     # "port|cid" -> 漂移倍率（1.0 为基准）
var market_events: Array = []        # 当前生效事件
var price_history: Dictionary = {}   # "port|cid" -> Array[int]（千分比漂移，最多 8 周）

## 交叉弹性：替代（正）/ 互补（负）系数；只在同港口传导，单层不级联
const CROSS_RELATIONS := [
	{"a": &"rum", "b": &"spice", "coef": 0.4},
	{"a": &"grain", "b": &"rum", "coef": -0.3},
	{"a": &"timber", "b": &"iron", "coef": 0.2},
]
const CROSS_THRESHOLD := 0.05
const CROSS_CAP := 0.08
const HISTORY_WEEKS := 8

func _drift_key(port_key: String, cid: StringName) -> String:
	return "%s|%s" % [port_key, String(cid)]

## 当前漂移倍率（含事件影响）
func price_drift_of(port_key: String, cid: StringName) -> float:
	return float(price_drift.get(_drift_key(port_key, cid), 1.0))

## 某港某商品当前受事件影响后的价格倍率
func price_modifier(port_key: String, cid: StringName) -> float:
	return price_drift_of(port_key, cid) * MarketEvents.effect_at(market_events, port_key, cid)

## 某港口某商品的 8 周历史（千分比）
func price_history_of(port_key: String, cid: StringName) -> Array:
	return price_history.get(_drift_key(port_key, cid), [])

## 交叉弹性：计算某商品本港受到的传导（来自其他商品的变化）
func _cross_transmission(port_key: String, cid: StringName) -> float:
	var total := 0.0
	for rel in CROSS_RELATIONS:
		if String(rel["b"]) != String(cid):
			continue
		var src_key := _drift_key(port_key, StringName(rel["a"]))
		var cur := float(price_drift.get(src_key, 1.0))
		var prev := float(price_drift.get(src_key + "|prev", cur))
		var chg := EconMath.change_pct(prev, cur)
		total += EconMath.cross_effect(chg, float(rel["coef"]), CROSS_THRESHOLD, CROSS_CAP)
	return clampf(total, -CROSS_CAP, CROSS_CAP)

## 周结算：事件推进与生成、价格漂移回归
func tick_market(week: int) -> Array:
	var events_out: Array = []
	market_events = MarketEvents.tick(market_events)
	for pk in port_stock.keys():
		var port_key := String(pk)
		if market_events.size() < MarketEvents.MAX_ACTIVE:
			var ev: Dictionary = MarketEvents.roll_event(port_key, week)
			if not ev.is_empty():
				market_events.append(ev)
				events_out.append(ev)
		for cid in port_stock[pk].keys():
			var key := _drift_key(port_key, cid)
			var cur := float(price_drift.get(key, 1.0))
			var target := MarketEvents.effect_at(market_events, port_key, cid)
			target *= (1.0 + _cross_transmission(port_key, cid))
			price_drift[key + "|prev"] = cur
			var next_v := EconMath.mean_revert(cur, target, DRIFT_SPEED)
			next_v += EconMath.seeded_noise([hash(port_key), int(hash(String(cid))), week], DRIFT_NOISE)
			next_v = clampf(next_v, DRIFT_MIN, DRIFT_MAX)
			price_drift[key] = next_v
			var hist: Array = price_history.get(key, [])
			hist.append(int(round(next_v * 1000.0)))
			while hist.size() > HISTORY_WEEKS:
				hist.pop_front()
			price_history[key] = hist
	return events_out

## 是否有上周对比数据（首周没有）
func has_price_history(port_key: String, cid: StringName) -> bool:
	return price_drift.has(_drift_key(port_key, cid) + "|prev")

## 价格涨跌（相对上周）
func price_change_pct(port_key: String, cid: StringName) -> float:
	var cur := price_drift_of(port_key, cid)
	var key := _drift_key(port_key, cid)
	var prev := float(price_drift.get(key + "|prev", cur))
	return EconMath.change_pct(prev, cur)

# ---------------- 多建筑并行升级（1.1.2） ----------------

## 建造中：{建筑 id: {"start": 起始周, "target": 目标等级, "weeks": 工期}}
var building_upgrades: Dictionary = {}

const BUILDING_WEEKS := 2

## 开始升级某建筑（独立计时，互不影响）
func building_start_upgrade(bid: StringName) -> Dictionary:
	var lv := building_level(bid)
	var b: Resource = DataRegistry.get_building(bid) if DataRegistry.has_method("get_building") else null
	var maxlv := int(b.max_level) if b != null else 5
	if lv >= maxlv:
		return {"ok": false, "reason": "已达最高等级"}
	if building_upgrades.has(bid):
		return {"ok": false, "reason": "该建筑正在升级"}
	var cost := 2000 * (lv + 1)
	if gold < cost:
		return {"ok": false, "reason": "金币不足，需要 %d" % cost}
	add_gold(-cost)
	building_upgrades[bid] = {"start": TimeService.total_weeks(), "target": lv + 1, "weeks": BUILDING_WEEKS}
	return {"ok": true, "cost": cost}

## 周结算推进建筑升级
func tick_buildings() -> Array:
	var done: Array = []
	var cur := TimeService.total_weeks()
	var finished: Array = []
	for bid in building_upgrades.keys():
		var rec: Dictionary = building_upgrades[bid]
		if cur - int(rec.get("start", cur)) >= int(rec.get("weeks", BUILDING_WEEKS)):
			buildings[bid] = int(rec.get("target", 1))
			finished.append(bid)
			done.append(String(bid))
	for f in finished:
		building_upgrades.erase(f)
	return done

## 建筑进度文本
func building_progress_text(bid: StringName) -> String:
	if not building_upgrades.has(bid):
		return ""
	var rec: Dictionary = building_upgrades[bid]
	var used := TimeService.total_weeks() - int(rec.get("start", 0))
	return "升级中 %d/%d 周 → Lv%d" % [used, int(rec.get("weeks", 2)), int(rec.get("target", 1))]

# ---------------- 船只改装（1.1） ----------------

## 改装记录：{cannon_slots: int, sail_tier: int}
var ship_mods: Dictionary = {"cannon_slots": 0, "sail_tier": 0}

const MOD_CANNON_COST := [0, 8000, 20000]
const MOD_SAIL_COST := [0, 6000, 15000]

func ship_cannon_bonus() -> int:
	return int(ship_mods.get("cannon_slots", 0)) * 2

func ship_sail_bonus() -> float:
	return float(ship_mods.get("sail_tier", 0)) * 0.06

## 改装火炮位（提升可装炮数与射速）
func mod_cannon() -> Dictionary:
	var lv := int(ship_mods.get("cannon_slots", 0))
	if lv >= 2:
		return {"ok": false, "reason": "火炮位已满"}
	var cost := int(MOD_CANNON_COST[lv + 1])
	if gold < cost:
		return {"ok": false, "reason": "金币不足，需要 %d" % cost}
	add_gold(-cost)
	ship_mods["cannon_slots"] = lv + 1
	return {"ok": true, "level": lv + 1, "cost": cost}

## 改装帆具（提升航速）
func mod_sail() -> Dictionary:
	var lv := int(ship_mods.get("sail_tier", 0))
	if lv >= 2:
		return {"ok": false, "reason": "帆具已满"}
	var cost := int(MOD_SAIL_COST[lv + 1])
	if gold < cost:
		return {"ok": false, "reason": "金币不足，需要 %d" % cost}
	add_gold(-cost)
	ship_mods["sail_tier"] = lv + 1
	return {"ok": true, "level": lv + 1, "cost": cost}

# ---------------- 船员职级与装备强化（1.1） ----------------

const CREW_RANKS := ["水手", "舵手", "炮长", "大副"]
const CREW_RANK_BONUS := [0.0, 0.05, 0.10, 0.15]

## 船员经验与职级：按 crew_id 记录
var crew_xp: Dictionary = {}

func crew_rank_of(cid: StringName) -> int:
	var xp := int(crew_xp.get(cid, 0))
	if xp >= 600:
		return 3
	if xp >= 300:
		return 2
	if xp >= 100:
		return 1
	return 0

func crew_rank_name(cid: StringName) -> String:
	return String(CREW_RANKS[crew_rank_of(cid)])

## 参战后给全部在岗船员加经验
func crew_gain_xp(amount: int) -> void:
	for key in crew_xp.keys():
		crew_xp[key] = int(crew_xp[key]) + amount

## 装备强化：消耗金币与材料，属性按强化等级提升
const GEAR_UPGRADE_COST := {1: 2000, 2: 5000, 3: 12000}
const GEAR_UPGRADE_MAT := {1: 2, 2: 4, 3: 8}
var gear_level: Dictionary = {}

func gear_level_of(gid: StringName) -> int:
	return int(gear_level.get(String(gid), 0))

func gear_upgrade(gid: StringName) -> Dictionary:
	var lv := gear_level_of(gid)
	if lv >= 3:
		return {"ok": false, "reason": "已达最高强化等级"}
	var cost := int(GEAR_UPGRADE_COST.get(lv + 1, 99999))
	var mat_n := int(GEAR_UPGRADE_MAT.get(lv + 1, 99))
	if gold < cost:
		return {"ok": false, "reason": "金币不足，需要 %d" % cost}
	if int(warehouse.get(&"iron_ore", 0)) < mat_n:
		return {"ok": false, "reason": "铁矿不足，需要 %d" % mat_n}
	add_gold(-cost)
	warehouse[&"iron_ore"] = int(warehouse.get(&"iron_ore", 0)) - mat_n
	gear_level[String(gid)] = lv + 1
	return {"ok": true, "level": lv + 1, "cost": cost}

## 装备合成：同部位三件同级合成一件高一级
func gear_combine(slot: StringName, rarity: int) -> Dictionary:
	var candidates: Array = []
	for g in gear_owned:
		var gd: Resource = DataRegistry.get_gear(g)
		if gd != null and String(gd.slot) == String(slot) and int(gd.rarity) == rarity:
			candidates.append(g)
	if candidates.size() < 3:
		return {"ok": false, "reason": "同部位同稀有度装备不足 3 件"}
	for i in range(3):
		gear_owned.erase(candidates[i])
	var pool: Array = []
	for k in DataRegistry.gear.keys():
		var gd2: Resource = DataRegistry.gear[k]
		if gd2 != null and String(gd2.slot) == String(slot) and int(gd2.rarity) == rarity + 1:
			pool.append(k)
	if pool.is_empty():
		gear_owned.append(candidates[0])
		return {"ok": false, "reason": "没有更高一级的同类装备"}
	var new_id: StringName = pool[RngService.randi_range(0, pool.size() - 1)]
	gear_owned.append(new_id)
	return {"ok": true, "new_id": new_id}

# ---------------- 城镇建筑与开局资源（1.2.0） ----------------

const TownPanelLib = preload("res://scripts/ui/town_panel.gd")

## 开局启动资源（够建两三座建筑）
const START_RES = {
	"gold": 8000, "timber": 300, "iron": 120, "stone": 150, "grain": 100,
}

## 按城镇规则初始化建筑等级
func init_town_buildings(is_home: bool, tier: int) -> void:
	var ids: Array = TownPanelLib.initial_buildings(is_home, tier)
	for bid in ids:
		if not buildings.has(bid):
			buildings[bid] = 1
	if not is_home:
		# 其他岛屿：按等级给更完整的建筑等级
		for b in TownPanelLib.buildings_for_tier(tier):
			buildings[StringName(String(b.id))] = maxi(1, tier - 1)

## 发放开局资源
func grant_start_resources() -> void:
	add_gold(int(START_RES["gold"]))
	for cid in [&"timber", &"iron_ore", &"stone", &"wheat"]:
		var key := String(cid)
		var amount := 0
		if key == "timber":
			amount = int(START_RES["timber"])
		elif key == "iron_ore":
			amount = int(START_RES["iron"])
		elif key == "stone":
			amount = int(START_RES["stone"])
		else:
			amount = int(START_RES["grain"])
		cargo[cid] = int(cargo.get(cid, 0)) + amount

## 某建筑是否已建（等级 ≥ 1）
func has_building(bid: StringName) -> bool:
	return building_level(bid) >= 1

# ---------------- 商品分类与建造（1.1） ----------------

const CATEGORIES := ["food", "raw", "consumer", "military", "precious"]
const CATEGORY_NAMES := {
	"food": "食物", "raw": "原材料", "consumer": "消费品",
	"military": "军用品", "precious": "贵金属",
}

## 按大类返回商品 id 列表
func commodities_of(cat: String) -> Array:
	var out: Array = []
	for k in DataRegistry.commodities.keys():
		var c: Resource = DataRegistry.commodities[k]
		if c != null and String(c.category) == cat:
			out.append(k)
	return out

## 全部商品 id
func all_commodities() -> Array:
	return DataRegistry.commodities.keys()

## 生产配方：成品 -> {输入:{材料:数量}, 设施}
const RECIPES := {
	&"cloth": {"in": {&"cotton": 2}, "facility": "工坊"},
	&"pottery": {"in": {&"clay": 2}, "facility": "工坊"},
	&"tools": {"in": {&"iron_ore": 2, &"timber": 1}, "facility": "工坊"},
	&"beer": {"in": {&"wheat": 3}, "facility": "工坊"},
	&"rum": {"in": {&"sugarcane": 3}, "facility": "工坊"},
	&"musket": {"in": {&"iron_ore": 2, &"timber": 2}, "facility": "工坊（军械）"},
	&"cannon_goods": {"in": {&"iron_ore": 3, &"copper": 2}, "facility": "工坊（军械）"},
	&"ammo_goods": {"in": {&"iron_ore": 1, &"saltpeter": 1}, "facility": "工坊（军械）"},
}

## 关税分档（按最高阵营声望）
func tariff_rate() -> float:
	var r := best_rep()
	if r < 2000:
		return 0.10
	if r < 5000:
		return 0.05
	if r < 8000:
		return 0.03
	return 0.01

## 城镇命名：前缀 + 等级后缀
func town_suffix(tier: int) -> String:
	match tier:
		1: return "港村"
		2: return "港镇"
		3: return "港城"
	return "港村"

func town_name(prefix: String, tier: int) -> String:
	return prefix + town_suffix(tier)

## 建造需求（材料 + 金币）
const BUILD_COSTS := {
	1: {&"timber": 200, &"stone": 120, &"iron_ore": 80, "gold": 5000},
	2: {&"timber": 500, &"stone": 400, &"iron_ore": 300, &"cloth": 100, "gold": 20000},
}

## 已提交的建造材料：{港口: {材料: 数量}}
var build_submitted: Dictionary = {}

func build_need(tier: int) -> Dictionary:
	return BUILD_COSTS.get(tier, {})

func build_submit(port_key: String, mat: StringName, amount: int) -> void:
	if amount <= 0:
		return
	if not build_submitted.has(port_key):
		build_submitted[port_key] = {}
	var cur := int(build_submitted[port_key].get(mat, 0))
	build_submitted[port_key][mat] = cur + amount

func build_progress(port_key: String, tier: int) -> Dictionary:
	var need := build_need(tier)
	var have: Dictionary = build_submitted.get(port_key, {})
	var ok := true
	for m in need.keys():
		if int(have.get(m, 0)) < int(need[m]):
			ok = false
	return {"need": need, "have": have, "ready": ok}

## 投资：从现金或存款扣款
## source: "cash" 或 "deposit"
func invest_from(source: String, key: String, amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "reason": "金额必须大于 0"}
	if source == "deposit":
		if bank_deposit < amount:
			return {"ok": false, "reason": "存款不足"}
		bank_deposit -= amount
		# 存款减少后，贷款额度约束可能失效，这里只做余额重算
	else:
		if gold < amount:
			return {"ok": false, "reason": "现金不足"}
		add_gold(-amount)
	var cur := int(island_investment.get(key, 0))
	island_investment[key] = cur + amount
	return {"ok": true, "invested": amount, "total": cur + amount}

## 生产设施周产出：按配方把原料加工为成品（港口仓库侧）
## 返回 {产出:{材料:数量}, 消耗:{材料:数量}}
func tick_production(port_key: String) -> Dictionary:
	var out: Dictionary = {}
	var used: Dictionary = {}
	# 轮转加工：每轮每个配方最多做 1 批，避免先到先得把原料吃光
	# 平衡：每周加工批次上限 = 工坊等级（0 级不可加工），最低 1
	var workshop := building_level(&"sawmill")
	var max_batches := maxi(1, workshop)
	var batches := 0
	var progressed := true
	var guard := 0
	while progressed and guard < 64 and batches < max_batches:
		progressed = false
		guard += 1
		for cid in RECIPES.keys():
			var rec: Dictionary = RECIPES[cid]
			var inputs: Dictionary = rec.get("in", {})
			var can := true
			for m in inputs.keys():
				if int(warehouse.get(m, 0)) < maxi(1, int(inputs[m])):
					can = false
					break
			if not can:
				continue
			for m2 in inputs.keys():
				var need2 := maxi(1, int(inputs[m2]))
				warehouse[m2] = maxi(0, int(warehouse.get(m2, 0)) - need2)
				used[m2] = int(used.get(m2, 0)) + need2
			warehouse[cid] = int(warehouse.get(cid, 0)) + 1
			out[cid] = int(out.get(cid, 0)) + 1
			progressed = true
			batches += 1
	return {"产出": out, "消耗": used}

# ---------------- 银行（0.12 / 0.12.1 多笔贷款） ----------------

const DEPOSIT_RATE := 0.001
const LOAN_TIERS := [1000, 5000, 20000, 50000, 100000]
const LOAN_TERMS := {
	1000: [12, 26],
	5000: [12, 26, 52],
	20000: [26, 52],
	50000: [26, 52],
	100000: [52],
}
const TERM_RATES := {12: 0.002, 26: 0.003, 52: 0.005}
const MAX_LOANS := 6

var bank_deposit := 0
var loans: Array = []

func loan_active() -> bool:
	return not loans.is_empty()

func loan_count() -> int:
	return loans.size()

func loan_interest_for(amount: int, weeks: int) -> int:
	var rate := float(TERM_RATES.get(weeks, 0.0))
	return int(round(float(amount) * rate * float(weeks)))

## 未还本息总额：Σ(本金 + 该笔剩余未付利息)
func loan_exposure() -> int:
	var total := 0
	for l in loans:
		total += int(l.get("amount", 0))
		total += maxi(0, int(l.get("itotal", 0)) - int(l.get("ipaid", 0)))
	return total

func bank_credit() -> int:
	return bank_deposit

func bank_deposited() -> int:
	return bank_deposit

func can_take_loan(amount: int, weeks: int) -> Dictionary:
	if not LOAN_TERMS.has(amount):
		return {"ok": false, "reason": "不支持的贷款金额"}
	if not (LOAN_TERMS[amount] as Array).has(weeks):
		return {"ok": false, "reason": "该金额不支持此期限"}
	if loans.size() >= MAX_LOANS:
		return {"ok": false, "reason": "最多同时持有 %d 笔贷款" % MAX_LOANS}
	if bank_deposit <= 0:
		return {"ok": false, "reason": "需先有存款才能贷款"}
	var add := amount + loan_interest_for(amount, weeks)
	if loan_exposure() + add > bank_deposit:
		return {"ok": false, "reason": "本息总额超出存款额（当前 %d + 本次 %d > 存款 %d）" % [
			loan_exposure(), add, bank_deposit]}
	return {"ok": true}

func bank_borrow(amount: int, weeks: int) -> Dictionary:
	var chk := can_take_loan(amount, weeks)
	if not bool(chk.get("ok", false)):
		return chk
	var itotal := loan_interest_for(amount, weeks)
	loans.append({
		"id": "loan_%d_%d" % [Time.get_ticks_usec(), loans.size()],
		"amount": amount, "weeks": weeks, "rate": float(TERM_RATES[weeks]),
		"left": weeks, "itotal": itotal, "ipaid": 0, "month": 0,
	})
	add_gold(amount)
	return {"ok": true, "interest": itotal}

## 单笔月付息额
func loan_monthly_due(l: Dictionary) -> int:
	if int(l.get("left", 0)) <= 0:
		return 0
	var per := int(round(float(l.get("amount", 0)) * float(l.get("rate", 0.0)) * 4.0))
	return mini(per, maxi(0, int(l.get("itotal", 0)) - int(l.get("ipaid", 0))))

func _loan_settle_amount(l: Dictionary) -> int:
	var elapsed := int(l.get("weeks", 0)) - int(l.get("left", 0))
	var due_int := int(round(float(l.get("amount", 0)) * float(l.get("rate", 0.0)) * float(maxi(0, elapsed))))
	return int(l.get("amount", 0)) + maxi(0, due_int - int(l.get("ipaid", 0)))

func bank_repay_one(index: int) -> Dictionary:
	if index < 0 or index >= loans.size():
		return {"ok": false, "reason": "无效贷款"}
	var l: Dictionary = loans[index]
	var owe := _loan_settle_amount(l)
	if gold < owe:
		return {"ok": false, "reason": "现金不足，需要 %d" % owe}
	add_gold(-owe)
	loans.remove_at(index)
	return {"ok": true, "paid": owe}

func bank_repay_all() -> Dictionary:
	if loans.is_empty():
		return {"ok": false, "reason": "没有未还贷款"}
	var total := 0
	for l in loans:
		total += _loan_settle_amount(l)
	if gold < total:
		return {"ok": false, "reason": "现金不足，需要 %d" % total}
	add_gold(-total)
	loans.clear()
	return {"ok": true, "paid": total}

func bank_deposit_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	add_gold(-amount)
	bank_deposit += amount
	return true

func bank_withdraw(amount: int) -> bool:
	if amount <= 0 or amount > bank_deposit:
		return false
	bank_deposit -= amount
	add_gold(amount)
	return true

func bank_bankrupt() -> void:
	bank_deposit = 0
	gold = 0
	reputation["royal_navy"] = 0
	reputation["notoriety"] = mini(100, notoriety() + 60)
	loans.clear()

func bank_tick_week() -> Array:
	var events: Array = []
	if bank_deposit > 0 and TimeService.total_weeks() % 4 == 0:
		var interest := int(round(float(bank_deposit) * DEPOSIT_RATE * 4.0))
		if interest > 0:
			bank_deposit += interest
			events.append({"type": "deposit_interest", "amount": interest})
	if loans.is_empty():
		return events
	var kept: Array = []
	for l in loans:
		l["month"] = int(l.get("month", 0)) + 1
		l["left"] = int(l.get("left", 1)) - 1
		if int(l["month"]) >= 4:
			l["month"] = 0
			var due := loan_monthly_due(l)
			if due > 0:
				if gold < due:
					bank_bankrupt()
					events.append({"type": "bankrupt", "reason": "interest"})
					return events
				add_gold(-due)
				l["ipaid"] = int(l.get("ipaid", 0)) + due
				events.append({"type": "loan_interest", "amount": due})
		if int(l["left"]) <= 0:
			var remain := int(l.get("amount", 0)) + maxi(0, int(l.get("itotal", 0)) - int(l.get("ipaid", 0)))
			if gold < remain:
				bank_bankrupt()
				events.append({"type": "bankrupt", "reason": "maturity"})
				return events
			add_gold(-remain)
			events.append({"type": "loan_repaid", "amount": remain})
			continue
		kept.append(l)
	loans = kept
	return events

# ---------------- 黑市 ----------------

## 违禁品：id -> {名称, 价格, 说明}
const CONTRABAND := {
	&"stimulant": {"name": "违禁药物", "price": 2400, "desc": "下场战斗船员状态 +20%（有副作用）"},
	&"forge_flag": {"name": "伪造旗帜", "price": 3600, "desc": "下场战斗敌方索敌半径 -50%"},
	&"forge_pass": {"name": "伪造通行证", "price": 5200, "desc": "一次通缉度免检（不触发赏金猎人）"},
	&"navy_gear": {"name": "海军制式火炮", "price": 8800, "desc": "非海军身份无法正规获得的高级装备"},
}

const BLACK_FENCE_RATE := 0.60       # 销赃收购价倍率
const BLACK_SELL_LIMIT := 200       # 单次销赃上限
const BLACK_LICENSE_MULT := 2.5     # 黑市私掠证价格倍数
const BLACK_LICENSE_NOTORIETY := 5  # 黑市买证的通缉度代价
const LEGAL_LICENSE_REP := 3000     # 正规私掠证所需海军声望

var contraband: Dictionary = {}     # 违禁品库存
var has_privateer_license := false
var license_is_legal := false       # true = 正规途径购得
var black_closed_week := -1         # 被海军盯上而关闭的周

## 黑市是否开放：通缉度 ≥ 80 时关闭一周
func black_market_open() -> bool:
	if notoriety() < 80:
		return true
	return TimeService.total_weeks() > black_closed_week

func _black_mark_activity() -> void:
	reputation["notoriety"] = mini(100, notoriety() + 2)

## 销赃：返回获得的金币
func fence_goods(cid: StringName, amount: int, base_sell: int) -> Dictionary:
	if not black_market_open():
		return {"ok": false, "reason": "黑市暂闭"}
	var have := int(cargo.get(cid, 0))
	var real := mini(amount, mini(have, BLACK_SELL_LIMIT))
	if real <= 0:
		return {"ok": false, "reason": "货舱里没有该商品"}
	remove_cargo(cid, real)
	var gain := int(round(float(base_sell) * BLACK_FENCE_RATE)) * real
	add_gold(gain)
	_black_mark_activity()
	return {"ok": true, "gold": gain, "amount": real}

## 购买违禁品
func buy_contraband(item_id: StringName) -> Dictionary:
	var def: Dictionary = CONTRABAND.get(item_id, {})
	if def.is_empty():
		return {"ok": false, "reason": "未知物品"}
	if not black_market_open():
		return {"ok": false, "reason": "黑市暂闭"}
	var price := int(def.get("price", 0))
	if gold < price:
		return {"ok": false, "reason": "金币不足"}
	add_gold(-price)
	contraband[item_id] = int(contraband.get(item_id, 0)) + 1
	_black_mark_activity()
	return {"ok": true, "price": price}

## 购买私掠许可证（黑市途径）
func buy_license_black() -> Dictionary:
	if has_privateer_license:
		return {"ok": false, "reason": "已经持有私掠许可证"}
	if not black_market_open():
		return {"ok": false, "reason": "黑市暂闭"}
	var price := int(round(float(LEGAL_LICENSE_REP) * BLACK_LICENSE_MULT * 10.0))
	if gold < price:
		return {"ok": false, "reason": "金币不足，需要 %d" % price}
	add_gold(-price)
	has_privateer_license = true
	license_is_legal = false
	reputation["notoriety"] = mini(100, notoriety() + BLACK_LICENSE_NOTORIETY)
	return {"ok": true, "price": price}

## 购买私掠许可证（正规途径：声望交易）
func buy_license_legal() -> Dictionary:
	if has_privateer_license:
		return {"ok": false, "reason": "已经持有私掠许可证"}
	if rep_of("royal_navy") < LEGAL_LICENSE_REP:
		return {"ok": false, "reason": "海军声望不足（需要 %d）" % LEGAL_LICENSE_REP}
	var price := LEGAL_LICENSE_REP * 2
	if gold < price:
		return {"ok": false, "reason": "金币不足，需要 %d" % price}
	add_gold(-price)
	has_privateer_license = true
	license_is_legal = true
	return {"ok": true, "price": price}

# ---------------- 拍卖行 ----------------

var auctions: Array = []        # 当前挂单
var auction_week := -1          # 上次刷新的周
var auction_defects := 0        # 违约次数（拍下后资金不足）

## 每周刷新：挂单清空后补 3~5 件
func refresh_auctions(week: int) -> void:
	if auction_week == week:
		return
	auction_week = week
	if not auctions.is_empty():
		return
	var n := RngService.randi_range(3, 5)
	auctions = AuctionFactory.generate(n, level)

## 玩家出价：必须 ≥ 当前价 × 1.05
func bid_auction(index: int, price: int) -> Dictionary:
	if index < 0 or index >= auctions.size():
		return {"ok": false, "reason": "无效货品"}
	var lot: Dictionary = auctions[index]
	var cur := int(lot.get("price", 0))
	var need := int(ceil(float(cur) * 1.05))
	if price < need:
		return {"ok": false, "reason": "出价需至少 %d" % need}
	if gold < price:
		return {"ok": false, "reason": "金币不足"}
	lot["price"] = price
	lot["leader"] = "player"
	return {"ok": true, "price": price}

## 每周：NPC 加价 → 倒计时 → 到期结算
func tick_auctions(npc_bid_enabled: bool = true) -> Array:
	var events: Array = []
	var kept: Array = []
	for lot in auctions:
		var kind := String(lot.get("kind", ""))
		if not lot.has("leader"):
			lot["leader"] = ""
		# NPC 加价（40% 概率，+8%~15%）
		if npc_bid_enabled:
			if RngService.chance(0.4):
				var old := int(lot.get("price", 0))
				var bump := old + int(round(float(old) * RngService.randf_range(0.08, 0.15)))
				lot["price"] = bump
				lot["leader"] = "npc"
				events.append({"type": "npc_bid", "name": String(lot.get("name", "")), "price": bump})
		lot["weeks"] = int(lot.get("weeks", 2)) - 1
		if int(lot["weeks"]) > 0:
			kept.append(lot)
			continue
		# 到期结算
		if String(lot.get("leader", "")) != "player":
			events.append({"type": "lost", "name": String(lot.get("name", ""))})
			continue
		var price := int(lot.get("price", 0))
		if gold < price:
			auction_defects += 1
			events.append({"type": "default", "name": String(lot.get("name", ""))})
			continue
		if kind == "ship" or kind == "magic":
			if ships_owned.size() + 1 > storage_slots():
				kept.append(lot)   # 船位不足，保留到下周
				lot["weeks"] = 1
				events.append({"type": "no_slot", "name": String(lot.get("name", ""))})
				continue
			add_gold(-price)
			add_owned_ship(StringName(lot.get("def_id", String(START_SHIP))),
				StringName(lot.get("variant", "standard")), price)
			events.append({"type": "won", "name": String(lot.get("name", "")), "price": price})
		elif kind == "gear":
			add_gold(-price)
			for g in lot.get("gear", []):
				gear_owned.append(StringName(g))
			events.append({"type": "won", "name": String(lot.get("name", "")), "price": price})
		elif kind == "crew":
			var cid := StringName(lot.get("crew_id", ""))
			if cid != &"":
				var roster: Array = CrewFactory.generate(1, ship_variant)
				if not roster.is_empty():
					var c: Resource = roster[0]
					c.rarity = 3
					add_gold(-price)
					hire_crew(c)
					events.append({"type": "won", "name": String(c.display_name), "price": price})
	auctions = kept
	return events

# ---------------- 岛屿投资与商品产地 ----------------

## 商品产地：origin = 最早出现的地图编号；range = 产出地图区间（含）
const COMMODITY_ORIGIN := {
	&"grain": {"origin": 1, "range": [1, 9]},
	&"timber": {"origin": 1, "range": [1, 9]},
	&"rum": {"origin": 1, "range": [1, 4]},
	&"spice": {"origin": 5, "range": [5, 9]},
}

const ISLAND_INVEST_TIERS := [0, 5000, 20000, 60000, 150000]
const ISLAND_DISCOUNTS := [0, 10, 20, 35, 50]
const ISLAND_UPGRADE_WEEKS := 52

var island_investment: Dictionary = {}     # key -> 累计投资额
var island_upgrade_start: Dictionary = {}  # key -> 满额时的周序号
var island_tier: Dictionary = {}           # key -> 当前聚落等级（1/2/3）
var port_registry: Dictionary = {}         # key -> {"name","map","tier"} 供世界市场使用

func commodity_origin_tier(cid: StringName) -> int:
	var d: Dictionary = COMMODITY_ORIGIN.get(cid, {})
	return int(d.get("origin", 1))

func commodity_produced_in(cid: StringName, map_index: int) -> bool:
	var d: Dictionary = COMMODITY_ORIGIN.get(cid, {})
	if d.is_empty():
		return true
	var rng: Array = d.get("range", [1, 9])
	return map_index >= int(rng[0]) and map_index <= int(rng[1])

## 售出倍率：目标地图不产出才有跨度溢价
func sale_multiplier_at(cid: StringName, map_index: int) -> float:
	var produced := commodity_produced_in(cid, map_index)
	var gap: int = maxi(0, map_index - commodity_origin_tier(cid))
	return MarketModel.sale_multiplier(produced, gap)

func island_key(map_index: int, idx: int) -> String:
	return "m%d_%d" % [map_index, idx]

## 海域生成时登记港口元信息（世界市场靠它显示名称与位置）
func register_port(key: String, name: String, map_index: int, tier: int) -> void:
	port_registry[key] = {"name": name, "map": map_index, "tier": tier}

func island_tier_of(key: String, fallback: int) -> int:
	return clampi(int(island_tier.get(key, fallback)), 1, 3)

func island_set_tier(key: String, tier: int) -> void:
	island_tier[key] = clampi(tier, 1, 3)

func island_invested(key: String) -> int:
	return int(island_investment.get(key, 0))

## 投资等级 1~5
func island_level(key: String) -> int:
	var v := island_invested(key)
	var lv := 1
	for i in range(ISLAND_INVEST_TIERS.size()):
		if v >= int(ISLAND_INVEST_TIERS[i]):
			lv = i + 1
	return clampi(lv, 1, 5)

## 投资折扣：连续曲线，150,000 处达到上限 50%
const INVEST_CAP := 150000.0
const INVEST_K := 1.6
const INVEST_MAX_DISCOUNT := 50.0

func island_discount(key: String) -> int:
	var invested := float(int(island_investment.get(key, 0)))
	return int(round(EconMath.diminishing_discount(invested, INVEST_CAP, INVEST_MAX_DISCOUNT, INVEST_K)))

## 边际回报（百分比/千金）
func island_marginal_discount(key: String) -> float:
	var invested := float(int(island_investment.get(key, 0)))
	return EconMath.marginal_discount(invested, INVEST_CAP, INVEST_MAX_DISCOUNT, INVEST_K, 1000.0)

func island_next_threshold(key: String) -> int:
	var lv := island_level(key)
	if lv >= 5:
		return int(ISLAND_INVEST_TIERS[4])
	return int(ISLAND_INVEST_TIERS[lv])

## 注资
func invest_island(key: String, gold: int) -> bool:
	if gold <= 0 or self.gold < gold:
		return false
	add_gold(-gold)
	island_investment[key] = island_invested(key) + gold
	_maybe_start_island_upgrade(key)
	return true

## 市场成交额按 10% 转化为投资额（不扣钱）
func credit_island_trade(key: String, turnover: int) -> void:
	if turnover <= 0:
		return
	var inc := int(turnover * 0.10)
	if inc <= 0:
		return
	island_investment[key] = island_invested(key) + inc
	_maybe_start_island_upgrade(key)

## 投资满额（Lv5）且聚落未到城市 → 开始 52 周升格计时
func _maybe_start_island_upgrade(key: String) -> void:
	if island_upgrade_start.has(key):
		return
	if island_level(key) < 5:
		return
	var tier := int(island_tier.get(key, 1))
	if tier >= 3:
		return
	island_upgrade_start[key] = TimeService.total_weeks()

## 周推进：满了 52 周就升格并清零
func tick_island_upgrades() -> Array:
	var done: Array = []
	for key in island_upgrade_start.keys():
		var start := int(island_upgrade_start[key])
		if TimeService.total_weeks() - start < ISLAND_UPGRADE_WEEKS:
			continue
		var tier := clampi(int(island_tier.get(key, 1)) + 1, 1, 3)
		island_tier[key] = tier
		island_investment[key] = 0
		island_upgrade_start.erase(key)
		done.append(key)
	return done

## 升格进度（周）；没有在计时返回 null
func island_upgrade_progress(key: String):
	if not island_upgrade_start.has(key):
		return null
	var elapsed: int = TimeService.total_weeks() - int(island_upgrade_start[key])
	return {"elapsed": clampi(elapsed, 0, ISLAND_UPGRADE_WEEKS), "total": ISLAND_UPGRADE_WEEKS}

# ---------------- 港口服务分级 ----------------

const PORT_NAMES := {1: "渔港村落", 2: "乡镇", 3: "港口城市"}
## 服务 → 解锁所需等级
const PORT_SERVICES := {
	"repair": 1, "market": 1, "tavern": 1, "quests": 1, "shiptrade": 1,
	"shipyard": 2, "building": 2,
	"exchange": 3, "reputation": 3,
}
## 母港升级条件
const PORT_UPGRADE_COST := {
	2: {"gold": 5000, "timber": 100, "iron": 50},
	3: {"gold": 30000, "timber": 400, "iron": 200},
}

func port_name(tier: int) -> String:
	return String(PORT_NAMES.get(clampi(tier, 1, 3), "港口"))

func port_service_unlocked(tier: int, service: String) -> bool:
	return clampi(tier, 1, 3) >= int(PORT_SERVICES.get(service, 1))

func home_port_name() -> String:
	return port_name(home_port_tier)

## 当前港口的某项服务是否可用（母港用 home_port_tier）
func home_has(service: String) -> bool:
	return port_service_unlocked(home_port_tier, service)

## 下一级升级条件；已满级返回空字典
func home_upgrade_cost() -> Dictionary:
	return PORT_UPGRADE_COST.get(home_port_tier + 1, {})

func can_upgrade_home_port() -> bool:
	var cost := home_upgrade_cost()
	if cost.is_empty():
		return false
	if gold < int(cost.get("gold", 0)):
		return false
	if int(resources.get("timber", 0)) < int(cost.get("timber", 0)):
		return false
	if int(resources.get("iron", 0)) < int(cost.get("iron", 0)):
		return false
	return true

func upgrade_home_port() -> bool:
	if not can_upgrade_home_port():
		return false
	var cost := home_upgrade_cost()
	add_gold(-int(cost.get("gold", 0)))
	resources["timber"] = maxi(0, int(resources.get("timber", 0)) - int(cost.get("timber", 0)))
	resources["iron"] = maxi(0, int(resources.get("iron", 0)) - int(cost.get("iron", 0)))
	home_port_tier = clampi(home_port_tier + 1, 1, 3)
	return true

# ---------------- 岛屿采集 ----------------

func island_stock_of(key: String, default_value: int) -> int:
	return int(island_stock.get(key, default_value))

func set_island_stock(key: String, value: int) -> void:
	island_stock[key] = maxi(0, value)

## 周结算：所有岛屿储量回复，最多回到上限
func regen_islands(cap: int, add_per_week: int) -> void:
	for k in island_stock.keys():
		island_stock[k] = mini(cap, int(island_stock[k]) + add_per_week)

# ---------------- 港口仓库 ----------------

func warehouse_capacity() -> int:
	return 800 + 400 * building_level(&"warehouse")

func warehouse_used() -> float:
	var used := 0.0
	for id in warehouse.keys():
		var c := DataRegistry.get_commodity(id)
		if c != null:
			used += float(c.volume) * float(warehouse[id])
	return used

func warehouse_free() -> float:
	return maxf(0.0, float(warehouse_capacity()) - warehouse_used())

func warehouse_add(id: StringName, amount: int) -> int:
	var c := DataRegistry.get_commodity(id)
	if c == null or amount <= 0:
		return 0
	var can := int(floor(warehouse_free() / float(c.volume)))
	var real := mini(amount, can)
	if real > 0:
		warehouse[id] = int(warehouse.get(id, 0)) + real
		EventBus.cargo_changed.emit(cargo_used(), cargo_capacity())
	return real

func warehouse_remove(id: StringName, amount: int) -> int:
	var have := int(warehouse.get(id, 0))
	var real := mini(amount, have)
	if real > 0:
		warehouse[id] = have - real
		if int(warehouse[id]) <= 0:
			warehouse.erase(id)
		EventBus.cargo_changed.emit(cargo_used(), cargo_capacity())
	return real

## 指定船型的载重（用于换船前的容量校验）
func cargo_capacity_of(def_id: StringName, variant: StringName) -> int:
	var d: Resource = DataRegistry.get_ship(def_id)
	if d == null:
		return 200
	return int(StatsLib.compute(d, variant, equipped, assigned_crews()).get("cargo_capacity", 200))

## 换乘到 ships_owned[index] 是否装不下当前货物
func swap_overload(index: int) -> bool:
	if index < 0 or index >= ships_owned.size():
		return false
	var other: Dictionary = ships_owned[index]
	var cap := cargo_capacity_of(StringName(other.get("def_id", "")), StringName(other.get("variant", "standard")))
	return cargo_used() > float(cap)

func add_gold(delta: int) -> void:
	gold = max(0, gold + delta)
	EventBus.gold_changed.emit(gold)

func add_cargo(id: StringName, amount: int) -> int:
	## 返回实际入库数量（受载重限制）
	var c := DataRegistry.get_commodity(id)
	if c == null or amount <= 0:
		return 0
	var free := cargo_free()
	var per := float(c.volume)
	var can := int(floor(free / per))
	var real := mini(amount, can)
	if real > 0:
		cargo[id] = int(cargo.get(id, 0)) + real
		EventBus.cargo_changed.emit(cargo_used(), cargo_capacity())
	return real

func remove_cargo(id: StringName, amount: int) -> int:
	var have := int(cargo.get(id, 0))
	var real := mini(amount, have)
	if real > 0:
		cargo[id] = have - real
		if int(cargo[id]) <= 0:
			cargo.erase(id)
		EventBus.cargo_changed.emit(cargo_used(), cargo_capacity())
	return real

# ---------------- 港口库存 ----------------

func get_stock(port_id: StringName, commodity_id: StringName) -> int:
	var p: Dictionary = port_stock.get(port_id, {})
	return int(p.get(commodity_id, -1))

func ensure_stock(port_id: StringName, commodity_id: StringName, max_stock: int) -> int:
	var p: Dictionary = port_stock.get(port_id, {})
	if not p.has(commodity_id):
		p[commodity_id] = int(round(float(max_stock) * 0.5))
		port_stock[port_id] = p
	return int(p[commodity_id])

func set_stock(port_id: StringName, commodity_id: StringName, value: int) -> void:
	var p: Dictionary = port_stock.get(port_id, {})
	p[commodity_id] = maxi(0, value)
	port_stock[port_id] = p

func ensure_ship() -> void:
	var d := ship_def()
	if d == null:
		ship_def_id = START_SHIP
		d = ship_def()
	hull_hp = clampf(hull_hp if hull_hp >= 0.0 else hull_max(), 0.0, hull_max())

func to_dict() -> Dictionary:
	return {
		"schema": 1,
		"player": {"name": player_name, "level": level, "xp": xp, "gold": gold, "commendation": commendation},
		"ship": {
			"def": String(ship_def_id), "variant": String(ship_variant), "hull_hp": hull_hp,
			"sail_pct": sail_pct, "rudder_pct": rudder_pct, "crew_pct": crew_pct,
			"equipped": _equipped_to_dict(), "gear": _names_to_strings(gear_owned),
			"cannon": String(cannon_id), "cannons": _names_to_strings(cannons_owned),
			"crew": _crew_to_array(), "crew_assigned": _names_to_strings(crew_assigned),
		},
		"base": {
			"port_tier": home_port_tier,
			"buildings": _buildings_to_dict(), "resources": resources.duplicate(),
			"queue": _queue_to_array(),
		},
		"quests": {"available": _orders_to_array(quests_available), "active": _orders_to_array(quests_active)},
		"exchange": {
			"orders": _orders_to_array(orders), "active": _orders_to_array(active_orders),
			"futures": _orders_to_array(futures),
		},
		"fleet": _fleet_to_array(),
		"cargo": _cargo_to_dict(),
		"warehouse": _cargo_to_dict_of(warehouse),
		"island_stock": island_stock.duplicate(),
		"island_investment": island_investment.duplicate(),
		"island_upgrade_start": island_upgrade_start.duplicate(),
		"island_tier": island_tier.duplicate(),
		"port_registry": port_registry.duplicate(true),
		"contraband": contraband.duplicate(),
		"crew_xp": crew_xp.duplicate(),
		"ship_mods": ship_mods.duplicate(),
		"building_upgrades": building_upgrades.duplicate(true),
		"gear_level": gear_level.duplicate(),
		"build_submitted": build_submitted.duplicate(true),
		"bank": {"deposit": bank_deposit, "loans": loans.duplicate(true)},
		"market": {"drift": price_drift.duplicate(), "events": market_events.duplicate(true),
			"history": price_history.duplicate(true)},
		"fin": {"reports": reports.duplicate(true), "year": report_year,
			"purchases": finance.get("purchases", {}).duplicate(true),
			"sales": finance.get("sales", {}).duplicate(true),
			"income": finance.get("income", {}).duplicate(true),
			"expense": finance.get("expense", {}).duplicate(true)},
		"license": {"has": has_privateer_license, "legal": license_is_legal},
		"black_closed_week": black_closed_week,
		"auctions": auctions.duplicate(true),
		"auction_week": auction_week,
		"auction_defects": auction_defects,
		"world": {
			"current_map": current_map, "pos_x": sea_position.x, "pos_y": sea_position.y,
			"cleared": cleared_maps.duplicate(), "boss": boss_defeated.duplicate(),
		},
		"reputation": reputation.duplicate(),
		"donated_week": donated_week.duplicate(),
		"stats": {"kills": stat_kills, "bosses": stat_bosses, "cleared": game_cleared},
		"port_stock": _nested_to_dict(port_stock),
	}

func _cargo_to_dict_of(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[String(k)] = int(d[k])
	return out

func from_dict(d: Dictionary) -> void:
	var p: Dictionary = d.get("player", {})
	player_name = String(p.get("name", "无名船长"))
	level = int(p.get("level", 1))
	xp = int(p.get("xp", 0))
	gold = int(p.get("gold", START_GOLD))
	commendation = int(p.get("commendation", 0))
	var s: Dictionary = d.get("ship", {})
	ship_def_id = StringName(s.get("def", String(START_SHIP)))
	ship_variant = StringName(s.get("variant", "standard"))
	hull_hp = float(s.get("hull_hp", -1.0))
	equipped.clear()
	var eq: Dictionary = s.get("equipped", {})
	for k in eq.keys():
		equipped[StringName(k)] = StringName(eq[k])
	gear_owned.clear()
	for g in s.get("gear", []):
		gear_owned.append(StringName(g))
	crew_roster.clear()
	for c0 in s.get("crew", []):
		crew_roster.append(CrewDefScript.from_dict(c0))
	crew_assigned.clear()
	for ca in s.get("crew_assigned", []):
		crew_assigned.append(StringName(ca))
	cannon_id = StringName(s.get("cannon", "pound3_light"))
	cannons_owned.clear()
	var co: Array = s.get("cannons", [])
	for c0 in co:
		cannons_owned.append(StringName(c0))
	if cannons_owned.is_empty():
		cannons_owned.append(&"pound3_light")
	ships_owned.clear()
	for entry in d.get("fleet", []):
		var e: Dictionary = entry
		var conv := {
			"def_id": String(e.get("def_id", "fishing_sloop")),
			"variant": String(e.get("variant", "standard")),
			"station_port": String(e.get("station_port", "jadehaven")),
			"hull_hp": float(e.get("hull_hp", -1.0)),
			"sail_pct": float(e.get("sail_pct", 1.0)),
			"rudder_pct": float(e.get("rudder_pct", 1.0)),
			"crew_pct": float(e.get("crew_pct", 1.0)),
			"equipped": {},
			"cannon_id": String(e.get("cannon_id", "pound3_light")),
		}
		var eq2: Dictionary = e.get("equipped", {})
		for k2 in eq2.keys():
			conv.equipped[StringName(k2)] = StringName(eq2[k2])
		ships_owned.append(conv)
	sail_pct = float(s.get("sail_pct", 1.0))
	rudder_pct = float(s.get("rudder_pct", 1.0))
	crew_pct = float(s.get("crew_pct", 1.0))
	island_investment.clear()
	var inv_d: Dictionary = d.get("island_investment", {})
	for k in inv_d.keys():
		island_investment[String(k)] = int(inv_d[k])
	island_upgrade_start.clear()
	var ups_d: Dictionary = d.get("island_upgrade_start", {})
	for k in ups_d.keys():
		island_upgrade_start[String(k)] = int(ups_d[k])
	var mk: Dictionary = d.get("market", {})
	price_drift.clear()
	var dr: Dictionary = mk.get("drift", {})
	for k in dr.keys():
		price_drift[String(k)] = float(dr[k])
	market_events.clear()
	for e0 in mk.get("events", []):
		market_events.append(e0)
	reports.clear()
	var fin: Dictionary = d.get("fin", {})
	for r0 in fin.get("reports", []):
		reports.append(r0)
	report_year = int(fin.get("year", 0))
	finance = {"purchases": fin.get("purchases", {}).duplicate(true),
		"sales": fin.get("sales", {}).duplicate(true),
		"income": fin.get("income", {}).duplicate(true),
		"expense": fin.get("expense", {}).duplicate(true)}
	price_history.clear()
	var hist_d: Dictionary = mk.get("history", {})
	for k in hist_d.keys():
		price_history[String(k)] = hist_d[k]
	var bk: Dictionary = d.get("bank", {})
	bank_deposit = int(bk.get("deposit", 0))
	loans.clear()
	for l0 in bk.get("loans", []):
		loans.append(l0)
	# 旧存档兼容：0.12.0 的单笔贷款字段 → 转成一笔贷款
	if loans.is_empty() and int(bk.get("principal", 0)) > 0:
		loans.append({
			"id": "loan_legacy", "amount": int(bk.get("principal", 0)),
			"weeks": int(bk.get("weeks", 12)), "rate": float(bk.get("rate", 0.002)),
			"left": int(bk.get("left", 12)), "itotal": int(bk.get("itotal", 0)),
			"ipaid": int(bk.get("ipaid", 0)), "month": int(bk.get("month", 0)),
		})
	crew_xp.clear()
	var cxp: Dictionary = d.get("crew_xp", {})
	for k0 in cxp.keys():
		crew_xp[StringName(k0)] = int(cxp[k0])
	building_upgrades.clear()
	var bu: Dictionary = d.get("building_upgrades", {})
	for kb in bu.keys():
		building_upgrades[StringName(kb)] = bu[kb]
	ship_mods = {"cannon_slots": 0, "sail_tier": 0}
	var sm: Dictionary = d.get("ship_mods", {})
	for k3 in sm.keys():
		ship_mods[String(k3)] = int(sm[k3])
	gear_level.clear()
	var glv: Dictionary = d.get("gear_level", {})
	for k1 in glv.keys():
		gear_level[String(k1)] = int(glv[k1])
	build_submitted.clear()
	var bsub: Dictionary = d.get("build_submitted", {})
	for k2 in bsub.keys():
		build_submitted[String(k2)] = bsub[k2]
	contraband.clear()
	var cb: Dictionary = d.get("contraband", {})
	for k in cb.keys():
		contraband[StringName(k)] = int(cb[k])
	var lic: Dictionary = d.get("license", {})
	has_privateer_license = bool(lic.get("has", false))
	license_is_legal = bool(lic.get("legal", false))
	black_closed_week = int(d.get("black_closed_week", -1))
	auctions.clear()
	for a in d.get("auctions", []):
		auctions.append(a)
	auction_week = int(d.get("auction_week", -1))
	auction_defects = int(d.get("auction_defects", 0))
	port_registry.clear()
	var pr: Dictionary = d.get("port_registry", {})
	for k in pr.keys():
		port_registry[String(k)] = pr[k]
	island_tier.clear()
	var tier_d: Dictionary = d.get("island_tier", {})
	for k in tier_d.keys():
		island_tier[String(k)] = int(tier_d[k])
	island_stock.clear()
	var isl_d: Dictionary = d.get("island_stock", {})
	for k in isl_d.keys():
		island_stock[String(k)] = int(isl_d[k])
	warehouse.clear()
	var wh: Dictionary = d.get("warehouse", {})
	for k in wh.keys():
		warehouse[StringName(k)] = int(wh[k])
	cargo.clear()
	var c: Dictionary = d.get("cargo", {})
	for k in c.keys():
		cargo[StringName(k)] = int(c[k])
	var w: Dictionary = d.get("world", {})
	current_map = int(w.get("current_map", 1))
	sea_position = Vector2(float(w.get("pos_x", 0)), float(w.get("pos_y", 0)))
	cleared_maps = w.get("cleared", []).duplicate()
	boss_defeated = w.get("boss", []).duplicate()
	var r: Dictionary = d.get("reputation", {})
	for k in reputation.keys():
		reputation[k] = int(r.get(k, 0))
	var dw: Dictionary = d.get("donated_week", {})
	for f in FACTIONS:
		donated_week[f] = int(dw.get(f, 0))
	var st2: Dictionary = d.get("stats", {})
	stat_kills = int(st2.get("kills", 0))
	stat_bosses = int(st2.get("bosses", 0))
	game_cleared = bool(st2.get("cleared", false))
	var bs: Dictionary = d.get("base", {})
	# 旧存档没有该字段 → 按 Lv3 兼容，避免老玩家被降级
	home_port_tier = clampi(int(bs.get("port_tier", 3)), 1, 3)
	buildings.clear()
	var bld: Dictionary = bs.get("buildings", {})
	for k in bld.keys():
		buildings[StringName(k)] = int(bld[k])
	resources = {"timber": 0, "iron": 0, "grain": 0, "saltpeter": 0}
	var rs: Dictionary = bs.get("resources", {})
	for rkey in resources.keys():
		resources[rkey] = int(rs.get(rkey, 0))
	build_queue.clear()
	for q in bs.get("queue", []):
		build_queue.append({"id": String(q.get("id", "")), "target": int(q.get("target", 1)),
			"weeks_left": int(q.get("weeks_left", 1))})
	var qu: Dictionary = d.get("quests", {})
	quests_available = _orders_to_array(qu.get("available", []))
	quests_active = _orders_to_array(qu.get("active", []))
	var ex: Dictionary = d.get("exchange", {})
	orders = _orders_to_array(ex.get("orders", []))
	active_orders = _orders_to_array(ex.get("active", []))
	futures = _orders_to_array(ex.get("futures", []))
	port_stock.clear()
	var ps: Dictionary = d.get("port_stock", {})
	for pid in ps.keys():
		var inner: Dictionary = ps[pid]
		var conv := {}
		for cid in inner.keys():
			conv[StringName(cid)] = int(inner[cid])
		port_stock[StringName(pid)] = conv
	ensure_ship()

func _orders_to_array(src: Array) -> Array:
	var out: Array = []
	for o in src:
		out.append(o.duplicate())
	return out

func _buildings_to_dict() -> Dictionary:
	var out := {}
	for k in buildings.keys():
		out[String(k)] = int(buildings[k])
	return out

func _queue_to_array() -> Array:
	var out: Array = []
	for q in build_queue:
		out.append({"id": q.get("id", ""), "target": q.get("target", 1), "weeks_left": q.get("weeks_left", 1)})
	return out

func _crew_to_array() -> Array:
	var out: Array = []
	for c in crew_roster:
		out.append(c.to_dict())
	return out

func _equipped_to_dict() -> Dictionary:
	var out := {}
	for k in equipped.keys():
		out[String(k)] = String(equipped[k])
	return out

func _names_to_strings(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(String(v))
	return out

func _fleet_to_array() -> Array:
	var out: Array = []
	for e in ships_owned:
		var entry: Dictionary = e
		var eq := {}
		for k in entry.get("equipped", {}).keys():
			eq[String(k)] = String(entry.equipped[k])
		out.append({
			"def_id": entry.get("def_id", ""), "variant": entry.get("variant", "standard"),
			"station_port": entry.get("station_port", "jadehaven"),
			"hull_hp": entry.get("hull_hp", -1.0), "sail_pct": entry.get("sail_pct", 1.0),
			"rudder_pct": entry.get("rudder_pct", 1.0), "crew_pct": entry.get("crew_pct", 1.0),
			"equipped": eq,
			"cannon_id": entry.get("cannon_id", "pound3_light"),
		})
	return out

func _nested_to_dict(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		var inner: Dictionary = src[k]
		var conv := {}
		for k2 in inner.keys():
			conv[String(k2)] = int(inner[k2])
		out[String(k)] = conv
	return out

func _cargo_to_dict() -> Dictionary:
	var out := {}
	for k in cargo.keys():
		out[String(k)] = int(cargo[k])
	return out

func reset_new_game() -> void:
	gold = START_GOLD
	commendation = 0
	level = 1
	xp = 0
	ship_def_id = START_SHIP
	ship_variant = &"standard"
	hull_hp = -1.0
	sail_pct = 1.0
	rudder_pct = 1.0
	crew_pct = 1.0
	equipped.clear()
	gear_owned.clear()
	crew_roster.clear()
	crew_assigned.clear()
	tavern_pool.clear()
	buildings.clear()
	# 1.2.0：母港开局只带总督府与仓库（启动资源在函数末尾发放，避免被清空）
	resources = {"timber": 0, "iron": 0, "grain": 0, "saltpeter": 0}
	build_queue.clear()
	orders.clear()
	active_orders.clear()
	futures.clear()
	quests_available.clear()
	quests_active.clear()
	cannon_id = &"pound3_light"
	cannons_owned = [&"pound3_light"]
	ships_owned.clear()
	cargo.clear()
	warehouse.clear()
	island_stock.clear()
	island_investment.clear()
	island_upgrade_start.clear()
	island_tier.clear()
	port_registry.clear()
	bank_deposit = 0
	loans.clear()
	price_drift.clear()
	market_events.clear()
	price_history.clear()
	contraband.clear()
	has_privateer_license = false
	license_is_legal = false
	black_closed_week = -1
	auctions.clear()
	auction_week = -1
	auction_defects = 0
	home_port_tier = 1
	current_map = 1
	sea_position = Vector2.ZERO
	cleared_maps.clear()
	boss_defeated.clear()
	for k in reputation.keys():
		reputation[k] = 0
	donated_week = {"royal_navy": 0, "merchant": 0, "black_sail": 0}
	stat_kills = 0
	stat_bosses = 0
	game_cleared = false
	ensure_ship()
	# 1.2.0：新游戏初始化母港建筑与启动资源（放在最后，避免被前面的 clear 清掉）
	init_town_buildings(true, 1)
	grant_start_resources()
