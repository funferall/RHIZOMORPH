extends Node3D
# The terrarium: a heightfield slab of moss, rock, litter and puddles on a
# wooden table, with cut-away soil sides and the tree trunks whose roots
# feed sugar to mycorrhizal mantles.

const Data = preload("res://scripts/data.gd")
const VRES := 3                 # height vertices per world unit (= Data.SIM_RES)
const WATER_Y := -0.45
const BOTTOM_Y := -11.0
const MOSS_SHELLS := 20

var nx := int(Data.HALF_W * 2 * VRES) + 1
var nz := int(Data.HALF_D * 2 * VRES) + 1
var heights := PackedFloat32Array()
var rock := PackedFloat32Array()
var water := PackedFloat32Array()
var wood := PackedFloat32Array()
var litter := PackedFloat32Array()
var sub_img: Image

var terrain_mat: ShaderMaterial
var moss_mat: ShaderMaterial
var sides_mat: ShaderMaterial
var water_mat: ShaderMaterial
var bark_mats: Array[ShaderMaterial] = []
var tree_parts: Array = []       # per tree: [butt MeshInstance3D, upper MeshInstance3D]
var felled := {}                 # tree index -> true: keeps its stump height

var _n_base := FastNoiseLite.new()
var _n_mound := FastNoiseLite.new()
var _n_rough := FastNoiseLite.new()
var _n_litter := FastNoiseLite.new()


func build(seed: int) -> void:
	for n in [_n_base, _n_mound, _n_rough, _n_litter]:
		n.seed = seed
		seed += 17
	_n_base.frequency = 0.035
	_n_mound.frequency = 0.16
	_n_mound.fractal_octaves = 3
	_n_rough.frequency = 0.6
	_n_litter.frequency = 0.09
	_gen_fields()
	_make_sub_image()


func attach_visuals(myc_texture: Texture2D) -> void:
	_build_terrain(myc_texture)
	_build_moss(myc_texture)
	_build_sides(myc_texture)
	_build_water()
	_build_table()
	_build_trees()


# --- fields ------------------------------------------------------------------

