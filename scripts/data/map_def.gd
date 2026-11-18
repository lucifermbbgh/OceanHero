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

## 1.3.1：大级别（1~10）与国家归属
@export var tier: int = 1              # 大级别 1~10
@export var nation: StringName = &""   # 所属国 id；空表示交界/争夺
@export var contested: bool = false    # 是否交界/争夺图
@export var neighbors: Array = []      # 1.3.2 邻接图：可通行的相邻海图索引
