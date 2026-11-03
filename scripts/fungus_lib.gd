extends RefCounted
# Procedural fruiting bodies. Every species is built from lathed profiles
# (stems, caps, cups, funnels, veils) plus a few hand-built parts (earthstar
# rays, legs), split into surfaces that share materials from fungus.gdshader.

const FUNGUS_SHADER := preload("res://shaders/fungus.gdshader")
const LEG_SHADER := preload("res://shaders/legs.gdshader")
const CepBulwark := preload("res://scripts/cep_bulwark.gd")
const Wartling := preload("res://scripts/wartling.gd")
const Angel := preload("res://scripts/destroying_angel.gd")
const Webcap := preload("res://scripts/webcap.gd")
const InkcapBed := preload("res://scripts/inkcap_bed.gd")
const RotBracket := preload("res://scripts/rot_bracket.gd")
const Runner := preload("res://scripts/candlesnuff_runner.gd")
const CoralBinder := preload("res://scripts/coral_binder.gd")
const Sniper := preload("res://scripts/pilobolus_sniper.gd")
const Bomber := preload("res://scripts/puffball_bomber.gd")
const Slinger := preload("res://scripts/elf_cup_slinger.gd")
const Bruiser := preload("res://scripts/morel_bruiser.gd")
const Spitter := preload("res://scripts/muscarine_spitter.gd")
const Beetle := preload("res://scripts/whitecoat_beetle.gd")
const Sailwing := preload("res://scripts/mycena_sailwing.gd")

static var _meshes := {}
static var _mats := {}
static var _heights := {}

# species that read too small next to their footprint get scaled at build time
const SPECIES_SCALE := {"armillaria": 1.6, "chanterelle": 1.5, "mycena_lantern": 1.4, "pilobolus": 1.4, "earthstar": 1.2, "birds_nest": 1.4, "bracket": 1.2}

