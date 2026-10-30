extends Node3D
# The war itself: structures, rhizomorph cords and supply, sporeling units,
# combat, spore actions, tech, economy read from the GPU mycelium, and the
# per-frame source list that tells the mycelium where each faction reaches.
# forest.gd keeps the world around them: tree vigor, deposits, insect nests.
# Insects are units of faction Data.NEUTRAL.
# The HUD drives it through the public API (try_place, order_*, cast, ...);
# ai.gd drives the other factions through the same calls.

signal message(text: String, col: Color)
signal game_over(won: bool)
signal sound(name: String, at: Vector3)   # at = Vector3.INF for flat UI sounds

const Data = preload("res://scripts/data.gd")
const FungusLib = preload("res://scripts/fungus_lib.gd")
const AI = preload("res://scripts/ai.gd")
const Forest = preload("res://scripts/forest.gd")
const Fog = preload("res://scripts/fog.gd")
const Weather = preload("res://scripts/weather.gd")

enum { UNIT, STRUCT, CORD, PUFF }

class Ent:
	var kind := 0
	var id := ""
	var d: Dictionary
	var f := 0
	var pos := Vector2.ZERO
	var hp := 1.0
	var max_hp := 1.0
	var radius := 1.0
	var alive := true
	var node: Node3D
	var mi: MeshInstance3D
	var ring: MeshInstance3D
	var flash := 0.0
	var poison_dps := 0.0
	var poison_t := 0.0
	var slow := 0.0
	var slow_t := 0.0
	var selected := false
	var dying := 0.0
	# structures
	var built := 1.0
	var connected := true
	var cords: Array = []
	var queue: Array = []
	var train_t := 0.0
	var research := ""
	var research_t := 0.0
	var rally := Vector2.INF
	var cd := 0.0
	var tree := -1
	var dep := {}          # the deposit a Rot Bracket digests
	var spotted := false   # the player has seen it (enemy structures stay as last seen)
	var seen_by := 0       # bit per faction that has ever had it in sight (the AI's memory)
	# units
	var vel := Vector2.ZERO
	var goal := Vector2.INF
	var target: Ent = null
	var amove := false
	var facing := 0.0
	var walk := 0.0
	var think_t := 0.0
	var home := Vector2.INF
	var squad := ""
	var corpse := false    # its body stays on the board as a deposit
	var summit := Vector2.INF
	var burst := -1.0      # sporulation countdown
	var nest := 0          # insects: the nest that bred it
	var infect := 0.0      # insects: how sick they are
	var life := INF        # short-lived insects (borers) count down
	# cords
	var a: Ent = null
	var b: Ent = null
	var regrow := 0.0
	var grow := 0.0
	var length := 1.0
	var load := 0.0        # carried income / capacity
	# giant puffball
	var timer := 0.0


var board: Node3D
var myc: Node
var rig: Node3D
var started := false
var player := 1
var bot := false
var time := 0.0
var paused := false
var speed := 1.0
var over := false
var match_seed := 0       # --match=N varies the AI and the forest between bot games

var units: Array[Ent] = []
var structs: Array[Ent] = []
var cords: Array[Ent] = []
var puffs: Array[Ent] = []
var selected: Array[Ent] = []
var fs: Array[Dictionary] = []
var ais: Array = []
var forest = Forest.new()
var flows: Array = []        # [source structure, resource index, amount/s] waiting to be carried home
var fog = Fog.new()
var weather = Weather.new()
var zones: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var _grid := {}
var _conn_dirty := true
var _econ_t := 0.0
var _decor_t := 0.0
var _ff_left := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _log := OS.get_cmdline_user_args().has("--log")
var _log_t := 0.0
var _stats := {}

var _ring_mat: ShaderMaterial
var _cord_mat: ShaderMaterial
var _shot_mats := {}
var _shot_mesh: SphereMesh
var _decor: Array = []        # per faction: Array of {mm, pts, born, species}
var _spark_mesh: QuadMesh


# --- setup ---------------------------------------------------------------------

func _ready() -> void:
	_rng.seed = 1234
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load("res://shaders/ring.gdshader")
	_cord_mat = ShaderMaterial.new()
	_cord_mat.shader = load("res://shaders/cord.gdshader")
	_shot_mesh = SphereMesh.new()
	_shot_mesh.radius = 0.16
	_shot_mesh.height = 0.32
	_shot_mesh.radial_segments = 8
	_shot_mesh.rings = 4
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.14, 0.14)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	_spark_mesh.material = sm


func start(faction: int, as_bot: bool) -> void:
	_rng.seed = 1234 + match_seed * 7919
	player = faction
	bot = as_bot
	started = true
	time = 0.0
	fs.clear()
	for f in 3:
		var fd: Dictionary = Data.FACTIONS[f]
		var sr: Array = fd["start_res"]
		fs.append({
			"res": [sr[0], sr[1], sr[2]],
			"rate": [0.0, 0.0, 0.0],
			"techs": {}, "cds": {}, "alive": true, "heart": null, "web": {},
			"key": fd["key"], "name": fd["name"], "color": fd["color"], "economy": fd["economy"],
		})
		var h := _spawn_struct(f, fd["heart"], Data.START_POS[f], true)
		fs[f]["heart"] = h
		h.rally = Data.START_POS[f].lerp(Vector2.ZERO, 0.2)
		_decor.append([])
		for sp in fd["decor"]:
			_decor[f].append(_make_decor(sp))
	ais.clear()
	for f in 3:
		if f != player or bot:
			var ai = AI.new()
			ai.setup(self, f)
			ais.append(ai)
	# a few starting bodies so the opening has something on the board
	for f in 3:
		var st: Array = Data.FACTIONS[f]["starters"]
		for i in st.size():
			var u := _spawn_unit(f, st[i], Data.START_POS[f] + Vector2(cos(i * 2.1), sin(i * 2.1)) * 5.0)
			u.home = u.pos
	forest.setup(self)
	fog.setup(self)
	add_child(weather)
	weather.setup(self)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snag="):
			forest.kill_tree(int(a.trim_prefix("--snag=")))   # testing: a snag for the wind to fell
	for m in [board.terrain_mat, board.moss_mat, board.water_mat]:
		m.set_shader_parameter("fog_tex", fog.tex)
		m.set_shader_parameter("fog_on", 1.0 if fog.enabled else 0.0)
	for ah in Data.ANTHILLS:
		var mi := MeshInstance3D.new()
		mi.mesh = FungusLib.mesh("anthill")
		mi.position = _v3(ah, -0.15)
		mi.rotation.y = _rng.randf() * TAU
		add_child(mi)
	for n in forest.nests:
		for k in mini(n["cap"], 2):
			spawn_insect(n["insect"], n["pos"] + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)), n["id"])
	var sp: Vector2 = Data.START_POS[player]
	rig.set_view(atan2(sp.x, sp.y), 52.0, _v3(sp.lerp(Vector2.ZERO, 0.3)))
	rig.snap()
	emit_signal("message", "%s awakens. Spread, link, and digest." % fs[player]["name"], fs[player]["color"])


func fast_forward(sec: float, spd: float) -> void:
	_ff_left = sec
	Engine.time_scale = spd


func busy() -> bool:
	return _ff_left > 0.0


func set_speed(s: float) -> void:
	speed = clampf(s, 0.25, 8.0)
	Engine.time_scale = speed


func toggle_pause() -> void:
	paused = not paused
	myc.paused = paused


# --- spawning ------------------------------------------------------------------

func _v3(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, board.ground_y(p) + lift, p.y)


func _make_ring(e: Ent, size: float) -> void:
	var q := PlaneMesh.new()
	q.size = Vector2(size, size)
	e.ring = MeshInstance3D.new()
	e.ring.mesh = q
	e.ring.material_override = _ring_mat
	e.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c: Color = Data.faction_color(e.f)
	e.ring.set_instance_shader_parameter("team", Color(c.r, c.g, c.b, 1.0))
	e.ring.position.y = 0.12
	e.node.add_child(e.ring)


func _spawn_struct(f: int, sid: String, p: Vector2, instant := false) -> Ent:
	var d: Dictionary = Data.STRUCTURES[sid]
	var e := Ent.new()
	e.kind = STRUCT
	e.id = sid
	e.d = d
	e.f = f
	e.pos = p
	e.max_hp = d["hp"]
	e.radius = d["radius"]
	e.built = 1.0 if instant else 0.0
	e.hp = e.max_hp if instant else e.max_hp * 0.1
	e.node = Node3D.new()
	e.node.position = _v3(p)
	e.node.rotation.y = _rng.randf() * TAU
	add_child(e.node)
	e.mi = MeshInstance3D.new()
	e.mi.mesh = FungusLib.mesh(d["species"])
	var c: Color = Data.faction_color(f)
	e.mi.set_instance_shader_parameter("team", Color(c.r, c.g, c.b, 0.3))
	e.node.add_child(e.mi)
	_make_ring(e, e.radius * 2.6)
	e.rally = p + (Vector2.ZERO - p).normalized() * (e.radius + 3.0)
	match d.get("on", ""):
		"tree":
			e.tree = forest.tree_in_roots(p)
		"deposit":
			e.dep = forest.wood_near(p, 3.0)
	structs.append(e)
	_conn_dirty = true
	return e


func _spawn_unit(f: int, uid: String, p: Vector2) -> Ent:
	var d: Dictionary = Data.UNITS[uid]
	var e := Ent.new()
	e.kind = UNIT
	e.id = uid
	e.d = d
	e.f = f
	e.pos = p
	e.max_hp = d["hp"] * (1.25 if has_tech(f, "universal_veil") else 1.0)
	if d.get("thrall", false) and has_tech(f, "chitin_lysis"):
		e.max_hp *= 1.15
	e.hp = e.max_hp
	e.radius = 0.55 if not d.get("elite", false) else 0.7
	e.facing = _rng.randf() * TAU
	e.cd = _rng.randf() * 0.5
	e.think_t = _rng.randf() * 0.3
	e.node = Node3D.new()
	e.node.position = _v3(p)
	add_child(e.node)
	e.mi = MeshInstance3D.new()
	e.mi.mesh = FungusLib.mesh(d["species"])
	var c: Color = Data.faction_color(f)
	var insect: bool = f == Data.NEUTRAL
	var tint := 0.0 if insect else (0.18 if d.get("thrall", false) else 0.45)   # a thrall's own fungus shows through
	e.mi.set_instance_shader_parameter("team", Color(c.r, c.g, c.b, tint))
	e.mi.set_instance_shader_parameter("gait", (16.0 if insect else 10.0) + _rng.randf() * 3.0)
	e.node.add_child(e.mi)
	units.append(e)
	if insect:
		e.radius = 0.4
		return e
	_make_ring(e, 1.6 if not d.get("elite", false) else 2.0)
	_burst(_v3(p, 0.4), Data.faction_color(f).lightened(0.4), 16, 1.5, 0.6)
	if started and time > 1.0:
		var kind := "spawn_elite" if d.get("elite", false) else ("spawn_heavy" if d["hp"] >= 130 else "spawn_light")
		emit_signal("sound", kind, _v3(p))
	return e


