class_name ShipDef
extends Resource
## 舰船定义（基准值）。实际船体 = 本表 × 变体倍率。

@export var id: StringName = &""
@export var display_name: String = ""
@export var tier: int = 1
@export var variant: StringName = &"standard"
@export var ship_class: String = ""
@export var base_hp: int = 400
@export var base_speed: float = 4.5
@export var turn_rate: float = 45.0
@export var cargo_capacity: int = 200
@export var crew_capacity: int = 6
@export var cannon_slots: int = 1
@export var guns_per_side: int = 1
@export var max_cannon_weight: int = 3
@export var armor_base: int = 0
@export var price: int = 500
@export var description: String = ""

func sail_pool() -> float:
	return float(base_hp) * 0.25

func rudder_pool() -> float:
	return float(base_hp) * 0.15

func crew_pool() -> float:
	return float(crew_capacity) * 10.0
