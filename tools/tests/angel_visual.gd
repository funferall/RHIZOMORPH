extends SceneTree
const Angel = preload("res://scripts/destroying_angel.gd")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var parts := Angel.instance()
	root.add_child(parts[0])
	var player: AnimationPlayer = parts[2]
	var trails = player.get_meta("slice_trails")
	for level in 3:
		Angel.set_lod(parts[1], level)
		assert(parts[1].mesh.get_surface_count() == 1)
	player.play("Attack")
	player.seek(0.0, true)
	for i in 52:
		player.advance(1.0 / 120.0)
		trails.tick(1.0 / 120.0, player, false)
	assert(trails.mesh.get_surface_count() == 6, "Both blades leave three air streaks")
	var clock_before: float = trails.elapsed
	trails.tick(0.0, player, false)
	assert(trails.elapsed == clock_before, "Pause freezes trails")
	for i in 30:
		player.advance(1.0 / 120.0)
		trails.tick(1.0 / 120.0, player, false)
	assert(trails.mesh.get_surface_count() == 0, "Trails expire after the cut")
	player.seek(0.40, true)
	for i in 3:
		trails.tick(0.01, player, false)
	assert(trails.mesh.get_surface_count() == 6)
	trails.tick(0.01, player, true)
	assert(trails.mesh.get_surface_count() == 0, "Cloak removes trails")
	print("PASS Angel: three LODs, both blade trails, pause, expiration, cloak suppression")
	parts[0].free()
	quit()
