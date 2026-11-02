extends SceneTree
## Real-game projectile and cobra strike capture, driven without AI or movement.
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
	var at := home + (-home).normalized() * 15.0
	var sl = g._spawn_unit(1, "sniper", at)
	var target = g._spawn_unit(0, "wartling", at + Vector2(5, 0))
	sl.facing = 0.0
	main.rig.set_view(0.55, 8.0, Vector3(at.x + 1.5, 0, at.y))
	main.rig.snap()
	for i in 24:
		g._update_visuals(0.0)
		await process_frame
	var dir := "res://art/sniper/frames_combat"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
	for i in 45:
		if i == 6:
			g._fire(sl, target, sl.d)
		g.time += 1.0 / 30.0
		g._update_sniper_windups()
		g._update_shots(1.0 / 30.0)
		g._update_visuals(1.0 / 30.0)
		for settle in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(dir.path_join("%03d.png" % i)))
	print("SNIPER COMBAT CAPTURE COMPLETE")
	quit()
