extends Node
## 出海模拟器：不开窗口、不建节点，直接用真实公式跑一遍经济循环。
## 输出：战斗时长、单次出海收益、修理费占比、升级所需出海次数。

const CRes = preload("res://scripts/systems/combat_resolver.gd")
const MRes = preload("res://scripts/systems/market_model.gd")
const StatsLib = preload("res://scripts/systems/ship_stats.gd")

const TICK := 0.25
const MAX_TICKS := 1200   # 300 秒上限

var report: Array = []

func _ready() -> void:
	print("=== 碧海英豪 · 出海模拟 ===")
	_sim_tier(1, &"fishing_sloop", &"pirate_scout", "起手：单桅渔船 vs 海盗斥候")
	_sim_tier(2, &"sand_junk", &"pirate_scout", "二级：平底沙船 vs 海盗斥候")
	_sim_tier(5, &"brig", &"pirate_scout", "五级：双桅横帆船 vs 海盗斥候")
	_sim_boss(&"sand_junk", &"boss_jack", "二级船 vs 图 1 Boss")
	_sim_boss(&"sixth_rate", &"boss_karl", "六级船 vs 图 5 Boss")
	_sim_boss(&"first_rate", &"boss_crown", "十级船 vs 图 9 Boss")
	_economy_check()
	_progression_table()
	for line in report:
		print(line)
	get_tree().quit(0)

# ---------------- 单场战斗 ----------------

## 该船承载范围内、单位时间伤害最高的炮
func _best_cannon(max_weight: int) -> Resource:
	var best: Resource = null
	var best_dps := 0.0
	for k in DataRegistry.cannons.keys():
		var c: Resource = DataRegistry.cannons[k]
		if int(c.pound_class) > max_weight:
			continue
		var dps := float(c.damage) / maxf(0.1, float(c.reload_seconds))
		if dps > best_dps:
			best_dps = dps
			best = c
	if best == null:
		best = DataRegistry.get_cannon(&"pound3_light")
	return best

func _player_stats(ship_id: StringName, variant: StringName) -> Dictionary:
	var def: Resource = DataRegistry.get_ship(ship_id)
	var st: Dictionary = StatsLib.compute(def, variant, {}, [])
	var cannon: Resource = _best_cannon(int(def.max_cannon_weight))
	return {
		"hull": st.hull_max, "sail": st.sail_max, "rudder": st.rudder_max,
		"crew": st.crew_max, "guns": st.guns_per_side, "armor": st.armor,
		"damage": float(cannon.damage), "reload": float(cannon.reload_seconds),
		"acc": float(cannon.accuracy_mod), "crew_pct_start": 1.0,
	}

func _enemy_stats(enemy_id: StringName, scale: float) -> Dictionary:
	var e: Resource = DataRegistry.get_enemy(enemy_id)
	var sdef: Resource = DataRegistry.get_ship(e.based_on_ship)
	var cdef: Resource = DataRegistry.get_cannon(e.based_on_cannon)
	var hull: float = float(sdef.base_hp) * float(e.hp_mult) * scale
	return {
		"hull": hull, "sail": hull * 0.25, "rudder": hull * 0.15,
		"crew": float(sdef.crew_capacity) * 10.0, "guns": int(sdef.guns_per_side),
		"armor": int(sdef.armor_base),
		"damage": float(cdef.damage) * float(e.damage_mult) * sqrt(scale),
		"reload": float(cdef.reload_seconds), "acc": float(cdef.accuracy_mod),
	}

func _sim_battle(p: Dictionary, e: Dictionary) -> Dictionary:
	var ammo: Resource = load("res://data/ammo/solid.tres")
	var php: float = p.hull
	var ehp: float = e.hull
	var p_reload := 0.0
	var e_reload := 0.0
	var t := 0.0
	var p_shots := 0
	var e_shots := 0
	while t < MAX_TICKS * TICK and php > 0.0 and ehp > 0.0:
		t += TICK
		p_reload -= TICK
		e_reload -= TICK
		if p_reload <= 0.0:
			p_reload = CRes.reload_time(p.reload, 1.0, 0.0)
			p_shots += 1
			var atk := {"guns_per_side": p.guns, "cannon_damage": p.damage, "quality_mult": 1.0,
				"gunnery": 0.0, "accuracy_mod": p.acc}
			var res: Dictionary = CRes.volley(atk, {"armor": e.armor, "evasion": 0.0}, ammo)
			ehp -= float(res.hull)
		if e_reload <= 0.0 and ehp > 0.0:
			e_reload = CRes.reload_time(e.reload, 1.0, 0.0)
			e_shots += 1
			var atk2 := {"guns_per_side": e.guns, "cannon_damage": e.damage, "quality_mult": 1.0,
				"gunnery": 0.0, "accuracy_mod": e.acc}
			var res2: Dictionary = CRes.volley(atk2, {"armor": p.armor, "evasion": 0.0}, ammo)
			php -= float(res2.hull)
	return {"win": ehp <= 0.0, "seconds": t, "player_hull_left": maxf(0.0, php),
		"player_hull_loss": clampf(1.0 - maxf(0.0, php) / p.hull, 0.0, 1.0),
		"volleys": p_shots}

