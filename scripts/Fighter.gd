class_name Fighter
extends Node2D

signal landed_hit(damage: int, world_position: Vector2, heavy: bool)
signal defeated

const FLOOR_Y := 545.0
const WALK_SPEED := 390.0
const DODGE_SPEED := 720.0
const GRAVITY := 1800.0
const ATTACK_RANGE := 112.0
const SPECIAL_RANGE := 155.0

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

var _rng := RandomNumberGenerator.new()
var _attack_cooldown := 0.0
var _block_timer := 0.0
var _dodge_timer := 0.0
var _stun_timer := 0.0
var _flash_timer := 0.0
var _cpu_think_timer := 0.0
var _cpu_action := "idle"

@onready var body: Polygon2D = $Body
@onready var head: Polygon2D = $Head
@onready var arm: Line2D = $Arm
@onready var name_label: Label = $NameLabel
@onready var shadow: Polygon2D = $Shadow

func _ready() -> void:
	_rng.randomize()
	name_label.text = fighter_name


func configure(new_name: String, cpu: bool, accent: Color) -> void:
	fighter_name = new_name
	is_cpu = cpu
	if is_inside_tree():
		name_label.text = fighter_name
		body.color = accent
		head.color = accent.lightened(0.18)
		arm.default_color = accent.lightened(0.35)


func reset_fight(start_position: Vector2, new_facing: int) -> void:
	position = start_position
	facing = new_facing
	scale.x = float(facing)
	health = max_health
	meter = 0.0
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

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_block_timer = maxf(_block_timer - delta, 0.0)
	_dodge_timer = maxf(_dodge_timer - delta, 0.0)
	_stun_timer = maxf(_stun_timer - delta, 0.0)
	_flash_timer = maxf(_flash_timer - delta, 0.0)

	if opponent:
		var target_direction := opponent.global_position.x - global_position.x
		facing = 1 if target_direction >= 0.0 else -1
		scale.x = float(facing)
		name_label.scale.x = float(facing)

	var move_axis := 0.0
	if _stun_timer <= 0.0:
		move_axis = _cpu_axis(delta) if is_cpu else _player_axis()

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
	var damage := 22 if heavy else 10
	var target_delta := opponent.global_position.x - global_position.x if opponent else 9999.0
	if opponent and absf(target_delta) <= reach and (1 if target_delta >= 0.0 else -1) == facing:
		opponent.take_hit(damage, heavy, global_position + Vector2(facing * reach, -75.0))
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
	var attacking := _attack_cooldown > 0.24

	body.color.a = 0.96
	head.color.a = 0.96
	if _flash_timer > 0.0:
		body.color = Color.WHITE
		head.color = Color.WHITE
	elif is_cpu:
		body.color = Color(1.0, 0.23, 0.35)
		head.color = Color(1.0, 0.45, 0.5)
	else:
		body.color = Color(0.15, 0.8, 1.0)
		head.color = Color(0.47, 0.94, 1.0)

	var arm_start := Vector2(12, -74)
	var arm_end := Vector2(86 if attacking else 42, -82 if attacking else -48)
	if blocking:
		arm_end = Vector2(34, -110)
	elif dodging:
		arm_end = Vector2(-20, -50)
		rotation = -0.12 * facing
	else:
		rotation = lerpf(rotation, 0.0, 0.25)

	arm.points = PackedVector2Array([arm_start, arm_end])
	shadow.scale.x = 1.0 + absf(velocity.x) / 1300.0
