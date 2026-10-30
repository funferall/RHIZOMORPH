extends Node
# GPU mycelium field. Runs myc_sim.glsl on the main RenderingDevice so the result
# can be sampled directly by the terrain/moss shaders through a Texture2DRD, and
# reads a coarse summary back to the CPU a few times a second for gameplay.

const Data = preload("res://scripts/data.gd")
const MAX_SOURCES := 768
const STEPS := 2              # even, so the newest state always lands in tex[0]
const READBACK_EVERY := 0.2

var rd: RenderingDevice
var ok := false
var tex: Array[RID] = [RID(), RID()]
var texture := Texture2DRD.new()
var sub_tex := RID()
var src_buf := RID()
var out_buf := RID()
var sim_shader := RID()
var sim_pipe := RID()
var sum_shader := RID()
var sum_pipe := RID()
var sim_sets: Array[RID] = [RID(), RID()]
var sum_set := RID()

var coarse := PackedFloat32Array()   # COARSE_W * COARSE_H * (d0, d1, d2, nutrient)
var growth := [1.0, 1.0, 1.0]        # per-faction growth multipliers
var _src := PackedFloat32Array()
var _count := 0
var _readback_t := 0.0
var time_scale := 1.0
var paused := false


func setup(sub_img: Image) -> void:
	coarse.resize(Data.COARSE_W * Data.COARSE_H * 4)
	coarse.fill(0.0)
	_src.resize(MAX_SOURCES * 8)
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		push_warning("RHIZOMORPH: no RenderingDevice (headless?) - mycelium disabled")
		return
	RenderingServer.call_on_render_thread(_init_gpu.bind(sub_img))


func _init_gpu(sub_img: Image) -> void:
	var sim_file: RDShaderFile = load("res://shaders/myc_sim.glsl")
	sim_shader = rd.shader_create_from_spirv(sim_file.get_spirv())
	sim_pipe = rd.compute_pipeline_create(sim_shader)
	var sum_file: RDShaderFile = load("res://shaders/myc_summary.glsl")
	sum_shader = rd.shader_create_from_spirv(sum_file.get_spirv())
	sum_pipe = rd.compute_pipeline_create(sum_shader)

	var fmt := RDTextureFormat.new()
	fmt.width = Data.SIM_W
	fmt.height = Data.SIM_H
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var init := PackedFloat32Array()
	init.resize(Data.SIM_W * Data.SIM_H * 4)
	init.fill(-1.0)
	var bytes := init.to_byte_array()
	for i in 2:
		tex[i] = rd.texture_create(fmt, RDTextureView.new(), [bytes])

	var sfmt := RDTextureFormat.new()
	sfmt.width = Data.SIM_W
	sfmt.height = Data.SIM_H
	sfmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	sfmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	sub_tex = rd.texture_create(sfmt, RDTextureView.new(), [sub_img.get_data()])

	src_buf = rd.storage_buffer_create(MAX_SOURCES * 32, _src.to_byte_array())
	out_buf = rd.storage_buffer_create(Data.COARSE_W * Data.COARSE_H * 16)

	for i in 2:
		var us: Array[RDUniform] = [
			_img_uniform(0, tex[i]), _img_uniform(1, tex[1 - i]), _img_uniform(2, sub_tex), _buf_uniform(3, src_buf)]
		sim_sets[i] = rd.uniform_set_create(us, sim_shader, 0)
	var su: Array[RDUniform] = [_img_uniform(0, tex[0]), _buf_uniform(1, out_buf)]
	sum_set = rd.uniform_set_create(su, sum_shader, 0)
	texture.texture_rd_rid = tex[0]
	ok = true


