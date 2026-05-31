extends Node2D

enum GameState { MENU, FIGHT, ROUND_END, OVER, PAUSED }

const FighterScene := preload("res://scenes/Fighter.tscn")
const FLOOR_Y := 545.0
const ROUND_SECONDS := 60.0

var state := GameState.MENU
var player_name := "Player One"
var winner_text := ""
var shake_time := 0.0
var shake_strength := 0.0
var round_number := 1
var player_rounds := 0
var cpu_rounds := 0
var round_time := ROUND_SECONDS

var player: Node2D
var cpu: Node2D
var camera: Camera2D
var menu_layer: CanvasLayer
var fight_layer: CanvasLayer
var over_layer: CanvasLayer
var name_input: LineEdit
var health_player: ProgressBar
var health_cpu: ProgressBar
var meter_player: ProgressBar
var status_label: Label
var prompt_label: Label
var timer_label: Label
var round_label: Label
var combo_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input()
	_build_arena()
	_build_fighters()
	_build_menu()
	_build_fight_hud()
	_build_over_screen()
	_show_menu()


func _process(delta: float) -> void:
	if state == GameState.FIGHT:
		round_time = maxf(round_time - delta, 0.0)
		health_player.value = player.health
		health_cpu.value = cpu.health
		meter_player.value = player.meter
		timer_label.text = "%02d" % int(ceil(round_time))
		round_label.text = "ROUND %d    %d - %d" % [round_number, player_rounds, cpu_rounds]
		combo_label.text = "%d HIT COMBO" % player.combo_count if player.combo_count >= 2 else ""
		status_label.text = "Cross: jab   Triangle: power punch   Square: guard   Circle: backstep"
		if round_time <= 0.0:
			_finish_round(player if player.health >= cpu.health else cpu)
		if Input.is_action_just_pressed("pause"):
			_set_paused(true)
	elif state == GameState.PAUSED and Input.is_action_just_pressed("pause"):
		_set_paused(false)

	if shake_time > 0.0:
		shake_time -= delta
		camera.offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
	else:
		camera.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if state == GameState.MENU:
		if event.is_action_pressed("confirm"):
			_start_fight()
		elif event.is_action_pressed("special"):
			name_input.text = _random_name()
	elif state == GameState.OVER and event.is_action_pressed("confirm"):
		_show_menu()


func _register_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_action("attack", [KEY_J, KEY_SPACE], [JOY_BUTTON_A], [])
	_add_action("block", [KEY_K], [JOY_BUTTON_X, JOY_BUTTON_LEFT_SHOULDER], [])
	_add_action("dodge", [KEY_L, KEY_SHIFT], [JOY_BUTTON_B], [])
	_add_action("special", [KEY_I], [JOY_BUTTON_Y, JOY_BUTTON_RIGHT_SHOULDER], [])
	_add_action("confirm", [KEY_ENTER], [JOY_BUTTON_A, JOY_BUTTON_START], [])
	_add_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])


func _add_action(action_name: String, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, 0.2)
	for keycode in keys:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action_name, key_event)
	for button in buttons:
		var joy_event := InputEventJoypadButton.new()
		joy_event.button_index = button
		InputMap.action_add_event(action_name, joy_event)
	for axis_data in axes:
		var axis_event := InputEventJoypadMotion.new()
		axis_event.axis = axis_data[0]
		axis_event.axis_value = axis_data[1]
		InputMap.action_add_event(action_name, axis_event)


