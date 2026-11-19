extends Node2D
## 势力巡逻队：沿航线巡航，遇敌对势力开战（轻量结算，无战利品）

var nation_id: String = ""
var hp: float = 120.0
var guns: int = 4
var speed: float = 60.0
var waypoints: Array = []
var wp_index: int = 0
var target: Node = null
var alive: bool = true
var fire_cd: float = 1.0
var name_label: Label = null
var color: Color = Color(0.75, 0.7, 0.4)

const MAX_HP := 120.0
const SIGHT := 420.0
const RELOAD := 1.0

func setup(nation_key: String, route: Array, col: Color) -> void:
	nation_id = nation_key
	waypoints = route
	color = col
	var f := ThemeDB.fallback_font
	name_label = Label.new()
	name_label.text = String(GameState.NATION_NAMES.get(nation_key, nation_key))
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", col)
	name_label.position = Vector2(-24, -34)
	add_child(name_label)

func _ready() -> void:
	z_index = 3

func _process(delta: float) -> void:
	if not alive:
		return
	_tick_combat(delta)
	_tick_move(delta)
	queue_redraw()

func _tick_move(delta: float) -> void:
	if target != null and is_instance_valid(target):
		var to: Vector2 = target.global_position - global_position
		if to.length() > 1.0:
			global_position += to.normalized() * speed * 0.6 * delta
		return
	if waypoints.is_empty():
		return
	var wp: Vector2 = waypoints[wp_index]
	var d: Vector2 = wp - global_position
	if d.length() < 30.0:
		wp_index = (wp_index + 1) % waypoints.size()
	else:
		global_position += d.normalized() * speed * delta

func _tick_combat(delta: float) -> void:
	fire_cd -= delta
	if fire_cd > 0.0:
		return
	fire_cd = RELOAD
	if target == null or not is_instance_valid(target) or not target.alive:
		target = null
		var best: Node = null
		var best_d := SIGHT
		for p in get_tree().get_nodes_in_group("patrols"):
			if p == self or not p.alive:
				continue
			if GameState.nation_relation_between(nation_id, p.nation_id) != "hostile":
				continue
			var d2: float = global_position.distance_to(p.global_position)
			if d2 < best_d:
				best_d = d2
				best = p
		target = best
	if target != null and is_instance_valid(target):
		target.take_damage(float(guns) * 6.0)

func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		_sink()

func _sink() -> void:
	alive = false
	remove_from_group("patrols")
	# 不产生战利品（设计约定）
	queue_free()

func _draw() -> void:
	if not alive:
		return
	draw_circle(Vector2.ZERO, 16.0, color)
	draw_arc(Vector2.ZERO, 20.0, 0, TAU, 20, color.lightened(0.3), 2.0)
	var w := 34.0
	draw_rect(Rect2(-w * 0.5, -26, w, 5), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(-w * 0.5, -26, w * clampf(hp / MAX_HP, 0.0, 1.0), 5), Color(0.85, 0.35, 0.3))
