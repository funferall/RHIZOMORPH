extends Node
# GPU mycelium field. Runs myc_sim.glsl on the main RenderingDevice so the result
# can be sampled directly by the terrain/moss shaders through a Texture2DRD, and
# reads a coarse summary back to the CPU a few times a second for gameplay.
# Without a GPU (the headless balance harness) a CPU port of the same rules runs
# on a 2 m grid and fills the same coarse summary, so gameplay code can't tell.

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
var cpu := false                     # the CPU stand-in is running instead of the GPU sim
var cpu_usec := 0                    # time spent in it (--profile)
var paused := false


func setup(sub_img: Image) -> void:
	coarse.resize(Data.COARSE_W * Data.COARSE_H * 4)
	coarse.fill(0.0)
	_src.resize(MAX_SOURCES * 8)
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		_init_cpu(sub_img)
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
	if cpu:
		_cpu_t += 0.0 if paused else delta * time_scale
		var n := 0
		while _cpu_t >= CPU_DT and n < 4:
			_cpu_t -= CPU_DT
			var t0 := Time.get_ticks_usec()
			_cpu_step(CPU_DT)
			cpu_usec += Time.get_ticks_usec() - t0
			n += 1
		return
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


# --- CPU stand-in (headless) ----------------------------------------------------
# The same rules as myc_sim.glsl - reach from sources, growth that creeps from
# neighbouring hyphae into rich ground, starving outside reach, fronts digesting
# each other, ground slowly exhausted, burns leaving ash - on a 2 m grid stepped
# twice a second. CPU_SPREAD slows growth so fronts advance about as fast as the
# GPU sim's fine grid (calibrated against rendered games; see tools/sim).

const CPU_CELL := 2
const CPU_DT := 0.5
const CPU_SPREAD := 0.35
var _cw := Data.COARSE_W / CPU_CELL
var _ch := Data.COARSE_H / CPU_CELL
var _d := PackedFloat32Array()       # _cw * _ch * 3
var _nut := PackedFloat32Array()
var _base := PackedFloat32Array()
var _cap := PackedFloat32Array()
var _rough := PackedFloat32Array()   # rock share, slows growth
var _jit := PackedFloat32Array()     # fixed per-cell irregularity
var _lobe := PackedFloat32Array()    # fixed per-cell edge wobble
var _cpu_t := 0.0


func _init_cpu(sub_img: Image) -> void:
	var n := _cw * _ch
	for a in [_d]:
		a.resize(n * 3)
		a.fill(0.0)
	for a in [_nut, _base, _cap, _rough, _jit, _lobe]:
		a.resize(n)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for cz in _ch:
		for cx in _cw:
			var i := cz * _cw + cx
			var px := clampi(int((cx * CPU_CELL + CPU_CELL * 0.5) * Data.SIM_RES), 0, Data.SIM_W - 1)
			var pz := clampi(int((cz * CPU_CELL + CPU_CELL * 0.5) * Data.SIM_RES), 0, Data.SIM_H - 1)
			var sub := sub_img.get_pixel(px, pz)
			var base := (0.55 + sub.b * 0.9 + sub.a * 0.5) * (1.0 - sub.r * 0.7) * (1.0 - sub.g)
			_base[i] = base
			_nut[i] = base
			_cap[i] = (1.0 - sub.g) * (1.0 - 0.55 * sub.r)
			_jit[i] = 0.35 + 1.3 * (noise.get_noise_2d(cx * 3.4, cz * 3.4) * 0.5 + 0.5) * (0.6 + 0.8 * rng.randf())
			_lobe[i] = 1.0 + noise.get_noise_2d(cx * 0.84 + 100.0, cz * 0.84) * 0.28
	ok = true
	cpu = true
	_write_coarse()


