extends CharacterBody2D
## 通用的"海上单位"：玩家船与 NPC 船共用。海怪走 sea_monster.gd。

const CombatResolver = preload("res://scripts/systems/combat_resolver.gd")

signal died(ship, info)
signal disengaged(ship)
signal stats_changed(ship)

var is_player := false
var display_name := "船"
var faction := "pirate"

# ---- 四个损伤池 ----
var hull_max := 400.0
var hull_hp := 400.0
var sail_max := 100.0
var sail_hp := 100.0
var rudder_max := 60.0
var rudder_hp := 60.0
var crew_max := 60.0
var crew_hp := 60.0

# ---- 属性 ----
var base_speed_px := 126.0
var turn_rate := 45.0
var armor := 0
var guns_per_side := 1
var boarding_bonus := 0
var crew_reload_bonus := 0.0
var crew_accuracy := 0.0
var boarding_pct := 0.0
var view_bonus := 0.0
var cannon_damage := 18.0
var cannon_range := 900.0
var cannon_reload := 2.0
var accuracy_mod := 0.0
var ammo: Resource = null
var ammo_id: StringName = &"solid"

# ---- 运行时 ----
## 脱战：距离超过此值且持续 DISENGAGE_TIME 秒，NPC 放弃追击
const DISENGAGE_DIST := 1600.0
const DISENGAGE_TIME := 5.0

var target = null
var reload_timer := 0.0
var disengage_timer := 0.0
var _last_target = null
var wander_heading := 0.0
var wander_timer := 0.0
var home_pos := Vector2.ZERO
var obstacles: Array = []      # 场景注入的岛屿列表 [[中心, 半径], ...]
var world_bounds := Rect2(0, 0, 8000, 8000)   # 场景注入：航行边界
var auto_fire := false         # 玩家：锁定后是否持续自动开火（按「开火」切换）
var _avoiding := false         # 是否正在绕障（带滞回）
var _avoid_side := 1.0         # 锁定的绕行侧，进入时决定，离开前不变
var cargo_hold: Dictionary = {}   # NPC 携带的货物（击沉后掉 30%）
var last_attacker = null
var dodging := false           # 玩家按下撤离后的一段时间内处于"主动脱离"
var dodge_timer := 0.0
var heading := 0.0
var nav_target = null
var nav_queue: Array = []
var external_push := Vector2.ZERO
var terrain_slow := 1.0
var throttle := 0.0
var alive := true
var engaged := false
var volleys_fired := 0
var damage_taken := 0.0

# ---- 掉落 ----
var xp_reward := 0
var gold_min := 0
var gold_max := 0
var loot_commodity := &""
var loot_amount := 0
var gear_drop_chance := 0.0
var commendation_reward := 0
var loot_mult := 1.0
var enemy_id: StringName = &""
var unique_gear: StringName = &""
var unique_crew_name := ""
var unique_crew_role: StringName = &""
var unique_crew_stat := 0
var is_boss := false
var boss_phase := 1
var base_damage_ref := 0.0
var base_reload_ref := 0.0

func _ready() -> void:
	# 原作规则：船与船、船与怪之间没有碰撞体积，可以叠在一起。
	# layer 保留给未来射线/点选用，mask 置 0 表示不检测任何实体。
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 26.0
	shape.shape = circle
	add_child(shape)
	scale = Vector2(1.35, 1.35)
	if ammo == null:
		ammo = load("res://data/ammo/solid.tres")

# ---------------- 配置 ----------------