const MATS := {
	"stem_white": {"base": Color(0.9, 0.88, 0.8), "rough": 0.75, "sss": 0.45, "pattern": 8, "pscale": 18.0, "accent": Color(0.82, 0.8, 0.72)},
	"agaric_cap": {"base": Color(0.78, 0.07, 0.04), "accent": Color(0.97, 0.94, 0.86), "pattern": 1, "pscale": 5.5, "bump": 0.035, "rough": 0.32, "sss": 0.25},
	"gill": {"base": Color(0.93, 0.9, 0.82), "accent": Color(0.78, 0.74, 0.66), "pattern": 4, "pscale": 46.0, "rough": 0.8, "sss": 0.5},
	"deathcap": {"base": Color(0.55, 0.58, 0.34), "accent": Color(0.75, 0.74, 0.5), "pattern": 8, "pscale": 9.0, "rough": 0.3, "sss": 0.3},
	"angel": {"base": Color(0.96, 0.96, 0.93), "rough": 0.3, "sss": 0.6},
	"clathrus": {"base": Color(0.9, 0.12, 0.06), "accent": Color(0.9, 0.16, 0.08), "pattern": 3, "pscale": 2.4, "rough": 0.4, "sss": 0.5},
	"volva": {"base": Color(0.88, 0.85, 0.78), "rough": 0.8, "sss": 0.3},
	"honey_cap": {"base": Color(0.78, 0.54, 0.22), "accent": Color(0.33, 0.21, 0.09), "pattern": 6, "pscale": 9.0, "rough": 0.45, "sss": 0.35},
	"honey_stem": {"base": Color(0.78, 0.66, 0.46), "rough": 0.7, "sss": 0.3, "pattern": 8, "pscale": 12.0, "accent": Color(0.6, 0.45, 0.28)},
	"chanterelle": {"base": Color(1.0, 0.66, 0.12), "accent": Color(1.0, 0.8, 0.35), "pattern": 4, "pscale": 30.0, "rough": 0.5, "sss": 0.6, "glow": 0.12, "glow_col": Color(1.0, 0.6, 0.1)},
	"morel_cap": {"base": Color(0.17, 0.11, 0.06), "accent": Color(0.66, 0.52, 0.32), "pattern": 2, "pscale": 7.5, "bump": 0.07, "rough": 0.6, "sss": 0.2},
	"morel_cap_big": {"base": Color(0.13, 0.085, 0.05), "accent": Color(0.62, 0.48, 0.28), "pattern": 2, "pscale": 3.0, "bump": 0.16, "rough": 0.6, "sss": 0.2},
	"morel_cap_small": {"base": Color(0.17, 0.11, 0.06), "accent": Color(0.6, 0.47, 0.3), "pattern": 2, "pscale": 15.0, "bump": 0.012, "rough": 0.6, "sss": 0.2},
	"morel_stem": {"base": Color(0.9, 0.84, 0.7), "rough": 0.8, "sss": 0.35},
	"elfcup": {"base": Color(0.9, 0.06, 0.05), "rough": 0.35, "sss": 0.6},
	"elfcup_out": {"base": Color(0.92, 0.72, 0.66), "rough": 0.9, "sss": 0.3},
	"earthstar": {"base": Color(0.6, 0.48, 0.34), "accent": Color(0.42, 0.32, 0.22), "pattern": 8, "pscale": 14.0, "rough": 0.85, "sss": 0.2},
	"earthstar_ball": {"base": Color(0.62, 0.53, 0.42), "accent": Color(0.48, 0.4, 0.3), "pattern": 7, "pscale": 14.0, "bump": 0.01, "rough": 0.8},
	"cordyceps": {"base": Color(1.0, 0.48, 0.08), "accent": Color(1.0, 0.7, 0.3), "pattern": 7, "pscale": 20.0, "rough": 0.5, "sss": 0.6, "glow": 0.18, "glow_col": Color(1.0, 0.4, 0.05)},
	"gleba": {"base": Color(0.17, 0.16, 0.08), "accent": Color(0.36, 0.33, 0.16), "pattern": 5, "pscale": 7.0, "bump": 0.03, "rough": 0.25, "sss": 0.1},
	"veil": {"base": Color(0.95, 0.94, 0.88), "accent": Color(0.96, 0.95, 0.9), "pattern": 3, "pscale": 5.5, "rough": 0.6, "sss": 0.7},
	"veil_big": {"base": Color(0.92, 0.9, 0.84), "accent": Color(0.93, 0.92, 0.86), "pattern": 3, "pscale": 2.2, "rough": 0.6, "sss": 0.7},
	"puffball": {"base": Color(0.92, 0.9, 0.84), "accent": Color(0.76, 0.73, 0.66), "pattern": 7, "pscale": 9.0, "bump": 0.02, "rough": 0.75, "sss": 0.35},
	"nest": {"base": Color(0.5, 0.37, 0.21), "accent": Color(0.33, 0.24, 0.13), "pattern": 8, "pscale": 30.0, "rough": 0.9},
	"egg": {"base": Color(0.78, 0.78, 0.74), "rough": 0.4, "sss": 0.3},
	"glass": {"base": Color(0.84, 0.9, 0.72), "pattern": 9, "rough": 0.1, "sss": 0.9, "glow": 0.08, "glow_col": Color(0.7, 0.9, 0.5)},
	"black": {"base": Color(0.05, 0.05, 0.05), "rough": 0.2},
	"mycena": {"base": Color(0.72, 0.86, 0.52), "rough": 0.4, "sss": 0.8, "glow": 1.4, "glow_col": Color(0.45, 1.0, 0.3)},
	"mycena_white": {"base": Color(0.86, 0.84, 0.78), "rough": 0.5, "sss": 0.8, "glow": 0.25, "glow_col": Color(0.6, 1.0, 0.5)},
	"bracket": {"base": Color(0.24, 0.1, 0.04), "accent": Color(0.62, 0.4, 0.17), "pattern": 10, "pscale": 9.0, "bump": 0.03, "rough": 0.35, "sss": 0.15},
	"bracket_pore": {"base": Color(0.86, 0.8, 0.66), "rough": 0.9, "sss": 0.2},
	"tail_dark": {"base": Color(0.16, 0.18, 0.21), "accent": Color(0.25, 0.25, 0.27), "pattern": 8, "pscale": 22.0, "rough": 0.88},
	"tail_slate": {"base": Color(0.29, 0.32, 0.35), "accent": Color(0.38, 0.39, 0.39), "pattern": 8, "pscale": 23.0, "rough": 0.9},
	"tail_rust": {"base": Color(0.48, 0.22, 0.16), "accent": Color(0.61, 0.33, 0.22), "pattern": 8, "pscale": 24.0, "rough": 0.86},
	"tail_tan": {"base": Color(0.68, 0.48, 0.32), "accent": Color(0.76, 0.58, 0.4), "pattern": 8, "pscale": 22.0, "rough": 0.9},
	"tail_cream": {"base": Color(0.92, 0.85, 0.7), "accent": Color(0.98, 0.92, 0.79), "pattern": 8, "pscale": 18.0, "rough": 0.86, "sss": 0.25},
	"wood": {"base": Color(0.24, 0.16, 0.1), "accent": Color(0.14, 0.09, 0.06), "pattern": 8, "pscale": 10.0, "rough": 0.9},
	"inkcap": {"base": Color(0.93, 0.91, 0.86), "accent": Color(0.4, 0.34, 0.28), "pattern": 6, "pscale": 11.0, "bump": 0.03, "rough": 0.7, "sss": 0.5},
	"chitin": {"base": Color(0.09, 0.06, 0.05), "rough": 0.3, "accent": Color(0.2, 0.12, 0.08), "pattern": 8, "pscale": 20.0},
	"ant_red": {"base": Color(0.45, 0.14, 0.06), "rough": 0.3, "accent": Color(0.3, 0.08, 0.04), "pattern": 8, "pscale": 24.0},
	"ant_black": {"base": Color(0.05, 0.04, 0.035), "rough": 0.22},
	"beetle": {"base": Color(0.17, 0.1, 0.05), "accent": Color(0.1, 0.06, 0.03), "pattern": 4, "pscale": 40.0, "rough": 0.18},
	"fly": {"base": Color(0.1, 0.17, 0.12), "accent": Color(0.05, 0.08, 0.06), "pattern": 8, "pscale": 18.0, "rough": 0.15, "sss": 0.1},
	"fly_eye": {"base": Color(0.62, 0.08, 0.04), "rough": 0.2, "sss": 0.4},
	"wing": {"base": Color(0.78, 0.82, 0.86), "rough": 0.08, "sss": 0.95},
	"springtail": {"base": Color(0.36, 0.4, 0.48), "accent": Color(0.25, 0.27, 0.33), "pattern": 8, "pscale": 30.0, "rough": 0.5, "sss": 0.3},
	"stag": {"base": Color(0.075, 0.05, 0.04), "accent": Color(0.14, 0.09, 0.06), "pattern": 8, "pscale": 34.0, "rough": 0.14},
	"mandible": {"base": Color(0.46, 0.17, 0.07), "accent": Color(0.3, 0.1, 0.04), "pattern": 8, "pscale": 40.0, "rough": 0.18, "sss": 0.15},
	"emerald": {"base": Color(0.02, 0.2, 0.08), "accent": Color(0.06, 0.38, 0.22), "pattern": 8, "pscale": 70.0, "rough": 0.06, "sss": 0.05},
	"hypha": {"base": Color(0.94, 0.92, 0.86), "rough": 0.95, "sss": 0.7},
	"stalk": {"base": Color(0.5, 0.33, 0.2), "accent": Color(0.35, 0.22, 0.13), "pattern": 8, "pscale": 50.0, "rough": 0.75, "sss": 0.2},
	"ascoma": {"base": Color(0.86, 0.82, 0.7), "accent": Color(0.55, 0.5, 0.4), "pattern": 7, "pscale": 40.0, "bump": 0.01, "rough": 0.95, "sss": 0.4},
	"stalk_pink": {"base": Color(0.8, 0.52, 0.4), "rough": 0.6, "sss": 0.45},
	"perithecia": {"base": Color(0.92, 0.82, 0.55), "accent": Color(0.66, 0.5, 0.26), "pattern": 7, "pscale": 30.0, "bump": 0.025, "rough": 0.7, "sss": 0.4},
	"truffle": {"base": Color(0.12, 0.08, 0.06), "accent": Color(0.26, 0.19, 0.13), "pattern": 7, "pscale": 22.0, "bump": 0.06, "rough": 0.9},
	"webcap": {"base": Color(0.24, 0.1, 0.42), "accent": Color(0.36, 0.19, 0.56), "pattern": 8, "pscale": 14.0, "rough": 0.5, "sss": 0.4},
	"webcap_stem": {"base": Color(0.64, 0.54, 0.74), "rough": 0.7, "sss": 0.4},
	"cortina": {"base": Color(0.84, 0.78, 0.92), "rough": 0.9, "sss": 0.8},
	"milkcap": {"base": Color(0.88, 0.45, 0.15), "accent": Color(0.68, 0.27, 0.08), "pattern": 10, "pscale": 30.0, "rough": 0.45, "sss": 0.4},
	"milk_stem": {"base": Color(0.95, 0.63, 0.36), "rough": 0.6, "sss": 0.3},
	"latex": {"base": Color(0.98, 0.55, 0.18), "rough": 0.12, "sss": 0.9},
	"sapling": {"base": Color(0.86, 0.85, 0.8), "accent": Color(0.1, 0.09, 0.09), "pattern": 6, "pscale": 18.0, "rough": 0.7},
	"leaf": {"base": Color(0.3, 0.5, 0.13), "accent": Color(0.44, 0.62, 0.2), "pattern": 7, "pscale": 8.0, "rough": 0.7, "sss": 0.6},
	"oyster": {"base": Color(0.8, 0.78, 0.74), "accent": Color(0.62, 0.6, 0.57), "pattern": 10, "pscale": 22.0, "rough": 0.5, "sss": 0.5},
	"panther_cap": {"base": Color(0.44, 0.31, 0.19), "accent": Color(0.95, 0.93, 0.86), "pattern": 1, "pscale": 6.5, "bump": 0.03, "rough": 0.4, "sss": 0.25},
	"yellow_morel": {"base": Color(0.36, 0.27, 0.13), "accent": Color(0.86, 0.76, 0.52), "pattern": 2, "pscale": 6.5, "bump": 0.07, "rough": 0.6, "sss": 0.25},
	"stinkhorn_cap": {"base": Color(0.11, 0.12, 0.06), "accent": Color(0.27, 0.26, 0.11), "pattern": 5, "pscale": 8.0, "rough": 0.12, "sss": 0.1},
	"stinkhorn_stem": {"base": Color(0.95, 0.93, 0.88), "accent": Color(0.86, 0.83, 0.77), "pattern": 7, "pscale": 26.0, "bump": 0.012, "rough": 0.8, "sss": 0.5},
	"honey_dark": {"base": Color(0.3, 0.17, 0.07), "accent": Color(0.14, 0.08, 0.04), "pattern": 6, "pscale": 9.0, "rough": 0.5, "sss": 0.3},
	"rhizo": {"base": Color(0.03, 0.022, 0.018), "accent": Color(0.1, 0.07, 0.05), "pattern": 8, "pscale": 40.0, "rough": 0.45},
	"root": {"base": Color(0.22, 0.15, 0.09), "accent": Color(0.12, 0.08, 0.05), "pattern": 8, "pscale": 22.0, "bump": 0.03, "rough": 0.9},
	"cocoon": {"base": Color(0.86, 0.82, 0.7), "accent": Color(0.7, 0.65, 0.52), "pattern": 8, "pscale": 30.0, "rough": 0.8, "sss": 0.5},
	"isaria": {"base": Color(0.97, 0.96, 0.92), "accent": Color(0.88, 0.86, 0.8), "pattern": 7, "pscale": 40.0, "bump": 0.02, "rough": 0.95, "sss": 0.6},
	"earth": {"base": Color(0.24, 0.17, 0.11), "accent": Color(0.33, 0.24, 0.15), "pattern": 7, "pscale": 12.0, "bump": 0.02, "rough": 0.95},
}


static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	if key == "leg":
		m.shader = LEG_SHADER
	else:
		var d: Dictionary = MATS[key]
		m.shader = FUNGUS_SHADER
		var b: Color = d["base"]
		var a: Color = d.get("accent", Color(1, 1, 1))
		var g: Color = d.get("glow_col", Color(0, 0, 0))
		m.set_shader_parameter("base_col", Vector3(b.r, b.g, b.b))
		m.set_shader_parameter("accent_col", Vector3(a.r, a.g, a.b))
		m.set_shader_parameter("pattern", d.get("pattern", 0))
		m.set_shader_parameter("pscale", d.get("pscale", 6.0))
		m.set_shader_parameter("bump", d.get("bump", 0.0))
		m.set_shader_parameter("rough", d.get("rough", 0.6))
		m.set_shader_parameter("sss", d.get("sss", 0.3))
		m.set_shader_parameter("glow", d.get("glow", 0.0))
		m.set_shader_parameter("glow_col", Vector3(g.r, g.g, g.b))
	_mats[key] = m
	return m


static func height_of(id: String) -> float:
	if not _heights.has(id):
		mesh(id)
	return _heights.get(id, 2.0)


# --- builder -----------------------------------------------------------------

