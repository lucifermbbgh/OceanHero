class_name CombatResolver
extends RefCounted
## 纯函数战斗结算器。不依赖节点树，可在 headless 下直接单元测试。
## 全部数值常量来自 cfg（默认值内嵌，DataRegistry 启动时用 balance_config.tres 覆盖）。

static var cfg: Dictionary = {
	"armor_k": 120.0,
	"hit_base": 0.60,
	"hit_per_point": 0.03,
	"hit_min": 0.25,
	"hit_max": 0.95,
	"reload_floor": 0.6,
	"crew_eff_floor": 0.5,
	"sail_mult_base": 0.4,
	"sail_mult_range": 0.6,
	"rudder_mult_base": 0.3,
	"rudder_mult_range": 0.7,
	"board_threshold": 0.10,
	"xp_a": 120.0,
	"xp_b": 1.35,
}

static func configure(d: Dictionary) -> void:
	for k in d.keys():
		cfg[k] = d[k]

static func reset_defaults() -> void:
	cfg = {
		"armor_k": 120.0, "hit_base": 0.60, "hit_per_point": 0.03,
		"hit_min": 0.25, "hit_max": 0.95, "reload_floor": 0.6,
		"crew_eff_floor": 0.5, "sail_mult_base": 0.4, "sail_mult_range": 0.6,
		"rudder_mult_base": 0.3, "rudder_mult_range": 0.7,
		"board_threshold": 0.10, "xp_a": 120.0, "xp_b": 1.35,
	}

## 齐射结算。attacker / defender 为字典。
## attacker: guns_per_side, cannon_damage, quality_mult, crew_pct, gunnery, accuracy_mod
## defender: armor, evasion
## 返回四个损伤池各自的伤害量。
static func volley(attacker: Dictionary, defender: Dictionary, ammo: Resource) -> Dictionary:
	var guns := int(attacker.get("guns_per_side", 1))
	var dmg_per := float(attacker.get("cannon_damage", 18.0))
	var quality := float(attacker.get("quality_mult", 1.0))
	var gunnery := float(attacker.get("gunnery", 0.0))
	var evasion := float(defender.get("evasion", 0.0))
	var acc_mod := float(attacker.get("accuracy_mod", 0.0))
	var ammo_dmg := 1.0
	var ammo_acc := 0.0
	var to_hull := 1.0
	var to_sail := 0.25
	var to_rudder := 0.4
	var to_crew := 0.1
	if ammo != null:
		ammo_dmg = float(ammo.damage_mult)
		ammo_acc = float(ammo.accuracy_mod)
		to_hull = float(ammo.to_hull)
		to_sail = float(ammo.to_sail)
		to_rudder = float(ammo.to_rudder)
		to_crew = float(ammo.to_crew)
	var armor := float(defender.get("armor", 0))
	var raw := float(guns) * dmg_per * quality * ammo_dmg
	var hit := clampf(
		float(cfg.hit_base) + float(cfg.hit_per_point) * (gunnery - evasion) + acc_mod + ammo_acc,
		float(cfg.hit_min), float(cfg.hit_max))
	var base_dmg := raw * hit
	var k := float(cfg.armor_k)
	var armor_factor := 1.0 - armor / (armor + k)
	return {
		"hit": hit,
		"raw": raw,
		"hull": base_dmg * to_hull * armor_factor,
		"sail": base_dmg * to_sail,
		"rudder": base_dmg * to_rudder,
		"crew": base_dmg * to_crew,
	}

## 装填时间：炮本身 × 船员效率，下限 cfg.reload_floor 秒
static func reload_time(cannon_reload: float, crew_pct: float, reload_bonus: float = 0.0) -> float:
	var floorv := float(cfg.crew_eff_floor)
	var eff := floorv + (1.0 - floorv) * clampf(crew_pct, 0.0, 1.0)
	return maxf(float(cfg.reload_floor), cannon_reload / (1.0 + reload_bonus) / eff)

## 风帆余量 → 航速倍率（0 则彻底停船）
static func speed_mult(sail_pct: float) -> float:
	if sail_pct <= 0.001:
		return 0.0
	return float(cfg.sail_mult_base) + float(cfg.sail_mult_range) * clampf(sail_pct, 0.0, 1.0)

## 舵机余量 → 转向倍率（0 则彻底失去转向）
static func turn_mult(rudder_pct: float) -> float:
	if rudder_pct <= 0.001:
		return 0.0
	return float(cfg.rudder_mult_base) + float(cfg.rudder_mult_range) * clampf(rudder_pct, 0.0, 1.0)

## 接舷：一次 tick 双方各自承受的船员伤害
static func boarding_tick(power_self: float, power_enemy: float) -> Dictionary:
	return {"to_self": power_enemy, "to_enemy": power_self}

## 是否允许接舷：目标船体 ≤ cfg.board_threshold
static func can_board(target_hull_hp: float, target_hull_max: float) -> bool:
	if target_hull_max <= 0.0:
		return false
	return target_hull_hp <= target_hull_max * float(cfg.board_threshold)

## 是否允许撤离：己方帆与舵都还活着
static func can_retreat(sail_hp: float, rudder_hp: float) -> bool:
	return sail_hp > 0.0 and rudder_hp > 0.0

## 经验曲线
static func xp_to_next(level: int) -> int:
	return int(round(float(cfg.xp_a) * pow(float(maxi(level, 1)), float(cfg.xp_b))))