func setup_player(def: Resource) -> void:
	is_player = true
	faction = "player"
	var st: Dictionary = GameState.stats()
	display_name = "%s·%s" % [def.display_name, String(st.get("variant_name", ""))]
	hull_max = float(st.get("hull_max", 400.0))
	sail_max = float(st.get("sail_max", 100.0))
	rudder_max = float(st.get("rudder_max", 60.0))
	crew_max = float(st.get("crew_max", 60.0))
	hull_hp = clampf(GameState.hull_hp if GameState.hull_hp >= 0.0 else hull_max, 0.0, hull_max)
	sail_hp = sail_max * GameState.sail_pct
	rudder_hp = rudder_max * GameState.rudder_pct
	crew_hp = crew_max * GameState.crew_pct
	base_speed_px = float(st.get("base_speed_px", 126.0))
	turn_rate = float(st.get("turn_rate", 45.0))
	armor = int(st.get("armor", 0))
	guns_per_side = int(st.get("guns_per_side", 1))
	boarding_bonus = int(st.get("boarding", 0))
	crew_reload_bonus = float(st.get("reload_bonus", 0.0))
	crew_accuracy = float(st.get("accuracy_bonus", 0.0))
	boarding_pct = float(st.get("boarding_pct", 0.0))
	view_bonus = float(st.get("view_bonus", 0.0))
	var cannon: Resource = DataRegistry.get_cannon(GameState.cannon_id)
	if cannon == null:
		cannon = DataRegistry.get_cannon(&"pound3_light")
	cannon_damage = float(cannon.damage)
	cannon_range = float(cannon.shot_range)
	cannon_reload = float(cannon.reload_seconds)
	accuracy_mod = float(cannon.accuracy_mod)
	queue_redraw()

func setup_enemy(edef: Resource, level_scale: float = 1.0) -> void:
	is_player = false
	faction = "navy" if StringName(edef.kind) == &"navy" else "pirate"
	enemy_id = edef.id
	display_name = edef.display_name
	var sdef: Resource = DataRegistry.get_ship(edef.based_on_ship)
	var cdef: Resource = DataRegistry.get_cannon(edef.based_on_cannon)
	hull_max = float(sdef.base_hp) * float(edef.hp_mult) * level_scale
	sail_max = sdef.sail_pool() * level_scale
	rudder_max = sdef.rudder_pool() * level_scale
	crew_max = sdef.crew_pool() * level_scale
	hull_hp = hull_max
	sail_hp = sail_max
	rudder_hp = rudder_max
	crew_hp = crew_max
	base_speed_px = float(sdef.base_speed) * 28.0 * float(edef.speed_mult)
	turn_rate = float(sdef.turn_rate)
	armor = int(sdef.armor_base)
	guns_per_side = int(sdef.guns_per_side)
	cannon_damage = float(cdef.damage) * float(edef.damage_mult) * sqrt(level_scale)
	cannon_range = float(cdef.shot_range)
	cannon_reload = float(cdef.reload_seconds)
	accuracy_mod = float(cdef.accuracy_mod)
	throttle = 0.6
	xp_reward = int(round(float(edef.xp_reward) * level_scale))
	gold_min = int(round(float(edef.gold_min) * level_scale))
	gold_max = int(round(float(edef.gold_max) * level_scale))
	loot_commodity = edef.loot_commodity
	loot_amount = int(round(float(edef.loot_amount) * level_scale))
	gear_drop_chance = float(edef.gear_drop_chance)
	commendation_reward = int(edef.commendation_reward)
	unique_gear = StringName(edef.unique_gear)
	unique_crew_name = String(edef.unique_crew_name)
	unique_crew_role = StringName(edef.unique_crew_role)
	unique_crew_stat = int(edef.unique_crew_stat)
	base_damage_ref = cannon_damage
	base_reload_ref = cannon_reload
	wander_heading = heading
	wander_timer = RngService.randf_range(2.0, 6.0)
	home_pos = global_position
	queue_redraw()

# ---------------- 状态查询 ----------------

## 粗略战力：船体 × 单位时间输出。只用于 NPC 的"打不打得过"判断
func combat_power() -> float:
	var dps := float(maxi(1, guns_per_side)) * cannon_damage / maxf(0.2, cannon_reload)
	return hull_hp * 0.6 + dps * 26.0

func sail_pct() -> float:
	return clampf(sail_hp / maxf(1.0, sail_max), 0.0, 1.0)

