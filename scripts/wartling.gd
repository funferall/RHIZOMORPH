extends RefCounted
## The Court's poison infantry: one indexed surface, shared material, six roots.
## Curved root limbs, a ragged cap and sculpted veil fragments establish identity.
## Two small baked surface maps are shared by every instance, never recomputed
## in the fragment shader. No transparency or per-leg scene nodes.

const SHADER := preload("res://shaders/wartling.gdshader")
const LOD_NAMES := ["close", "battle", "distant"]
const CAP_R := 0.73
const CAP_H := 0.37
const CAP_AT := Vector3(0.055, 0.67, 0.0)
static var _meshes := {}
static var _material: ShaderMaterial
static var _surface_map: ImageTexture
static var _normal_map: ImageTexture


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_bake_surface_maps()
		_material.set_shader_parameter("surface_map", _surface_map)
		_material.set_shader_parameter("normal_map", _normal_map)
	return _material


static func _bake_surface_maps() -> void:
	# Small reusable data tiles, baked once on the CPU. The root grain is stretched
	# in texture space; the cap's speckle is isotropic. All levels share the maps.
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var normals := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var fine := FastNoiseLite.new()
	fine.seed = 4197
	fine.frequency = 0.24
	fine.fractal_octaves = 3
	var broad := FastNoiseLite.new()
	broad.seed = 814
	broad.frequency = 0.027
	broad.fractal_octaves = 3
	var grain := FastNoiseLite.new()
	grain.seed = 718
	grain.frequency = 0.13
	grain.fractal_octaves = 2
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			var f := fine.get_noise_2d(x, y) * 0.5 + 0.5
			var b := broad.get_noise_2d(x, y) * 0.5 + 0.5
			var g := grain.get_noise_2d(x * 2.8, y * 0.19) * 0.5 + 0.5
			image.set_pixel(x, y, Color(f, b, g, 1.0))
			heights[y * size + x] = f * 0.35 + g * 0.65
	for y in size:
		for x in size:
			var dx := heights[y * size + (x + 1) % size] - heights[y * size + (x - 1 + size) % size]
			var dy := heights[((y + 1) % size) * size + x] - heights[((y - 1 + size) % size) * size + x]
			var n := Vector3(-dx * 2.4, -dy * 2.4, 1.0).normalized()
			normals.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	image.generate_mipmaps()
	normals.generate_mipmaps()
	_surface_map = ImageTexture.create_from_image(image)
	_normal_map = ImageTexture.create_from_image(normals)


static func mesh(lod := 0) -> ArrayMesh:
	lod = clampi(lod, 0, 2)
	if _meshes.has(lod):
		return _meshes[lod]
	var builder := Builder.new()
	builder.build(lod)
	var result := builder.finish()
	result.resource_name = "Wartling_" + LOD_NAMES[lod]
	result.surface_set_material(0, material())
	# Bounds include the full vertex-shader stride, even at the edge of the view.
	result.custom_aabb = result.get_aabb().grow(0.15)
	_meshes[lod] = result
	return result


static func stats(lod: int) -> Dictionary:
	var m := mesh(lod)
	return {"lod": LOD_NAMES[lod], "triangles": m.surface_get_array_index_len(0) / 3,
		"vertices": m.surface_get_array_len(0), "surfaces": m.get_surface_count()}


static func choose_lod(pixels: float, current: int) -> int:
	# Projected body width, with hysteresis to avoid oscillating at a boundary.
	if current == 0:
		return 1 if pixels < 75.0 else 0
	if current == 2:
		return 1 if pixels > 24.0 else 2
	if pixels > 90.0:
		return 0
	return 2 if pixels < 18.0 else 1


