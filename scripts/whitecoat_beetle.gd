extends RefCounted
## The beetle, healthy and as the Choir's Whitecoat Bulwark (Leptinotarsa x Beauveria, after
## reference_images/veiled_choir_roster.png). Built in Blender by tools/blender/beetle_build.py:
## a domed, black-striped cream shell, an orange pronotum and head spotted black, stout orange
## legs, and cottony white Beauveria tufts bursting from every seam, baked onto three low-poly
## meshes sharing one 1024 atlas. One opaque surface, one draw call.
##
## Both forms come from the same GLBs: a healthy beetle's mesh drops the tuft triangles; the
## shader swells the tufts out of the seams and dusts the shell white as `infect` rises, so a
## wild beetle sickening near a Choir lure turns white before it rises as a thrall.
## The shader walks it on alternating tripods and plays the attack: it rears onto its hind
## legs with mandibles open, then slams down and bites; the blow lands at IMPACT.

const SHADER := preload("res://shaders/whitecoat_beetle.gdshader")
const SCENES := [
	preload("res://art/beetle/beetle_close.glb"),
	preload("res://art/beetle/beetle_battle.glb"),
	preload("res://art/beetle/beetle_distant.glb"),
]
const ALBEDO := preload("res://art/beetle/beetle_albedo.png")
const NORMAL := preload("res://art/beetle/beetle_normal.png")
const ORM := preload("res://art/beetle/beetle_orm.png")
const LOD_NAMES := ["close", "battle", "distant"]
const LOD_SIZE := 1.15        # body length (m), for on-screen detail choice
const HEIGHT := 0.86
const SWING_SECONDS := 0.75   # the attack animation
const IMPACT := 0.4           # the bite lands this far in (= IMPACT in the shader)
const WINDUP_SECONDS := 0.3   # IMPACT * SWING_SECONDS; Data's "windup"
const TUFT_KIND := 4.5        # data UV kinds above this are Beauveria tufts
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


## infected: with the Beauveria tufts (a thrall, or a wild beetle that has begun to sicken).
static func mesh(lod := 0, infected := true) -> ArrayMesh:
	lod = clampi(lod, 0, 2)
	var key := lod * 2 + int(infected)
	if not _meshes.has(key):
		var root: Node = SCENES[lod].instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		root.free()
		if not infected:
			arrays = _without_tufts(arrays)
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.resource_name = "Beetle_%s_%s" % [LOD_NAMES[lod], "infected" if infected else "healthy"]
		m.surface_set_material(0, material())
		m.custom_aabb = m.get_aabb().grow(0.3)   # rearing and the lunge move it
		_meshes[key] = m
	return _meshes[key]


# Drops every triangle that touches a tuft and compacts the vertex arrays.
static func _without_tufts(arrays: Array) -> Array:
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var remap := PackedInt32Array()
	remap.resize(uv2.size())
	remap.fill(-1)
	var kept := PackedInt32Array()
	var out_idx := PackedInt32Array()
	for i in range(0, idx.size(), 3):
		if uv2[idx[i]].x > TUFT_KIND or uv2[idx[i + 1]].x > TUFT_KIND or uv2[idx[i + 2]].x > TUFT_KIND:
			continue
		for k in 3:
			var v := idx[i + k]
			if remap[v] < 0:
				remap[v] = kept.size()
				kept.append(v)
			out_idx.append(remap[v])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		var src = arrays[slot]
		if src == null or slot == Mesh.ARRAY_INDEX:
			continue
		if slot == Mesh.ARRAY_TANGENT:
			var dst := PackedFloat32Array()
			dst.resize(kept.size() * 4)
			for n in kept.size():
				for c in 4:
					dst[n * 4 + c] = src[kept[n] * 4 + c]
			out[slot] = dst
		else:
			var dst = src.duplicate()
			dst.resize(kept.size())
			for n in kept.size():
				dst[n] = src[kept[n]]
			out[slot] = dst
	out[Mesh.ARRAY_INDEX] = out_idx
	return out


static func stats(lod: int, infected := true) -> Dictionary:
	var m := mesh(lod, infected)
	return {"lod": LOD_NAMES[lod] + ("" if infected else " healthy"), "triangles": m.surface_get_array_index_len(0) / 3,
		"vertices": m.surface_get_array_len(0), "surfaces": m.get_surface_count()}


static func choose_lod(pixels: float, current: int) -> int:
	if current == 0:
		return 1 if pixels < 80.0 else 0
	if current == 2:
		return 1 if pixels > 26.0 else 2
	if pixels > 96.0:
		return 0
	return 2 if pixels < 20.0 else 1
