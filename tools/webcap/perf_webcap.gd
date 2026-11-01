extends SceneTree
# Frame-time cost of the Violet Webcap art, measured in the real game scene with the real renderer.
# godot --path . --script tools/webcap/perf_webcap.gd [-- --count=60 --frames=240]
# Same units, same camera; only the mesh changes between runs. Prints one line per variant.

const Webcap = preload("res://scripts/webcap.gd")
const WebcapV1 = preload("res://tools/webcap/v1/webcap_v1.gd")
const FungusLib = preload("res://scripts/fungus_lib.gd")


func _initialize() -> void:
	run.call_deferred()


func arg(name: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return int(a.get_slice("=", 1))
	return fallback


func run() -> void:
	var count := arg("count", 60)
	var frames := arg("frames", 240)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g = main.game
	g.start(0, false)
	g.toggle_pause()
	main.hud.menu.visible = false
	main.hud.visible = false
	var home: Vector2 = g.heart(0).pos
	var at := home + (Vector2.ZERO - home).normalized() * 16.0
	var units := []
	var side := ceili(sqrt(count))
	for i in count:
		var u = g._spawn_unit(0, "webcap", at + Vector2((i % side) - side * 0.5, (i / side) - side * 0.5) * 1.9)
		u.goal = u.pos
		units.append(u)
	main.rig.set_view(0.6, 26.0, Vector3(at.x, 0, at.y))
	main.rig.snap()
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # as the game's --fpstest
	Engine.max_fps = 0
	var variants := [
		["none", null],
		["current in-game model", FungusLib.mesh("u_webcap")],
		["v1 procedural, battle", WebcapV1.mesh(1)],
		["v2 Blender, battle", Webcap.mesh(1)],
		["v2 Blender, close", Webcap.mesh(0)],
		["v2 Blender, distant", Webcap.mesh(2)],
	]
	# GPU clocks on a laptop drift by more than the effect being measured, so the variants
	# are interleaved over several rounds and each is compared with "none" in its own round.
	var rounds := arg("rounds", 6)
	var samples := {}
	for v in variants:
		samples[v[0]] = []
	for r in rounds:
		for v in variants:
			for u in units:
				u.node.visible = v[1] != null
				if v[1] != null:
					u.mi.mesh = v[1]
					u.mi.set_instance_shader_parameter("walk", 1.0)
			for i in 30:
				await process_frame
			# wall-clock frame time, median of the block: the frame is GPU-bound here
			var times := []
			var last := Time.get_ticks_usec()
			for i in frames:
				await process_frame
				var now := Time.get_ticks_usec()
				times.append((now - last) / 1000.0)
				last = now
				for u in units:
					u.mi.set_instance_shader_parameter("motion_time", (r * frames + i) / 60.0)
			times.sort()
			samples[v[0]].append(times[frames / 2])
	var base: Array = samples["none"]
	for v in variants:
		var deltas := []
		for r in rounds:
			deltas.append(samples[v[0]][r] - base[r])
		deltas.sort()
		var all: Array = samples[v[0]].duplicate()
		all.sort()
		var tris := 0
		if v[1] != null:
			for s in v[1].get_surface_count():
				var n: int = v[1].surface_get_array_index_len(s)
				tris += (n if n > 0 else v[1].surface_get_array_len(s)) / 3
		print("PERF %-24s frame median %.2f ms   added by %d Webcaps: median %+.2f ms (range %+.2f to %+.2f)   %d tris each" % [
			v[0], all[rounds / 2], count, deltas[rounds / 2], deltas[0], deltas[rounds - 1], tris])
	quit()