class B:
	var tools := {}
	var rng := RandomNumberGenerator.new()
	var top := 0.0
	var sc := 1.0

	func st(key: String) -> SurfaceTool:
		if not tools.has(key):
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = s
		return tools[key]

	# prof: (radius, y) points; lathed around Y, placed by xf.
	func lathe(key: String, prof: PackedVector2Array, segs: int, xf: Transform3D, a0 := 0.0, a1 := TAU, col := Color(0, 0, 0, 1), wave := 0.0) -> void:
		var s := st(key)
		var n := prof.size()
		var nb := xf.basis.inverse().transposed()
		var n2: Array[Vector2] = []
		for i in n:
			var t := prof[mini(i + 1, n - 1)] - prof[maxi(i - 1, 0)]
			n2.append(Vector2(t.y, -t.x).normalized())
		for i in n - 1:
			for k in segs:
				var aa := a0 + (a1 - a0) * k / segs
				var ab := a0 + (a1 - a0) * (k + 1) / segs
				var quad := [[i, aa, k], [i, ab, k + 1], [i + 1, ab, k + 1], [i, aa, k], [i + 1, ab, k + 1], [i + 1, aa, k]]
				for q in quad:
					var pi: int = q[0]
					var ang: float = q[1]
					var pr := prof[pi]
					var nn := n2[pi]
					var ripple := 1.0 + wave * (0.65 * sin(ang * 5.0 + 0.6) + 0.35 * sin(ang * 9.0 - 0.4))
					var p3 := Vector3(cos(ang) * pr.x * ripple, pr.y + wave * pr.x * 0.45 * sin(ang * 5.0 + 0.6), sin(ang) * pr.x * ripple)
					var nrm := Vector3(cos(ang) * nn.x, nn.y, sin(ang) * nn.x)
					s.set_color(col)
					s.set_uv(Vector2(float(q[2]) / segs, float(pi) / (n - 1)))
					s.set_normal((nb * nrm).normalized())
					var w := (xf * p3) * sc
					s.add_vertex(w)
					top = maxf(top, w.y)

	func tube(key: String, a: Vector3, b: Vector3, r0: float, r1: float, segs: int, ca: Color, cb: Color) -> void:
		var s := st(key)
		var d := (b - a).normalized()
		var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := d.cross(u)
		for k in segs:
			var t0 := TAU * k / segs
			var t1 := TAU * (k + 1) / segs
			var o0 := u * cos(t0) + v * sin(t0)
			var o1 := u * cos(t1) + v * sin(t1)
			var verts := [[a + o0 * r0, o0, ca], [a + o1 * r0, o1, ca], [b + o1 * r1, o1, cb],
				[a + o0 * r0, o0, ca], [b + o1 * r1, o1, cb], [b + o0 * r1, o0, cb]]
			for i in verts.size():
				var q: Array = verts[i]
				s.set_color(q[2])
				# UVs too, so a lathe can share this surface whichever comes first
				s.set_uv(Vector2(float(k) / segs, 0.0 if i in [0, 1, 3] else 1.0))
				s.set_normal(q[1])
				s.add_vertex(q[0] * sc)

	func commit() -> ArrayMesh:
		var m := ArrayMesh.new()
		for key in tools:
			var s: SurfaceTool = tools[key]
			s.commit(m)
			m.surface_set_name(m.get_surface_count() - 1, key)
		return m


# profile helpers ---------------------------------------------------------------