func spawn_insect(uid: String, p: Vector2, nest_id: int) -> Ent:
	p.x = clampf(p.x, -Data.HALF_W + 1.0, Data.HALF_W - 1.0)
	p.y = clampf(p.y, -Data.HALF_D + 1.0, Data.HALF_D - 1.0)
	var u := _spawn_unit(Data.NEUTRAL, uid, p)
	u.nest = nest_id
	u.home = p
	u.life = u.d.get("life", INF)
	return u


func on_tree_died(i: int) -> void:
	board.bark_mats[i].set_shader_parameter("dead", 1.0)
	var t: Dictionary = forest.trees[i]
	emit_signal("message", "The %s has died and stands as a snag." % t["name"], Color(0.75, 0.62, 0.45))
	emit_signal("sound", "tree_dies", _v3(t["pos"]))


func on_tree_felled(i: int, dir: Vector2, length: float) -> void:
	board.fell_tree(i, dir, length)
	var t: Dictionary = forest.trees[i]
	_shake = maxf(_shake, 0.7)
	_burst(_v3(t["pos"] + dir * length * 0.5, 1.0), Color(0.6, 0.5, 0.35), 160, 6.0, 1.6, length * 0.3, 1.6)
	emit_signal("sound", "treefall", _v3(t["pos"] + dir * length * 0.4))
	emit_signal("message", "The %s has fallen. A new log lies across the floor." % t["name"], Color(0.8, 0.68, 0.48))


