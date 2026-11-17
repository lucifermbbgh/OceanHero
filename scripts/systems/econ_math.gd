extends RefCounted
## 经济数学函数库（全 static、无状态）

## 分段供给弹性：库存越低，弹性系数越大
static func piecewise_elasticity(stock_ratio: float, alpha_lo: float = 0.35,
		alpha_mid: float = 0.55, alpha_hi: float = 0.90) -> float:
	var r := clampf(stock_ratio, 0.0, 1.0)
	if r > 0.7:
		return alpha_lo
	if r < 0.3:
		return alpha_hi
	return alpha_mid

## 均值回归：把 current 按 speed 拉向 target
static func mean_revert(current: float, target: float, speed: float) -> float:
	return current + (target - current) * clampf(speed, 0.0, 1.0)

## 确定性噪声：同样输入必然同样输出，范围约 [-1, 1]
static func seeded_noise(seed_values: Array, magnitude: float) -> float:
	var h := 2166136261
	for v in seed_values:
		h = (h ^ int(v)) * 16777619
		h = h & 0x7fffffff
	var n := float(h % 10000) / 5000.0 - 1.0
	return n * magnitude

## 单周变动上限
static func clamp_swing(old_value: float, new_value: float, cap: float) -> float:
	var lo := old_value * (1.0 - cap)
	var hi := old_value * (1.0 + cap)
	return clampf(new_value, lo, hi)

## 交叉弹性传导：源涨跌幅 × 系数，上限 ±cap
static func cross_effect(source_change: float, coef: float, threshold: float, cap: float) -> float:
	if absf(source_change) < threshold:
		return 0.0
	return clampf(source_change * coef, -cap, cap)

## 边际利润：按容量与库存逐件累加，返回 {count, total, reason}
static func marginal_trade(buy_price: int, sell_price: int, capacity_left: float,
		volume: float, stock: int) -> Dictionary:
	var can_by_cap := int(floor(capacity_left / maxf(0.01, volume)))
	var can := mini(can_by_cap, stock)
	if can <= 0:
		return {"count": 0, "total": 0, "reason": "capacity" if can_by_cap <= 0 else "stock"}
	var per := sell_price - buy_price
	if per <= 0:
		return {"count": 0, "total": 0, "reason": "unprofitable"}
	return {"count": can, "total": per * can, "reason": "ok"}

## 涨价幅度（正数=涨）
static func change_pct(old_value: float, new_value: float) -> float:
	if is_zero_approx(old_value):
		return 0.0
	return (new_value - old_value) / old_value
