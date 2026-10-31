extends RefCounted
# One computer-run faction. Thinks once a second through the same public calls
# the HUD uses. Each court plays to its economy: the Court mantles trees, guards
# them with root snares and culls the pests on them; the Hollow grows toward
# wood and corpses, plants brackets and Honey Rot; the Choir hunts insects,
# grows lures beside their nests and sporulates its dying thralls. All three
# research down a fixed order, keep training, gather an army at the front and
# send it in waves, raid enemy cords, defend, and cast spore actions on clumps.
# It plays under the same fog: it acts only on what its court can see now or has
# spotted before (fog.gd), plus the three start positions anyone reading the map
# knows. A scout keeps the picture fresh.

const Data = preload("res://scripts/data.gd")

var g: Node
var f := 0
var fd: Dictionary
var eco := ""
var rng := RandomNumberGenerator.new()
var think_t := 1.0
var wave := 0
var wave_size := 6
var attack_t := 170.0
var attacking := false
var raid_t := 95.0
var tech_order: Array = []
var builder = null          # Choir: the thrall walking off to become a structure
var scout = null
var scout_t := 40.0
var scout_route: Array[Vector2] = []
var build_plan := {}        # Choir: {sid, at}


func setup(game: Node, faction: int) -> void:
	g = game
	f = faction
	fd = Data.FACTIONS[f]
	eco = fd["economy"]
	rng.seed = 99 + f * 7 + game.match_seed * 104729
	think_t = 1.0 + f * 0.33
	attack_t = 160.0 + rng.randf() * 40.0
	tech_order = fd["ai_techs"]


func tick(dt: float) -> void:
	if not g.fs[f]["alive"]:
		return
	think_t -= dt
	if think_t > 0.0:
		return
	think_t = 1.0
	_research()
	_train()
	match eco:
		"mycorrhizal":
			_build_court()
		"saprotroph":
			_build_hollow()
		"parasite":
			_build_choir()
			_sporulate()
	_scout()
	_army()
	_abilities()


# --- what this court knows ------------------------------------------------------

func _sees(p: Vector2) -> bool:
	return g.fog.visible(f, p)


func _knows(s) -> bool:
	return s.seen_by & (1 << f) != 0


# One fast unit tours the rival starts and the middle of the map, so the
# army has targets; a dead scout is replaced after a while.
func _scout() -> void:
	if scout != null and (not scout.alive or scout.squad != "scout"):
		scout = null
		scout_t = g.time + 75.0
	if scout == null:
		if g.time < scout_t:
			return
		var best = null
		for u in g.units:
			if u.f == f and u.alive and u.squad == "" and not u.d.get("elite", false) and u.summit == Vector2.INF:
				if best == null or u.d["speed"] > best.d["speed"]:
					best = u
		if best == null:
			return
		scout = best
		scout.squad = "scout"
		scout_route.clear()
		for o in 3:
			if o != f and g.fs[o]["alive"]:
				scout_route.append(Data.START_POS[o])
		scout_route.append(Vector2(rng.randf_range(-30, 30), rng.randf_range(-20, 20)))
		scout_route.shuffle()
	if scout.goal == Vector2.INF and scout.target == null:
		if scout_route.is_empty():
			scout.squad = ""   # done: back to the army
			scout = null
			scout_t = g.time + 120.0
			return
		g.order_move([scout], scout_route.pop_front())


func _mine(sid := "") -> Array:
	var out := []
	for s in g.structs:
		if s.f == f and s.alive and (sid == "" or s.id == sid):
			out.append(s)
	return out


func _n(sid: String) -> int:
	return _mine(sid).size()


func _research() -> void:
	var h = g.heart(f)
	if h == null or h.research != "":
		return
	for t in tech_order:
		if g.tech_state(f, t) == 1:
			var c: Array = Data.TECHS[t]["cost"]
			if g.afford(f, c, Data.TECHS[t].get("spores", 0.0)):
				g.start_research(f, t)
			return


# What to hold back for the next lineage. Training and spare buildings otherwise
# spend every second's income, and a court that never researches never reaches
# its elites or its tier-3 spore actions. Once the colony has a small army, save.
func _saving() -> Array:
	var h = g.heart(f)
	if h == null or h.research != "" or g.time < 120.0 or g.pop(f) < 10:
		return [0.0, 0.0]
	for t in tech_order:
		if g.tech_state(f, t) == 1:
			var c: Array = Data.TECHS[t]["cost"]
			return [c[0], c[1]]
	return [0.0, 0.0]