# A small fallen branch: a thin dead-wood cylinder between a and b.
func branch_node(a: Vector2, b: Vector2) -> Node3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.26
	cm.height = a.distance_to(b)
	cm.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.24, 0.18)
	mat.roughness = 0.95
	cm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var mid := (a + b) * 0.5
	add_child(mi)
	mi.look_at_from_position(_v3(mid, 0.25), _v3(b, 0.25), Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return mi


func on_deposit_gone(d: Dictionary) -> void:
	for s in structs:
		if s.alive and s.dep == d and s.f == player:
			emit_signal("message", "A Rot Bracket has eaten its wood away.", Color(0.85, 0.75, 0.5))
			return


func _link(child: Ent, parent: Ent) -> void:
	var e := Ent.new()
	e.kind = CORD
	e.f = child.f
	e.a = child
	e.b = parent
	e.pos = (child.pos + parent.pos) * 0.5
	e.length = child.pos.distance_to(parent.pos)
	e.max_hp = Data.CORD_HP * (2.0 if laces(child.f) else 1.0)
	e.hp = e.max_hp
	e.radius = 0.5
	e.grow = 0.0
	e.node = Node3D.new()
	add_child(e.node)
	e.mi = MeshInstance3D.new()
	e.mi.mesh = _cord_mesh(child.pos, parent.pos)
	e.mi.material_override = _cord_mat
	var c: Color = Data.faction_color(child.f)
	e.mi.set_instance_shader_parameter("team", Color(c.r, c.g, c.b, 1.0))
	e.mi.set_instance_shader_parameter("length_m", e.length)
	e.mi.set_instance_shader_parameter("progress", 0.0)
	e.node.add_child(e.mi)
	child.cords.append(e)
	parent.cords.append(e)
	cords.append(e)
	_conn_dirty = true


func _cord_mesh(a: Vector2, b: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ab := b - a
	var L := ab.length()
	var perp := Vector2(-ab.y, ab.x) / maxf(L, 0.001)
	var n := maxi(int(L / 0.35), 4)
	var ph := _rng.randf() * TAU
	var w1 := _rng.randf_range(-1.0, 1.0) * L * 0.08
	var w2 := _rng.randf_range(0.3, 0.7)
	var pts: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / n
		var env := sin(t * PI)
		var p := a + ab * t + perp * (env * w1 + sin(t * PI * 4.0 + ph) * w2 * env)
		pts.append(Vector3(p.x, board.ground_y(p) + 0.2, p.y))
	var segs := 6
	for i in n:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var dir := (p1 - p0).normalized()
		var u := dir.cross(Vector3.UP).normalized()
		var v := u.cross(dir)
		var r0 := 0.21 * (0.85 + 0.3 * sin(i * 1.7 + ph))
		var r1 := 0.21 * (0.85 + 0.3 * sin((i + 1) * 1.7 + ph))
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var o0 := u * cos(a0) + v * sin(a0)
			var o1 := u * cos(a1) + v * sin(a1)
			var quad := [[p0 + o0 * r0, o0, Vector2(t0, float(k) / segs)], [p0 + o1 * r0, o1, Vector2(t0, float(k + 1) / segs)],
				[p1 + o1 * r1, o1, Vector2(t1, float(k + 1) / segs)], [p0 + o0 * r0, o0, Vector2(t0, float(k) / segs)],
				[p1 + o1 * r1, o1, Vector2(t1, float(k + 1) / segs)], [p1 + o0 * r1, o0, Vector2(t1, float(k) / segs)]]
			for q in quad:
				st.set_uv(q[2])
				st.set_normal(q[1])
				st.add_vertex(q[0])
	return st.commit()


# --- faction queries -----------------------------------------------------------

func has_tech(f: int, t: String) -> bool:
	return t == "" or (f >= 0 and f < fs.size() and fs[f]["techs"].has(t))


func econ(f: int) -> String:
	return Data.FACTIONS[f]["economy"] if f >= 0 and f < 3 else ""


# The court that farms hosts, if it is still alive.
func choir() -> int:
	for f in 3:
		if econ(f) == "parasite" and fs[f]["alive"]:
			return f
	return -1


# Rhizomorph Bootlaces (Court) and Armillaria Bootlaces (Hollow) do the same to cords.
func laces(f: int) -> bool:
	return has_tech(f, "bootlaces") or has_tech(f, "armillaria")


func pop_cap(f: int) -> int:
	return 50 if has_tech(f, "brood") else Data.POP_CAP


func res(f: int) -> Array:
	return fs[f]["res"]


func afford(f: int, cost: Array, spores := 0.0) -> bool:
	var r := res(f)
	return r[0] >= cost[0] and r[1] >= cost[1] and r[2] >= spores


func pay(f: int, cost: Array, spores := 0.0) -> void:
	var r := res(f)
	r[0] -= cost[0]
	r[1] -= cost[1]
	r[2] -= spores


func spore_cap(f: int) -> float:
	return Data.SPORE_CAP * (2.0 if econ(f) == "parasite" else 1.0)


func link_range(f: int) -> float:
	return Data.BASE_LINK + (6.0 if laces(f) else 0.0)


func pop(f: int) -> int:
	var n := 0
	for u in units:
		if u.f == f and u.alive:
			n += 1
	return n


func thralls(f: int) -> int:
	var n := 0
	for u in units:
		if u.f == f and u.alive and u.d.get("thrall", false):
			n += 1
	return n


func queued(f: int) -> int:
	var n := 0
	for s in structs:
		if s.f == f and s.alive:
			n += s.queue.size()
	return n


func count_structs(f: int, sid: String, include_building := true) -> int:
	var n := 0
	for s in structs:
		if s.f == f and s.alive and s.id == sid and (include_building or s.built >= 1.0):
			n += 1
	return n


func heart(f: int) -> Ent:
	return fs[f]["heart"]


func mantles_on(tree: int, sid := "mantle") -> int:
	var n := 0
	for s in structs:
		if s.alive and s.id == sid and s.tree == tree:
			n += 1
	return n


func mantle_cap(f: int) -> int:
	return Data.MANTLES_PER_TREE + (1 if has_tech(f, "old_growth") else 0)


# The thrall a Choir structure at p would grow out of.
func host_for(f: int, p: Vector2) -> Ent:
	var best: Ent = null
	var bd := Data.HOST_RANGE
	for u in units:
		if u.f == f and u.alive and u.d.get("thrall", false) and u.burst < 0.0:
			var d := u.pos.distance_to(p)
			if d < bd:
				bd = d
				best = u
	return best


# --- placement -----------------------------------------------------------------

# Returns "" when f may place structure sid at p, otherwise the reason.
func place_error(f: int, sid: String, p: Vector2, check_cost := true) -> String:
	var d: Dictionary = Data.STRUCTURES[sid]
	var r: float = d["radius"]
	if not board.in_bounds(p, r + 1.0):
		return "Off the board"
	if d.has("req") and not has_tech(f, d["req"]):
		return "Needs %s" % Data.TECHS[d["req"]]["name"]
	if check_cost and not afford(f, d["cost"]):
		return "Not enough resources"
	if board.water_at(p) > 0.2:
		return "Too wet"
	for i in Data.TREES.size():
		var tr: Dictionary = Data.TREES[i]
		if p.distance_to(tr["pos"]) < tr["radius"] * 1.6 + r:
			return "Blocked by the trunk"
	for s in structs:
		if s.alive and p.distance_to(s.pos) < s.radius + r + 0.5:
			return "Too close to another fruiting body"
	for ah in Data.ANTHILLS:
		if p.distance_to(ah) < 2.6 + r:
			return "Blocked by an anthill"
	match d.get("on", ""):
		"tree":
			var t := forest.tree_in_roots(p)
			if t < 0:
				return "Must be in a living tree's root zone"
			if sid == "mantle" and mantles_on(t) >= mantle_cap(f):
				return "This tree already feeds %d mantles" % mantle_cap(f)
			if sid == "honey_rot" and mantles_on(t, "honey_rot") > 0:
				return "This tree is already rotting"
		"deposit":
			if forest.wood_near(p, 3.0).is_empty():
				return "Must sit on a log, snag or fallen branch"
	if econ(f) == "parasite":
		if host_for(f, p) == null:
			return "Needs a thrall within %d m to grow from" % int(Data.HOST_RANGE)
	elif _link_parents(f, p).is_empty():
		return "Out of cord reach - build closer to your network"
	return ""


func _link_parents(f: int, p: Vector2) -> Array[Ent]:
	var cands: Array[Ent] = []
	var lr := link_range(f)
	for s in structs:
		if s.f == f and s.alive and s.built >= 1.0 and s.connected and p.distance_to(s.pos) <= lr:
			cands.append(s)
	cands.sort_custom(func(x: Ent, y: Ent): return p.distance_squared_to(x.pos) < p.distance_squared_to(y.pos))
	return cands.slice(0, 2)


func try_place(f: int, sid: String, p: Vector2) -> String:
	var err := place_error(f, sid, p)
	if err != "":
		return err
	pay(f, Data.STRUCTURES[sid]["cost"])
	if econ(f) == "parasite":
		# the host dies where it stands and the fruiting body bursts out of it
		var host := host_for(f, p)
		host.alive = false
		host.dying = 0.001
		_burst(_v3(host.pos, 0.6), Data.faction_color(f).lightened(0.3), 30, 2.0, 0.8)
		_spawn_struct(f, sid, p)
	else:
		var parents := _link_parents(f, p)
		var e := _spawn_struct(f, sid, p)
		for par in parents:
			_link(e, par)
	emit_signal("sound", "place", _v3(p))
	return ""


# --- orders --------------------------------------------------------------------

func order_move(group: Array, p: Vector2, attack_move := false) -> void:
	var i := 0
	for u in group:
		if not u.alive or u.kind != UNIT:
			continue
		var off := Vector2.ZERO
		if i > 0:
			var a := i * 2.39996
			off = Vector2(cos(a), sin(a)) * 1.15 * sqrt(i)
		u.goal = p + off
		u.target = null
		u.amove = attack_move
		i += 1


func order_attack(group: Array, t: Ent) -> void:
	for u in group:
		if u.alive and u.kind == UNIT:
			u.target = t
			u.goal = Vector2.INF
			u.amove = false


func order_stop(group: Array) -> void:
	for u in group:
		if u.kind == UNIT:
			u.goal = Vector2.INF
			u.target = null
			u.amove = false
			u.home = u.pos


# Choir thralls climb to something high and burst into spores.
func order_sporulate(group: Array) -> void:
	for u in group:
		if not u.alive or u.kind != UNIT or not u.d.get("thrall", false) or econ(u.f) != "parasite":
			continue
		var q: Vector2 = forest.summit_near(u.pos, 25.0)
		u.summit = q if q != Vector2.INF else u.pos
		u.goal = u.summit
		u.target = null
		u.amove = false


func _sporulate(u: Ent) -> void:
	var f := u.f
	if _log:
		_stats["spor%d" % f] = _stats.get("spor%d" % f, 0) + 1
	var big := 1.5 if has_tech(f, "summit") else 1.0
	var high := 1.0 if forest.summit_near(u.pos, 2.5) != Vector2.INF else 0.6
	var r := res(f)
	r[2] = minf(r[2] + 20.0 * big * high, spore_cap(f))
	r[0] += 15.0 * big * high
	# insects nearby breathe the spores in
	for o in _near_units(u.pos, 6.0):
		if o.alive and o.f == Data.NEUTRAL and o.d.get("host", "") != "" and thralls(f) < pop_cap(f):
			_raise_thrall(o, f)
	for e in _enemies_in(f, u.pos, 4.0, true, true):
		_damage(e, 70.0 if big > 1.0 else 40.0, f, u)
	fog.reveal(f, u.pos, 16.0, 40.0 if big > 1.0 else 20.0)
	u.alive = false
	u.dying = 0.001
	_burst(_v3(u.pos, 1.6), Data.faction_color(f).lerp(Color(1.0, 0.6, 0.2), 0.4), 120, 5.0, 1.4, 1.0, 1.4)
	_cloud(u.pos, 3.0, Data.faction_color(f).lerp(Color(0.8, 0.7, 0.5), 0.5), 2.0, 120)
	emit_signal("sound", "sporulate", _v3(u.pos))


func set_rally(s: Ent, p: Vector2) -> void:
	s.rally = p


func queue_train(s: Ent, uid: String) -> String:
	var d: Dictionary = Data.UNITS[uid]
	if s.built < 1.0:
		return "Still growing"
	if not s.connected:
		return "Cut off from the Heart"
	if s.queue.size() >= 5:
		return "Queue full"
	if pop(s.f) + queued(s.f) >= pop_cap(s.f):
		return "Colony at its limit (%d)" % pop_cap(s.f)
	if not afford(s.f, d["cost"], d.get("spores", 0.0)):
		return "Not enough resources"
	pay(s.f, d["cost"], d.get("spores", 0.0))
	s.queue.append(uid)
	if s.queue.size() == 1:
		s.train_t = 0.0
	return ""


func cancel_train(s: Ent) -> void:
	if s.queue.is_empty():
		return
	var uid: String = s.queue.pop_back()
	var c: Array = Data.UNITS[uid]["cost"]
	res(s.f)[0] += c[0]
	res(s.f)[1] += c[1]
	res(s.f)[2] += Data.UNITS[uid].get("spores", 0.0)
	if s.queue.is_empty():
		s.train_t = 0.0


func tech_state(f: int, t: String) -> int:
	# 0 locked, 1 available, 2 researching, 3 done
	if has_tech(f, t):
		return 3
	var h := heart(f)
	if h and h.alive and h.research == t:
		return 2
	for r in Data.TECHS[t]["req"]:
		if not has_tech(f, r):
			return 0
	return 1


func start_research(f: int, t: String) -> String:
	var h := heart(f)
	if h == null or not h.alive:
		return "No Heart"
	if h.research != "":
		return "Already researching %s" % Data.TECHS[h.research]["name"]
	if tech_state(f, t) != 1:
		return "Locked" if tech_state(f, t) == 0 else "Already known"
	var td: Dictionary = Data.TECHS[t]
	if not afford(f, td["cost"], td.get("spores", 0.0)):
		return "Not enough resources"
	pay(f, td["cost"], td.get("spores", 0.0))
	h.research = t
	h.research_t = 0.0
	return ""


func ability_ready(f: int, ab: String) -> String:
	var d: Dictionary = Data.ABILITIES[ab]
	if not has_tech(f, d["tech"]):
		return "Needs %s" % Data.TECHS[d["tech"]]["name"]
	var cdl: float = fs[f]["cds"].get(ab, 0.0)
	if cdl > 0.0:
		return "Recharging %ds" % ceili(cdl)
	if res(f)[2] < d["cost"]:
		return "Needs %d spores" % d["cost"]
	return ""


func cast_error(f: int, ab: String, p: Vector2) -> String:
	var err := ability_ready(f, ab)
	if err != "":
		return err
	if not board.in_bounds(p, 0.0):
		return "Off the board"
	if f == player and not fog.seen(f, p):
		return "You have never seen that ground"
	if ab == "borer_swarm" and _swarm_tree(p) < 0:
		return "Cast it on a living tree"
	for e in units:
		if e.f == f and e.alive and e.pos.distance_to(p) < Data.CAST_RANGE:
			return ""
	for e in structs:
		if e.f == f and e.alive and e.pos.distance_to(p) < Data.CAST_RANGE:
			return ""
	return "Too far from your colony"


func cast(f: int, ab: String, p: Vector2) -> String:
	var err := cast_error(f, ab, p)
	if err != "":
		return err
	var d: Dictionary = Data.ABILITIES[ab]
	if _log:
		_stats["cast_" + ab] = _stats.get("cast_" + ab, 0) + 1
	res(f)[2] -= d["cost"]
	fs[f]["cds"][ab] = d["cd"]
	emit_signal("sound", "puffball_grow" if ab == "giant_puffball" else ab, _v3(p))
	var r: float = d["radius"]
	var col := Data.faction_color(f)
	match ab:
		"haze":
			zones.append({"kind": ab, "f": f, "p": p, "r": r, "t": 0.0, "dur": 4.0})
			_cloud(p, r, col.lerp(Color(0.6, 1.0, 0.3), 0.5), 4.0, 260)
		"fairy_ring":
			for e in _enemies_in(f, p, r, true, false):
				_damage(e, 45.0, f, null)
			zones.append({"kind": ab, "f": f, "p": p, "r": r, "t": 0.0, "dur": 20.0, "props": _ring_of(p, r * 0.85, "agaric_button", 26)})
			_burst(_v3(p, 0.5), col.lightened(0.3), 90, 4.0, 1.2, r)
		"bloom":
			zones.append({"kind": ab, "f": f, "p": p, "r": r, "t": 0.0, "dur": 1.5, "props": _ring_of(p, r * 0.5, "death_cap", 5, 0.35)})
		"volley":
			for e in _enemies_in(f, p, r, true, true):
				_damage(e, 48.0, f, null)
			_burst(_v3(p, 0.6), Color(1.0, 0.85, 0.45), 160, 7.0, 0.9, r * 0.6)
			_shake = maxf(_shake, 0.35)
		"zombify":
			var n := 0
			for e in _enemies_in(f, p, r, true, false):
				if n >= 4 or e.d.get("elite", false) or e.d.get("thrall", false) or e.d.get("host", "x") == "":
					continue
				_raise_thrall(e, f)
				n += 1
			_burst(_v3(p, 0.5), Color(1.0, 0.5, 0.1), 80, 3.0, 1.0, r * 0.7)
		"wildfire":
			zones.append({"kind": ab, "f": f, "p": p, "r": r, "t": 0.0, "dur": 26.5})
			for e in _enemies_in(f, p, r, true, true):
				_damage(e, 70.0 if e.kind == UNIT else 140.0, f, null)
			_flames(p, r)
			_shake = maxf(_shake, 0.6)
		"lure":
			zones.append({"kind": ab, "f": f, "p": p, "r": r, "t": 0.0, "dur": 4.0})
			_cloud(p, r, Color(0.55, 0.45, 0.25), 4.0, 160)
		"barrage":
			zones.append({"kind": ab, "f": f, "p": p, "r": r, "t": 0.0, "dur": 3.0, "next": 0.0})
		"borer_swarm":
			var t: Dictionary = forest.trees[_swarm_tree(p)]
			var edge: float = t["radius"] * 1.6 + 0.9
			for i in 7:
				var a := TAU * i / 7.0 + _rng.randf() * 0.4
				var q: Vector2 = t["pos"] + Vector2(cos(a), sin(a)) * edge
				var b := spawn_insect("borer", q + Vector2(cos(a), sin(a)) * 3.0, 0)
				b.home = q
				b.goal = q
			_burst(_v3(t["pos"], 2.0), Color(0.2, 0.8, 0.35), 90, 4.0, 1.2, t["radius"] * 1.6)
		"pandemic":
			zones.append({"kind": ab, "f": f, "p": p, "r": r, "t": 0.0, "dur": 15.0})
			_cloud(p, r, Color(1.0, 0.5, 0.12), 15.0, 220)
		"giant_puffball":
			var e := Ent.new()
			e.kind = PUFF
			e.id = "giant_puffball"
			e.f = f
			e.pos = p
			e.max_hp = 450.0
			e.hp = e.max_hp
			e.radius = 3.0
			e.d = {"name": "Giant Puffball"}
			e.node = Node3D.new()
			e.node.position = _v3(p)
			add_child(e.node)
			e.mi = MeshInstance3D.new()
			e.mi.mesh = FungusLib.mesh("giant_puffball")
			e.node.add_child(e.mi)
			e.node.scale = Vector3.ONE * 0.1
			_make_ring(e, r * 2.0)
			puffs.append(e)
	return ""


# --- selection & picking -------------------------------------------------------

# Where the most units are currently fighting (for automated screenshots).
func hotspot() -> Vector2:
	var best := Vector2.ZERO
	var bn := -1
	for u in units:
		if not u.alive or u.target == null or u.f == Data.NEUTRAL or u.target.f == Data.NEUTRAL:
			continue
		var n := _near_units(u.pos, 8.0).size()
		if n > bn:
			bn = n
			best = u.pos
	return best


func ground_hit(screen: Vector2) -> Vector3:
	var cam: Camera3D = rig.cam
	var o := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var t := 0.0
	var prev_t := 0.0
	for i in 300:
		var p := o + dir * t
		var h: float = p.y - board.ground_y(Vector2(p.x, p.z))
		if h < 0.0:
			var lo := prev_t
			var hi := t
			for k in 12:
				var mid := (lo + hi) * 0.5
				var q := o + dir * mid
				if q.y - board.ground_y(Vector2(q.x, q.z)) < 0.0:
					hi = mid
				else:
					lo = mid
			return o + dir * hi
		prev_t = t
		t += clampf(h * 0.6, 0.05, 4.0)
		if t > 900.0:
			break
	return Vector3.INF


func screen_pos(e: Ent) -> Vector2:
	return rig.cam.unproject_position(e.node.global_position + Vector3(0, 0.6, 0))


func pick(screen: Vector2) -> Ent:
	var cam: Camera3D = rig.cam
	var best: Ent = null
	var bd := 1e9
	for list in [units, structs, puffs]:
		for e in list:
			if not e.alive or not e.node.visible or cam.is_position_behind(e.node.global_position):
				continue
			var sp := screen_pos(e)
			var px := _px_radius(e)
			var dd := sp.distance_to(screen)
			if dd < px and dd < bd:
				bd = dd
				best = e
	if best:
		return best
	var g := ground_hit(screen)
	if g == Vector3.INF:
		return null
	var gp := Vector2(g.x, g.z)
	for c in cords:
		if c.alive and c.node.visible and c.regrow <= 0.0 and _seg_dist(gp, c.a.pos, c.b.pos) < 0.8:
			return c
	return null


func _px_radius(e: Ent) -> float:
	var cam: Camera3D = rig.cam
	var d := cam.global_position.distance_to(e.node.global_position)
	var px_per_m := get_viewport().get_visible_rect().size.y / (2.0 * d * tan(deg_to_rad(cam.fov * 0.5)))
	return maxf(e.radius * px_per_m * 1.1, 12.0)


func units_in_rect(r: Rect2, f: int) -> Array[Ent]:
	var out: Array[Ent] = []
	for u in units:
		if u.alive and u.f == f and not rig.cam.is_position_behind(u.node.global_position) and r.has_point(screen_pos(u)):
			out.append(u)
	return out


func select(list: Array, add := false) -> void:
	if not add:
		for e in selected:
			e.selected = false
		selected.clear()
	for e in list:
		if e and e.alive and not e in selected:
			e.selected = true
			selected.append(e)


func select_same_type(e: Ent) -> void:
	var out: Array[Ent] = []
	for u in units:
		if u.alive and u.f == e.f and u.id == e.id and not rig.cam.is_position_behind(u.node.global_position):
			var sp := screen_pos(u)
			if get_viewport().get_visible_rect().has_point(sp):
				out.append(u)
	select(out)


# --- main loop -----------------------------------------------------------------

func _process(delta: float) -> void:
	if not started:
		return
	if _ff_left > 0.0:
		_ff_left -= delta
		if _ff_left <= 0.0:
			Engine.time_scale = speed
	if not paused and not over:
		var steps := maxi(1, ceili(delta / 0.05))
		var dt := minf(delta / steps, 0.05)
		for s in steps:
			_step(dt)
	_push_sources()
	_update_visuals(delta)


func _step(dt: float) -> void:
	time += dt
	if _conn_dirty:
		_recompute_connectivity()
	_econ_t -= dt
	if _econ_t <= 0.0:
		_econ_t = 0.5
		_update_rates()
	for f in 3:
		var r := res(f)
		var rate: Array = fs[f]["rate"]
		r[0] = maxf(r[0] + rate[0] * dt, 0.0)
		r[1] += rate[1] * dt
		r[2] = minf(r[2] + rate[2] * dt, spore_cap(f))
		var cds: Dictionary = fs[f]["cds"]
		for k in cds:
			cds[k] = maxf(cds[k] - dt, 0.0)
	_rebuild_grid()
	for s in structs:
		if s.alive:
			_update_struct(s, dt)
	for u in units:
		if u.alive:
			_update_unit(u, dt)
	for c in cords:
		if c.alive:
			_update_cord(c, dt)
	for p in puffs:
		if p.alive:
			_update_puff(p, dt)
	_update_zones(dt)
	_update_shots(dt)
	forest.tick(dt)
	fog.tick(dt)
	weather.tick(dt)
	for f in 3:
		if econ(f) == "parasite":
			res(f)[1] = thralls(f)
	for ai in ais:
		ai.tick(dt)
	_cleanup(dt)
	_decor_t -= dt
	if _decor_t <= 0.0:
		_decor_t = 0.4
		_update_decor()
	_check_end()
	if _log:
		_log_t -= dt
		if _log_t <= 0.0:
			_log_t = 20.0
			for f in 3:
				var r := res(f)
				var rate: Array = fs[f]["rate"]
				print("t=%d f%d alive=%s res=%d/%d/%d rate=%.1f/%.1f/%.1f structs=%d units=%d techs=%s" % [time, f, fs[f]["alive"],
					r[0], r[1], r[2], rate[0], rate[1], rate[2], structs.filter(func(e): return e.f == f and e.alive).size(), pop(f), fs[f]["techs"].keys()])
			print("   stats ", _stats)
			print("   cords: %d, busiest %.2f, over capacity %d" % [cords.size(), cords.reduce(func(m, c): return maxf(m, c.load), 0.0), cords.filter(func(c): return c.load > 1.0).size()])
			print("   forest: insects=%d deposits=%d humus=%d vigor=%s" % [pop(Data.NEUTRAL), forest.deposits.size(), forest.humus.size(),
				forest.trees.map(func(t): return snappedf(t["vigor"], 0.01) if t["alive"] else -1.0)])


func _rebuild_grid() -> void:
	_grid.clear()
	for u in units:
		if u.alive:
			var k := Vector2i(floori(u.pos.x / 4.0), floori(u.pos.y / 4.0))
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(u)


func _near_units(p: Vector2, r: float) -> Array:
	var out := []
	var r4 := ceili(r / 4.0)
	var c := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	for j in range(-r4, r4 + 1):
		for i in range(-r4, r4 + 1):
			var k := c + Vector2i(i, j)
			if _grid.has(k):
				for u in _grid[k]:
					if u.pos.distance_to(p) <= r:
						out.append(u)
	return out


# --- economy -------------------------------------------------------------------

func _update_rates() -> void:
	# bare soil: the Court digests minerals from it, the Hollow a little cellulose, the Choir nothing
	var soil := [0.0, 0.0, 0.0]
	if myc.ok and not myc.coarse.is_empty():
		var cz: PackedFloat32Array = myc.coarse
		var n := Data.COARSE_W * Data.COARSE_H
		for i in n:
			var o := i * 4
			var nu := cz[o + 3]
			soil[0] += cz[o] * nu
			soil[1] += cz[o + 1] * nu
			soil[2] += cz[o + 2] * nu
		for f in 3:
			soil[f] *= Data.NUTRIENT_RATE
	else:
		# no GPU (headless): estimate from each structure's reach
		for s in structs:
			if s.alive and s.connected and s.built >= 1.0:
				soil[s.f] += PI * pow(s.d["myc"], 2.0) * 0.45 * Data.NUTRIENT_RATE
	var add := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for f in 3:
		match econ(f):
			"mycorrhizal":
				add[f][0] += soil[f]
			"saprotroph":
				add[f][0] += soil[f] * Data.SOIL_SHARE * (1.35 if has_tech(f, "exoenzymes") else 1.0)
	for s in structs:
		if s.alive and s.connected and s.built >= 1.0:
			add[s.f][2] += s.d.get("spores", 0.0)
			add[s.f][0] += s.d.get("income", 0.0)
	flows.clear()
	forest.rates(add)
	_route_flows(add)
	for f in 3:
		if not fs[f]["alive"]:
			fs[f]["rate"] = [0.0, 0.0, 0.0]
			continue
		fs[f]["rate"] = add[f]
		if econ(f) == "parasite":
			fs[f]["rate"][1] = 0.0
		myc.growth[f] = (1.25 if has_tech(f, "exoenzymes") else 1.0) * weather.growth_mult()


# Carry each structure's income home along the cord tree: the shortest path to the
# Heart, losing HOP_LOSS at every hop, and no cord carrying more than its capacity.
func _route_flows(add: Array) -> void:
	for c in cords:
		c.load = 0.0
	for f in 3:
		var h := heart(f)
		if h == null or not h.alive or econ(f) == "parasite":
			continue
		var parent := {h: null}
		var queue: Array[Ent] = [h]
		while not queue.is_empty():
			var s: Ent = queue.pop_front()
			for c in s.cords:
				if not c.alive or c.regrow > 0.0 or c.grow < 1.0:
					continue
				var o: Ent = c.a if c.b == s else c.b
				if o.alive and not parent.has(o) and (o.built >= 1.0 or o == h):
					parent[o] = [s, c]
					queue.append(o)
		var cap := Data.CORD_CAP * (2.0 if laces(f) else 1.0)
		var load := {}
		var routed := []
		for fl in flows:
			var src: Ent = fl[0]
			if src.f != f or not parent.has(src):
				continue
			var path := []
			var e := src
			while e != h:
				path.append(parent[e][1])
				e = parent[e][0]
			var amt: float = fl[2] * pow(1.0 - Data.HOP_LOSS, path.size())
			for c in path:
				load[c] = load.get(c, 0.0) + amt
			routed.append([fl[1], amt, path])
		for r in routed:
			var k := 1.0
			for c in r[2]:
				k = minf(k, cap / maxf(load[c], cap))
			add[f][r[0]] += r[1] * k
		for c in load:
			c.load = load[c] / cap


func _recompute_connectivity() -> void:
	_conn_dirty = false
	var was := {}
	for s in structs:
		was[s] = s.connected
		s.connected = false
	for f in 3:
		var h := heart(f)
		if h == null or not h.alive:
			continue
		if econ(f) == "parasite":
			for s in structs:
				if s.f == f and s.alive:
					s.connected = true
			continue
		var stack: Array[Ent] = [h]
		h.connected = true
		while not stack.is_empty():
			var s: Ent = stack.pop_back()
			if s.built < 1.0 and s != h:
				continue
			for c in s.cords:
				if not c.alive or c.regrow > 0.0 or c.grow < 1.0:
					continue
				var o: Ent = c.a if c.b == s else c.b
				if o.alive and not o.connected:
					o.connected = true
					stack.append(o)
	# structures still growing their first cord count as linked, so they can finish
	for s in structs:
		if s.alive and not s.connected and s.built < 1.0:
			for c in s.cords:
				var o: Ent = c.a if c.b == s else c.b
				if c.alive and c.regrow <= 0.0 and o.connected:
					s.connected = true
		if s.alive and was.get(s, true) and not s.connected and s.f == player and s.built >= 1.0:
			emit_signal("message", "%s is cut off and starving!" % s.d["name"], Color(1.0, 0.5, 0.35))
			emit_signal("sound", "cut_off_alert", Vector3.INF)


# --- structures ----------------------------------------------------------------

func _update_struct(s: Ent, dt: float) -> void:
	var d := s.d
	if s.built < 1.0:
		if s.connected:
			var bt: float = d.get("build", 10.0) / weather.build_mult()
			s.built = minf(s.built + dt / bt, 1.0)
			s.hp = minf(s.hp + s.max_hp * 0.9 * dt / bt, s.max_hp)
			if s.built >= 1.0:
				_conn_dirty = true
				_burst(_v3(s.pos, 1.0), Data.faction_color(s.f).lightened(0.5), 40, 3.0, 1.0, s.radius)
				emit_signal("sound", "fruited", _v3(s.pos))
				if s.f == player:
					emit_signal("message", "%s has fruited." % d["name"], Data.faction_color(s.f))
		return
	if not s.connected:
		_damage(s, s.max_hp * Data.STARVE_DPS * dt, -1, null, true)
		return
	if has_tech(s.f, "pyrophilous") and s.hp < s.max_hp:
		s.hp = minf(s.hp + 3.0 * dt, s.max_hp)
	_tick_status(s, dt)
	if d.has("brood"):
		for u in _near_units(s.pos, d["brood"]):
			if u.f == s.f and u.alive and u.hp < u.max_hp:
				u.hp = minf(u.hp + 3.0 * dt, u.max_hp)
	# training
	if not s.queue.is_empty():
		var uid: String = s.queue[0]
		s.train_t += dt * weather.build_mult()
		if s.train_t >= Data.UNITS[uid]["train"]:
			s.queue.pop_front()
			s.train_t = 0.0
			var dir := (s.rally - s.pos).normalized() if s.rally != Vector2.INF else Vector2.RIGHT
			var u := _spawn_unit(s.f, uid, s.pos + dir * (s.radius + 0.8))
			if _log:
				_stats["trained%d" % s.f] = _stats.get("trained%d" % s.f, 0) + 1
			u.goal = s.rally
			u.home = s.rally
	# research
	if s.research != "":
		s.research_t += dt
		var td: Dictionary = Data.TECHS[s.research]
		if s.research_t >= td["time"]:
			_finish_tech(s.f, s.research)
			s.research = ""
			s.research_t = 0.0
	# towers
	if d.has("attack"):
		s.cd -= dt
		var at: Dictionary = d["attack"]
		if s.cd <= 0.0:
			var t := _find_target(s, at["range"], false)
			if t:
				s.cd = at["cd"]
				_fire(s, t, at)


func _finish_tech(f: int, t: String) -> void:
	fs[f]["techs"][t] = true
	if t == "universal_veil":
		for u in units:
			if u.f == f and u.alive:
				u.max_hp *= 1.25
				u.hp *= 1.25
	if t == "bootlaces" or t == "armillaria":
		for c in cords:
			if c.f == f:
				c.max_hp *= 2.0
				c.hp *= 2.0
	if t == "chitin_lysis":
		for u in units:
			if u.f == f and u.alive and u.d.get("thrall", false):
				u.max_hp *= 1.15
				u.hp *= 1.15
	if f == player:
		emit_signal("message", "Researched %s." % Data.TECHS[t]["name"], Color(0.95, 0.9, 0.6))
		emit_signal("sound", "research_done", Vector3.INF)


func _update_cord(c: Ent, dt: float) -> void:
	if not c.a.alive or not c.b.alive:
		c.alive = false
		_conn_dirty = true
		return
	if c.regrow > 0.0:
		c.regrow -= dt * (2.0 if laces(c.f) else 1.0)
		if c.regrow <= 0.0:
			c.regrow = 0.0
			c.hp = c.max_hp
			c.grow = 0.0
			emit_signal("sound", "cord_regrow", _v3(c.pos))
		return
	if c.grow < 1.0:
		c.grow = minf(c.grow + dt / maxf(c.length / 8.0, 0.6), 1.0)
		if c.grow >= 1.0:
			_conn_dirty = true


func _update_puff(p: Ent, dt: float) -> void:
	p.timer += dt
	p.node.scale = Vector3.ONE * lerpf(0.1, 1.0, smoothstep(0.0, 6.0, p.timer))
	if p.timer >= 6.0:
		_puff_burst(p, 1.0)


func _puff_burst(p: Ent, mult: float) -> void:
	p.alive = false
	var r: float = Data.ABILITIES["giant_puffball"]["radius"]
	for e in _enemies_in(p.f, p.pos, r, true, true):
		_damage(e, 320.0 * mult, p.f, null)
	_burst(_v3(p.pos, 2.0), Color(0.85, 0.75, 0.55), 400, 9.0, 2.2, r * 0.5, 3.0)
	emit_signal("sound", "puffball_burst", _v3(p.pos))
	_cloud(p.pos, r, Color(0.7, 0.62, 0.45), 3.0, 300)
	_shake = maxf(_shake, 1.0)


# --- units ---------------------------------------------------------------------

func _unit_speed(u: Ent) -> float:
	var s: float = u.d["speed"]
	if laces(u.f) and myc.density(u.f, u.pos) > 0.3:
		s *= 1.15
	if board.water_at(u.pos) > 0.3 and not u.d.get("flies", false):
		s *= 0.6
	s *= 1.0 - u.slow
	return s


func _tick_status(e: Ent, dt: float) -> void:
	if e.poison_t > 0.0:
		e.poison_t -= dt
		_damage(e, e.poison_dps * dt, -1, null, true)
	if e.slow_t > 0.0:
		e.slow_t -= dt
		if e.slow_t <= 0.0:
			e.slow = 0.0


func _update_unit(u: Ent, dt: float) -> void:
	var d := u.d
	_tick_status(u, dt)
	if not u.alive:
		return
	if d.has("regen") and u.hp < u.max_hp:
		u.hp = minf(u.hp + d["regen"] * dt, u.max_hp)
	if d.get("thrall", false):
		_thrall_decay(u, dt)
		if not u.alive:
			return
	if u.burst >= 0.0:
		# clinging to the summit, swelling with spores
		u.burst += dt
		u.vel = u.vel.lerp(Vector2.ZERO, 1.0 - exp(-dt * 10.0))
		u.walk = 0.0
		u.node.scale = Vector3.ONE * (1.0 + u.burst * 0.12)
		if u.burst >= 3.0:
			_sporulate(u)
		return
	if u.summit != Vector2.INF:
		u.target = null
		if u.pos.distance_to(u.summit) < 1.6:
			u.burst = 0.0
			u.goal = Vector2.INF
			return
		u.goal = u.summit
	if u.f == Data.NEUTRAL:
		_insect_think(u, dt)
	elif d.get("bores", false) and u.target == null:
		_bore(u, dt)
	u.cd -= dt
	if u.target and (not u.target.alive or (u.target.kind == CORD and u.target.regrow > 0.0)):
		u.target = null
	# look for trouble
	u.think_t -= dt
	if u.think_t <= 0.0:
		u.think_t = 0.3
		if u.target == null and (u.goal == Vector2.INF or u.amove) and u.f != Data.NEUTRAL and u.summit == Vector2.INF:
			var t := _find_target(u, Data.AGGRO + d["range"] * 0.5, true)
			if t:
				u.target = t
		elif u.target and u.goal == Vector2.INF and u.home != Vector2.INF and u.pos.distance_to(u.home) > 22.0 and not u.amove:
			# leashed: an idle defender drifts back after a long chase
			u.target = null
			u.goal = u.home
	var desired := Vector2.ZERO
	var spd := _unit_speed(u)
	if u.target:
		var t := u.target
		var reach: float = d["range"] + u.radius + (t.radius if t.kind != CORD else 0.2)
		var dist := _dist_to(u, t)
		var aim := _aim_point(u, t)
		if dist <= reach:
			u.facing = lerp_angle(u.facing, atan2(aim.y - u.pos.y, aim.x - u.pos.x), 1.0 - exp(-dt * 12.0))
			if u.cd <= 0.0:
				u.cd = d["cd"]
				_fire(u, t, d)
		else:
			desired = (aim - u.pos).normalized()
	elif u.goal != Vector2.INF:
		var to := u.goal - u.pos
		if to.length() < 0.5:
			u.goal = Vector2.INF
			u.amove = false
			u.home = u.pos
		else:
			desired = to.normalized() * clampf(to.length() / 1.5, 0.2, 1.0)
	# separation and obstacles
	var push := Vector2.ZERO
	for o in _near_units(u.pos, 2.0):
		if o == u:
			continue
		var dv: Vector2 = u.pos - o.pos
		var dl := dv.length()
		var md: float = u.radius + o.radius
		if dl < md and dl > 0.001:
			push += dv / dl * (md - dl) * (3.0 if o.f == u.f else 5.0)
		elif dl <= 0.001:
			push += Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5)
	for s in structs:
		if s.alive and s != u.target:
			var dv := u.pos - s.pos
			var md := s.radius + u.radius * 0.6
			if dv.length() < md:
				push += dv.normalized() * (md - dv.length()) * 8.0
	for tr in Data.TREES:
		var dv: Vector2 = u.pos - tr["pos"]
		var md: float = tr["radius"] * 1.5 + u.radius
		if dv.length() < md + 1.5:
			push += dv.normalized() * (md + 1.5 - dv.length()) * 4.0
			# slide around the trunk instead of pushing straight into it
			if desired != Vector2.ZERO and desired.dot(-dv.normalized()) > 0.3:
				desired = (desired + Vector2(-dv.y, dv.x).normalized() * signf(desired.cross(dv) + 0.001) * -1.0).normalized()
	var want := desired * spd + push
	u.vel = u.vel.lerp(want, 1.0 - exp(-dt * 10.0))
	u.pos += u.vel * dt
	u.pos.x = clampf(u.pos.x, -Data.HALF_W + 0.6, Data.HALF_W - 0.6)
	u.pos.y = clampf(u.pos.y, -Data.HALF_D + 0.6, Data.HALF_D - 0.6)
	var sp := u.vel.length()
	if sp > 0.4 and desired != Vector2.ZERO:
		u.facing = lerp_angle(u.facing, atan2(u.vel.y, u.vel.x), 1.0 - exp(-dt * 10.0))
	u.walk = lerpf(u.walk, clampf(sp / maxf(spd, 0.1), 0.0, 1.0), 1.0 - exp(-dt * 8.0))


func _dist_to(u: Ent, t: Ent) -> float:
	if t.kind == CORD:
		return _seg_dist(u.pos, t.a.pos, t.b.pos)
	return u.pos.distance_to(t.pos) - t.radius


func _aim_point(u: Ent, t: Ent) -> Vector2:
	if t.kind == CORD:
		var ab := t.b.pos - t.a.pos
		var k := clampf((u.pos - t.a.pos).dot(ab) / ab.length_squared(), 0.1, 0.9)
		return t.a.pos + ab * k
	return t.pos


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var k := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * k)


