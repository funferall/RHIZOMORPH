extends RefCounted
## Violet Webcap (Cortinarius violaceus), the Court's ranged control unit.
## The art is built in Blender by tools/blender/webcap_build.py: a high-detail sculpt
## baked onto three low-poly meshes that share one 1024 atlas (colour + silk alpha,
## normals, occlusion / roughness / glow). This script loads them and applies the one
## shared ShaderMaterial. Legs and silk step in the shader; there is no skeleton.

const SHADER := preload("res://shaders/webcap.gdshader")
const SILK_SHADER := preload("res://shaders/webcap_silk.gdshader")
const SCENES := [
	preload("res://art/webcap/webcap_close.glb"),
	preload("res://art/webcap/webcap_battle.glb"),
	preload("res://art/webcap/webcap_distant.glb"),
]
const ALBEDO := preload("res://art/webcap/webcap_albedo.png")
const NORMAL := preload("res://art/webcap/webcap_normal.png")
const ORM := preload("res://art/webcap/webcap_orm.png")
const LOD_NAMES := ["close", "battle", "distant"]
const CAP_R := 0.52
const LOD_SIZE := CAP_R * 2.0   # cap width (m), for on-screen detail choice
const HEIGHT := 1.80
static var _meshes := {}
static var _material: ShaderMaterial
static var _silk: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("albedo_map", ALBEDO)
		_material.set_shader_parameter("normal_map", NORMAL)
		_material.set_shader_parameter("orm_map", ORM)
	return _material


static func silk_material() -> ShaderMaterial:
	if _silk == null:
		_silk = ShaderMaterial.new()
		_silk.shader = SILK_SHADER
		_silk.set_shader_parameter("albedo_map", ALBEDO)
		_silk.set_shader_parameter("orm_map", ORM)
	return _silk


# One mesh, two surfaces: the opaque body, then the blended silk of the cortina.
static func mesh(lod := 0) -> ArrayMesh:
	lod = clampi(lod, 0, 2)
	if not _meshes.has(lod):
		var root: Node = SCENES[lod].instantiate()
		var m := ArrayMesh.new()
		for part in ["_body", "_silk"]:
			for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				if mi.name.ends_with(part):
					m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(0))
		root.free()
		m.resource_name = "Webcap_" + LOD_NAMES[lod]
		m.surface_set_material(0, material())
		m.surface_set_material(1, silk_material())
		m.custom_aabb = m.get_aabb().grow(0.2)   # the stride lifts and swings the feet
		_meshes[lod] = m
	return _meshes[lod]


static func stats(lod: int) -> Dictionary:
	var m := mesh(lod)
	var tris := 0
	var verts := 0
	for s in m.get_surface_count():
		tris += m.surface_get_array_index_len(s) / 3
		verts += m.surface_get_array_len(s)
	return {"lod": LOD_NAMES[lod], "triangles": tris, "vertices": verts, "surfaces": m.get_surface_count(),
		"silk_triangles": m.surface_get_array_index_len(1) / 3}


# Projected cap width in pixels, with hysteresis.
static func choose_lod(pixels: float, current: int) -> int:
	if current == 0:
		return 1 if pixels < 75.0 else 0
	if current == 2:
		return 1 if pixels > 24.0 else 2
	if pixels > 90.0:
		return 0
	return 2 if pixels < 18.0 else 1
