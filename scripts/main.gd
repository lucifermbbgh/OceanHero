extends Control
## 应用外壳：持有屏幕容器与淡入淡出层。

func _ready() -> void:
	var fade: ColorRect = $FadeLayer/Fade
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	SceneRouter.register_host($ScreenHost, fade)
	set_process_unhandled_input(true)
	SceneRouter.goto(&"menu")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		DataRegistry.reload_all()
