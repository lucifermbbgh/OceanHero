extends Node
## 周结算调度：把 TimeService 的周信号分发给各系统。
## 阶段二先接市场库存回归，后续再挂建造进度、船员薪酬、任务刷新。

const MRes = preload("res://scripts/systems/market_model.gd")

var last_week := 0

func _ready() -> void:
	TimeService.week_advanced.connect(_on_week_advanced)

func _on_week_advanced(week_index: int) -> void:
	last_week = week_index
	_regen_markets()
	_produce()
	_tick_builds()
	_tick_crew_wages()
	if GameState != null:
		GameState.refresh_tavern()
		GameState.tick_exchange()
		GameState.refresh_quests()
		GameState.reset_donations()
		GameState.decay_notoriety()
	EventBus.ticker.emit("%s · 周结算：产出 / 建造 / 薪酬 / 市场" % TimeService.date_text())

func _produce() -> void:
	var p: Dictionary = GameState.total_production()
	for r in p.keys():
		GameState.resources[r] = int(GameState.resources.get(r, 0)) + int(p[r])

func _tick_builds() -> void:
	var done: Array = GameState.tick_build_queue()
	for n in done:
		EventBus.ticker.emit("%s 建造完成" % String(n))

func _regen_markets() -> void:
	for pid in DataRegistry.ports.keys():
		var port: Resource = DataRegistry.ports[pid]
		var max_stock := int(port.max_stock)
		for cid in DataRegistry.commodities.keys():
			var stock := GameState.ensure_stock(pid, cid, max_stock)
			GameState.set_stock(pid, cid, MRes.weekly_regen(stock, max_stock))

func _tick_crew_wages() -> void:
	var due: int = GameState.assigned_wages()
	if due <= 0:
		return
	var paid: int = GameState.pay_crew_wages()
	if paid < due:
		EventBus.ticker.emit("金币不足，欠发薪酬 %d" % (due - paid))
