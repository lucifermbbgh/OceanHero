extends RefCounted
## 拍卖行货品程序化生成（纯静态，无状态）

const CrewFactory = preload("res://scripts/systems/crew_factory.gd")

const RARITY_MIN_GEAR := 2      # SR 及以上
const CREW_MIN_RARITY := 3      # SSR 及以上

static func generate(count: int, player_level: int) -> Array:
	var out: Array = []
	var magic_used := false
	for i in range(count):
		var roll := RngService.randf()
		var kind := "ship"
		if magic_used:
			rng_pick(roll)
		var lot: Dictionary
		if roll < 0.40:
			lot = _make_whole_ship(player_level)
		elif roll < 0.70:
			lot = _make_gear()
		elif roll < 0.90:
			lot = _make_crew()
		else:
			lot = _make_magic_ship(player_level)
			magic_used = true
		if lot.is_empty():
			continue
		lot["id"] = "lot_%d_%d" % [Time.get_ticks_usec(), i]
		lot["start"] = int(lot.get("price", 1000))
		lot["leader"] = ""
		lot["weeks"] = 2
		out.append(lot)
	return out

static func rng_pick(_r: float) -> void:
	pass

static func _ship_pool() -> Array:
	var ids: Array = []
	for k in DataRegistry.ship_bases.keys():
		ids.append(k)
	return ids

static func _make_whole_ship(player_level: int) -> Dictionary:
	var pool := _ship_pool()
	if pool.is_empty():
		return {}
	var sid: StringName = pool[RngService.randi_range(0, pool.size() - 1)]
	var base: Resource = DataRegistry.get_ship(sid)
	if base == null:
		return {}
	var variant: StringName = ["standard", "navy", "pirate"][RngService.randi_range(0, 2)]
	var sdef: Resource = DataRegistry.get_ship(StringName("%s_%s" % [String(sid), String(variant)]))
	if sdef == null:
		sdef = base
	var gear_ids: Array = []
	var n_gear := RngService.randi_range(1, 2)
	for i in range(n_gear):
		var gid := _random_gear()
		if gid != &"":
			gear_ids.append(gid)
	var crew_id: StringName = &""
	if RngService.chance(0.4):
		crew_id = _random_crew()
	var price := int(round(float(sdef.get("price")) * RngService.randf_range(1.0, 1.3)))
	for g in gear_ids:
		var gd: Resource = DataRegistry.get_gear(g)
		if gd != null:
			price += int(round(float(gd.get("price")) * 1.2))
	if crew_id != &"":
		var crew: Resource = GameState.find_crew_template(crew_id) if GameState.has_method("find_crew_template") else null
		price += 30000
	var parts: Array = []
	for g in gear_ids:
		var gd2: Resource = DataRegistry.get_gear(g)
		if gd2 != null:
			parts.append(String(gd2.display_name))
	return {
		"kind": "ship", "name": String(sdef.display_name), "price": price,
		"def_id": String(sid), "variant": String(variant),
		"gear": gear_ids, "crew_id": String(crew_id),
		"desc": "附带：" + (" / ".join(parts) if not parts.is_empty() else "无"),
	}

static func _make_magic_ship(player_level: int) -> Dictionary:
	var lot := _make_whole_ship(player_level)
	if lot.is_empty():
		return {}
	lot["kind"] = "magic"
	lot["name"] = "幽澜之旗舰 " + String(lot.get("name", ""))
	lot["price"] = int(round(float(lot.get("price", 1000)) * 2.5))
	lot["desc"] = String(lot.get("desc", "")) + " · 魔法船只"
	return lot

static func _make_gear() -> Dictionary:
	var gid := _random_gear()
	if gid == &"":
		return {}
	var gd: Resource = DataRegistry.get_gear(gid)
	if gd == null:
		return {}
	return {
		"kind": "gear", "name": String(gd.display_name),
		"price": int(round(float(gd.get("price")) * RngService.randf_range(1.2, 1.8))),
		"gear": [gid], "desc": "特殊装备",
	}

static func _make_crew() -> Dictionary:
	var cid := _random_crew()
	if cid == &"":
		return {}
	return {
		"kind": "crew", "name": "特殊船员", "crew_id": String(cid),
		"price": RngService.randi_range(30000, 60000), "desc": "SSR 以上船员",
	}

static func _random_gear() -> StringName:
	var pool: Array = []
	for k in DataRegistry.gear.keys():
		var g: Resource = DataRegistry.gear[k]
		if g != null and int(g.get("rarity")) >= RARITY_MIN_GEAR:
			pool.append(k)
	if pool.is_empty():
		return &""
	return pool[RngService.randi_range(0, pool.size() - 1)]

static func _random_crew() -> StringName:
	var roster: Array = CrewFactory.generate(1, &"standard")
	if roster.is_empty():
		return &""
	var c: Resource = roster[0]
	c.rarity = maxi(int(c.rarity), CREW_MIN_RARITY)
	return StringName(c.crew_id)
