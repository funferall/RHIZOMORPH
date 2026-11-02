extends SceneTree
## Real-match wall growth capture: fixed root, simulated growth and two stills.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g = main.game
	g.start(1, false)
	g.toggle_pause()
	main.hud.visible = false
	var home: Vector2 = g.heart(1).pos
	var at := home + (Vector2.ZERO - home).normalized() * 15.0
	var binder = g._spawn_unit(1, "binder", at)
	binder.wall_dir = Vector2.RIGHT
	binder.wall_limit = 8.0
	binder.facing = 0.0
	main.rig.set_view(0.55, 12.0, Vector3(at.x + 3.8, 0, at.y))
	main.rig.snap()
	var dir := "res://art/binder/frames_growth"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
	for i in 33:
		g._update_unit(binder, 1.0 if i > 0 else 0.0)
		g.time += 1.0
		g._update_visuals(0.0)
		for settle in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(dir.path_join("%03d.png" % i)))
	for view in [["binder_ingame.png", 0.55, 18.0], ["binder_ingame_close.png", 0.35, 10.0]]:
		main.rig.set_view(view[1], view[2], Vector3(at.x + 3.8, 0, at.y))
		main.rig.snap()
		for i in 24:
			g._update_visuals(0.0)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://art/binder/" + view[0]))
		print("SHOT ", view[0], " grown ", binder.wall_length)
	quit()
