extends RefCounted
# The living forest around the war: each tree's vigor and who feeds it, the
# Hollow's deposits (logs, litter, snags, corpses, rubble) and the humus they
# leave, and the insect nests that breed the Choir's hosts. game.gd owns every
# entity; this file owns the world state between them and adds each court's
# special income to the rates game.gd computes.

const Data = preload("res://scripts/data.gd")

var g: Node
# i, pos, radius, roots, sugar, partner, old, vigor, alive, links (tree indices), fed (mantles per faction)
var trees: Array[Dictionary] = []
# kind (log, litter, snag, corpse, rubble), pos, a, b, radius, c, n, c0, n0, life, kept, node, drain_c, drain_n, fly_t, uid
var deposits: Array[Dictionary] = []
# id, kind, pos, dep, insect, cap, every, t
var nests: Array[Dictionary] = []
var humus: Array[Dictionary] = []      # pos, r
var _alert_t := 0.0
var _nest_ids := 0
var _rng := RandomNumberGenerator.new()


func setup(game: Node) -> void:
	g = game
	_rng.seed = 4321 + game.match_seed * 31
	for i in Data.TREES.size():
		var t: Dictionary = Data.TREES[i].duplicate()
		t["i"] = i
		t["vigor"] = Data.VIGOR_REST
		t["alive"] = true
		t["fed"] = [0, 0, 0]
		t["links"] = []
		trees.append(t)
	# trees whose roots overlap talk to each other: up to 4 nearest within TREE_LINK
	for t in trees:
		var near := []
		for o in trees:
			if o != t and t["pos"].distance_to(o["pos"]) <= Data.TREE_LINK:
				near.append(o["i"])
		near.sort_custom(func(a, b): return t["pos"].distance_to(trees[a]["pos"]) < t["pos"].distance_to(trees[b]["pos"]))
		t["links"] = near.slice(0, 4)
	for lg in Data.LOGS:
		var d := _deposit("log", (lg[0] + lg[1]) * 0.5, lg[3], 0.0)
		d["a"] = lg[0]
		d["b"] = lg[1]
		d["radius"] = lg[2]
		nests.append(_nest("log", d["pos"], d))
	for lt in Data.LITTER:
		var d := _deposit("litter", lt[0], lt[1], lt[2])
		d["radius"] = 3.0
		nests.append(_nest("litter", d["pos"], d))
	for p in Data.ANTHILLS:
		nests.append(_nest("anthill", p, {}))
	for t in trees:
		var n := _nest("weak_tree", t["pos"], {})
		n["tree"] = t["i"]
		nests.append(n)


func _deposit(kind: String, p: Vector2, c: float, n: float) -> Dictionary:
	var d := {"kind": kind, "pos": p, "a": p, "b": p, "radius": 1.0, "c": c, "n": n, "c0": c, "n0": n,
		"life": INF, "kept": false, "node": null, "drain_c": 0.0, "drain_n": 0.0, "fly_t": INF}
	deposits.append(d)
	return d


func _nest(kind: String, p: Vector2, dep: Dictionary) -> Dictionary:
	var nd: Array = Data.NESTS[kind]
	_nest_ids += 1
	return {"id": _nest_ids, "kind": kind, "pos": p, "dep": dep, "insect": nd[0], "cap": nd[1], "every": nd[2], "t": _rng.randf() * nd[2]}


# --- queries -------------------------------------------------------------------

func tree_in_roots(p: Vector2, living_only := true) -> int:
	var best := -1
	var bd := INF
	for t in trees:
		if living_only and not t["alive"]:
			continue
		var d: float = p.distance_to(t["pos"])
		if d <= t["roots"] and d < bd:
			bd = d
			best = t["i"]
	return best


func vigor(i: int) -> float:
	return trees[i]["vigor"] if i >= 0 and trees[i]["alive"] else 0.0


func dist_to(d: Dictionary, p: Vector2) -> float:
	var a: Vector2 = d["a"]
	var ab: Vector2 = d["b"] - a
	if ab.length_squared() < 0.001:
		return p.distance_to(a) - d["radius"]
	var k := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * k) - d["radius"]


