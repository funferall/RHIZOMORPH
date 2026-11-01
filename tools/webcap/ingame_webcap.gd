extends SceneTree
# Preview only: the real game scene with Webcaps wearing the new mesh. Does not change game code.
# godot --path . --script tools/webcap/ingame_webcap.gd -- --out=DIR

const Webcap = preload("res://scripts/webcap.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var out := "res://art/webcap"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g = main.game
	g.start(0, false)
	g.toggle_pause()
	main.hud.menu.visible = false
	main.hud.visible = false
	var home: Vector2 = g.heart(0).pos
	var at := home + (Vector2.ZERO - home).normalized() * 14.0
	var caps := []
	for i in 4:
		var u = g._spawn_unit(0, "webcap", at + Vector2(-2.0 + i * 1.8, (i % 2) * 1.6))
		u.mi.mesh = Webcap.mesh(1 if i > 0 else 0)
		u.mi.set_instance_shader_parameter("gait", 6.5 + i * 0.4)
		u.goal = u.pos + Vector2(6, 0) if i % 2 == 0 else u.pos
		caps.append(u)
	for i in 3:
		g._spawn_unit(0, "wartling", at + Vector2(-3.5 + i * 1.4, -2.6)).goal = at + Vector2(-3.5 + i * 1.4, -2.6)
	g._spawn_unit(0, "cep", at + Vector2(3.5, -2.8)).goal = at + Vector2(3.5, -2.8)
	for i in 10:
		g._step(0.05)
	for view in [["webcap_ingame", 0.55, 15.0], ["webcap_ingame_close", 0.2, 8.0]]:
		main.rig.set_view(view[1], view[2], Vector3(at.x + 1.0, 0, at.y))
		main.rig.snap()
		for i in 20:
			g.time += 1.0 / 30.0
			g._update_visuals(1.0 / 30.0)
			for u in caps:
				u.mi.set_instance_shader_parameter("motion_time", g.time)
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = out.path_join(view[0] + ".png")
		root.get_texture().get_image().save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
	quit()