static func stem_prof(h: float, rb: float, rt: float, bulb := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		p.append(Vector2(lerpf(rb, rt, t) + bulb * exp(-t * 7.0), h * t))
	return p


static func dome_prof(R: float, H: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(Vector2(R * 0.9, -H * 0.08))
	for i in 11:
		var th := PI * 0.5 * i / 10.0
		p.append(Vector2(R * cos(th) + 0.0001, H * sin(th)))
	return p


static func gill_prof(R: float, sr: float, H: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(sr, H * 0.15), Vector2(R * 0.55, H * 0.02), Vector2(R * 0.9, -H * 0.08)])


static func bell_prof(R: float, H: float, flare := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(Vector2(R * (1.0 + flare), 0.0))
	for i in range(1, 11):
		var t := i / 10.0
		p.append(Vector2(R * pow(1.0 - t, 0.5) + 0.0001, H * t))
	return p


static func egg_prof(R: float, H: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		var r := R * pow(maxf(1.0 - t, 0.0), 0.55) * (0.78 + 0.32 * sin(t * PI))
		p.append(Vector2(r + 0.0001, H * t))
	return p


static func sphere_prof(R: float, squash := 1.0, base := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 13:
		var th := -PI * 0.5 + PI * i / 12.0
		p.append(Vector2(R * cos(th) + 0.0001, (R * sin(th) + R) * squash + base))
	return p


# --- species -----------------------------------------------------------------

static func mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	if id == "u_cep_bulwark":
		var cep := CepBulwark.mesh(0)
		_meshes[id] = cep
		_heights[id] = cep.get_aabb().end.y
		return cep
	if id == "bracket":
		var bracket := RotBracket.mesh()
		_meshes[id] = bracket
		_heights[id] = RotBracket.HEIGHT
		return bracket
	if id == "inkcap_bed":
		var inkbed := InkcapBed.mesh()
		_meshes[id] = inkbed
		_heights[id] = InkcapBed.HEIGHT
		return inkbed
	if id == "u_binder":
		var binder := CoralBinder.mesh(0)
		_meshes[id] = binder
		_heights[id] = CoralBinder.HEIGHT
		return binder
	if id == "u_runner":
		var runner := Runner.mesh(0)
		_meshes[id] = runner
		_heights[id] = Runner.HEIGHT
		return runner
	if id == "u_sniper":
		var sniper := Sniper.mesh(0)
		_meshes[id] = sniper
		_heights[id] = Sniper.HEIGHT
		return sniper
	if id == "u_bomber":
		var bomber := Bomber.mesh(0)
		_meshes[id] = bomber
		_heights[id] = Bomber.HEIGHT
		return bomber
	if id == "u_slinger":
		var slinger := Slinger.mesh(0)
		_meshes[id] = slinger
		_heights[id] = Slinger.HEIGHT
		return slinger
	if id == "u_bruiser":
		var bruiser := Bruiser.mesh(0)
		_meshes[id] = bruiser
		_heights[id] = Bruiser.HEIGHT
		return bruiser
	if id == "i_beetle" or id == "t_beetle":
		var beetle := Beetle.mesh(0, id == "t_beetle")
		_meshes[id] = beetle
		_heights[id] = Beetle.HEIGHT
		return beetle
	if id == "u_spitter":
		var spitter := Spitter.mesh(0)
		_meshes[id] = spitter
		_heights[id] = Spitter.HEIGHT
		return spitter
	if id == "u_sailwing":
		var sailwing := Sailwing.mesh(0)
		_meshes[id] = sailwing
		_heights[id] = Sailwing.HEIGHT
		return sailwing
	if id == "u_webcap":
		var webcap := Webcap.mesh(0)
		_meshes[id] = webcap
		_heights[id] = Webcap.HEIGHT
		return webcap
	if id == "u_angel":
		# the skinned close mesh in its bind pose, for portraits and catalogs
		var angel: ArrayMesh = Angel.lod(0)[0]
		_meshes[id] = angel
		_heights[id] = Angel.HEIGHT
		return angel
	if id == "u_wartling":
		var wartling := Wartling.mesh(0)
		_meshes[id] = wartling
		_heights[id] = wartling.get_aabb().end.y
		return wartling
	var b := B.new()
	b.rng.seed = hash(id)
	b.sc = SPECIES_SCALE.get(id, 1.0)
	_build(b, id)
	var m := b.commit()
	for s in m.get_surface_count():
		m.surface_set_material(s, material(m.surface_get_name(s)))
	_meshes[id] = m
	_heights[id] = b.top
	return m


# The original procedural model of a species, even where newer art replaces it in mesh().
# Uncached; for before/after comparisons such as tools/art/perf_unit.gd.
static func legacy_mesh(id: String) -> ArrayMesh:
	var b := B.new()
	b.rng.seed = hash(id)
	b.sc = SPECIES_SCALE.get(id, 1.0)
	_build(b, id)
	var m := b.commit()
	for s in m.get_surface_count():
		m.surface_set_material(s, material(m.surface_get_name(s)))
	return m


static func _rot(y: float, tilt := 0.0, tilt_dir := 0.0) -> Basis:
	return Basis(Vector3.UP, y) * Basis(Vector3(cos(tilt_dir), 0, sin(tilt_dir)), tilt)


static func agaric(b: B, at: Vector3, h: float, R: float, cap := "agaric_cap", stem := "stem_white", tilt := 0.0) -> void:
	var bas := _rot(b.rng.randf() * TAU, tilt, b.rng.randf() * TAU)
	var sr := R * 0.17
	b.lathe(stem, stem_prof(h, sr * 1.25, sr * 0.85, sr * 0.7), 14, Transform3D(bas, at))
	# ring (annulus)
	b.lathe(stem, PackedVector2Array([Vector2(sr * 0.9, h * 0.78), Vector2(sr * 1.9, h * 0.68), Vector2(sr * 1.7, h * 0.66)]), 14, Transform3D(bas, at))
	var top := Transform3D(bas, at + bas * Vector3(0, h, 0))
	b.lathe(cap, dome_prof(R, R * 0.55), 22, top)
	b.lathe("gill", gill_prof(R, sr, R * 0.55), 22, top)


static func flatcap(b: B, at: Vector3, h: float, R: float, cap: String, stem: String, tilt := 0.0) -> void:
	var bas := _rot(b.rng.randf() * TAU, tilt, b.rng.randf() * TAU)
	var sr := R * 0.14
	b.lathe(stem, stem_prof(h, sr * 1.1, sr * 0.8), 10, Transform3D(bas, at))
	var top := Transform3D(bas, at + bas * Vector3(0, h, 0))
	b.lathe(cap, dome_prof(R, R * 0.28), 18, top)
	b.lathe("gill", gill_prof(R, sr, R * 0.28), 18, top)


static func morel(b: B, at: Vector3, h: float, R: float, tilt := 0.0, cap := "morel_cap_big") -> void:
	var bas := _rot(b.rng.randf() * TAU, tilt, b.rng.randf() * TAU)
	b.lathe("morel_stem", stem_prof(h * 0.4, R * 0.75, R * 0.62, R * 0.25), 14, Transform3D(bas, at))
	b.lathe(cap, egg_prof(R, h * 0.68), 26, Transform3D(bas, at + bas * Vector3(0, h * 0.34, 0)))


static func veiled(b: B, at: Vector3, h: float, R: float, tilt := 0.0, veil := "veil_big") -> void:
	var bas := _rot(b.rng.randf() * TAU, tilt, b.rng.randf() * TAU)
	var sr := R * 0.38
	b.lathe("stem_white", stem_prof(h, sr * 1.2, sr), 14, Transform3D(bas, at))
	b.lathe("volva", sphere_prof(sr * 1.6, 0.6, -sr * 0.4), 12, Transform3D(bas, at))
	b.lathe("gleba", bell_prof(R, R * 1.25), 18, Transform3D(bas, at + bas * Vector3(0, h - R * 0.15, 0)))
	var skirt := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		skirt.append(Vector2(lerpf(R * 0.85, R * 2.0, pow(t, 0.8)), lerpf(h - R * 0.1, h * 0.12, t)))
	b.lathe(veil, skirt, 30, Transform3D(bas, at))


static func puffball(b: B, at: Vector3, R: float, mat := "puffball") -> void:
	b.lathe(mat, sphere_prof(R, 0.82, -R * 0.06), 18, Transform3D(_rot(b.rng.randf() * TAU), at))


static func cup(b: B, at: Vector3, R: float, hs: float, inner := "elfcup", outer := "elfcup_out", tilt := 0.0) -> void:
	var bas := _rot(b.rng.randf() * TAU, tilt, b.rng.randf() * TAU)
	b.lathe(outer, PackedVector2Array([Vector2(R * 0.18, 0), Vector2(R * 0.16, hs), Vector2(R * 0.55, hs + R * 0.25), Vector2(R, hs + R * 0.75)]), 18, Transform3D(bas, at))
	b.lathe(inner, PackedVector2Array([Vector2(R * 0.97, hs + R * 0.76), Vector2(R * 0.5, hs + R * 0.33), Vector2(0.001, hs + R * 0.18)]), 18, Transform3D(bas, at))


static func club(b: B, at: Vector3, h: float, r: float, mat: String, tilt: float, dir: float) -> void:
	var bas := _rot(0.0, tilt, dir)
	b.lathe(mat, PackedVector2Array([Vector2(r, 0), Vector2(r * 0.85, h * 0.6), Vector2(r * 1.5, h * 0.78), Vector2(r * 1.3, h * 0.95), Vector2(0.001, h)]), 8, Transform3D(bas, at))


static func funnel(b: B, at: Vector3, h: float, R: float, tilt := 0.0) -> void:
	var bas := _rot(b.rng.randf() * TAU, tilt, b.rng.randf() * TAU)
	var p := PackedVector2Array([Vector2(R * 0.18, 0), Vector2(R * 0.2, h * 0.45), Vector2(R * 0.55, h * 0.85), Vector2(R, h), Vector2(R * 0.96, h + R * 0.06), Vector2(R * 0.55, h + R * 0.02), Vector2(0.001, h - R * 0.12)])
	b.lathe("chanterelle", p, 22, Transform3D(bas, at))


static func star(b: B, at: Vector3, R: float, rays: int) -> void:
	var s := b.st("earthstar")
	for k in rays:
		var a := TAU * k / rays + b.rng.randf() * 0.2
		var steps := 6
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in steps + 1:
			var t := float(i) / steps
			var w := R * 0.42 * (1.0 - t) * sin(PI / rays) * 2.0 + 0.02
			var c := Vector3(cos(a) * R * t, 0.25 * R * (1.0 - t) * t * 2.0 + 0.1 * t * t * R, sin(a) * R * t)
			var side := Vector3(-sin(a), 0, cos(a)) * w
			var l := at + c + side
			var r := at + c - side
			if i > 0:
				for v in [prev_l, prev_r, r, prev_l, r, l]:
					s.set_normal(Vector3.UP)
					s.add_vertex(v * b.sc)
			prev_l = l
			prev_r = r
	b.lathe("earthstar_ball", sphere_prof(R * 0.42, 0.9, 0.0), 16, Transform3D(Basis(), at))
	b.top = maxf(b.top, (at.y + R * 0.8) * b.sc)


static func legs(b: B, at: Vector3, n: int, span: float, hip_h: float, thick := 0.035) -> void:
	for k in n:
		var a := TAU * (k + 0.5) / n
		var dir := Vector3(cos(a), 0, sin(a))
		var hip := at + dir * span * 0.25 + Vector3(0, hip_h, 0)
		var knee := at + dir * span * 0.7 + Vector3(0, hip_h + span * 0.35, 0)
		var foot := at + dir * span * 1.05
		var ph := float(k % 2) * 0.5 + float(k) * 0.07
		b.tube("leg", hip, knee, thick, thick * 0.8, 5, Color(ph, 0.0, 0), Color(ph, 0.5, 0))
		b.tube("leg", knee, foot, thick * 0.8, thick * 0.35, 5, Color(ph, 0.5, 0), Color(ph, 1.0, 0))


static func _build(b: B, id: String) -> void:
	var r := b.rng
	var O := Vector3.ZERO
	match id:
		"giant_agaric":
			agaric(b, O, 5.2, 3.0)
			for i in 6:
				var a := TAU * i / 6.0 + r.randf() * 0.4
				var d := r.randf_range(2.6, 3.6)
				agaric(b, Vector3(cos(a) * d, 0, sin(a) * d), r.randf_range(1.4, 2.8), r.randf_range(0.8, 1.4), "agaric_cap", "stem_white", r.randf_range(0.05, 0.25))
			for i in 7:
				var a := r.randf() * TAU
				var d := r.randf_range(1.8, 4.0)
				b.lathe("volva", sphere_prof(r.randf_range(0.2, 0.4), 0.9), 10, Transform3D(Basis(), Vector3(cos(a) * d, 0, sin(a) * d)))
		"fly_agaric":
			agaric(b, Vector3(0, 0, 0), 2.9, 1.7)
			agaric(b, Vector3(1.4, 0, 0.6), 2.0, 1.2, "agaric_cap", "stem_white", 0.15)
			agaric(b, Vector3(-1.1, 0, 0.9), 1.4, 0.9, "agaric_cap", "stem_white", 0.2)
			agaric(b, Vector3(0.3, 0, -1.4), 1.0, 0.65, "agaric_cap", "stem_white", 0.1)
		"agaric_button":
			agaric(b, O, 0.38, 0.28)
			agaric(b, Vector3(0.35, 0, 0.15), 0.22, 0.18, "agaric_cap", "stem_white", 0.2)
		"clathrus":
			b.lathe("volva", sphere_prof(0.75, 0.55, -0.15), 14, Transform3D(Basis(), O))
			b.lathe("clathrus", sphere_prof(1.5, 1.05, 0.0), 26, Transform3D(Basis(), Vector3(0, 0.05, 0)))
		"death_cap":
			flatcap(b, Vector3(0, 0, 0), 2.6, 1.5, "deathcap", "stem_white")
			flatcap(b, Vector3(1.3, 0, 0.7), 1.9, 1.1, "deathcap", "stem_white", 0.15)
			flatcap(b, Vector3(-1.2, 0, 0.5), 1.4, 0.85, "deathcap", "stem_white", 0.2)
			var bas := Transform3D(Basis(), Vector3(0.2, 0, -1.3))
			b.lathe("angel", stem_prof(2.2, 0.22, 0.16, 0.2), 12, bas)
			b.lathe("angel", bell_prof(0.75, 0.95, 0.05), 16, bas.translated(Vector3(0, 2.1, 0)))
		"armillaria":
			for i in 7:
				var a := TAU * i / 7.0 + r.randf() * 0.5
				var tilt := r.randf_range(0.15, 0.45)
				var h := r.randf_range(1.0, 1.9)
				var bas := _rot(0.0, tilt, a)
				var R := r.randf_range(0.42, 0.7)
				b.lathe("honey_stem", stem_prof(h, 0.12, 0.08), 8, Transform3D(bas, O))
				var top := Transform3D(bas, bas * Vector3(0, h, 0))
				b.lathe("honey_cap", dome_prof(R, R * 0.3), 14, top)
				b.lathe("gill", gill_prof(R, 0.08, R * 0.3), 14, top)
		"chanterelle":
			funnel(b, O, 1.3, 0.9)
			funnel(b, Vector3(0.9, 0, 0.5), 1.0, 0.7, 0.2)
			funnel(b, Vector3(-0.8, 0, 0.6), 0.8, 0.6, 0.25)
			funnel(b, Vector3(0.1, 0, -0.9), 1.1, 0.75, 0.15)
		"giant_morel":
			morel(b, O, 6.5, 2.0)
			for i in 6:
				var a := TAU * i / 6.0 + r.randf() * 0.4
				var d := r.randf_range(2.3, 3.4)
				morel(b, Vector3(cos(a) * d, 0, sin(a) * d), r.randf_range(1.6, 3.2), r.randf_range(0.5, 0.9), r.randf_range(0.05, 0.2))
		"morel":
			morel(b, O, 3.2, 0.95)
			morel(b, Vector3(1.2, 0, 0.5), 2.4, 0.72, 0.12)
			morel(b, Vector3(-1.0, 0, 0.7), 2.0, 0.6, 0.18)
			morel(b, Vector3(0.2, 0, -1.2), 1.6, 0.5, 0.1)
		"morel_small":
			morel(b, O, 0.75, 0.22, 0.1, "morel_cap_small")
		"elf_cup_small":
			cup(b, O, 0.3, 0.06)
			cup(b, Vector3(0.35, 0, 0.1), 0.22, 0.04, "elfcup", "elfcup_out", 0.3)
		"earthstar":
			star(b, O, 1.9, 8)
		"cordyceps":
			b.lathe("chitin", sphere_prof(0.9, 0.5, -0.1), 14, Transform3D(Basis(), O))
			for i in 9:
				var a := TAU * i / 9.0 + r.randf() * 0.4
				club(b, Vector3(cos(a) * 0.4, 0.2, sin(a) * 0.4), r.randf_range(1.6, 3.4), r.randf_range(0.07, 0.12), "cordyceps", r.randf_range(0.1, 0.5), a)
		"giant_veiled":
			veiled(b, O, 6.2, 1.25)
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				veiled(b, Vector3(cos(a) * 3.1, 0, sin(a) * 3.1), r.randf_range(2.4, 3.6), r.randf_range(0.5, 0.7), 0.08)
		"veiled_lady":
			veiled(b, O, 3.6, 0.75)
			veiled(b, Vector3(1.5, 0, 0.6), 2.6, 0.55, 0.1)
			veiled(b, Vector3(-1.3, 0, 0.7), 2.1, 0.45, 0.15)
		"birds_nest":
			for c in [Vector3(0, 0, 0), Vector3(1.1, 0, 0.4), Vector3(-0.8, 0, 0.8)]:
				var R := 0.75 if c == Vector3.ZERO else 0.55
				b.lathe("nest", PackedVector2Array([Vector2(0.15, 0), Vector2(R * 0.7, R * 0.45), Vector2(R, R * 1.1), Vector2(R * 0.9, R * 1.1), Vector2(R * 0.55, R * 0.5), Vector2(0.001, R * 0.25)]), 18, Transform3D(Basis(), c))
				for e in 4:
					var a := TAU * e / 4.0
					b.lathe("egg", sphere_prof(R * 0.22, 0.6), 8, Transform3D(Basis(), c + Vector3(cos(a) * R * 0.28, R * 0.3, sin(a) * R * 0.28)))
		"pilobolus":
			for i in 13:
				var a := r.randf() * TAU
				var d := sqrt(r.randf()) * 1.5
				var at := Vector3(cos(a) * d, 0, sin(a) * d)
				var h := r.randf_range(0.9, 2.0)
				var bas := _rot(0.0, r.randf_range(0.0, 0.25), r.randf() * TAU)
				b.lathe("glass", stem_prof(h, 0.06, 0.05), 6, Transform3D(bas, at))
				b.lathe("glass", sphere_prof(0.2, 1.2), 10, Transform3D(bas, at + bas * Vector3(0, h - 0.05, 0)))
				b.lathe("black", sphere_prof(0.1, 0.6), 8, Transform3D(bas, at + bas * Vector3(0, h + 0.4, 0)))
		"puffball_small":
			puffball(b, O, 0.28)
			puffball(b, Vector3(0.38, 0, 0.12), 0.18)
		"giant_puffball":
			puffball(b, O, 3.2)
		"mycena_lantern":
			for i in 14:
				var a := r.randf() * TAU
				var d := sqrt(r.randf()) * 1.3
				var h := r.randf_range(0.6, 1.6)
				var bas := _rot(0.0, r.randf_range(0.05, 0.35), a)
				var at := Vector3(cos(a) * d, 0, sin(a) * d)
				b.lathe("mycena_white", stem_prof(h, 0.04, 0.035), 6, Transform3D(bas, at))
				b.lathe("mycena", bell_prof(0.22, 0.26, 0.1), 10, Transform3D(bas, at + bas * Vector3(0, h, 0)))
		"mycena_white":
			for i in 4:
				var a := r.randf() * TAU
				var at := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.3)
				var h := r.randf_range(0.25, 0.5)
				b.lathe("mycena_white", stem_prof(h, 0.018, 0.015), 5, Transform3D(Basis(), at))
				b.lathe("mycena_white", bell_prof(0.08, 0.1), 8, Transform3D(Basis(), at + Vector3(0, h, 0)))
		"inkcap":
			for i in 3:
				var at := Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3))
				var h := r.randf_range(0.3, 0.6)
				b.lathe("stem_white", stem_prof(h, 0.04, 0.03), 6, Transform3D(Basis(), at))
				b.lathe("inkcap", egg_prof(0.12, 0.42), 10, Transform3D(Basis(), at + Vector3(0, h * 0.7, 0)))

		# --- walking sporelings -------------------------------------------------
		"u_spitter":
			legs(b, O, 4, 0.6, 0.35)
			b.lathe("stem_white", stem_prof(0.85, 0.16, 0.11, 0.08), 10, Transform3D(Basis(), Vector3(0, 0.25, 0)))
			b.lathe("agaric_cap", dome_prof(0.36, 0.3), 16, Transform3D(Basis(), Vector3(0, 1.08, 0)))
			b.lathe("gill", gill_prof(0.36, 0.1, 0.3), 16, Transform3D(Basis(), Vector3(0, 1.08, 0)))
		"u_angel":
			legs(b, O, 6, 0.95, 0.5, 0.04)
			b.lathe("angel", stem_prof(0.8, 0.15, 0.12, 0.1), 10, Transform3D(Basis(), Vector3(0, 0.4, 0)))
			b.lathe("angel", bell_prof(0.5, 0.7, 0.05), 16, Transform3D(Basis(), Vector3(0, 1.15, 0)))
		"u_bruiser":
			legs(b, O, 6, 0.85, 0.3, 0.05)
			b.lathe("morel_stem", stem_prof(0.4, 0.38, 0.32), 12, Transform3D(Basis(), Vector3(0, 0.22, 0)))
			b.lathe("morel_cap", egg_prof(0.45, 1.1), 16, Transform3D(Basis(), Vector3(0, 0.55, 0)))
		"u_slinger":
			legs(b, O, 4, 0.6, 0.3)
			cup(b, Vector3(0, 0.25, 0), 0.45, 0.25)
		"u_stalker", "u_zombie":
			var sc := 1.0 if id == "u_stalker" else 0.8
			legs(b, O, 6, 0.85 * sc, 0.32 * sc, 0.035)
			b.lathe("chitin", sphere_prof(0.28 * sc, 0.75, 0.25 * sc), 12, Transform3D(Basis(), Vector3(-0.35 * sc, 0.1, 0)))
			b.lathe("chitin", sphere_prof(0.38 * sc, 0.7, 0.2 * sc), 12, Transform3D(Basis(), Vector3(0.15 * sc, 0.1, 0)))
			b.lathe("chitin", sphere_prof(0.2 * sc, 0.9, 0.3 * sc), 10, Transform3D(Basis(), Vector3(0.62 * sc, 0.1, 0)))
			for i in (6 if id == "u_stalker" else 3):
				var a := TAU * i / 6.0
				club(b, Vector3(0.1 * sc + cos(a) * 0.15, 0.55 * sc, sin(a) * 0.15), r.randf_range(0.5, 1.0) * sc, 0.045, "cordyceps", r.randf_range(0.2, 0.6), a)
		"u_lure":
			legs(b, O, 4, 0.6, 0.3)
			b.lathe("stem_white", stem_prof(0.75, 0.1, 0.08), 10, Transform3D(Basis(), Vector3(0, 0.25, 0)))
			b.lathe("gleba", bell_prof(0.24, 0.32), 12, Transform3D(Basis(), Vector3(0, 0.95, 0)))
			var sk := PackedVector2Array()
			for i in 6:
				var t := i / 5.0
				sk.append(Vector2(lerpf(0.2, 0.5, t), lerpf(1.0, 0.45, t)))
			b.lathe("veil", sk, 16, Transform3D(Basis(), O))
		"u_bomber":
			legs(b, O, 6, 0.7, 0.32)
			puffball(b, Vector3(0, 0.25, 0), 0.5)
		"u_sniper":
			legs(b, O, 4, 0.6, 0.3)
			b.lathe("glass", stem_prof(0.9, 0.09, 0.07), 8, Transform3D(Basis(), Vector3(0, 0.25, 0)))
			b.lathe("glass", sphere_prof(0.28, 1.25), 12, Transform3D(Basis(), Vector3(0, 1.05, 0)))
			b.lathe("black", sphere_prof(0.14, 0.6), 10, Transform3D(Basis(), Vector3(0, 1.72, 0)))
		"inkcap_bed":
			b.lathe("black", PackedVector2Array([Vector2(1.5, 0.02), Vector2(0.8, 0.05), Vector2(0.001, 0.06)]), 18, Transform3D(Basis(), O))
			for i in 6:
				var a := TAU * i / 6.0 + r.randf() * 0.5
				var d := 0.25 + r.randf() * 0.9 if i > 0 else 0.0
				var at := Vector3(cos(a) * d, 0, sin(a) * d)
				var h := r.randf_range(0.6, 1.3) if i > 0 else 1.6
				var bas := _rot(0.0, r.randf_range(0.0, 0.15), a)
				b.lathe("stem_white", stem_prof(h * 0.7, 0.07, 0.06), 8, Transform3D(bas, at))
				b.lathe("inkcap", egg_prof(0.24 * h / 1.3 + 0.08, 0.9 * h / 1.3 + 0.2), 12, Transform3D(bas, at + bas * Vector3(0, h * 0.55, 0)))
		"anthill":
			b.lathe("earth", PackedVector2Array([Vector2(2.6, -0.1), Vector2(2.0, 0.5), Vector2(1.2, 1.15), Vector2(0.5, 1.5), Vector2(0.001, 1.6)]), 20, Transform3D(Basis(), O))

		# --- the forest's insects, and the Choir's thralls grown from them --------
		"oyster_shelf":
			# a log stub with overlapping oyster fans fanning out of its side
			b.lathe("wood", stem_prof(1.3, 0.85, 0.7), 12, Transform3D(Basis(), O))
			for i in 7:
				var y := 0.25 + i * 0.16 + r.randf() * 0.05
				var R := r.randf_range(0.75, 1.15)
				var a := r.randf_range(-0.9, 0.9) + (PI if i % 2 else 0.0)
				var top := PackedVector2Array([Vector2(R + 0.6, y), Vector2(R * 0.8 + 0.6, y + 0.07), Vector2(0.65, y + 0.12)])
				var under := PackedVector2Array([Vector2(0.65, y - 0.06), Vector2(R * 0.7 + 0.6, y - 0.03), Vector2(R + 0.6, y)])
				b.lathe("oyster", top, 14, Transform3D(Basis(), O), a, a + 1.1)
				b.lathe("gill", under, 14, Transform3D(Basis(), O), a, a + 1.1)
		# --- unit buildings: the Hearts' genera, other species ---------------------
		"panther_ring":
			# Amanita pantherina: brown caps flecked with white warts
			agaric(b, Vector3.ZERO, 2.7, 1.5, "panther_cap")
			agaric(b, Vector3(1.4, 0, 0.6), 1.9, 1.1, "panther_cap", "stem_white", 0.15)
			agaric(b, Vector3(-1.1, 0, 0.9), 1.4, 0.85, "panther_cap", "stem_white", 0.2)
			agaric(b, Vector3(0.3, 0, -1.4), 1.0, 0.6, "panther_cap", "stem_white", 0.1)
		"morel_blond":
			# Morchella esculenta: blond, rounder honeycombs than the Heart's dark spires
			morel(b, O, 2.6, 1.15, 0.0, "yellow_morel")
			morel(b, Vector3(1.3, 0, 0.5), 2.0, 0.9, 0.12, "yellow_morel")
			morel(b, Vector3(-1.1, 0, 0.8), 1.7, 0.78, 0.18, "yellow_morel")
			morel(b, Vector3(0.2, 0, -1.3), 1.4, 0.65, 0.1, "yellow_morel")
		"common_stinkhorn":
			# Phallus impudicus: no veil, a slimy olive-black head, unopened "eggs" at the foot
			for c in [[Vector3.ZERO, 3.2, 0.6], [Vector3(1.2, 0, 0.6), 2.4, 0.5], [Vector3(-1.0, 0, 0.8), 1.9, 0.42]]:
				var at: Vector3 = c[0]
				var h: float = c[1]
				var R: float = c[2]
				var bas := _rot(r.randf() * TAU, r.randf_range(0.0, 0.12), r.randf() * TAU)
				b.lathe("volva", PackedVector2Array([Vector2(R * 0.9, 0.0), Vector2(R * 1.05, R * 0.5), Vector2(R * 0.8, R * 0.8), Vector2(R * 0.55, R * 0.6)]), 14, Transform3D(bas, at))
				b.lathe("stinkhorn_stem", stem_prof(h * 0.82, R * 0.5, R * 0.42), 12, Transform3D(bas, at))
				b.lathe("stinkhorn_cap", bell_prof(R * 0.62, h * 0.24, 0.05), 14, Transform3D(bas, at + bas * Vector3(0, h * 0.78, 0)))
			for e in [Vector3(0.9, 0, -0.8), Vector3(-0.6, 0, -0.9)]:
				b.lathe("egg", egg_prof(0.32, 0.55), 12, Transform3D(Basis(), e))
		"honey_rot":
			# Armillaria ostoyae: a dark clump, black bootlace rhizomorphs fanning over the ground
			for i in 8:
				var a := TAU * i / 8.0 + r.randf() * 0.5
				var tilt := r.randf_range(0.12, 0.42)
				var h := r.randf_range(1.3, 2.3)
				var bas := _rot(0.0, tilt, a)
				var R := r.randf_range(0.65, 1.0)
				b.lathe("honey_stem", stem_prof(h, 0.12, 0.08), 8, Transform3D(bas, O))
				var top := Transform3D(bas, bas * Vector3(0, h, 0))
				b.lathe("honey_dark", dome_prof(R, R * 0.32), 14, top)
				b.lathe("gill", gill_prof(R, 0.08, R * 0.32), 14, top)
			for i in 7:
				var a := TAU * i / 7.0 + r.randf() * 0.4
				var pts := [Vector3(cos(a) * 0.3, 0.05, sin(a) * 0.3)]
				for k in 3:
					var d := 1.0 + k * 0.6
					var w := a + r.randf_range(-0.35, 0.35)
					pts.append(Vector3(cos(w) * d, 0.04, sin(w) * d))
				_bent(b, "rhizo", pts, 0.1, 0.04)
		"root_snare":
			# the tree's own roots arching up out of the soil, studded with amanita buttons
			for i in 7:
				var a := TAU * i / 7.0 + r.randf() * 0.4
				var d0 := r.randf_range(0.1, 0.4)
				var d1 := r.randf_range(1.4, 2.1)
				var h := r.randf_range(0.6, 1.2)
				var w := r.randf_range(-0.25, 0.25)
				var mid := (d0 + d1) * 0.5
				_bent(b, "root", [Vector3(cos(a) * d0, -0.15, sin(a) * d0), Vector3(cos(a) * (d0 + 0.25), h * 0.85, sin(a) * (d0 + 0.25)),
					Vector3(cos(a + w) * mid, h, sin(a + w) * mid), Vector3(cos(a) * (d1 - 0.3), h * 0.6, sin(a) * (d1 - 0.3)),
					Vector3(cos(a) * d1, -0.15, sin(a) * d1)], 0.3, 0.12)
				b.lathe("root", sphere_prof(0.24, 0.8, h * 0.8), 8, Transform3D(Basis(), Vector3(cos(a + w) * mid, 0, sin(a + w) * mid)))
				agaric(b, Vector3(cos(a + 0.6) * 1.0, 0, sin(a + 0.6) * 1.0), 0.4, 0.26, "agaric_cap", "stem_white", 0.15)
		"brood_chamber":
			# a mound of insect cocoons, overgrown with white Isaria clubs
			b.lathe("earth", PackedVector2Array([Vector2(2.4, -0.1), Vector2(1.8, 0.5), Vector2(0.9, 0.95), Vector2(0.001, 1.05)]), 18, Transform3D(Basis(), O))
			for i in 9:
				var a := TAU * i / 9.0 + r.randf() * 0.4
				var d := r.randf_range(0.5, 1.7)
				var at := Vector3(cos(a) * d, 1.0 - d * 0.42, sin(a) * d)
				var bas := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3(0, 0, 1), PI * 0.5 - 0.3)
				b.lathe("cocoon", egg_prof(0.22, 0.75), 10, Transform3D(bas, at))
			for i in 12:
				var a := r.randf() * TAU
				var d := r.randf_range(0.2, 1.8)
				club(b, Vector3(cos(a) * d, 1.05 - d * 0.42, sin(a) * d), r.randf_range(0.5, 1.1), 0.06, "isaria", r.randf_range(0.0, 0.4), a)
		"truffle":
			b.lathe("truffle", sphere_prof(0.42, 0.8, -0.28), 16, Transform3D(Basis(), O))
			b.lathe("truffle", sphere_prof(0.24, 0.85, -0.16), 12, Transform3D(Basis(), Vector3(0.48, 0, 0.2)))
			b.lathe("truffle", sphere_prof(0.17, 0.9, -0.12), 10, Transform3D(Basis(), Vector3(-0.3, 0, 0.42)))
		"cortina_thicket":
			webcap(b, Vector3.ZERO, 2.4, 1.1)
			webcap(b, Vector3(1.3, 0, 0.5), 1.8, 0.85, 0.15)
			webcap(b, Vector3(-0.6, 0, 1.3), 1.4, 0.7, 0.2)
			milkcap(b, Vector3(-1.2, 0, -0.6), 1.3, 0.95, 0.1)
			milkcap(b, Vector3(0.6, 0, -1.3), 1.0, 0.75, 0.15)
		"nursery":
			b.lathe("sapling", stem_prof(3.4, 0.14, 0.05, 0.05), 10, Transform3D(Basis(), O))
			for i in 7:
				var a := TAU * i / 7.0 + r.randf() * 0.5
				var at := Vector3(cos(a) * 0.55, r.randf_range(2.4, 3.5), sin(a) * 0.55)
				b.lathe("leaf", sphere_prof(r.randf_range(0.35, 0.55), 0.75, 0.0), 10, Transform3D(Basis(), at))
			b.lathe("leaf", sphere_prof(0.5, 0.9, 3.1), 10, Transform3D(Basis(), O))
			funnel(b, Vector3(0.8, 0, 0.3), 0.6, 0.45, 0.2)
			funnel(b, Vector3(-0.6, 0, 0.6), 0.5, 0.38, 0.25)
			funnel(b, Vector3(0.1, 0, -0.8), 0.55, 0.42, 0.15)
		"u_webcap":
			legs(b, O, 4, 0.6, 0.32)
			b.lathe("webcap_stem", stem_prof(0.8, 0.16, 0.1, 0.1), 10, Transform3D(Basis(), Vector3(0, 0.25, 0)))
			b.lathe("webcap", dome_prof(0.42, 0.34), 16, Transform3D(Basis(), Vector3(0, 1.02, 0)))
			_cortina(b, Vector3(0, 1.0, 0), 0.38, Vector3(0, 0.62, 0), 0.12, 7)
		"u_milkcap":
			legs(b, O, 6, 0.85, 0.3, 0.05)
			b.lathe("milk_stem", stem_prof(0.42, 0.3, 0.26), 12, Transform3D(Basis(), Vector3(0, 0.22, 0)))
			_milk_cap(b, Vector3(0, 0.62, 0), 0.62)
		"i_ant", "t_ant":
			insect_ant(b, id == "t_ant")
		"i_beetle", "t_beetle":
			insect_beetle(b, id == "t_beetle")
		"i_fly", "t_fly":
			insect_fly(b, id == "t_fly")
		"i_stag", "t_stag":
			insect_stag(b, id == "t_stag")
		"i_borer":
			insect_borer(b)
		"i_springtail":
			for i in 6:
				var a := r.randf() * TAU
				var at := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.55)
				var bas := Basis(Vector3.UP, r.randf() * TAU) * Basis().scaled(Vector3(2.2, 1, 1))
				b.lathe("springtail", sphere_prof(0.07, 0.9, 0.02), 8, Transform3D(bas, at))
		_:
			agaric(b, O, 1.0, 0.6)


