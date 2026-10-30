extends Node3D
# The war itself: structures, rhizomorph cords and supply, sporeling units,
# combat, spore actions, tech, economy read from the GPU mycelium, and the
# per-frame source list that tells the mycelium where each faction reaches.
# The HUD drives it through the public API (try_place, order_*, cast, ...);
# ai.gd drives the other factions through the same calls.

signal message(text: String, col: Color)
signal game_over(won: bool)
signal sound(name: String, at: Vector3)   # at = Vector3.INF for flat UI sounds

const Data = preload("res://scripts/data.gd")
const FungusLib = preload("res://scripts/fungus_lib.gd")
const AI = preload("res://scripts/ai.gd")

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
	# cords
	var a: Ent = null
	var b: Ent = null
	var regrow := 0.0
	var grow := 0.0
	var length := 1.0
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

var units: Array[Ent] = []
var structs: Array[Ent] = []
var cords: Array[Ent] = []
var puffs: Array[Ent] = []
var selected: Array[Ent] = []
var fs: Array[Dictionary] = []
var ais: Array = []
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
	player = faction
	bot = as_bot
	started = true
	time = 0.0
	fs.clear()
	for f in 3:
		var fd: Dictionary = Data.FACTIONS[f]
		fs.append({
			"res": [Data.START_RES[0], Data.START_RES[1], Data.START_RES[2]],
			"rate": [0.0, 0.0, 0.0],
			"techs": {}, "cds": {}, "alive": true, "heart": null,
			"key": fd["key"], "name": fd["name"], "color": fd["color"],
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
	# a few starting wartlings so the opening has bodies on the board
	for f in 3:
		var starter: String = ["wartling", "bruiser", "lure_fly"][f]
		for i in 3:
			var u := _spawn_unit(f, starter, Data.START_POS[f] + Vector2(cos(i * 2.1), sin(i * 2.1)) * 5.0)
			u.home = u.pos
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
	if d.get("near_tree", false) or d.get("near_trunk", false):
		e.tree = _nearest_tree(p)
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
	e.mi.set_instance_shader_parameter("team", Color(c.r, c.g, c.b, 0.45))
	e.mi.set_instance_shader_parameter("gait", 10.0 + _rng.randf() * 3.0)
	e.node.add_child(e.mi)
	_make_ring(e, 1.6 if not d.get("elite", false) else 2.0)
	units.append(e)
	_burst(_v3(p, 0.4), Data.faction_color(f).lightened(0.4), 16, 1.5, 0.6)
	if started and time > 1.0:
		var kind := "spawn_elite" if d.get("elite", false) else ("spawn_heavy" if d["hp"] >= 130 else "spawn_light")
		emit_signal("sound", kind, _v3(p))
	return e


func _link(child: Ent, parent: Ent) -> void:
	var e := Ent.new()
	e.kind = CORD
	e.f = child.f
	e.a = child
	e.b = parent
	e.pos = (child.pos + parent.pos) * 0.5
	e.length = child.pos.distance_to(parent.pos)
	e.max_hp = Data.CORD_HP * (2.0 if has_tech(child.f, "bootlaces") else 1.0)
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
	return t == "" or fs.size() > f and fs[f]["techs"].has(t)


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
	return Data.SPORE_CAP * (1.5 if has_tech(f, "spore_sacs") else 1.0)


func link_range(f: int) -> float:
	return Data.BASE_LINK + (6.0 if has_tech(f, "bootlaces") else 0.0)


func pop(f: int) -> int:
	var n := 0
	for u in units:
		if u.f == f and u.alive:
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


func _nearest_tree(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for i in Data.TREES.size():
		var d := p.distance_to(Data.TREES[i]["pos"])
		if d < bd:
			bd = d
			best = i
	return best


func mantles_on(tree: int) -> int:
	var n := 0
	for s in structs:
		if s.alive and s.id == "mantle" and s.tree == tree:
			n += 1
	return n


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
	if d.get("near_tree", false):
		var t := _nearest_tree(p)
		var tr: Dictionary = Data.TREES[t]
		if p.distance_to(tr["pos"]) > tr["roots"]:
			return "Must be in a tree's root zone"
		if mantles_on(t) >= Data.MANTLES_PER_TREE:
			return "This tree already feeds %d mantles" % Data.MANTLES_PER_TREE
	if d.get("near_trunk", false) and _wood_dist(p) > 3.5:
		return "Must touch a trunk or log"
	if _link_parents(f, p).is_empty():
		return "Out of cord reach - build closer to your network"
	return ""


func _wood_dist(p: Vector2) -> float:
	var best := INF
	for tr in Data.TREES:
		best = minf(best, p.distance_to(tr["pos"]) - tr["radius"] * 1.6)
	for lg in Data.LOGS:
		var a: Vector2 = lg[0]
		var b: Vector2 = lg[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t) - lg[2])
	return best


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
	if pop(s.f) + queued(s.f) >= Data.POP_CAP:
		return "Colony at its limit (%d)" % Data.POP_CAP
	if not afford(s.f, d["cost"]):
		return "Not enough resources"
	pay(s.f, d["cost"])
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
	if not afford(f, td["cost"]):
		return "Not enough resources"
	pay(f, td["cost"])
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
				if n >= 4 or e.d.get("elite", false) or e.id == "zombie":
					continue
				_raise_zombie(e, f)
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
		if not u.alive or u.target == null:
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
			if not e.alive or cam.is_position_behind(e.node.global_position):
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
		if c.alive and c.regrow <= 0.0 and _seg_dist(gp, c.a.pos, c.b.pos) < 0.8:
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
		r[0] += rate[0] * dt
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
	var nut := [0.0, 0.0, 0.0]
	if myc.ok and not myc.coarse.is_empty():
		var cz: PackedFloat32Array = myc.coarse
		var n := Data.COARSE_W * Data.COARSE_H
		for i in n:
			var o := i * 4
			var nu := cz[o + 3]
			nut[0] += cz[o] * nu
			nut[1] += cz[o + 1] * nu
			nut[2] += cz[o + 2] * nu
		for f in 3:
			nut[f] *= Data.NUTRIENT_RATE
	else:
		# no GPU (headless): estimate from each structure's reach
		for s in structs:
			if s.alive and s.connected and s.built >= 1.0:
				nut[s.f] += PI * pow(s.d["myc"], 2.0) * 0.45 * Data.NUTRIENT_RATE
	var spores := [0.0, 0.0, 0.0]
	var sugar := [0.0, 0.0, 0.0]
	var tree_n := []
	tree_n.resize(Data.TREES.size())
	tree_n.fill(0)
	for s in structs:
		if s.alive and s.connected and s.built >= 1.0:
			spores[s.f] += s.d.get("spores", 0.0)
			nut[s.f] += s.d.get("nutrients", 0.0)
			if s.id == "mantle":
				tree_n[s.tree] += 1
	for s in structs:
		if s.alive and s.connected and s.built >= 1.0 and s.id == "mantle":
			sugar[s.f] += Data.TREES[s.tree]["sugar"] * Data.SUGAR_SCALE / tree_n[s.tree]
	for f in 3:
		if not fs[f]["alive"]:
			fs[f]["rate"] = [0.0, 0.0, 0.0]
			continue
		var nm := 1.35 if has_tech(f, "exoenzymes") else 1.0
		var sm := 1.4 if has_tech(f, "spore_sacs") else 1.0
		fs[f]["rate"] = [nut[f] * nm, sugar[f], spores[f] * sm]
		myc.growth[f] = 1.25 if has_tech(f, "exoenzymes") else 1.0


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
			var bt: float = d.get("build", 10.0)
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
	# training
	if not s.queue.is_empty():
		var uid: String = s.queue[0]
		s.train_t += dt
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
	if t == "bootlaces":
		for c in cords:
			if c.f == f:
				c.max_hp *= 2.0
				c.hp *= 2.0
	if f == player:
		emit_signal("message", "Researched %s." % Data.TECHS[t]["name"], Color(0.95, 0.9, 0.6))
		emit_signal("sound", "research_done", Vector3.INF)


func _update_cord(c: Ent, dt: float) -> void:
	if not c.a.alive or not c.b.alive:
		c.alive = false
		_conn_dirty = true
		return
	if c.regrow > 0.0:
		c.regrow -= dt * (2.0 if has_tech(c.f, "bootlaces") else 1.0)
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
	if has_tech(u.f, "calvatia"):
		s *= 1.2
	if has_tech(u.f, "bootlaces") and myc.density(u.f, u.pos) > 0.3:
		s *= 1.15
	if board.water_at(u.pos) > 0.3:
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
	if u.id == "zombie":
		_damage(u, 1.2 * dt, -1, null, true)
	u.cd -= dt
	if u.target and (not u.target.alive or (u.target.kind == CORD and u.target.regrow > 0.0)):
		u.target = null
	# look for trouble
	u.think_t -= dt
	if u.think_t <= 0.0:
		u.think_t = 0.3
		if u.target == null and (u.goal == Vector2.INF or u.amove):
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
		if o.f != e.f and o.alive:
			var dd: float = e.pos.distance_to(o.pos)
			if dd < bs:
				bs = dd
				best = o
	var cutter := e.id in ["lure_fly", "angel"]
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

func _fire(src: Ent, t: Ent, d: Dictionary) -> void:
	var shot: String = d.get("shot", "")
	var dmg: float = d["dmg"]
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
	e.hp -= amt
	if not quiet:
		e.flash = 1.0
		if d.has("poison"):
			e.poison_dps = maxf(e.poison_dps if e.poison_t > 0.0 else 0.0, d["poison"])
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
		_burst(_v3(e.pos, 0.5), col.lerp(Color(0.9, 0.85, 0.7), 0.5), 30, 3.5, 0.8)
		emit_signal("sound", "unit_death", _v3(e.pos))
		if killer and killer.alive and killer.d.get("infects", false) and not e.d.get("elite", false) and e.id != "zombie":
			_raise_zombie(e, killer.f)
	else:
		_burst(_v3(e.pos, 1.0), col.lerp(Color(0.8, 0.75, 0.6), 0.5), 120, 5.0, 1.4, e.radius)
		emit_signal("sound", "heart_death" if e.d.has("research") else "struct_death", _v3(e.pos))
		_shake = maxf(_shake, 0.5 if e.d.has("research") else 0.25)
		_conn_dirty = true
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


func _raise_zombie(e: Ent, f: int) -> void:
	if e.alive:
		e.alive = false
		e.dying = 0.001
	var z := _spawn_unit(f, "zombie", e.pos)
	z.home = e.pos
	_burst(_v3(e.pos, 0.6), Color(1.0, 0.55, 0.1), 24, 2.0, 0.8)


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
					e.node.scale = Vector3(1.0 + k * 0.2, maxf(1.0 - k, 0.02), 1.0 + k * 0.2)
					if e.ring:
						e.ring.visible = false
					if k >= 1.0:
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
		if u.alive:
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
			for k in 6:
				if pts.size() >= cap:
					break
				var q := Vector2(_rng.randf_range(-Data.HALF_W + 1, Data.HALF_W - 1), _rng.randf_range(-Data.HALF_D + 1, Data.HALF_D - 1))
				if myc.density(f, q) > 0.6 and board.water_at(q) < 0.1:
					pts.append(q)
					born.append(time)
			var mm: MultiMesh = dec["mm"]
			mm.visible_instance_count = pts.size()
			for j in pts.size():
				var p: Vector2 = pts[j]
				var age: float = time - born[j]
				var s := smoothstep(0.0, 2.5, age) * (0.7 + 0.6 * fposmod(p.x * 7.13 + p.y * 3.7, 1.0))
				var b := Basis(Vector3.UP, p.x * 13.1).scaled(Vector3.ONE * maxf(s, 0.01))
				mm.set_instance_transform(j, Transform3D(b, _v3(p, -0.05)))
