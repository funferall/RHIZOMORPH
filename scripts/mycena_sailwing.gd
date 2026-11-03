extends RefCounted
## Mycena Sailwing, the Court's flying skirmisher: seven lilac Mycena bonnets with glowing gold
## gills, fanned out like wings from a pale, hook-beaked fruiting knot that trails its hyphae.
## The art is built in Blender by tools/blender/sailwing_build.py and baked onto three low-poly
## meshes sharing one 1024 atlas. One opaque surface and one draw call. The shader keeps it
## aloft: the bells pulse like a jellyfish's, the wings rise and fall, and the strands stream
## behind. To attack it rears with its bells flared, then claps them shut to throw spore darts.

const SHADER := preload("res://shaders/mycena_sailwing.gdshader")
const SCENES := [
	preload("res://art/sailwing/sailwing_close.glb"),
	preload("res://art/sailwing/sailwing_battle.glb"),
	preload("res://art/sailwing/sailwing_distant.glb"),
]
const ALBEDO := preload("res://art/sailwing/sailwing_albedo.png")
const NORMAL := preload("res://art/sailwing/sailwing_normal.png")
const ORM := preload("res://art/sailwing/sailwing_orm.png")
const LOD_NAMES := ["close", "battle", "distant"]
const LOD_SIZE := 1.8       # wingspan scale (m), for on-screen detail choice
const HEIGHT := 2.1
const SWING_SECONDS := 0.8  # the volley; the darts leave 40% of the way in, as the bells clap shut
const WINDUP_SECONDS := 0.32   # = CLAP in the shader * SWING_SECONDS; Data's "windup"
const MUZZLE := Vector3(0.42, 1.0, 0.0)   # in front of the beak
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
		m.resource_name = "Sailwing_" + LOD_NAMES[lod]
		m.surface_set_material(0, material())
		m.custom_aabb = m.get_aabb().grow(0.45)   # the bob, the flap and the rear move it
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
