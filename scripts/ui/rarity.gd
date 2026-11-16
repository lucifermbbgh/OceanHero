class_name Rarity
extends RefCounted
## 全项目唯一的稀有度配色表（见 02-systems-design.md §17）。

const NAMES := ["普通", "精良", "稀有", "史诗", "传说"]

static func color(rarity: int) -> Color:
	match clampi(rarity, 0, 4):
		0: return Color("9E9E9E")   # N 灰
		1: return Color("1F6FA8")   # R 海蓝
		2: return Color("6B2E8F")   # SR 罗马紫
		3: return Color("D4AF37")   # SSR 黄金
	return Color("C2185B")          # UR 六色流光（简化为品红，后续换 shader）

static func name_of(rarity: int) -> String:
	return NAMES[clampi(rarity, 0, 4)]

static func label(rarity: int) -> String:
	return "%s·%s" % [name_of(rarity), NAMES[clampi(rarity, 0, 4)]]
