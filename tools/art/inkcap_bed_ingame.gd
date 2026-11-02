extends SceneTree
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
	var bed = g._spawn_struct(1, "inkcap_bed", at, true)
	bed.connected = true
	for view in [["inkcap_bed_ingame", .55, 13.0], ["inkcap_bed_ingame_close", .25, 7.0]]:
		main.rig.set_view(view[1], view[2], Vector3(at.x, 0, at.y))
		main.rig.snap()
		for i in 24:
			g.time += 1.0 / 60.0
			g._update_visuals(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://art/inkcap_bed/" + view[0] + ".png"))
		print("SHOT ", view[0])
	quit()
