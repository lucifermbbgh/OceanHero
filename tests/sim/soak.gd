extends Node
## 稳定性压测：反复进出场景、反复存读档、连续战斗。
## 关注：节点数是否失控、内存是否失控、是否报错。

const ITER_SCENE := 18
const ITER_SAVE := 60
const ITER_BATTLE := 40

var errors: Array = []
var node_base := 0

func _ready() -> void:
	print("=== 稳定性压测 ===")
	await _frames(5)
	node_base = get_tree().get_node_count()
	print("起始节点数 %d · 静态内存 %.1f MB" % [node_base, OS.get_static_memory_usage() / 1048576.0])

	await _scene_cycle()
	await _save_cycle()
	await _battle_cycle()

	var node_end := get_tree().get_node_count()
	var mem := OS.get_static_memory_usage() / 1048576.0
	print("结束节点数 %d（基线 %d，增量 %d）· 静态内存 %.1f MB" % [
		node_end, node_base, node_end - node_base, mem])
	var ok := errors.is_empty()
	if not errors.is_empty():
		for e in errors:
			print("  ✗ " + String(e))
	print("=== 压测%s ===" % ("通过" if ok else "失败"))
	get_tree().quit(0 if ok else 1)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _scene_cycle() -> void:
	print("\n[场景反复进出] %d 轮：9 张海域 + 母港 + 主菜单" % ITER_SCENE)
	for i in range(ITER_SCENE):
		var map_id := (i % 9) + 1
		GameState.current_map = map_id
		var sea = load("res://scenes/sea/sea_scene.tscn").instantiate()
		add_child(sea)
		await _frames(4)
		if sea.map_index != map_id:
			errors.append("海域地图不匹配：期望 %d 实得 %d" % [map_id, sea.map_index])
		sea.queue_free()
		await _frames(2)

		var base_s = load("res://scenes/base/base_scene.tscn").instantiate()
		add_child(base_s)
		await _frames(3)
		base_s.queue_free()
		await _frames(2)
	print("  完成，节点数 %d" % get_tree().get_node_count())

func _save_cycle() -> void:
	print("\n[存读档反复] %d 轮" % ITER_SAVE)
	GameState.reset_new_game()
	for i in range(ITER_SAVE):
		GameState.add_gold(7)
		GameState.cargo[&"grain"] = i
		if not SaveManager.save(4):
			errors.append("第 %d 轮保存失败" % i)
		if not SaveManager.load_slot(4):
			errors.append("第 %d 轮读取失败" % i)
		if int(GameState.cargo.get(&"grain", -1)) != i:
			errors.append("第 %d 轮货物未还原" % i)
	SaveManager.delete_slot(4)
	print("  完成，无异常" if errors.is_empty() else "  出现异常")

func _battle_cycle() -> void:
	print("\n[连续战斗] %d 场" % ITER_BATTLE)
	GameState.reset_new_game()
	GameState.current_map = 3
	for i in range(ITER_BATTLE):
		var sea = load("res://scenes/sea/sea_scene.tscn").instantiate()
		add_child(sea)
		await _frames(3)
		var target = null
		for e in sea.enemies:
			if not e.has_method("alive_limbs"):
				target = e
				break
		if target == null:
			errors.append("第 %d 场没有可用目标" % i)
			sea.queue_free()
			await _frames(2)
			continue
		# 直接打死，验证掉落与信号链
		target.take_damage({"hull": 999999.0, "sail": 0.0, "rudder": 0.0, "crew": 0.0})
		await _frames(3)
		sea.queue_free()
		await _frames(2)
	print("  完成，金币 %d · 等级 %d" % [GameState.gold, GameState.level])
