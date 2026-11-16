class_name AmmoDef
extends Resource
## 弹药。分配矩阵决定这一发打在哪个损伤池上。

@export var id: StringName = &""
@export var display_name: String = ""
@export var damage_mult: float = 1.0
@export var accuracy_mod: float = 0.0
## 四个池的伤害分配（0~1）
@export var to_hull: float = 1.0
@export var to_sail: float = 0.25
@export var to_rudder: float = 0.4
@export var to_crew: float = 0.1
@export var price_per_shot: int = 1
