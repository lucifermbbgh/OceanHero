extends SceneTree
## 1.4.15 基线审计：输出 17 艘基准船的属性与模块数，并检查单调性

func _init() -> void:
	await create_timer(0.6).timeout
	var dr = root.get_node("DataRegistry")
	var gs = root.get_node("GameState")
	var lib = load("res://scripts/systems/ship_stats.gd")
	var rows: Array = []
	for id in dr.ship_bases.keys():
		var d: Resource = dr.ship_bases[id]
		var st: Dictionary = lib.compute(d, &"standard", {}, [])
		gs.ship_def_id = StringName(String(id))
		gs.ship_module_levels.clear()
		rows.append({
			"id": String(id), "name": String(d.display_name), "tier": int(d.tier),
			"hull": int(round(float(st.get("hull_max", 0.0)))),
			"speed": int(round(float(st.get("base_speed_px", 0.0)))),
			"turn": int(round(float(st.get("turn_rate", 0.0)))),
			"guns": int(st.get("guns_per_side", 0)),
			"cargo": int(st.get("cargo_capacity", 0)),
			"crew": int(round(float(st.get("crew_max", 0.0)))),
			"modules": gs.ship_modules().size(),
			"cap": gs.module_level_cap(),
		})
	rows.sort_custom(func(a, b): return int(a["tier"]) < int(b["tier"]))
	print("TIER | 船名 | 船体 | 航速 | 转向 | 炮 | 货舱 | 船员 | 模块 | 强化上限")
	for r in rows:
		print("%2d | %s | %d | %d | %d | %d | %d | %d | %d | %d" % [
			int(r["tier"]), String(r["name"]), int(r["hull"]), int(r["speed"]),
			int(r["turn"]), int(r["guns"]), int(r["cargo"]), int(r["crew"]),
			int(r["modules"]), int(r["cap"])])
	# 单调性检查（按船级）
	var bad: Array = []
	var prev_hull := 0
	var prev_mod := 0
	var prev_guns := 0
	for r2 in rows:
		if String(r2["id"]).begins_with("fx_"):
			continue  # 势力专属船为特化型，不参与主线单调性
		if int(r2["hull"]) < prev_hull:
			bad.append("船体下降：" + String(r2["name"]))
		if int(r2["modules"]) < prev_mod:
			bad.append("模块数下降：" + String(r2["name"]))
		if int(r2["guns"]) < prev_guns:
			bad.append("炮数下降：" + String(r2["name"]))
		prev_hull = int(r2["hull"])
		prev_mod = int(r2["modules"])
		prev_guns = int(r2["guns"])
	print("VIOLATIONS=", bad.size(), " ", str(bad))
	quit(0 if bad.is_empty() else 1)
