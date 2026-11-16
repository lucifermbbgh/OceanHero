class_name BalanceConfig
extends Resource
## 全局数值常量。改这里不需要动代码。

@export_group("战斗")
@export var armor_k: float = 120.0
@export var hit_base: float = 0.60
@export var hit_per_point: float = 0.03
@export var hit_min: float = 0.25
@export var hit_max: float = 0.95
@export var reload_floor: float = 0.6
@export var crew_eff_floor: float = 0.5

@export_group("损伤")
@export var sail_mult_base: float = 0.4
@export var sail_mult_range: float = 0.6
@export var rudder_mult_base: float = 0.3
@export var rudder_mult_range: float = 0.7
@export var board_threshold: float = 0.10

@export_group("经济")
@export var price_elasticity: float = 0.55
@export var buy_markup: float = 1.05
@export var sell_markdown: float = 0.90
@export var bulk_ratio: float = 0.30
@export var bulk_penalty: float = 0.10
@export var weekly_regen_rate: float = 0.02

@export_group("修理")
@export var repair_per_hull: float = 0.25     # 每点缺失船体的修理费

@export_group("成长")
@export var xp_a: float = 120.0
@export var xp_b: float = 1.35

@export_group("时间")
@export var real_sec_per_game_day: float = 24.0

func to_dict() -> Dictionary:
	return {
		"armor_k": armor_k,
		"hit_base": hit_base, "hit_per_point": hit_per_point,
		"hit_min": hit_min, "hit_max": hit_max,
		"reload_floor": reload_floor, "crew_eff_floor": crew_eff_floor,
		"sail_mult_base": sail_mult_base, "sail_mult_range": sail_mult_range,
		"rudder_mult_base": rudder_mult_base, "rudder_mult_range": rudder_mult_range,
		"board_threshold": board_threshold,
		"price_elasticity": price_elasticity,
		"buy_markup": buy_markup, "sell_markdown": sell_markdown,
		"bulk_ratio": bulk_ratio, "bulk_penalty": bulk_penalty,
		"weekly_regen_rate": weekly_regen_rate,
		"repair_per_hull": repair_per_hull,
		"xp_a": xp_a, "xp_b": xp_b,
		"real_sec_per_game_day": real_sec_per_game_day,
	}
