extends SceneTree
## Real engine renders and portable static models; no image-generation stand-ins.
## godot --path . --rendering-method gl_compatibility --script tools/cep_bulwark/render_cep_bulwark.gd
## -- --out=art/cep_bulwark --frames=16

const CepBulwark := preload("res://scripts/cep_bulwark.gd")
var output := "res://art/cep_bulwark"
var frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		if arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
	if not output.is_absolute_path():
		output = "res://" + output
	_run.call_deferred()


func _run() -> void:
	if "--poses-only" in OS.get_cmdline_user_args():
		await _render_poses()
		quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for lod in 3:
		var mesh := CepBulwark.mesh(lod)
		var path := output.path_join("cep_bulwark_" + CepBulwark.LOD_NAMES[lod])
		assert(ResourceSaver.save(mesh, path + ".res") == OK)
		_export_glb(mesh, path + ".glb")
		print("ASSET " + JSON.stringify(CepBulwark.stats(lod)))
	var hero := _view(CepBulwark.mesh(0), Vector2i(1400, 1050))
	_caption(hero, "CEP BULWARK", "Amanita Court / heavy protector", 38)
	await _settle()
	assert(hero.get_texture().get_image().save_png(output.path_join("cep_bulwark_hero.png")) == OK)
	hero.queue_free()
	await process_frame
	var sheet := Image.create(1500, 540, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.86, 0.85, 0.82))
	for lod in 3:
		var vp := _view(CepBulwark.mesh(lod), Vector2i(500, 540))
		var stats := CepBulwark.stats(lod)
		_caption(vp, str(stats["lod"]).to_upper(), "%d triangles / %d indexed vertices / 1 material" % [stats["triangles"], stats["vertices"]], 27)
		await _settle()
		sheet.blit_rect(vp.get_texture().get_image(), Rect2i(0, 0, 500, 540), Vector2i(lod * 500, 0))
		vp.queue_free()
		await process_frame
	assert(sheet.save_png(output.path_join("cep_bulwark_lods.png")) == OK)
	await _render_poses()
	if frames > 0:
		var dir := output.path_join("frames")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var vp := _view(CepBulwark.mesh(0), Vector2i(640, 560))
		var unit: MeshInstance3D = vp.get_node("Stage/Unit")
		unit.set_instance_shader_parameter("walk", 1.0)
		unit.set_instance_shader_parameter("gait", 4.8)
		for i in frames:
			unit.set_instance_shader_parameter("motion_time", float(i) / frames * TAU / 4.8)
			await _settle()
			vp.get_texture().get_image().save_png(dir.path_join("%03d.png" % i))
		vp.queue_free()
	print("CEP BULWARK RENDERS SAVED " + ProjectSettings.globalize_path(output))
	quit()


func _render_poses() -> void:
	var poses := Image.create(1500, 540, false, Image.FORMAT_RGBA8)
	for i in 3:
		var vp := _view(CepBulwark.mesh(0), Vector2i(500, 540))
		var unit: MeshInstance3D = vp.get_node("Stage/Unit")
		if i == 1:
			unit.set_instance_shader_parameter("brace", 1.0)
		if i == 2:
			var camera: Camera3D = vp.get_node("Stage/Camera")
			camera.position = Vector3(3.0, 5.0, 3.7)
			camera.look_at(Vector3(0.02, 0.65, 0))
		_caption(vp, ["IDLE", "BRACED", "RTS VIEW"][i],
			["Four planted limbs / chestnut shield", "Legs buried / cap shield exposed", "Heavy protector silhouette"][i], 27)
		await _settle()
		poses.blit_rect(vp.get_texture().get_image(), Rect2i(0, 0, 500, 540), Vector2i(i * 500, 0))
		vp.queue_free()
		await process_frame
	assert(poses.save_png(output.path_join("cep_bulwark_poses.png")) == OK)


func _settle() -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw


func _view(mesh: Mesh, size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var stage := Node3D.new()
	stage.name = "Stage"
	vp.add_child(stage)
	var unit := MeshInstance3D.new()
	unit.name = "Unit"
	unit.mesh = mesh
	unit.set_instance_shader_parameter("motion_time", 0.19)
	unit.set_instance_shader_parameter("team", Color(0.8, 0.12, 0.05, 0.10))
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
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.35
	camera.position = Vector3(3.0, 1.48, 3.7)
	stage.add_child(camera)
	camera.look_at(Vector3(0.02, 0.65, 0))
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


func _export_glb(source: ArrayMesh, path: String) -> void:
	# Static interchange meshes retain baked RGB paint. Shader gait stays in Godot.
	var arrays := source.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in colors.size():
		colors[i].a = 1.0
	arrays[Mesh.ARRAY_COLOR] = colors
	var portable := ArrayMesh.new()
	portable.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = CepBulwark.material().get_shader_parameter("albedo_map")
	mat.roughness = 0.7
	mat.normal_enabled = true
	mat.normal_texture = CepBulwark.material().get_shader_parameter("normal_roughness_map")
	mat.normal_scale = 0.45
	portable.surface_set_material(0, mat)
	var node := MeshInstance3D.new()
	node.name = source.resource_name
	node.mesh = portable
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert(doc.append_from_scene(node, state) == OK)
	assert(doc.write_to_filesystem(state, path) == OK)
	# Godot leaves conversion PNGs beside the GLB, which embeds both images.
	for suffix in ["__normal.png", "__albedo.png"]:
		var intermediate: String = path.get_basename() + suffix
		if FileAccess.file_exists(intermediate):
			DirAccess.remove_absolute(intermediate)
	node.free()
