class_name PortDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var map_id: int = 0
@export var position: Vector2 = Vector2.ZERO
@export var services: Array = []
## 生产 / 需求系数：<1 盛产便宜，>1 缺货昂贵
@export var production: Dictionary = {}
@export var demand: Dictionary = {}
@export var max_stock: int = 800
