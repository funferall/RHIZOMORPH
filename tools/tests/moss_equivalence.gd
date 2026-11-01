extends SceneTree
# Compare rendered moss pixels, with temporal effects and other geometry removed.
# godot --path . --script tools/tests/moss_equivalence.gd -- --reference-moss=PATH
func _initialize() -> void:
	create_timer(90.0).timeout.connect(func():
		push_error("Moss equivalence timed out waiting for rendering")
		quit(1))
	run.call_deferred()

func run() -> void:
	var reference := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference-moss="):
			reference = arg.trim_prefix("--reference-moss=")
	if not FileAccess.file_exists(reference):
		push_error("Supply --reference-moss=PATH to the original moss.gdshader")
		quit(1)
		return
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.hud.visible = false
	main.game.visible = false
	for node in main.get_children():
		if node is GPUParticles3D:
			node.visible = false
	for node in main.board.get_children():
		if node is GeometryInstance3D:
			node.visible = node is MultiMeshInstance3D
	main.sun.shadow_enabled = false
	main.env.ssr_enabled = false
	main.env.ssao_enabled = false
	main.env.ssil_enabled = false
	main.env.volumetric_fog_enabled = false
	main.env.glow_enabled = false
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = 1.0
	root.use_taa = false
	main.rig.attrs.dof_blur_amount = 0.0
	var mat: ShaderMaterial = main.board.moss_mat
	var optimized := mat.shader
	var original := Shader.new()
	original.code = FileAccess.get_file_as_string(reference)
	var same := true
	DirAccess.make_dir_recursive_absolute("res://.godot/perf_review")
	for distance in [18.0, 36.0]:
		main.rig.set_view(0.3, distance, Vector3.ZERO)
		main.rig.snap()
		main.board.update_moss_lod(main.rig.cam.global_position)
		var frames: Array[Image] = []
		for shader in [original, optimized]:
			mat.shader = shader
			for i in 20:
				await process_frame
			await RenderingServer.frame_post_draw
			frames.append(root.get_texture().get_image())
		if frames[0].is_empty() or frames[1].is_empty():
			push_error("Empty moss image readback at distance %s" % distance)
			same = false
		elif frames[0].get_data() != frames[1].get_data():
			push_error("Moss images differ at distance %s" % distance)
			same = false
		# Identical backgrounds must not pass when both shaders failed to draw.
		main.board.visible = false
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var background := root.get_texture().get_image()
		main.board.visible = true
		if background.is_empty() or frames[0].get_data() == background.get_data() or frames[1].get_data() == background.get_data():
			push_error("Moss coverage missing at distance %s" % distance)
			same = false
		var suffix := "" if distance == 18.0 else "_far"
		frames[0].save_png("res://.godot/perf_review/moss_before%s.png" % suffix)
		frames[1].save_png("res://.godot/perf_review/moss_after%s.png" % suffix)
	print("MOSS_EQUIVALENCE ", "PASS: byte-identical rendered images at two distances" if same else "FAIL: images differ or readback failed")
	mat.shader = optimized
	original = null
	optimized = null
	mat = null
	# This test never starts a match. Weather is allocated by Game but only
	# parented in start(), so scene teardown alone cannot release that node.
	if main.game.weather.get_parent() == null:
		main.game.weather.free()
	main.queue_free()
	main = null
	await process_frame
	await process_frame
	# Let this coroutine return and release its loop-local images/shader arrays
	# before SceneTree begins shutdown and checks remaining resource references.
	quit.call_deferred(0 if same else 1)
