class_name ShipStats
extends RefCounted
## 把「基准船体 × 变体倍率 × 装备加成」算成最终战斗属性。
## 纯函数，不依赖节点树。

const GEAR_SLOTS := [&"sail", &"rudder", &"armor", &"figurehead", &"flag"]

## 变体倍率（相对基准模板）
const VARIANT_MULT := {
	&"standard": {"hull": 1.10, "guns": 0.90, "speed": 0.90, "turn": 0.95, "cargo": 1.30, "crew_slots": 8, "price": 1.00},
	&"navy":     {"hull": 1.30, "guns": 1.20, "speed": 0.85, "turn": 0.90, "cargo": 0.80, "crew_slots": 12, "price": 1.50},
	&"pirate":   {"hull": 0.80, "guns": 0.90, "speed": 1.25, "turn": 1.30, "cargo": 0.70, "crew_slots": 9, "price": 1.30},
}

const VARIANT_NAMES := {
	&"standard": "通用型", &"navy": "海军型", &"pirate": "海盗型",
}

static func variant_mult(variant: StringName) -> Dictionary:
	return VARIANT_MULT.get(variant, VARIANT_MULT[&"standard"])

## 声望门槛：海军型 / 海盗型 = 500 × 等级；通用型无门槛
static func reputation_gate(variant: StringName, tier: int) -> Dictionary:
	if variant == &"navy":
		return {"royal_navy": 500 * tier}
	if variant == &"pirate":
		return {"black_sail": 500 * tier}
	return {}

## 汇总装备加成
static func _resolve_gear(id) -> Resource:
	var loop := Engine.get_main_loop()
	if loop == null:
		return null
	var root := (loop as SceneTree).root
	if root == null:
		return null
	var reg = root.get_node_or_null("DataRegistry")
	if reg == null:
		return null
	return reg.get_gear(id)

static func gear_bonus(equipped: Dictionary) -> Dictionary:
	var out := {"speed_pct": 0.0, "turn_pct": 0.0, "armor": 0, "boarding": 0}
	for slot in equipped.keys():
		var gid = equipped[slot]
		var g: Resource = _resolve_gear(gid)
		if g == null:
			continue
		out.speed_pct += float(g.speed_pct)
		out.turn_pct += float(g.turn_pct)
		out.armor += int(g.armor_add)
		out.boarding += int(g.boarding_add)
	return out

## 岗位效果：每点技能值提供的加成
const CREW_EFFECT := {
	&"helmsman": {"turn_pct": 0.006},
	&"first_mate": {"reload_pct": 0.005},
	&"gunner": {"accuracy": 0.03},
	&"lookout": {"view": 40.0},
	&"boatswain": {"speed_pct": 0.004},
	&"sailmaster": {"speed_pct": 0.003},
	&"raider": {"boarding_pct": 0.25},
	&"collector": {},
	&"carpenter": {},
	&"surgeon": {},
}

static func crew_bonus(crew_list: Array) -> Dictionary:
	var out := {"turn_pct": 0.0, "reload_pct": 0.0, "accuracy": 0.0,
		"speed_pct": 0.0, "view": 0.0, "boarding_pct": 0.0}
	for c in crew_list:
		if c == null:
			continue
		var role := StringName(c.role)
		var eff: Dictionary = CREW_EFFECT.get(role, {})
		for k in eff.keys():
			if String(k) == "boarding_pct":
				out.boarding_pct += float(eff[k])
			else:
				out[k] += float(eff[k]) * float(c.stat)
	out.accuracy = minf(float(out.accuracy), 0.35)
	return out

## 最终属性
static func compute(def: Resource, variant: StringName, equipped: Dictionary, crew_list: Array = []) -> Dictionary:
	var m := variant_mult(variant)
	var bonus := gear_bonus(equipped)
	var cb := crew_bonus(crew_list)
	var hull_max: float = float(def.base_hp) * float(m.hull)
	var speed_px: float = float(def.base_speed) * 28.0 * float(m.speed) \
		* (1.0 + float(bonus.speed_pct) + float(cb.speed_pct))
	var turn: float = float(def.turn_rate) * float(m.turn) \
		* (1.0 + float(bonus.turn_pct) + float(cb.turn_pct))
	var guns: int = int(round(float(def.guns_per_side) * float(m.guns)))
	return {
		"hull_max": hull_max,
		"sail_max": hull_max * 0.25,
		"rudder_max": hull_max * 0.15,
		"crew_max": float(def.crew_capacity) * 10.0,
		"base_speed_px": speed_px,
		"turn_rate": turn,
		"armor": int(def.armor_base) + int(bonus.armor),
		"guns_per_side": maxi(1, guns),
		"cargo_capacity": int(round(float(def.cargo_capacity) * float(m.cargo))),
		"crew_slots": int(m.crew_slots),
		"boarding": int(bonus.boarding),
		"price": int(round(float(def.price) * float(m.price))),
		"variant_name": VARIANT_NAMES.get(variant, "通用型"),
		"reload_bonus": float(cb.reload_pct),
		"accuracy_bonus": float(cb.accuracy),
		"view_bonus": float(cb.view),
		"boarding_pct": float(cb.boarding_pct),
	}