class Builder:
	var st := SurfaceTool.new()
	var rng := RandomNumberGenerator.new()
	var cap_profile := PackedVector2Array()

	func triangle(points: Array, normals: Array, color: Color, kind: int,
			phase := 0.0, weights := Vector3.ZERO, uv: Array = [], colors: Array = []) -> void:
		var a: Vector3 = points[0]
		var b: Vector3 = points[1]
		var c: Vector3 = points[2]
		var cross := (b - a).cross(c - a)
		if cross.length_squared() < 0.0000000001:
			return
		# Godot front faces are clockwise when seen from outside.
		var order := [0, 2, 1] if cross.dot(normals[0] + normals[1] + normals[2]) > 0.0 else [0, 1, 2]
		for i in order:
			st.set_normal(normals[i])
			var paint: Color = colors[i] if not colors.is_empty() else color
			paint = paint.srgb_to_linear()
			st.set_color(Color(paint.r, paint.g, paint.b, weights[i]))
			st.set_uv(uv[i] if not uv.is_empty() else Vector2.ZERO)
			st.set_uv2(Vector2(kind, phase))
			st.add_vertex(points[i])


	func cap_point(r: float, h: float, angle: float) -> Vector3:
		var wobble := 1.0 + 0.033 * sin(angle * 3.0 + 0.5) + 0.019 * cos(angle * 7.0)
		var x := r * CAP_R * cos(angle) * wobble
		var scallop := (0.017 * sin(angle * 5.0) + 0.009 * cos(angle * 11.0)) * pow(r, 3.0)
		return CAP_AT + Vector3(x, h * CAP_H + x * 0.12 + scallop,
			r * CAP_R * sin(angle) * wobble)


	func lathe(profile: PackedVector2Array, sides: int, at: Vector3,
			color: Color, kind: int, cap := false) -> void:
		for row in profile.size() - 1:
			for k in sides:
				var points := []
				var normals := []
				var uvs := []
				var paints := []
				for pair in [[row, k], [row, k + 1], [row + 1, k + 1], [row + 1, k]]:
					var j: int = pair[0]
					var angle: float = TAU * pair[1] / sides
					var p := profile[j]
					var tangent := profile[mini(j + 1, profile.size() - 1)] - profile[maxi(j - 1, 0)]
					var n := Vector3(tangent.y * cos(angle), -tangent.x, tangent.y * sin(angle)).normalized()
					var paint := color
					if cap:
						points.append(cap_point(p.x, p.y, angle))
						n = Vector3(n.x, n.y - n.x * 0.12, n.z).normalized()
						var t := clampf(p.y, 0.0, 1.0)
						var mottle := 0.5 + 0.5 * sin(angle * 4.0 + p.x * 11.0) * cos(angle * 7.0 - p.x * 5.0)
						paint = Color(0.51, 0.035, 0.022).lerp(Color(0.83, 0.16, 0.065), 0.34 + t * 0.50 + mottle * 0.16)
						# A ragged ivory veil remains on the downward-turning lip.
						var lip := clampf((-0.005 - p.y) * 9.0, 0.0, 1.0)
						paint = paint.lerp(Color(0.87, 0.77, 0.53), lip)
					else:
						var ripple := 1.0 + 0.035 * sin(angle * 7.0 + p.y * 13.0) + 0.018 * cos(angle * 13.0)
						var offset := Vector3(p.x * cos(angle) * ripple, p.y, p.x * sin(angle) * ripple)
						if kind == 4:
							offset.y += offset.x * 0.12
						points.append(at + offset)
						paint = color.darkened(0.08 * (0.5 + 0.5 * sin(angle * 7.0 + p.y * 11.0)))
					normals.append(n)
					uvs.append(Vector2(float(pair[1]) / sides * (3.0 if cap else 2.0), float(j) / (profile.size() - 1)))
					paints.append(paint)
				for ids in [[0, 1, 2], [0, 2, 3]]:
					triangle([points[ids[0]], points[ids[1]], points[ids[2]]],
						[normals[ids[0]], normals[ids[1]], normals[ids[2]]], color, kind,
						0.0, Vector3.ZERO, [uvs[ids[0]], uvs[ids[1]], uvs[ids[2]]],
						[paints[ids[0]], paints[ids[1]], paints[ids[2]]])


	func root_limb(path: PackedVector3Array, radii: PackedFloat32Array, sides: int,
			samples: int, phase: float, weight0: float, weight1: float, seed_offset: float) -> void:
		# Smooth swept roots, with bulging knuckles and longitudinal bark folds.
		var rings := []
		var normals := []
		var paints := []
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
			var ring := []
			var nr := []
			var pc := []
			for k in sides + 1:
				var angle := TAU * k / sides
				var radial := u * cos(angle) + v * sin(angle)
				var folds := 1.0 + 0.12 * sin(angle * 3.0 + seed_offset + t * 3.0) + 0.06 * cos(angle * 5.0 - t * 2.0)
				ring.append(center + radial * radius * folds)
				nr.append(radial)
				var stain := clampf(t * 0.65 + 0.18 * sin(angle * 3.0 + seed_offset + t * 9.0), 0.0, 1.0)
				pc.append(Color(0.91, 0.87, 0.75).lerp(Color(0.49, 0.41, 0.29), stain * 0.73))
			rings.append(ring)
			normals.append(nr)
			paints.append(pc)
		for j in samples:
			var w0 := lerpf(weight0, weight1, float(j) / samples)
			var w1 := lerpf(weight0, weight1, float(j + 1) / samples)
			for k in sides:
				var p := [rings[j][k], rings[j][k+1], rings[j+1][k+1], rings[j+1][k]]
				var n := [normals[j][k], normals[j][k+1], normals[j+1][k+1], normals[j+1][k]]
				var c := [paints[j][k], paints[j][k+1], paints[j+1][k+1], paints[j+1][k]]
				var uv := [Vector2(float(k)/sides, float(j)/samples*2.0), Vector2(float(k+1)/sides, float(j)/samples*2.0),
					Vector2(float(k+1)/sides, float(j+1)/samples*2.0), Vector2(float(k)/sides, float(j+1)/samples*2.0)]
				triangle([p[0],p[1],p[2]], [n[0],n[1],n[2]], Color.WHITE, 3, phase, Vector3(w0,w0,w1), [uv[0],uv[1],uv[2]], [c[0],c[1],c[2]])
				triangle([p[0],p[2],p[3]], [n[0],n[2],n[3]], Color.WHITE, 3, phase, Vector3(w0,w1,w1), [uv[0],uv[2],uv[3]], [c[0],c[2],c[3]])


	func flake(at: Vector3, normal: Vector3, radius: float, height: float, sides: int, skin := Color(0.96,0.94,0.86),
			kind := 2, phase := 0.0, weight := 0.0) -> void:
		var u := normal.cross(Vector3.FORWARD if absf(normal.z) < 0.9 else Vector3.UP).normalized()
		var v := normal.cross(u)
		var lower := []
		var upper := []
		var stretch := rng.randf_range(0.65, 1.25)
		for k in sides:
			var angle := TAU * k / sides
			var radial := (u * cos(angle) * stretch + v * sin(angle)) * rng.randf_range(0.72, 1.18)
			lower.append(at + radial * radius)
			upper.append(at + radial * radius * rng.randf_range(0.62, 0.9) + normal * height * rng.randf_range(0.65, 1.0))
		var top := at + normal * height * 0.86 + u * radius * 0.15
		for k in sides:
			var j := (k + 1) % sides
			var nk: Vector3 = (upper[k] - at).normalized()
			var nj: Vector3 = (upper[j] - at).normalized()
			var color := skin
			var faces := [[lower[k],lower[j],upper[j]], [lower[k],upper[j],upper[k]], [upper[k],upper[j],top]]
			var face_normals := [[nk,nj,(nj+normal).normalized()], [nk,(nj+normal).normalized(),(nk+normal).normalized()],
				[(nk*0.3+normal).normalized(),(nj*0.3+normal).normalized(),normal]]
			for f in 3:
				triangle(faces[f],face_normals[f],color,kind,phase,Vector3.ONE*weight,
					[Vector2(0,0),Vector2(1,0),Vector2(0.5,1)])


	func cap_height(r: float) -> float:
		for i in range(1, cap_profile.size() - 1):
			var a := cap_profile[i]
			var b := cap_profile[i + 1]
			if r <= a.x and r >= b.x:
				return lerpf(a.y, b.y, inverse_lerp(a.x, b.x, r))
		return 1.0


	func build(lod: int) -> void:
		rng.seed = 81473
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		cap_profile = [PackedVector2Array([Vector2(0.965,-0.10), Vector2(1.02,-0.025),
			Vector2(1.015,0.11), Vector2(0.975,0.28), Vector2(0.90,0.49),
			Vector2(0.80,0.67), Vector2(0.66,0.83), Vector2(0.49,0.94),
			Vector2(0.31,1.00), Vector2(0.14,1.025), Vector2(0,1.03)]),
			PackedVector2Array([Vector2(0.965,-0.10), Vector2(1.02,-0.025), Vector2(0.99,0.23),
			Vector2(0.88,0.52), Vector2(0.66,0.83), Vector2(0.36,0.985), Vector2(0,1.03)]),
			PackedVector2Array([Vector2(0.97,-0.10),Vector2(1.02,0.04),Vector2(0.88,0.52),Vector2(0.50,0.94),Vector2(0,1.03)])][lod]
		lathe(cap_profile, [56,32,16][lod], Vector3.ZERO, Color.WHITE, 1, true)
		var stem := PackedVector2Array([Vector2(0.15,0.16), Vector2(0.25,0.23),
			Vector2(0.29,0.33),Vector2(0.255,0.44),Vector2(0.185,0.56),Vector2(0.20,0.73)])
		if lod == 2:
			stem = PackedVector2Array([Vector2(0.20,0.18),Vector2(0.28,0.33),Vector2(0.19,0.60)])
		lathe(stem, [24,16,8][lod], Vector3.ZERO, Color(0.92,0.88,0.76), 0)
		# An actual underside and radial fins: readable at a low camera angle.
		lathe(PackedVector2Array([Vector2(0.19,0.70),Vector2(0.40,0.62),Vector2(0.70,0.64)]),
			[48,32,16][lod], Vector3(0.055,0,0), Color(0.78,0.75,0.38), 4)
		if lod < 2:
			var count: int = [48,24][lod]
			for k in count:
				var a := TAU * k / count
				var d := Vector3(cos(a),0,sin(a))
				var n := Vector3(-d.z,0,d.x)
				var center := Vector3(0.055,0,0)
				var profile := [Vector3(0.21,0.69,0.67),Vector3(0.34,0.62,0.54),
					Vector3(0.50,0.60,0.49),Vector3(0.70,0.63,0.62)]
				for j in 3:
					var q := []
					for pair in [[j,1],[j+1,1],[j+1,2],[j,2]]:
						var p: Vector3 = profile[pair[0]]
						var point := center+d*p.x+Vector3(0,p[pair[1]],0)
						point.y += point.x*0.12
						q.append(point)
					for sign_value in [-1.0,1.0]:
						var offset: Vector3 = n*sign_value*0.003
						var color := Color(0.84,0.81,0.42).darkened(0.13 if sign_value < 0 else 0.0)
						var uv := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
						for ids in [[0,1,2],[0,2,3]]:
							triangle([q[ids[0]]+offset,q[ids[1]]+offset,q[ids[2]]+offset],
								[n*sign_value,n*sign_value,n*sign_value],color,4,0.0,Vector3.ZERO,
								[uv[ids[0]],uv[ids[1]],uv[ids[2]]])
					# The lower lip closes the lamella instead of leaving a zero-thickness card.
					var lip := [q[2]-n*0.003,q[2]+n*0.003,q[3]+n*0.003,q[3]-n*0.003]
					for ids in [[0,1,2],[0,2,3]]:
						triangle([lip[ids[0]],lip[ids[1]],lip[ids[2]]],[Vector3.DOWN,Vector3.DOWN,Vector3.DOWN],
							Color(0.91,0.86,0.56),4,0.0,Vector3.ZERO,[Vector2(0,0),Vector2(1,0),Vector2(0.5,1)])
			# Torn annulus droops around the narrow neck; not an insect chassis.
			lathe(PackedVector2Array([Vector2(0.19,0.56),Vector2(0.30,0.47),Vector2(0.26,0.43)]),
				[32,16][lod],Vector3.ZERO,Color(0.94,0.89,0.77),0)
		for k in 6:
			var angle: float = [-0.52,0.55,1.60,2.55,3.68,4.75][k]
			var dir := Vector3(cos(angle),0,sin(angle))
			var side := Vector3(-dir.z,0,dir.x)
			var curl := 1.0 if k % 2 == 0 else -1.0
			var phase := float(k % 2) * PI
			var path := PackedVector3Array([dir*0.19+Vector3(0,0.33,0),
				dir*0.35+side*0.035*curl+Vector3(0,0.40,0),
				dir*0.51+side*0.045*curl+Vector3(0,0.36,0),
				dir*0.60-side*0.01*curl+Vector3(0,0.20,0),
				dir*0.73-side*0.035*curl+Vector3(0,0.07,0),
				dir*0.88+side*0.035*curl+Vector3(0,0.025,0),
				dir*0.96+side*0.09*curl+Vector3(0,0.012,0)])
			root_limb(path,PackedFloat32Array([0.085,0.090,0.113,0.059,0.048,0.025,0.002]),
				[10,7,4][lod],[16,9,5][lod],phase,0.0,1.0,float(k))
			if lod < 2:
				# Overlapping fungal plates break up the smooth knee silhouette.
				for plate in [3,2][lod]:
					var normal: Vector3 = (dir*0.55+Vector3.UP*0.83+side*(plate-1)*0.25).normalized()
					var at: Vector3 = path[2] + normal*0.095 - dir*plate*0.035
					flake(at,normal,0.075-plate*0.007,0.028,[7,5][lod],Color(0.84,0.79,0.65),3,phase,0.40)
				for branch in [-1.0,1.0]:
					var start := path[4].lerp(path[3],0.18)
					var fork := PackedVector3Array([start,
						dir*0.79+side*(branch*0.10-0.035*curl)+Vector3(0,0.065,0),
						dir*0.87+side*(branch*0.16-0.035*curl)+Vector3(0,0.022,0),
						dir*0.91+side*(branch*0.20-0.035*curl)+Vector3(0,0.012,0)])
					root_limb(fork,PackedFloat32Array([0.037,0.029,0.016,0.001]),
						[7,4][lod],[7,4][lod],phase,0.73,1.0,float(k)+branch)
		# A scattered veil, with persistent landmarks across LODs. Each fragment is
		# a shallow torn flake rather than a regular pointed jewel.
		var layout := RandomNumberGenerator.new()
		layout.seed = 24601
		for i in 64:
			var rr := sqrt((float(i)+0.5)/64.0)*0.97
			var angle := i * 2.39996323 + layout.randf_range(-0.12,0.12)
			var size := layout.randf_range(0.035,0.068)
			var height := layout.randf_range(0.016,0.033)
			if lod == 1 and i % 3 == 0 or lod == 2 and i % 5 != 0:
				continue
			var at := cap_point(rr,cap_height(rr),angle)
			var n := Vector3(cos(angle)*rr*1.25,1.0-rr*0.55,sin(angle)*rr*1.25).normalized()
			flake(at+n*0.002,n,size,height,[7,5,3][lod])
			if lod == 0 and i % 3 == 0:
				flake(at+Vector3(-sin(angle),0,cos(angle))*size*0.9,n,size*0.43,height*0.47,5)


	func finish() -> ArrayMesh:
		st.generate_tangents()
		st.index()
		st.optimize_indices_for_cache()
		var result := st.commit()
		result.surface_set_name(0,"wartling_opaque")
		return result
