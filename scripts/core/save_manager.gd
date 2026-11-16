extends Node
## 存档：JSON + 原子写入 + 版本号。

const SAVE_DIR := "user://saves"
const CURRENT_SCHEMA := 1
const AUTO_SLOT := 0
const MANUAL_SLOTS := 5

func auto_save() -> bool:
	return save(AUTO_SLOT)

func all_slot_ids() -> Array:
	var out: Array = [AUTO_SLOT]
	for i in range(1, MANUAL_SLOTS + 1):
		out.append(i)
	return out

## 只读表头：给存档位 UI 用
func slot_meta(slot: int) -> Dictionary:
	if not has_save(slot):
		return {"exists": false}
	var text := FileAccess.get_file_as_string(slot_path(slot))
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"exists": true, "broken": true}
	var d: Dictionary = parsed
	var p: Dictionary = d.get("player", {})
	var w: Dictionary = d.get("world", {})
	return {
		"exists": true,
		"broken": false,
		"name": String(p.get("name", "船长")),
		"level": int(p.get("level", 1)),
		"gold": int(p.get("gold", 0)),
		"commendation": int(p.get("commendation", 0)),
		"map": int(w.get("current_map", 1)),
		"saved_at": float(d.get("playtime", 0)),
	}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

func save(slot: int) -> bool:
	var data := GameState.to_dict()
	data["clock_time"] = TimeService.to_dict()
	data["playtime"] = Time.get_unix_time_from_system()
	var tmp := slot_path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 无法写入 %s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f = null
	# 原子替换
	var final_path := slot_path(slot)
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(final_path))
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(final_path))
	if err != OK:
		push_error("[SaveManager] 原子替换失败: %d" % err)
		return false
	EventBus.game_saved.emit(slot)
	return true

func load_slot(slot: int) -> bool:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[SaveManager] 存档损坏: %s" % path)
		return false
	var data: Dictionary = parsed
	var schema := int(data.get("schema", 0))
	if schema > CURRENT_SCHEMA:
		push_error("[SaveManager] 存档版本过新: %d" % schema)
		return false
	GameState.from_dict(data)
	TimeService.from_dict(data.get("clock_time", {}))
	EventBus.game_loaded.emit(slot)
	return true

func delete_slot(slot: int) -> void:
	var p := slot_path(slot)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
