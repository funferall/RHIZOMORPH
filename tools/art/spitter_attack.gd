extends SceneTree
## A real in-game spit, driven by hand (no AI, no movement): the coil, the lash, the golden
## spray, the glob in flight and its impact. Frames for a combat GIF.
##   godot --path . --script tools/art/spitter_attack.gd
func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g = main.game
	g.start(0, false)
	g.toggle_pause()
	main.hud.visible = false
	var home: Vector2 = g.heart(0).pos
	var at := home + (-home).normalized() * 15.0
	var sp = g._spawn_unit(0, "spitter", at)
	var target = g._spawn_unit(1, "bruiser", at + Vector2(6, 0))
	sp.facing = 0.0
	target.facing = PI
	main.rig.set_view(0.42, 6.0, Vector3(at.x + 3.0, 0, at.y))
	main.rig.snap()
	g.fog.reveal(0, at + Vector2(3, 0), 14.0, 60.0)   # see the target and the spit's whole flight
	g.fog.update()
	for i in 24:
		g._update_visuals(0.0)
		await process_frame
	var dir := "res://art/spitter/frames_combat"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
	for i in 48:
		if i == 6:
			g._fire(sp, target, sp.d)
		g.time += 1.0 / 30.0
		g._update_swings(1.0 / 30.0)
		g._update_shots(1.0 / 30.0)
		g._update_visuals(1.0 / 30.0)
		for settle in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(dir.path_join("%03d.png" % i)))
	print("SPITTER COMBAT CAPTURE COMPLETE")
	quit()