func rudder_pct() -> float:
	return clampf(rudder_hp / maxf(1.0, rudder_max), 0.0, 1.0)

func crew_pct() -> float:
	return clampf(crew_hp / maxf(1.0, crew_max), 0.0, 1.0)

func hull_pct() -> float:
	return clampf(hull_hp / maxf(1.0, hull_max), 0.0, 1.0)

func can_retreat() -> bool:
	return CombatResolver.can_retreat(sail_hp, rudder_hp)

func can_target(target_ship) -> bool:
	if target_ship == null or not is_instance_valid(target_ship):
		return false
	return global_position.distance_to(target_ship.global_position) <= cannon_range

# ---------------- 主循环 ----------------

func _physics_process(delta: float) -> void:
	if not alive:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_update_steering(delta)
	_update_firing(delta)
	move_and_slide()
	# 不允许驶出海域边界（玩家与 NPC 都受限）
	var b := world_bounds
	global_position = global_position.clamp(b.position + Vector2(70, 70), b.end - Vector2(70, 70))
	queue_redraw()

func _update_steering(delta: float) -> void:
	var turn_mult := CombatResolver.turn_mult(rudder_pct())
	var speed_mult := CombatResolver.speed_mult(sail_pct())
	var desired_turn := 0.0
	var desired_throttle := throttle

	if is_player:
		# 手动输入优先
		var input_turn := 0.0
		if Input.is_action_pressed("steer_left"):
			input_turn -= 1.0
		if Input.is_action_pressed("steer_right"):
			input_turn += 1.0
		if input_turn != 0.0:
			nav_target = null
			nav_queue.clear()
			desired_turn = input_turn
		else:
			if nav_target == null and not nav_queue.is_empty():
				nav_target = nav_queue.pop_front()
			if nav_target != null:
				var to_target: Vector2 = nav_target - global_position
				if to_target.length() < 60.0:
					nav_target = null
					desired_throttle = 0.0
				else:
					desired_turn = _turn_toward(to_target.angle())
					desired_throttle = 1.0
		if Input.is_action_pressed("sail_forward"):
			desired_throttle = maxf(desired_throttle, 1.0)
		if Input.is_action_pressed("sail_back"):
			desired_throttle = 0.0
		# 交战中接管：自动靠近并保持距离
		if engaged and target != null and is_instance_valid(target):
			var dist: float = global_position.distance_to(target.global_position)
			if dist > cannon_range * 0.8:
				desired_turn = _turn_toward((target.global_position - global_position).angle())
				desired_throttle = 1.0
			else:
				desired_throttle = 0.12
	else:
		desired_turn = _ai_steer(delta)

	# turn_rate 数据里是「度/秒」，这里必须转成弧度，否则转向快 57 倍（船头会疯狂抽搐）
	heading += clampf(desired_turn, -1.0, 1.0) * deg_to_rad(turn_rate) * turn_mult * delta
	rotation = heading
	var mod_bonus := 1.0
	if is_player and GameState != null:
		mod_bonus = 1.0 + GameState.ship_sail_bonus()
	var target_speed := base_speed_px * speed_mult * mod_bonus * clampf(desired_throttle, 0.0, 1.0)
	# 岛屿软约束：斥力来自 sea_scene 每帧写入的 external_push
	velocity = Vector2(target_speed, 0).rotated(heading) * terrain_slow + external_push
	external_push = Vector2.ZERO
	terrain_slow = 1.0

func _turn_toward(want: float) -> float:
	var diff := wrapf(want - heading, -PI, PI)
	return clampf(diff * 2.0, -1.0, 1.0)

