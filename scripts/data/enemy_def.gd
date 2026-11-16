class_name EnemyDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = &"pirate"     # pirate / monster
@export var tier: int = 1
@export var based_on_ship: StringName = &"fishing_sloop"
@export var based_on_cannon: StringName = &"pound3_light"
@export var hp_mult: float = 1.0
@export var damage_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var aggro_radius: float = 0.0
@export var xp_reward: int = 10
@export var gold_min: int = 20
@export var gold_max: int = 60
@export var loot_commodity: StringName = &"grain"
@export var loot_amount: int = 5
@export var gear_drop_chance: float = 0.15
@export var commendation_reward: int = 0     # 战功：仅 Boss / 精英 应设 > 0
## Boss 特化：独有装备与独有船员（不设技能，靠配置差异化）
@export var unique_gear: StringName = &""
@export var unique_crew_name: String = ""
@export var unique_crew_role: StringName = &""
@export var unique_crew_stat: int = 0
## 海怪专用
@export var limb_count: int = 2
@export var body_hp: float = 800.0
@export var attack_interval: float = 4.0
@export var attack_damage: float = 40.0
