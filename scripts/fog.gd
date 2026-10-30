extends RefCounted
# Fog of war on the 1 m coarse grid. Each court sees around its units and
# structures; the Court and the Hollow also see wherever their mycelium runs;
# the Court hears through the roots: every tree it feeds and that tree's
# neighbours on the root graph (two hops with Root Signalling). The Choir has
# no network to see through - only its thralls, its structures, and the brief
# view from a sporulating thrall's summit. The player's view is baked into a
# texture for the ground shaders and the minimap; the AI does not use fog yet.

const Data = preload("res://scripts/data.gd")

const W := Data.COARSE_W
const H := Data.COARSE_H
const SEEN := 1
const VIS := 2

var g: Node
var enabled := not OS.get_cmdline_user_args().has("--nofog")
var grid: Array[PackedByteArray] = []    # per faction: bit SEEN, bit VIS
var reveals: Array[Dictionary] = []       # f, pos, r, t
var tex := ImageTexture.new()             # ground and minimap: r = 0 unseen, ~0.45 explored, 1 visible
var _img := Image.create(W, H, false, Image.FORMAT_R8)
var _t := 0.0


func setup(game: Node) -> void:
	g = game
	for f in 3:
		var b := PackedByteArray()
		b.resize(W * H)
		grid.append(b)
	tex.set_image(_img)
	update()


func reveal(f: int, p: Vector2, r: float, secs: float) -> void:
	reveals.append({"f": f, "pos": p, "r": r, "t": secs})


func tick(dt: float) -> void:
	for rv in reveals:
		rv["t"] -= dt
	reveals = reveals.filter(func(rv): return rv["t"] > 0.0)
	_t -= dt
	if _t <= 0.0:
		_t = 0.25
		update()


func _idx(p: Vector2) -> int:
	var cx := clampi(int(p.x + Data.HALF_W), 0, W - 1)
	var cz := clampi(int(p.y + Data.HALF_D), 0, H - 1)
	return cz * W + cx


func visible(f: int, p: Vector2) -> bool:
	return not enabled or f < 0 or f > 2 or grid[f][_idx(p)] & VIS != 0


func seen(f: int, p: Vector2) -> bool:
	return not enabled or f < 0 or f > 2 or grid[f][_idx(p)] & SEEN != 0


func _disc(b: PackedByteArray, p: Vector2, r: float) -> void:
	var x0 := clampi(int(p.x - r + Data.HALF_W), 0, W - 1)
	var x1 := clampi(int(p.x + r + Data.HALF_W), 0, W - 1)
	var z0 := clampi(int(p.y - r + Data.HALF_D), 0, H - 1)
	var z1 := clampi(int(p.y + r + Data.HALF_D), 0, H - 1)
	var r2 := r * r
	for z in range(z0, z1 + 1):
		var dz := z - Data.HALF_D + 0.5 - p.y
		for x in range(x0, x1 + 1):
			var dx := x - Data.HALF_W + 0.5 - p.x
			if dx * dx + dz * dz <= r2:
				b[z * W + x] = SEEN | VIS


func sight(e) -> float:
	if e.d.has("sight"):
		return e.d["sight"]
	if e.kind == g.STRUCT:
		return e.d["myc"] + 2.0
	return 12.0 if e.d.get("elite", false) else 10.0


func update() -> void:
	for f in 3:
		var b := grid[f]
		# last frame's sight fades to explored
		for i in b.size():
			b[i] &= SEEN
		if not g.fs[f]["alive"]:
			continue
		for u in g.units:
			if u.alive and u.f == f:
				_disc(b, u.pos, sight(u))
		for s in g.structs:
			if s.alive and s.f == f:
				_disc(b, s.pos, sight(s))
		for rv in reveals:
			if rv["f"] == f:
				_disc(b, rv["pos"], rv["r"])
		var eco: String = g.econ(f)
		if eco != "parasite" and g.myc.ok and not g.myc.coarse.is_empty():
			var cz: PackedFloat32Array = g.myc.coarse
			for i in W * H:
				if cz[i * 4 + f] > 0.25:
					b[i] = SEEN | VIS
		if eco == "mycorrhizal":
			_root_sight(f, b)
	_bake()


# The Court hears through the roots: fed trees, and their neighbours one hop out.
func _root_sight(f: int, b: PackedByteArray) -> void:
	var trees: Array = g.forest.trees
	var hops := 2 if g.has_tech(f, "root_signalling") else 1
	var lit := {}
	var front := []
	for t in trees:
		if t["fed"][f] > 0 and t["alive"]:
			lit[t["i"]] = true
			front.append(t["i"])
	for h in hops:
		var nxt := []
		for i in front:
			for li in trees[i]["links"]:
				if not lit.has(li):
					lit[li] = true
					nxt.append(li)
		front = nxt
	for i in lit:
		_disc(b, trees[i]["pos"], trees[i]["roots"])


func _bake() -> void:
	var f: int = g.player
	if f < 0 or f > 2:
		return
	var b := grid[f]
	var data := PackedByteArray()
	data.resize(W * H)
	for i in W * H:
		var v := b[i]
		var k := 255 if v & VIS else (115 if v & SEEN else 0)
		data[i] = k
	_img.set_data(W, H, false, Image.FORMAT_R8, data)
	tex.update(_img)
