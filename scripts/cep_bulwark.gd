extends RefCounted
## Cep Bulwark art prototype: four planted limbs, chestnut shield-cap and pores.
## Shared, indexed geometry and two baked atlas maps; no runtime noise or skinning.

const SHADER := preload("res://shaders/cep_bulwark.gdshader")
const LOD_NAMES := ["close", "battle", "distant"]
const CAP_WIDTH := 2.60
const CAP_AT := Vector3(0.035, 1.08, 0.0)
const ATLAS_SIZE := 512
static var _meshes := {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		var maps := _bake_atlas()
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("albedo_map", maps[0])
		_material.set_shader_parameter("normal_roughness_map", maps[1])
	return _material


static func mesh(lod := 0) -> ArrayMesh:
	lod = clampi(lod, 0, 2)
	if not _meshes.has(lod):
		var builder := Builder.new()
		builder.build(lod)
		var result := builder.finish()
		result.resource_name = "CepBulwark_" + LOD_NAMES[lod]
		result.surface_set_material(0, material())
		result.custom_aabb = result.get_aabb().grow(1.05)
		_meshes[lod] = result
	return _meshes[lod]


static func stats(lod: int) -> Dictionary:
	var m := mesh(lod)
	return {"lod": LOD_NAMES[lod], "triangles": m.surface_get_array_index_len(0) / 3,
		"vertices": m.surface_get_array_len(0), "surfaces": m.get_surface_count()}


static func choose_lod(pixels: float, current: int) -> int:
	if current == 0:
		return 1 if pixels < 80.0 else 0
	if current == 2:
		return 1 if pixels > 28.0 else 2
	if pixels > 100.0:
		return 0
	return 2 if pixels < 22.0 else 1


static func _hash_cell(x: int, y: int, seed_value: float) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7 + seed_value) * 43758.5453, 1.0)


static func _cells(u: float, v: float, cols: int, rows: int) -> Vector3:
	# Periodic Worley distances, used only during atlas baking on the CPU.
	var x := u * cols
	var y := v * rows
	var ix := int(floor(x))
	var iy := int(floor(y))
	var first := 10.0
	var second := 10.0
	var seed_value := 0.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cx := ix + dx
			var cy := iy + dy
			var hx := posmod(cx, cols)
			var hy := posmod(cy, rows)
			var jitter := Vector2(_hash_cell(hx, hy, 1.0), _hash_cell(hx, hy, 9.0))
			var distance := Vector2(cx + 0.22 + jitter.x * 0.56 - x,
				cy + 0.22 + jitter.y * 0.56 - y).length_squared()
			if distance < first:
				second = first
				first = distance
				seed_value = _hash_cell(hx, hy, 41.0)
			elif distance < second:
				second = distance
	return Vector3(sqrt(first), sqrt(second) - sqrt(first), seed_value)


static func _tile_noise(noise: FastNoiseLite, x: float, y: float, size: float) -> float:
	var u := x / size
	var v := y / size
	return lerpf(lerpf(noise.get_noise_2d(x, y), noise.get_noise_2d(x - size, y), u),
		lerpf(noise.get_noise_2d(x, y - size), noise.get_noise_2d(x - size, y - size), u), v)


