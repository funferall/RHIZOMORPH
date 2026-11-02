extends RefCounted
## A single shared multi-mesh of pointed Xylaria fruiting bodies per ground strike.
static var _mesh: CylinderMesh
static var _material: ShaderMaterial

static func instance() -> MultiMeshInstance3D:
	if _mesh == null:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = 0.004
		_mesh.bottom_radius = 0.075
		_mesh.height = 1.0
		_mesh.radial_segments = 7
		_mesh.rings = 1
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/runner_spikes.gdshader")
		_mesh.material = _material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = 9
	# Fixed pattern avoids consuming gameplay RNG for a cosmetic effect.
	for i in 9:
		var angle := float(i - 1) * TAU / 8.0
		var radius := 0.0 if i == 0 else 0.72
		var height := 1.30 if i == 0 else (0.80 + 0.10 * (i % 4))
		var base := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var tilt := Vector3(sin(angle) * 0.14, 0.0, -cos(angle) * 0.14) if i != 0 else Vector3.ZERO
		var basis := Basis.from_euler(tilt) * Basis.from_scale(Vector3(1.0, height, 1.0))
		mm.set_instance_transform(i, Transform3D(basis, base + basis * Vector3(0.0, 0.5, 0.0)))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale.y = 0.001
	return node
