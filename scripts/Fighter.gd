class_name Fighter
extends Node2D

signal landed_hit(damage: int, world_position: Vector2, heavy: bool)
signal defeated

const FLOOR_Y := 545.0
const WALK_SPEED := 390.0
const DODGE_SPEED := 720.0
const GRAVITY := 1800.0
const ATTACK_RANGE := 132.0
const SPECIAL_RANGE := 188.0

var fighter_name := "Fighter"
var is_cpu := false
var max_health := 100
var health := 100
var meter := 0.0
var facing := 1
var velocity := Vector2.ZERO
var opponent: Fighter
var arena_bounds := Vector2(90.0, 1190.0)
var enabled := false
var combo_count := 0
var combo_timer := 0.0
var current_move_axis := 0.0

var _rng := RandomNumberGenerator.new()
var _anim_time := 0.0
var _attack_cooldown := 0.0
var _block_timer := 0.0
var _dodge_timer := 0.0
var _stun_timer := 0.0
var _flash_timer := 0.0
var _cpu_think_timer := 0.0
var _cpu_action := "idle"

@onready var character_sprite: Sprite2D = $CharacterSprite
@onready var body: Polygon2D = $Body
@onready var head: Polygon2D = $Head
@onready var front_arm: Polygon2D = $FrontArm
@onready var front_fist: Polygon2D = $FrontFist
@onready var guard_fist: Polygon2D = $GuardFist
@onready var back_arm: Polygon2D = $BackArm
@onready var front_leg: Polygon2D = $FrontLeg
@onready var back_leg: Polygon2D = $BackLeg
@onready var front_foot: Polygon2D = $FrontFoot
@onready var back_foot: Polygon2D = $BackFoot
@onready var chest_glow: Line2D = $ChestGlow
@onready var belt: Polygon2D = $Belt
@onready var name_label: Label = $NameLabel
@onready var shadow: Polygon2D = $Shadow

func _ready() -> void:
	_rng.randomize()
	name_label.text = fighter_name
	character_sprite.centered = true
	character_sprite.visible = false


func configure(new_name: String, cpu: bool, accent: Color) -> void:
	fighter_name = new_name
	is_cpu = cpu
	if is_inside_tree():
		name_label.text = fighter_name
		body.color = accent
		head.color = accent.lightened(0.18)
		front_arm.color = accent.lightened(0.18)
		back_arm.color = accent.darkened(0.24)
		chest_glow.default_color = accent.lightened(0.65)


func reset_fight(start_position: Vector2, new_facing: int) -> void:
	position = start_position
	facing = new_facing
	scale.x = float(facing)
	health = max_health
	meter = 0.0
	combo_count = 0
	combo_timer = 0.0
	current_move_axis = 0.0
	_anim_time = _rng.randf_range(0.0, TAU)
	velocity = Vector2.ZERO
	_attack_cooldown = 0.0
	_block_timer = 0.0
	_dodge_timer = 0.0
	_stun_timer = 0.0
	_flash_timer = 0.0
	_cpu_action = "idle"
	enabled = true
	_update_pose()


func _physics_process(delta: float) -> void:
	if not enabled:
		return

	_anim_time += delta
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_block_timer = maxf(_block_timer - delta, 0.0)
	_dodge_timer = maxf(_dodge_timer - delta, 0.0)
	_stun_timer = maxf(_stun_timer - delta, 0.0)
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	combo_timer = maxf(combo_timer - delta, 0.0)
	if combo_timer <= 0.0:
		combo_count = 0

	if opponent:
		var target_direction := opponent.global_position.x - global_position.x
		facing = 1 if target_direction >= 0.0 else -1
		scale.x = float(facing)
		name_label.scale.x = float(facing)

	var move_axis := 0.0
	if _stun_timer <= 0.0:
		move_axis = _cpu_axis(delta) if is_cpu else _player_axis()
	current_move_axis = move_axis

	velocity.x = move_axis * WALK_SPEED
	if _dodge_timer > 0.0:
		velocity.x = -facing * DODGE_SPEED
	velocity.y += GRAVITY * delta
	position += velocity * delta
	position.x = clampf(position.x, arena_bounds.x, arena_bounds.y)
	if position.y >= FLOOR_Y:
		position.y = FLOOR_Y
		velocity.y = 0.0

	if not is_cpu and _stun_timer <= 0.0:
		if Input.is_action_just_pressed("attack"):
			attack(false)
		elif Input.is_action_just_pressed("special"):
			attack(true)
		elif Input.is_action_pressed("block"):
			block()
		elif Input.is_action_just_pressed("dodge"):
			dodge()

	if is_cpu and _stun_timer <= 0.0:
		_cpu_combat(delta)

	meter = clampf(meter + delta * 3.5, 0.0, 100.0)
	_update_pose()