func _growing() -> int:
	var n := 0
	for s in _mine():
		if s.built < 1.0:
			n += 1
	return n


# Try each wanted structure in order; the first that has a spot gets placed (or waited for).
func _try_wants(wants: Array) -> void:
	var save := _saving()
	for sid in wants:
		var cost: Array = Data.STRUCTURES[sid]["cost"]
		if g.res(f)[1] < cost[1]:
			continue   # short on the elite resource: don't let it block the cheap builds
		if _n(sid) > 0 and (g.res(f)[0] - cost[0] < save[0] or g.res(f)[1] - cost[1] < save[1]):
			continue   # saving for a lineage: only first-of-a-kind buildings go ahead
		var spot := _spot(sid)
		if spot == Vector2.INF:
			var reach := _reach_for(sid)
			if reach != Vector2.INF:
				var ns := _spot("node", reach)
				if ns != Vector2.INF:
					_place("node", ns)
					return
			continue
		_place(sid, spot)
		return


func _place(sid: String, p: Vector2) -> void:
	# wait for the money instead of skipping down the list
	if g.afford(f, Data.STRUCTURES[sid]["cost"]):
		g.try_place(f, sid, p)


# --- the Court -----------------------------------------------------------------

func _build_court() -> void:
	if _growing() >= 2:
		return
	var t: float = g.time
	var mantled := 0
	for tr in g.forest.trees:
		if tr["alive"] and tr["fed"][f] > 0:
			mantled += 1
	var wants := []
	if _n("agaric_ring") == 0:
		wants.append("agaric_ring")
	if _n("mantle") < 2:
		wants.append("mantle")
	if _n("node") < 2:
		wants.append("node")
	if g.has_tech(f, "phalloides") and _n("deathcap_grove") == 0:
		wants.append("deathcap_grove")
	if t > 100.0 and _n("root_snare") < mini(mantled, 1 + int(t / 150.0)):
		wants.append("root_snare")
	if t > 110.0 and mantled > 0 and (_n("cortina_thicket") < 1 or t > 300.0 and _n("cortina_thicket") < 2):
		wants.append("cortina_thicket")
	if t > 90.0 and _n("truffle") < mini(1 + int(t / 120.0), 5):
		wants.append("truffle")
	if t > 180.0 and _n("nursery") == 0 and g.res(f)[0] > 150.0 and g.res(f)[1] > 80.0:
		wants.append("nursery")
	if _n("mantle") < mini(2 + int(t / 70.0), 9):
		wants.append("mantle")
	if t > 110.0 and _n("agaric_ring") < 2:
		wants.append("agaric_ring")
	if _n("node") < mini(3 + int(t / 90.0), 10):
		wants.append("node")
	if g.res(f)[0] > 220.0 and _n("agaric_ring") < 4:
		wants.append("agaric_ring")
	_try_wants(wants)


# --- the Hollow ----------------------------------------------------------------

func _build_hollow() -> void:
	if _growing() >= 2:
		return
	var t: float = g.time
	var wants := []
	if _n("morel_patch") == 0:
		wants.append("morel_patch")
	if _n("rot_bracket") < 1:
		wants.append("rot_bracket")
	if t > 30.0 and _n("oyster_shelf") < 1:
		wants.append("oyster_shelf")
	if _n("node") < 2:
		wants.append("node")
	if t > 50.0 and _n("inkcap_bed") < 1:
		wants.append("inkcap_bed")
	if _n("rot_bracket") < mini(1 + int(t / 80.0), 6):
		wants.append("rot_bracket")
	if _n("oyster_shelf") < mini(1 + int(t / 150.0), 3):
		wants.append("oyster_shelf")
	if g.has_tech(f, "pilobolus") and _n("pilobolus_bed") == 0:
		wants.append("pilobolus_bed")
	if g.has_tech(f, "armillaria") and _n("honey_rot") < 2:
		wants.append("honey_rot")
	if t > 110.0 and _n("earthstar") < mini(1 + int(t / 220.0), 3):
		wants.append("earthstar")
	if t > 200.0 and _n("birds_nest") < 1:
		wants.append("birds_nest")
	if t > 90.0 and _n("morel_patch") < 2 or t > 240.0 and _n("morel_patch") < 3:
		wants.append("morel_patch")
	if t > 240.0 and _n("inkcap_bed") < 2:
		wants.append("inkcap_bed")
	if _n("node") < mini(3 + int(t / 80.0), 11):
		wants.append("node")
	if g.res(f)[0] > 220.0 and _n("morel_patch") < 4:
		wants.append("morel_patch")
	_try_wants(wants)


