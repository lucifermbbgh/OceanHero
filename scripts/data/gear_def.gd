class_name GearDef
extends Resource
## 非火炮类装备（火炮用 CannonDef）。五个部位：风帆 / 船舵 / 装甲 / 船首像 / 旗帜。

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: StringName = &"sail"      # sail / rudder / armor / figurehead / flag
@export var rarity: int = 0                  # 0 N / 1 R / 2 SR / 3 SSR / 4 UR
@export var speed_pct: float = 0.0
@export var turn_pct: float = 0.0
@export var armor_add: int = 0
@export var boarding_add: int = 0
@export var price: int = 0
@export var view_add: float = 0.0        # 望远镜：视野
@export var reload_pct: float = 0.0      # 旗帜：装填
@export var rep_gain_pct: float = 0.0    # 旗帜：声望获取
@export var description: String = ""

func bonus_text() -> String:
	var parts: Array = []
	if absf(speed_pct) > 0.0001:
		parts.append("航速 %+d%%" % int(round(speed_pct * 100.0)))
	if absf(turn_pct) > 0.0001:
		parts.append("转向 %+d%%" % int(round(turn_pct * 100.0)))
	if armor_add != 0:
		parts.append("装甲 %+d" % armor_add)
	if boarding_add != 0:
		parts.append("接舷 %+d" % boarding_add)
	if parts.is_empty():
		return "无属性加成"
	return " · ".join(parts)
