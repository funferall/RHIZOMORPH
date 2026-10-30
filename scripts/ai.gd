extends RefCounted
# One computer-run faction. Thinks once a second through the same public calls
# the HUD uses: research down a fixed order, grow a cord network toward trees and
# the enemy, keep the fruiting bodies training, gather an army at the front and
# send it in waves, raid enemy cords, defend, and cast spore actions on clumps.

const Data = preload("res://scripts/data.gd")

var g: Node
var f := 0
var fd: Dictionary
var rng := RandomNumberGenerator.new()
var think_t := 1.0
var wave := 0
var wave_size := 6
var attack_t := 170.0
var attacking := false
var raid_t := 95.0
var tech_order: Array = []


func setup(game: Node, faction: int) -> void:
	g = game
	f = faction
	fd = Data.FACTIONS[f]
	rng.seed = 99 + f * 7
	think_t = 1.0 + f * 0.33
	attack_t = 160.0 + rng.randf() * 40.0
	var t: Array = fd["techs"]
	tech_order = [t[0], t[1], t[3], t[2], t[4]]


func tick(dt: float) -> void:
	if not g.fs[f]["alive"]:
		return
	think_t -= dt
	if think_t > 0.0:
		return
	think_t = 1.0
	_research()
	_train()
	_build()
	_army()
	_abilities()


func _mine(sid := "") -> Array:
	var out := []
	for s in g.structs:
		if s.f == f and s.alive and (sid == "" or s.id == sid):
			out.append(s)
	return out


func _research() -> void:
	var h = g.heart(f)
	if h == null or h.research != "":
		return
	for t in tech_order:
		if g.tech_state(f, t) == 1:
			if g.afford(f, Data.TECHS[t]["cost"]) and g.res(f)[0] > Data.TECHS[t]["cost"][0] + 40.0:
				g.start_research(f, t)
			return


# --- building ------------------------------------------------------------------

func _build() -> void:
	var growing := 0
	for s in _mine():
		if s.built < 1.0:
			growing += 1
	if growing >= 2:
		return
	var bl: Array = fd["build"]
	var t: float = g.time
	var n_node := _mine("node").size()
	var n_bar := _mine(bl[2]).size()
	var n_tower := _mine(bl[3]).size()
	var n_elite := _mine(bl[4]).size()
	var n_lantern := _mine("lantern").size()
	var n_bracket := _mine("bracket").size()
	var n_mantle := _mine("mantle").size()
	var wants := []
	if n_bar == 0:
		wants.append(bl[2])
	if n_mantle < 1:
		wants.append("mantle")
	if n_node < 2:
		wants.append("node")
	if n_mantle < 2:
		wants.append("mantle")
	if g.has_tech(f, "spore_sacs") and n_lantern < 1:
		wants.append("lantern")
	if g.has_tech(f, "exoenzymes") and n_bracket < 1:
		wants.append("bracket")
	var elite_req: String = Data.STRUCTURES[bl[4]]["req"]
	if g.has_tech(f, elite_req) and n_elite == 0:
		wants.append(bl[4])
	if t > 110.0 and n_tower < mini(1 + int(t / 220.0), 4):
		wants.append(bl[3])
	if t > 230.0 and n_bar < 2:
		wants.append(bl[2])
	if t > 300.0 and n_mantle < 3:
		wants.append("mantle")
	if n_node < mini(3 + int(t / 80.0), 11):
		wants.append("node")
	if g.res(f)[0] > 350.0 and n_bar < 4:
		wants.append(bl[2])
	for sid in wants:
		var cost: Array = Data.STRUCTURES[sid]["cost"]
		if g.res(f)[1] < cost[1]:
			continue   # short on sugar: don't let it block the nutrient-only builds
		var spot := _spot(sid)
		if spot == Vector2.INF:
			if sid == "mantle" or sid == "bracket":
				# can't reach a free tree yet: grow toward one
				var tp := _free_tree()
				if tp != Vector2.INF:
					var ns := _spot("node", tp)
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


func _free_tree() -> Vector2:
	var h = g.heart(f)
	var best := Vector2.INF
	var bd := INF
	for i in Data.TREES.size():
		if g.mantles_on(i) >= Data.MANTLES_PER_TREE:
			continue
		var tp: Vector2 = Data.TREES[i]["pos"]
		var d: float = tp.distance_to(h.pos)
		if d < bd:
			bd = d
			best = tp
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
			power[o] = g.pop(o) * 1.0 + g.structs.filter(func(e): return e.f == o and e.alive).size() * 0.6
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
	for step in [1, 2]:
		var o: int = (f + step) % 3
		if g.fs[o]["alive"]:
			return o
	return f