# --- insects -------------------------------------------------------------------

static func _long(x: float) -> Basis:
	return Basis().scaled(Vector3(x, 1, 1))


# Cordyceps clubs bursting from a thrall's back.
static func _sprouts(b: B, at: Vector3, n: int, h: float) -> void:
	for i in n:
		var a := TAU * i / n + b.rng.randf() * 0.4
		club(b, at + Vector3(cos(a) * 0.06, 0, sin(a) * 0.06), b.rng.randf_range(0.6, 1.0) * h, 0.035, "cordyceps", b.rng.randf_range(0.15, 0.55), a)


static func insect_ant(b: B, thrall: bool) -> void:
	var nz := Color(0, 0, 0, 1)
	legs(b, Vector3(0.05, 0, 0), 6, 0.55, 0.2, 0.022)
	b.lathe("ant_black", sphere_prof(0.19, 0.85, 0.14), 12, Transform3D(_long(1.45), Vector3(-0.36, 0, 0)))
	b.lathe("ant_black", sphere_prof(0.05, 1.0, 0.26), 6, Transform3D(Basis(), Vector3(-0.13, 0, 0)))
	b.lathe("ant_red", sphere_prof(0.1, 0.9, 0.22), 10, Transform3D(_long(2.0), Vector3(0.05, 0, 0)))
	b.lathe("ant_red", sphere_prof(0.12, 0.9, 0.22), 10, Transform3D(_long(1.1), Vector3(0.33, 0, 0)))
	for sd in [-1.0, 1.0]:
		b.tube("ant_black", Vector3(0.4, 0.4, sd * 0.05), Vector3(0.55, 0.55, sd * 0.14), 0.014, 0.012, 4, nz, nz)
		b.tube("ant_black", Vector3(0.55, 0.55, sd * 0.14), Vector3(0.72, 0.45, sd * 0.2), 0.012, 0.008, 4, nz, nz)
	if thrall:
		# Ophiocordyceps: white hyphae bursting from every joint, one stalk out of the back of the head
		_tufts(b, Vector3(-0.13, 0.3, 0), 16, 0.34)
		_tufts(b, Vector3(0.2, 0.34, 0), 12, 0.26)
		_tufts(b, Vector3(-0.45, 0.4, 0), 18, 0.4)
		_tufts(b, Vector3(0.05, 0.28, 0), 10, 0.24)
		_bent(b, "stalk", [Vector3(0.3, 0.42, 0), Vector3(0.24, 0.75, 0.02), Vector3(0.3, 1.05, 0.05), Vector3(0.44, 1.24, 0.06)], 0.04, 0.014)
		b.lathe("ascoma", sphere_prof(0.075, 1.3, -0.06), 12, Transform3D(Basis(), Vector3(0.245, 0.74, 0.02)))