func attack(heavy: bool) -> void:
	if _attack_cooldown > 0.0 or _dodge_timer > 0.0:
		return
	if heavy and meter < 40.0:
		return

	_attack_cooldown = 0.78 if heavy else 0.38
	if heavy:
		meter -= 40.0

	var reach := SPECIAL_RANGE if heavy else ATTACK_RANGE
	var damage := 26 if heavy else 9
	var target_delta := opponent.global_position.x - global_position.x if opponent else 9999.0
	if opponent and absf(target_delta) <= reach and (1 if target_delta >= 0.0 else -1) == facing:
		opponent.take_hit(damage, heavy, global_position + Vector2(facing * reach, -75.0))
		combo_count += 1
		combo_timer = 1.25
		landed_hit.emit(damage, global_position + Vector2(facing * reach, -75.0), heavy)


func block() -> void:
	_block_timer = 0.16
	meter = clampf(meter + 0.75, 0.0, 100.0)


func dodge() -> void:
	if _dodge_timer <= 0.0:
		_dodge_timer = 0.22
		_attack_cooldown = maxf(_attack_cooldown, 0.18)


func take_hit(damage: int, heavy: bool, hit_position: Vector2) -> void:
	var final_damage := damage
	if _block_timer > 0.0:
		final_damage = maxi(2, int(round(float(damage) * 0.34)))
		meter = clampf(meter + 8.0, 0.0, 100.0)
	else:
		_stun_timer = 0.35 if heavy else 0.2
		velocity.x = -facing * (380.0 if heavy else 220.0)

	health = maxi(health - final_damage, 0)
	_flash_timer = 0.12
	if health <= 0:
		enabled = false
		defeated.emit()


func _player_axis() -> float:
	var axis := Input.get_axis("move_left", "move_right")
	if absf(axis) < 0.2:
		axis = 0.0
	return axis


func _cpu_axis(delta: float) -> float:
	_cpu_think_timer -= delta
	if _cpu_think_timer <= 0.0:
		_cpu_think_timer = _rng.randf_range(0.22, 0.55)
		var distance := absf(opponent.global_position.x - global_position.x)
		if health < 32 and _rng.randf() < 0.35:
			_cpu_action = "retreat"
		elif distance > 135.0:
			_cpu_action = "approach"
		elif _rng.randf() < 0.24:
			_cpu_action = "block"
		elif _rng.randf() < 0.18:
			_cpu_action = "retreat"
		else:
			_cpu_action = "attack"

	match _cpu_action:
		"approach":
			return float(facing)
		"retreat":
			return float(-facing)
		_:
			return 0.0


func _cpu_combat(_delta: float) -> void:
	var distance := absf(opponent.global_position.x - global_position.x)
	if _cpu_action == "block":
		block()
	elif _cpu_action == "attack" and distance < 150.0:
		if meter >= 40.0 and _rng.randf() < 0.2:
			attack(true)
		else:
			attack(false)


