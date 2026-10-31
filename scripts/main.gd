extends Node3D
# Scene glue: builds the terrarium, light, camera, GPU mycelium, then the game
# and HUD. Command-line flags (after `--`) drive automated checks:
#   --bot              the player's faction is also played by the AI
#   --faction=N        play faction N (0 Amanita, 1 Morel, 2 Veiled)
#   --seconds=N        fast-forward N game seconds before showing / screenshotting
#   --shot=path.png    save a screenshot and quit
#   --view=yaw,dist,x,z[,bias]  camera for the shot
#   --nohud            hide the HUD for the shot (with --nofog for the whole board)
#   --speed=N          game speed multiplier while fast-forwarding
#   --viewtest         board + mycelium only, with test sources
#   --showcase         every species lined up
#   --catalog=DIR      one close-up plate per species + catalog.json, then quit
#   --perf-nocanopy    hide the shadow-only tree crowns, for before/after shots and FPS
#   --fpstest[=dist]   after --seconds, 20 s at 1x with vsync off framed on the biggest fight; prints FPS (--scale=0.75 --fsr)
#   --sim              headless balance run (with --headless --fixed-fps): all bots, no HUD or
#                      audio, ends when one court is left or at --seconds, prints one SIM {json} line

const Data = preload("res://scripts/data.gd")
const Board = preload("res://scripts/board.gd")
const Mycelium = preload("res://scripts/mycelium.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const FungusLib = preload("res://scripts/fungus_lib.gd")

var args := {}
var board: Node3D
var myc: Node
var rig: Node3D
var sun := DirectionalLight3D.new()
var env := Environment.new()
var game: Node
var hud: CanvasLayer
var _elapsed := 0.0
var _shot_done := false
var _framed := false
var _fps_t := -1.0
var _fps_frames: Array[float] = []
var _fps_cpu := 0.0
var _fps_gpu := 0.0
var _fps_proc := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seed := int(args.get("seed", "7"))

	board = Board.new()
	add_child(board)
	board.build(seed)
	myc = Mycelium.new()
	add_child(myc)
	myc.setup(board.sub_img)
	board.attach_visuals(myc.texture)
	_build_light()
	board.build_forest_canopy(-sun.global_transform.basis.z)

	rig = CameraRig.new()
	rig.board = board
	add_child(rig)
	_build_particles()

	if args.has("viewtest"):
		rig.set_view(0.5, 75.0, Vector3.ZERO)
	elif args.has("showcase"):
		_showcase()
	elif args.has("catalog"):
		_catalog.call_deferred()
	elif args.has("sim"):
		var Game = load("res://scripts/game.gd")
		game = Game.new()
		game.board = board
		game.myc = myc
		game.match_seed = int(args.get("match", "0"))
		game.rig = rig
		if not game.has_method("sim_summary"):
			print("SIM {\"failed\": true}")   # the game script did not load
			get_tree().quit(1)
			return
		game.sim = true
		add_child(game)
		game.start(0, true)
		if game.ais.size() < 3:
			print("SIM {\"failed\": true}")   # an AI script did not load
			get_tree().quit(1)
			return
	else:
		var Game = load("res://scripts/game.gd")
		game = Game.new()
		game.board = board
		game.myc = myc
		game.match_seed = int(args.get("match", "0"))
		game.difficulty = args.get("difficulty", "cruel")
		game.rig = rig
		add_child(game)
		var Audio = load("res://scripts/audio.gd")
		var audio = Audio.new()
		audio.game = game
		audio.rig = rig
		add_child(audio)
		game.sound.connect(audio.play)
		game.game_over.connect(audio.on_game_over)
		var Hud = load("res://scripts/hud.gd")
		hud = Hud.new()
		hud.game = game
		hud.audio = audio
		add_child(hud)
		var bot := args.has("bot")
		if args.has("faction") or bot or (args.has("shot") and not args.has("menu")):
			game.start(int(args.get("faction", "1")), bot)
		else:
			hud.show_menu()
		if args.has("seconds"):
			game.fast_forward(float(args["seconds"]), float(args.get("speed", "4")))
	if args.has("scale") or args.has("fsr"):
		var vp := get_viewport()
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if args.has("fsr") else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(args.get("scale", "0.75"))
		if args.has("fsr"):
			vp.use_taa = false   # FSR2 does its own temporal reconstruction
	if args.has("fpstest"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# perf tests: switch suspects off one at a time
	if args.has("perf-nomoss"):
		for c in board.get_children():
			if c is MultiMeshInstance3D:
				c.visible = false
	if args.has("perf-nofx"):
		env.ssr_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.volumetric_fog_enabled = false
		env.glow_enabled = false
	if args.has("perf-noshadow"):
		sun.shadow_enabled = false
	if args.has("perf-nocanopy"):
		for c in board.crowns + [board.forest_canopy]:
			c.visible = false
	if args.has("view"):
		var v: PackedStringArray = args["view"].split(",")
		var at := Vector3(float(v[2]), 0, float(v[3])) if v.size() >= 4 else Vector3.ZERO
		rig.set_view(deg_to_rad(float(v[0])), float(v[1]), at, float(v[4]) if v.size() >= 5 else 0.0)
	rig.snap()


func _build_light() -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.014)
	# the sky is never seen; it only feeds golden-hour reflections on caps and water
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.36, 0.45)
	sky_mat.sky_horizon_color = Color(0.95, 0.66, 0.38)
	sky_mat.ground_horizon_color = Color(0.35, 0.24, 0.15)
	sky_mat.ground_bottom_color = Color(0.06, 0.045, 0.03)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.46, 0.44, 0.4)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.4
	env.ssao_power = 1.7
	env.ssil_enabled = true
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.05
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.08
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color(1.0, 0.8, 0.58)
	env.volumetric_fog_anisotropy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun.rotation_degrees = Vector3(-21, -38, 0)
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.shadow_opacity = 0.8   # a little sun gets through every shadow, so units stay readable under the canopy
	sun.directional_shadow_max_distance = 220.0
	sun.light_volumetric_fog_energy = 1.6
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-50, 150, 0)
	fill.light_color = Color(0.5, 0.58, 0.78)
	fill.light_energy = 0.28
	add_child(fill)