# --- the Choir -----------------------------------------------------------------

func _build_choir() -> void:
	var t: float = g.time
	# a thrall already walking off to become something: place it once it arrives
	if not build_plan.is_empty():
		var sid: String = build_plan["sid"]
		var at: Vector2 = build_plan["at"]
		if builder == null or not builder.alive or t - build_plan["t0"] > 40.0:
			_drop_plan()
		elif g.place_error(f, sid, at, false) == "":
			if g.afford(f, Data.STRUCTURES[sid]["cost"]):
				g.try_place(f, sid, at)
				_drop_plan()
			return
		else:
			builder.goal = at
			return
	if _growing() >= 2:
		return
	var wants := []
	if _n("stinkhorn_lure") < 1:
		wants.append("stinkhorn_lure")
	if t > 60.0 and _n("clathrus_cage") < 1:
		wants.append("clathrus_cage")
	if g.has_tech(f, "hypocreales") and _n("cordyceps_spire") == 0:
		wants.append("cordyceps_spire")
	if _n("stinkhorn_lure") < mini(1 + int(t / 60.0), 6):
		wants.append("stinkhorn_lure")
	if g.has_tech(f, "brood") and _n("brood_chamber") == 0:
		wants.append("brood_chamber")
	if t > 150.0 and _n("clathrus_cage") < mini(1 + int(t / 110.0), 6):
		wants.append("clathrus_cage")
	for sid in wants:
		if not g.afford(f, Data.STRUCTURES[sid]["cost"]):
			return
		var at := _choir_spot(sid)
		if at == Vector2.INF:
			continue
		var host = _nearest_thrall(at)
		if host == null:
			return
		builder = host
		builder.squad = "build"
		g.order_move([builder], at)
		build_plan = {"sid": sid, "at": at, "t0": t}
		return


func _drop_plan() -> void:
	if builder and builder.alive:
		builder.squad = ""
	builder = null
	build_plan = {}


func _nearest_thrall(p: Vector2):
	var best = null
	var bd := INF
	for u in g.units:
		if u.f == f and u.alive and u.d.get("thrall", false) and u.squad == "" and u.burst < 0.0 and u.summit == Vector2.INF:
			var d: float = u.pos.distance_to(p)
			if d < bd:
				bd = d
				best = u
	return best


# Lures go beside insect nests nobody of ours is farming yet; cages guard the
# Heart and the lures; the rest sit near home.
func _choir_spot(sid: String) -> Vector2:
	var h = g.heart(f)
	var targets: Array[Vector2] = []
	if sid == "stinkhorn_lure":
		var nests: Array = g.forest.nests.duplicate()
		nests.sort_custom(func(a, b): return a["pos"].distance_to(h.pos) < b["pos"].distance_to(h.pos))
		for n in nests:
			var taken := false
			for s in _mine("stinkhorn_lure"):
				if s.pos.distance_to(n["pos"]) < 12.0:
					taken = true
			if not taken and n["pos"].distance_to(h.pos) < 90.0:
				targets.append(n["pos"])
		if targets.is_empty():
			targets.append(h.pos.lerp(_front(), 0.25))
	elif sid == "clathrus_cage":
		var lures := _mine("stinkhorn_lure")
		if not lures.is_empty() and rng.randf() < 0.6:
			targets.append(lures[rng.randi() % lures.size()].pos.lerp(_front(), 0.1))
		targets.append(h.pos.lerp(_front(), 0.2))
	else:
		targets.append(h.pos.lerp(_front(), 0.1))
	var d: Dictionary = Data.STRUCTURES[sid]
	for tp in targets:
		for k in 16:
			var a := TAU * k / 16.0 + rng.randf() * 0.4
			for rr in [5.0, 7.5, 10.0]:
				var q: Vector2 = tp + Vector2(cos(a), sin(a)) * (rr + d["radius"])
				var err: String = g.place_error(f, sid, q, false)
				if err == "" or err.begins_with("Needs a thrall"):
					return q
	return Vector2.INF