# Picks something to hit: units first, then towers, then structures, then cords.
# Cord-cutters (lures, angels) go for cords first.
func _find_target(e: Ent, r: float, include_cords: bool) -> Ent:
	var best: Ent = null
	var bs := INF
	for o in _near_units(e.pos, r + 1.0):
		if o.f != e.f and o.alive and (o.f != Data.NEUTRAL or _hunts(e, o)):
			var dd: float = e.pos.distance_to(o.pos)
			if dd < bs:
				bs = dd
				best = o
	var cutter: bool = e.d.get("cutter", false)
	if best and not cutter:
		return best
	var unit_pick := best
	best = null
	bs = INF
	for s in structs:
		if s.f != e.f and s.alive:
			var dd: float = e.pos.distance_to(s.pos) - s.radius
			if dd < r:
				var sc := dd - (6.0 if s.d.has("attack") else 0.0)
				if sc < bs:
					bs = sc
					best = s
	for p in puffs:
		if p.f != e.f and p.alive and e.pos.distance_to(p.pos) - p.radius < r:
			return p
	if include_cords and e.kind == UNIT:
		for c in cords:
			if c.f != e.f and c.alive and c.regrow <= 0.0 and c.grow >= 1.0:
				var dd := _seg_dist(e.pos, c.a.pos, c.b.pos)
				if dd < r and (cutter or best == null):
					return c
	if cutter and unit_pick:
		return unit_pick
	return best if best else unit_pick


