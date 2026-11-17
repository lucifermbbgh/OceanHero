extends RefCounted
## 市场事件：驱动价格波动的"原因层"

const EVENTS := {
	&"harvest": {"name": "丰收", "target": &"grain", "kind": "supply", "value": -0.20, "desc": "谷物供给 +25%"},
	&"poor_harvest": {"name": "歉收", "target": &"grain", "kind": "supply", "value": 0.20, "desc": "谷物供给 −25%"},
	&"forest_bloom": {"name": "林木茂盛", "target": &"timber", "kind": "supply", "value": -0.16, "desc": "木材供给 +20%"},
	&"quake": {"name": "港口地震", "target": &"timber", "kind": "supply", "value": 0.25, "desc": "木材产出 −40%"},
	&"war": {"name": "战争阴云", "target": &"spice", "kind": "demand", "value": 0.15, "desc": "香料需求 +15%"},
	&"rum_fest": {"name": "朗姆酒节", "target": &"rum", "kind": "demand", "value": 0.22, "desc": "朗姆酒需求 +30%"},
	&"blockade": {"name": "海盗封锁", "target": &"", "kind": "supply", "value": 0.18, "desc": "全港供给 −20%"},
	&"caravan": {"name": "商队抵达", "target": &"", "kind": "supply", "value": -0.14, "desc": "全港供给 +15%"},
}

const MAX_ACTIVE := 8
const WEEKLY_CHANCE := 0.15

## 为某港口生成一个事件（可能返回 null）
static func roll_event(port_key: String, week: int) -> Dictionary:
	var h := 2166136261
	for ch in (port_key + str(week)).to_utf8_buffer():
		h = (h ^ int(ch)) * 16777619
		h = h & 0x7fffffff
	if float(h % 10000) / 10000.0 >= WEEKLY_CHANCE:
		return {}
	var ids: Array = EVENTS.keys()
	var pick: StringName = ids[(h / 7) % ids.size()]
	var def: Dictionary = EVENTS[pick]
	return {
		"id": pick, "name": String(def.get("name", "")), "port": port_key,
		"target": String(def.get("target", "")), "kind": String(def.get("kind", "")),
		"value": float(def.get("value", 0.0)), "weeks": 1 + (h / 13) % 3,
		"desc": String(def.get("desc", "")),
	}

## 推进一周：周数减一，过期的移除
static func tick(events: Array) -> Array:
	var kept: Array = []
	for e in events:
		e["weeks"] = int(e.get("weeks", 1)) - 1
		if int(e["weeks"]) > 0:
			kept.append(e)
	return kept

## 某港口某商品受事件影响的价格倍率（1.0 表示无影响）
static func effect_at(events: Array, port_key: String, cid: StringName) -> float:
	var mult := 1.0
	for e in events:
		if String(e.get("port", "")) != port_key:
			continue
		var tgt := String(e.get("target", ""))
		if tgt != "" and tgt != String(cid):
			continue
		var v := float(e.get("value", 0.0))
		var kind := String(e.get("kind", "supply"))
		# 供给增加 → 价格下降；需求增加 → 价格上升
		if kind == "supply":
			mult *= (1.0 - v)
		else:
			mult *= (1.0 + v)
	return mult