## 前视避障：正前方 320px 若压进岛屿减速带，就沿切线滑开。
## 关键：**进入时锁定绕行侧**并加滞回半径，否则会在左右切线之间逐帧翻转（船头抽搐）。
func _avoidance_turn() -> float:
	if obstacles.is_empty():
		return 0.0
	var look: Vector2 = global_position + Vector2.RIGHT.rotated(heading) * 320.0
	var hit_c := Vector2.ZERO
	var found := false
	for o in obstacles:
		var c: Vector2 = o[0]
		var r_in: float = o[1] + 150.0 + 90.0
		# 已在避障中时用更大的退出半径，避免刚脱离又立刻触发
		var r := (r_in + 110.0) if _avoiding else r_in
		if look.distance_to(c) < r:
			hit_c = c
			found = true
			break
	if not found:
		_avoiding = false
		return 0.0
	var away: Vector2 = global_position - hit_c
	if away.length() < 1.0:
		away = Vector2.RIGHT
	var tangent := Vector2(-away.y, away.x).normalized()
	if not _avoiding:
		# 首次进入：按当前朝向选一侧，之后一直沿这一侧绕，不再重算
		_avoiding = true
		var d1 := absf(wrapf(tangent.angle() - heading, -PI, PI))
		var d2 := absf(wrapf((-tangent).angle() - heading, -PI, PI))
		_avoid_side = 1.0 if d1 <= d2 else -1.0
	var dir := tangent * _avoid_side
	# 死区 + 限幅：否则会在"对准切线"附近来回过冲，导致船头高频抽搐
	var diff := wrapf(dir.angle() - heading, -PI, PI)
	if absf(diff) < 0.05:
		return 0.0
	return clampf(diff * 1.2, -0.6, 0.6)

func _ai_steer(delta: float) -> float:
	var avoid := _avoidance_turn()
	# 只要还在绕障中（_avoiding），就独占转向权：
	# 否则"返航/巡游"会插进来把船头往回掰，与避障逐帧互相覆盖 → 抽搐
	if _avoiding or avoid != 0.0:
		throttle = maxf(throttle, 0.4)
		return avoid
	if faction == "merchant" and target != null and is_instance_valid(target):
		# 商船逃向远离威胁的方向
		var away: Vector2 = global_position - target.global_position
		throttle = 1.0
		return _turn_toward(away.angle())
	if target != null and is_instance_valid(target):
		var dist: float = global_position.distance_to(target.global_position)
		if dist > cannon_range * 0.75:
			throttle = 1.0
			return _turn_toward((target.global_position - global_position).angle())
		throttle = 0.1
		return 0.0
	if nav_target != null:
		var to_target: Vector2 = nav_target - global_position
		if to_target.length() < 40.0:
			nav_target = null
			throttle = 0.0
			return 0.0
		throttle = 0.6
		return _turn_toward(to_target.angle())
	# 无目标：在"属地"附近缓慢巡游，不会全图乱窜去追玩家
	var to_home: Vector2 = home_pos - global_position
	if home_pos != Vector2.ZERO and to_home.length() > 1300.0:
		throttle = 0.7
		return _turn_toward(to_home.angle())
	wander_timer -= delta
	if wander_timer <= 0.0:
		wander_timer = RngService.randf_range(4.0, 9.0)
		wander_heading = heading + RngService.randf_range(-PI * 0.7, PI * 0.7)
	throttle = 0.25
	var wdiff := wrapf(wander_heading - heading, -PI, PI)
	if absf(wdiff) < 0.08:
		return 0.0
	return clampf(wdiff * 1.5, -0.6, 0.6)

func _update_firing(delta: float) -> void:
	_update_disengage(delta)
	if dodging:
		dodge_timer -= delta
		if dodge_timer <= 0.0:
			dodging = false
	# 换目标（含首次锁定）时重新开始一轮装填，避免"刚锁定就立刻开火"
	if target != _last_target:
		_last_target = target
		if target != null and is_instance_valid(target):
			reload_timer = CombatResolver.reload_time(cannon_reload, crew_pct(), crew_reload_bonus)
			disengage_timer = 0.0
	if target == null or not is_instance_valid(target):
		return
	if not target.alive:
		target = null
		engaged = false
		return
	# 锁定即开始装填；是否开火由玩家决定
	if reload_timer > 0.0:
		reload_timer -= delta
	# 玩家：任何情况下都不会自己开火，必须由玩家点「开火」才打一轮
	if is_player:
		auto_fire = false
		return
	# 商船只逃不打
	if faction == "merchant":
		return
	if reload_timer > 0.0:
		return
	if not can_target(target):
		return
	_fire_at(target)

