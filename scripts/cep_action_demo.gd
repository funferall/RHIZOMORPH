extends Node3D
## Interactive, deterministic action fixture. Not the RTS projectile manager.
const Cep := preload("res://scripts/cep_bulwark.gd")
const Actions := preload("res://scripts/cep_actions.gd")
const Wartling := preload("res://scripts/wartling.gd")
var actions := Actions.new()
var unit: MeshInstance3D
var target: MeshInstance3D
var trails: MultiMeshInstance3D
var area: MeshInstance3D
var rubble: MultiMeshInstance3D
var shots: Array[Dictionary] = []
var received_damage := 0.0
var ally_damage := 0.0
var captured_count := 0
var impact_age := 10.0
var _flash := 0.0
var _shot_mesh := SphereMesh.new()
var _shot_material := StandardMaterial3D.new()

func _ready() -> void:
	unit = MeshInstance3D.new()
	unit.name = "Unit"
	unit.mesh = Cep.mesh(0)
	add_child(unit)
	target = MeshInstance3D.new()
	target.mesh = Wartling.mesh(1)
	target.scale = Vector3.ONE * 0.75
	target.position.x = 1.95
	target.visible = false
	add_child(target)
	area = MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 96:
		var a := TAU * i / 96.0
		var b := TAU * (i + 1) / 96.0
		for radius in [Actions.CAPTURE_RADIUS, Actions.CAPTURE_RADIUS - 0.14]:
			var p := [Vector3(cos(a),0.018,sin(a))*Vector3(radius,1,radius),
				Vector3(cos(b),0.018,sin(b))*Vector3(radius,1,radius),
				Vector3(cos(b),0.018,sin(b))*Vector3(radius-0.035,1,radius-0.035),
				Vector3(cos(a),0.018,sin(a))*Vector3(radius-0.035,1,radius-0.035)]
			for j in [0,2,1,0,3,2]:
				st.add_vertex(p[j])
	area.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.76,0.83,0.20)
	area.material_override = mat
	add_child(area)
	rubble = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var rock := SphereMesh.new()
	rock.radius = 0.10
	rock.height = 0.16
	rock.radial_segments = 6
	rock.rings = 3
	mm.mesh = rock
	mm.instance_count = 20
	rubble.multimesh = mm
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.36,0.25,0.12)
	rubble.material_override = earth
	add_child(rubble)
	_shot_mesh.radius = 0.055
	_shot_mesh.height = 0.11
	_shot_mesh.radial_segments = 8
	_shot_mesh.rings = 4
	_shot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shot_material.albedo_color = Color(1.0,0.35,0.08)
	trails = MultiMeshInstance3D.new()
	var trail_mm := MultiMesh.new()
	trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	var streak := CylinderMesh.new()
	streak.top_radius = 0.012
	streak.bottom_radius = 0.006
	streak.height = 1.0
	streak.radial_segments = 5
	trail_mm.mesh = streak
	trail_mm.instance_count = 96
	trail_mm.visible_instance_count = 0
	trails.multimesh = trail_mm
	trails.material_override = _shot_material
	add_child(trails)
	actions.bash_impact.connect(_on_bash_impact)
	_apply_pose()

func _process(delta: float) -> void:
	advance(delta)

func _on_bash_impact() -> void:
	impact_age = 0.0
	target.set_instance_shader_parameter("flash", 0.7)

func fire(lane := 0.0) -> void:
	var shot := MeshInstance3D.new()
	shot.mesh = _shot_mesh
	shot.material_override = _shot_material
	shot.position = Vector3(4.4,0.80,lane)
	add_child(shot)
	shots.append({"node":shot, "target":Vector3(-4.0,0.7,-lane*0.35), "captured":false,
		"entry":Vector3.ZERO, "progress":0.0, "damage":100.0, "trail":[]})

func advance(delta: float) -> void:
	impact_age += delta
	actions.advance(delta)
	_flash = maxf(0.0, _flash - delta * 3.0)
	for i in range(shots.size()-1, -1, -1):
		var shot := shots[i]
		var node: MeshInstance3D = shot["node"]
		var done := false
		if shot["captured"]:
			shot["progress"] = minf(1.0, shot["progress"] + delta / 0.45)
			var t: float = shot["progress"]
			var end := Vector3(0.06,0.69,0)
			var start: Vector3 = shot["entry"]
			var bend := start.lerp(end,0.48) + Vector3(0,0.65,0.5 if start.z >= 0 else -0.5)
			node.position = start * (1-t)*(1-t) + bend*2*t*(1-t) + end*t*t
			if t >= 1.0:
				received_damage += shot["damage"]
				captured_count += 1
				_flash = 0.65
				done = true
		else:
			var next := node.position.move_toward(shot["target"], delta*7.0)
			var entry := Actions.entry_fraction(node.position,next,Vector3.ZERO)
			if actions.capture_active() and entry >= 0.0:
				shot["entry"] = node.position.lerp(next,entry)
				shot["captured"] = true
				# Snapshot once on capture; no stacking or repeated damage reduction.
				shot["damage"] = actions.capture_damage(shot["damage"])
				node.position = shot["entry"]
			else:
				node.position = next
				if next.is_equal_approx(shot["target"]):
					ally_damage += shot["damage"]
					done = true
		shot["trail"].append(node.position)
		if shot["trail"].size() > 8:
			shot["trail"].pop_front()
		if done:
			node.queue_free()
			shots.remove_at(i)
	var count := 0
	for shot in shots:
		var history: Array = shot["trail"]
		for j in range(1,history.size()):
			if count >= 96:
				break
			var delta_point: Vector3 = history[j] - history[j-1]
			var length_value := delta_point.length()
			if length_value < 0.00001:
				continue
			var basis := Basis(Quaternion(Vector3.UP,delta_point/length_value)) * Basis.from_scale(Vector3(1,length_value,1))
			trails.multimesh.set_instance_transform(count,Transform3D(basis,(history[j]+history[j-1])*0.5))
			count += 1
	trails.multimesh.visible_instance_count = count
	_apply_pose()

func _apply_pose() -> void:
	unit.set_instance_shader_parameter("motion_time", actions.clock)
	unit.set_instance_shader_parameter("walk", actions.walking)
	unit.set_instance_shader_parameter("brace", actions.brace)
	unit.set_instance_shader_parameter("bash", actions.bash)
	unit.set_instance_shader_parameter("flash", _flash)
	target.position.x = 1.95 + 0.45 * (1.0-exp(-impact_age*18.0)) * exp(-impact_age*2.8)
	target.set_instance_shader_parameter("flash", maxf(0,0.7-impact_age*4.0))
	area.visible = actions.capture_active()
	area.scale = Vector3.ONE * (1.0+sin(actions.clock*5.0)*0.008)
	rubble.visible = actions.brace > 0.01 or impact_age < 0.45
	for i in 20:
		var angle := TAU * i / 20.0
		if actions.brace < 0.01 and impact_age < 0.45:
			angle = -0.65 + float(i)/19.0*1.3
		var r := 1.25 + 0.07*sin(i*4.1)
		var transition := sin(actions.brace*PI)
		var impact := maxf(0,1.0-impact_age/0.45)
		var point := Vector3(cos(angle)*r,0.035+sin(i*7.0)*0.02+transition*0.13+impact*0.12,sin(angle)*r*0.86)
		rubble.multimesh.set_instance_transform(i,Transform3D(Basis.from_euler(Vector3(i,angle,i*0.3))*0.6,point))