static func _bake_atlas() -> Array[ImageTexture]:
	# Four padded tiles: chestnut cuticle, reticulate stalk, sponge, foot skin.
	# Both images are shared by all units and LODs. Each tile has its own height
	# field, so cap smoothness and deep pores do not share a generic bark normal.
	var albedo := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	var normal := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	var broad := FastNoiseLite.new()
	broad.seed = 72319
	broad.frequency = 0.036
	broad.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = 2194
	fine.frequency = 0.38
	fine.fractal_octaves = 2
	var heights := PackedFloat32Array()
	var roughness := PackedFloat32Array()
	heights.resize(256 * 256)
	roughness.resize(256 * 256)
	for tile in 4:
		var origin := Vector2i((tile % 2) * 256, (tile / 2) * 256)
		for y in 256:
			for x in 256:
				# The 8-pixel guard repeats the tile instead of neighboring materials.
				var px := float(posmod(x - 8, 240))
				var py := float(posmod(y - 8, 240))
				var u := px / 240.0
				var v := py / 240.0
				var b := _tile_noise(broad, px, py, 240.0) * 0.5 + 0.5
				var f := _tile_noise(fine, px, py, 240.0) * 0.5 + 0.5
				var color := Color.WHITE
				var height := 0.0
				var rough := 0.8
				match tile:
					0:
						var cells := _cells(u, v, 9, 9)
						var scar := (1.0 - smoothstep(0.006, 0.027, cells.y)) * smoothstep(0.72, 0.91, cells.z)
						var freckle := smoothstep(0.67, 0.78, f) * 0.3
						color = Color(0.21, 0.092, 0.032).lerp(Color(0.52, 0.29, 0.13), b)
						color = color.lerp(Color(0.67, 0.48, 0.27), scar * 0.30 + freckle)
						height = b * 0.025 + f * 0.045 - scar * 0.035
						rough = 0.39 + f * 0.19 + scar * 0.18
					1:
						var cells := _cells(u, v, 21, 11)
						var net := 1.0 - smoothstep(0.014, 0.075, cells.y)
						var grain := 0.5 + 0.5 * sin(u * TAU * 69.0 + sin(v * TAU * 3.0) * 0.8)
						color = Color(0.73, 0.65, 0.50).lerp(Color(0.89, 0.82, 0.66), b)
						color = color.lerp(Color(0.93, 0.88, 0.73), net * 0.85)
						color *= 0.95 + grain * 0.05
						height = net * 0.15 + f * 0.025 + grain * 0.018
						rough = 0.80 + f * 0.13
					2:
						var cells := _cells(u, v, 41, 41)
						var hole := 1.0 - smoothstep(0.16 + cells.z * 0.045, 0.35 + cells.z * 0.055, cells.x)
						color = Color(0.82, 0.77, 0.34).lerp(Color(0.48, 0.45, 0.15), hole)
						color *= 0.88 + b * 0.22
						height = -hole * 0.23 + f * 0.018
						rough = 0.91
					3:
						var cells := _cells(u, v, 12, 9)
						var seam := 1.0 - smoothstep(0.009, 0.045, cells.y)
						var grain := 0.5 + 0.5 * sin(u * TAU * 41.0 + b * 2.0)
						color = Color(0.72, 0.62, 0.43).lerp(Color(0.94, 0.88, 0.72), b)
						color = color.darkened(seam * 0.09 + (1.0 - grain) * 0.035)
						height = f * 0.055 - seam * 0.07 + grain * 0.025
						rough = 0.84 + f * 0.13
				albedo.set_pixel(origin.x + x, origin.y + y, color)
				heights[y * 256 + x] = height
				roughness[y * 256 + x] = rough
		for y in 256:
			for x in 256:
				var dx := heights[y * 256 + (x + 1) % 256] - heights[y * 256 + (x + 255) % 256]
				var dy := heights[((y + 1) % 256) * 256 + x] - heights[((y + 255) % 256) * 256 + x]
				var n := Vector3(-dx * 4.0, -dy * 4.0, 1.0).normalized()
				normal.set_pixel(origin.x + x, origin.y + y,
					Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, roughness[y * 256 + x]))
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	return [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(normal)]