func _sporulate() -> void:
	var th := []
	for u in g.units:
		if u.f == f and u.alive and u.d.get("thrall", false) and u.squad != "build" and u.burst < 0.0 and u.summit == Vector2.INF:
			th.append(u)
	var cap: int = g.pop_cap(f)
	var burst := []
	for u in th:
		# a dying thrall is worth more as spores than as a corpse
		if u.hp < u.max_hp * 0.45 and u.target == null:
			burst.append(u)
	if th.size() >= int(cap * 0.6):
		th.sort_custom(func(a, b): return a.hp / a.max_hp < b.hp / b.max_hp)
		for u in th.slice(0, 3):
			if not u in burst:
				burst.append(u)
	if not burst.is_empty():
		g.order_sporulate(burst)


# --- spots ---------------------------------------------------------------------

# Where to grow a node toward when sid has nowhere to go yet.
func _reach_for(sid: String) -> Vector2:
	var h = g.heart(f)
	var best := Vector2.INF
	var bd := INF
	match sid:
		"mantle", "root_snare", "honey_rot", "cortina_thicket":
			for tr in g.forest.trees:
				if not tr["alive"]:
					continue
				if sid == "mantle" and g.mantles_on(tr["i"]) >= g.mantle_cap(f):
					continue
				if sid in ["root_snare", "cortina_thicket"] and tr["fed"][f] == 0:
					continue
				var d: float = tr["pos"].distance_to(h.pos)
				if sid == "honey_rot" and tr["fed"][f] == 0:
					d *= 0.6   # rot the trees the others feed on first
				if d < bd:
					bd = d
					best = tr["pos"]
		"rot_bracket", "oyster_shelf":
			for dep in g.forest.deposits:
				if dep["kind"] in ["log", "snag", "branch"] and dep["c"] > 80.0:
					var q: Vector2 = dep["a"] + (dep["b"] - dep["a"]) * clampf((h.pos - dep["a"]).dot(dep["b"] - dep["a"]) / maxf((dep["b"] - dep["a"]).length_squared(), 0.01), 0.0, 1.0)
					var d: float = q.distance_to(h.pos)
					if d < bd:
						bd = d
						best = q
		"inkcap_bed":
			for dep in g.forest.deposits:
				if dep["kind"] == "litter" and dep["c"] > 40.0:
					var d: float = dep["pos"].distance_to(h.pos)
					if d < bd:
						bd = d
						best = dep["pos"]
	return best


func _front() -> Vector2:
	return Data.START_POS[rival()]


# Who to fight: each court presses the next one round the table, so no two
# grind each other down while the third grows fat - unless someone is running
# away with the game, in which case everyone turns on the leader.
func rival() -> int:
	var power := [0.0, 0.0, 0.0]
	for o in 3:
		if g.fs[o]["alive"]:
			# judged only by what this court has seen of them
			power[o] = g.units.filter(func(e): return e.f == o and e.alive and (o == f or _sees(e.pos))).size() * 1.0 \
				+ g.structs.filter(func(e): return e.f == o and e.alive and (o == f or _knows(e))).size() * 0.6
	var leader := -1
	for o in 3:
		if o != f and g.fs[o]["alive"]:
			var others := 0.0
			for k in 3:
				if k != o:
					others = maxf(others, power[k])
			if power[o] > others * 1.5 + 4.0:
				leader = o
	if leader >= 0:
		return leader
	for step in [g.rival_step, 3 - g.rival_step]:
		var o: int = (f + step) % 3
		if g.fs[o]["alive"]:
			return o
	return f


