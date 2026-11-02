extends RefCounted
## Muscarine Spitter (Amanita muscaria), the Court's ranged gunner. The art is built in
## Blender by tools/blender/spitter_build.py: a tall, top-heavy sporeling on four volva bulbs
## with a squeezed, hooked cone of a cap, baked onto three low-poly meshes sharing one 1024
## atlas. One opaque surface and one draw call; the shader wobbles the stalk as it waddles,
## and coils, squeezes and lashes it to spit.

const SHADER := preload("res://shaders/muscarine_spitter.gdshader")
const SCENES := [
	preload("res://art/spitter/spitter_close.glb"),
	preload("res://art/spitter/spitter_battle.glb"),
	preload("res://art/spitter/spitter_distant.glb"),
]
const ALBEDO := preload("res://art/spitter/spitter_albedo.png")
const NORMAL := preload("res://art/spitter/spitter_normal.png")
const ORM := preload("res://art/spitter/spitter_orm.png")
const LOD_NAMES := ["close", "battle", "distant"]
const LOD_SIZE := 1.2      # body width (m), for on-screen detail choice
const HEIGHT := 1.95
const SWING_SECONDS := 0.85   # the spit animation; the glob leaves 35% of the way in
const WINDUP_SECONDS := 0.3   # = SPIT in the shader * SWING_SECONDS; Data's "windup"
const MUZZLE := Vector3(0.05, 1.28, 0.0)   # the throat, as the cap lashes forward
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
		m.resource_name = "Spitter_" + LOD_NAMES[lod]
		m.surface_set_material(0, material())
		m.custom_aabb = m.get_aabb().grow(0.35)   # the sway and the lash move it
		_meshes[lod] = m
	return _meshes[lod]


static func stats(lod: int) -> Dictionary:
	var m := mesh(lod)
	return {"lod": LOD_NAMES[lod], "triangles": m.surface_get_array_index_len(0) / 3,
		"vertices": m.surface_get_array_len(0), "surfaces": m.get_surface_count()}


static func choose_lod(pixels: float, current: int) -> int:
	if current == 0:
		return 1 if pixels < 80.0 else 0
	if current == 2:
		return 1 if pixels > 26.0 else 2
	if pixels > 96.0:
		return 0
	return 2 if pixels < 20.0 else 1