func _update_pose() -> void:
	var blocking := _block_timer > 0.0
	var dodging := _dodge_timer > 0.0
	var heavy_windup := _attack_cooldown > 0.5
	var punching := _attack_cooldown > 0.18
	var jab_extend := _attack_cooldown > 0.22 and _attack_cooldown <= 0.5
	var walking := absf(current_move_axis) > 0.08 and not blocking and not dodging and not punching and _stun_timer <= 0.0
	var idle := not walking and not blocking and not dodging and not punching and _stun_timer <= 0.0
	var idle_phase := sin(_anim_time * 4.2)
	var idle_phase_fast := sin(_anim_time * 8.4)
	var walk_phase := sin(_anim_time * 13.0)
	var walk_step := absf(walk_phase)

	var body_color := Color(0.18, 0.32, 0.28)
	var arm_color := Color(0.24, 0.42, 0.35)
	var dark_color := Color(0.09, 0.12, 0.16)
	var glove_color := Color(0.95, 0.92, 0.78)
	var trim_color := Color(0.96, 0.75, 0.22)
	if is_cpu:
		body_color = Color(0.5, 0.12, 0.08)
		arm_color = Color(0.66, 0.18, 0.12)
		dark_color = Color(0.13, 0.1, 0.09)
		glove_color = Color(0.12, 0.12, 0.12)
		trim_color = Color(0.92, 0.86, 0.72)

	if _flash_timer > 0.0:
		body.color = Color.WHITE
		head.color = Color.WHITE
		front_arm.color = Color.WHITE
		front_fist.color = Color.WHITE
	else:
		body.color = body_color
		head.color = Color(0.82, 0.58, 0.38) if not is_cpu else Color(0.62, 0.38, 0.25)
		front_arm.color = arm_color
		back_arm.color = dark_color.lightened(0.18)
		front_fist.color = glove_color
		guard_fist.color = glove_color.darkened(0.08)

	front_leg.color = dark_color.lightened(0.16)
	back_leg.color = dark_color.darkened(0.04)
	front_foot.color = Color(0.018, 0.018, 0.018)
	back_foot.color = Color(0.01, 0.01, 0.012)
	belt.color = trim_color
	chest_glow.default_color = Color(0.05, 0.045, 0.035, 0.72)

	body.position = Vector2(0, -105)
	head.position = Vector2(7, -198)
	character_sprite.position = Vector2(0, -196)
	character_sprite.scale = Vector2(0.38, 0.38)
	character_sprite.rotation = 0.0
	character_sprite.modulate = Color.WHITE
	front_arm.position = Vector2(28, -142)
	front_arm.rotation = 0.0
	front_fist.position = Vector2(74, -104)
	front_fist.rotation = 0.0
	guard_fist.position = Vector2(38, -166)
	guard_fist.rotation = 0.0
	back_arm.position = Vector2(-28, -138)
	front_leg.position = Vector2(24, -50)
	front_leg.rotation = 0.0
	back_leg.position = Vector2(-20, -50)
	back_leg.rotation = 0.0
	front_foot.position = Vector2(28, 12)
	front_foot.rotation = 0.0
	back_foot.position = Vector2(-18, 10)
	back_foot.rotation = 0.0

	if idle:
		body.position.y += idle_phase * 2.0
		head.position.y += idle_phase * 3.0
		front_arm.position.y += idle_phase * 3.0
		front_fist.position.y += idle_phase * 3.5
		guard_fist.position.y -= idle_phase * 2.0
		front_leg.rotation = idle_phase * 0.025
		back_leg.rotation = -idle_phase * 0.02
		front_foot.position.x += idle_phase_fast * 1.2
		back_foot.position.x -= idle_phase_fast * 0.9
	elif walking:
		var travel_lean := clampf(current_move_axis * facing, -1.0, 1.0)
		body.position.x += travel_lean * 8.0
		body.position.y += walk_step * 3.0
		head.position.x += travel_lean * 6.0
		front_arm.position.x += walk_phase * 8.0
		back_arm.position.x -= walk_phase * 8.0
		front_fist.position.x += walk_phase * 10.0
		guard_fist.position.x -= walk_phase * 7.0
		front_leg.position.x += walk_phase * 18.0
		front_leg.position.y += walk_step * 8.0
		front_leg.rotation = walk_phase * 0.28
		back_leg.position.x -= walk_phase * 18.0
		back_leg.position.y += (1.0 - walk_step) * 8.0
		back_leg.rotation = -walk_phase * 0.28
		front_foot.position.x += walk_phase * 28.0
		front_foot.position.y -= maxf(walk_phase, 0.0) * 8.0
		front_foot.rotation = walk_phase * 0.18
		back_foot.position.x -= walk_phase * 28.0
		back_foot.position.y += minf(walk_phase, 0.0) * 8.0
		back_foot.rotation = -walk_phase * 0.18
		rotation = lerpf(rotation, travel_lean * 0.035, 0.3)
	elif blocking:
		front_arm.position = Vector2(18, -156)
		front_arm.rotation = -0.72
		front_fist.position = Vector2(24, -174)
		guard_fist.position = Vector2(50, -156)
		body.position.x = -6
		front_leg.position.x = 14
		front_leg.rotation = -0.12
		back_leg.position.x = -30
		back_leg.rotation = 0.08
	elif dodging:
		body.position.x = -18
		head.position.x = -8
		front_arm.position = Vector2(10, -132)
		front_fist.position = Vector2(38, -98)
		guard_fist.position = Vector2(-18, -142)
		front_leg.position.x = 4
		front_leg.rotation = -0.3
		back_leg.position.x = -42
		back_leg.rotation = 0.18
		front_foot.position.x = 5
		back_foot.position.x = -50
		rotation = -0.12 * facing
	elif heavy_windup:
		body.position.x = -12
		front_arm.position = Vector2(2, -148)
		front_arm.rotation = -1.25
		front_fist.position = Vector2(-20, -178)
		guard_fist.position = Vector2(50, -148)
		front_leg.position.x = 12
		front_leg.rotation = -0.16
		back_leg.position.x = -38
		back_leg.rotation = 0.12
		rotation = lerpf(rotation, -0.04 * facing, 0.25)
	elif jab_extend:
		body.position.x = 10
		head.position.x = 18
		front_arm.position = Vector2(36, -146)
		front_arm.rotation = -0.14
		front_fist.position = Vector2(128, -122)
		front_fist.rotation = 0.08
		guard_fist.position = Vector2(30, -164)
		front_leg.position.x = 38
		front_leg.rotation = 0.16
		back_leg.position.x = -28
		back_leg.rotation = -0.08
		rotation = lerpf(rotation, 0.05 * facing, 0.35)
	elif punching:
		body.position.x = 18
		head.position.x = 23
		front_arm.position = Vector2(48, -150)
		front_arm.rotation = -0.02
		front_fist.position = Vector2(168, -130)
		front_fist.rotation = 0.05
		guard_fist.position = Vector2(28, -166)
		front_leg.position.x = 44
		front_leg.rotation = 0.22
		back_leg.position.x = -22
		back_leg.rotation = -0.12
		rotation = lerpf(rotation, 0.08 * facing, 0.45)
	else:
		rotation = lerpf(rotation, 0.0, 0.25)

	var shadow_motion := walk_step if walking else absf(idle_phase) * 0.12
	shadow.scale.x = 1.0 + absf(velocity.x) / 1300.0 + shadow_motion * 0.12
	shadow.scale.y = 1.0 - minf(absf(velocity.x) / 2500.0, 0.18) - shadow_motion * 0.05