func _spot(sid: String, toward := Vector2.INF) -> Vector2:
	var d: Dictionary = Data.STRUCTURES[sid]
	var h = g.heart(f)
	var cands: Array[Vector2] = []
	match d.get("on", ""):
		"tree":
			for tr in g.forest.trees:
				if not tr["alive"]:
					continue
				if sid in ["root_snare", "cortina_thicket"] and tr["fed"][f] == 0:
					continue
				for k in 14:
					var a := TAU * k / 14.0 + rng.randf() * 0.3
					for rr in [tr["radius"] * 1.6 + 3.0, tr["radius"] * 1.6 + 5.5, tr["radius"] * 1.6 + 8.0]:
						if rr < tr["roots"]:
							cands.append(tr["pos"] + Vector2(cos(a), sin(a)) * rr)
			if sid == "honey_rot":
				toward = _enemy_tree()
			if toward == Vector2.INF:
				toward = h.pos
		"territory", "gap":
			# truffles on the approach to the front; nurseries back home, in the open
			for s in _mine():
				if s.built < 1.0 or not s.connected:
					continue
				for k in 10:
					var a := TAU * k / 10.0 + rng.randf() * 0.5
					for dd in [6.0, 10.0, 13.0]:
						cands.append(s.pos + Vector2(cos(a), sin(a)) * dd)
			toward = h.pos.lerp(_front(), 0.45) if d["on"] == "territory" else h.pos
		"deposit":
			for dep in g.forest.deposits:
				if not dep["kind"] in ["log", "snag", "branch"] or dep["c"] <= 0.0:
					continue
				var ab: Vector2 = dep["b"] - dep["a"]
				var n: Vector2 = ab.orthogonal().normalized() if ab.length() > 0.1 else Vector2.RIGHT
				for k in 9:
					var p: Vector2 = dep["a"].lerp(dep["b"], k / 8.0)
					for side in [1.0, -1.0]:
						cands.append(p + n * side * (dep["radius"] + 2.0))
					if ab.length() <= 0.1:
						var a := TAU * k / 9.0
						cands.append(p + Vector2(cos(a), sin(a)) * (dep["radius"] + 2.0))
			toward = h.pos
		_:
			var lr: float = g.link_range(f)
			if toward == Vector2.INF:
				if sid == "node":
					toward = _front()
				elif sid == "inkcap_bed":
					toward = _reach_for("inkcap_bed")
					if toward == Vector2.INF:
						toward = h.pos.lerp(_front(), 0.4)
				else:
					var towers := ["root_snare", "earthstar", "birds_nest"]
					toward = h.pos.lerp(_front(), 0.4 if sid in towers else 0.2)
			for s in _mine():
				if s.built < 1.0 or not s.connected:
					continue
				for k in 10:
					var a := TAU * k / 10.0 + rng.randf() * 0.5
					var dists := [lr * 0.6, lr * 0.9] if sid == "node" else [s.radius + d["radius"] + 1.5, s.radius + d["radius"] + 4.5]
					for dd in dists:
						cands.append(s.pos + Vector2(cos(a), sin(a)) * dd)
	var best := Vector2.INF
	var bs := INF
	for p in cands:
		if g.place_error(f, sid, p, false) != "":
			continue
		var sc: float = p.distance_to(toward) + rng.randf() * 2.0
		if sc < bs:
			bs = sc
			best = p
	return best


# The tree some rival is getting the most sugar from.
func _enemy_tree() -> Vector2:
	var best := Vector2.INF
	var bn := 0
	for tr in g.forest.trees:
		if not tr["alive"] or g.mantles_on(tr["i"], "honey_rot") > 0:
			continue
		var n := 0
		for s in g.structs:
			if s.alive and s.id == "mantle" and s.f != f and s.tree == tr["i"] and _knows(s):
				n += 1
		if n > bn:
			bn = n
			best = tr["pos"]
	return best


# --- army ----------------------------------------------------------------------

func _train() -> void:
	# keep the army near a target that grows with time; past it, save for buildings
	var army: int = g.pop(f) + g.queued(f)
	var reserve := 0.0 if army < mini(4 + int(g.time / 12.0), g.pop_cap(f)) else 110.0
	var save := _saving()
	reserve = maxf(reserve, save[0])
	for s in _mine():
		if s.built < 1.0 or not s.connected or s.d.get("trains", []).is_empty():
			continue
		if s.queue.size() >= 2:
			continue
		var trains: Array = s.d["trains"]
		var uid: String = trains[rng.randi() % trains.size()]
		var ud: Dictionary = Data.UNITS[uid]
		var c: Array = ud["cost"]
		if g.res(f)[0] < c[0] + reserve or g.res(f)[1] < c[1] + save[1]:
			continue
		if ud.get("spores", 0.0) > 0.0 and g.res(f)[2] < ud["spores"] + 30.0:
			continue
		g.queue_train(s, uid)


