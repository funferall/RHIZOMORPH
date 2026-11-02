extends MeshInstance3D
## Blade-attached air ribbons. Explicit game-time updates preserve pause/speed.
## Lives under the unit rig, so fog visibility also hides every streak.

const LIFE := 0.12
var rig: Skeleton3D
var ribbons: Array = [[], [], [], [], [], []]
var elapsed := 0.0
var blade_bones: Array[int] = []
var surface := ImmediateMesh.new()
static var shared_material: StandardMaterial3D


func _ready() -> void:
	rig = get_parent().find_children("*", "Skeleton3D", true, false)[0]
	blade_bones.assign([rig.find_bone("Blade_L"), rig.find_bone("Blade_R")])
	mesh = surface
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shared_material == null:
		shared_material = StandardMaterial3D.new()
		shared_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shared_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shared_material.vertex_color_use_as_albedo = true
		shared_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = shared_material
	custom_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 5, 6))


func tick(dt: float, anim: AnimationPlayer, cloaked: bool) -> void:
	if dt <= 0.0:
		return
	elapsed += dt
	surface.clear_surfaces()
	if cloaked:
		for ribbon: Array in ribbons:
			ribbon.clear()
		return
	var cutting := anim.current_animation == "Attack" and anim.current_animation_position >= 0.95 * 0.35 and anim.current_animation_position <= 0.95 * 0.54
	if not cutting and ribbons.all(func(ribbon: Array) -> bool: return ribbon.is_empty()):
		return
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var bone := blade_bones[side]
		var pose := rig.global_transform * rig.get_bone_global_pose(bone)
		for streak in 3:
			var ribbon: Array = ribbons[side * 3 + streak]
			while not ribbon.is_empty() and elapsed - ribbon[0][0] > LIFE:
				ribbon.pop_front()
			if cutting:
				var tip := Vector3(sign_x * 0.39, -0.90, 0.23) * (1.0 - streak * 0.13)
				ribbon.append([elapsed, pose * tip, pose * (tip * (0.94 if streak == 0 else 0.975))])
			if ribbon.size() < 2:
				continue
			surface.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for sample: Array in ribbon:
				var fade: float = pow(1.0 - (elapsed - sample[0]) / LIFE, 1.5)
				surface.surface_set_color(Color(0.90, 0.96, 1.0, fade * (0.72 if streak == 0 else 0.40)))
				surface.surface_add_vertex(to_local(sample[1]))
				surface.surface_set_color(Color(0.90, 0.96, 1.0, 0.0))
				surface.surface_add_vertex(to_local(sample[2]))
			surface.surface_end()
