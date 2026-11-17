extends Node
## 唯一的可存档状态。场景与 UI 只读，修改一律走这里的公开方法。

const StatsLib = preload("res://scripts/systems/ship_stats.gd")
const CrewFactory = preload("res://scripts/systems/crew_factory.gd")
const MarketModel = preload("res://scripts/systems/market_model.gd")
const CRes = preload("res://scripts/systems/combat_resolver.gd")
const CrewDefScript = preload("res://scripts/data/crew_def.gd")

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
		var t: String = ["hunt", "trade", "transport", "escort", "gather"][RngService.randi_range(0, 4)]
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
	reputation["notoriety"] = noto
	if kind == "pirate":
		add_rep("royal_navy", 8 if is_boss else 3)
		add_rep("black_sail", -3)
	elif kind == "monster":
		add_rep("royal_navy", 5 if is_boss else 2)
	stat_add_kill(is_boss)
	# 讨伐任务进度
	for q in quests_active:
		if String(q.get("type", "")) == "hunt" and String(q.get("target_kind", "")) == kind:
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
