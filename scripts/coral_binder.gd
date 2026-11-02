extends RefCounted
## Shared LODs and baked material for the rooted Coral Binder and wall modules.
const SHADER := preload("res://shaders/coral_binder.gdshader")
const SCENES := [preload("res://art/binder/binder_close.glb"), preload("res://art/binder/binder_battle.glb"), preload("res://art/binder/binder_distant.glb")]
const ALBEDO := preload("res://art/binder/binder_albedo.png")
const NORMAL := preload("res://art/binder/binder_normal.png")
const ORM := preload("res://art/binder/binder_orm.png")
const LOD_NAMES := ["close", "battle", "distant"]
const LOD_SIZE := 1.6
const HEIGHT := 1.35
const SWING_SECONDS := 1.0
static var _meshes := {}
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("albedo_map", ALBEDO)
		_material.set_shader_parameter("normal_map", NORMAL)
		_material.set_shader_parameter("orm_map", ORM)
	return _material

static func mesh(lod := 0) -> ArrayMesh:
	lod = clampi(lod, 0, 2)
	if not _meshes.has(lod):
		var root: Node = SCENES[lod].instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(0))
		root.free()
		m.resource_name = "Binder_" + LOD_NAMES[lod]
		m.surface_set_material(0, material())
		m.custom_aabb = m.get_aabb().grow(0.15)
		_meshes[lod] = m
	return _meshes[lod]

static func stats(lod: int) -> Dictionary:
	var m := mesh(lod)
	return {"lod": LOD_NAMES[lod], "triangles": m.surface_get_array_index_len(0) / 3, "vertices": m.surface_get_array_len(0), "surfaces": m.get_surface_count()}

static func choose_lod(pixels: float, current: int) -> int:
	if current == 0:
		return 1 if pixels < 80.0 else 0
	if current == 2:
		return 1 if pixels > 26.0 else 2
	if pixels > 96.0:
		return 0
	return 2 if pixels < 20.0 else 1
