extends SceneTree
## Capture a Rot Bracket in the real match scene.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g = main.game
	g.start(1, false)
	g.toggle_pause()
	main.hud.menu.visible = false
	main.hud.visible = false
	var home: Vector2 = g.heart(1).pos
	var at := home + (Vector2.ZERO - home).normalized() * 15.0
	var structure = g._spawn_struct(1, "rot_bracket", at, true)
	for view in [["bracket_ingame.png", 0.55, 15.0], ["bracket_ingame_close.png", 0.25, 7.5]]:
		main.rig.set_view(view[1], view[2], Vector3(at.x, 0, at.y))
		main.rig.snap()
		for i in 24:
			g._update_visuals(0.0)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://art/bracket/" + view[0]))
		print("SHOT ", view[0], " mesh ", structure.mi.mesh.resource_name)
	quit()
