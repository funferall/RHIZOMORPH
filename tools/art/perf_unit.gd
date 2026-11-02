extends SceneTree
# Frame-time cost of a Blender-built unit's art, in the real match scene, real renderer.
#   godot --path . --script tools/art/perf_unit.gd -- --unit=bruiser [--count=60 --frames=150 --rounds=8]
# Same units and camera; only the mesh changes. Vsync off, as the game's --fpstest.
# Laptop GPU clocks drift by more than the effect being measured, so variants are
# interleaved over rounds and each is compared with "none" in its own round.

const FungusLib = preload("res://scripts/fungus_lib.gd")
const ART := {"bomber": ["res://scripts/puffball_bomber.gd", "u_bomber"], "runner": ["res://scripts/candlesnuff_runner.gd", "u_runner"], "webcap": ["res://scripts/webcap.gd", "u_webcap"], "bruiser": ["res://scripts/morel_bruiser.gd", "u_bruiser"],
	"spitter": ["res://scripts/muscarine_spitter.gd", "u_spitter"], "t_beetle": ["res://scripts/whitecoat_beetle.gd", "t_beetle"]}


func _initialize() -> void:
	run.call_deferred()


func opt(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return fallback


func run() -> void:
	var unit := opt("unit", "bruiser")
	var count := int(opt("count", "60"))
	var frames := int(opt("frames", "150"))
	var rounds := int(opt("rounds", "8"))
	var art = load(ART[unit][0])
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g = main.game
	g.start(1, false)
	g.toggle_pause()
	main.hud.menu.visible = false
	main.hud.visible = false
	var home: Vector2 = g.heart(1).pos
	var at := home + (Vector2.ZERO - home).normalized() * 16.0
	var units := []
	var side := ceili(sqrt(count))
	for i in count:
		var u = g._spawn_unit(1, unit, at + Vector2((i % side) - side * 0.5, (i / side) - side * 0.5) * 1.9)
		u.goal = u.pos
		units.append(u)
	main.rig.set_view(0.6, 26.0, Vector3(at.x, 0, at.y))
	main.rig.snap()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var variants := [
		["none", null],
		["old procedural model", FungusLib.legacy_mesh(ART[unit][1])],
		["new, battle detail", art.mesh(1)],
		["new, close detail", art.mesh(0)],
		["new, distant detail", art.mesh(2)],
	]
	if unit == "t_beetle":
		variants.append(["new, battle, healthy", art.mesh(1, false)])
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
		print("PERF %-22s frame median %.2f ms   added by %d units: median %+.2f ms (middle half %+.2f to %+.2f)   %d tris each" % [
			v[0], all[rounds / 2], count, deltas[rounds / 2], deltas[rounds / 4], deltas[rounds * 3 / 4], tris])
	quit()