func _gen_fields() -> void:
	var count := nx * nz
	heights.resize(count)
	rock.resize(count)
	water.resize(count)
	wood.resize(count)
	litter.resize(count)
	# the open floor everywhere, then each feature stamps only its own patch
	for j in nz:
		var z := -Data.HALF_D + float(j) / VRES
		for i in nx:
			var x := -Data.HALF_W + float(i) / VRES
			var k := j * nx + i
			var h := _n_base.get_noise_2d(x, z) * 1.3
			var mound := _n_mound.get_noise_2d(x, z)
			h += maxf(mound, -0.2) * 0.75
			if h < 0.0:
				h = -0.3 * (1.0 - exp(h / 0.3))   # only the puddles dip below the waterline
			heights[k] = h
			rock[k] = 0.0
			water[k] = 0.0
			wood[k] = 0.0
			litter[k] = clampf(_n_litter.get_noise_2d(x, z) * 1.6 - 0.15, 0.0, 1.0) * 0.6
	# the stream: a channel along a polyline (cut before the rocks and logs that cross it)
	for si in Data.STREAM.size() - 1:
		var a: Vector2 = Data.STREAM[si]
		var b: Vector2 = Data.STREAM[si + 1]
		var reach := Data.STREAM_W * 2.2
		_stamp(Rect2(a, Vector2.ZERO).expand(b).grow(reach), func(k: int, p: Vector2):
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d := p.distance_to(a + ab * t) / Data.STREAM_W + _n_rough.get_noise_2d(p.x * 0.6, p.y * 0.6) * 0.2
			if d < 2.2:
				heights[k] = minf(heights[k], lerpf(heights[k], -1.4, smoothstep(2.2, 0.7, d))))
	for rk in Data.ROCKS:
		_stamp(Rect2(rk[0], Vector2.ZERO).grow(rk[1] * 1.25), func(k: int, p: Vector2):
			var d: float = p.distance_to(rk[0]) / rk[1]
			if d < 1.25:
				var rough := 0.75 + 0.5 * _n_rough.get_noise_2d(p.x, p.y)
				var bump: float = pow(maxf(1.0 - d * d, 0.0), 1.2) * rk[2] * rough
				heights[k] = maxf(heights[k], heights[k] * 0.4 + bump)
				rock[k] = maxf(rock[k], clampf((1.0 - d) * 3.0 + _n_rough.get_noise_2d(p.x * 2, p.y * 2) * 0.6, 0.0, 1.0)))
	for lg in Data.LOGS:
		var a: Vector2 = lg[0]
		var b: Vector2 = lg[1]
		var R: float = lg[2]
		_stamp(Rect2(a, Vector2.ZERO).expand(b).grow(R * 1.3), func(k: int, p: Vector2):
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < R * 1.3:
				var top := sqrt(maxf(R * R - d * d, 0.0)) * 1.05 + 0.1
				heights[k] = maxf(heights[k], top)
				wood[k] = maxf(wood[k], clampf(1.0 - d / (R * 1.3), 0.0, 1.0)))
	for pd in Data.PUDDLES:
		_stamp(Rect2(pd[0], Vector2.ZERO).grow(pd[1] * 1.7), func(k: int, p: Vector2):
			var d: float = p.distance_to(pd[0]) / pd[1]
			d += _n_rough.get_noise_2d(p.x * 0.5, p.y * 0.5) * 0.25
			if d < 1.4:
				heights[k] = lerpf(heights[k], -1.3, smoothstep(1.4, 0.55, d)))
	for tr in Data.TREES:
		var tp: Vector2 = tr["pos"]
		var rr: float = tr["radius"]
		_stamp(Rect2(tp, Vector2.ZERO).grow(rr * 5.0), func(k: int, p: Vector2):
			var d := p.distance_to(tp)
			if d < rr * 5.0:
				var ang := atan2(p.y - tp.y, p.x - tp.x)
				var ridge := pow(maxf(cos(ang * 6.0 + rr), 0.0), 6.0) * maxf(1.0 - d / (rr * 4.5), 0.0)
				heights[k] += 0.9 * exp(-pow(d / (rr * 2.0), 2.0)) + ridge * 0.9
				litter[k] = maxf(litter[k], 0.7 * (1.0 - d / (rr * 5.0))))
	for lp in Data.LITTER:
		_stamp(Rect2(lp[0], Vector2.ZERO).grow(5.0), func(k: int, p: Vector2):
			var d: float = p.distance_to(lp[0]) + _n_rough.get_noise_2d(p.x * 1.5, p.y * 1.5) * 0.8
			if d < 4.2:
				litter[k] = maxf(litter[k], smoothstep(4.2, 1.5, d))
				heights[k] += 0.3 * smoothstep(4.2, 0.5, d))
	for ah in Data.ANTHILLS:
		_stamp(Rect2(ah, Vector2.ZERO).grow(3.4), func(k: int, p: Vector2):
			var d: float = p.distance_to(ah)
			if d < 3.4:
				heights[k] = maxf(heights[k], heights[k] * 0.5 + smoothstep(3.4, 0.0, d) * 0.4))
	for sp in Data.START_POS:
		_stamp(Rect2(sp, Vector2.ZERO).grow(10.0), func(k: int, p: Vector2):
			var d: float = p.distance_to(sp)
			heights[k] = lerpf(heights[k], 0.15 + heights[k] * 0.25, smoothstep(10.0, 5.0, d)))
	for k in count:
		if heights[k] < WATER_Y + 0.08:
			water[k] = clampf((WATER_Y + 0.08 - heights[k]) * 3.0, 0.0, 1.0)


# Calls fn(index, world position) for every height vertex inside r.
func _stamp(r: Rect2, fn: Callable) -> void:
	var i0 := clampi(int((r.position.x + Data.HALF_W) * VRES), 0, nx - 1)
	var i1 := clampi(int((r.end.x + Data.HALF_W) * VRES) + 1, 0, nx - 1)
	var j0 := clampi(int((r.position.y + Data.HALF_D) * VRES), 0, nz - 1)
	var j1 := clampi(int((r.end.y + Data.HALF_D) * VRES) + 1, 0, nz - 1)
	for j in range(j0, j1 + 1):
		var z := -Data.HALF_D + float(j) / VRES
		for i in range(i0, i1 + 1):
			fn.call(j * nx + i, Vector2(-Data.HALF_W + float(i) / VRES, z))