# The nearest wood a Rot Bracket can sit on.
func wood_near(p: Vector2, reach: float) -> Dictionary:
	var best := {}
	var bd := INF
	for d in deposits:
		if d["kind"] in ["log", "snag", "branch"] and d["c"] > 0.0:
			var dd := dist_to(d, p)
			if dd < reach and dd < bd:
				bd = dd
				best = d
	return best


# Somewhere high for a sporulating thrall to climb: a trunk, a rock, a log.
func summit_near(p: Vector2, reach: float) -> Vector2:
	var best := Vector2.INF
	var bd := reach
	for t in trees:
		var tp: Vector2 = t["pos"]
		var q: Vector2 = tp + (p - tp).normalized() * (t["radius"] * 1.6 + 0.7)
		if q.distance_to(p) < bd:
			bd = q.distance_to(p)
			best = q
	for rk in Data.ROCKS:
		var q: Vector2 = rk[0] + (p - rk[0]).normalized() * rk[1] * 0.45
		if q.distance_to(p) < bd:
			bd = q.distance_to(p)
			best = q
	for d in deposits:
		if d["kind"] == "log":
			var ab: Vector2 = d["b"] - d["a"]
			var q: Vector2 = d["a"] + ab * clampf((p - d["a"]).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if q.distance_to(p) < bd:
				bd = q.distance_to(p)
				best = q
	return best


func corpses_near(p: Vector2, r: float) -> Array:
	var out := []
	for d in deposits:
		if d["kind"] == "corpse" and d["n"] > 0.0 and d["pos"].distance_to(p) < r:
			out.append(d)
	return out


# Does faction f hold the ground at p?
func owns(f: int, p: Vector2) -> bool:
	if g.myc.ok and not g.myc.coarse.is_empty():
		return g.myc.density(f, p) > 0.3
	for s in g.structs:
		if s.f == f and s.alive and s.connected and s.built >= 1.0 and s.pos.distance_to(p) < s.d["myc"]:
			return true
	return false


func holder(p: Vector2) -> int:
	if g.myc.ok and not g.myc.coarse.is_empty():
		var best := -1
		var bd := 0.3
		for f in 3:
			var d: float = g.myc.density(f, p)
			if d > bd:
				bd = d
				best = f
		return best
	for f in 3:
		if owns(f, p):
			return f
	return -1


# --- the dead ------------------------------------------------------------------

func add_corpse(e) -> void:
	var n := 11.0
	if e.d.get("insect", false):
		n = 4.0
	elif e.d.get("elite", false):
		n = 30.0
	elif e.d.get("thrall", false):
		n = 8.0
	var d := _deposit("corpse", e.pos, 0.0, n)
	d["life"] = Data.CORPSE_LIFE * (2.0 if _hollow_has("necrophagy") else 1.0)
	d["node"] = e.node
	d["fly_t"] = 12.0 if _rng.randf() < 0.5 else INF
	d["uid"] = e.id


func add_rubble(p: Vector2) -> void:
	var d := _deposit("rubble", p, 60.0, 6.0)
	d["life"] = 90.0


func _hollow_has(t: String) -> bool:
	for f in 3:
		if Data.FACTIONS[f]["economy"] == "saprotroph" and g.has_tech(f, t):
			return true
	return false


func kill_tree(i: int) -> void:
	var t := trees[i]
	if not t["alive"]:
		return
	t["alive"] = false
	t["vigor"] = 0.0
	var d := _deposit("snag", t["pos"], 500.0, 0.0)
	d["radius"] = t["radius"] * 1.6
	nests.append(_nest("snag", t["pos"], d))
	g.on_tree_died(i)


# A windstorm brings a dead tree down: its snag becomes a long log lying along dir,
# much more wood for the Hollow, and a stag-beetle nursery instead of a bark-beetle one.
func fell(i: int, dir: Vector2) -> void:
	var t := trees[i]
	if t.get("felled", false):
		return
	t["felled"] = true
	var length: float = 10.0 + t["radius"] * 6.0
	var snag := {}
	for d in deposits:
		if d["kind"] == "snag" and d["pos"] == t["pos"]:
			snag = d
	if snag.is_empty():
		snag = _deposit("log", t["pos"], 0.0, 0.0)
	snag["kind"] = "log"
	snag["a"] = t["pos"] + dir * t["radius"] * 1.6
	snag["b"] = t["pos"] + dir * length
	snag["pos"] = (snag["a"] + snag["b"]) * 0.5
	snag["radius"] = t["radius"] * 0.9
	snag["c"] += 600.0
	snag["c0"] = snag["c"]
	for n in nests:
		if is_same(n["dep"], snag):
			var nd: Array = Data.NESTS["log"]
			n["kind"] = "log"
			n["insect"] = nd[0]
			n["cap"] = nd[1]
			n["every"] = nd[2]
			n["pos"] = snag["pos"]
	g.on_tree_felled(i, dir, length)


func add_branch(p: Vector2, dir: Vector2) -> void:
	var d := _deposit("branch", p, 120.0, 0.0)
	d["a"] = p - dir * 1.6
	d["b"] = p + dir * 1.6
	d["radius"] = 0.3
	d["node"] = g.branch_node(d["a"], d["b"])


# Fresh litter: every pile refills by 30%, and a few new piles gather under the big trees.
func leaf_fall(rng: RandomNumberGenerator) -> void:
	for d in deposits:
		if d["kind"] == "litter":
			d["c"] += d["c0"] * 0.3
			d["n"] += d["n0"] * 0.3
	for t in trees:
		if t["alive"] and t["sugar"] >= 4.0 and rng.randf() < 0.6:
			var p: Vector2 = t["pos"] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(t["radius"] * 2.0 + 2.0, t["roots"] * 0.8)
			if g.board.in_bounds(p, 4.0) and g.board.water_at(p) < 0.2:
				var d := _deposit("litter", p, 160.0, 16.0)
				d["radius"] = 3.0
				nests.append(_nest("litter", p, d))


# --- per step ------------------------------------------------------------------

func tick(dt: float) -> void:
	_alert_t -= dt
	# trees drift toward what their partners make of them
	for t in trees:
		if not t["alive"]:
			continue
		var fed := 0
		for f in 3:
			fed += t["fed"][f]
		var target := minf(Data.VIGOR_REST + Data.VIGOR_PER_MANTLE * fed, 1.0)
		var rate := Data.VIGOR_RATE
		for f in 3:
			if t["fed"][f] > 0 and g.has_tech(f, "hartig_net"):
				rate *= 2.0
		t["vigor"] = move_toward(t["vigor"], target, rate * dt)
	# root signalling: linked mantled trees even out their vigor
	for f in 3:
		if not g.has_tech(f, "root_signalling"):
			continue
		for t in trees:
			if not t["alive"] or t["fed"][f] == 0:
				continue
			for li in t["links"]:
				var o := trees[li]
				if o["alive"] and o["fed"][f] > 0:
					var mid: float = (t["vigor"] + o["vigor"]) * 0.5
					t["vigor"] = move_toward(t["vigor"], mid, 0.01 * dt)
	# honey rot eats its tree
	for s in g.structs:
		if s.alive and s.id == "honey_rot" and s.built >= 1.0 and s.connected and s.tree >= 0:
			var t := trees[s.tree]
			if t["alive"]:
				drain(s.tree, Data.HONEY_ROT * (1.5 if t["vigor"] < 0.3 else 1.0) * dt, s.f)
	for t in trees:
		if t["alive"] and t["vigor"] <= 0.0:
			kill_tree(t["i"])
	# deposits drain and rot
	var i := deposits.size() - 1
	while i >= 0:
		var d := deposits[i]
		d["c"] = maxf(d["c"] - d["drain_c"] * dt, 0.0)
		d["n"] = maxf(d["n"] - d["drain_n"] * dt, 0.0)
		if not d["kept"]:
			d["life"] -= dt
		if d["fly_t"] != INF:
			d["fly_t"] -= dt
			if d["fly_t"] <= 0.0:
				d["fly_t"] = INF
				if g.pop(Data.NEUTRAL) < Data.INSECT_CAP:
					g.spawn_insect("fly", d["pos"], 0)
		if d["node"] and d["kind"] == "corpse" and d["n0"] > 0.0:
			var k: float = clampf(d["n"] / d["n0"], 0.0, 1.0) * clampf(d["life"] / 10.0, 0.0, 1.0)
			d["node"].scale = Vector3(1.2, 0.35, 1.2) * maxf(k, 0.05)
			d["node"].position = Vector3(d["pos"].x, g.board.ground_y(d["pos"]), d["pos"].y)
		var empty: bool = d["c"] <= 0.0 and d["n"] <= 0.0
		if empty or d["life"] <= 0.0:
			if empty and d["kind"] in ["log", "snag", "litter"]:
				humus.append({"pos": d["pos"], "r": maxf(dist_to(d, d["a"]) + d["radius"] + 4.0, 5.0)})
				if d["kind"] != "litter":
					g.on_deposit_gone(d)
			if d["node"]:
				d["node"].queue_free()
			d["gone"] = true
			deposits.remove_at(i)
		i -= 1
	_breed(dt)


func drain(tree: int, amt: float, by: int) -> void:
	var t := trees[tree]
	if not t["alive"]:
		return
	t["vigor"] = maxf(t["vigor"] - amt, 0.0)
	# the roots cry out to the court that feeds this tree
	for f in 3:
		if t["fed"][f] > 0 and f != by and f == g.player and _alert_t <= 0.0 and g.has_tech(f, "root_signalling"):
			_alert_t = 20.0
			g.emit_signal("message", "The %s is being eaten!" % t["name"], Color(1.0, 0.6, 0.3))


func _breed(dt: float) -> void:
	var count := 0
	var by_nest := {}
	for u in g.units:
		if u.alive and u.f == Data.NEUTRAL:
			count += 1
			by_nest[u.nest] = by_nest.get(u.nest, 0) + 1
	for n in nests:
		var dep: Dictionary = n["dep"]
		if not dep.is_empty() and (dep.get("gone", false) or dep["c"] + dep["n"] <= 0.0):
			continue
		if n.has("tree"):
			# stressed trees give off the scent bark beetles home in on
			var t := trees[n["tree"]]
			if not t["alive"] or t["vigor"] >= 0.4:
				continue
		if by_nest.get(n["id"], 0) >= n["cap"] or count >= Data.INSECT_CAP:
			continue
		n["t"] += dt * g.weather.breed_mult()
		if n["t"] >= n["every"]:
			n["t"] = 0.0
			g.spawn_insect(n["insect"], n["pos"] + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2)), n["id"])
			count += 1
	# stinkhorn lures breed flies
	for s in g.structs:
		if s.alive and s.built >= 1.0 and s.id == "stinkhorn_lure" and count < Data.INSECT_CAP:
			s.timer += dt
			if s.timer >= 30.0 and by_nest.get(s.get_instance_id(), 0) < 2:
				s.timer = 0.0
				g.spawn_insect("fly", s.pos + Vector2(1.5, 0), s.get_instance_id())
				count += 1


