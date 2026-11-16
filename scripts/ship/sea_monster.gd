extends CharacterBody2D
## 海怪：躯体 + 肢体 + 狂怒。不能接舷、不能俘获、链弹无效。

signal died(ship, info)

var display_name := "海怪"
var faction := "monster"
var alive := true

var body_max := 600.0
var body_hp := 600.0
var limb_count := 2
var limb_hp: Array = []
var limb_max := 150.0
var frenzy := false

var attack_interval := 4.0
var attack_damage := 30.0
var attack_timer := 3.0
var move_speed := 90.0

var target = null
var xp_reward := 0
var gold_min := 0
var gold_max := 0
var loot_commodity := &""
var loot_amount := 0
var gear_drop_chance := 0.0
var loot_mult := 1.0
var enemy_id: StringName = &""
var is_boss := false
var boss_phase := 1
var base_attack_ref := 0.0

var _sway := 0.0
var external_push := Vector2.ZERO

func _ready() -> void:
	# 与船一致：不与任何实体碰撞，避免冲撞型敌人互相卡住
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 48.0
	shape.shape = circle
	add_child(shape)

func setup(edef: Resource, level_scale: float = 1.0) -> void:
	enemy_id = edef.id
	display_name = edef.display_name
	body_max = float(edef.body_hp) * level_scale
	body_hp = body_max
	limb_count = int(edef.limb_count)
	limb_max = body_max * 0.25
	limb_hp.clear()
	for i in range(limb_count):
		limb_hp.append(limb_max)
	attack_interval = float(edef.attack_interval)
	attack_damage = float(edef.attack_damage) * sqrt(level_scale)
	base_attack_ref = attack_damage
	xp_reward = int(edef.xp_reward)
	gold_min = int(edef.gold_min)
	gold_max = int(edef.gold_max)
	loot_commodity = edef.loot_commodity
	loot_amount = int(edef.loot_amount)
	gear_drop_chance = float(edef.gear_drop_chance)
	queue_redraw()

func body_pct() -> float:
	return clampf(body_hp / maxf(1.0, body_max), 0.0, 1.0)

func alive_limbs() -> int:
	var n := 0
	for hp in limb_hp:
		if hp > 0.0:
			n += 1
	return n

func _physics_process(delta: float) -> void:
	if not alive:
		velocity = Vector2.ZERO
		return
	_sway += delta
	if target != null and is_instance_valid(target) and target.alive:
		var to_t: Vector2 = target.global_position - global_position
		var dist := to_t.length()
		if dist > 120.0:
			var spd := move_speed * (1.3 if frenzy else 1.0)
			velocity = to_t.normalized() * spd
		else:
			velocity = Vector2.ZERO
		attack_timer -= delta
		if attack_timer <= 0.0 and dist <= 220.0:
			_attack()
			attack_timer = attack_interval
	else:
		velocity = Vector2.ZERO
	velocity += external_push
	external_push = Vector2.ZERO
	move_and_slide()
	queue_redraw()

func _attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	var dmg := attack_damage * (1.5 if frenzy else 1.0)
	# 冲撞打船体，肢体越多撕咬越狠
	var res := {
		"hit": 1.0, "raw": dmg,
		"hull": dmg, "sail": dmg * 0.15, "rudder": dmg * 0.1, "crew": dmg * 0.25 * float(alive_limbs()) * 0.5,
	}
	target.take_damage(res)

func take_damage(res: Dictionary) -> void:
	if not alive:
		return
	# 链弹对海怪无效
	var hull_dmg := float(res.get("hull", 0.0))
	if hull_dmg <= 0.0:
		return
	body_hp = maxf(0.0, body_hp - hull_dmg)
	# 一部分伤害转移到肢体
	var limb_dmg := hull_dmg * 0.35
	for i in range(limb_hp.size()):
		if limb_hp[i] > 0.0:
			limb_hp[i] = maxf(0.0, limb_hp[i] - limb_dmg)
			break
	if is_boss:
		if boss_phase == 1 and body_pct() <= 0.66:
			boss_phase = 2
			attack_damage = base_attack_ref * 1.3
		elif boss_phase == 2 and body_pct() <= 0.33:
			boss_phase = 3
			attack_damage = base_attack_ref * 1.6
	if not frenzy and body_pct() <= 0.30:
		frenzy = true
		move_speed *= 1.3
	if body_hp <= 0.0:
		alive = false
		died.emit(self, {"sunk": true, "captured": false, "monster": true})
	queue_redraw()

func _draw() -> void:
	var col: Color = Color(0.65, 0.22, 0.22) if frenzy else Color(0.32, 0.28, 0.22)
	draw_circle(Vector2.ZERO, 44.0, col)
	draw_arc(Vector2.ZERO, 44.0, 0, TAU, 24, Color(0.9, 0.85, 0.6), 2.0)
	# 肢体
	for i in range(limb_hp.size()):
		var ang := TAU * float(i) / float(maxi(1, limb_hp.size())) + _sway * 0.7
		var dir := Vector2.RIGHT.rotated(ang)
		var alive_l: bool = float(limb_hp[i]) > 0.0
		var c: Color = Color(0.42, 0.34, 0.24) if alive_l else Color(0.2, 0.18, 0.15)
		draw_line(dir * 34.0, dir * 72.0, c, 7.0 if alive_l else 3.0)
	# 血条
	var w := 70.0
	var y := -70.0
	draw_rect(Rect2(-w * 0.5, y, w, 5), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w * 0.5, y, w * body_pct(), 5), Color(0.75, 0.25, 0.25))
