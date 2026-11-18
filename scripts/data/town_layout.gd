class_name TownLayout
extends Resource
## 城镇界面布局：槽位坐标化，为美术资源与点击交互预留。

@export var tier: int = 1
@export var background_path: String = ""
@export var menu_side: String = "left"
## 槽位：{id: String, x: float, y: float, w: float, h: float}
@export var slots: Array = []

func slot_of(slot_id: String) -> Dictionary:
	for s in slots:
		if String(s.get("id", "")) == slot_id:
			return s
	return {}

static func default_for(tier: int) -> Resource:
	var script: GDScript = load("res://scripts/data/town_layout.gd")
	var t = script.new()
	t.tier = tier
	t.slots = [
		{"id": "slot_governor", "x": 120.0, "y": 120.0, "w": 220.0, "h": 140.0},
		{"id": "slot_warehouse", "x": 400.0, "y": 120.0, "w": 220.0, "h": 140.0},
		{"id": "slot_tavern", "x": 680.0, "y": 120.0, "w": 220.0, "h": 140.0},
		{"id": "slot_sailmaker", "x": 960.0, "y": 120.0, "w": 220.0, "h": 140.0},
		{"id": "slot_watchtower", "x": 1240.0, "y": 120.0, "w": 220.0, "h": 140.0},
		{"id": "slot_drydock", "x": 120.0, "y": 300.0, "w": 220.0, "h": 140.0},
		{"id": "slot_foundry", "x": 400.0, "y": 300.0, "w": 220.0, "h": 140.0},
		{"id": "slot_exchange", "x": 680.0, "y": 300.0, "w": 220.0, "h": 140.0},
	]
	return t