class Builder:
	var st := SurfaceTool.new()

	func atlas_uv(local: Vector2, kind: int) -> Vector2:
		return (Vector2((kind % 2) * 256 + 8, (kind / 2) * 256 + 8) + local * 240.0) / 512.0


	func triangle(points: Array, normals: Array, uvs: Array, colors: Array,
			kind: int, phase := 0.0, weights := Vector3.ZERO) -> void:
		var a: Vector3 = points[0]
		var b: Vector3 = points[1]
		var c: Vector3 = points[2]
		var cross := (b - a).cross(c - a)
		if cross.length_squared() < 0.0000000001:
			return
		var order := [0, 2, 1] if cross.dot(normals[0] + normals[1] + normals[2]) > 0.0 else [0, 1, 2]
		for i in order:
			var paint: Color = colors[i].srgb_to_linear()
			st.set_color(Color(paint.r, paint.g, paint.b, weights[i]))
			st.set_normal(normals[i])
			st.set_uv(atlas_uv(uvs[i], kind))
			st.set_uv2(Vector2(kind, phase))
			st.add_vertex(points[i])


	func quad(p: Array, n: Array, uv: Array, color: Array, kind: int,
			phase := 0.0, weights := Vector4.ZERO) -> void:
		for ids in [[0, 1, 2], [0, 2, 3]]:
			triangle([p[ids[0]], p[ids[1]], p[ids[2]]], [n[ids[0]], n[ids[1]], n[ids[2]]],
				[uv[ids[0]], uv[ids[1]], uv[ids[2]]], [color[ids[0]], color[ids[1]], color[ids[2]]],
				kind, phase, Vector3(weights[ids[0]], weights[ids[1]], weights[ids[2]]))


	func cap_point(r: float, h: float, angle: float) -> Vector3:
		var lobes := 1.0 + 0.046 * sin(angle * 3.0 + 0.4) + 0.025 * cos(angle * 5.0)
		var x := cos(angle) * r * 1.23 * lobes
		var z := sin(angle) * r * 1.04 * lobes
		var folds := (0.018 * sin(angle * 7.0 + 0.3) + 0.011 * cos(angle * 13.0)) * pow(r, 3.0)
		return CAP_AT + Vector3(x, h * 0.50 + x * 0.105 + z * 0.025 + folds, z)


	func cap(profile: PackedVector2Array, sides: int, kind: int) -> void:
		for j in profile.size() - 1:
			for k in sides:
				var points := []
				var normals := []
				var uv := []
				var colors := []
				var weights := Vector4.ZERO
				var index := 0
				for pair in [[j, k], [j, k + 1], [j + 1, k + 1], [j + 1, k]]:
					var row: int = pair[0]
					var a: float = TAU * pair[1] / sides
					var p := profile[row]
					var tangent := profile[mini(row + 1, profile.size() - 1)] - profile[maxi(row - 1, 0)]
					var n := Vector3(tangent.y * cos(a) / 1.23, -tangent.x / 0.50, tangent.y * sin(a) / 1.04).normalized()
					n = Vector3(n.x - n.y * 0.105, n.y, n.z - n.y * 0.025).normalized()
					points.append(cap_point(p.x, p.y, a))
					normals.append(n)
					uv.append(Vector2(0.5 + cos(a) * p.x * 0.48, 0.5 + sin(a) * p.x * 0.48))
					var color := Color.WHITE
					if kind == 0:
						# Pale flesh at the rolled edge; broad, painted chestnut lobes above.
						var edge := 1.0 - smoothstep(-0.13, 0.025, p.y)
						weights[index] = edge * 0.90
						var shade := 0.88 + 0.12 * (0.5 + 0.5 * cos(a * 3.0 + p.x * 8.0))
						color *= shade
					colors.append(color)
					index += 1
				quad(points, normals, uv, colors, kind, 0.0, weights)


	func body(sides: int, rows: int) -> void:
		for j in rows:
			for k in sides:
				var p := []
				var n := []
				var uv := []
				var color := []
				for pair in [[j, k], [j, k + 1], [j + 1, k + 1], [j + 1, k]]:
					var t: float = float(pair[0]) / rows
					var a: float = TAU * pair[1] / sides
					var y := 0.20 + t * 0.90
					var radius := 0.30 + sin(t * PI) * 0.18 - t * 0.045
					var folds := 1.0 + 0.035 * sin(a * 5.0 + t * 4.0) + 0.02 * cos(a * 9.0 - t * 8.0)
					var lean := Vector3(0.07 * t, 0, 0)
					p.append(lean + Vector3(cos(a) * radius * folds, y, sin(a) * radius * 0.92 * folds))
					var derivative := cos(t * PI) * 0.18 * PI - 0.045
					n.append(Vector3(cos(a), -derivative / 0.90, sin(a) / 0.92).normalized())
					uv.append(Vector2(float(pair[1]) / sides, t))
					color.append(Color(0.83, 0.78, 0.66).lerp(Color.WHITE, smoothstep(0.1, 0.5, t)))
				quad(p, n, uv, color, 1)


	func leg_point(t: float, angle: float, sx: float, sz: float) -> Vector3:
		# Horizontal cross-sections keep the feet broad and flat on the ground.
		var y := 0.025 + t * 0.86
		var cx := sx * (0.79 - 0.36 * smoothstep(0.0, 1.0, t))
		var cz := sz * (0.57 - 0.27 * smoothstep(0.0, 1.0, t))
		var radius := 0.24 + 0.095 * exp(-pow((t - 0.13) / 0.11, 2.0))
		radius += 0.075 * exp(-pow((t - 0.62) / 0.22, 2.0))
		radius *= 1.0 - pow(t, 7.0) * 0.87
		var wrinkles := 1.0 + sin(angle * 5.0 + t * 5.0) * 0.022
		wrinkles += sin(t * 33.0 + angle * 2.0) * 0.025 * smoothstep(0.2, 0.7, t)
		var point := Vector3(cx + cos(angle) * radius * wrinkles, y, cz + sin(angle) * radius * wrinkles * 0.90)
		# A low root buttress reaches inward into the body at the shoulder.
		return point


	func leg(sx: float, sz: float, phase: float, sides: int, rows: int) -> void:
		for j in rows:
			for k in sides:
				var p := []
				var n := []
				var uv := []
				var color := []
				var weights := Vector4.ZERO
				var index := 0
				for pair in [[j, k], [j, k + 1], [j + 1, k + 1], [j + 1, k]]:
					var t: float = float(pair[0]) / rows
					var a: float = TAU * pair[1] / sides
					var point := leg_point(t, a, sx, sz)
					var dt := leg_point(minf(1.0, t + 0.002), a, sx, sz) - leg_point(maxf(0.0, t - 0.002), a, sx, sz)
					var da := leg_point(t, a + 0.002, sx, sz) - leg_point(t, a - 0.002, sx, sz)
					p.append(point)
					n.append(dt.cross(da).normalized())
					uv.append(Vector2(float(pair[1]) / sides, t))
					color.append(Color(0.73, 0.65, 0.48).lerp(Color.WHITE, smoothstep(0.0, 0.30, t)))
					weights[index] = 1.0 - smoothstep(0.16, 0.95, t)
					index += 1
				quad(p, n, uv, color, 3, phase, weights)


		var center := Vector3(sx * 0.79, 0.025, sz * 0.57)
		for k in sides:
			var a := leg_point(0.0, TAU * k / sides, sx, sz)
			var b := leg_point(0.0, TAU * (k + 1) / sides, sx, sz)
			triangle([center, a, b], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN],
				[Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0)],
				[Color(0.65, 0.58, 0.45), Color(0.65, 0.58, 0.45), Color(0.65, 0.58, 0.45)],
				3, phase, Vector3.ONE)


	func toe(at: Vector3, scale_value: Vector3, phase: float, sides: int, rows: int) -> void:
		for j in rows:
			for k in sides:
				var p := []
				var n := []
				var uv := []
				for pair in [[j, k], [j, k + 1], [j + 1, k + 1], [j + 1, k]]:
					var v: float = float(pair[0]) / rows
					var a: float = TAU * pair[1] / sides
					var radial := Vector3(sin(v * PI) * cos(a), cos(v * PI), sin(v * PI) * sin(a))
					p.append(at + radial * scale_value)
					n.append((radial / scale_value).normalized())
					uv.append(Vector2(float(pair[1]) / sides, v))
				quad(p, n, uv, [Color(0.98, 0.96, 0.89), Color(0.98, 0.96, 0.89),
					Color(0.98, 0.96, 0.89), Color(0.98, 0.96, 0.89)], 3, phase, Vector4.ONE)


	func build(lod: int) -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var profiles := [PackedVector2Array([Vector2(0.97,-0.15), Vector2(1.01,-0.08),
			Vector2(1.02,0.04), Vector2(1.00,0.22), Vector2(0.94,0.44), Vector2(0.85,0.64),
			Vector2(0.71,0.82), Vector2(0.54,0.94), Vector2(0.34,1.00), Vector2(0.16,1.02), Vector2(0,1.01)]),
			PackedVector2Array([Vector2(0.97,-0.15), Vector2(1.02,0.04), Vector2(0.97,0.36),
			Vector2(0.82,0.68), Vector2(0.58,0.92), Vector2(0.30,1.01), Vector2(0,1.01)]),
			PackedVector2Array([Vector2(0.97,-0.15),Vector2(1.02,0.05),Vector2(0.88,0.57),Vector2(0.52,0.96),Vector2(0,1.01)])]
		cap(profiles[lod], [96, 40, 20][lod], 0)
		# Bolete tubes, not gills: a shallow sponge under the overhanging cuticle.
		cap(PackedVector2Array([Vector2(0.23,-0.04), Vector2(0.46,-0.30),
			Vector2(0.73,-0.40), Vector2(0.97,-0.15)]), [64, 32, 16][lod], 2)
		body([32, 20, 10][lod], [14, 8, 4][lod])
		var feet := [Vector3(1,1,0.0), Vector3(-1,-1,0.25), Vector3(1,-1,0.5), Vector3(-1,1,0.75)]
		for foot in feet:
			leg(foot.x, foot.y, foot.z, [24, 14, 8][lod], [18, 10, 5][lod])
			if lod < 2:
				for k in 3:
					var offset := float(k - 1) * 0.16
					toe(Vector3(foot.x * 0.99, 0.10, foot.y * 0.57 + offset),
						Vector3(0.15, 0.095, 0.105), foot.z, [12, 8][lod], [8, 5][lod])


	func finish() -> ArrayMesh:
		st.generate_tangents()
		st.index()
		st.optimize_indices_for_cache()
		var result := st.commit()
		result.surface_set_name(0, "cep_bulwark_opaque")
		return result