static func insect_beetle(b: B, thrall: bool) -> void:
	legs(b, Vector3.ZERO, 6, 0.75, 0.2, 0.032)
	b.lathe("beetle", sphere_prof(0.33, 0.78, 0.1), 16, Transform3D(_long(1.5), Vector3(-0.14, 0, 0)))
	b.lathe("beetle", sphere_prof(0.23, 0.8, 0.13), 14, Transform3D(_long(1.05), Vector3(0.34, 0, 0)))
	b.lathe("ant_black", sphere_prof(0.12, 0.9, 0.15), 10, Transform3D(Basis(), Vector3(0.56, 0, 0)))
	if thrall:
		_sprouts(b, Vector3(-0.1, 0.6, 0), 4, 0.8)
		_tufts(b, Vector3(0.22, 0.42, 0), 8, 0.16)


static func insect_fly(b: B, thrall: bool) -> void:
	legs(b, Vector3(0.0, 0.42, 0), 6, 0.3, 0.08, 0.014)
	b.lathe("fly", sphere_prof(0.15, 0.9, 0.5), 12, Transform3D(_long(1.4), Vector3(-0.16, 0, 0)))
	b.lathe("fly", sphere_prof(0.14, 0.95, 0.5), 12, Transform3D(Basis(), Vector3(0.08, 0, 0)))
	b.lathe("fly", sphere_prof(0.1, 0.9, 0.56), 10, Transform3D(Basis(), Vector3(0.27, 0, 0)))
	for sd in [-1.0, 1.0]:
		b.lathe("fly_eye", sphere_prof(0.065, 1.0, 0.6), 8, Transform3D(Basis(), Vector3(0.3, 0, sd * 0.07)))
		var wb := Basis(Vector3.UP, sd * 0.45) * Basis().scaled(Vector3(1.7, 1, 0.65))
		b.lathe("wing", sphere_prof(0.2, 0.08, 0.0), 10, Transform3D(wb, Vector3(-0.12, 0.79, sd * 0.2)))
	if thrall:
		# two long stalks topped with dotted perithecial heads, as on a parasitised fly
		for sd in [-1.0, 1.0]:
			var top := Vector3(0.02 + sd * 0.03, 1.5, sd * 0.13)
			_bent(b, "stalk_pink", [Vector3(0.08, 0.72, sd * 0.04), Vector3(0.0, 1.05, sd * 0.1), top], 0.024, 0.016)
			b.lathe("perithecia", sphere_prof(0.1, 0.85, 0.0), 14, Transform3D(Basis(), top - Vector3(0, 0.02, 0)))
		_tufts(b, Vector3(-0.2, 0.62, 0), 6, 0.1)