# --- combat --------------------------------------------------------------------

# Who bothers with insects: the Choir hunts them, the Court culls pests on its trees.
func _hunts(e: Ent, o: Ent) -> bool:
	match econ(e.f):
		"parasite":
			return o.d.get("host", "") != "" or e.kind == STRUCT
		"mycorrhizal":
			var t: int = forest.tree_in_roots(o.pos)
			return t >= 0 and forest.trees[t]["fed"][e.f] > 0
	return false


func _fire(src: Ent, t: Ent, d: Dictionary) -> void:
	var shot: String = d.get("shot", "")
	var dmg: float = d["dmg"]
	if d.get("vigor", false):
		dmg *= 0.8 + 1.0 * forest.vigor(src.tree)
	if shot == "":
		_damage(t, dmg, src.f, src, false, d)
		var hp3 := _v3(_aim_point(src, t), 0.5)
		emit_signal("sound", "hit_" + src.id if src.kind == UNIT else "hit_melee", hp3)
		_burst(hp3, Data.faction_color(src.f).lightened(0.3), 6, 1.5, 0.35)
		return
	var from := src.node.global_position + Vector3(0, FungusLib.height_of(src.d["species"]) * (0.7 if src.kind == UNIT else 0.8), 0)
	var to := _aim_point(src, t)
	var arc: bool = d.get("arc", false)
	var spd := 25.0 if src.id == "sniper" else 16.0
	emit_signal("sound", "tower_fire" if src.kind == STRUCT and shot == "puff" else {"spit": "spit_fire", "puff": "puff_fire"}.get(shot, "lob_fire"), from)
	shots.append({
		"from": from, "to": to, "target": null if arc else t, "t": 0.0,
		"dur": maxf(from.distance_to(_v3(to)) / spd, 0.15) * (1.4 if arc else 1.0),
		"arc": arc, "dmg": dmg, "f": src.f, "src": src, "d": d, "shot": shot,
		"node": _shot_node(shot, src.f),
	})


