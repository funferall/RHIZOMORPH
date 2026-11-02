extends RefCounted
## Turkey tail shelves and rotten stump, sharing a single baked material.
const SCENE := preload("res://art/bracket/bracket.glb")
const SHADER := preload("res://shaders/rot_bracket.gdshader")
const ALBEDO := preload("res://art/bracket/bracket_albedo.png")
const NORMAL := preload("res://art/bracket/bracket_normal.png")
const ORM := preload("res://art/bracket/bracket_orm.png")
const HEIGHT := 1.5
static var _mesh: ArrayMesh

static func mesh(_lod := 0) -> ArrayMesh:
	if _mesh == null:
		var root: Node = SCENE.instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(0))
		root.free()
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("albedo_map", ALBEDO)
		mat.set_shader_parameter("normal_map", NORMAL)
		mat.set_shader_parameter("orm_map", ORM)
		_mesh.surface_set_material(0, mat)
		_mesh.resource_name = "RotBracket"
	return _mesh

static func stats(_lod := 0) -> Dictionary:
	var m := mesh()
	return {"lod": "static", "triangles": m.surface_get_array_index_len(0) / 3, "vertices": m.surface_get_array_len(0), "surfaces": m.get_surface_count()}
