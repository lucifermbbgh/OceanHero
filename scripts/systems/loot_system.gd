extends RefCounted
## 战利品结算：金币、货物、经验、升级。

const CombatResolver = preload("res://scripts/systems/combat_resolver.gd")

static func apply(player_ship, enemy_ship, info: Dictionary) -> Dictionary:
	var result := {
		"gold": 0, "cargo": {}, "xp": 0,
		"sunk": bool(info.get("sunk", false)),
		"captured": bool(info.get("captured", false)),
		"monster": bool(info.get("monster", false)),
		"leveled": false,
	}
	var mult := 2 if result.captured else 1
	var loot_raw: Variant = enemy_ship.get("loot_mult")
	var loot_mult := 1.0 if loot_raw == null else float(loot_raw)
	var g := RngService.randi_range(enemy_ship.gold_min, maxi(enemy_ship.gold_min, enemy_ship.gold_max))
	result.gold = int(round(float(g * mult) * loot_mult))
	GameState.add_gold(result.gold)

	# NPC 载货：击沉可获其 30%（与市场结算无关，纯战斗收益）
	var hold: Dictionary = {}
	var hold_raw: Variant = enemy_ship.get("cargo_hold")
	if hold_raw != null and hold_raw is Dictionary:
		for cid in hold_raw.keys():
			var carried := int(hold_raw[cid])
			var take := int(floor(float(carried) * 0.3))
			if take > 0:
				hold[cid] = take
	result["cargo_hold"] = hold

	var amount := int(round(float(int(enemy_ship.loot_amount) * mult) * loot_mult))
	result["overflow"] = 0
	if amount > 0 and String(enemy_ship.loot_commodity) != "":
		var got := GameState.add_cargo(enemy_ship.loot_commodity, amount)
		if got > 0:
			result.cargo[String(enemy_ship.loot_commodity)] = got
		result["overflow"] = amount - got

	# 载货战利品入舱（受载重限制）
	for cid2 in hold.keys():
		var got2: int = GameState.add_cargo(cid2, int(hold[cid2]))
		if got2 > 0:
			result.cargo[String(cid2)] = got2

	# 战功：硬通货，只有 Boss / 精英会掉
	result["commendation"] = 0
	var comm_raw: Variant = enemy_ship.get("commendation_reward")
	if comm_raw != null and int(comm_raw) > 0:
		var comm := int(comm_raw) * mult
		GameState.commendation += comm
		result["commendation"] = comm

	var xp := int(enemy_ship.xp_reward) * mult
	result.xp = xp
	GameState.xp += xp
	while GameState.xp >= CombatResolver.xp_to_next(GameState.level):
		GameState.xp -= CombatResolver.xp_to_next(GameState.level)
		GameState.level += 1
		result.leveled = true
	return result

static func describe(result: Dictionary) -> String:
	var parts: Array = []
	if result.gold > 0:
		parts.append("+%d 金币" % result.gold)
	for k in result.cargo.keys():
		parts.append("+%d %s" % [result.cargo[k], k])
	if not result.get("cargo_hold", {}).is_empty():
		parts.append("（含缴获载货）")
	if result.xp > 0:
		parts.append("+%d 经验" % result.xp)
	if result.leveled:
		parts.append("升级！")
	if result.captured:
		parts.append("【俘获】")
	if int(result.get("commendation", 0)) > 0:
		parts.append("+%d 战功" % int(result.commendation))
	if int(result.get("overflow", 0)) > 0:
		parts.append("货舱已满，损失 %d" % int(result.overflow))
	var head := "击沉" if result.sunk else "俘获"
	return "%s %s" % [head, ", ".join(parts)]
