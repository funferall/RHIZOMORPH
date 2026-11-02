extends SceneTree
# A Blender-built unit in the real match scene, wearing its in-game art: a few standing,
# a few walking, one mid-attack, with other units for scale. Two screenshots.
#   godot --path . --script tools/art/ingame_unit.gd -- --unit=bruiser [--faction=1] [--out=res://art/bruiser]


func _initialize() -> void:
	run.call_deferred()


func opt(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return fallback


func run() -> void:
	var unit := opt("unit", "bruiser")
	var faction := int(opt("faction", "1" if unit in ["bruiser", "slinger", "bomber", "sniper", "runner"] else "0"))
	var out := opt("out", "res://art/" + unit)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g = main.game
	g.start(faction, false)
	g.toggle_pause()
	main.hud.menu.visible = false
	main.hud.visible = false
	var home: Vector2 = g.heart(faction).pos
	var at := home + (Vector2.ZERO - home).normalized() * 15.0
	var walkers := []
	for i in 5:
		var p := at + Vector2(-3.0 + i * 1.7, (i % 2) * 1.8 - 0.6)
		var u = g._spawn_unit(faction, unit, p)
		u.goal = p + Vector2(8, 0) if i % 2 == 0 else p
		if unit == "angel" and i < 3:
			u.reveal_t = 10.0
		walkers.append(u)
	walkers[1].strike = 0.62   # caught with its arms up
	var others: Array = Data().FACTIONS[faction]["starters"]
	for i in others.size():
		var q := at + Vector2(-2.0 + i * 1.6, -2.8)
		g._spawn_unit(faction, others[i], q).goal = q
	for i in 12:
		g._step(0.05)
	walkers[1].strike = 0.62
	for view in [[unit + "_ingame", 0.55, 15.0], [unit + "_ingame_close", 0.25, 7.5]]:
		main.rig.set_view(view[1], view[2], Vector3(at.x + 1.0, 0, at.y))
		main.rig.snap()
		for i in 24:
			g.time += 1.0 / 60.0
			g._update_visuals(1.0 / 60.0)
			walkers[1].strike = 0.62
			if unit == "angel":
				walkers[1].anim.play("Attack")
				walkers[1].anim.seek(0.95 * 0.43, true)
			else:
				walkers[1].mi.set_instance_shader_parameter("strike", 0.62)
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = out.path_join(view[0] + ".png")
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("SHOT ", ProjectSettings.globalize_path(path))
	quit()


func Data():
	return load("res://scripts/data.gd")
