class_name MapDef
extends Resource
## 单张海图。图 0 是母港，图 1~9 是递进的海域。

@export var id: StringName = &""
@export var index: int = 1
@export var display_name: String = ""
@export var level_min: int = 1
@export var level_max: int = 3
@export var hostile: bool = false
@export var pirates: int = 6
@export var monsters: int = 2
@export var pirate_boss: StringName = &""
@export var monster_boss: StringName = &""
@export var island_seed: int = 1
