extends RefCounted
## 城镇面板构建器（1.2.0）：按建筑数据生成菜单项，母港与岛屿共用。

## 返回按 sort_order 排序的建筑列表
static func buildings_for_tier(tier: int) -> Array:
	var out: Array = []
	for bid in DataRegistry.buildings.keys():
		var b: Resource = DataRegistry.buildings[bid]
		if b == null:
			continue
		if int(b.unlock_tier) > tier:
			continue
		out.append(b)
	out.sort_custom(func(a, b2): return int(a.sort_order) < int(b2.sort_order))
	return out

## 城镇初始建筑 id 列表
static func initial_buildings(is_home: bool, tier: int) -> Array:
	var out: Array = []
	for b in buildings_for_tier(tier):
		var is_init := bool(b.is_initial)
		if is_home:
			if is_init:
				out.append(b.id if b.get("id") != null else StringName(String(b.id)))
		else:
			out.append(StringName(String(b.id)))
	return out

## 城镇布局（按等级）
static func layout_for(tier: int) -> Resource:
	var path := "res://data/towns/layout_%d.tres" % tier
	if ResourceLoader.exists(path):
		return load(path)
	return load("res://scripts/data/town_layout.gd").default_for(tier)

## 菜单项 id → 标题（供 UI 生成按钮）
static func menu_items(tier: int) -> Array:
	var out: Array = []
	for b in buildings_for_tier(tier):
		out.append({"id": String(b.id), "title": String(b.display_name),
			"category": String(b.category), "unlock_tier": int(b.unlock_tier)})
	return out
