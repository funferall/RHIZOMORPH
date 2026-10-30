extends Node3D
# Orbit camera that dives from a tilt-shift overview down to moss level.
# Pitch flattens as you zoom in; depth of field follows the focus point.

const Data = preload("res://scripts/data.gd")

var cam := Camera3D.new()
var attrs := CameraAttributesPractical.new()
var target := Vector3.ZERO
var yaw := 0.0
var dist := 70.0
var pitch_bias := 0.0
var min_dist := 5.0
var max_dist := 110.0
var board: Node3D

var _goal_target := Vector3.ZERO
var _goal_dist := 70.0


func _ready() -> void:
	add_child(cam)
	cam.fov = 38.0
	cam.near = 0.1
	cam.far = 800.0
	cam.attributes = attrs
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_amount = 0.09
	cam.current = true
	_goal_target = target
	_goal_dist = dist


func pitch() -> float:
	var t := inverse_lerp(min_dist, max_dist, dist)
	return clampf(lerpf(14.0, 58.0, pow(t, 0.6)) + pitch_bias, 6.0, 85.0)


func set_view(y: float, d: float, at: Vector3, bias := 0.0) -> void:
	yaw = y
	dist = d
	_goal_dist = d
	target = at
	_goal_target = at
	pitch_bias = bias


func focus(at: Vector3) -> void:
	_goal_target = at


func zoom(f: float) -> void:
	_goal_dist = clampf(_goal_dist * f, min_dist, max_dist)


func pan(screen_delta: Vector2) -> void:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var s := dist * 0.0016
	_goal_target += (right * screen_delta.x + fwd * screen_delta.y) * s
	_clamp_target()


func pan_world(v: Vector2) -> void:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	_goal_target += right * v.x + fwd * v.y
	_clamp_target()


func _clamp_target() -> void:
	_goal_target.x = clampf(_goal_target.x, -Data.HALF_W, Data.HALF_W)
	_goal_target.z = clampf(_goal_target.z, -Data.HALF_D, Data.HALF_D)


func snap() -> void:
	target = _goal_target
	dist = _goal_dist
	_apply()


func _process(delta: float) -> void:
	var k := 1.0 - exp(-delta * 9.0)
	target = target.lerp(_goal_target, k)
	dist = lerpf(dist, _goal_dist, k)
	if board:
		var gy: float = board.ground_y(Vector2(target.x, target.z))
		target.y = lerpf(target.y, gy + 0.5, k)
	_apply()


func _apply() -> void:
	var p := deg_to_rad(pitch())
	var offs := Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist
	var pos := target + offs
	if board:
		pos.y = maxf(pos.y, board.ground_y(Vector2(pos.x, pos.z)) + 0.6)
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	attrs.dof_blur_far_distance = dist * 1.12
	attrs.dof_blur_far_transition = dist * 0.9
	attrs.dof_blur_near_distance = dist * 0.55
	attrs.dof_blur_near_transition = dist * 0.45
	attrs.dof_blur_amount = lerpf(0.13, 0.07, inverse_lerp(min_dist, max_dist, dist))
