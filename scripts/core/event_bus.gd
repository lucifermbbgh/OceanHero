extends Node
## 全局信号总线。所有跨系统的通知都走这里，避免节点之间互相持有引用。

signal gold_changed(value: int)
signal cargo_changed(used: float, capacity: int)
signal hull_changed(current: float, maximum: float)
signal target_changed(target: Node)
signal combat_started(target: Node)
signal combat_finished(result: Dictionary)
signal ship_disabled(part: String)
signal ticker(text: String)
signal islands_upgraded(keys: Array)
signal screen_changed(screen: StringName)
signal game_saved(slot: int)
signal game_loaded(slot: int)
