extends SceneTree
## Run: godot --headless --path . --script tools/wartling/check_wartling.gd

const Wartling := preload("res://scripts/wartling.gd")
const FungusLib := preload("res://scripts/fungus_lib.gd")


func _initialize() -> void:
	var previous := 100000
	for lod in 3:
		var mesh := Wartling.mesh(lod)
		assert(mesh == Wartling.mesh(lod), "Meshes must be shared, not rebuilt")
		assert(mesh.get_surface_count() == 1, "One material surface per LOD")
		assert(mesh.surface_get_material(0) == Wartling.material())
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		assert(tangents.size() == verts.size() * 4)
		for tangent in tangents:
			assert(is_finite(tangent), "Invalid normal-map tangent")
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert(not indices.is_empty() and indices.size() % 3 == 0)
		var triangles := indices.size() / 3
		assert(triangles < previous, "Every LOD must actually reduce geometry")
		assert(triangles <= [9000, 4200, 650][lod], "Geometry budget exceeded")
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
		assert(bounds.size.x > 1.3 and bounds.size.z > 1.3)
		assert(bounds.end.y > 0.97 and bounds.end.y < 1.2)
		assert(mesh.custom_aabb.encloses(bounds.grow(0.149)), "Culling bounds must include the shader stride")
		print("WARTLING " + JSON.stringify(Wartling.stats(lod)))
	for name in ["surface_map", "normal_map"]:
		var texture: Texture2D = Wartling.material().get_shader_parameter(name)
		assert(texture.get_width() == 256 and texture.get_height() == 256)
		assert(texture.get_image().has_mipmaps())
	assert(FungusLib.mesh("u_wartling") == Wartling.mesh(0))
	assert(Wartling.choose_lod(100.0, 1) == 0)
	assert(Wartling.choose_lod(80.0, 0) == 0)
	assert(Wartling.choose_lod(80.0, 1) == 1)
	assert(Wartling.choose_lod(16.0, 1) == 2)
	assert(Wartling.choose_lod(20.0, 2) == 2)
	assert(Wartling.choose_lod(20.0, 1) == 1)
	assert(Wartling.choose_lod(30.0, 2) == 1)
	print("WARTLING CHECKS PASSED")
	quit()