func _shot_node(shot: String, f: int) -> MeshInstance3D:
	var key := "%s%d" % [shot, f]
	if not _shot_mats.has(key):
		var m := StandardMaterial3D.new()
		var c: Color
		match shot:
			"spit": c = Data.faction_color(f).lerp(Color(0.7, 1.0, 0.3), 0.35)
			"puff": c = Color(0.85, 0.75, 0.55)
			_: c = Color(0.25, 0.22, 0.2)
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5 if shot != "egg" else 0.2
		_shot_mats[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _shot_mesh
	mi.material_override = _shot_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shot == "puff":
		mi.scale = Vector3.ONE * 1.5
	add_child(mi)
	return mi


func _update_shots(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for s in shots:
		s["t"] += dt
		var t: Ent = s["target"]
		if t and t.alive:
			s["to"] = _aim_point(s["src"], t) if s["src"].alive else t.pos
		var k := clampf(s["t"] / s["dur"], 0.0, 1.0)
		var to3 := _v3(s["to"], 0.5)
		var from: Vector3 = s["from"]
		var p := from.lerp(to3, k)
		if s["arc"]:
			p.y += sin(k * PI) * maxf(from.distance_to(to3) * 0.35, 2.0)
		var node: MeshInstance3D = s["node"]
		node.position = p
		if k >= 1.0:
			node.queue_free()
			_impact(s)
		else:
			keep.append(s)
	shots = keep


func _impact(s: Dictionary) -> void:
	var d: Dictionary = s["d"]
	var f: int = s["f"]
	var p: Vector2 = s["to"]
	var splash: float = d.get("splash", 0.0)
	var src: Ent = s["src"] if s["src"].alive else null
	var col := Data.faction_color(f).lightened(0.3)
	if s["shot"] == "puff":
		col = Color(0.9, 0.8, 0.6)
	emit_signal("sound", {"spit": "spit_impact", "puff": "puff_impact"}.get(s["shot"], "lob_impact"), _v3(p))
	if splash > 0.0:
		for e in _enemies_in(f, p, splash, true, true):
			_damage(e, s["dmg"], f, src, false, d)
		_burst(_v3(p, 0.4), col, 40, 3.0, 0.7, splash * 0.5)
	else:
		var t: Ent = s["target"]
		if t and t.alive:
			_damage(t, s["dmg"], f, src, false, d)
		_burst(_v3(p, 0.5), col, 10, 2.0, 0.4)


func _enemies_in(f: int, p: Vector2, r: float, inc_units: bool, inc_structs: bool) -> Array[Ent]:
	var out: Array[Ent] = []
	if inc_units:
		for u in _near_units(p, r + 0.6):
			if u.f != f and u.alive:
				out.append(u)
	if inc_structs:
		for s in structs:
			if s.f != f and s.alive and s.pos.distance_to(p) < r + s.radius:
				out.append(s)
		for c in cords:
			if c.f != f and c.alive and c.regrow <= 0.0 and _seg_dist(p, c.a.pos, c.b.pos) < r:
				out.append(c)
		for pf in puffs:
			if pf.f != f and pf.alive and pf.pos.distance_to(p) < r + pf.radius:
				out.append(pf)
	return out


func _damage(e: Ent, amt: float, src_f: int, src: Ent, quiet := false, d := {}) -> void:
	if not e.alive or amt <= 0.0:
		return
	if e.d.has("armor") and d.get("shot", "") != "":
		amt *= 1.0 - e.d["armor"]
	e.hp -= amt
	if not quiet:
		e.flash = 1.0
		if d.has("poison"):
			var pz: float = d["poison"] * (1.5 if has_tech(src_f, "muscarine") else 1.0)
			e.poison_dps = maxf(e.poison_dps if e.poison_t > 0.0 else 0.0, pz)
			e.poison_t = 3.0
		if d.has("slow"):
			e.slow = d["slow"]
			e.slow_t = d.get("slow_t", 2.0)
		# being hit wakes idle units up
		if e.kind == UNIT and src and src.alive and e.target == null and e.goal == Vector2.INF:
			e.target = src
	if e.hp > 0.0:
		return
	match e.kind:
		CORD:
			e.hp = 0.0
			e.regrow = Data.CORD_REGROW
			_conn_dirty = true
			_burst(_v3(e.pos, 0.3), Color(1.0, 0.75, 0.3), 30, 3.0, 0.6)
			emit_signal("sound", "cord_severed", _v3(e.pos))
			if e.f == player:
				emit_signal("message", "A supply cord was severed!", Color(1.0, 0.55, 0.3))
		PUFF:
			_puff_burst(e, 0.5)
		_:
			_kill(e, src)


func _kill(e: Ent, killer: Ent) -> void:
	if _log:
		var key := "%s%d<-%s" % ["u" if e.kind == UNIT else "s", e.f, ("f%d" % killer.f) if killer else "env"]
		_stats[key] = _stats.get(key, 0) + 1
	e.alive = false
	e.dying = 0.001
	var col := Data.faction_color(e.f)
	if e.kind == UNIT:
		_burst(_v3(e.pos, 0.5), col.lerp(Color(0.9, 0.85, 0.7), 0.5), 30 if e.f != Data.NEUTRAL else 10, 3.5, 0.8)
		if e.f != Data.NEUTRAL:
			emit_signal("sound", "unit_death", _v3(e.pos))
		var ch := _infector(e, killer)
		if ch >= 0 and e.d.get("host", "x") == "":
			res(ch)[2] = minf(res(ch)[2] + 4.0, spore_cap(ch))   # too small to ride: just spores
		elif ch >= 0 and thralls(ch) < pop_cap(ch):
			_raise_thrall(e, ch)
		elif ch >= 0:
			res(ch)[0] += 6.0
		else:
			e.corpse = true
			forest.add_corpse(e)
	else:
		_burst(_v3(e.pos, 1.0), col.lerp(Color(0.8, 0.75, 0.6), 0.5), 120, 5.0, 1.4, e.radius)
		emit_signal("sound", "heart_death" if e.d.has("research") else "struct_death", _v3(e.pos))
		_shake = maxf(_shake, 0.5 if e.d.has("research") else 0.25)
		_conn_dirty = true
		forest.add_rubble(e.pos)
		for c in e.cords:
			c.alive = false
		if _log:
			print("t=%d %s of f%d destroyed by %s" % [time, e.id, e.f, ("f%d %s" % [killer.f, killer.id]) if killer else "?"])
		if e.d.has("research"):
			_faction_falls(e.f)
		elif e.f == player:
			emit_signal("message", "%s was destroyed." % e.d["name"], Color(1.0, 0.45, 0.35))
	if e in selected:
		selected.erase(e)


# The Choir claims a body when it killed it, when the body fell near Choir flesh,
# or inside a Pandemic. Returns the Choir's faction, or -1.
func _infector(e: Ent, killer: Ent) -> int:
	var ch := choir()
	if ch < 0 or e.f == ch or e.d.get("elite", false) or (e.d.get("thrall", false) and e.f != Data.NEUTRAL):
		return -1
	for z in zones:
		if z["kind"] == "pandemic" and z["f"] == ch and e.pos.distance_to(z["p"]) < z["r"]:
			return ch
	# the other courts' sporelings rise when a Stalker brings them down, and
	# sometimes when any Choir body does
	if e.f != Data.NEUTRAL:
		if killer and killer.f == ch and (killer.d.get("infects", false) and _rng.randf() < 0.6 or _rng.randf() < 0.2):
			return ch
		return -1
	if killer and killer.f == ch:
		return ch
	for s in structs:
		if s.f == ch and s.alive and s.pos.distance_to(e.pos) < Data.INFECT_RANGE:
			return ch
	if e.f == Data.NEUTRAL:
		for u in _near_units(e.pos, Data.INFECT_RANGE):
			if u.f == ch and u.alive:
				return ch
	return -1


# The living tree an Agrilus Swarm cast at p lands on.
func _swarm_tree(p: Vector2) -> int:
	var best := -1
	var bd: float = Data.ABILITIES["borer_swarm"]["radius"]
	for t in forest.trees:
		var d: float = p.distance_to(t["pos"]) - t["radius"] * 1.6
		if t["alive"] and d < bd:
			bd = d
			best = t["i"]
	return best


func _raise_thrall(e: Ent, f: int) -> void:
	if e.alive:
		e.alive = false
		e.dying = 0.001
	var uid: String = e.d.get("host", "zombie") if e.f == Data.NEUTRAL else "zombie"
	if uid == "":
		return
	var z := _spawn_unit(f, uid, e.pos)
	z.home = e.pos
	_burst(_v3(e.pos, 0.6), Color(1.0, 0.55, 0.1), 24, 2.0, 0.8)
	emit_signal("sound", "thrall_rise", _v3(e.pos))


func _thrall_decay(u: Ent, dt: float) -> void:
	var k := Data.THRALL_DECAY * (0.6 if has_tech(u.f, "chitin_lysis") else 1.0)
	if myc.density(u.f, u.pos) > 0.3:
		k *= 0.5
	for s in structs:
		if s.f == u.f and s.alive and s.d.has("brood") and s.built >= 1.0 and s.pos.distance_to(u.pos) < s.d["brood"]:
			return
	_damage(u, u.max_hp * k * dt, -1, null, true)


# Bark beetles (and the Choir's beetle thralls) chew into any living trunk they idle by.
func _bore(u: Ent, dt: float) -> void:
	for t in forest.trees:
		if t["alive"] and u.pos.distance_to(t["pos"]) < t["radius"] * 1.6 + 2.2:
			# Agrilus borers are specialists: each broadleaf has its own, conifers resist
			var k: float = u.d.get("bore", 0.004) * (t.get("borer", 1.0) if u.d.has("bore") else 1.0)
			k *= 2.0 if has_tech(u.f, "ophiocordyceps") else 1.0
			forest.drain(t["i"], k * dt, u.f)
			return


# Insects mind their own business: wander near the nest, chase the stench of a
# lure, carry off the dead, bore into trees, and fall sick near Choir flesh.
func _insect_think(u: Ent, dt: float) -> void:
	var d := u.d
	if u.life != INF:
		u.life -= dt
		if u.life <= 0.0:
			_kill(u, null)
			return
	if d.get("bores", false) and u.target == null:
		_bore(u, dt)
	if u.id == "borer":
		# a borer stays on its tree, crawling round the trunk
		u.timer -= dt
		if u.timer <= 0.0 and u.target == null:
			u.timer = _rng.randf_range(1.5, 3.0)
			u.goal = u.home + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
		return
	var ch := choir()
	if ch >= 0 and d.get("host", "") != "":
		var sick := 0.0
		var pull := Vector2.INF
		for s in structs:
			if s.f != ch or not s.alive or s.built < 1.0 or not s.d.has("lure"):
				continue
			var lr: float = s.d["lure"] * (1.5 if has_tech(ch, "stench_glands") else 1.0)
			var dd := u.pos.distance_to(s.pos)
			if dd < lr:
				pull = s.pos
				if dd < s.radius + 2.5:
					sick = 1.0 / (6.0 if s.id == "stinkhorn_lure" else 8.0)
				break
		if sick == 0.0 and has_tech(ch, "ophiocordyceps"):
			for o in _near_units(u.pos, 5.0):
				if o.f == ch and o.alive:
					sick = 1.0 / 12.0
					break
		if sick > 0.0:
			u.infect += sick * dt
			if u.infect >= 1.0:
				if thralls(ch) < pop_cap(ch):
					_raise_thrall(u, ch)
				else:
					u.alive = false
					u.dying = 0.001
					res(ch)[0] += 6.0
				return
		if pull != Vector2.INF and u.target == null:
			u.goal = pull
			return
	u.timer -= dt
	if u.target or u.timer > 0.0:
		return
	u.timer = _rng.randf_range(3.0, 7.0)
	# ants go for the nearest corpse; beetles drift toward living trees
	if u.id == "ant":
		var cs: Array = forest.corpses_near(u.pos, 10.0)
		if not cs.is_empty():
			var c: Dictionary = cs[0]
			if u.pos.distance_to(c["pos"]) < 1.2:
				c["n"] = maxf(c["n"] - 3.0, 0.0)   # carried off, morsel by morsel
				u.timer = 1.0
				return
			u.goal = c["pos"]
			return
	if u.id == "beetle" and _rng.randf() < 0.5:
		for t in forest.trees:
			if t["alive"] and t["pos"].distance_to(u.home) < 30.0:
				var a := _rng.randf() * TAU
				u.goal = t["pos"] + Vector2(cos(a), sin(a)) * (t["radius"] * 1.6 + 1.2)
				return
	var a := _rng.randf() * TAU
	u.goal = u.home + Vector2(cos(a), sin(a)) * _rng.randf_range(2.0, 11.0)


func _faction_falls(f: int) -> void:
	fs[f]["alive"] = false
	emit_signal("message", "%s has fallen - its colony rots." % fs[f]["name"], Data.faction_color(f))
	for s in structs:
		if s.f == f:
			s.connected = false


func _check_end() -> void:
	if over:
		return
	if not fs[player]["alive"]:
		over = true
		emit_signal("game_over", false)
		return
	var others := 0
	for f in 3:
		if f != player and fs[f]["alive"]:
			others += 1
	if others == 0:
		over = true
		emit_signal("game_over", true)


func _cleanup(dt: float) -> void:
	for list in [units, structs, cords, puffs]:
		var i: int = list.size() - 1
		while i >= 0:
			var e: Ent = list[i]
			if not e.alive:
				if e.kind == CORD:
					e.node.queue_free()
					list.remove_at(i)
				elif e.kind == PUFF:
					e.node.queue_free()
					list.remove_at(i)
				else:
					e.dying += dt
					var dur := 0.6 if e.kind == UNIT else 1.6
					var k := e.dying / dur
					e.mi.set_instance_shader_parameter("wither", minf(k * 2.0, 1.0))
					e.node.scale = Vector3(1.0 + k * 0.2, maxf(1.0 - k, 0.35 if e.corpse else 0.02), 1.0 + k * 0.2)
					if e.ring:
						e.ring.visible = false
					if k >= 1.0:
						if not e.corpse:
							e.node.queue_free()
						list.remove_at(i)
						selected.erase(e)
			i -= 1
	# a fallen faction's leftovers rot away
	for f in 3:
		if fs[f]["alive"]:
			continue
		for u in units:
			if u.f == f and u.alive:
				_damage(u, u.max_hp * 0.04 * dt, -1, null, true)


# --- spore-action zones --------------------------------------------------------

func _update_zones(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for z in zones:
		z["t"] += dt
		var f: int = z["f"]
		var p: Vector2 = z["p"]
		var r: float = z["r"]
		match z["kind"]:
			"haze":
				for e in _enemies_in(f, p, r, true, false):
					_damage(e, 8.0 * dt, f, null, true)
					e.slow = maxf(e.slow, 0.4)
					e.slow_t = maxf(e.slow_t, 0.3)
			"lure":
				for e in _enemies_in(f, p, r * 1.3, true, false):
					if z["t"] < 1.2:
						e.vel += (p - e.pos).normalized() * 30.0 * dt
					e.slow = maxf(e.slow, 0.5)
					e.slow_t = maxf(e.slow_t, 0.3)
			"barrage":
				z["next"] -= dt
				if z["next"] <= 0.0:
					z["next"] += 3.0 / 14.0
					var a := _rng.randf() * TAU
					var q := p + Vector2(cos(a), sin(a)) * sqrt(_rng.randf()) * r
					var from := _v3(q, 22.0) + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
					var nobody := Ent.new()
					nobody.alive = false
					shots.append({"from": from, "to": q, "target": null, "t": 0.0, "dur": 0.55, "arc": false,
						"dmg": 26.0, "f": f, "src": nobody, "d": {"splash": 2.0}, "shot": "egg", "node": _shot_node("egg", f)})
			"bloom":
				if z["t"] >= z["dur"]:
					for e in _enemies_in(f, p, r, true, true):
						_damage(e, 90.0 if e.kind == UNIT else 260.0, f, null)
					_burst(_v3(p, 1.0), Color(0.75, 0.8, 0.45), 260, 7.0, 1.6, r * 0.6, 2.5)
					_shake = maxf(_shake, 0.8)
		if z["t"] < z["dur"]:
			keep.append(z)
		elif z.has("props"):
			for n in z["props"]:
				n.queue_free()
	zones = keep


func _ring_of(c: Vector2, r: float, species: String, n: int, scale := 1.0) -> Array:
	var out := []
	for i in n:
		var a := TAU * i / n + _rng.randf() * 0.1
		var p := c + Vector2(cos(a), sin(a)) * r * (1.0 if n > 6 else sqrt(_rng.randf()) * 1.4)
		var mi := MeshInstance3D.new()
		mi.mesh = FungusLib.mesh(species)
		mi.position = _v3(p)
		mi.rotation.y = _rng.randf() * TAU
		mi.scale = Vector3.ONE * scale * _rng.randf_range(0.8, 1.3)
		add_child(mi)
		out.append(mi)
	return out


# --- mycelium sources ----------------------------------------------------------

func _push_sources() -> void:
	if not started:
		return
	myc.clear_sources()
	for s in structs:
		if not s.alive:
			continue
		var r: float = s.d["myc"]
		if s.connected:
			myc.add_disc(s.pos, r * lerpf(0.25, 1.0, s.built), 1.0, s.f)
		else:
			myc.add_disc(s.pos, s.radius + 1.0, 0.85, s.f)
	for c in cords:
		if c.alive and c.regrow <= 0.0 and c.grow >= 1.0 and c.a.connected:
			myc.add_capsule(c.a.pos, c.b.pos, 2.6, 0.9, c.f)
	for u in units:
		if u.alive and u.f != Data.NEUTRAL:
			myc.add_disc(u.pos, 2.2, 0.55, u.f)
	for z in zones:
		match z["kind"]:
			"fairy_ring":
				myc.add_disc(z["p"], z["r"], 1.0, z["f"])
			"wildfire":
				if z["t"] < 1.5:
					myc.add_burn(z["p"], z["r"])
				else:
					myc.add_disc(z["p"], z["r"], 1.0, z["f"])


# --- visuals -------------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	# fog: enemy units and insects show only in sight; enemy structures once spotted
	for u in units:
		if u.alive:
			u.node.visible = u.f == player or fog.visible(player, u.pos)
	for s in structs:
		if s.alive and s.f != player:
			if not s.spotted and fog.visible(player, s.pos):
				s.spotted = true
			s.node.visible = s.spotted
	for c in cords:
		if c.alive:
			c.node.visible = c.f == player or c.a.spotted or c.b.spotted or fog.visible(player, c.pos)
	for p in puffs:
		if p.alive:
			p.node.visible = p.f == player or fog.visible(player, p.pos)
	for u in units:
		if not u.alive:
			continue
		var gy: float = board.ground_y(u.pos)
		u.node.position = Vector3(u.pos.x, lerpf(u.node.position.y, gy, 1.0 - exp(-delta * 12.0)), u.pos.y)
		u.node.rotation.y = -u.facing
		u.mi.position.y = absf(sin(time * 9.0 + u.think_t * 20.0)) * 0.06 * u.walk
		u.mi.set_instance_shader_parameter("walk", u.walk)
		_fx_common(u, delta)
	for s in structs:
		if not s.alive:
			continue
		s.node.scale = Vector3.ONE * lerpf(0.3, 1.0, smoothstep(0.0, 1.0, s.built))
		s.mi.set_instance_shader_parameter("growing", 1.0 - s.built)
		s.mi.set_instance_shader_parameter("wither", 0.0 if s.connected else 0.55)
		_fx_common(s, delta)
	for c in cords:
		if not c.alive:
			continue
		c.mi.set_instance_shader_parameter("progress", c.grow if c.regrow <= 0.0 else 1.0)
		c.mi.set_instance_shader_parameter("load", c.load)
		c.mi.set_instance_shader_parameter("severed", 1.0 if c.regrow > 0.0 else 0.0)
		c.flash = maxf(c.flash - delta * 4.0, 0.0)
		c.mi.set_instance_shader_parameter("flash", c.flash)
	for p in puffs:
		if p.alive:
			_fx_common(p, delta)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 2.5, 0.0)
		rig.cam.h_offset = (randf() - 0.5) * _shake * 0.6
		rig.cam.v_offset = (randf() - 0.5) * _shake * 0.6
	else:
		rig.cam.h_offset = 0.0
		rig.cam.v_offset = 0.0


func _fx_common(e: Ent, delta: float) -> void:
	e.flash = maxf(e.flash - delta * 5.0, 0.0)
	e.mi.set_instance_shader_parameter("flash", e.flash)
	if e.ring:
		e.ring.set_instance_shader_parameter("selected", 1.0 if e.selected else 0.0)


func _burst(at: Vector3, col: Color, amount: int, spd: float, life: float, spread := 0.3, size := 1.0) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 16, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = spread
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = spd * 0.4
	pm.initial_velocity_max = spd
	pm.gravity = Vector3(0, -3.5, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.6 * size
	pm.scale_max = 1.6 * size
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, 1.0))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _spark_mesh
	p.position = at
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _cloud(c: Vector2, r: float, col: Color, dur: float, amount: int) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.6
	p.visibility_aabb = AABB(Vector3(-r - 3, -2, -r - 3), Vector3(r * 2 + 6, 8, r * 2 + 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = r
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 90.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.25, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.scale_min = 3.0
	pm.scale_max = 6.0
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 0.0))
	grad.add_point(0.3, Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, 0.45))
	grad.set_color(grad.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _spark_mesh
	p.position = _v3(c, 0.4)
	add_child(p)
	get_tree().create_timer(dur, false).timeout.connect(func():
		p.emitting = false
		get_tree().create_timer(2.0, false).timeout.connect(p.queue_free))


func _flames(p: Vector2, r: float) -> void:
	_cloud(p, r, Color(1.0, 0.45, 0.1), 1.6, 420)
	_burst(_v3(p, 0.5), Color(1.0, 0.6, 0.2), 200, 6.0, 1.2, r * 0.6)


# --- decor: little fruiting bodies popping up on owned ground ------------------

const DECOR_MAX := 170
const DECOR_MAX_ACCENT := 50     # the second species of each faction is a sprinkle, not a carpet

func _make_decor(species: String) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = FungusLib.mesh(species)
	mm.instance_count = DECOR_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-Data.HALF_W, -3, -Data.HALF_D), Vector3(Data.HALF_W * 2, 10, Data.HALF_D * 2))
	add_child(mmi)
	return {"mm": mm, "pts": [], "born": []}


