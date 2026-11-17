extends RefCounted
## 价格推导明细生成器（只在 UI 打开时调用）

const EconMath = preload("res://scripts/systems/econ_math.gd")

## 返回 {steps:[{label,value,note}], result, metrics:{}}
static func price_breakdown(port_key: String, cid: StringName, base_price: int,
		stock: int, max_stock: int, event_mult: float, drift: float) -> Dictionary:
	var ratio := clampf(float(stock) / maxf(1.0, float(max_stock)), 0.0, 1.0)
	var e: float = EconMath.piecewise_elasticity(ratio)
	var formula := float(base_price) * (1.0 + e * (1.0 - ratio))
	var buy := formula * float(MarketModel.cfg.get("buy_markup", 1.05))
	var after_event := buy * event_mult
	var final_price := int(round(after_event * drift))
	var steps: Array = [
		{"label": "基础价", "value": base_price,
			"note": "商品定义中的基准"},
		{"label": "库存弹性", "value": int(round(formula)) - base_price,
			"note": "弹性 %.2f · 库存 %d/%d（%d%%）" % [e, stock, max_stock, int(ratio * 100.0)]},
		{"label": "买入加价", "value": int(round(buy)) - int(round(formula)),
			"note": "买价系数 ×%.2f" % float(MarketModel.cfg.get("buy_markup", 1.05))},
		{"label": "事件倍率", "value": int(round(after_event)) - int(round(buy)),
			"note": "×%.3f" % event_mult},
		{"label": "市场漂移", "value": final_price - int(round(after_event)),
			"note": "×%.3f（每周回归 25%%）" % drift},
	]
	return {
		"steps": steps,
		"result": final_price,
		"metrics": {
			"elasticity": e, "stock_ratio": ratio,
			"event_mult": event_mult, "drift": drift,
		},
	}
