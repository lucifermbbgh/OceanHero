extends SceneTree
## 无头测试入口。全部通过返回 0，否则返回 1。
## 运行：godot_run_headless(project_path="...", script="tests/headless/run_all.gd")

const CRes = preload("res://scripts/systems/combat_resolver.gd")
const MRes = preload("res://scripts/systems/market_model.gd")
const StatsLib = preload("res://scripts/systems/ship_stats.gd")
const CrewDefScript = preload("res://scripts/data/crew_def.gd")

var _pass := 0
var _fail := 0
var _section := ""

func _initialize() -> void:
	print("=== SeaHeroes 无头测试 ===")
	_test_data()
	_test_combat()
	_test_pools()
	_test_market()
	_test_curve()
	_test_balance_config()
	_test_variants()
	_test_crew()
	print("=== 通过 %d / 失败 %d ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _sec(name: String) -> void:
	_section = name
	print("\n[%s]" % name)

func _ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s  %s" % [label, detail])

func _near(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps

# ---------------- 数据 ----------------
func _test_data() -> void:
	_sec("数据表")
	for f in ["ships/fishing_sloop", "ships/sand_junk", "ships/brig"]:
		var r: Resource = load("res://data/%s.tres" % f)
		_ok(r != null and String(r.get("id")) != "", "载入 %s" % f)
	for f in ["cannons/pound3_light", "cannons/pound6", "cannons/pound12"]:
		var r: Resource = load("res://data/%s.tres" % f)
		_ok(r != null and float(r.get("damage")) > 0.0, "载入 %s" % f)
	for f in ["ammo/solid", "ammo/chain", "ammo/grape"]:
		var r: Resource = load("res://data/%s.tres" % f)
		_ok(r != null and String(r.get("id")) != "", "载入 %s" % f)
	var ship: Resource = load("res://data/ships/fishing_sloop.tres")
	_ok(_near(ship.sail_pool(), 100.0, 0.01), "帆池 = 船体 ×0.25")
	_ok(_near(ship.rudder_pool(), 60.0, 0.01), "舵池 = 船体 ×0.15")
	_ok(_near(ship.crew_pool(), 60.0, 0.01), "船员池 = 人数 ×10")

# ---------------- 战斗 ----------------
func _test_combat() -> void:
	_sec("战斗结算")
	var solid: Resource = load("res://data/ammo/solid.tres")
	var chain: Resource = load("res://data/ammo/chain.tres")
	var grape: Resource = load("res://data/ammo/grape.tres")
	var atk := {"guns_per_side": 1, "cannon_damage": 18.0, "quality_mult": 1.0, "gunnery": 0.0, "accuracy_mod": 0.0}
	var def0 := {"armor": 0, "evasion": 0.0}
	var r: Dictionary = CRes.volley(atk, def0, solid)
	_ok(r.hull >= 10.0 and r.hull <= 25.0, "C1 3磅炮船体伤害在 [10,25]", "实得 %.2f" % r.hull)

	# C2 弹药分配
	var rc: Dictionary = CRes.volley(atk, def0, chain)
	var rg: Dictionary = CRes.volley(atk, def0, grape)
	_ok(rc.sail > rc.hull * 5.0, "C2 链弹对帆伤害远高于船体", "sail %.2f hull %.2f" % [rc.sail, rc.hull])
	_ok(rg.crew > rg.hull * 5.0, "C2 葡萄弹对船员伤害远高于船体", "crew %.2f hull %.2f" % [rg.crew, rg.hull])

	# C3 命中钳制
	var hi := atk.duplicate(); hi.gunnery = 1000.0
	var lo := atk.duplicate(); lo.gunnery = -1000.0
	_ok(CRes.volley(hi, def0, solid).hit <= 0.95, "C3 命中上限 0.95")
	_ok(CRes.volley(lo, def0, solid).hit >= 0.25, "C3 命中下限 0.25")

	# C4 装甲只减船体
	var def120 := {"armor": 120, "evasion": 0.0}
	var ra: Dictionary = CRes.volley(atk, def120, solid)
	var rs: Dictionary = CRes.volley(atk, def120, chain)
	_ok(_near(ra.hull, r.hull * 0.5, 0.01), "C4 armor=120 时船体伤害减半", "%.2f vs %.2f" % [ra.hull, r.hull * 0.5])
	_ok(_near(rs.sail, rc.sail, 0.01), "C4 装甲不影响帆伤害")

	# C5 装填下限
	_ok(_near(CRes.reload_time(2.0, 1.0), 2.0, 0.001), "C5 满船员装填 = 炮基础装填")
	_ok(_near(CRes.reload_time(2.0, 0.5), 2.6667, 0.001), "C10 船员 50% 时装填 ×1.33")
	_ok(CRes.reload_time(0.1, 0.0) >= 0.6, "C5 装填下限 0.6")

# ---------------- 损伤池与状态 ----------------
func _test_pools() -> void:
	_sec("损伤与状态")
	_ok(_near(CRes.speed_mult(1.0), 1.0, 0.001), "C6 满帆航速 100%")
	_ok(CRes.speed_mult(0.0) == 0.0, "C6 帆毁航速归零")
	_ok(_near(CRes.speed_mult(0.5), 0.7, 0.001), "C6 半帆航速 70%")
	_ok(_near(CRes.turn_mult(1.0), 1.0, 0.001), "C7 满舵转向 100%")
	_ok(CRes.turn_mult(0.0) == 0.0, "C7 舵毁转向归零")
	_ok(CRes.can_board(99.0, 1000.0), "C11 船体 9.9% 可接舷")
	_ok(not CRes.can_board(101.0, 1000.0), "C11 船体 10.1% 不可接舷")
	_ok(CRes.can_retreat(50.0, 50.0), "C12 帆舵俱在可撤离")
	_ok(not CRes.can_retreat(0.0, 50.0), "C12 帆毁不可撤离")
	_ok(not CRes.can_retreat(50.0, 0.0), "C12 舵毁不可撤离")

# ---------------- 市场 ----------------
func _test_market() -> void:
	_sec("市场模型")
	var empty_p := MRes.buy_price(100, 0, 1000)
	var full_p := MRes.buy_price(100, 1000, 1000)
	_ok(empty_p > full_p, "E1 空库存买价高于满库存", "%d vs %d" % [empty_p, full_p])
	_ok(full_p <= 106, "E2 满库存买价接近基准", "实得 %d" % full_p)
	var sell := MRes.sell_price(100, 500, 1000)
	_ok(sell < MRes.buy_price(100, 500, 1000), "E3 卖价低于买价（存在价差）")
	var regen := MRes.weekly_regen(0, 1000)
	_ok(regen == 20, "E4 每周回归 2%", "实得 %d" % regen)
	_ok(MRes.is_bulk(400, 1000), "E5 400/1000 触发大额惩罚")
	_ok(not MRes.is_bulk(200, 1000), "E5 200/1000 不触发")
	var prod_sell := MRes.sell_price(100, 500, 1000, 0.6)
	_ok(prod_sell < sell, "E6 生产港卖价更低")

# ---------------- 曲线 ----------------
# ---------------- 船体变体 ----------------
func _test_variants() -> void:
	_sec("船体变体")
	var sloop: Resource = load("res://data/ships/fishing_sloop.tres")
	var brig: Resource = load("res://data/ships/brig.tres")

	var std: Dictionary = StatsLib.compute(sloop, &"standard", {})
	var navy: Dictionary = StatsLib.compute(sloop, &"navy", {})
	var pirate: Dictionary = StatsLib.compute(sloop, &"pirate", {})
	_ok(_near(float(std.hull_max), 440.0, 0.5), "通用型船体 = 基准 ×1.10", "%.0f" % std.hull_max)
	_ok(_near(float(navy.hull_max), 520.0, 0.5), "海军型船体 = 基准 ×1.30", "%.0f" % navy.hull_max)
	_ok(_near(float(pirate.hull_max), 320.0, 0.5), "海盗型船体 = 基准 ×0.80", "%.0f" % pirate.hull_max)
	_ok(float(pirate.base_speed_px) > float(navy.base_speed_px), "海盗型比海军型快")
	_ok(float(navy.turn_rate) < float(pirate.turn_rate), "海军型比海盗型笨重")

	var bstd: Dictionary = StatsLib.compute(brig, &"standard", {})
	var bnavy: Dictionary = StatsLib.compute(brig, &"navy", {})
	_ok(int(bstd.guns_per_side) == 9, "横帆船通用型单侧 9 门", "实得 %d" % int(bstd.guns_per_side))
	_ok(int(bnavy.guns_per_side) == 12, "横帆船海军型单侧 12 门", "实得 %d" % int(bnavy.guns_per_side))
	_ok(int(bstd.cargo_capacity) == 2600, "通用型载重 = 基准 ×1.30", "实得 %d" % int(bstd.cargo_capacity))

	_ok(StatsLib.reputation_gate(&"standard", 8).is_empty(), "通用型无声望门槛")
	_ok(int(StatsLib.reputation_gate(&"navy", 8).get("royal_navy", 0)) == 4000, "海军型 VIII 需海军声望 4000")
	_ok(int(StatsLib.reputation_gate(&"pirate", 10).get("black_sail", 0)) == 5000, "海盗型 X 需黑帆声望 5000")

	var bonus: Dictionary = StatsLib.gear_bonus({})
	_ok(_near(float(bonus.speed_pct), 0.0, 0.0001), "空装备无加成")

func _mk_crew(role: StringName, stat: int) -> Resource:
	var c = CrewDefScript.new()
	c.role = role
	c.stat = stat
	c.rarity = 1
	return c

# ---------------- 船员 ----------------
func _test_crew() -> void:
	_sec("船员加成")
	var gunner := _mk_crew(&"gunner", 10)
	var helmsman := _mk_crew(&"helmsman", 10)
	var cb: Dictionary = StatsLib.crew_bonus([gunner, helmsman])
	_ok(_near(float(cb.accuracy), 0.30, 0.001), "炮手 10 技能 → 命中 +0.30", "%.3f" % cb.accuracy)
	_ok(_near(float(cb.turn_pct), 0.06, 0.001), "舵手 10 技能 → 转向 +6%", "%.3f" % cb.turn_pct)

	var big := _mk_crew(&"gunner", 20)
	_ok(_near(float(StatsLib.crew_bonus([big]).accuracy), 0.35, 0.001), "命中加成封顶 0.35")

	var raider := _mk_crew(&"raider", 5)
	_ok(_near(float(StatsLib.crew_bonus([raider]).boarding_pct), 0.25, 0.001), "突击队长 → 接舷 +25%")

	_ok(_near(float(StatsLib.crew_bonus([]).turn_pct), 0.0, 0.0001), "无船员无加成")

	var sloop: Resource = load("res://data/ships/fishing_sloop.tres")
	var base_turn: float = float(StatsLib.compute(sloop, &"standard", {}).turn_rate)
	var with_turn: float = float(StatsLib.compute(sloop, &"standard", {}, [helmsman]).turn_rate)
	_ok(with_turn > base_turn, "舵手让转向变快", "%.1f -> %.1f" % [base_turn, with_turn])

# ---------------- 热参数 ----------------
func _test_balance_config() -> void:
	_sec("热参数")
	var solid: Resource = load("res://data/ammo/solid.tres")
	var atk := {"guns_per_side": 10, "cannon_damage": 18.0, "quality_mult": 1.0, "gunnery": 0.0, "accuracy_mod": 0.0}
	var base_hull: float = CRes.volley(atk, {"armor": 120, "evasion": 0.0}, solid).hull

	CRes.configure({"armor_k": 240.0})
	var changed: float = CRes.volley(atk, {"armor": 120, "evasion": 0.0}, solid).hull
	_ok(changed > base_hull, "armor_k 调大后装甲减伤变弱", "%.1f -> %.1f" % [base_hull, changed])
	CRes.reset_defaults()
	_ok(_near(CRes.volley(atk, {"armor": 120, "evasion": 0.0}, solid).hull, base_hull, 0.01), "reset_defaults 还原")

	CRes.configure({"hit_base": 0.10})
	var low: float = CRes.volley(atk, {"armor": 0, "evasion": 0.0}, solid).hit
	_ok(low <= 0.26, "hit_base 调低后命中贴近下限", "hit=%.2f" % low)
	CRes.reset_defaults()

	MRes.configure({"price_elasticity": 0.0})
	_ok(MRes.buy_price(100, 0, 1000) == MRes.buy_price(100, 1000, 1000), "弹性为 0 时空/满库存同价")
	MRes.reset_defaults()
	_ok(MRes.buy_price(100, 0, 1000) > MRes.buy_price(100, 1000, 1000), "恢复默认后价格重新拉开")

	CRes.configure({"xp_a": 240.0})
	_ok(CRes.xp_to_next(1) == 240, "经验曲线系数可调")
	CRes.reset_defaults()

func _test_curve() -> void:
	_sec("成长曲线")
	var prev := 0
	var mono := true
	for lv in range(1, 61):
		var cur := CRes.xp_to_next(lv)
		if cur <= prev:
			mono = false
		prev = cur
	_ok(mono, "P3 经验曲线单调递增")
	_ok(CRes.xp_to_next(1) == 120, "P3 1→2 级需 120 经验")