func _update_decor() -> void:
	if not myc.ok or myc.coarse.is_empty():
		return
	for f in 3:
		for dec in _decor[f]:
			var pts: Array = dec["pts"]
			var born: Array = dec["born"]
			# wither where the colony has lost the ground
			var i := pts.size() - 1
			while i >= 0:
				if myc.density(f, pts[i]) < 0.25:
					pts.remove_at(i)
					born.remove_at(i)
				i -= 1
			# sprout a few new ones on dense owned ground
			var cap := DECOR_MAX if dec == _decor[f][0] else DECOR_MAX_ACCENT
			for k in 16:
				if pts.size() >= cap:
					break
				var q := Vector2(_rng.randf_range(-Data.HALF_W + 1, Data.HALF_W - 1), _rng.randf_range(-Data.HALF_D + 1, Data.HALF_D - 1))   # 4x the board, so more tries below
				if myc.density(f, q) > 0.6 and board.water_at(q) < 0.1:
					pts.append(q)
					born.append(time)
			var mm: MultiMesh = dec["mm"]
			mm.visible_instance_count = pts.size()
			for j in pts.size():
				var p: Vector2 = pts[j]
				var age: float = time - born[j]
				var s := smoothstep(0.0, 2.5, age) * (0.7 + 0.6 * fposmod(p.x * 7.13 + p.y * 3.7, 1.0))
				if f != player and not fog.visible(player, p):
					s = 0.0   # other courts' sprouts hide in the fog
				var b := Basis(Vector3.UP, p.x * 13.1).scaled(Vector3.ONE * maxf(s, 0.01))
				mm.set_instance_transform(j, Transform3D(b, _v3(p, -0.05)))