# --- income --------------------------------------------------------------------

# Adds each court's special income into add[f] = [res0, res1, spores] per second,
# and records how fast each deposit is being eaten.
func rates(add: Array) -> void:
	for d in deposits:
		d["drain_c"] = 0.0
		d["drain_n"] = 0.0
		d["kept"] = false
	for t in trees:
		t["fed"] = [0, 0, 0]
	var mantles := [[], [], []]
	for s in g.structs:
		if s.alive and s.connected and s.built >= 1.0 and s.id == "mantle" and s.tree >= 0:
			mantles[s.f].append(s)
			trees[s.tree]["fed"][s.f] += 1
	for f in 3:
		if not g.fs[f]["alive"]:
			continue
		match Data.FACTIONS[f]["economy"]:
			"mycorrhizal":
				_court(f, mantles[f], add[f])
			"saprotroph":
				_hollow(f, add[f])
	# springtails graze whoever's ground they sit on; humus feeds whoever holds it
	for u in g.units:
		if u.alive and u.d.get("grazes", false):
			var h := holder(u.pos)
			if h >= 0:
				add[h][0] -= 0.15
	for hm in humus:
		var h := holder(hm["pos"])
		if h >= 0:
			add[h][0] += 0.8 * (2.0 if g.has_tech(h, "humus_engine") else 1.0)