func _make_sub_image() -> void:
	sub_img = Image.create(Data.SIM_W, Data.SIM_H, false, Image.FORMAT_RGBA8)
	for j in Data.SIM_H:
		for i in Data.SIM_W:
			var k := mini(j, nz - 1) * nx + mini(i, nx - 1)
			sub_img.set_pixel(i, j, Color(rock[k], water[k], wood[k], litter[k]))


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + Data.HALF_W) * VRES, 0.0, nx - 1.001)
	var fz := clampf((z + Data.HALF_D) * VRES, 0.0, nz - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * nx + i
	var a := lerpf(heights[k], heights[k + 1], tx)
	var b := lerpf(heights[k + nx], heights[k + nx + 1], tx)
	return lerpf(a, b, tz)


func ground_y(p: Vector2) -> float:
	return maxf(height_at(p.x, p.y), WATER_Y - 0.15)


func water_at(p: Vector2) -> float:
	var fx := clampi(int((p.x + Data.HALF_W) * VRES), 0, nx - 1)
	var fz := clampi(int((p.y + Data.HALF_D) * VRES), 0, nz - 1)
	return water[fz * nx + fx]


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.3
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func in_bounds(p: Vector2, margin := 0.5) -> bool:
	return absf(p.x) < Data.HALF_W - margin and absf(p.y) < Data.HALF_D - margin


# --- meshes ------------------------------------------------------------------

func _grid_mesh(step: int) -> ArrayMesh:
	var cx := (nx - 1) / step + 1
	var cz := (nz - 1) / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(cx * cz)
	norms.resize(cx * cz)
	uvs.resize(cx * cz)
	for j in cz:
		for i in cx:
			var x := -Data.HALF_W + float(i * step) / VRES
			var z := -Data.HALF_D + float(j * step) / VRES
			var k := j * cx + i
			verts[k] = Vector3(x, heights[(j * step) * nx + i * step], z)
			norms[k] = normal_at(x, z)
			uvs[k] = Vector2(float(i) / (cx - 1), float(j) / (cz - 1))
	var idx := PackedInt32Array()
	idx.resize((cx - 1) * (cz - 1) * 6)
	var o := 0
	for j in cz - 1:
		for i in cx - 1:
			var a := j * cx + i
			var b := a + 1
			var c := a + cx
			var d := c + 1
			idx[o] = a; idx[o + 1] = b; idx[o + 2] = d
			idx[o + 3] = a; idx[o + 4] = d; idx[o + 5] = c
			o += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _sub_texture() -> ImageTexture:
	return ImageTexture.create_from_image(sub_img)


func _build_terrain(myc_texture: Texture2D) -> void:
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("myc_tex", myc_texture)
	terrain_mat.set_shader_parameter("half_size", Vector2(Data.HALF_W, Data.HALF_D))
	terrain_mat.set_shader_parameter("sub_tex", _sub_texture())
	_set_faction_tints(terrain_mat, 0.4)
	var mi := MeshInstance3D.new()
	mi.mesh = _grid_mesh(1)
	mi.material_override = terrain_mat
	add_child(mi)


func _set_faction_tints(mat: ShaderMaterial, amt: float) -> void:
	for f in 3:
		var c: Color = Data.FACTIONS[f]["color"]
		var t := Color(1, 1, 1).lerp(c, amt)
		mat.set_shader_parameter("fcol%d" % f, Vector3(t.r, t.g, t.b))


func _build_moss(myc_texture: Texture2D) -> void:
	moss_mat = ShaderMaterial.new()
	moss_mat.shader = load("res://shaders/moss.gdshader")
	moss_mat.set_shader_parameter("myc_tex", myc_texture)
	moss_mat.set_shader_parameter("half_size", Vector2(Data.HALF_W, Data.HALF_D))
	moss_mat.set_shader_parameter("sub_tex", _sub_texture())
	moss_mat.set_shader_parameter("shells", float(MOSS_SHELLS))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _grid_mesh(2)
	mm.instance_count = MOSS_SHELLS
	for i in MOSS_SHELLS:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = moss_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-Data.HALF_W, -3, -Data.HALF_D), Vector3(Data.HALF_W * 2, 10, Data.HALF_D * 2))
	add_child(mmi)


func _build_sides(myc_texture: Texture2D) -> void:
	sides_mat = ShaderMaterial.new()
	sides_mat.shader = load("res://shaders/sides.gdshader")
	sides_mat.set_shader_parameter("myc_tex", myc_texture)
	sides_mat.set_shader_parameter("half_size", Vector2(Data.HALF_W, Data.HALF_D))
	sides_mat.set_shader_parameter("bottom_y", BOTTOM_Y)
	_set_faction_tints(sides_mat, 0.7)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# four faces: walk each edge of the height grid
	var edges := [
		[Vector2i(0, nz - 1), Vector2i(1, 0), nx, Vector3(0, 0, 1)],
		[Vector2i(nx - 1, 0), Vector2i(-1, 0), nx, Vector3(0, 0, -1)],
		[Vector2i(0, 0), Vector2i(0, 1), nz, Vector3(-1, 0, 0)],
		[Vector2i(nx - 1, nz - 1), Vector2i(0, -1), nz, Vector3(1, 0, 0)],
	]
	for e in edges:
		var start: Vector2i = e[0]
		var dir: Vector2i = e[1]
		var n: int = e[2]
		var norm: Vector3 = e[3]
		for s in n - 1:
			var g0 := start + dir * s
			var g1 := start + dir * (s + 1)
			var p0 := Vector3(-Data.HALF_W + float(g0.x) / VRES, heights[g0.y * nx + g0.x], -Data.HALF_D + float(g0.y) / VRES)
			var p1 := Vector3(-Data.HALF_W + float(g1.x) / VRES, heights[g1.y * nx + g1.x], -Data.HALF_D + float(g1.y) / VRES)
			var b0 := Vector3(p0.x, BOTTOM_Y, p0.z)
			var b1 := Vector3(p1.x, BOTTOM_Y, p1.z)
			for v in [p0, p1, b1, p0, b1, b0]:
				st.set_normal(norm)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = sides_mat
	add_child(mi)