## 玩家主动齐射。返回是否真的打出去了
func try_fire() -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {"ok": false, "reason": "没有锁定目标"}
	if not target.alive:
		return {"ok": false, "reason": "目标已沉没"}
	if reload_timer > 0.0:
		return {"ok": false, "reason": "装填中 %.1fs" % reload_timer}
	if not can_target(target):
		return {"ok": false, "reason": "目标超出射程"}
	_fire_at(target)
	return {"ok": true}

## 玩家是否可以立即开火
func ready_to_fire() -> bool:
	if target == null or not is_instance_valid(target) or not target.alive:
		return false
	return reload_timer <= 0.0 and can_target(target)

## 脱战：拉开足够距离并维持一段时间后放弃追击
func _update_disengage(delta: float) -> void:
	if is_player or target == null or not is_instance_valid(target):
		disengage_timer = 0.0
		return
	var d: float = global_position.distance_to(target.global_position)
	if d > DISENGAGE_DIST:
		disengage_timer += delta
		if disengage_timer >= DISENGAGE_TIME:
			target = null
			engaged = false
			nav_target = null
			disengage_timer = 0.0
			disengaged.emit(self)
	else:
		disengage_timer = 0.0

func _fire_at(enemy) -> void:
	volleys_fired += 1
	var atk := {
		"guns_per_side": guns_per_side,
		"cannon_damage": cannon_damage,
		"quality_mult": 1.0,
		"gunnery": 0.0,
		"accuracy_mod": accuracy_mod + crew_accuracy,
	}
	var enemy_armor: float = 0.0
	var raw_armor: Variant = enemy.get("armor")
	if raw_armor != null:
		enemy_armor = float(raw_armor)
	var dfd := {"armor": enemy_armor, "evasion": 0.0}
	var res: Dictionary = CombatResolver.volley(atk, dfd, ammo)
	# 海军制式火炮：持有即 +10% 火炮伤害（不消耗）
	if is_player and GameState != null and int(GameState.contraband.get(&"navy_gear", 0)) > 0:
		for k2 in ["hull", "sail", "rudder", "crew"]:
			if res.has(k2):
				res[k2] = float(res[k2]) * 1.10
	# 链弹打的是帆索，海怪没有帆 → 完全无效
	var is_monster: bool = enemy.has_method("alive_limbs")
	if not (is_monster and ammo_id == &"chain"):
		enemy.last_attacker = self
		enemy.take_damage(res)
	reload_timer = CombatResolver.reload_time(cannon_reload, crew_pct(), crew_reload_bonus)

func take_damage(res: Dictionary) -> void:
	if not alive:
		return
	# 被动还击：被打且当前没有目标时，锁定攻击者
	if not is_player and target == null and last_attacker != null and is_instance_valid(last_attacker):
		target = last_attacker
		engaged = true
	damage_taken += float(res.get("hull", 0.0))
	hull_hp = maxf(0.0, hull_hp - float(res.get("hull", 0.0)))
	sail_hp = maxf(0.0, sail_hp - float(res.get("sail", 0.0)))
	rudder_hp = maxf(0.0, rudder_hp - float(res.get("rudder", 0.0)))
	crew_hp = maxf(0.0, crew_hp - float(res.get("crew", 0.0)))
	stats_changed.emit(self)
	if is_boss:
		_update_boss_phase()
	queue_redraw()
	_check_death()

## Boss 三阶段：66% / 33% 各强化一档
func _update_boss_phase() -> void:
	var pct := hull_pct()
	if boss_phase == 1 and pct <= 0.66:
		boss_phase = 2
		cannon_damage = base_damage_ref * 1.3
		cannon_reload = base_reload_ref * 0.9
	elif boss_phase == 2 and pct <= 0.33:
		boss_phase = 3
		cannon_damage = base_damage_ref * 1.6
		cannon_reload = base_reload_ref * 0.8

