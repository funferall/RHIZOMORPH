extends RefCounted
## Pilobolus Sniper: shared Blender meshes, atlas and game-time cup recoil.

const SHADER := preload("res://shaders/pilobolus_sniper.gdshader")
const GEL_SHADER := preload("res://shaders/pilobolus_gel.gdshader")
const SCENES := [
	preload("res://art/sniper/sniper_close.glb"),
	preload("res://art/sniper/sniper_battle.glb"),
	preload("res://art/sniper/sniper_distant.glb"),
]
const ALBEDO := preload("res://art/sniper/sniper_albedo.png")
const NORMAL := preload("res://art/sniper/sniper_normal.png")
const LOD_NAMES := ["close", "battle", "distant"]
const LOD_SIZE := 1.8     # cap width (m), for on-screen detail choice
const HEIGHT := 1.99
const SWING_SECONDS := 0.90
const WINDUP_SECONDS := 0.24
const MUZZLE := Vector3(0.32, 1.78, 0.0)
static var _meshes := {}
static var _material: ShaderMaterial
static var _gel_material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("albedo_map", ALBEDO)
		_material.set_shader_parameter("normal_map", NORMAL)
	return _material


static func mesh(lod := 0) -> ArrayMesh:
	lod = clampi(lod, 0, 2)
	if not _meshes.has(lod):
		var root: Node = SCENES[lod].instantiate()
		var m := ArrayMesh.new()
		if _gel_material == null:
			_gel_material = ShaderMaterial.new()
			_gel_material.shader = GEL_SHADER
			_gel_material.set_shader_parameter("albedo_map", ALBEDO)
		for part in ["Opaque", "Gel"]:
			var mi: MeshInstance3D = root.find_child(part + "*", true, false)
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(0))
			m.surface_set_material(m.get_surface_count() - 1, material() if part == "Opaque" else _gel_material)
		root.free()
		m.resource_name = "Sniper_" + LOD_NAMES[lod]
		m.custom_aabb = m.get_aabb().grow(0.3)
		_meshes[lod] = m
	return _meshes[lod]


static func stats(lod: int) -> Dictionary:
	var m := mesh(lod)
	return {"lod": LOD_NAMES[lod], "triangles": (m.surface_get_array_index_len(0) + m.surface_get_array_index_len(1)) / 3,
		"vertices": m.surface_get_array_len(0) + m.surface_get_array_len(1), "surfaces": m.get_surface_count()}


static func choose_lod(pixels: float, current: int) -> int:
	if current == 0:
		return 1 if pixels < 80.0 else 0
	if current == 2:
		return 1 if pixels > 26.0 else 2
	if pixels > 96.0:
		return 0
	return 2 if pixels < 20.0 else 1