func _court(f: int, ms: Array, out: Array) -> void:
	if ms.is_empty():
		return
	var starved: bool = g.res(f)[0] <= 1.0
	out[0] -= Data.MANTLE_FEED * ms.size() * (0.0 if starved else 1.0)
	var linked := 0
	var mother := false
	var need := 2 if g.has_tech(f, "old_growth") else 3
	for t in trees:
		if t["fed"][f] > 0 and t["alive"]:
			linked += 1
	for t in trees:
		if t["fed"][f] > 0 and t["alive"] and t.get("old", false) and linked - 1 >= need:
			mother = true
	var mult := (1.0 + Data.WEB_BONUS * clampi(linked - 1, 0, 4)) * (1.0 + (Data.MOTHER_BONUS if mother else 0.0))
	mult *= 1.35 if g.has_tech(f, "hartig_net") else 1.0
	mult *= 0.4 if starved else 1.0
	for t in trees:
		if t["fed"][f] == 0 or not t["alive"]:
			continue
		# every mantle on the tree shares its sugar; this court's share
		var all_fed := 0
		for k in 3:
			all_fed += t["fed"][k]
		var tree_sugar: float = t["sugar"] * Data.SUGAR_SCALE * (0.4 + t["vigor"]) * t["partner"]
		# each mantle's share travels home along the cords (game.gd routes it)
		for m in ms:
			if m.tree == t["i"]:
				g.flows.append([m, 1, tree_sugar * mult / all_fed])
		if t["vigor"] >= 0.7:
			out[2] += Data.FRUIT_SPORES * t["fed"][f]
	g.fs[f]["web"] = {"linked": linked, "mother": mother, "mult": mult}


