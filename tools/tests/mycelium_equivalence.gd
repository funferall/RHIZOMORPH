extends SceneTree
# GPU regression: compare an external reference shader with the current one.
# godot --path . --script tools/tests/mycelium_equivalence.gd -- --reference-sim=PATH
# Use a graphical renderer (a headless dummy device cannot execute compute).
const Data = preload("res://scripts/data.gd")
var rd: RenderingDevice
var owned: Array[RID] = []

func _initialize() -> void:
	run.call_deferred()

func keep(rid: RID) -> RID:
	owned.append(rid)
	return rid

func cleanup() -> void:
	owned.reverse()
	for rid in owned:
		if rid.is_valid():
			rd.free_rid(rid)
	owned.clear()
	if rd != null:
		rd.free()
		rd = null

func uniform(binding: int, rid: RID, type: int) -> RDUniform:
	var u := RDUniform.new()
	u.binding = binding
	u.uniform_type = type
	u.add_id(rid)
	return u

func run() -> void:
	var reference := ""
	var benchmark := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--benchmark":
			benchmark = true
		if arg.begins_with("--reference-sim="):
			reference = arg.trim_prefix("--reference-sim=")
	if not FileAccess.file_exists(reference):
		push_error("Supply --reference-sim=PATH to the original myc_sim.glsl")
		quit(1)
		return
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("GPU rendering device required")
		quit(1)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 67291
	var cells := Data.SIM_W * Data.SIM_H
	var substrate := PackedByteArray()
	substrate.resize(cells * 4)
	for i in substrate.size():
		substrate[i] = rng.randi_range(0, 255)
	var sf := RDTextureFormat.new()
	sf.width = Data.SIM_W
	sf.height = Data.SIM_H
	sf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	sf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var sub := keep(rd.texture_create(sf, RDTextureView.new(), [substrate]))
	var sources := PackedFloat32Array()
	for i in 96:
		# All source kinds, all factions, zero-radius and degenerate capsules.
		var x := rng.randf_range(-96, 96)
		var z := rng.randf_range(-72, 72)
		sources.append_array(PackedFloat32Array([x, z, 0.0 if i % 17 == 0 else rng.randf_range(0.01, 18),
			rng.randf_range(0.1, 1), i % 3, i % 4,
			(x if i % 13 == 0 else x + rng.randf_range(-20, 20)) if i % 4 == 1 else rng.randf_range(0, 25),
			z if i % 13 == 0 else z + rng.randf_range(-20, 20)]))
	var src := keep(rd.storage_buffer_create(sources.size() * 4, sources.to_byte_array()))
	var initial := PackedFloat32Array()
	initial.resize(cells * 4)
	initial.fill(-1.0)
	# Existing mixed-faction growth exercises starvation, fighting and burns;
	# retain uninitialized cells to cover the first-step substrate path too.
	for i in cells:
		if i % 5 != 0:
			for faction in 3:
				initial[i * 4 + faction] = rng.randf_range(0.0, 0.3)
			initial[i * 4 + 3] = rng.randf_range(0.0, 1.6)
	var fmt := RDTextureFormat.new()
	fmt.width = Data.SIM_W
	fmt.height = Data.SIM_H
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var variants := []
	for path in [reference, "res://shaders/myc_sim.glsl"]:
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(path).replace("#[compute]", "")
		var spirv := rd.shader_compile_spirv_from_source(source)
		if spirv.compile_error_compute != "":
			push_error(spirv.compile_error_compute)
			cleanup()
			quit(1)
			return
		var shader := keep(rd.shader_create_from_spirv(spirv))
		var pipe := keep(rd.compute_pipeline_create(shader))
		var textures := []
		for i in 2:
			textures.append(keep(rd.texture_create(fmt, RDTextureView.new(), [initial.to_byte_array()])))
		var sets := []
		for i in 2:
			sets.append(keep(rd.uniform_set_create([
				uniform(0, textures[i], RenderingDevice.UNIFORM_TYPE_IMAGE),
				uniform(1, textures[1 - i], RenderingDevice.UNIFORM_TYPE_IMAGE),
				uniform(2, sub, RenderingDevice.UNIFORM_TYPE_IMAGE),
				uniform(3, src, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)], shader, 0)))
		variants.append({"pipe": pipe, "tex": textures, "sets": sets})
	var failed := false
	for step in 12:
		var pc := PackedFloat32Array([[0.0, 0.016, 0.05, 0.1][step % 4], 96,
			Data.SIM_RES, Data.HALF_W, Data.HALF_D, 1.0, 1.25, 0.8]).to_byte_array()
		for v in variants:
			var cl := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(cl, v.pipe)
			rd.compute_list_bind_uniform_set(cl, v.sets[step % 2], 0)
			rd.compute_list_set_push_constant(cl, pc, pc.size())
			rd.compute_list_dispatch(cl, ceili(Data.SIM_W / 16.0), ceili(Data.SIM_H / 16.0), 1)
			rd.compute_list_end()
		rd.submit()
		rd.sync()
		var a := rd.texture_get_data(variants[0].tex[1 - step % 2], 0)
		var b := rd.texture_get_data(variants[1].tex[1 - step % 2], 0)
		if a.size() != cells * 16 or b.size() != cells * 16:
			push_error("GPU field readback missing or incomplete at step %d" % step)
			failed = true
			break
		if a != b:
			push_error("GPU field differs at step %d" % step)
			failed = true
			break
	if benchmark and not failed:
		benchmark_variants(variants)
	cleanup()
	print("MYCELIUM_EQUIVALENCE ", "FAIL" if failed else "PASS: 12 steps, 96 sources, full grid, byte-identical fields")
	quit(1 if failed else 0)

func benchmark_variants(variants: Array) -> void:
	# Every dispatch reads texture 0 and overwrites texture 1; neither variant
	# evolves between samples. Correctness above established identical inputs.
	var pc := PackedFloat32Array([0.05, 96, Data.SIM_RES, Data.HALF_W,
		Data.HALF_D, 1.0, 1.25, 0.8]).to_byte_array()
	var samples := [[], []]
	for sample in 8:
		# Two warmup rounds, then six measured rounds with alternating order.
		for offset in 2:
			var index := (sample + offset) % 2
			var v: Dictionary = variants[index]
			var started := Time.get_ticks_usec()
			for dispatch in 10:
				var cl := rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(cl, v.pipe)
				rd.compute_list_bind_uniform_set(cl, v.sets[0], 0)
				rd.compute_list_set_push_constant(cl, pc, pc.size())
				rd.compute_list_dispatch(cl, ceili(Data.SIM_W / 16.0), ceili(Data.SIM_H / 16.0), 1)
				rd.compute_list_end()
			rd.submit()
			rd.sync()
			if sample >= 2:
				samples[index].append((Time.get_ticks_usec() - started) / 1000.0 / 10.0)
	for index in 2:
		var sorted: Array = samples[index].duplicate()
		sorted.sort()
		print("MYCELIUM_BENCHMARK ", "reference" if index == 0 else "optimized",
			" GPU submit+wait wall ms/dispatch (includes CPU overhead), 96 sources, 10 dispatches/sample: ",
			"samples=", samples[index], " median=", (sorted[2] + sorted[3]) / 2.0)