func _spot(sid: String, toward := Vector2.INF) -> Vector2:
	var d: Dictionary = Data.STRUCTURES[sid]
	var h = g.heart(f)
	var cands: Array[Vector2] = []
	if sid == "mantle":
		for i in Data.TREES.size():
			var tr: Dictionary = Data.TREES[i]
			for k in 14:
				var a := TAU * k / 14.0 + rng.randf() * 0.3
				for rr in [tr["radius"] * 1.6 + 3.0, tr["radius"] * 1.6 + 5.5]:
					cands.append(tr["pos"] + Vector2(cos(a), sin(a)) * rr)
		toward = h.pos
	elif sid == "bracket":
		for tr in Data.TREES:
			for k in 14:
				var a := TAU * k / 14.0
				cands.append(tr["pos"] + Vector2(cos(a), sin(a)) * (tr["radius"] * 1.6 + 2.6))
		for lg in Data.LOGS:
			for k in 9:
				var p: Vector2 = lg[0].lerp(lg[1], k / 8.0)
				var n: Vector2 = (lg[1] - lg[0]).orthogonal().normalized()
				cands.append(p + n * (lg[2] + 2.4))
				cands.append(p - n * (lg[2] + 2.4))
		toward = h.pos
	else:
		var lr: float = g.link_range(f)
		if toward == Vector2.INF:
			if sid == "node":
				toward = _front()
			else:
				toward = h.pos.lerp(_front(), 0.4 if sid == fd["build"][3] else 0.2)
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


# --- army ----------------------------------------------------------------------

func _train() -> void:
	var bl: Array = fd["build"]
	# keep the army near a target that grows with time; past it, save for buildings
	var army: int = g.pop(f) + g.queued(f)
	var reserve := 0.0 if army < mini(4 + int(g.time / 12.0), Data.POP_CAP) else 110.0
	for s in _mine():
		if s.built < 1.0 or not s.connected or s.d.get("trains", []).is_empty():
			continue
		if s.queue.size() >= 2:
			continue
		var trains: Array = s.d["trains"]
		var uid: String = trains[0] if trains.size() == 1 or rng.randf() < 0.55 else trains[1]
		var c: Array = Data.UNITS[uid]["cost"]
		if g.res(f)[0] < c[0] + reserve:
			continue
		g.queue_train(s, uid)


func _army() -> void:
	var army := []
	for u in g.units:
		if u.f == f and u.alive and u.squad == "":
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
		if u.f == f and u.alive and u.squad == "raid" and u.target == null and u.goal == Vector2.INF:
			u.squad = ""
	# defend anything under attack
	var threat := _threat()
	if threat != Vector2.INF and not attacking:
		var idle := []
		for u in army:
			if u.target == null:
				idle.append(u)
		g.order_move(idle, threat, true)
		return
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
	# gather idle units at the front node
	var gather := []
	for u in army:
		if u.target == null and u.goal == Vector2.INF and u.pos.distance_to(rally) > 7.0:
			gather.append(u)
	if not gather.is_empty():
		g.order_move(gather, rally, true)


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
		if u.f == f or not u.alive:
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
		if s.f == r and s.alive:
			var d: float = s.pos.distance_to(from)
			if d < bd:
				bd = d
				best = s.pos
	return best


func _enemy_cord():
	var h = g.heart(f)
	var best = null
	var bd := INF
	for c in g.cords:
		if c.f != f and c.alive and c.regrow <= 0.0 and c.grow >= 1.0:
			var d: float = c.pos.distance_to(h.pos)
			if d < bd:
				bd = d
				best = c
	return best


# --- spore actions -------------------------------------------------------------

func _abilities() -> void:
	for ab in fd["abilities"]:
		if g.ability_ready(f, ab) != "":
			continue
		var d: Dictionary = Data.ABILITIES[ab]
		var r: float = d["radius"]
		var vs_structs: bool = ab in ["bloom", "wildfire", "giant_puffball"]
		var best := Vector2.INF
		var bn := 0.0
		var pts := []
		for u in g.units:
			if u.f != f and u.alive:
				pts.append(u.pos)
		if vs_structs:
			for s in g.structs:
				if s.f != f and s.alive:
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