func _army() -> void:
	var army := []
	for u in g.units:
		if u.f == f and u.alive and u.squad == "" and u.summit == Vector2.INF:
			army.append(u)
	# raids on supply cords
	raid_t -= 1.0
	if raid_t <= 0.0 and army.size() >= 7:
		raid_t = 70.0 + rng.randf() * 40.0
		var fast := army.duplicate()
		fast.sort_custom(func(a, b): return a.d["speed"] > b.d["speed"])
		var cord = _enemy_cord()
		if cord:
			var squad := fast.slice(0, 2)
			for u in squad:
				u.squad = "raid"
			g.order_attack(squad, cord)
	for u in g.units:
		if u.f == f and u.alive and u.squad in ["raid", "pest"] and u.target == null and u.goal == Vector2.INF:
			u.squad = ""
	# the Heart under attack: drop everything and come home
	var hp: Vector2 = g.heart(f).pos
	for u in g.units:
		if u.alive and u.f != f and u.f != Data.NEUTRAL and u.pos.distance_to(hp) < 24.0 and _sees(u.pos):
			if attacking:
				attacking = false
				attack_t = g.time + 40.0
			g.order_move(army, u.pos, true)
			return
	# defend anything under attack
	var threat := _threat()
	if threat != Vector2.INF and not attacking:
		var idle := []
		for u in army:
			if u.target == null:
				idle.append(u)
		g.order_move(idle, threat, true)
		return
	if eco == "mycorrhizal":
		_cull_pests(army)
	var rally := _rally()
	if attacking:
		if army.size() < 3:
			attacking = false
			attack_t = g.time + 45.0
			g.order_move(army, rally, false)
			return
		var idle := []
		for u in army:
			if u.target == null and u.goal == Vector2.INF:
				idle.append(u)
		if not idle.is_empty():
			var tgt := _enemy_target(idle[0].pos)
			if tgt != Vector2.INF:
				g.order_move(idle, tgt, true)
		return
	if army.size() >= wave_size and g.time >= attack_t:
		var tgt := _enemy_target(rally)
		if tgt != Vector2.INF:
			attacking = true
			wave += 1
			wave_size = mini(6 + wave * 2, 22)
			g.order_move(army, tgt, true)
			return
	if eco == "parasite" and _hunt(army):
		return
	# gather idle units at the front
	var gather := []
	for u in army:
		if u.target == null and u.goal == Vector2.INF and u.pos.distance_to(rally) > 7.0:
			gather.append(u)
	if not gather.is_empty():
		g.order_move(gather, rally, true)


# The Choir's idle army goes looking for hosts: the nearest insects, in bites of a few.
func _hunt(army: Array) -> bool:
	var idle := []
	for u in army:
		if u.target == null and u.goal == Vector2.INF:
			idle.append(u)
	if idle.size() < 3:
		return false
	var h = g.heart(f)
	var best = null
	var bd := 85.0
	for u in g.units:
		if u.f == Data.NEUTRAL and u.alive and u.d.get("host", "") != "" and _ours(u.pos) and _sees(u.pos):
			var d: float = u.pos.distance_to(h.pos)
			if d < bd:
				bd = d
				best = u
	if best != null:
		g.order_move(idle.slice(0, 6), best.pos, true)
		return true
	# nothing in sight: go and look where insects breed
	var nests: Array = g.forest.nests.filter(func(n): return _ours(n["pos"]) and not _sees(n["pos"]))
	if nests.is_empty():
		return false
	nests.sort_custom(func(a, b): return a["pos"].distance_to(h.pos) < b["pos"].distance_to(h.pos))
	g.order_move(idle.slice(0, 4), nests[0]["pos"], true)
	return true


# Closer to our Heart than to anyone else's: the hunting grounds we can hold.
func _ours(p: Vector2) -> bool:
	var mine: float = p.distance_to(g.heart(f).pos)
	for o in 3:
		if o != f and g.fs[o]["alive"] and p.distance_to(g.heart(o).pos) < mine * 1.1:
			return false
	return true