# A tube bent through several points, tapering from r0 to r1.
static func _bent(b: B, key: String, pts: Array, r0: float, r1: float) -> void:
	var nz := Color(0, 0, 0, 1)
	for i in pts.size() - 1:
		var t0 := float(i) / (pts.size() - 1)
		var t1 := float(i + 1) / (pts.size() - 1)
		b.tube(key, pts[i], pts[i + 1], lerpf(r0, r1, t0), lerpf(r0, r1, t1), 6, nz, nz)


# White mycelial tufts bursting from a body joint, mostly upward and outward.
static func _tufts(b: B, at: Vector3, n: int, length: float) -> void:
	var nz := Color(0, 0, 0, 1)
	for i in n:
		var a := b.rng.randf() * TAU
		var up := b.rng.randf_range(0.2, 1.0)
		var d := Vector3(cos(a) * (1.0 - up * 0.6), up, sin(a) * (1.0 - up * 0.6)).normalized()
		var l := length * b.rng.randf_range(0.5, 1.0)
		var mid := at + d * l * 0.55 + Vector3(b.rng.randf_range(-0.03, 0.03), 0.0, b.rng.randf_range(-0.03, 0.03))
		b.tube("hypha", at, mid, 0.02, 0.012, 4, nz, nz)
		b.tube("hypha", mid, at + d * l, 0.012, 0.002, 4, nz, nz)


