extends Node
## 场景切换 + 淡入淡出。屏幕节点统一挂在 main.tscn 的 ScreenHost 下。

const SCREENS := {
	&"menu": "res://scenes/main_menu.tscn",
	&"base": "res://scenes/base/base_scene.tscn",
	&"sea": "res://scenes/sea/sea_scene.tscn",
}

var host: Node = null
var current: Node = null
var _fade: ColorRect = null

func register_host(h: Node, fade: ColorRect) -> void:
	host = h
	_fade = fade

## 测试环境下没有 host，需要能安全跳过场景切换
func has_host() -> bool:
	return host != null and is_instance_valid(host)

func goto(screen: StringName) -> void:
	if host == null:
		push_error("[SceneRouter] 未注册 host")
		return
	var path: String = SCREENS.get(screen, "")
	if path == "":
		push_error("[SceneRouter] 未知屏幕: %s" % screen)
		return
	await _fade_to(1.0)
	if current != null and is_instance_valid(current):
		current.queue_free()
		await host.get_tree().process_frame
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("[SceneRouter] 场景载入失败: %s" % path)
		await _fade_to(0.0)
		return
	current = packed.instantiate()
	host.add_child(current)
	EventBus.screen_changed.emit(screen)
	await _fade_to(0.0)

func _fade_to(alpha: float) -> void:
	if _fade == null:
		return
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.25)
	await tw.finished
	if alpha <= 0.001:
		_fade.visible = false