# Send a pair to clear bugs off the trees the Court feeds, and the army after
# any Honey Rot eating one of them.
func _cull_pests(army: Array) -> void:
	for s in g.structs:
		if s.alive and s.id == "honey_rot" and s.f != f and _knows(s) and s.tree >= 0 and g.forest.trees[s.tree]["fed"][f] > 0:
			var idle := army.filter(func(a): return a.target == null)
			if idle.size() >= 3:
				g.order_attack(idle, s)
				return
	for u in g.units:
		if u.f != Data.NEUTRAL or not u.alive or not _sees(u.pos):
			continue
		var t: int = g.forest.tree_in_roots(u.pos)
		if t < 0 or g.forest.trees[t]["fed"][f] == 0:
			continue
		var idle := army.filter(func(a): return a.target == null and a.squad == "")
		idle.sort_custom(func(a, b): return a.pos.distance_to(u.pos) < b.pos.distance_to(u.pos))
		var pair := idle.slice(0, 2)
		for a in pair:
			a.squad = "pest"
		g.order_attack(pair, u)
		return


func _rally() -> Vector2:
	var fr := _front()
	var best: Vector2 = g.heart(f).pos
	var bd := INF
	for s in _mine():
		if s.built >= 1.0 and s.connected:
			var d: float = s.pos.distance_to(fr)
			if d < bd:
				bd = d
				best = s.pos
	return best.lerp(g.heart(f).pos, 0.15)


func _threat() -> Vector2:
	for u in g.units:
		if u.f == f or not u.alive or u.f == Data.NEUTRAL or not _sees(u.pos):
			continue
		for s in _mine():
			if s.pos.distance_to(u.pos) < 16.0:
				return u.pos
	return Vector2.INF


func _enemy_target(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	var r := rival()
	for s in g.structs:
		if s.f == r and s.alive and _knows(s):
			var d: float = s.pos.distance_to(from)
			if d < bd:
				bd = d
				best = s.pos
	if best == Vector2.INF and g.fs[r]["alive"]:
		best = Data.START_POS[r]   # nothing spotted yet: march on where they started
	return best


func _enemy_cord():
	var h = g.heart(f)
	var best = null
	var bd := INF
	for c in g.cords:
		if c.f != f and c.alive and c.regrow <= 0.0 and c.grow >= 1.0 and (_knows(c.a) or _knows(c.b)):
			var d: float = c.pos.distance_to(h.pos)
			if d < bd:
				bd = d
				best = c
	return best


# --- spore actions -------------------------------------------------------------

func _abilities() -> void:
	# keep enough spores back for the next lineage that is paid in them
	var keep := 0.0
	for t in tech_order:
		if g.tech_state(f, t) == 1:
			keep = Data.TECHS[t].get("spores", 0.0)
			break
	for ab in fd["abilities"]:
		if g.ability_ready(f, ab) != "" or g.res(f)[2] - Data.ABILITIES[ab]["cost"] < keep:
			continue
		if ab == "carbon_transfer":
			# pour sugar into a fed tree that is failing
			for tr in g.forest.trees:
				if tr["alive"] and tr["fed"][f] > 0 and tr["vigor"] < 0.4 and g.cast_error(f, ab, tr["pos"]) == "":
					g.cast(f, ab, tr["pos"])
					return
			continue
		if ab == "mast_year":
			var ripe: Array = g.forest.trees.filter(func(tr): return tr["alive"] and tr["fed"][f] > 0 and tr["vigor"] >= 0.5)
			if ripe.size() >= 3 and g.cast_error(f, ab, ripe[0]["pos"]) == "":
				g.cast(f, ab, ripe[0]["pos"])
				return
			continue
		if ab == "borer_swarm":
			# girdle the tree a rival feeds on hardest
			var tp := _enemy_tree()
			if tp != Vector2.INF and g.cast_error(f, ab, tp) == "":
				g.cast(f, ab, tp)
				return
			continue
		var d: Dictionary = Data.ABILITIES[ab]
		var r: float = d["radius"]
		var vs_structs: bool = ab in ["bloom", "wildfire", "giant_puffball"]
		var best := Vector2.INF
		var bn := 0.0
		var pts := []
		for u in g.units:
			if u.f != f and u.alive and u.f != Data.NEUTRAL and _sees(u.pos):
				pts.append(u.pos)
		if vs_structs:
			for s in g.structs:
				if s.f != f and s.alive and _knows(s):
					pts.append(s.pos)
		for p in pts:
			var n := 0.0
			for q in pts:
				if p.distance_to(q) < r * 0.8:
					n += 1.0
			if n > bn and g.cast_error(f, ab, p) == "":
				bn = n
				best = p
		if best != Vector2.INF and bn >= (2.0 if vs_structs else 3.0):
			g.cast(f, ab, best)
			return
