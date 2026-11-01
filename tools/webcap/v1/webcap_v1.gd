extends RefCounted
## Violet Webcap (Cortinarius violaceus), the Court's ranged control unit.
## A violet dome cap on a thin stalk that swells into a pale lilac bulb; six stilt
## legs; a cobweb cortina hung from the cap rim to the bulb and the knees, with a few
## gold-glowing threads. One indexed opaque surface, one shared material and one
## small baked map. Legs and web strands step in the shader; no transparency.

const SHADER := preload("res://tools/webcap/v1/webcap_v1.gdshader")
const LOD_NAMES := ["close", "battle", "distant"]
const CAP_R := 0.505
const CAP_BASE := 1.50          # height of the gill plane
const RIM := Vector2(0.475, 1.455)   # where the veil hangs from: radius, height
const BULB := Vector2(0.165, 0.80)  # widest point of the pale bulb
const HEIGHT := 1.82
# Leg directions round the body (+X is forward) and their tripod phase.
const LEG_ANGLES := [-2.62, -1.52, -0.48, 0.52, 1.55, 2.58]
static var _meshes := {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("surface_map", _bake_map())
	return _material


static func _bake_map() -> ImageTexture:
	# R: fine speckle (cap fibrils), G: broad mottling, B: streaks along v (radial on
	# the cap, lengthwise on legs and stalk). Baked once; the shader only samples it.
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var fine := FastNoiseLite.new()
	fine.seed = 5261
	fine.frequency = 0.21
	fine.fractal_octaves = 3
	var broad := FastNoiseLite.new()
	broad.seed = 913
	broad.frequency = 0.03
	broad.fractal_octaves = 3
	var streak := FastNoiseLite.new()
	streak.seed = 377
	streak.frequency = 0.11
	streak.fractal_octaves = 2
	for y in size:
		for x in size:
			image.set_pixel(x, y, Color(fine.get_noise_2d(x, y) * 0.5 + 0.5, broad.get_noise_2d(x, y) * 0.5 + 0.5,
				streak.get_noise_2d(x * 3.2, y * 0.18) * 0.5 + 0.5, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func mesh(lod := 0) -> ArrayMesh:
	lod = clampi(lod, 0, 2)
	if _meshes.has(lod):
		return _meshes[lod]
	var builder := Builder.new()
	builder.build(lod)
	var result := builder.finish()
	result.resource_name = "Webcap_" + LOD_NAMES[lod]
	result.surface_set_material(0, material())
	result.custom_aabb = result.get_aabb().grow(0.2)   # the stride lifts and swings the feet
	_meshes[lod] = result
	return result


static func stats(lod: int) -> Dictionary:
	var m := mesh(lod)
	return {"lod": LOD_NAMES[lod], "triangles": m.surface_get_array_index_len(0) / 3,
		"vertices": m.surface_get_array_len(0), "surfaces": m.get_surface_count()}


# Projected cap width in pixels, with hysteresis.
static func choose_lod(pixels: float, current: int) -> int:
	if current == 0:
		return 1 if pixels < 75.0 else 0
	if current == 2:
		return 1 if pixels > 24.0 else 2
	if pixels > 90.0:
		return 0
	return 2 if pixels < 18.0 else 1


static func leg_phase(k: int) -> float:
	return 0.0 if k % 2 == 0 else PI   # neighbours alternate: two tripods


# The knee of leg k, where the veil's side threads tie on.
static func knee(k: int) -> Vector3:
	var a: float = LEG_ANGLES[k]
	return Vector3(cos(a), 0, sin(a)) * 0.47 + Vector3(0, 1.12, 0)


class Builder:
	var st := SurfaceTool.new()
	var rng := RandomNumberGenerator.new()

	# kind (UV2.x): 0 stalk / bulb, 1 cap, 2 gills, 3 leg, 4 web, 5 glowing web, 6 cap fibril
	# COLOR.a: how much the gait moves this vertex; UV2.y: its step phase.
	func triangle(points: Array, normals: Array, colors: Array, kind: int,
			phases: Array, weights: Array, uv: Array) -> void:
		var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
		if cross.length_squared() < 1e-12:
			return
		# Godot front faces are clockwise seen from outside.
		var order := [0, 2, 1] if cross.dot(normals[0] + normals[1] + normals[2]) > 0.0 else [0, 1, 2]
		for i in order:
			var paint: Color = colors[i].srgb_to_linear()
			st.set_normal(normals[i])
			st.set_color(Color(paint.r, paint.g, paint.b, weights[i]))
			st.set_uv(uv[i])
			st.set_uv2(Vector2(kind, phases[i]))
			st.add_vertex(points[i])

	func quad(p: Array, n: Array, c: Array, kind: int, ph: Array, w: Array, uv: Array) -> void:
		triangle([p[0], p[1], p[2]], [n[0], n[1], n[2]], [c[0], c[1], c[2]], kind, [ph[0], ph[1], ph[2]], [w[0], w[1], w[2]], [uv[0], uv[1], uv[2]])
		triangle([p[0], p[2], p[3]], [n[0], n[2], n[3]], [c[0], c[2], c[3]], kind, [ph[0], ph[2], ph[3]], [w[0], w[2], w[3]], [uv[0], uv[2], uv[3]])

	# A surface of revolution. paint(t, angle) colours each ring.
	func lathe(profile: PackedVector2Array, sides: int, base_y: float, kind: int, paint: Callable,
			wobble := 0.0, uv_wrap := 2.0) -> void:
		for row in profile.size() - 1:
			for k in sides:
				var p := []
				var n := []
				var c := []
				var uv := []
				for pair in [[row, k], [row, k + 1], [row + 1, k + 1], [row + 1, k]]:
					var j: int = pair[0]
					var angle: float = TAU * pair[1] / sides
					var q := profile[j]
					var tangent := profile[mini(j + 1, profile.size() - 1)] - profile[maxi(j - 1, 0)]
					var ripple := 1.0 + wobble * (sin(angle * 3.0 + 0.7) * 0.6 + cos(angle * 7.0) * 0.4)
					p.append(Vector3(q.x * cos(angle) * ripple, base_y + q.y, q.x * sin(angle) * ripple))
					n.append(Vector3(tangent.y * cos(angle), -tangent.x, tangent.y * sin(angle)).normalized())
					var t := float(j) / (profile.size() - 1)
					c.append(paint.call(t, angle))
					uv.append(Vector2(float(pair[1]) / sides * uv_wrap, t))
				quad(p, n, c, kind, [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], uv)

	# A swept tube through a Catmull-Rom path. Per-point radius, weight and colour.
	func tube(path: PackedVector3Array, radii: PackedFloat32Array, weights: PackedFloat32Array,
			colors: Array, sides: int, samples: int, kind: int, phase: float) -> void:
		var rings := []
		var norms := []
		var paints := []
		var ws := []
		for j in samples + 1:
			var t := float(j) / samples
			var f := t * (path.size() - 1)
			var i := mini(int(f), path.size() - 2)
			var local := f - i
			var a := path[maxi(0, i - 1)]
			var b := path[i]
			var c := path[i + 1]
			var d := path[mini(path.size() - 1, i + 2)]
			var center := b.cubic_interpolate(c, a, d, local)
			var axis := ((c - a) * (1.0 - local) + (d - b) * local).normalized()
			var u := axis.cross(Vector3.UP if absf(axis.y) < 0.94 else Vector3.RIGHT).normalized()
			var v := axis.cross(u).normalized()
			var radius := lerpf(radii[i], radii[i + 1], smoothstep(0.0, 1.0, local))
			var paint: Color = (colors[i] as Color).lerp(colors[i + 1], local)
			var ring := []
			var nr := []
			for k in sides + 1:
				var angle := TAU * k / sides
				var radial := u * cos(angle) + v * sin(angle)
				ring.append(center + radial * radius)
				nr.append(radial)
			rings.append(ring)
			norms.append(nr)
			paints.append(paint)
			ws.append(lerpf(weights[i], weights[i + 1], local))
		for j in samples:
			for k in sides:
				var p := [rings[j][k], rings[j][k + 1], rings[j + 1][k + 1], rings[j + 1][k]]
				var n := [norms[j][k], norms[j][k + 1], norms[j + 1][k + 1], norms[j + 1][k]]
				var c := [paints[j], paints[j], paints[j + 1], paints[j + 1]]
				var w := [ws[j], ws[j], ws[j + 1], ws[j + 1]]
				var v0 := float(j) / samples * 3.0
				var v1 := float(j + 1) / samples * 3.0
				var uv := [Vector2(float(k) / sides, v0), Vector2(float(k + 1) / sides, v0),
					Vector2(float(k + 1) / sides, v1), Vector2(float(k) / sides, v1)]
				quad(p, n, c, kind, [phase, phase, phase, phase], w, uv)

	# A thread of the cortina: sags between two points, outward from the stalk.
	func strand(a: Vector3, b: Vector3, sag: float, radius: float, sides: int, samples: int,
			glow: bool, wa := 0.0, wb := 0.0, phase := 0.0) -> void:
		var mid := (a + b) * 0.5
		var out := Vector3(mid.x, 0, mid.z).normalized() * sag + Vector3(0, -absf(sag) * 0.35, 0)
		var path := PackedVector3Array([a, a.lerp(b, 0.33) + out * 0.85, a.lerp(b, 0.67) + out * 0.85, b])
		var col := Color(0.98, 0.83, 0.52) if glow else Color(0.95, 0.93, 0.87)
		tube(path, PackedFloat32Array([radius * 0.8, radius, radius, radius * 0.8]),
			PackedFloat32Array([wa, lerpf(wa, wb, 0.33), lerpf(wa, wb, 0.67), wb]),
			[col, col, col, col], sides, samples, 5 if glow else 4, phase)

	func rim_point(angle: float) -> Vector3:
		return Vector3(cos(angle) * RIM.x, RIM.y, sin(angle) * RIM.x)

	func bulb_point(angle: float, y: float) -> Vector3:
		# radius of the bulb profile at height y (matches the lathe below)
		var r := 0.165 * sqrt(clampf(1.0 - pow((y - 0.80) / 0.20, 2.0), 0.05, 1.0))
		return Vector3(cos(angle) * r, y, sin(angle) * r)

	func build(lod: int) -> void:
		rng.seed = 60317
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sides: int = [40, 24, 12][lod]
		# --- cap: a broad violet dome, darker at the crown, paler toward the rim ---
		var cap_profile := PackedVector2Array([Vector2(0.462, -0.046), Vector2(0.505, -0.012), Vector2(0.522, 0.035),
			Vector2(0.505, 0.095), Vector2(0.462, 0.158), Vector2(0.39, 0.215), Vector2(0.295, 0.257),
			Vector2(0.19, 0.282), Vector2(0.09, 0.294), Vector2(0.0, 0.297)])
		if lod == 2:
			cap_profile = PackedVector2Array([Vector2(0.462, -0.046), Vector2(0.52, 0.03), Vector2(0.462, 0.158),
				Vector2(0.295, 0.257), Vector2(0.0, 0.297)])
		lathe(cap_profile, [56, 32, 14][lod], CAP_BASE, 1, func(t: float, a: float) -> Color:
			var mottle := 0.5 + 0.5 * sin(a * 5.0 + t * 7.0) * cos(a * 3.0 - t * 4.0)
			return Color(0.64, 0.48, 0.83).lerp(Color(0.42, 0.22, 0.63), smoothstep(0.1, 0.95, t) * 0.8 + mottle * 0.12), 0.012, 3.0)
		# --- gill plane and radial gills ---
		var under := PackedVector2Array([Vector2(0.085, 0.002), Vector2(0.25, -0.022), Vector2(0.40, -0.038), Vector2(0.462, -0.046)])
		lathe(under, [48, 28, 12][lod], CAP_BASE, 2, func(_t: float, _a: float) -> Color:
			return Color(0.40, 0.27, 0.57))
		if lod < 2:
			var count: int = [44, 22][lod]
			for k in count:
				var a := TAU * (k + 0.5) / count
				var d := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-d.z, 0, d.x)
				var inner := 0.10 if k % 2 == 0 else 0.22
				var r0 := Vector3(0, CAP_BASE + 0.0 - inner * 0.15, 0) + d * inner
				var r1 := Vector3(0, CAP_BASE - 0.040, 0) + d * 0.445
				var depth := 0.045
				var q := [r0, r1, r1 + Vector3(0, -depth * 0.4, 0), r0 + Vector3(0, -depth, 0) + d * 0.04]
				var col := Color(0.47, 0.33, 0.64)
				for s in [-1.0, 1.0]:
					var off: Vector3 = side * s * 0.0025
					quad([q[0] + off, q[1] + off, q[2] + off, q[3] + off], [side * s, side * s, side * s, side * s],
						[col, col, col.darkened(0.15), col.darkened(0.15)], 2, [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0],
						[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		# --- stalk swelling into a pale lilac bulb with a blunt point ---
		var stalk := PackedVector2Array([Vector2(0.0, 0.595), Vector2(0.05, 0.612), Vector2(0.105, 0.655),
			Vector2(0.148, 0.725), Vector2(0.165, 0.80), Vector2(0.155, 0.88), Vector2(0.122, 0.955),
			Vector2(0.087, 1.035), Vector2(0.067, 1.14), Vector2(0.058, 1.27), Vector2(0.061, 1.39),
			Vector2(0.074, 1.465), Vector2(0.092, 1.505)])
		if lod == 2:
			stalk = PackedVector2Array([Vector2(0.0, 0.595), Vector2(0.11, 0.66), Vector2(0.165, 0.80),
				Vector2(0.12, 0.96), Vector2(0.065, 1.16), Vector2(0.065, 1.40), Vector2(0.092, 1.505)])
		lathe(stalk, sides, 0.0, 0, func(t: float, a: float) -> Color:
			var violet := smoothstep(0.38, 0.8, t)
			var pale := Color(0.90, 0.86, 0.94).lerp(Color(0.80, 0.72, 0.90), 0.5 + 0.5 * sin(a * 3.0 + t * 9.0))
			return pale.lerp(Color(0.53, 0.37, 0.75), violet), 0.0, 2.0)
		# --- six stilt legs: a short rising coxa, a knee, then a long straight shin ---
		for k in 6:
			var a: float = LEG_ANGLES[k]
			var d := Vector3(cos(a), 0, sin(a))
			var up := Vector3.UP
			var path := PackedVector3Array([d * 0.11 + up * 0.80, d * 0.22 + up * 0.875, d * 0.36 + up * 1.02,
				d * 0.47 + up * 1.12, d * 0.62 + up * 0.743, d * 0.77 + up * 0.367, d * 0.90 + up * 0.04,
				d * 0.912 + up * 0.0])
			var lilac := Color(0.76, 0.66, 0.89)
			var colors := [lilac.lerp(Color(0.86, 0.82, 0.93), 0.4), lilac, lilac, lilac.lightened(0.06), lilac,
				lilac.lerp(Color(0.74, 0.62, 0.50), 0.35), Color(0.62, 0.50, 0.38), Color(0.20, 0.13, 0.09)]
			tube(path, PackedFloat32Array([0.036, 0.031, 0.024, 0.029, 0.020, 0.016, 0.010, 0.002]),
				PackedFloat32Array([0.0, 0.0, 0.15, 0.40, 0.60, 0.80, 1.0, 1.0]), colors,
				[10, 7, 4][lod], [22, 12, 7][lod], 3, _phase(k))
		# --- cap fibrils: a few pale flat patches on the crown ---
		if lod == 0:
			for i in 26:
				var rr := sqrt((i + 0.5) / 26.0) * 0.82
				var ang := i * 2.39996 + rng.randf_range(-0.2, 0.2)
				var h := _cap_h(rr)
				var at := Vector3(cos(ang) * rr * CAP_R, CAP_BASE + h, sin(ang) * rr * CAP_R)
				var n := Vector3(cos(ang) * rr * 0.9, 1.0, sin(ang) * rr * 0.9).normalized()
				patch(at + n * 0.002, n, rng.randf_range(0.018, 0.04))
		# --- the cortina ---
		var drapes: int = [26, 12, 0][lod]
		var radius: float = [0.0055, 0.009, 0.014][lod]
		var thread_sides: int = [4, 3, 3][lod]
		var bottoms := []
		for i in drapes:
			var a0 := TAU * (i + 0.37) / drapes + rng.randf_range(-0.06, 0.06)
			var a1 := a0 + rng.randf_range(-0.7, 0.7)
			var top := rim_point(a0) + Vector3(0, rng.randf_range(-0.02, 0.01), 0)
			# most threads gather on the bulb; some catch the stalk higher up, some a leg's hip
			var low := bulb_point(a1, rng.randf_range(0.64, 0.88))
			var roll := rng.randf()
			if roll < 0.2:
				low = Vector3(cos(a1) * 0.07, rng.randf_range(1.0, 1.2), sin(a1) * 0.07)
			elif roll < 0.4:
				var leg: int = int(posmod(roundi((a0 + PI) / TAU * 6.0), 6))
				var la: float = LEG_ANGLES[leg]
				low = Vector3(cos(la), 0, sin(la)) * rng.randf_range(0.22, 0.34) + Vector3(0, 0.9, 0)
			bottoms.append([top, low])
			strand(top, low, rng.randf_range(0.0, 0.07), radius * rng.randf_range(0.7, 1.15), thread_sides, [7, 5, 3][lod], i % 6 == 2)
		# cross threads tie neighbouring drapes into a net
		if lod < 2:
			var levels: Array = [[0.22, 0.48, 0.74], [0.45]][lod]
			for i in drapes:
				var p0: Array = bottoms[i]
				var p1: Array = bottoms[(i + 1) % drapes]
				for lv in levels:
					var t: float = lv + rng.randf_range(-0.06, 0.06)
					var s0 := _along(p0[0], p0[1], t)
					var s1 := _along(p1[0], p1[1], t + rng.randf_range(-0.12, 0.12))
					strand(s0, s1, rng.randf_range(-0.05, 0.0), radius * 0.7, 3, [4, 3][lod], rng.randf() < 0.08)
		# the side threads, rim to each knee and knee to the bulb, ride with the legs
		for k in 6:
			var a: float = LEG_ANGLES[k]
			var kn := _knee(k)
			strand(rim_point(a + 0.18), kn, 0.04, radius * 1.2, thread_sides, [6, 4, 3][lod], k % 3 == 1, 0.0, 0.40, _phase(k))
			if lod < 2:
				strand(rim_point(a - 0.22), kn, 0.03, radius, thread_sides, [6, 4][lod], false, 0.0, 0.40, _phase(k))
				strand(kn, bulb_point(a, 0.72), 0.05, radius, thread_sides, [6, 4][lod], k % 2 == 0, 0.40, 0.0, _phase(k))
			elif k % 2 == 0:
				strand(kn, bulb_point(a, 0.72), 0.05, radius, thread_sides, 3, false, 0.40, 0.0, _phase(k))

	func _along(a: Vector3, b: Vector3, t: float) -> Vector3:
		var mid := (a + b) * 0.5
		return a.lerp(b, t) + Vector3(mid.x, 0, mid.z).normalized() * 0.04 * sin(t * PI)

	func _cap_h(rr: float) -> float:
		# crown height (above the gill plane) at a fraction of the cap radius
		return 0.297 * sqrt(maxf(1.0 - rr * rr * 0.95, 0.0))

	func patch(at: Vector3, n: Vector3, size: float) -> void:
		var u := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.UP).normalized()
		var v := n.cross(u)
		var pts := []
		var sides := 6
		var stretch := rng.randf_range(0.5, 1.0)
		for k in sides:
			var ang := TAU * k / sides
			pts.append(at + (u * cos(ang) * stretch + v * sin(ang)) * size * rng.randf_range(0.7, 1.15))
		var col := Color(0.84, 0.77, 0.93)
		for k in sides:
			triangle([at + n * 0.004, pts[k], pts[(k + 1) % sides]], [n, n, n], [col, col, col], 6,
				[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0)])

	func _phase(k: int) -> float:
		return 0.0 if k % 2 == 0 else PI

	func _knee(k: int) -> Vector3:
		var a: float = LEG_ANGLES[k]
		return Vector3(cos(a), 0, sin(a)) * 0.47 + Vector3(0, 1.12, 0)

	func finish() -> ArrayMesh:
		st.generate_tangents()
		st.index()
		st.optimize_indices_for_cache()
		var result := st.commit()
		result.surface_set_name(0, "webcap_opaque")
		return result
