class_name BuildingDef
extends Resource
## 母港建筑。等级 0~5。

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var effect_text: String = ""
@export var max_level: int = 5
@export var gold_base: int = 1000
@export var timber_base: int = 0
@export var iron_base: int = 0
@export var weeks_base: int = 2
@export var production: Dictionary = {}

func cost_for(target_level: int) -> Dictionary:
	var k := pow(float(target_level), 1.5)
	return {
		"gold": int(round(float(gold_base) * k)),
		"timber": int(round(float(timber_base) * k)),
		"iron": int(round(float(iron_base) * k)),
		"weeks": maxi(1, int(round(float(weeks_base) * pow(float(target_level), 0.5)))),
	}