func take_crew_damage(amount: float) -> void:
	if not alive:
		return
	crew_hp = maxf(0.0, crew_hp - amount)
	stats_changed.emit(self)
	queue_redraw()
	_check_death()

func _check_death() -> void:
	if not alive:
		return
	if hull_hp <= 0.0:
		alive = false
		died.emit(self, {"sunk": true, "captured": false})
	elif crew_hp <= 0.0:
		alive = false
		died.emit(self, {"sunk": false, "captured": true})

# ---------------- 绘制 ----------------

func _draw() -> void:
	var hull_col := Color(0.55, 0.42, 0.26)
	if faction == "player":
		hull_col = Color(0.24, 0.42, 0.62)
	elif faction == "pirate":
		hull_col = Color(0.62, 0.24, 0.24)
	elif faction == "navy":
		hull_col = Color(0.30, 0.36, 0.68)
	elif faction == "merchant":
		hull_col = Color(0.30, 0.55, 0.35)
	var pts := PackedVector2Array([
		Vector2(26, 0), Vector2(10, 11), Vector2(-20, 9),
		Vector2(-26, 0), Vector2(-20, -9), Vector2(10, -11),
	])
	draw_colored_polygon(pts, hull_col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.05, 0.08, 0.1), 1.5)
	# 桅杆与帆：帆毁了就画成破布
	var mast_x := 0.0
	draw_line(Vector2(mast_x, -8), Vector2(mast_x, 8), Color(0.9, 0.88, 0.8), 1.5)
	if sail_pct() > 0.01:
		var h := 16.0 * (0.35 + 0.65 * sail_pct())
		draw_rect(Rect2(Vector2(mast_x - 3, -h * 0.5), Vector2(6, h)), Color(0.91, 0.86, 0.77))
	else:
		draw_line(Vector2(mast_x - 3, -6), Vector2(mast_x + 2, 4), Color(0.5, 0.45, 0.4), 2.0)
	# 血条
	if hull_pct() < 1.0:
		var w := 44.0
		var y := -34.0
		draw_rect(Rect2(-w * 0.5, y, w, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w * 0.5, y, w * hull_pct(), 4), Color(0.75, 0.25, 0.25))
	if is_player:
		draw_circle(Vector2.ZERO, 3.0, Color(0.9, 0.8, 0.3))
		# 锁定目标时显示自己的火炮射程圈
		if target != null and is_instance_valid(target):
			draw_arc(Vector2.ZERO, cannon_range, 0, TAU, 64, Color(0.55, 0.85, 1.0, 0.35), 3.0)
	# 阵营标签（美术资源到位后改为头顶信息栏，见 02-systems-design §16.3）
	if not is_player:
		var tag := ""
		var tag_col := Color(0.8, 0.8, 0.8)
		match faction:
			"pirate":
				tag = "海盗"
				tag_col = Color(0.95, 0.55, 0.5)
			"navy":
				tag = "海军"
				tag_col = Color(0.65, 0.75, 1.0)
			"merchant":
				tag = "商船"
				tag_col = Color(0.6, 0.95, 0.7)
		if tag != "":
			# 阵营 id 与单位 faction 名称不同，需要映射
			var aligned := ""
			if GameState != null:
				var a: String = GameState.aligned_faction()
				if (a == "royal_navy" and faction == "navy") 					or (a == "merchant" and faction == "merchant") 					or (a == "black_sail" and faction == "pirate"):
					aligned = a
			if aligned != "":
				tag = "同势力"
				tag_col = Color(0.55, 1.0, 0.6)
			# 抵消船体旋转，让标签始终水平
			draw_set_transform(Vector2(-26, -44), -rotation, Vector2.ONE)
			draw_string(ThemeDB.fallback_font, Vector2.ZERO, tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tag_col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
