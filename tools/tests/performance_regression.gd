extends SceneTree
# Run with Godot --path . --script tools/tests/performance_regression.gd
# Uses the real game/HUD and rendering server. No test doubles for UI state.

var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error(what)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g = main.game
	var hud = main.hud
	g.start(1, false)
	g.toggle_pause()
	hud.menu.visible = false
	hud._process(0.0)
	hud.set_process(false)
	var e = g._spawn_struct(1, "morel_patch", Vector2(60, 40), true)
	g.select([e])
	hud._refresh_ctx()
	var head = hud.ctx_box.get_child(0)
	var button = hud._ctx_train_buttons[0][0]
	var resources: Array = g.res(1)
	resources[0] = 10000.0
	resources[1] = 10000.0
	resources[2] = 100.0
	e.hp = 321.0
	hud._refresh_ctx()
	check(hud.ctx_box.get_child(0) == head, "Health refresh replaced header")
	check(hud._ctx_hp.text == "321 / 760", "Health did not refresh")
	button.grab_focus()
	button.pressed.emit()
	hud._refresh_ctx()
	check(e.queue == ["bruiser"], "Persistent training button failed")
	check(hud._ctx_train_buttons[0][0] == button, "Queue change replaced training button")
	check(button.has_focus(), "Refresh lost keyboard focus")
	var progress = hud._ctx_progress
	e.train_t = 2.0
	hud._refresh_ctx()
	check(hud._ctx_progress == progress and hud._ctx_progress_value > 0.0, "Progress did not update in place")
	button.pressed.emit()
	hud._refresh_ctx()
	check(e.queue == ["bruiser", "bruiser"], "Repeated training failed")
	check(hud._ctx_train_buttons[0][0] == button and button.has_focus(), "Queue growth replaced or unfocused training button")
	check(hud._ctx_queue.get_child_count() == 4, "Queue portraits did not grow")
	hud._ctx_queue.get_child(hud._ctx_queue.get_child_count() - 1).pressed.emit()
	hud._refresh_ctx()
	check(e.queue == ["bruiser"] and hud._ctx_queue.get_child_count() == 3, "Queue cancellation did not remove last portrait")
	resources[0] = 0.0
	hud._refresh_ctx()
	check(button.modulate != Color.WHITE, "Unaffordable state not shown")
	resources[0] = 10000.0
	hud._refresh_ctx()
	check(button.modulate == Color.WHITE, "Affordable state not restored")
	hud._ctx_queue.get_child(hud._ctx_queue.get_child_count() - 1).pressed.emit()
	hud._refresh_ctx()
	check(e.queue.is_empty() and not hud._ctx_queue.visible, "Cancel/refund button failed")
	e.connected = false
	hud._refresh_ctx()
	check(hud._ctx_status.text.begins_with("CUT OFF"), "Connectivity status stale")
	e.built = 0.5
	hud._refresh_ctx()
	check(hud._ctx_train_buttons.is_empty() and hud._ctx_status.text.begins_with("Growing 50%"), "Construction state stale")
	e.built = 1.0
	e.connected = true
	hud._refresh_ctx()
	check(hud._ctx_train_buttons.size() == 3, "Completion did not restore actions")
	var enemy = g._spawn_struct(2, "morel_patch", Vector2(64, 40), true)
	g.select([enemy])
	hud._refresh_ctx()
	check(hud._ctx_train_buttons.is_empty() and hud._ctx_queue == null, "Enemy selection exposed player actions")
	enemy.hp = 123.0
	enemy.connected = false
	hud._refresh_ctx()
	check(hud._ctx_hp.text == "123 / 760" and hud._ctx_status.text.begins_with("CUT OFF"), "Enemy live state stale")
	g._kill(enemy, null)
	hud._refresh_ctx()
	check(g.selected.is_empty() and not hud.ctx.visible, "Selected enemy death left context visible")
	g.select([e])
	hud._refresh_ctx()
	check(hud._ctx_train_buttons.size() == 3, "Reselection after death did not restore actions")
	var heart = g.heart(1)
	g.select([heart])
	hud._refresh_ctx()
	var tech: String = g.Data.TECHS.keys()[0]
	heart.research = tech
	heart.research_t = 1.0
	hud._refresh_ctx()
	check(hud._ctx_status.text.begins_with("Researching"), "Research progress stale")
	heart.research = ""
	var unit = g.units[0]
	g.select([unit])
	hud._refresh_ctx()
	check(hud._ctx_status.text.contains("dmg"), "Unit context missing")
	g.select([unit, e])
	hud._refresh_ctx()
	check(hud.ctx_box.get_child(0).get_child(0).text == "2 selected", "Group context missing")
	g.select([])
	hud._refresh_ctx()
	check(not hud.ctx.visible, "Empty selection remains visible")
	g.select([e])
	hud._refresh_ctx()
	e.flash = 1.0
	g._update_visuals(0.1)
	check(is_equal_approx(float(e.mi.get_instance_shader_parameter("flash")), 0.5), "Hit flash did not advance")
	g._update_visuals(1.0)
	check(e.mi.get_instance_shader_parameter("flash") == 0.0, "Hit flash did not reset")
	check(e.ring.get_instance_shader_parameter("selected") == 1.0, "Selection ring did not update")
	e.connected = false
	e.built = 0.5
	g._update_visuals(0.0)
	check(is_equal_approx(float(e.mi.get_instance_shader_parameter("wither")), 0.55), "Withering did not update")
	check(e.mi.get_instance_shader_parameter("growing") == 0.5, "Growth did not update")
	e.connected = true
	e.built = 1.0
	g._update_visuals(0.0)
	check(e.node.scale == Vector3.ONE, "Completed structure scale stale")
	check(e.mi.get_instance_shader_parameter("wither") == 0.0, "Restored connection did not clear wither")
	# Instant test structures do not create network links automatically.
	g._link(e, heart)
	var cord = g.cords.back()
	cord.grow = 0.5
	cord.regrow = 0.0
	cord.load = 0.7
	g._update_visuals(0.0)
	check(cord.mi.get_instance_shader_parameter("progress") == 0.5, "Cord growth stale")
	check(is_equal_approx(float(cord.mi.get_instance_shader_parameter("load")), 0.7), "Cord load stale")
	cord.regrow = 5.0
	g._update_visuals(0.0)
	check(cord.mi.get_instance_shader_parameter("severed") == 1.0, "Severed cord stale")
	cord.regrow = 0.0
	cord.grow = 1.0
	g._update_visuals(0.0)
	check(cord.mi.get_instance_shader_parameter("severed") == 0.0, "Regrown cord stale")
	# Optional isolated CPU comparison with the unmodified game script.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference-game="):
			var old = load(arg.trim_prefix("--reference-game=")).new()
			old.board = g.board
			old.myc = g.myc
			old.rig = g.rig
			root.add_child(old)
			old.start(1, false)
			old.set_process(false)
			# Equal seeded populations and settled state in two fresh games.
			var fresh = load("res://scripts/game.gd").new()
			fresh.board = g.board
			fresh.myc = g.myc
			fresh.rig = g.rig
			root.add_child(fresh)
			fresh.start(1, false)
			fresh.set_process(false)
			for sample in 3:
				for variant in [old, fresh]:
					variant._update_visuals(0.0)
					var begin := Time.get_ticks_usec()
					for i in 1000:
						variant._update_visuals(0.0)
					print("VISUAL_CPU ", "before" if variant == old else "after", " usec/call=", (Time.get_ticks_usec() - begin) / 1000.0)
			old.queue_free()
			fresh.queue_free()
	# Capture a selected production building, with an active queue, for visual QA.
	button = hud._ctx_train_buttons[0][0]
	button.pressed.emit()
	hud._refresh_ctx()
	main.rig.set_view(0.0, 26.0, Vector3(e.pos.x, 0, e.pos.y))
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/perf_review")
	root.get_texture().get_image().save_png("res://.godot/perf_review/hud.png")
	print("PERF_REGRESSION failures=", failures)
	quit(1 if failures else 0)