func _img_uniform(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u


func _buf_uniform(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u


# --- source list, rebuilt by the game every frame -------------------------------

func clear_sources() -> void:
	_count = 0


func _push(x: float, z: float, r: float, s: float, f: float, kind: float, x2: float, z2: float) -> void:
	if _count >= MAX_SOURCES:
		return
	var o := _count * 8
	_src[o] = x
	_src[o + 1] = z
	_src[o + 2] = r
	_src[o + 3] = s
	_src[o + 4] = f
	_src[o + 5] = kind
	_src[o + 6] = x2
	_src[o + 7] = z2
	_count += 1


func add_disc(p: Vector2, r: float, strength: float, faction: int) -> void:
	_push(p.x, p.y, r, strength, faction, 0, 0, 0)


func add_capsule(a: Vector2, b: Vector2, r: float, strength: float, faction: int) -> void:
	_push(a.x, a.y, r, strength, faction, 1, b.x, b.y)


func add_ring(c: Vector2, ring_r: float, width: float, strength: float, faction: int) -> void:
	_push(c.x, c.y, width, strength, faction, 2, ring_r, 0)


func add_burn(p: Vector2, r: float) -> void:
	_push(p.x, p.y, r, 1.0, 0, 3, 0, 0)


# --- stepping -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ok:
		return
	if texture.texture_rd_rid != tex[0]:
		texture.texture_rd_rid = tex[0]
	var dt: float = 0.0 if paused else minf(delta * time_scale, 0.1) / STEPS
	_readback_t -= delta
	var readback := _readback_t <= 0.0
	if readback:
		_readback_t = READBACK_EVERY
	RenderingServer.call_on_render_thread(_gpu_step.bind(dt, _count, _src.to_byte_array(), readback))


func _gpu_step(dt: float, count: int, src_bytes: PackedByteArray, readback: bool) -> void:
	rd.buffer_update(src_buf, 0, src_bytes.size(), src_bytes)
	var gx := ceili(Data.SIM_W / 16.0)
	var gy := ceili(Data.SIM_H / 16.0)
	var pc := PackedFloat32Array([dt, count, Data.SIM_RES, Data.HALF_W, Data.HALF_D, growth[0], growth[1], growth[2]]).to_byte_array()
	for i in STEPS:
		var cl := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, sim_pipe)
		rd.compute_list_bind_uniform_set(cl, sim_sets[i % 2], 0)
		rd.compute_list_set_push_constant(cl, pc, pc.size())
		rd.compute_list_dispatch(cl, gx, gy, 1)
		rd.compute_list_end()
	if readback:
		var k := Data.SIM_W / Data.COARSE_W
		var pc2 := PackedFloat32Array([Data.COARSE_W, Data.COARSE_H, k, 0]).to_byte_array()
		var cl2 := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl2, sum_pipe)
		rd.compute_list_bind_uniform_set(cl2, sum_set, 0)
		rd.compute_list_set_push_constant(cl2, pc2, pc2.size())
		rd.compute_list_dispatch(cl2, ceili(Data.COARSE_W / 8.0), ceili(Data.COARSE_H / 8.0), 1)
		rd.compute_list_end()
		coarse = rd.buffer_get_data(out_buf).to_float32_array()


# --- queries (coarse, CPU side) -------------------------------------------------

func _idx(p: Vector2) -> int:
	var cx := clampi(int(p.x + Data.HALF_W), 0, Data.COARSE_W - 1)
	var cz := clampi(int(p.y + Data.HALF_D), 0, Data.COARSE_H - 1)
	return (cz * Data.COARSE_W + cx) * 4


func density(f: int, p: Vector2) -> float:
	if f < 0 or f > 2 or coarse.is_empty():
		return 0.0
	return coarse[_idx(p) + f]


func nutrient(p: Vector2) -> float:
	return coarse[_idx(p) + 3] if not coarse.is_empty() else 0.0


func strongest_enemy(f: int, p: Vector2) -> float:
	var i := _idx(p)
	var best := 0.0
	for g in 3:
		if g != f:
			best = maxf(best, coarse[i + g])
	return best


func _exit_tree() -> void:
	if rd == null or not ok:
		return
	ok = false
	var rids := [sim_sets[0], sim_sets[1], sum_set, sim_pipe, sum_pipe, sim_shader, sum_shader, src_buf, out_buf, sub_tex, tex[0], tex[1]]
	texture.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(func():
		for r in rids:
			if r.is_valid():
				rd.free_rid(r))
