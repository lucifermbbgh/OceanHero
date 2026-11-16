class_name CrewDef
extends Resource
## 船员。运行时由 CrewFactory 生成（酒馆随机池），不落 .tres。

@export var crew_id: StringName = &""
@export var display_name: String = ""
@export var role: StringName = &"gunner"
@export var rarity: int = 0
@export var stat: int = 5
@export var wage: int = 10
@export var hire_cost: int = 200

func to_dict() -> Dictionary:
	return {
		"id": String(crew_id), "name": display_name, "role": String(role),
		"rarity": rarity, "stat": stat, "wage": wage, "hire_cost": hire_cost,
	}

static func from_dict(d: Dictionary) -> Resource:
	var script: GDScript = load("res://scripts/data/crew_def.gd")
	var c = script.new()
	c.crew_id = StringName(d.get("id", ""))
	c.display_name = String(d.get("name", ""))
	c.role = StringName(d.get("role", "gunner"))
	c.rarity = int(d.get("rarity", 0))
	c.stat = int(d.get("stat", 5))
	c.wage = int(d.get("wage", 10))
	c.hire_cost = int(d.get("hire_cost", 200))
	return c
