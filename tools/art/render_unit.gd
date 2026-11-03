extends SceneTree
## Studio renders of a Blender-built unit: hero shot, LOD sheet, and optional walk and
## attack frames (for GIFs). Real engine, real shaders, TAA on as in the game.
##   godot --path . --script tools/art/render_unit.gd -- --unit=bruiser [--out=res://art/bruiser] [--frames=24]

const UNITS := {
	"binder": ["res://scripts/coral_binder.gd", "CORAL BINDER", "Morel Hollow / growing barricade", Color(0.98, 0.8, 0.22, 0.25)],
	"bracket": ["res://scripts/rot_bracket.gd", "ROT BRACKET", "Morel Hollow / cellulose digester", Color(0.98, 0.8, 0.22, 0.08)],
	"t_beetle": ["res://scripts/whitecoat_beetle.gd", "WHITECOAT BULWARK", "Veiled Choir / armoured frontline", Color(0.74, 0.46, 1.0, 0.18)],
	"beetle": ["res://scripts/whitecoat_beetle.gd", "LEPTINOTARSA", "Wild host, before the Choir takes it", Color(1.0, 1.0, 1.0, 0.0)],
	"spitter": ["res://scripts/muscarine_spitter.gd", "MUSCARINE SPITTER", "Amanita Court / ranged poison", Color(0.92, 0.18, 0.12, 0.25)],
	"inkcap_bed": ["res://scripts/inkcap_bed.gd", "INKCAP BED", "Morel Hollow / salvage", Color(0.98, 0.8, 0.22, 0.25)],
	"runner": ["res://scripts/candlesnuff_runner.gd", "CANDLESNUFF RUNNER", "Morel Hollow / scout", Color(0.98, 0.8, 0.22, 0.25)],
	"sniper": ["res://scripts/pilobolus_sniper.gd", "PILOBOLUS SNIPER", "Morel Hollow / precision fire", Color(0.98, 0.8, 0.22, 0.25)],
	"bomber": ["res://scripts/puffball_bomber.gd", "PUFFBALL BOMBER", "Morel Hollow / area bombardment", Color(0.98, 0.8, 0.22, 0.25)],
	"slinger": ["res://scripts/elf_cup_slinger.gd", "ELF-CUP SLINGER", "Morel Hollow / ranged pressure", Color(0.98, 0.8, 0.22, 0.25)],
	"webcap": ["res://scripts/webcap.gd", "VIOLET WEBCAP", "Amanita Court / control", Color(0.92, 0.18, 0.12, 0.25)],
	"sailwing": ["res://scripts/mycena_sailwing.gd", "MYCENA SAILWING", "Amanita Court / flying skirmisher", Color(0.92, 0.18, 0.12, 0.25)],
	"bruiser": ["res://scripts/morel_bruiser.gd", "MOREL BRUISER", "Morel Hollow / regenerating frontline", Color(0.98, 0.8, 0.22, 0.25)],
}
var unit := "bruiser"
var output := ""
var frames := 0
var art


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--unit="):
			unit = arg.trim_prefix("--unit=")
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		if arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
	if output == "":
		output = "res://art/" + unit
	art = load(UNITS[unit][0])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for lod in 3:
		print("ASSET " + JSON.stringify(_stats(lod)))
	var hero := _view(_mesh(0), Vector2i(1400, 1050), 0.0)
	_caption(hero, UNITS[unit][1], UNITS[unit][2], 38)
	await _settle(24)
	_save(hero, unit + "_hero.png")
	hero.queue_free()
	var close := _view(_mesh(0), Vector2i(1000, 1000), 0.0, 0.42)
	await _settle(24)
	_save(close, unit + "_detail.png")
	close.queue_free()
	await process_frame
	var sheet := Image.create(1500, 540, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.86, 0.85, 0.82))
	for lod in 3:
		var vp := _view(_mesh(lod), Vector2i(500, 540), 0.0)
		var st: Dictionary = _stats(lod)
		_caption(vp, str(st["lod"]).to_upper(), "%d triangles / %d vertices / %d surface(s)" % [st["triangles"], st["vertices"], st["surfaces"]], 27)
		await _settle(16)
		var shot := vp.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, Rect2i(0, 0, 500, 540), Vector2i(lod * 500, 0))
		vp.queue_free()
		await process_frame
	sheet.save_png(ProjectSettings.globalize_path(output.path_join(unit + "_lods.png")))
	if frames > 0:
		for clip in (["infect"] if unit == "beetle" else ["walk", "attack"]):
			var dir := output.path_join("frames_" + clip)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
			var vp := _view(_mesh(0) if clip != "infect" else art.mesh(0, true), Vector2i(640, 560), 0.0)
			var mi: MeshInstance3D = vp.get_node("Stage/Unit")
			mi.set_instance_shader_parameter("walk", 1.0 if clip == "walk" else 0.0)
			var gait: float = 13.0 if unit == "t_beetle" else 6.6 if unit == "spitter" else (5.6 if unit == "bruiser" else (9.2 if unit == "runner" else 7.0))
			mi.set_instance_shader_parameter("gait", gait)
			await _settle(8)
			for i in frames:
				var t := float(i) / frames
				if clip == "infect":
					mi.set_instance_shader_parameter("infect", t * 1.15)
				mi.set_instance_shader_parameter("motion_time", t * 3.0 if clip == "infect" else t * TAU * (2.0 if unit == "runner" else 1.0) / gait if clip == "walk" else 1.0 + t * (art.SWING_SECONDS if unit in ["spitter", "t_beetle", "sailwing"] else 0.72 if unit == "slinger" else (0.8 if unit == "runner" else 0.6)))
				mi.set_instance_shader_parameter("strike", 1.0 - t if clip == "attack" else 0.0)
				await _settle(3)
				vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(dir.path_join("%03d.png" % i)))
			vp.queue_free()
			await process_frame
	print("RENDERS SAVED " + ProjectSettings.globalize_path(output))
	quit()


