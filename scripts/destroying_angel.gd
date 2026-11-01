extends RefCounted
## The Destroying Angel's skinned visual: three GLB detail levels that share one
## 13-joint skeleton layout and three clips (Idle 2.4 s, Walk 1.2 s, Attack 0.95 s).
## One scene is instanced per unit; LOD swaps only the mesh and skin.
## Revealed and cloaked looks are two shared materials, swapped on state change.

const SCENES := [
	preload("res://art/destroying_angel/destroying_angel.glb"),
	preload("res://art/destroying_angel/destroying_angel_battle.glb"),
	preload("res://art/destroying_angel/destroying_angel_distant.glb"),
]
const SHADER := preload("res://shaders/destroying_angel.gdshader")
const CLOAK_SHADER := preload("res://shaders/destroying_angel_cloak.gdshader")
const SKIN_MAP := preload("res://art/destroying_angel/angel_skin.png")
const DETAIL_MAP := preload("res://art/destroying_angel/surface_detail.png")
const SCALE := 0.8            # the GLB stands 2.5 m; in the game it towers over a Wartling at 2 m
const HEIGHT := 2.5 * SCALE
const ATTACK_SECONDS := 0.95
const IMPACT := 0.43          # fraction of the Attack clip where the blades connect
const YAW := PI * 0.5         # the GLB faces +Z; game units face +X

static var _lods := {}
static var _mats := {}


# [mesh, skin] for a detail level, pulled once out of its imported scene.
static func lod(level: int) -> Array:
	level = clampi(level, 0, 2)
	if not _lods.has(level):
		var n: Node = SCENES[level].instantiate()
		var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
		_lods[level] = [mi.mesh, mi.skin]
		n.free()
	return _lods[level]


static func material(cloaked: bool) -> ShaderMaterial:
	if not _mats.has(cloaked):
		var m := ShaderMaterial.new()
		m.shader = CLOAK_SHADER if cloaked else SHADER
		m.set_shader_parameter("skin_map", SKIN_MAP)
		m.set_shader_parameter("detail_map", DETAIL_MAP)
		_mats[cloaked] = m
	return _mats[cloaked]


# A fresh rig at battle detail. Returns [root, mesh instance, animation player].
# The player is advanced by hand with game time, so pause and speed apply.
static func instance() -> Array:
	var root: Node3D = SCENES[1].instantiate()
	root.scale = Vector3.ONE * SCALE
	root.rotation.y = YAW
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	mi.material_override = material(false)
	# the attack lunges forward and the hood sways; bones leave the bind-pose box
	mi.custom_aabb = AABB(Vector3(-1.0, -0.2, -1.0), Vector3(2.0, 3.2, 3.0))
	var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	for clip in ["Idle", "Walk"]:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("Idle")
	player.seek(randf() * 2.4, true)
	return [root, mi, player]


static func set_lod(mi: MeshInstance3D, level: int) -> void:
	var pair := lod(level)
	mi.mesh = pair[0]
	mi.skin = pair[1]


# Same hysteresis idea as the Wartling, judged on the figure's projected height.
static func choose_lod(pixels: float, current: int) -> int:
	if current == 0:
		return 1 if pixels < 110.0 else 0
	if current == 2:
		return 1 if pixels > 34.0 else 2
	if pixels > 140.0:
		return 0
	return 2 if pixels < 26.0 else 1
