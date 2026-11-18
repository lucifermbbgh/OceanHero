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

# ---- 1.2.0 组件化字段（数据与表现分离）----
@export var category: String = "民生"        # 民生 / 生产 / 服务 / 军事
@export var unlock_tier: int = 1              # 城镇达到几级才出现
@export var sort_order: int = 100             # 菜单与布局排序
@export var icon_path: String = ""            # 图标资源，空则文字占位
@export var scene_path: String = ""           # 建筑立绘/场景，空则表格行占位
@export var slot_id: String = ""              # 对应 TownLayout 槽位
@export var is_initial: bool = false          # 是否开局自带

static func from_id(bid: StringName) -> Resource:
	return DataRegistry.get_building(bid) if DataRegistry != null else null

func cost_for(target_level: int) -> Dictionary:
	var k := pow(float(target_level), 1.5)
	return {
		"gold": int(round(float(gold_base) * k)),
		"timber": int(round(float(timber_base) * k)),
		"iron": int(round(float(iron_base) * k)),
		"weeks": maxi(1, int(round(float(weeks_base) * pow(float(target_level), 0.5)))),
	}