# Lucanus cervus, a male: glossy elytra, broad head, red-brown antlers.
static func insect_stag(b: B, thrall: bool) -> void:
	var nz := Color(0, 0, 0, 1)
	legs(b, Vector3(0.05, 0, 0), 6, 1.0, 0.22, 0.035)
	b.lathe("mandible", sphere_prof(0.34, 0.62, 0.12), 18, Transform3D(_long(1.75), Vector3(-0.34, 0, 0)))
	b.lathe("stag", sphere_prof(0.27, 0.6, 0.15), 16, Transform3D(Basis().scaled(Vector3(0.85, 1, 1.2)), Vector3(0.42, 0, 0)))
	b.lathe("stag", sphere_prof(0.2, 0.55, 0.17), 14, Transform3D(Basis().scaled(Vector3(0.9, 1, 1.4)), Vector3(0.74, 0, 0)))
	for sd in [-1.0, 1.0]:
		# a male's antlers sweep up and in, so they read from above
		_bent(b, "mandible", [Vector3(0.84, 0.3, sd * 0.13), Vector3(1.08, 0.5, sd * 0.3), Vector3(1.32, 0.74, sd * 0.3), Vector3(1.5, 0.86, sd * 0.1)], 0.075, 0.018)
		_bent(b, "mandible", [Vector3(1.2, 0.63, sd * 0.31), Vector3(1.36, 0.72, sd * 0.42)], 0.032, 0.008)
		_bent(b, "mandible", [Vector3(1.44, 0.83, sd * 0.17), Vector3(1.6, 0.86, sd * 0.1)], 0.024, 0.006)
		_bent(b, "ant_black", [Vector3(0.8, 0.32, sd * 0.17), Vector3(0.9, 0.46, sd * 0.33), Vector3(1.04, 0.44, sd * 0.4)], 0.014, 0.01)
		b.lathe("ant_black", sphere_prof(0.035, 1.0, 0.27), 6, Transform3D(Basis(), Vector3(0.86, 0, sd * 0.24)))
	if thrall:
		_tufts(b, Vector3(0.14, 0.42, 0), 10, 0.22)
		_tufts(b, Vector3(0.6, 0.4, 0), 8, 0.18)
		_tufts(b, Vector3(-0.8, 0.36, 0), 8, 0.2)
		for i in 3:
			var at := Vector3(-0.2 - i * 0.22, 0.52, (i - 1) * 0.12)
			var top := at + Vector3(b.rng.randf_range(-0.1, 0.1), b.rng.randf_range(0.55, 0.85), b.rng.randf_range(-0.1, 0.1))
			_bent(b, "stalk_pink", [at, (at + top) * 0.5 + Vector3(0.05, 0, 0), top], 0.03, 0.02)
			b.lathe("perithecia", sphere_prof(0.09, 0.85, 0.0), 12, Transform3D(Basis(), top - Vector3(0, 0.02, 0)))


# Agrilus planipennis, the emerald ash borer: a slim metallic bullet.
static func insect_borer(b: B) -> void:
	var nz := Color(0, 0, 0, 1)
	legs(b, Vector3(0.02, 0, 0), 6, 0.34, 0.1, 0.012)
	var prof := PackedVector2Array([Vector2(0.001, 0.0), Vector2(0.045, 0.06), Vector2(0.07, 0.2), Vector2(0.08, 0.36), Vector2(0.078, 0.44), Vector2(0.06, 0.5), Vector2(0.001, 0.52)])
	b.lathe("emerald", prof, 12, Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(-0.3, 0.17, 0)))
	b.lathe("emerald", sphere_prof(0.065, 0.9, 0.11), 10, Transform3D(Basis().scaled(Vector3(0.8, 1, 1.1)), Vector3(0.25, 0, 0)))
	for sd in [-1.0, 1.0]:
		b.lathe("ant_black", sphere_prof(0.03, 1.0, 0.15), 6, Transform3D(Basis(), Vector3(0.28, 0, sd * 0.05)))
		_bent(b, "ant_black", [Vector3(0.3, 0.2, sd * 0.03), Vector3(0.4, 0.26, sd * 0.08)], 0.008, 0.005)


# --- the Court's ectomycorrhizal fungi ----------------------------------------

# Cortinarius violaceus: a deep violet cap with cobweb veil threads to the stem.
static func webcap(b: B, at: Vector3, h: float, R: float, tilt := 0.0) -> void:
	var bas := _rot(b.rng.randf() * TAU, tilt, b.rng.randf() * TAU)
	b.lathe("webcap_stem", stem_prof(h, R * 0.2, R * 0.13, R * 0.18), 10, Transform3D(bas, at))
	b.lathe("webcap", dome_prof(R, R * 0.75), 18, Transform3D(bas, at + bas * Vector3(0, h, 0)))
	b.lathe("gill", gill_prof(R, R * 0.13, R * 0.75), 18, Transform3D(bas, at + bas * Vector3(0, h, 0)))
	_cortina(b, at + bas * Vector3(0, h - 0.02, 0), R * 0.9, at + bas * Vector3(0, h * 0.62, 0), R * 0.16, 9)


# Cobweb threads from a cap's rim down to its stem.
static func _cortina(b: B, rim: Vector3, R: float, stem: Vector3, sr: float, n: int) -> void:
	var nz := Color(0, 0, 0, 1)
	for i in n:
		var a := TAU * i / n + b.rng.randf() * 0.3
		var p0 := rim + Vector3(cos(a) * R, -0.02, sin(a) * R)
		var a2 := a + b.rng.randf_range(-0.4, 0.4)
		var p1 := stem + Vector3(cos(a2) * sr, 0, sin(a2) * sr)
		b.tube("cortina", p0, p1, 0.008, 0.006, 3, nz, nz)


# Lactarius deliciosus: a saffron funnel with concentric zones, beaded with orange latex.
static func milkcap(b: B, at: Vector3, h: float, R: float, tilt := 0.0) -> void:
	var bas := _rot(b.rng.randf() * TAU, tilt, b.rng.randf() * TAU)
	b.lathe("milk_stem", stem_prof(h, R * 0.24, R * 0.2), 10, Transform3D(bas, at))
	_milk_cap(b, at + bas * Vector3(0, h, 0), R)


static func _milk_cap(b: B, at: Vector3, R: float) -> void:
	var cap := PackedVector2Array([Vector2(R * 0.2, 0.0), Vector2(R * 0.6, R * 0.18), Vector2(R, R * 0.32), Vector2(R * 0.96, R * 0.38),
		Vector2(R * 0.6, R * 0.28), Vector2(R * 0.25, R * 0.16), Vector2(0.001, R * 0.12)])
	b.lathe("milkcap", cap, 20, Transform3D(Basis(), at))
	for i in 5:
		var a := TAU * i / 5.0 + b.rng.randf() * 0.6
		b.lathe("latex", sphere_prof(R * 0.07, 1.1, 0.0), 6, Transform3D(Basis(), at + Vector3(cos(a) * R * 0.8, R * 0.08, sin(a) * R * 0.8)))
