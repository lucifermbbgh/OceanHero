class_name MarketModel
extends RefCounted
## 纯函数市场模型。常量来自 cfg，可由 balance_config.tres 覆盖。

static var cfg: Dictionary = {
	"price_elasticity": 0.55,
	"buy_markup": 1.05,
	"sell_markdown": 0.90,
	"bulk_ratio": 0.30,
	"bulk_penalty": 0.10,
	"weekly_regen_rate": 0.02,
	"piecewise_enabled": true,
	"max_weekly_price_swing": 0.15,
}

static func configure(d: Dictionary) -> void:
	for k in d.keys():
		cfg[k] = d[k]

static func reset_defaults() -> void:
	cfg = {
		"price_elasticity": 0.55, "buy_markup": 1.05, "sell_markdown": 0.90,
		"bulk_ratio": 0.30, "bulk_penalty": 0.10, "weekly_regen_rate": 0.02,
		"max_weekly_price_swing": 0.15,
		"piecewise_enabled": true,
	}

const EconMath = preload("res://scripts/systems/econ_math.gd")

static func generic_price(base_price: int, stock: int, max_stock: int) -> float:
	var ratio := clampf(float(stock) / maxf(1.0, float(max_stock)), 0.0, 1.0)
	var e := float(cfg.price_elasticity)
	if bool(cfg.get("piecewise_enabled", false)):
		e = EconMath.piecewise_elasticity(ratio)
	return float(base_price) * (1.0 + e * (1.0 - ratio))

static func buy_price(base_price: int, stock: int, max_stock: int, demand_mod: float = 1.0, bulk: bool = false) -> int:
	var p := generic_price(base_price, stock, max_stock) * demand_mod * float(cfg.buy_markup)
	if bulk:
		p *= (1.0 + float(cfg.bulk_penalty))
	return int(round(p))

static func sell_price(base_price: int, stock: int, max_stock: int, production_mod: float = 1.0) -> int:
	return int(floor(generic_price(base_price, stock, max_stock) * production_mod * float(cfg.sell_markdown)))

## 每周库存向满值回归一次
static func weekly_regen(stock: int, max_stock: int, rate: float = -1.0) -> int:
	var r := float(cfg.weekly_regen_rate) if rate < 0.0 else rate
	var target := float(max_stock)
	return int(round(minf(target, float(stock) + target * r)))

static func is_bulk(amount: int, stock: int) -> bool:
	return float(amount) > float(stock) * float(cfg.bulk_ratio)

## 阶梯溢价：目标地图不产出该商品时的售价倍率
## gap = 目标地图编号 - 商品产地地图编号（取正）
## 最高 +300%（倍率 4.0）
static func span_premium(gap: int) -> float:
	var g := clampi(gap, 0, 8)
	return 1.0 + 3.0 * (float(g) / 8.0)

## 综合售价倍率：目标地图不产出才有跨度溢价，否则按普通距离差价
static func sale_multiplier(produced_here: bool, gap: int) -> float:
	if produced_here:
		return 1.0
	return span_premium(gap)
