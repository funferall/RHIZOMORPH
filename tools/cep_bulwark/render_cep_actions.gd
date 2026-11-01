extends "res://tools/cep_bulwark/render_cep_bulwark.gd"
## Deterministic actual-engine action sequences, 20 fps bash / 12 fps brace.
const Demo := preload("res://scripts/cep_action_demo.gd")
const Actions := preload("res://scripts/cep_actions.gd")

func _run() -> void:
	for lod in 3:
		var path: String = "res://art/cep_bulwark/cep_bulwark_" + CepBulwark.LOD_NAMES[lod] + ".res"
		assert(ResourceSaver.save(CepBulwark.mesh(lod),path) == OK)
	for action in ["bash","brace"]:
		var dir: String = "res://art/cep_bulwark/frames/"+action
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var vp := _view(CepBulwark.mesh(0),Vector2i(960,720))
		var stage := vp.get_node("Stage")
		stage.get_node("Unit").free()
		var demo := Demo.new()
		stage.add_child(demo)
		demo.set_process(false)
		var camera: Camera3D = stage.get_node("Camera")
		if action == "brace":
			camera.size = 5.65
			camera.position = Vector3(4.8,4.2,6.0)
			camera.look_at(Vector3(0,0.25,0))
		else:
			camera.size = 3.65
			camera.position = Vector3(3.1,1.9,5.0)
			camera.look_at(Vector3(0.65,0.6,0))
			# This is a target dummy, not a second braced unit.
			demo.target.visible = true
		_caption(vp,"CAP BASH" if action == "bash" else "ROOTED BRACE",
			"Wind up / cap impact / recovery" if action == "bash" else "Projectile capture area / 100 damage becomes 25",30)
		var status := Label.new()
		status.position = Vector2(28,650)
		status.add_theme_font_size_override("font_size",23)
		status.add_theme_color_override("font_color",Color(0.20,0.15,0.07))
		vp.add_child(status)
		var count := 48 if action == "bash" else 72
		var fps := 20.0 if action == "bash" else 12.0
		var fired := 0
		for i in count:
			if action == "bash" and i == 6:
				assert(demo.actions.attack())
			if action == "brace":
				if i == 4:
					demo.actions.toggle_brace()
				if i in [19,25,31,37]:
					demo.fire([-1.8,1.5,-0.5,0.8][fired])
					fired += 1
				if i == 56:
					demo.actions.toggle_brace()
			demo.advance(1.0/fps)
			status.text = "Capture active: %s    Absorbed: %d    Cep damage: %.0f" % [
				"YES" if demo.actions.capture_active() else "NO",demo.captured_count,demo.received_damage] if action == "brace" else "Automatic melee attack / rear legs drive the cap forward"
			await _settle()
			assert(vp.get_texture().get_image().save_png(dir.path_join("%03d.png"%i)) == OK)
			if action == "brace" and i == 44:
				assert(vp.get_texture().get_image().save_png("res://art/cep_bulwark/cep_bulwark_braced.png") == OK)
		if action == "brace":
			assert(demo.captured_count == 4 and demo.received_damage == 100.0 and demo.ally_damage == 0.0)
			print("BRACE DEMO: four 100-damage shots -> four 25-damage hits")
		vp.queue_free()
		await process_frame
	print("CEP ACTION ANIMATIONS RENDERED")
	quit()