func _cpu_step(dt: float) -> void:
	var n := _cw * _ch
	var reach := PackedFloat32Array()
	reach.resize(n * 3)
	reach.fill(0.0)
	var burn := PackedFloat32Array()
	burn.resize(n)
	burn.fill(0.0)
	var cs := float(CPU_CELL)
	for k in _count:
		var o := k * 8
		var ax := _src[o]
		var az := _src[o + 1]
		var r := _src[o + 2]
		var st := _src[o + 3]
		var fi := int(_src[o + 4] + 0.5)
		var kind := int(_src[o + 5] + 0.5)
		var bx := _src[o + 6]
		var bz := _src[o + 7]
		var lo := Vector2(ax, az)
		var hi := Vector2(ax, az)
		var ext := r * 1.3
		if kind == 1:
			lo = Vector2(minf(ax, bx), minf(az, bz))
			hi = Vector2(maxf(ax, bx), maxf(az, bz))
		elif kind == 2:
			ext += bx
		var x0 := clampi(int((lo.x - ext + Data.HALF_W) / cs), 0, _cw - 1)
		var x1 := clampi(int((hi.x + ext + Data.HALF_W) / cs), 0, _cw - 1)
		var z0 := clampi(int((lo.y - ext + Data.HALF_D) / cs), 0, _ch - 1)
		var z1 := clampi(int((hi.y + ext + Data.HALF_D) / cs), 0, _ch - 1)
		var abx := bx - ax
		var abz := bz - az
		var ab2 := maxf(abx * abx + abz * abz, 0.0001)
		for cz in range(z0, z1 + 1):
			var wz := (cz + 0.5) * cs - Data.HALF_D
			for cx in range(x0, x1 + 1):
				var i := cz * _cw + cx
				var wx := (cx + 0.5) * cs - Data.HALF_W
				var dist: float
				if kind == 1:
					var h := clampf(((wx - ax) * abx + (wz - az) * abz) / ab2, 0.0, 1.0)
					dist = Vector2(wx - ax - abx * h, wz - az - abz * h).length()
				elif kind == 2:
					dist = absf(Vector2(wx - ax, wz - az).length() - bx)
				else:
					dist = Vector2(wx - ax, wz - az).length()
				dist *= _lobe[i]
				if dist > r:
					continue
				var f := st * (1.0 - smoothstep(r * 0.55, r, dist))
				if kind == 3:
					burn[i] = maxf(burn[i], f)
				elif fi >= 0 and fi <= 2:
					reach[i * 3 + fi] = maxf(reach[i * 3 + fi], f)
	var nd := _d.duplicate()
	var spread := 1.7 * CPU_SPREAD
	var g0: float = growth[0]
	var g1: float = growth[1]
	var g2: float = growth[2]
	for cz in _ch:
		for cx in _cw:
			var i := cz * _cw + cx
			var j := i * 3
			var d0 := _d[j]
			var d1 := _d[j + 1]
			var d2 := _d[j + 2]
			var r0 := reach[j]
			var r1 := reach[j + 1]
			var r2 := reach[j + 2]
			var nut := _nut[i]
			var bn := burn[i]
			if r0 + r1 + r2 + d0 + d1 + d2 + bn <= 0.0:
				_nut[i] = nut + dt * 0.0025 * (_base[i] - nut)
				continue
			# strongest neighbour per faction (4-neighbourhood)
			var qa := (i - 1) * 3 if cx > 0 else j
			var qb := (i + 1) * 3 if cx < _cw - 1 else j
			var qc := (i - _cw) * 3 if cz > 0 else j
			var qd := (i + _cw) * 3 if cz < _ch - 1 else j
			var m0 := maxf(maxf(_d[qa], _d[qb]), maxf(_d[qc], _d[qd]))
			var m1 := maxf(maxf(_d[qa + 1], _d[qb + 1]), maxf(_d[qc + 1], _d[qd + 1]))
			var m2 := maxf(maxf(_d[qa + 2], _d[qb + 2]), maxf(_d[qc + 2], _d[qd + 2]))
			var room := maxf(_cap[i] - d0 - d1 - d2, 0.0)
			var rich := 0.45 + 0.55 * clampf(nut / maxf(_base[i], 0.05), 0.0, 1.0)
			var gg := spread * room * rich * _jit[i]
			var tot := d0 + d1 + d2
			var kill := 1.0 - clampf(bn * 40.0 * dt, 0.0, 1.0)
			nd[j] = _cell(d0, r0, m0, gg * g0, tot - d0, maxf(r1, r2), dt) * kill
			nd[j + 1] = _cell(d1, r1, m1, gg * g1, tot - d1, maxf(r0, r2), dt) * kill
			nd[j + 2] = _cell(d2, r2, m2, gg * g2, tot - d2, maxf(r0, r1), dt) * kill
			nut += dt * (0.0025 * (_base[i] - nut) - 0.003 * tot * nut)
			nut = lerpf(nut, _base[i] * 1.3, clampf(bn * dt * 3.0, 0.0, 1.0))
			_nut[i] = clampf(nut, 0.0, 1.6)
	_d = nd
	_write_coarse()


# One faction's density in one cell after a step: growth creeping in from the
# strongest neighbour, starving outside reach, and digestion by other factions.
func _cell(d: float, rf: float, m: float, g: float, others: float, oreach: float, dt: float) -> float:
	var front := maxf(maxf(m * 0.95, d), 0.5 if rf >= 0.8 else 0.0)
	var grow := g * rf * front
	var starve := 0.45 * (1.0 - smoothstep(0.0, 0.1, rf)) * d + 0.04 * d * (1.0 - rf)
	var fight := 1.4 * d * others * (0.35 + oreach) / (0.5 + rf)
	return clampf(d + dt * (grow - starve - fight), 0.0, 1.0)


# Sum of density x nutrient per faction, in 1 m cells, for soil income.
func soil_sums() -> Array:
	var out := [0.0, 0.0, 0.0]
	var area := float(CPU_CELL * CPU_CELL)
	for i in _cw * _ch:
		var nu := _nut[i]
		if nu > 0.0:
			out[0] += _d[i * 3] * nu
			out[1] += _d[i * 3 + 1] * nu
			out[2] += _d[i * 3 + 2] * nu
	for f in 3:
		out[f] *= area
	return out


# Mark (in 1 m fog grids) every cell where faction f's mycelium is denser than t.
func stamp_sight(f: int, t: float, vis: PackedByteArray, seen: PackedByteArray) -> void:
	var w := Data.COARSE_W
	for cz in _ch:
		for cx in _cw:
			if _d[(cz * _cw + cx) * 3 + f] > t:
				var o := cz * CPU_CELL * w + cx * CPU_CELL
				for k in [o, o + 1, o + w, o + w + 1]:
					vis[k] = 1
					seen[k] = 1


# Upsample the 2 m grid into the 1 m coarse summary the game reads.
func _write_coarse() -> void:
	var w := Data.COARSE_W
	for z in Data.COARSE_H:
		var crow := (z / CPU_CELL) * _cw
		for x in w:
			var i := crow + x / CPU_CELL
			var o := (z * w + x) * 4
			coarse[o] = _d[i * 3]
			coarse[o + 1] = _d[i * 3 + 1]
			coarse[o + 2] = _d[i * 3 + 2]
			coarse[o + 3] = _nut[i]
