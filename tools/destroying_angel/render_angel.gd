extends "res://tools/art/render_unit.gd"

const Angel = preload("res://scripts/destroying_angel.gd")

func _initialize() -> void:
	output = "res://art/destroying_angel"
	_run.call_deferred()

func _run() -> void:
	for mode in ["revealed", "cloaked", "attack", "walk"]:
		var vp := _view(Angel.lod(0)[0], Vector2i(1000, 900), 0.0)
		vp.get_node("Stage/Unit").free()
		var parts := Angel.instance()
		var model: Node3D = parts[0]
		model.scale = Vector3.ONE
		model.rotation.y = 0.0
		vp.get_node("Stage").add_child(model)
		var player: AnimationPlayer = parts[2]
		var trails = player.get_meta("slice_trails")
		parts[1].material_override = Angel.material(mode == "cloaked")
		_caption(vp, "DESTROYING ANGEL", mode.to_upper() + " / Amanita Court", 28)
		player.play("Attack" if mode == "attack" else ("Walk" if mode == "walk" else "Idle"))
		player.seek(0.0, true)
		await _settle(12)
		if mode in ["attack", "walk"]:
			var dir := output.path_join("frames_" + mode)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
			FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
			var duration := 0.95 if mode == "attack" else 1.2
			for i in 48:
				for sample in 3:
					player.advance(duration / 144.0)
					trails.tick(duration / 144.0, player, false)
				await _settle(2)
				vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(dir.path_join("%03d.png" % i)))
		else:
			_save(vp, mode + ".png")
		vp.queue_free()
		await process_frame
	print("ANGEL REVIEW COMPLETE")
	quit()
