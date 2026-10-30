extends Node
# Sound for RHIZOMORPH. Loads whatever picked clips exist in res://audio/sfx and
# res://audio/music (<name>.wav, or <name>_1.wav, _2... for random variants);
# missing sounds are simply silent. World sounds are positional around a
# listener that sits over the camera's focus point, so what you look at is
# what you hear. Music crossfades calm -> tension -> battle with the fighting.

const SFX_DIR := "res://audio/sfx"
const MUSIC_DIR := "res://audio/music"
const LOOPS := ["skitter_loop", "ambient_terrarium", "ambient_mycelium", "ambient_forest", "ambient_rain", "ambient_wind", "ambient_dry"]
const WEATHER_LOOPS := {"rain": "ambient_rain", "wind": "ambient_wind", "dry": "ambient_dry"}
const VOICES := 24
# how many copies of one sound may overlap, and the minimum gap between starts
const LIMIT := {"hit_melee": [6, 0.03], "spit_fire": [4, 0.04], "spit_impact": [4, 0.04], "puff_fire": [3, 0.05],
	"puff_impact": [3, 0.05], "lob_fire": [3, 0.05], "lob_impact": [3, 0.05], "spawn": [3, 0.08], "unit_death": [4, 0.05],
	"thrall_rise": [3, 0.15], "branch_fall": [2, 0.3]}
const FAMILY := {"hit": "hit_melee", "spawn": "spawn"}
const PITCH := {"hit_melee": 0.18, "unit_death": 0.12, "spawn": 0.12, "spit_impact": 0.12, "lob_impact": 0.12}
const VOLUME := {"ambient_terrarium": -10.0, "ambient_mycelium": -14.0, "ambient_forest": -13.0, "ambient_rain": -8.0,
	"ambient_wind": -9.0, "ambient_dry": -14.0, "thrall_rise": -6.0, "skitter_loop": -12.0, "ui_click": -8.0,
	"hit_melee": -4.0, "spawn": -6.0, "place": -2.0}

var game: Node
var rig: Node3D
var sfx := {}            # name -> Array[AudioStream]
var music := {}          # name -> Array[AudioStream] (variants picked at random)
var listener := AudioListener3D.new()
var muted := false

var _voices: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _playing := {}       # name -> Array of players currently on it
var _last := {}          # name -> last start time
var _music_a := AudioStreamPlayer.new()
var _music_b := AudioStreamPlayer.new()
var _music_now := ""
var _music_hold := 0.0
var _intensity := 0.0
var _skitter := AudioStreamPlayer3D.new()
var _amb: Array[AudioStreamPlayer] = []
var _weather := {}       # weather kind -> its looping player, faded in while it lasts


func _ready() -> void:
	_scan()
	add_child(listener)
	listener.make_current()
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_distance = 140.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_voices.append(p)
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_ui.append(p)
	for p in [_music_a, _music_b]:
		p.volume_db = -80.0
		add_child(p)
	_skitter.unit_size = 14.0
	_skitter.volume_db = -80.0
	add_child(_skitter)
	if sfx.has("skitter_loop"):
		_skitter.stream = sfx["skitter_loop"][0]
		_skitter.play()
	for w in WEATHER_LOOPS:
		var n: String = WEATHER_LOOPS[w]
		if sfx.has(n):
			var p := AudioStreamPlayer.new()
			p.stream = sfx[n].pick_random()
			p.volume_db = -80.0
			add_child(p)
			p.play()
			_weather[w] = p
	for n in ["ambient_forest", "ambient_mycelium"]:
		if sfx.has(n):
			var p := AudioStreamPlayer.new()
			p.stream = sfx[n].pick_random()
			p.volume_db = VOLUME[n]
			add_child(p)
			p.play()
			_amb.append(p)
	print("AUDIO %d sfx, %d music" % [sfx.size(), music.size()])


func _scan() -> void:
	for f in _files(SFX_DIR):
		var name := _strip_index(f.get_basename())
		var s := _load(SFX_DIR.path_join(f), name in LOOPS)
		if s:
			if not sfx.has(name):
				sfx[name] = []
			sfx[name].append(s)
	for f in _files(MUSIC_DIR):
		var name := _strip_index(f.get_basename())
		var s := _load(MUSIC_DIR.path_join(f), name in ["menu", "calm", "tension", "battle"])
		if s:
			if not music.has(name):
				music[name] = []
			music[name].append(s)


# "hit_melee_3" -> "hit_melee"; "menu" stays "menu"
func _strip_index(base: String) -> String:
	var tail := base.get_slice("_", base.get_slice_count("_") - 1)
	if tail.is_valid_int() and base.get_slice_count("_") > 1:
		return base.substr(0, base.length() - tail.length() - 1)
	return base


func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in ResourceLoader.list_directory(dir):
		if f.get_extension() in ["wav", "ogg", "mp3"]:
			out.append(f)
	return out


