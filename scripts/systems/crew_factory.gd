extends RefCounted
## 酒馆随机船员生成器。

const CrewDefScript = preload("res://scripts/data/crew_def.gd")

const ROLES := [&"mate", &"gunner", &"surgeon", &"sailor"]

const ROLE_WEIGHTS := [&"sailor", &"sailor", &"sailor", &"sailor", &"sailor", &"gunner", &"gunner", &"mate", &"surgeon"]

const ROLE_NAMES := {
	&"mate": "大副", &"gunner": "炮手", &"surgeon": "船医", &"sailor": "水手",
	
	
}

const SURNAMES := ["陈", "林", "王", "赵", "海", "沈", "顾", "罗", "雷", "白", "秦", "薛"]
const GIVEN := ["阿七", "铁手", "老猫", "九斤", "三顺", "黑石", "浪里", "断桅", "青翰", "小满", "大鲛", "夜航"]

const RARITY_WEIGHT := [50, 28, 14, 6, 2]
const STAT_MIN := [3, 8, 15, 25, 38]
const STAT_MAX := [8, 14, 24, 36, 50]
const HIRE_COST := [200, 1200, 6000, 30000, 150000]

static func _roll_rarity() -> int:
	var total := 0
	for w in RARITY_WEIGHT:
		total += w
	var r := RngService.randi_range(1, total)
	var acc := 0
	for i in range(RARITY_WEIGHT.size()):
		acc += RARITY_WEIGHT[i]
		if r <= acc:
			return i
	return 0

static func generate(count: int, variant: StringName = &"standard") -> Array:
	var out: Array = []
	var role_pool: Array = ROLE_WEIGHTS.duplicate()
	if variant == &"navy":
		role_pool.append(&"collector")
	elif variant == &"pirate":
		role_pool.append(&"raider")
	for i in range(count):
		var r := _roll_rarity()
		var role: StringName = role_pool[RngService.randi_range(0, role_pool.size() - 1)]
		var c = CrewDefScript.new()
		c.crew_id = StringName("crew_%d_%d_%d" % [Time.get_ticks_usec(), i, RngService.randi_range(100, 999)])
		c.display_name = "%s%s" % [SURNAMES[RngService.randi_range(0, SURNAMES.size() - 1)],
			GIVEN[RngService.randi_range(0, GIVEN.size() - 1)]]
		c.role = role
		c.rarity = r
		c.stat = RngService.randi_range(STAT_MIN[r], STAT_MAX[r])
		c.wage = maxi(1, int(round(float(c.stat) * 2.5)))
		c.hire_cost = HIRE_COST[r]
		out.append(c)
	return out