func _hollow(f: int, out: Array) -> void:
	var exo := 1.35 if g.has_tech(f, "exoenzymes") else 1.0
	var necro := 1.5 if g.has_tech(f, "necrophagy") else 1.0
	var beds := []
	for s in g.structs:
		if not s.alive or s.f != f or not s.connected or s.built < 1.0:
			continue
		if s.id == "rot_bracket" and not s.dep.is_empty() and not s.dep.get("gone", false) and s.dep["c"] > 0.0:
			var r: float = Data.BRACKET_RATE * exo
			s.dep["drain_c"] += r
			g.flows.append([s, 0, r])   # carried home along the cords
			out[2] += r * 0.02
		elif s.id == "inkcap_bed":
			beds.append(s)
	for d in deposits:
		var bed = null
		for b in beds:
			if b.pos.distance_to(d["pos"]) < b.d["gather"] + d["radius"]:
				bed = b
				break
		match d["kind"]:
			"corpse", "rubble":
				if bed:
					d["kept"] = true
					# drawn in toward the inkcaps
					d["pos"] = d["pos"].move_toward(bed.pos, 0.6)
				if bed or owns(f, d["pos"]):
					if d["n"] > 0.0:
						d["drain_n"] += Data.CORPSE_RATE
						out[1] += Data.CORPSE_RATE * necro
					if d["c"] > 0.0:
						d["drain_c"] += Data.CORPSE_RATE
						out[0] += Data.CORPSE_RATE * exo
			"litter":
				var r := 1.2 if bed else (0.5 if owns(f, d["pos"]) else 0.0)
				if r > 0.0 and (d["c"] > 0.0 or d["n"] > 0.0):
					d["drain_c"] += r
					d["drain_n"] += r * 0.1
					out[0] += r * exo
					out[1] += r * 0.1 * necro
