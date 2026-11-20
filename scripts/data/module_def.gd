class_name ModuleDef
extends Resource
## 舰船模块定义（1.4.1）：模块类型、可装装备、可置岗位、锚点位置。

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: String = "single"        # single / deck / gundeck
@export var gear_slots: Array = []         # 可装装备类型：rudder/sail/flag/cannon/armor/figurehead/telescope
@export var crew_posts: Array = []         # 可置岗位：mate/gunner/surgeon/sailor
@export var max_level: int = 5
@export var anchor: Vector2 = Vector2(0.5, 0.5)   # 相对船模图的位置（0~1）
@export var stat_key: String = ""          # 该模块影响的属性键（1.4.2 使用）