# The beetle art carries both forms: "beetle" renders it healthy.
func _mesh(lod: int) -> Mesh:
	return art.mesh(lod, false) if unit == "beetle" else art.mesh(lod)


func _stats(lod: int) -> Dictionary:
	return art.stats(lod, false) if unit == "beetle" else art.stats(lod)


func _save(vp: SubViewport, name: String) -> void:
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(name)))


func _settle(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw


# zoom < 1 frames a closer crop around the upper body
func _view(mesh: Mesh, size: Vector2i, yaw_offset: float, zoom := 1.0) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_taa = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var stage := Node3D.new()
	stage.name = "Stage"
	vp.add_child(stage)
	var mi := MeshInstance3D.new()
	mi.name = "Unit"
	mi.mesh = mesh
	mi.set_instance_shader_parameter("motion_time", 0.4)
	mi.set_instance_shader_parameter("team", UNITS[unit][3])
	mi.set_instance_shader_parameter("infect", 0.0 if unit == "beetle" else 1.0)
	stage.add_child(mi)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.74, 0.72, 0.68)
	floor_mat.roughness = 0.95
	floor.material_override = floor_mat
	stage.add_child(floor)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.85, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.83, 0.85, 0.91)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -32, 0)
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 0.65
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 145, 0)
	fill.light_color = Color(0.68, 0.77, 1.0)
	fill.light_energy = 0.16
	stage.add_child(fill)
	var box := AABB()
	var first := true
	for si in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	var centre := box.get_center()
	var extent := maxf(box.size.y, maxf(box.size.x, box.size.z))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extent * 1.32 * zoom
	var aim := centre + Vector3(0, extent * (0.18 if zoom < 1.0 else 0.0), 0)
	var dir := Vector3(sin(0.68 + yaw_offset), 0.38, cos(0.68 + yaw_offset)).normalized()
	cam.position = aim + dir * 6.0
	stage.add_child(cam)
	cam.look_at(aim)
	cam.make_current()
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