func _build_arena() -> void:
	camera = Camera2D.new()
	camera.position = Vector2(640, 360)
	add_child(camera)
	camera.make_current()

	var sky := ColorRect.new()
	sky.color = Color(0.13, 0.12, 0.105)
	sky.size = Vector2(1280, 720)
	add_child(sky)

	var back_wall := ColorRect.new()
	back_wall.color = Color(0.23, 0.215, 0.185)
	back_wall.position = Vector2(0, 0)
	back_wall.size = Vector2(1280, 545)
	add_child(back_wall)

	for x in range(0, 1280, 160):
		var panel_line := ColorRect.new()
		panel_line.color = Color(0.11, 0.105, 0.095, 0.52)
		panel_line.position = Vector2(x, 0)
		panel_line.size = Vector2(3, 545)
		add_child(panel_line)

	for y in [132, 263, 394]:
		var wall_line := ColorRect.new()
		wall_line.color = Color(0.11, 0.105, 0.095, 0.45)
		wall_line.position = Vector2(0, y)
		wall_line.size = Vector2(1280, 3)
		add_child(wall_line)

	for side in [-1, 1]:
		var banner := Polygon2D.new()
		banner.polygon = PackedVector2Array([Vector2(-78, -86), Vector2(78, -86), Vector2(58, 92), Vector2(0, 128), Vector2(-58, 92)])
		banner.color = Color(0.1, 0.095, 0.085) if side < 0 else Color(0.42, 0.08, 0.06)
		banner.position = Vector2(240 if side < 0 else 1040, 205)
		add_child(banner)

		var light := Polygon2D.new()
		light.polygon = PackedVector2Array([Vector2(-28, 0), Vector2(28, 0), Vector2(190 * side, 440), Vector2(-190 * side, 440)])
		light.color = Color(1.0, 0.78, 0.43, 0.16)
		light.position = Vector2(640 + side * 245, 18)
		add_child(light)

	var screen := ColorRect.new()
	screen.color = Color(0.055, 0.05, 0.043)
	screen.position = Vector2(365, 116)
	screen.size = Vector2(550, 92)
	add_child(screen)

	var screen_text := _label("BACKROOM BRAWL", 38, Vector2(365, 124), Vector2(550, 64), HORIZONTAL_ALIGNMENT_CENTER)
	screen_text.add_theme_color_override("font_color", Color(0.94, 0.77, 0.45))
	add_child(screen_text)

	var floor := ColorRect.new()
	floor.color = Color(0.155, 0.145, 0.13)
	floor.position = Vector2(0, 545)
	floor.size = Vector2(1280, 175)
	add_child(floor)

	var stage_lip := ColorRect.new()
	stage_lip.color = Color(0.055, 0.05, 0.044)
	stage_lip.position = Vector2(0, 538)
	stage_lip.size = Vector2(1280, 7)
	add_child(stage_lip)

	for x in range(-80, 1280, 120):
		var floor_line := Line2D.new()
		floor_line.width = 2
		floor_line.default_color = Color(0.07, 0.065, 0.058, 0.48)
		floor_line.points = PackedVector2Array([Vector2(x, 545), Vector2(x + 105, 720)])
		add_child(floor_line)

	for y in range(580, 720, 44):
		var chalk := Line2D.new()
		chalk.width = 3
		chalk.default_color = Color(0.68, 0.63, 0.52, 0.18)
		chalk.points = PackedVector2Array([Vector2(125, y), Vector2(1155, y - 18)])
		add_child(chalk)


func _build_fighters() -> void:
	player = FighterScene.instantiate()
	cpu = FighterScene.instantiate()
	add_child(player)
	add_child(cpu)
	player.configure(player_name, false, Color(0.15, 0.8, 1.0))
	cpu.configure("CPU Bruiser", true, Color(1.0, 0.23, 0.35))
	player.opponent = cpu
	cpu.opponent = player
	player.landed_hit.connect(_on_hit)
	cpu.landed_hit.connect(_on_hit)
	player.defeated.connect(func() -> void: _finish_round(cpu))
	cpu.defeated.connect(func() -> void: _finish_round(player))


