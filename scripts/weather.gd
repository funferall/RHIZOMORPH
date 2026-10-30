extends Node3D
# The forest's weather, drawn every 2-4 minutes and announced 15 s ahead.
#   rain       45 s: mycelium grows x1.5, building and training x1.25, insects breed x0.5
#   dry spell  60 s: insects breed x1.5
#   windstorm  20 s: branches fall as small deposits, every snag is felled into a log,
#                    and trees below 0.3 vigor may come down with them
# Every 8 minutes the canopy drops its leaves: litter piles refill and new ones
# gather under the big trees.

const Data = preload("res://scripts/data.gd")
const ANNOUNCE := 15.0
const KINDS := {
	"rain": {"dur": 45.0, "say": "Rain is coming. The mycelium will flush.", "col": Color(0.6, 0.75, 0.95)},
	"dry": {"dur": 60.0, "say": "A dry spell is coming. The insects will swarm.", "col": Color(0.95, 0.75, 0.4)},
	"wind": {"dur": 20.0, "say": "A windstorm is coming. Snags and weak trees will fall.", "col": Color(0.8, 0.8, 0.7)},
}
const LEAF_FALL := 480.0

var g: Node
var now := ""            # the weather in force ("" for fair)
var next := ""
var next_t := 150.0      # seconds until the next weather arrives
var left := 0.0          # seconds of the current weather left
var _said := false
var _gust_t := 0.0
var _leaf_t := LEAF_FALL
var _rng := RandomNumberGenerator.new()
var _rain: GPUParticles3D
var _sun_energy := -1.0


func setup(game: Node) -> void:
	g = game
	_rng.seed = 777 + game.match_seed * 13
	next = _pick()
	next_t = _rng.randf_range(110.0, 170.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			next = a.trim_prefix("--weather=")   # testing: this weather arrives in 20 s
			next_t = 20.0
	_build_rain()


func growth_mult() -> float:
	return 1.5 if now == "rain" else 1.0


func build_mult() -> float:
	return 1.25 if now == "rain" else 1.0


func breed_mult() -> float:
	return 0.5 if now == "rain" else (1.5 if now == "dry" else 1.0)


func _pick() -> String:
	var r := _rng.randf()
	return "rain" if r < 0.45 else ("dry" if r < 0.7 else "wind")


func tick(dt: float) -> void:
	var at: Vector3 = g.rig.target
	_rain.global_position = Vector3(at.x, 28.0, at.z)
	if now != "":
		left -= dt
		if now == "wind":
			_gust_t -= dt
			if _gust_t <= 0.0:
				_gust_t = _rng.randf_range(3.0, 6.0)
				_gust()
		if left <= 0.0:
			now = ""
			_rain.emitting = false
			_light(1.0)
	else:
		next_t -= dt
		if next_t <= ANNOUNCE and not _said:
			_said = true
			g.emit_signal("message", KINDS[next]["say"], KINDS[next]["col"])
		if next_t <= 0.0:
			now = next
			left = KINDS[now]["dur"]
			_said = false
			next = _pick()
			next_t = _rng.randf_range(120.0, 240.0)
			_begin()
	_leaf_t -= dt
	if _leaf_t <= 0.0:
		_leaf_t = LEAF_FALL
		_leaf_fall()


func _begin() -> void:
	match now:
		"rain":
			_rain.emitting = true
			_light(0.55)
		"dry":
			_light(1.15)
		"wind":
			_gust_t = 0.5
			_light(0.8)
			# every standing dead tree comes down
			for t in g.forest.trees:
				if not t["alive"] and not t.get("felled", false):
					g.forest.fell(t["i"], Vector2.from_angle(_rng.randf() * TAU))
			for t in g.forest.trees:
				if t["alive"] and t["vigor"] < 0.3 and _rng.randf() < 0.25:
					g.forest.kill_tree(t["i"])
					g.forest.fell(t["i"], Vector2.from_angle(_rng.randf() * TAU))


# A gust brings down a branch somewhere under the canopy.
func _gust() -> void:
	var trees: Array = g.forest.trees.filter(func(t): return t["alive"])
	if trees.is_empty():
		return
	var t: Dictionary = trees[_rng.randi() % trees.size()]
	var a := _rng.randf() * TAU
	var p: Vector2 = t["pos"] + Vector2.from_angle(a) * _rng.randf_range(t["radius"] * 2.0 + 2.0, t["roots"])
	if g.board.in_bounds(p, 3.0) and g.board.water_at(p) < 0.2:
		g.forest.add_branch(p, Vector2.from_angle(_rng.randf() * TAU))


func _leaf_fall() -> void:
	g.emit_signal("message", "The canopy drops its leaves. Fresh litter covers the floor.", Color(0.85, 0.65, 0.35))
	g.forest.leaf_fall(_rng)


func _light(k: float) -> void:
	var sun: DirectionalLight3D = g.get_parent().get("sun")
	if sun == null:
		return
	if _sun_energy < 0.0:
		_sun_energy = sun.light_energy
	var tw := create_tween()
	tw.tween_property(sun, "light_energy", _sun_energy * k, 4.0)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 7000
	_rain.lifetime = 1.4
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-50, -35, -50), Vector3(100, 45, 100))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(45.0, 1.0, 45.0)   # dense where the camera looks
	pm.direction = Vector3(0.15, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_align_y = true
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 0.9, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	_rain.draw_pass_1 = q
	_rain.position = Vector3(0, 28, 0)
	add_child(_rain)