func _build_particles() -> void:
	# drifting spores catching the low sun - pure GPU particles
	var p := GPUParticles3D.new()
	p.amount = 1250
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.visibility_aabb = AABB(Vector3(-60, -5, -45), Vector3(120, 30, 90))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(Data.HALF_W, 4.0, Data.HALF_D)
	pm.direction = Vector3(0.3, 1, 0.1)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0.05, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.9, 0.7, 0))
	grad.add_point(0.2, Color(1, 0.9, 0.7, 0.8))
	grad.add_point(0.8, Color(1, 0.9, 0.7, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(1, 0.9, 0.7, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.6, 1.4, 1.0)
	q.material = m
	p.draw_pass_1 = q
	p.position.y = 4.0
	add_child(p)


func _showcase() -> void:
	# a flat soil stage floating above the board; --group=0 structures, 1 units, 2 decor
	board.visible = false
	var groups := [
		["giant_agaric", "fly_agaric", "clathrus", "death_cap", "armillaria", "chanterelle", "mycena_lantern", "bracket",
			"giant_morel", "morel", "earthstar", "cordyceps", "giant_veiled", "veiled_lady", "birds_nest", "pilobolus", "giant_puffball", "inkcap_bed", "anthill"],
		["u_wartling", "u_spitter", "u_angel", "u_bruiser", "u_slinger", "u_bomber", "u_sniper", "u_stalker", "u_zombie",
			"i_ant", "t_ant", "i_beetle", "t_beetle", "i_fly", "t_fly", "i_springtail"],
		["agaric_button", "mycena_white", "morel_small", "elf_cup_small", "puffball_small", "inkcap"],
	]
	var g := int(args.get("group", "0"))
	var ids: Array = groups[g]
	var stage := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	stage.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.09, 0.075, 0.055)
	sm.roughness = 0.95
	stage.material_override = sm
	add_child(stage)
	var cols := 6 if g == 0 else 5
	var sp := 9.0 if g == 0 else (2.6 if g == 1 else 1.2)
	for i in ids.size():
		var mi := MeshInstance3D.new()
		mi.mesh = FungusLib.mesh(ids[i])
		var row := i / cols
		var col := i % cols
		mi.position = Vector3((col - (cols - 1) * 0.5) * sp, 0, (row - 1) * sp)
		if ids[i].begins_with("u_"):
			mi.set_instance_shader_parameter("walk", 1.0)
		add_child(mi)
	rig.board = null
	rig.min_dist = 1.0
	rig.set_view(0.0, [55.0, 17.0, 7.5][g], Vector3(0, 0, sp * 0.3), 4.0)


# Every species in the game, with who uses it: structures and units by court,
# the forest's insects, decor sprouts and spore-action props.
# Frame the biggest fight, settle, then time 20 s of frames at 1x.
func _fps_test(delta: float) -> void:
	if _fps_t < 0.0:
		_fps_t = 0.0
		var hp: Vector2 = game.hotspot()
		var dist := float(args["fpstest"]) if args["fpstest"] != "1" else 45.0
		rig.set_view(rig.yaw, dist, Vector3(hp.x, 0, hp.y))
		rig.snap()
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		return
	_fps_t += delta / maxf(Engine.time_scale, 0.01)
	if _fps_t < 3.0:
		return
	_fps_frames.append(delta / maxf(Engine.time_scale, 0.01))
	var vrid := get_viewport().get_viewport_rid()
	_fps_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu()
	_fps_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
	_fps_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if _fps_t >= 23.0:
		var ms := _fps_frames.duplicate()
		ms.sort()
		var avg := 0.0
		for m in ms:
			avg += m
		avg /= ms.size()
		var p99: float = ms[int(ms.size() * 0.99)]
		print("FPSTEST dist=%s scale=%s fsr=%s: avg %.1f fps (%.2f ms), 1%% low %.1f fps, %d frames, %d units" % [args["fpstest"],
			args.get("scale", "1.0"), args.has("fsr"), 1.0 / avg, avg * 1000.0, 1.0 / p99, ms.size(), game.units.filter(func(u): return u.alive).size()])
		var n := float(ms.size())
		if game._profiling:
			var pr: Dictionary = game._prof_report()
			var tot := float(ms.size())
			var parts := []
			for k in pr:
				parts.append("%s %.1f" % [k, float(pr[k]) / tot])
			print("FPSTEST game ms/frame (whole run incl. fast-forward): " + ", ".join(parts))
		print("FPSTEST split: scripts (_process) %.1f ms, render CPU %.1f ms, render GPU %.1f ms, draw calls %d, objects %d" % [_fps_proc / n, _fps_cpu / n, _fps_gpu / n,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		get_tree().quit()


func _catalog_entries() -> Array:
	var out := {}
	var add := func(id: String, kind: String, f: int, used: String):
		if not out.has(id):
			out[id] = {"id": id, "kind": kind, "faction": f, "used_by": []}
		if not used in out[id]["used_by"]:
			out[id]["used_by"].append(used)
	for f in 3:
		var fd: Dictionary = Data.FACTIONS[f]
		var sids: Array = [fd["heart"]] + fd["build"]
		for sid in sids:
			var sd: Dictionary = Data.STRUCTURES[sid]
			add.call(sd["species"], "structure", f, sd["name"])
			for uid in sd.get("trains", []):
				add.call(Data.UNITS[uid]["species"], "unit", f, Data.UNITS[uid]["name"])
		for uid in fd["starters"]:
			add.call(Data.UNITS[uid]["species"], "unit", f, Data.UNITS[uid]["name"])
		for sp in fd["decor"]:
			add.call(sp, "decor", f, "Ground sprouts")
	for uid in Data.UNITS:
		var ud: Dictionary = Data.UNITS[uid]
		if ud.get("insect", false):
			add.call(ud["species"], "insect", Data.NEUTRAL, ud["name"])
		elif ud.get("thrall", false):
			add.call(ud["species"], "unit", 2, ud["name"])
	add.call("giant_puffball", "prop", 1, "Giant Puffball (spore action)")
	add.call("agaric_button", "prop", 0, "Fairy Ring (spore action)")
	add.call("death_cap", "prop", 0, "Death Cap Bloom (spore action)")
	add.call("anthill", "prop", Data.NEUTRAL, "Anthill (insect nest)")
	return out.values()


func _catalog() -> void:
	board.visible = false
	for c in get_children():
		if c is GPUParticles3D:
			c.visible = false   # the drifting spore motes read as specks on a plate
	var dir: String = args["catalog"]
	DirAccess.make_dir_recursive_absolute(dir)
	var stage := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	stage.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.09, 0.075, 0.055)
	sm.roughness = 0.95
	stage.material_override = sm
	add_child(stage)
	var cam := Camera3D.new()
	cam.fov = 28.0
	add_child(cam)
	cam.make_current()
	var only: PackedStringArray = args.get("only", "").split(",", false)
	var entries := _catalog_entries()
	for e in entries:
		if not only.is_empty() and not e["id"] in only:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = FungusLib.mesh(e["id"])
		var f: int = e["faction"]
		if f < 3 and e["kind"] != "decor" and e["kind"] != "prop":
			var c: Color = Data.faction_color(f)
			var thrall: bool = e["id"].begins_with("t_") or e["id"] == "u_zombie"
			var stint := 0.3
			for sid in Data.STRUCTURES:
				if Data.STRUCTURES[sid]["species"] == e["id"]:
					stint = Data.STRUCTURES[sid].get("tint", 0.3)
			mi.set_instance_shader_parameter("team", Color(c.r, c.g, c.b, 0.18 if thrall else (0.45 if e["kind"] == "unit" else stint)))
		if e["kind"] in ["unit", "insect"]:
			mi.set_instance_shader_parameter("walk", 0.6)
		add_child(mi)
		var ab: AABB = mi.mesh.get_aabb()
		var ctr := ab.get_center()
		var r := maxf(ab.size.length() * 0.5, 0.2)
		var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 1.12
		var yaw := 0.65
		var pitch := 0.4
		cam.near = maxf(dist * 0.02, 0.01)
		cam.position = ctr + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
		cam.look_at(ctr)
		for k in 24:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var s := mini(img.get_width(), img.get_height())
		img = img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
		img.resize(640, 640, Image.INTERPOLATE_LANCZOS)
		img.save_webp(dir.path_join(e["id"] + ".webp"), true, 0.86)
		e["height_m"] = snappedf(ab.size.y, 0.01)
		e["width_m"] = snappedf(maxf(ab.size.x, ab.size.z), 0.01)
		mi.queue_free()
	if not only.is_empty() and FileAccess.file_exists(dir.path_join("catalog.json")):
		# a partial re-render keeps the sizes measured last time for everything else
		var old = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("catalog.json")))
		for o in (old if old is Array else []):
			for e in entries:
				if e["id"] == o["id"] and not e.has("height_m"):
					e["height_m"] = o.get("height_m", 0.0)
					e["width_m"] = o.get("width_m", 0.0)
	var fa := FileAccess.open(dir.path_join("catalog.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(entries, " "))
	fa.close()
	get_tree().quit()


func _process(delta: float) -> void:
	_elapsed += delta
	if args.has("fpstest") and game and not game.busy():
		_fps_test(delta)
		return
	if args.has("sim") and game and (game.over or game.time >= float(args.get("seconds", "1200"))):
		print("SIM " + JSON.stringify(game.sim_summary()))
		get_tree().quit()
		return
	if args.has("viewtest"):
		myc.clear_sources()
		for f in 3:
			var sp: Vector2 = Data.START_POS[f]
			myc.add_disc(sp, 15.0, 1.0, f)
			myc.add_capsule(sp, sp.lerp(Vector2.ZERO, 0.7), 3.0, 1.0, f)
	if rig:
		var zoom := inverse_lerp(rig.min_dist, rig.max_dist, rig.dist)
		board.set_cut_height(lerpf(4.0, 30.0, 1.0 - zoom))
		board.set_canopy_zoom(zoom)
		board.update_moss_lod(rig.cam.global_position)
	if game:
		board.set_wind(1.0 if game.weather.now == "wind" else 0.25, delta)
	if args.has("shot") and not _shot_done:
		var wait := float(args.get("wait", "3"))
		var ready: bool = game == null or not game.busy()
		if ready and game != null and not _framed:
			# one-off staging for automated shots, then let things settle for a second
			_framed = true
			if args.has("hot"):
				var hp: Vector2 = game.hotspot()
				rig.set_view(rig.yaw, float(args["hot"]) if args["hot"] != "1" else 26.0, Vector3(hp.x, 0, hp.y))
				rig.snap()
			if args.has("nohud"):
				hud.visible = false
			if args.has("selheart"):
				game.select([game.heart(game.player)])
			if args.has("tech"):
				hud._toggle_tech()
			if args.has("settings"):
				hud._open_settings()
			if args.has("selq"):
				for s in game.structs:
					if s.f == game.player and s.alive and s.queue.size() >= 2:
						game.select([s])
						rig.set_view(rig.yaw, 22.0, Vector3(s.pos.x, 0, s.pos.y))
						rig.snap()
						break
			# the lineage strands take ~2.5 s to grow in
			_elapsed = minf(_elapsed, wait - (3.0 if args.has("tech") else 1.0))
		if _elapsed >= wait and ready:
			_shot_done = true
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(args["shot"])
			print("SHOT ", args["shot"])
			get_tree().quit()