func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	var panel := _panel(Vector2(390, 155), Vector2(500, 350))
	menu_layer.add_child(panel)

	var title := _label("FIGHTY FIGHTY", 48, Vector2(0, 24), Vector2(500, 60), HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_color", Color(0.94, 0.77, 0.45))
	panel.add_child(title)

	var sub := _label("Enter your fighter name", 22, Vector2(0, 100), Vector2(500, 34), HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(sub)

	name_input = LineEdit.new()
	name_input.position = Vector2(80, 150)
	name_input.size = Vector2(340, 44)
	name_input.placeholder_text = "Player One"
	name_input.max_length = 18
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.add_theme_font_size_override("font_size", 24)
	name_input.text_submitted.connect(func(_text: String) -> void: _start_fight())
	panel.add_child(name_input)

	prompt_label = _label("Cross / Enter: fight    Triangle: random name", 18, Vector2(0, 225), Vector2(500, 44), HORIZONTAL_ALIGNMENT_CENTER)
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	panel.add_child(prompt_label)

	var controls := _label("PS4: Left stick or D-pad move, Cross jab, Square guard, Circle backstep, Triangle power punch", 16, Vector2(46, 286), Vector2(410, 44), HORIZONTAL_ALIGNMENT_CENTER)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(controls)


func _build_fight_hud() -> void:
	fight_layer = CanvasLayer.new()
	add_child(fight_layer)

	var player_label := _label(player_name, 24, Vector2(48, 26), Vector2(310, 28), HORIZONTAL_ALIGNMENT_LEFT)
	player_label.name = "PlayerName"
	fight_layer.add_child(player_label)
	var cpu_label := _label("CPU BRUISER", 24, Vector2(920, 26), Vector2(310, 28), HORIZONTAL_ALIGNMENT_RIGHT)
	fight_layer.add_child(cpu_label)

	health_player = _bar(Vector2(48, 65), Vector2(430, 30), Color(0.86, 0.58, 0.22))
	fight_layer.add_child(health_player)
	health_cpu = _bar(Vector2(802, 65), Vector2(430, 30), Color(0.68, 0.12, 0.1))
	fight_layer.add_child(health_cpu)
	meter_player = _bar(Vector2(48, 104), Vector2(260, 18), Color(0.94, 0.77, 0.45))
	meter_player.max_value = 100
	fight_layer.add_child(meter_player)

	timer_label = _label("60", 42, Vector2(588, 48), Vector2(104, 52), HORIZONTAL_ALIGNMENT_CENTER)
	timer_label.add_theme_color_override("font_color", Color(0.94, 0.77, 0.45))
	fight_layer.add_child(timer_label)

	round_label = _label("ROUND 1    0 - 0", 20, Vector2(490, 102), Vector2(300, 28), HORIZONTAL_ALIGNMENT_CENTER)
	fight_layer.add_child(round_label)

	combo_label = _label("", 34, Vector2(70, 170), Vector2(280, 50), HORIZONTAL_ALIGNMENT_LEFT)
	combo_label.add_theme_color_override("font_color", Color(0.94, 0.77, 0.45))
	fight_layer.add_child(combo_label)

	status_label = _label("", 18, Vector2(370, 645), Vector2(540, 32), HORIZONTAL_ALIGNMENT_CENTER)
	status_label.add_theme_color_override("font_color", Color(0.88, 0.91, 0.96))
	fight_layer.add_child(status_label)


func _build_over_screen() -> void:
	over_layer = CanvasLayer.new()
	add_child(over_layer)
	var panel := _panel(Vector2(410, 210), Vector2(460, 250))
	over_layer.add_child(panel)
	var result := _label("", 38, Vector2(0, 54), Vector2(460, 58), HORIZONTAL_ALIGNMENT_CENTER)
	result.name = "Result"
	panel.add_child(result)
	var restart := _label("Cross / Enter: run it back", 22, Vector2(0, 150), Vector2(460, 38), HORIZONTAL_ALIGNMENT_CENTER)
	restart.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	panel.add_child(restart)


func _show_menu() -> void:
	state = GameState.MENU
	get_tree().paused = false
	menu_layer.visible = true
	fight_layer.visible = false
	over_layer.visible = false
	player.enabled = false
	cpu.enabled = false
	player.visible = false
	cpu.visible = false
	name_input.grab_focus()


func _start_fight() -> void:
	player_name = name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player One"
	player.configure(player_name, false, Color(0.15, 0.8, 1.0))
	fight_layer.get_node("PlayerName").text = player_name.to_upper()
	player_rounds = 0
	cpu_rounds = 0
	round_number = 1
	_start_round()
	state = GameState.FIGHT
	menu_layer.visible = false
	fight_layer.visible = true
	over_layer.visible = false


func _start_round() -> void:
	round_time = ROUND_SECONDS
	combo_label.text = ""
	status_label.text = ""
	player.reset_fight(Vector2(350, FLOOR_Y), 1)
	cpu.reset_fight(Vector2(930, FLOOR_Y), -1)
	player.visible = true
	cpu.visible = true
	health_player.max_value = player.max_health
	health_cpu.max_value = cpu.max_health
	health_player.value = player.max_health
	health_cpu.value = cpu.max_health
	timer_label.text = "%02d" % int(ROUND_SECONDS)
	round_label.text = "ROUND %d    %d - %d" % [round_number, player_rounds, cpu_rounds]


func _finish_round(winner: Node2D) -> void:
	if state == GameState.ROUND_END or state == GameState.OVER:
		return
	state = GameState.ROUND_END
	player.enabled = false
	cpu.enabled = false
	if winner == player:
		player_rounds += 1
		status_label.text = "%s takes the round" % player.fighter_name
	else:
		cpu_rounds += 1
		status_label.text = "CPU Bruiser takes the round"

	if player_rounds >= 2:
		_finish_fight(player.fighter_name + " wins")
	elif cpu_rounds >= 2:
		_finish_fight(cpu.fighter_name + " wins")
	else:
		round_number += 1
		await get_tree().create_timer(1.6).timeout
		if state == GameState.ROUND_END:
			state = GameState.FIGHT
			_start_round()


func _finish_fight(text: String) -> void:
	if state == GameState.OVER:
		return
	winner_text = text
	state = GameState.OVER
	player.enabled = false
	cpu.enabled = false
	player.visible = true
	cpu.visible = true
	fight_layer.visible = false
	over_layer.visible = true
	over_layer.get_node("Panel/Result").text = winner_text.to_upper()


func _set_paused(paused: bool) -> void:
	state = GameState.PAUSED if paused else GameState.FIGHT
	get_tree().paused = paused
	status_label.text = "Paused" if paused else ""


func _on_hit(_damage: int, world_position: Vector2, heavy: bool) -> void:
	shake_time = 0.2 if heavy else 0.1
	shake_strength = 18.0 if heavy else 7.0

	var burst := Polygon2D.new()
	burst.position = world_position
	burst.color = Color(1.0, 0.85, 0.18, 0.88) if heavy else Color(0.68, 0.95, 1.0, 0.8)
	burst.polygon = PackedVector2Array([
		Vector2(0, -44), Vector2(14, -12), Vector2(56, -18), Vector2(22, 8),
		Vector2(36, 44), Vector2(0, 24), Vector2(-36, 44), Vector2(-22, 8),
		Vector2(-56, -18), Vector2(-14, -12)
	])
	add_child(burst)
	var burst_tween := create_tween()
	burst_tween.tween_property(burst, "scale", Vector2(1.45, 1.45), 0.12)
	burst_tween.parallel().tween_property(burst, "modulate:a", 0.0, 0.16)
	burst_tween.tween_callback(burst.queue_free)

	var spark := Label.new()
	spark.text = "CRUSH!" if heavy else "JAB!"
	spark.position = world_position - Vector2(48, 70)
	spark.add_theme_font_size_override("font_size", 42 if heavy else 28)
	spark.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2) if heavy else Color.WHITE)
	add_child(spark)
	var tween := create_tween()
	tween.tween_property(spark, "position:y", spark.position.y - 45, 0.28)
	tween.parallel().tween_property(spark, "modulate:a", 0.0, 0.28)
	tween.tween_callback(spark.queue_free)


func _panel(pos: Vector2, size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = "Panel"
	panel.position = pos
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.082, 0.068, 0.95)
	style.border_color = Color(0.94, 0.77, 0.45, 0.82)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(text: String, size: int, pos: Vector2, node_size: Vector2, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = node_size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	return label


func _bar(pos: Vector2, node_size: Vector2, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = node_size
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.055, 0.05, 0.044, 0.95)
	bg.set_border_width_all(1)
	bg.border_color = Color(1, 1, 1, 0.22)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _random_name() -> String:
	var names := ["Neon Viper", "Knuckle Nova", "Cyber Champ", "Turbo Ace", "Pixel Fury", "Flash Baron"]
	return names.pick_random()