func _build_water() -> void:
	# one sheet at the waterline; the terrain hides it everywhere but the puddles
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("half_size", Vector2(Data.HALF_W, Data.HALF_D))
	water_mat = mat
	var pm := PlaneMesh.new()
	pm.size = Vector2(Data.HALF_W * 2.0, Data.HALF_D * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, WATER_Y, 0)
	add_child(mi)


func _build_table() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/table.gdshader")
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position.y = BOTTOM_Y
	add_child(mi)


func _build_trees() -> void:
	for tr in Data.TREES:
		var kind := 0
		match tr["kind"]:
			"birch": kind = 1
			"hemlock": kind = 2
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/bark.gdshader")
		mat.set_shader_parameter("kind", kind)
		bark_mats.append(mat)
		var p: Vector2 = tr["pos"]
		# only the butt casts a shadow, so the low sun doesn't stripe the board
		var parts := _trunk_meshes(tr["radius"], 46.0, kind, 7.0)
		tree_parts.append([])
		for i in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = parts[i]
			mi.material_override = mat
			mi.position = Vector3(p.x, height_at(p.x, p.y) - 0.6, p.y)
			if i == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			tree_parts[-1].append(mi)


func _trunk_meshes(r: float, h: float, kind: int, split_y: float) -> Array[ArrayMesh]:
	var sts: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	for s in sts:
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 40
	var rings := 48
	var pts := []
	for j in rings + 1:
		var t := float(j) / rings
		var y := pow(t, 1.6) * h
		var row := []
		for i in segs + 1:
			var a := TAU * i / segs
			var flare := exp(-y / (r * 0.9)) * (0.5 if kind == 1 else 1.2)
			var butt := pow(maxf(cos(a * 6.0 + r), 0.0), 3.0)
			var rad := r * (1.0 - t * 0.25) * (1.0 + flare * (0.35 + 0.9 * butt))
			rad *= 1.0 + 0.04 * sin(a * 3.0 + y * 0.4)
			var lean := Vector2(sin(y * 0.07) * 0.6, cos(y * 0.05) * 0.4) * (y / h)
			row.append(Vector3(cos(a) * rad + lean.x, y, sin(a) * rad + lean.y))
		pts.append(row)
	for j in rings:
		var p0: Vector3 = pts[j][0]
		var s := sts[0 if p0.y < split_y else 1]
		for i in segs:
			var p00: Vector3 = pts[j][i]
			var p10: Vector3 = pts[j][i + 1]
			var p01: Vector3 = pts[j + 1][i]
			var p11: Vector3 = pts[j + 1][i + 1]
			for v in [p00, p10, p11, p00, p11, p01]:
				s.set_normal(Vector3(v.x, 0.0, v.z).normalized())
				s.add_vertex(v)
	return [sts[0].commit(), sts[1].commit()]


func set_cut_height(cut: float) -> void:
	for i in bark_mats.size():
		if not felled.has(i):
			bark_mats[i].set_shader_parameter("cut_h", cut)


# A felled tree: the trunk snaps to a ragged stump and a log lies along dir.
func fell_tree(i: int, dir: Vector2, length: float) -> void:
	felled[i] = true
	var tr: Dictionary = Data.TREES[i]
	var p: Vector2 = tr["pos"]
	bark_mats[i].set_shader_parameter("cut_h", height_at(p.x, p.y) + 1.6)
	tree_parts[i][1].visible = false
	var r: float = tr["radius"]
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.75
	cm.bottom_radius = r * 0.95
	cm.height = length - r * 1.6
	cm.radial_segments = 24
	cm.rings = 8
	var mat: ShaderMaterial = bark_mats[i].duplicate()
	mat.set_shader_parameter("cut_h", 999.0)
	mat.set_shader_parameter("dead", 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	var mid := p + dir * (r * 1.6 + length) * 0.5
	var at := Vector3(mid.x, height_at(mid.x, mid.y) + r * 0.6, mid.y)
	add_child(mi)
	# lay the cylinder's axis along dir
	mi.look_at_from_position(at, at + Vector3(dir.x, 0, dir.y), Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