func _sim_tier(tier: int, ship_id: StringName, enemy_id: StringName, label: String) -> void:
	var p := _player_stats(ship_id, &"standard")
	var e := _enemy_stats(enemy_id, 1.0)
	var r := _sim_battle(p, e)
	var hull_max: float = p.hull
	var per: float = float(DataRegistry.balance_dict.get("repair_per_hull", 0.25))
	var loss_gold: int = int(round(float(r.player_hull_loss) * hull_max * per))
	report.append("[%s] 耗时 %.1fs · 胜=%s · 船体损失 %.0f%% · 修理费 %d 金 · 齐射 %d 轮" % [
		label, r.seconds, str(r.win), r.player_hull_loss * 100.0, loss_gold, int(r.volleys)])

func _sim_boss(ship_id: StringName, enemy_id: StringName, label: String) -> void:
	var p := _player_stats(ship_id, &"standard")
	var e := _enemy_stats(enemy_id, 1.0)
	var r := _sim_battle(p, e)
	report.append("[%s] 耗时 %.1fs · 胜=%s · 船体损失 %.0f%%" % [
		label, r.seconds, str(r.win), r.player_hull_loss * 100.0])

# ---------------- 全等级成长曲线 ----------------

const TIER_SHIPS := [
	&"fishing_sloop", &"sand_junk", &"longship", &"schooner", &"brig",
	&"sixth_rate", &"fifth_rate", &"fourth_rate", &"third_rate", &"first_rate",
]

func _progression_table() -> void:
	report.append("")
	report.append("--- 等级成长曲线（同图海盗斥候，按等级缩放）---")
	report.append("  级  船型              单场耗时  船体损失  修理费   净收益   换下一级需")
	for i in range(TIER_SHIPS.size()):
		var tier := i + 1
		var ship_id: StringName = TIER_SHIPS[i]
		var def: Resource = DataRegistry.get_ship(ship_id)
		if def == null:
			continue
		var scale := 1.0 + float(tier - 1) * 0.35
		var p := _player_stats(ship_id, &"standard")
		var e := _enemy_stats(&"pirate_scout", scale)
		var r := _sim_battle(p, e)
		var per: float = float(DataRegistry.balance_dict.get("repair_per_hull", 0.25))
		var repair := float(r.player_hull_loss) * float(p.hull) * per
		var e_res: Resource = DataRegistry.get_enemy(&"pirate_scout")
		var gold_avg := float(int(e_res.gold_min) + int(e_res.gold_max)) * 0.5 * scale * pow(2.4, float(tier - 1))
		var net := gold_avg * 2.0 - repair
		var next_txt := "—"
		if tier < TIER_SHIPS.size():
			var next_def: Resource = DataRegistry.get_ship(StringName("%s_standard" % String(TIER_SHIPS[i + 1])))
			if next_def != null and net > 0.0:
				next_txt = "%.0f 次" % (float(next_def.price) / net)
			elif next_def != null:
				next_txt = "无法达成"
		report.append("  %2d  %-16s %6.1fs  %5.0f%%  %6.0f  %+7.0f  %s" % [
			tier, String(def.display_name), r.seconds, r.player_hull_loss * 100.0,
			repair, net, next_txt])

# ---------------- 经济循环 ----------------

func _economy_check() -> void:
	var p := _player_stats(&"fishing_sloop", &"standard")
	var e := _enemy_stats(&"pirate_scout", 1.0)
	var r := _sim_battle(p, e)
	var hull_max: float = p.hull
	var per: float = float(DataRegistry.balance_dict.get("repair_per_hull", 0.25))
	var repair: float = float(r.player_hull_loss) * hull_max * per
	var loot_min := 20 * 2   # 一次出海打 2 只
	var loot_max := 60 * 2
	report.append("")
	report.append("--- 起手经济（单次出海 = 打 2 只海盗斥候）---")
	report.append("  单场战斗 %.1fs，两次约 %.1fs" % [r.seconds, r.seconds * 2.0])
	report.append("  战利品金币 %d ~ %d" % [loot_min, loot_max])
	report.append("  修理费 %.0f 金（船体缺失 %.0f%%）" % [repair, r.player_hull_loss * 100.0])
	report.append("  净收益 %.0f ~ %.0f 金" % [float(loot_min) - repair, float(loot_max) - repair])
	var ship_price := int(DataRegistry.get_ship(&"sand_junk_standard").price)
	if loot_max - repair > 0:
		report.append("  换到平底沙船（%d 金）需出海约 %.0f 次" % [ship_price, ship_price / maxf(1.0, (loot_min + loot_max) / 2.0 - repair)])
	else:
		report.append("  ⚠ 单次出海净收益为负：修理费远高于战利品，经济无法自持")
