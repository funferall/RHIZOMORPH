extends SceneTree
## Run: godot --headless --path . --script tools/cep_bulwark/check_cep_bulwark.gd

const CepBulwark := preload("res://scripts/cep_bulwark.gd")
const FungusLib := preload("res://scripts/fungus_lib.gd")


func _initialize() -> void:
	var previous := 100000
	for lod in 3:
		var mesh := CepBulwark.mesh(lod)
		assert(mesh == CepBulwark.mesh(lod), "Meshes must be shared, not rebuilt")
		assert(mesh.get_surface_count() == 1, "One material surface per LOD")
		assert(mesh.surface_get_material(0) == CepBulwark.material())
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		assert(tangents.size() == verts.size() * 4)
		for tangent in tangents:
			assert(is_finite(tangent), "Invalid normal-map tangent")
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var tags: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var phases := {}
		for i in verts.size():
			assert(uvs[i].is_finite() and uvs[i].x > 0.0 and uvs[i].x < 1.0)
			assert(uvs[i].y > 0.0 and uvs[i].y < 1.0, "UV outside padded atlas")
			if tags[i].x > 2.5:
				phases[tags[i].y] = true
		assert(phases.size() == 4, "All four legs need distinct crawl phases")
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert(not indices.is_empty() and indices.size() % 3 == 0)
		var triangles := indices.size() / 3
		assert(triangles < previous, "Every LOD must actually reduce geometry")
		assert(triangles <= [10000, 3500, 900][lod], "Geometry budget exceeded")
		assert(verts.size() < indices.size(), "Mesh should reuse indexed vertices")
		previous = triangles
		for i in verts.size():
			assert(verts[i].is_finite() and normals[i].is_finite())
			assert(absf(normals[i].length() - 1.0) < 0.01)
			assert(colors[i].a >= 0.0 and colors[i].a <= 1.0)
		for i in range(0, indices.size(), 3):
			var a := indices[i]
			var b := indices[i + 1]
			var c := indices[i + 2]
			var cross := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			assert(cross.length_squared() > 0.0000000001, "Degenerate triangle")
			assert(cross.dot(normals[a] + normals[b] + normals[c]) <= 0.00001, "Wrong front-face winding")
		var bounds := mesh.get_aabb()
		assert(bounds.size.x > 2.3 and bounds.size.z > 1.9)
		assert(bounds.end.y > 1.45 and bounds.end.y < 1.8)
		assert(mesh.custom_aabb.encloses(bounds.grow(1.049)), "Culling bounds must include the shader stride")
		print("CEP BULWARK " + JSON.stringify(CepBulwark.stats(lod)))
	for name in ["albedo_map", "normal_roughness_map"]:
		var texture: Texture2D = CepBulwark.material().get_shader_parameter(name)
		assert(texture.get_width() == 512 and texture.get_height() == 512)
		assert(texture.get_image().has_mipmaps())
	assert(FungusLib.mesh("u_cep_bulwark") == CepBulwark.mesh(0))
	assert(CepBulwark.choose_lod(110.0, 1) == 0)
	assert(CepBulwark.choose_lod(85.0, 0) == 0)
	assert(CepBulwark.choose_lod(85.0, 1) == 1)
	assert(CepBulwark.choose_lod(16.0, 1) == 2)
	assert(CepBulwark.choose_lod(20.0, 2) == 2)
	assert(CepBulwark.choose_lod(24.0, 1) == 1)
	assert(CepBulwark.choose_lod(30.0, 2) == 1)
	if "--exports" in OS.get_cmdline_user_args():
		for lod in 3:
			var path: String = "res://art/cep_bulwark/cep_bulwark_" + CepBulwark.LOD_NAMES[lod] + ".res"
			var saved: ArrayMesh = load(path)
			assert(saved.surface_get_array_index_len(0) == CepBulwark.mesh(lod).surface_get_array_index_len(0))
			var mat: ShaderMaterial = saved.surface_get_material(0)
			for name in ["albedo_map", "normal_roughness_map"]:
				var texture: Texture2D = mat.get_shader_parameter(name)
				assert(texture.get_width() == 512 and texture.get_height() == 512)
	print("CEP BULWARK CHECKS PASSED")
	quit()
