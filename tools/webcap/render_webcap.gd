extends SceneTree
## Violet Webcap: real engine renders of the Blender-built meshes (tools/blender/webcap_build.py).
## godot --path . --rendering-method gl_compatibility --script tools/wartling/render_webcap.gd
## -- --out=art/webcap --frames=16

const Webcap := preload("res://scripts/webcap.gd")
var output := "res://art/webcap"
var frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		if arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for lod in 3:
		print("ASSET " + JSON.stringify(Webcap.stats(lod)))
	var hero := _view(Webcap.mesh(0), Vector2i(1400, 1050))
	_caption(hero, "VIOLET WEBCAP", "Amanita Court / control", 38)
	await _settle()
	assert(hero.get_texture().get_image().save_png(output.path_join("webcap_hero.png")) == OK)
	hero.queue_free()
	await process_frame
	var sheet := Image.create(1500, 540, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.86, 0.85, 0.82))
	for lod in 3:
		var vp := _view(Webcap.mesh(lod), Vector2i(500, 540))
		var stats := Webcap.stats(lod)
		_caption(vp, str(stats["lod"]).to_upper(), "%d triangles (%d silk) / %d vertices / 2 surfaces" % [stats["triangles"], stats["silk_triangles"], stats["vertices"]], 27)
		await _settle()
		var shot := vp.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, Rect2i(0, 0, 500, 540), Vector2i(lod * 500, 0))
		vp.queue_free()
		await process_frame
	assert(sheet.save_png(output.path_join("webcap_lods.png")) == OK)
	if frames > 0:
		var dir := output.path_join("frames")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var vp := _view(Webcap.mesh(0), Vector2i(640, 560))
		var unit: MeshInstance3D = vp.get_node("Stage/Unit")
		unit.set_instance_shader_parameter("walk", 1.0)
		unit.set_instance_shader_parameter("gait", 7.0)
		for i in frames:
			unit.set_instance_shader_parameter("motion_time", float(i) / frames * TAU / 7.0)
			await _settle()
			vp.get_texture().get_image().save_png(dir.path_join("%03d.png" % i))
		vp.queue_free()
	print("WEBCAP RENDERS SAVED " + ProjectSettings.globalize_path(output))
	quit()


func _settle() -> void:
	for i in 24:
		await process_frame
	await RenderingServer.frame_post_draw


func _view(mesh: Mesh, size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_taa = true   # as in the game
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var stage := Node3D.new()
	stage.name = "Stage"
	vp.add_child(stage)
	var unit := MeshInstance3D.new()
	unit.name = "Unit"
	unit.mesh = mesh
	unit.set_instance_shader_parameter("motion_time", 0.19)
	unit.set_instance_shader_parameter("team", Color(0.92, 0.18, 0.12, 0.25))
	stage.add_child(unit)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.74, 0.72, 0.68)
	floor_mat.roughness = 0.95
	floor.material_override = floor_mat
	stage.add_child(floor)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.86, 0.85, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.83, 0.85, 0.91)
	environment.ambient_light_energy = 0.30
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -32, 0)
	key.light_color = Color(1.0, 0.98, 0.94)
	key.light_energy = 0.60
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 145, 0)
	fill.light_color = Color(0.68, 0.77, 1.0)
	fill.light_energy = 0.15
	stage.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.55
	camera.position = Vector3(2.5, 1.25, 3.2)
	stage.add_child(camera)
	camera.look_at(Vector3(0.02, 0.93, 0))
	camera.make_current()
	return vp


func _caption(vp: SubViewport, title: String, subtitle: String, size: int) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.19, 0.14, 0.08))
	label.position = Vector2(26, 20)
	vp.add_child(label)
	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.30, 0.24, 0.16))
	sub.position = Vector2(27, 26 + size)
	vp.add_child(sub)
