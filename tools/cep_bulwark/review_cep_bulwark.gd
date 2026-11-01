extends Node3D
## Open scenes/art_review/cep_bulwark.tscn and press F6.
## Orbit, compare silhouettes, inspect LODs, walk and brace without balance changes.

const Cep := preload("res://scripts/cep_bulwark.gd")
const Demo := preload("res://scripts/cep_action_demo.gd")
var demo: Node3D
var firing := false
var fire_timer := 0.0
var status_timer := 0.0
const Wartling := preload("res://scripts/wartling.gd")
var unit: MeshInstance3D
var comparison: MeshInstance3D
var camera: Camera3D
var label: Label
var lod := 0
var paused := false
var yaw := 0.88
var pitch := 0.24
var zoom := 3.15
var dragging := false


func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.20, 0.19, 0.17)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.87, 0.90, 1.0)
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -35, 0)
	key.light_color = Color(1.0, 0.97, 0.91)
	key.light_energy = 0.65
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_color = Color(0.70, 0.80, 1.0)
	fill.light_energy = 0.18
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.35, 0.32, 0.27)
	floor_material.roughness = 0.95
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	demo = Demo.new()
	add_child(demo)
	demo.set_process(false)
	unit = demo.unit
	comparison = MeshInstance3D.new()
	comparison.name = "WartlingComparison"
	comparison.mesh = Wartling.mesh(0)
	comparison.position.x = 2.35
	comparison.visible = false
	add_child(comparison)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	camera.make_current()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.065, 0.05, 0.87)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.82))
	var content := VBoxContainer.new()
	panel.add_child(content)
	content.add_child(label)
	var commands := HBoxContainer.new()
	content.add_child(commands)
	for spec in [["Attack [A]",_attack],["Brace / Uproot [B]",_brace],["Move [M]",_move],["Incoming shots [V]",_fire]]:
		var button := Button.new()
		button.text = spec[0]
		button.tooltip_text = "Prototype command; animation follows the unit state."
		button.pressed.connect(spec[1])
		commands.add_child(button)
	_update_label()
	_update_camera()
	if "--cep-smoke" in OS.get_cmdline_user_args():
		_smoke.call_deferred()


func _attack() -> void:
	if demo.actions.attack():
		demo.target.visible = true

func _brace() -> void:
	demo.actions.toggle_brace()
	demo.target.visible = false
	zoom = 5.8
	pitch = 0.50
	_update_camera()

func _move() -> void:
	demo.actions.move()

func _fire() -> void:
	firing = not firing
	fire_timer = 0.0

func _process(delta: float) -> void:
	if not paused:
		demo.advance(delta)
		if firing:
			fire_timer -= delta
			if fire_timer <= 0.0:
				demo.fire(sin(demo.actions.clock*3.0)*1.9)
				fire_timer = 0.65
	comparison.set_instance_shader_parameter("motion_time", demo.actions.clock)
	comparison.set_instance_shader_parameter("walk", demo.actions.walking)
	status_timer -= delta
	if status_timer <= 0.0:
		status_timer = 0.1
		_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_move() if demo.actions.state != demo.actions.State.WALK else demo.actions.stop()
			KEY_A:
				_attack()
			KEY_B:
				_brace()
			KEY_M:
				_move()
			KEY_V:
				_fire()
			KEY_L:
				lod = (lod + 1) % 3
				unit.mesh = Cep.mesh(lod)
			KEY_C:
				comparison.visible = not comparison.visible
				_update_camera()
			KEY_P:
				paused = not paused
			KEY_R:
				pitch = 0.75 if pitch < 0.5 else 0.24
				_update_camera()
		_update_label()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(1.6, zoom * 0.90)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(6.5, zoom * 1.10)
			_update_camera()
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.006, 0.05, 1.35)
		_update_camera()


func _update_camera() -> void:
	var target := Vector3(0.80 if comparison.visible else 0.0, 0.68, 0)
	camera.size = zoom
	camera.position = target + Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * 7.0
	camera.look_at(target)


func _update_label() -> void:
	var stats := Cep.stats(lod)
	var names := ["IDLE","WALK","CAP BASH","ROOTING","BRACED: CAPTURE ACTIVE","UPROOTING"]
	label.text = "CEP BULWARK / action prototype%s\n%s | %s | %s triangles\nCapture radius: 3 units | 100 incoming damage -> 25 to Cep\nCaptured: %d | Cep damage: %.0f | Escaped shots damage: %.0f\nA: attack   B: brace/uproot   M: move   V: incoming shots\nL: detail   C: compare   R: RTS angle   P: pause | Drag / wheel: camera" % [
		" [PAUSED]" if paused else "",names[demo.actions.state],str(stats["lod"]).to_upper(),str(stats["triangles"]),
		demo.captured_count,demo.received_damage,demo.ally_damage]



func _smoke() -> void:
	set_process(false)
	_attack()
	for i in 24:
		demo.advance(1.0/20.0)
		await get_tree().process_frame
	_brace()
	for i in 22:
		demo.advance(1.0/20.0)
		await get_tree().process_frame
	assert(demo.actions.capture_active())
	demo.fire(1.0)
	for i in 30:
		demo.advance(1.0/20.0)
		await get_tree().process_frame
	assert(demo.received_damage == 25.0)
	_update_label()
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("res://art/cep_bulwark/cep_bulwark_action_review.png") == OK)
	print("CEP ACTION REVIEW CHECK PASSED: 100 -> 25")
	get_tree().quit()
