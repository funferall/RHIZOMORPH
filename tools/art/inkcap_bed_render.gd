extends "res://tools/art/render_unit.gd"

func _initialize() -> void:
	unit = "inkcap_bed"
	output = "res://art/inkcap_bed"
	_run.call_deferred()

func _run() -> void:
	var ink = load("res://scripts/inkcap_bed.gd")
	var vp := _view(ink.mesh(), Vector2i(1200, 1000), 0.0)
	_caption(vp, "INKCAP BED", "Morel Hollow / deliquescing caps", 30)
	await _settle(20)
	_save(vp, "inkcap_bed_hero.png")
	var mi: MeshInstance3D = vp.get_node("Stage/Unit")
	var dir := output.path_join("frames_drip")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
	for i in 36:
		mi.set_instance_shader_parameter("motion_time", float(i) / 36.0 / 0.65)
		await _settle(2)
		vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(dir.path_join("%03d.png" % i)))
	print("INKCAP BED REVIEW COMPLETE")
	quit()
