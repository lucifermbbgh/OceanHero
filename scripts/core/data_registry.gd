extends Node
## 启动时把 data/ 下的所有 .tres 读进内存，提供按 id 查询。
## 同时把 balance_config.tres 注入到纯函数结算器的 static cfg 里（热参数第一层）。

const CRes = preload("res://scripts/systems/combat_resolver.gd")
const MRes = preload("res://scripts/systems/market_model.gd")
const StatsLib = preload("res://scripts/systems/ship_stats.gd")

var balance: Resource = null
var balance_dict: Dictionary = {}

var ships: Dictionary = {}          # 含变体：fishing_sloop_standard / _navy / _pirate
var ship_bases: Dictionary = {}     # 仅基准模板
var gear: Dictionary = {}
var buildings: Dictionary = {}
var maps: Dictionary = {}
var cannons: Dictionary = {}
var commodities: Dictionary = {}
var enemies: Dictionary = {}
var ports: Dictionary = {}
var ammo: Dictionary = {}

func _ready() -> void:
	_reload()

func _reload() -> void:
	_load_balance()
	ships = _load_dir("res://data/ships")
	_build_variants()
	gear = _load_dir("res://data/gear")
	buildings = _load_dir("res://data/buildings")
	maps = _load_dir("res://data/maps")
	cannons = _load_dir("res://data/cannons")
	commodities = _load_dir("res://data/commodities")
	enemies = _load_dir("res://data/enemies")
	ports = _load_dir("res://data/ports")
	ammo = _load_dir("res://data/ammo")
	print("[DataRegistry] ships=%d(基准 %d) gear=%d cannons=%d ammo=%d commodities=%d enemies=%d ports=%d buildings=%d maps=%d" % [
		ships.size(), ship_bases.size(), gear.size(), cannons.size(), ammo.size(),
		commodities.size(), enemies.size(), ports.size(), buildings.size(), maps.size(),
	])

func _load_balance() -> void:
	var res = load("res://data/balance/balance_config.tres")
	if res == null:
		push_warning("[DataRegistry] 未找到 balance_config.tres，使用代码内默认值")
		return
	balance = res
	balance_dict = res.call("to_dict")
	CRes.configure(balance_dict)
	MRes.configure(balance_dict)

## 按基准模板 × 变体倍率派生出 通用 / 海军 / 海盗 三种船体。
## 属性倍率在 ShipStats.compute() 里应用，这里只改 id / 名称 / 价格。
func _build_variants() -> void:
	ship_bases = ships.duplicate()
	for bid in ship_bases.keys():
		var bdef: Resource = ship_bases[bid]
		for v in [&"standard", &"navy", &"pirate"]:
			var d = bdef.duplicate()
			var vid := StringName("%s_%s" % [String(bid), String(v)])
			var mult: Dictionary = StatsLib.variant_mult(v)
			d.set("id", vid)
			d.set("variant", v)
			d.set("price", int(round(float(bdef.get("price")) * float(mult.price))))
			ships[vid] = d

## F5 热重载：重新读一遍全部数据并重新注入常量
func reload_all() -> void:
	_reload()
	EventBus.ticker.emit("数据已热重载")

func _load_dir(path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for f in dir.get_files():
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var res: Resource = load(path.path_join(f))
		if res == null:
			push_warning("[DataRegistry] 载入失败: %s" % f)
			continue
		if res.get("id") == null or String(res.get("id")) == "":
			push_warning("[DataRegistry] 缺少 id: %s" % f)
			continue
		out[StringName(res.get("id"))] = res
	return out

func get_ship(id: StringName) -> Resource:
	return ships.get(id, null)

func get_cannon(id: StringName) -> Resource:
	return cannons.get(id, null)

func get_gear(id: StringName) -> Resource:
	return gear.get(id, null)

func get_building(id: StringName) -> Resource:
	return buildings.get(id, null)

func get_map(index: int) -> Resource:
	return maps.get(StringName("map%d" % index), null)

func gear_by_slot(slot: StringName) -> Array:
	var out: Array = []
	for k in gear.keys():
		var g: Resource = gear[k]
		if StringName(g.slot) == slot:
			out.append(g)
	out.sort_custom(func(a, b): return int(a.price) < int(b.price))
	return out

func get_commodity(id: StringName) -> Resource:
	return commodities.get(id, null)

func get_enemy(id: StringName) -> Resource:
	return enemies.get(id, null)

func get_port(id: StringName) -> Resource:
	return ports.get(id, null)

func get_ammo(id: StringName) -> Resource:
	return ammo.get(id, null)