func _load(path: String, looped: bool) -> AudioStream:
	var s: AudioStream = load(path)
	if s == null:
		return null
	if looped:
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif s is AudioStreamOggVorbis or s is AudioStreamMP3:
			s.loop = true
	return s


# --- playing -------------------------------------------------------------------

# at = Vector3.INF plays it flat (UI / alerts).
func play(name: String, at: Vector3 = Vector3.INF, vol := 0.0, pitch_var := -1.0) -> void:
	# per-unit sounds (hit_bruiser, spawn_elite...) mix with their generic family
	var generic: String = FAMILY.get(name.get_slice("_", 0), "")
	if generic != "" and generic != name and (not sfx.has(name) or (sfx.has(generic) and randf() < 0.35)):
		name = generic
	if muted or not sfx.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var lim: Array = LIMIT.get(name, LIMIT.get(FAMILY.get(name.get_slice("_", 0), ""), [4, 0.0]))
	var active: Array = _playing.get(name, []).filter(func(p): return p.playing and p.get_meta("snd", "") == name)
	_playing[name] = active
	if active.size() >= lim[0] or now - _last.get(name, -1.0) < lim[1]:
		return
	_last[name] = now
	var list: Array = sfx[name]
	var stream: AudioStream = list[randi() % list.size()]
	var p
	if at == Vector3.INF:
		p = _free(_ui)
	else:
		p = _free(_voices)
		p.global_position = at
	p.stream = stream
	p.volume_db = VOLUME.get(name, 0.0) + vol
	var pv: float = PITCH.get(name, PITCH.get(FAMILY.get(name.get_slice("_", 0), ""), 0.08)) if pitch_var < 0.0 else pitch_var
	p.pitch_scale = 1.0 + randf_range(-pv, pv)
	p.set_meta("snd", name)
	p.play()
	active.append(p)


func _free(pool: Array):
	for p in pool:
		if not p.playing:
			return p
	# steal the voice that has played longest
	var best = pool[0]
	for p in pool:
		if p.get_playback_position() > best.get_playback_position():
			best = p
	return best


func set_music(name: String, fade := 3.0) -> void:
	if name == _music_now or not music.has(name):
		return
	_music_now = name
	var old := _music_a if _music_a.playing and _music_a.volume_db > -60.0 else _music_b
	var new := _music_b if old == _music_a else _music_a
	var takes: Array = music[name]
	new.stream = takes[randi() % takes.size()]
	new.volume_db = -40.0
	new.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(new, "volume_db", -6.0 if not name in ["victory", "defeat"] else -3.0, fade)
	tw.tween_property(old, "volume_db", -80.0, fade)
	tw.chain().tween_callback(func():
		if old.volume_db <= -79.0:
			old.stop())


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)


# --- per frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	if rig:
		# hear what the camera is looking at, oriented like the camera
		var cam: Camera3D = rig.cam
		var tgt: Vector3 = rig.target
		listener.global_transform = Transform3D(cam.global_transform.basis, tgt.lerp(cam.global_position, 0.18))
	if game == null:
		return
	if not game.started:
		set_music("menu")
		return
	if game.over:
		return
	# weather beds fade in and out with the sky
	for w in _weather:
		var on: bool = game.weather.now == w
		var p: AudioStreamPlayer = _weather[w]
		p.volume_db = lerpf(p.volume_db, VOLUME[WEATHER_LOOPS[w]] if on else -80.0, 1.0 - exp(-delta * (0.8 if on else 0.4)))
	# skitter: louder with more units moving near the focus point
	var moving := 0
	for u in game.units:
		if u.alive and u.walk > 0.3 and u.pos.distance_to(Vector2(rig.target.x, rig.target.z)) < 16.0:
			moving += 1
	_skitter.global_position = rig.target
	var want := -80.0 if moving == 0 else lerpf(-26.0, VOLUME["skitter_loop"], clampf(moving / 12.0, 0.0, 1.0))
	_skitter.volume_db = lerpf(_skitter.volume_db, want, 1.0 - exp(-delta * 3.0))
	# music follows how much of the player's colony is fighting
	var fighting := 0
	for u in game.units:
		if u.alive and u.target != null and (u.f == game.player or u.target.f == game.player):
			fighting += 1
	_intensity = lerpf(_intensity, float(fighting), 1.0 - exp(-delta * 0.6))
	_music_hold -= delta
	var level := "calm"
	if _intensity > 8.0:
		level = "battle"
	elif _intensity > 2.0:
		level = "tension"
	if not music.has(level):
		level = "tension" if music.has("tension") else "calm"
	if level != _music_now and (_music_hold <= 0.0 or _music_now == "menu" or _music_now == ""):
		_music_hold = 20.0
		# coming down from a battle fades slowly, back to tension or calm
		set_music(level, 7.0 if _music_now == "battle" else 4.0)


func on_game_over(won: bool) -> void:
	set_music("victory" if won else "defeat", 1.5)
