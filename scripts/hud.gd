extends CanvasLayer
# Player interface, laid out like the inspiration art: resource pill top-centre,
# selection portraits down the left, build bar + spore actions along the bottom,
# minimap with territory and the cord graph bottom-right. Also owns input:
# selection, orders, build placement, ability targeting and the camera keys.

const Data = preload("res://scripts/data.gd")
const FungusLib = preload("res://scripts/fungus_lib.gd")
const CepActions = preload("res://scripts/cep_actions.gd")

const INK := Color(0.055, 0.045, 0.035, 0.86)
const EDGE := Color(0.85, 0.74, 0.45, 0.35)
const TEXT := Color(0.93, 0.89, 0.8)
const DIM := Color(0.62, 0.58, 0.5)
const RES_COL := [Color(0.72, 0.88, 0.4), Color(1.0, 0.74, 0.28), Color(0.78, 0.68, 1.0)]

var game: Node
var audio: Node
var root := Control.new()
var overlay := Control.new()
var pill := Control.new()
var info_lbl := Label.new()
var portraits := VBoxContainer.new()
var build_bar := HBoxContainer.new()
var ability_bar := HBoxContainer.new()
var ctx := PanelContainer.new()
var ctx_box := VBoxContainer.new()
var minimap := Control.new()
var _mm_mat: ShaderMaterial
var mm_tex := TextureRect.new()
var msgs := VBoxContainer.new()
var tech_panel := Control.new()
var tech_canvas := Control.new()
var tech_tip := PanelContainer.new()
var tech_tip_lbl := Label.new()
var _tech_open_t := 0.0
var _tech_nodes := {}      # id -> {pos, r, tier}; "heart" is the root
var _tech_edges := []      # strands along prerequisites: {from, to, pts, cum, delay, branches}
var _tech_fuzz := []       # faint wandering filaments
var _tech_hover := ""
var _tech_faction := -1
var menu := Control.new()
var end_panel := Control.new()
var settings_panel := Control.new()
var settings := {"master": 0.5, "music": 0.55, "sfx": 0.6, "cam_speed": 1.0, "fullscreen": false, "edge_pan": true, "difficulty": "fair", "render": "quality", "show_fps": false,
	"court": 1, "mode": "ffa", "rival": -1}
const RENDER_MODES := {"native": ["Native", 1.0], "quality": ["FSR Quality", 0.77], "balanced": ["FSR Balanced", 0.67], "performance": ["FSR Performance", 0.59]}
var _diff_btns := {}
var _paused_before := false
const SETTINGS_PATH := "user://settings.cfg"
var help := Label.new()

var mode := ""            # build, cast, binder_origin, binder_aim, amove
var _binder_origin := Vector2.INF
var mode_arg := ""
var place_err := ""
var _drag_from := Vector2.INF
var _drag_to := Vector2.ZERO
var _last_click := 0.0
var _last_pick = null
var _mmb_from := Vector2.INF
var _sel_sig := ""
var _icons := {}
var _build_btns := []
var _ab_btns := []
var _font: SystemFont
var _font_b: SystemFont
var _menu_choice := 1
var _menu_cards := []
var _menu_mode := "ffa"       # "duel" (1 v 1) or "ffa" (all three courts)
var _menu_rival := -1         # the court a duel is fought against
var _mode_btns := {}
var _rival_chips: Array = []  # two chips, one per other court: {b, icon, name, line, f}
var _rival_note: Label
var _menu_summary: RichTextLabel
const COURT_LINES := ["feeds the living trees", "eats everything dead", "rides the forest's insects"]
var _ctx_refresh := 0.0
var _ctx_key: Array = []
var _ctx_hp: Label
var _ctx_status: Label
var _ctx_train_buttons: Array = []
var _ctx_queue: HBoxContainer
var _ctx_queue_ids: Array = []
var _ctx_progress: Control
var _ctx_progress_value := 0.0


func _ready() -> void:
	layer = 5
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	_font_b = SystemFont.new()
	_font_b.font_names = PackedStringArray(["Georgia", "Cambria", "Times New Roman"])
	var th := Theme.new()
	th.default_font = _font
	th.default_font_size = 14
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_color", "Button", TEXT)
	th.set_stylebox("panel", "PanelContainer", _box(INK))
	th.set_stylebox("normal", "Button", _box(Color(0.1, 0.085, 0.065, 0.92), 8))
	th.set_stylebox("hover", "Button", _box(Color(0.17, 0.14, 0.1, 0.95), 8, Color(0.95, 0.82, 0.45, 0.8)))
	th.set_stylebox("pressed", "Button", _box(Color(0.22, 0.18, 0.12, 0.95), 8, Color(1, 0.9, 0.5, 1)))
	th.set_stylebox("disabled", "Button", _box(Color(0.07, 0.06, 0.05, 0.8), 8, Color(0.4, 0.35, 0.25, 0.3)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("panel", "TooltipPanel", _box(Color(0.05, 0.04, 0.03, 0.96), 6))
	th.set_color("font_color", "TooltipLabel", TEXT)
	root.theme = th
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	root.add_child(overlay)

	_build_pill()
	_build_portraits()
	_build_bottom()
	_build_ctx()
	_build_minimap()
	_build_msgs()
	_build_tech()
	_load_settings()
	_build_menu()
	_build_end()
	settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_panel.visible = false
	root.add_child(settings_panel)

	get_tree().node_added.connect(func(n):
		if n is BaseButton:
			n.pressed.connect(func():
				if audio:
					audio.play("ui_click")))
	game.message.connect(_on_message)
	game.game_over.connect(_on_game_over)
	_set_hud_visible(false)


func _box(c: Color, r := 12, edge := EDGE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.border_color = edge
	s.set_border_width_all(1)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _label(text: String, size := 14, col := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", _font_b)
	return l


func _set_hud_visible(v: bool) -> void:
	for c in [pill, portraits, build_bar.get_parent(), minimap.get_parent(), msgs, help]:
		c.visible = v


# --- icons: each species rendered once in its own little world -----------------

func icon(species: String) -> Texture2D:
	if _icons.has(species):
		return _icons[species]
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mi := MeshInstance3D.new()
	mi.mesh = FungusLib.mesh(species)
	vp.add_child(mi)
	var aabb := mi.mesh.get_aabb()
	var c := aabb.get_center()
	var size := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = c + Vector3(0.0, 0.35, 1.0).normalized() * size * 2.1
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, c, Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_color = Color(1.0, 0.85, 0.65)
	sun.light_energy = 2.0
	vp.add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.5)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	vp.add_child(we)
	add_child(vp)
	_icons[species] = vp.get_texture()
	return _icons[species]


# --- top resource pill ---------------------------------------------------------

func _build_pill() -> void:
	pill.custom_minimum_size = Vector2(640, 46)
	pill.size = pill.custom_minimum_size
	pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pill.position = Vector2(-320, 10)
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.draw.connect(_draw_pill)
	root.add_child(pill)
	info_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_lbl.position = Vector2(-230, 16)
	info_lbl.size = Vector2(215, 24)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_lbl.add_theme_color_override("font_color", DIM)
	root.add_child(info_lbl)
	help.text = "LMB select, move, attack   drag box-select   Ctrl+LMB attack-move   RMB cancel   WASD pan   Q/E rotate   Y stop   F sporulate / brace   Tab lineages   Space Heart   P pause   +/- speed   Esc settings"
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-430, -20)
	help.size = Vector2(860, 16)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 0.55))
	root.add_child(help)


func _draw_pill() -> void:
	var w := pill.size.x
	pill.draw_style_box(_box(INK, 23), Rect2(Vector2.ZERO, pill.size))
	if not game.started:
		return
	var f: int = game.player
	var r: Array = game.res(f)
	var rate: Array = game.fs[f]["rate"]
	var seg := w / 4.0
	var tips := []
	for i in 4:
		var x0 := seg * i + 16.0
		var cy := 23.0
		var col: Color = RES_COL[i] if i < 3 else Color(0.85, 0.82, 0.75)
		_glyph_res(pill, i, Vector2(x0 + 10, cy), col)
		var val := ""
		var frac := 0.0
		if i < 3:
			val = "%d" % int(r[i])
			frac = clampf(r[i] / (game.spore_cap(f) if i == 2 else 400.0), 0.0, 1.0)
			tips.append("%s %d  (%+.1f/s)" % [_res_name(i), int(r[i]), rate[i]])
		else:
			var p: int = game.pop(f)
			val = "%d/%d" % [p, game.pop_cap(f)]
			frac = float(p) / game.pop_cap(f)
		pill.draw_string(_font, Vector2(x0 + 26, cy - 1), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT)
		if i < 3:
			pill.draw_string(_font, Vector2(x0 + 26, cy + 13), _res_name(i).to_lower() if game.econ(f) == "parasite" and i == 1 else "%+.1f" % rate[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
		var bx := x0 + 72.0
		var bw := seg - 96.0
		pill.draw_rect(Rect2(bx, cy - 3, bw, 6), Color(1, 1, 1, 0.08))
		pill.draw_rect(Rect2(bx, cy - 3, bw * frac, 6), col)
	pill.tooltip_text = "\n".join(tips)


func _res_name(i: int) -> String:
	return Data.FACTIONS[game.player]["res_names"][i]


# "80 cellulose, 20 nitrogen, 70 spores" in the player's own currencies.
func _cost_text(c: Array, spores := 0.0) -> String:
	var parts := []
	for i in 2:
		if c[i] > 0:
			parts.append("%d %s" % [c[i], _res_name(i).to_lower()])
	if spores > 0.0:
		parts.append("%d spores" % spores)
	return "free" if parts.is_empty() else ", ".join(parts)


func _glyph_res(c: Control, i: int, at: Vector2, col: Color) -> void:
	match i:
		0:  # nutrients: a cluster of granules
			for k in 5:
				var a := TAU * k / 5.0
				c.draw_circle(at + Vector2(cos(a), sin(a)) * 5.0, 2.6, col)
			c.draw_circle(at, 3.0, col)
		1:  # sugar: a droplet
			c.draw_circle(at + Vector2(0, 2), 5.5, col)
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-5, 1), at + Vector2(0, -9), at + Vector2(5, 1)]), col)
		2:  # spores: scattered dots
			for k in 7:
				var a := k * 2.4
				c.draw_circle(at + Vector2(cos(a), sin(a)) * (2.0 + k * 1.1), 1.4 + (k % 3) * 0.5, col)
		_:  # population: a little sporeling
			c.draw_circle(at + Vector2(0, -3), 6.0, col)
			c.draw_rect(Rect2(at + Vector2(-2, 1), Vector2(4, 6)), col)


# --- portraits (left column) ---------------------------------------------------

func _build_portraits() -> void:
	portraits.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	portraits.position = Vector2(14, -260)
	portraits.add_theme_constant_override("separation", 8)
	root.add_child(portraits)


func _refresh_portraits() -> void:
	var groups := {}
	var order := []
	for e in game.selected:
		if not e.alive:
			continue
		var key: String = e.id
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(e)
	var sig := ""
	for k in order:
		sig += "%s:%d," % [k, groups[k].size()]
	if sig != _sel_sig:
		_sel_sig = sig
		for c in portraits.get_children():
			c.queue_free()
		for k in order.slice(0, 7):
			var list: Array = groups[k]
			var e = list[0]
			var b := Button.new()
			b.custom_minimum_size = Vector2(78, 78)
			b.tooltip_text = "%s x%d" % [e.d["name"], list.size()]
			b.pressed.connect(func(): game.select(list))
			var tr := TextureRect.new()
			tr.texture = icon(e.d["species"])
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.offset_bottom = -8
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(tr)
			if list.size() > 1:
				var cl := _label("x%d" % list.size(), 12, TEXT)
				cl.position = Vector2(50, 2)
				b.add_child(cl)
			var bar := Control.new()
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_top = -9
			bar.offset_bottom = -4
			bar.offset_left = 8
			bar.offset_right = -8
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.draw.connect(func():
				var hp := 0.0
				var mx := 0.0
				for x in list:
					if x.alive:
						hp += x.hp
						mx += x.max_hp
				bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(0, 0, 0, 0.5))
				bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * (hp / maxf(mx, 1.0)), bar.size.y)), Data.faction_color(e.f)))
			b.add_child(bar)
			portraits.add_child(b)
	for b in portraits.get_children():
		for c in b.get_children():
			if c is Control and c.get_class() == "Control":
				c.queue_redraw()


# --- bottom: build bar and spore actions ---------------------------------------

func _build_bottom() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hb.position = Vector2(-470, -126)
	hb.resized.connect(func():
		# centred on the space left of the minimap, so the last buttons never hide under it
		var shift := (MM_SIZE.x + 30.0) * 0.5
		hb.offset_left = -hb.size.x * 0.5 - shift
		hb.offset_right = hb.size.x * 0.5 - shift
		hb.offset_top = -hb.size.y - 26
		hb.offset_bottom = -26)
	root.add_child(hb)
	var p1 := PanelContainer.new()
	p1.add_child(build_bar)
	build_bar.add_theme_constant_override("separation", 6)
	hb.add_child(p1)
	var p2 := PanelContainer.new()
	p2.add_child(ability_bar)
	ability_bar.add_theme_constant_override("separation", 6)
	hb.add_child(p2)


func _populate_bars() -> void:
	for c in build_bar.get_children():
		c.queue_free()
	for c in ability_bar.get_children():
		c.queue_free()
	_build_btns.clear()
	_ab_btns.clear()
	var fd: Dictionary = Data.FACTIONS[game.player]
	var bl: Array = fd["build"]
	for i in bl.size():
		var sid: String = bl[i]
		var d: Dictionary = Data.STRUCTURES[sid]
		var b := _tile(icon(d["species"]), Data.BUILD_KEYS[i], _cost_str(d["cost"]))
		if bl.size() + fd["abilities"].size() > 11:
			b.custom_minimum_size = Vector2(68, 76)   # a court with many buttons gets slimmer tiles
		b.pressed.connect(func(): _enter_build(sid))
		build_bar.add_child(b)
		_build_btns.append([b, sid])
	var abs: Array = fd["abilities"]
	for i in abs.size():
		var ab: String = abs[i]
		var b := _tile(null, Data.ABILITY_KEYS[i], "%d" % Data.ABILITIES[ab]["cost"], ab)
		if bl.size() + abs.size() > 11:
			b.custom_minimum_size = Vector2(68, 76)
		b.pressed.connect(func(): _enter_cast(ab))
		ability_bar.add_child(b)
		_ab_btns.append([b, ab])


func _cost_str(c: Array, spores := 0.0) -> String:
	if spores > 0.0:
		return "%d sp" % spores
	return "%d" % c[0] if c[1] == 0 else "%d·%d" % [c[0], c[1]]


func _tile(tex: Texture2D, key: String, cost: String, glyph := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(76, 82)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_top = 2
		tr.offset_bottom = -14
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
	else:
		var g := Control.new()
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.offset_bottom = -14
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.draw.connect(func(): _draw_ability_glyph(g, glyph))
		b.add_child(g)
	var kl := _label(key, 11, Color(0.95, 0.85, 0.5))
	kl.position = Vector2(6, 2)
	b.add_child(kl)
	var cl := _label(cost, 11, DIM)
	cl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cl.offset_top = -17
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(cl)
	return b


func _draw_ability_glyph(c: Control, ab: String) -> void:
	var ctr := c.size * 0.5
	var col := Color(0.95, 0.88, 0.6)
	var w := 2.0
	match ab:
		"haze", "lure":
			for k in 3:
				c.draw_arc(ctr, 8.0 + k * 7.0, 0.0, TAU, 32, Color(col, 1.0 - k * 0.28), w)
			if ab == "haze":
				for k in 9:
					c.draw_circle(ctr + Vector2(cos(k * 2.4), sin(k * 2.4)) * (6 + k * 2), 1.8, col)
		"fairy_ring":
			for k in 14:
				var a := TAU * k / 14.0
				c.draw_circle(ctr + Vector2(cos(a), sin(a)) * 20.0, 2.6, col)
		"bloom", "volley", "barrage":
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2(cos(a), sin(a))
				if ab == "barrage":
					c.draw_line(ctr + Vector2(-16 + k * 4.5, -16), ctr + Vector2(-20 + k * 4.5, 4), col, w)
					c.draw_circle(ctr + Vector2(-20 + k * 4.5, 8), 2.2, col)
				else:
					c.draw_line(ctr + d * 6.0, ctr + d * (22.0 if ab == "volley" else 16.0), col, w)
			c.draw_circle(ctr, 5.0 if ab == "bloom" else 3.0, col)
		"zombify":
			var pts := PackedVector2Array()
			for k in 40:
				var t := k / 39.0
				pts.append(ctr + Vector2(cos(t * 12.0), sin(t * 12.0)) * t * 22.0)
			c.draw_polyline(pts, col, w)
		"wildfire":
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(0, -22), ctr + Vector2(12, 4), ctr + Vector2(6, 18), ctr + Vector2(-6, 18), ctr + Vector2(-12, 4)]), Color(1.0, 0.55, 0.2))
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(0, -8), ctr + Vector2(6, 8), ctr + Vector2(0, 16), ctr + Vector2(-6, 8)]), Color(1.0, 0.9, 0.5))
		"carbon_transfer":
			# sugar flowing from two trees into a third
			for sd in [-1.0, 1.0]:
				var src := ctr + Vector2(sd * 18.0, 12.0)
				c.draw_line(src, src + Vector2(0, -14), Color(0.55, 0.42, 0.3), 3.0)
				c.draw_line(src + Vector2(0, -6), ctr + Vector2(sd * 4.0, -6.0), Color(1.0, 0.8, 0.35), w)
			c.draw_line(ctr + Vector2(0, 16), ctr + Vector2(0, -16), Color(0.55, 0.42, 0.3), 4.0)
			c.draw_circle(ctr + Vector2(0, -18), 6.0, Color(0.5, 0.85, 0.35))
		"mast_year":
			# acorns raining from a crown
			c.draw_circle(ctr + Vector2(0, -10), 12.0, Color(0.45, 0.7, 0.3))
			for k in 6:
				var q := ctr + Vector2(-15 + k * 6, 6 + (k % 2) * 7)
				c.draw_circle(q, 3.0, Color(0.8, 0.6, 0.3))
				c.draw_rect(Rect2(q + Vector2(-3, -4), Vector2(6, 2)), Color(0.45, 0.32, 0.18))
		"borer_swarm":
			# jewel beetles converging on a trunk
			c.draw_rect(Rect2(ctr + Vector2(-5, -22), Vector2(10, 44)), Color(0.55, 0.42, 0.3))
			for k in 5:
				var a := TAU * k / 5.0 + 0.3
				var q := ctr + Vector2(cos(a) * 15.0, sin(a) * 18.0)
				var dir := (ctr - q).normalized()
				c.draw_line(q - dir * 5.0, q + dir * 4.0, Color(0.3, 0.85, 0.45), 4.0)
		"pandemic":
			# a host, and clubs bursting from it in every direction
			c.draw_circle(ctr, 6.0, col)
			for k in 7:
				var a := TAU * k / 7.0 - PI * 0.5
				var d := Vector2(cos(a), sin(a))
				c.draw_line(ctr + d * 7.0, ctr + d * 19.0, Color(1.0, 0.6, 0.2), w)
				c.draw_circle(ctr + d * 20.0, 3.0, Color(1.0, 0.6, 0.2))
		"giant_puffball":
			c.draw_circle(ctr + Vector2(0, 3), 15.0, col)
			for k in 10:
				c.draw_circle(ctr + Vector2(cos(k * 2.4), sin(k * 2.4) - 1.0) * (17.0 + k), 1.6, col)


func _update_bars() -> void:
	var f: int = game.player
	for pair in _build_btns:
		var b: Button = pair[0]
		var sid: String = pair[1]
		var d: Dictionary = Data.STRUCTURES[sid]
		var locked: bool = d.has("req") and not game.has_tech(f, d["req"])
		var poor: bool = not game.afford(f, d["cost"])
		b.modulate = Color(1, 1, 1, 0.35) if locked else (Color(1, 0.75, 0.7, 0.8) if poor else Color.WHITE)
		var tip := "%s  [%s]\n%s\nCost: %s" % [d["name"], Data.BUILD_KEYS[_build_btns.find(pair)], d["desc"], _cost_text(d["cost"])]
		if game.econ(f) == "parasite":
			tip += "\nGrows out of a thrall standing within %d m." % int(Data.HOST_RANGE)
		if locked:
			tip += "\nRequires %s" % Data.TECHS[d["req"]]["name"]
		b.tooltip_text = tip
		b.button_pressed = mode == "build" and mode_arg == sid
	for pair in _ab_btns:
		var b: Button = pair[0]
		var ab: String = pair[1]
		var d: Dictionary = Data.ABILITIES[ab]
		var err: String = game.ability_ready(f, ab)
		b.modulate = Color.WHITE if err == "" else Color(1, 1, 1, 0.4)
		b.tooltip_text = "%s\n%s\n%d spores, %ds recharge%s" % [d["name"], d["desc"], d["cost"], int(d["cd"]), ("\n" + err) if err != "" else ""]
		b.button_pressed = mode == "cast" and mode_arg == ab


# --- context panel (what is selected) ------------------------------------------

func _build_ctx() -> void:
	ctx.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ctx.position = Vector2(-300, -250)
	ctx.custom_minimum_size = Vector2(600, 0)
	ctx.add_child(ctx_box)
	ctx_box.add_theme_constant_override("separation", 4)
	ctx.visible = false
	root.add_child(ctx)


# Only selection/action changes rebuild the panel. Live values and queue progress
# retain their controls so refreshes cannot interrupt hover, focus or presses.
func _refresh_ctx() -> void:
	var sel: Array = game.selected
	if sel.is_empty():
		ctx.visible = false
		_ctx_key.clear()
		return
	ctx.visible = true
	var e = sel[0]
	var actions: bool = sel.size() == 1 and e.kind == game.STRUCT and e.f == game.player and e.built >= 1.0
	var key: Array = [sel.duplicate(), actions, e.d.get("trains", []).duplicate(), e.d.has("research")]
	if key != _ctx_key:
		_ctx_key = key
		_rebuild_ctx(sel, actions)
	if sel.size() != 1:
		return
	_ctx_hp.text = "%d / %d" % [ceili(e.hp), int(e.max_hp)]
	var d: Dictionary = e.d
	if e.kind == game.UNIT:
		_ctx_status.text = "%s   dmg %d  range %.1f  speed %.1f" % [d["desc"], d["dmg"], d["range"], d["speed"]]
		if e.id == "binder":
			_ctx_status.text = "%s\nWall: %.1f / %.1f m" % [d["desc"], e.wall_length, e.wall_limit]
		if e.act and e.f == game.player:
			_ctx_status.text = "%s
%s" % [_brace_state(e), _ctx_status.text]
		elif d.has("cloak") and e.f == game.player:
			var cloaked: bool = game.hidden_from(e, (e.f + 1) % 3) and game.hidden_from(e, (e.f + 2) % 3)
			_ctx_status.text = "%s
%s" % ["CLOAKED - unseen by the enemy" if cloaked else "REVEALED - the enemy can see it", _ctx_status.text]
	elif e.kind == game.PUFF:
		_ctx_status.text = "Swelling... bursts in %.1fs" % maxf(6.0 - e.timer, 0.0)
	else:
		var status: String = d["desc"]
		if e.built < 1.0:
			status = "Growing %d%%  -  %s" % [int(e.built * 100), d["desc"]]
		elif not e.connected:
			status = "CUT OFF from the Heart: no income, withering. Rebuild a cord or wait for one to regrow."
		if e.f == game.player and d.has("research") and e.research != "":
			status = "Researching %s  %d%%" % [Data.TECHS[e.research]["name"], int(100 * e.research_t / Data.TECHS[e.research]["time"])]
		_ctx_status.text = status
	if actions:
		for item in _ctx_train_buttons:
			var ud: Dictionary = Data.UNITS[item[1]]
			item[0].modulate = Color.WHITE if game.afford(game.player, ud["cost"], ud.get("spores", 0.0)) else Color(1, 0.75, 0.7, 0.8)
		_refresh_ctx_queue(e)


func _rebuild_ctx(sel: Array, actions: bool) -> void:
	for c in ctx_box.get_children():
		ctx_box.remove_child(c)
		c.queue_free()
	_ctx_train_buttons.clear()
	_ctx_queue_ids.clear()
	_ctx_progress = null
	_ctx_queue = null
	_ctx_hp = null
	_ctx_status = null
	var e = sel[0]
	var head := HBoxContainer.new()
	head.add_child(_label(e.d["name"] if sel.size() == 1 else "%d selected" % sel.size(), 17, Data.faction_color(e.f).lerp(TEXT, 0.4), true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	if sel.size() == 1:
		_ctx_hp = _label("", 13, DIM)
		head.add_child(_ctx_hp)
	ctx_box.add_child(head)
	if sel.any(func(u): return u.kind == game.UNIT and u.f == game.player and u.act != null):
		var bb := Button.new()
		bb.text = "Brace / Uproot  [F]"
		bb.tooltip_text = "Cep Bulwark: sink the roots. While braced it cannot move or attack, but every enemy shot
that flies within 3 m bends into its cap for 25% damage. A move order pulls the roots up first."
		bb.pressed.connect(func(): game.order_brace(game.selected))
		ctx_box.add_child(bb)
	if sel.size() > 1:
		ctx_box.add_child(_label("Right-click to move, right-click an enemy to attack, A then click to attack-move.", 12, DIM))
		return
	_ctx_status = _wrap("")
	ctx_box.add_child(_ctx_status)
	if not actions:
		return
	var d: Dictionary = e.d
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var trains: Array = d.get("trains", [])
	for i in trains.size():
		var uid: String = trains[i]
		var ud: Dictionary = Data.UNITS[uid]
		var b := _tile(icon(ud["species"]), str(i + 1), _cost_str(ud["cost"], ud.get("spores", 0.0)))
		b.custom_minimum_size = Vector2(64, 70)
		b.tooltip_text = "%s [%d]\n%s\nhp %d  dmg %d  range %.1f\nCost: %s" % [ud["name"], i + 1, ud["desc"], ud["hp"], ud["dmg"], ud["range"], _cost_text(ud["cost"], ud.get("spores", 0.0))]
		b.pressed.connect(func(): _train(uid))
		_ctx_train_buttons.append([b, uid])
		row.add_child(b)
	if e.id == "morel_patch":
		var binder_data: Dictionary = Data.UNITS["binder"]
		var bind := _tile(icon(binder_data["species"]), "5", _cost_str(binder_data["cost"]))
		bind.custom_minimum_size = Vector2(64, 70)
		bind.tooltip_text = "%s [5]\n%s\nClick the root position, then the wall endpoint.\nCost: %s" % [binder_data["name"], binder_data["desc"], _cost_text(binder_data["cost"])]
		bind.pressed.connect(_enter_binder)
		_ctx_train_buttons.append([bind, "binder"])
		row.add_child(bind)
	_ctx_queue = HBoxContainer.new()
	_ctx_queue.add_theme_constant_override("separation", 3)
	_ctx_queue.visible = false
	row.add_child(_ctx_queue)
	if d.has("research"):
		var rb := Button.new()
		rb.text = "Lineages (Tab)"
		rb.pressed.connect(func(): _toggle_tech())
		row.add_child(rb)
	if not trains.is_empty():
		row.add_child(_label("  RMB sets rally", 11, DIM))
	ctx_box.add_child(row)


func _refresh_ctx_queue(e) -> void:
	_ctx_queue.visible = not e.queue.is_empty()
	if _ctx_queue_ids != e.queue:
		_ctx_queue_ids = e.queue.duplicate()
		for c in _ctx_queue.get_children():
			_ctx_queue.remove_child(c)
			c.queue_free()
		_ctx_progress = null
		if not e.queue.is_empty():
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(10, 0)
			_ctx_queue.add_child(gap)
			for i in e.queue.size():
				var ud: Dictionary = Data.UNITS[e.queue[i]]
				var cell := Control.new()
				cell.custom_minimum_size = Vector2(42, 50)
				var tr := TextureRect.new()
				tr.texture = icon(ud["species"])
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.position = Vector2(1, 0)
				tr.size = Vector2(40, 40)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(tr)
				if i == 0:
					_ctx_progress = cell
					cell.draw.connect(func():
						cell.draw_rect(Rect2(3, 44, 36, 4), Color(0, 0, 0, 0.6))
						cell.draw_rect(Rect2(3, 44, 36 * _ctx_progress_value, 4), GOLD))
				else:
					tr.modulate = Color(1, 1, 1, 0.55)
				_ctx_queue.add_child(cell)
			var cb := Button.new()
			cb.text = "x"
			cb.tooltip_text = "Cancel the last one (refunds it)"
			cb.custom_minimum_size = Vector2(30, 30)
			cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cb.pressed.connect(func(): game.cancel_train(e))
			_ctx_queue.add_child(cb)
	if _ctx_progress:
		_ctx_progress_value = clampf(e.train_t / Data.UNITS[e.queue[0]]["train"], 0.0, 1.0)
		_ctx_progress.queue_redraw()


func _brace_state(e) -> String:
	match e.act.state:
		CepActions.State.ROOTING: return "ROOTING..."
		CepActions.State.BRACED: return "BRACED - catching enemy shots within 3 m (25% damage)"
		CepActions.State.UPROOTING: return "UPROOTING..."
	return "Loose - press F to brace"


func _wrap(text: String) -> Label:
	var l := _label(text, 13, Color(0.85, 0.8, 0.7))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	return l


func _train(uid: String) -> void:
	var tot := 0
	for e in game.selected:
		if e.kind == game.STRUCT and uid in e.d.get("trains", []):
			var err: String = game.queue_train(e, uid)
			if err != "":
				if tot == 0:
					_on_message(err, Color(1, 0.6, 0.5))
				break
			tot += 1
			break
	_ctx_refresh = 0.0


# --- minimap -------------------------------------------------------------------

const MM_SIZE := Vector2(288, 216)

func _build_minimap() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.position = Vector2(-MM_SIZE.x - 30, -MM_SIZE.y - 30)
	root.add_child(panel)
	var holder := Control.new()
	holder.custom_minimum_size = MM_SIZE
	panel.add_child(holder)
	mm_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	mm_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mm_tex.stretch_mode = TextureRect.STRETCH_SCALE
	mm_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D myc_tex : filter_linear;
uniform sampler2D sub_tex : filter_linear;
uniform vec3 c0; uniform vec3 c1; uniform vec3 c2;
uniform sampler2D fog_tex : filter_linear;
uniform float fog_on = 0.0;
void fragment() {
	vec4 s = texture(sub_tex, UV);
	vec3 d = clamp(texture(myc_tex, UV).rgb, 0.0, 1.0);
	vec3 col = mix(vec3(0.16, 0.24, 0.07), vec3(0.22, 0.15, 0.08), s.a);
	col = mix(col, vec3(0.42, 0.41, 0.38), smoothstep(0.2, 0.6, s.r));
	col = mix(col, vec3(0.04, 0.05, 0.05), smoothstep(0.05, 0.4, s.g));
	float tot = clamp(d.r + d.g + d.b, 0.0, 1.0);
	vec3 tint = (d.r * c0 + d.g * c1 + d.b * c2) / max(d.r + d.g + d.b, 0.001);
	col = mix(col, tint * 0.75, smoothstep(0.1, 0.5, tot) * 0.8);
	float fv = fog_on > 0.5 ? texture(fog_tex, UV).r : 1.0;
	vec3 grey = vec3(dot(col, vec3(0.3, 0.5, 0.2)));
	col = mix(mix(col * 0.05, grey * 0.5, smoothstep(0.05, 0.4, fv)), col, smoothstep(0.6, 0.95, fv));
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("myc_tex", game.myc.texture)
	mat.set_shader_parameter("sub_tex", ImageTexture.create_from_image(game.board.sub_img))
	for f in 3:
		var c: Color = Data.FACTIONS[f]["color"]
		mat.set_shader_parameter("c%d" % f, Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("fog_tex", game.fog.tex)
	mat.set_shader_parameter("fog_on", 1.0 if game.fog.enabled else 0.0)
	mm_tex.material = mat
	_mm_mat = mat
	mm_tex.texture = ImageTexture.create_from_image(game.board.sub_img)
	holder.add_child(mm_tex)
	minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.draw.connect(_draw_minimap)
	minimap.gui_input.connect(_minimap_input)
	holder.add_child(minimap)


func _w2m(p: Vector2) -> Vector2:
	return Data.world_to_uv(p) * MM_SIZE


func _m2w(m: Vector2) -> Vector2:
	var uv := m / MM_SIZE
	return Vector2(uv.x * Data.HALF_W * 2.0 - Data.HALF_W, uv.y * Data.HALF_D * 2.0 - Data.HALF_D)


func _draw_minimap() -> void:
	if not game.started:
		return
	for c in game.cords:
		if c.alive and c.node.visible:
			var col: Color = Data.faction_color(c.f)
			if c.regrow > 0.0:
				col = Color(col, 0.3)
			minimap.draw_line(_w2m(c.a.pos), _w2m(c.b.pos), col.lightened(0.3), 1.5)
	for s in game.structs:
		if s.alive and s.node.visible:
			var col: Color = Data.faction_color(s.f).lightened(0.35)
			var r := 4.5 if s.d.has("research") else 2.6
			minimap.draw_circle(_w2m(s.pos), r + 1.0, Color(0, 0, 0, 0.6))
			minimap.draw_circle(_w2m(s.pos), r, col if s.connected else Color(0.5, 0.45, 0.4))
	for u in game.units:
		if u.alive and u.node.visible:
			minimap.draw_rect(Rect2(_w2m(u.pos) - Vector2(1, 1), Vector2(2.2, 2.2)), Data.faction_color(u.f) if u.f != Data.NEUTRAL else Color(0.7, 0.62, 0.45, 0.6))
	for tr in game.forest.trees:
		minimap.draw_circle(_w2m(tr["pos"]), tr["radius"] * 2.0, Color(0.25, 0.16, 0.08))
	# camera footprint
	var vs := root.get_viewport_rect().size
	var corners := [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(0, vs.y)]
	var poly := PackedVector2Array()
	for c in corners:
		var cam: Camera3D = game.rig.cam
		var o := cam.project_ray_origin(c)
		var dir := cam.project_ray_normal(c)
		if dir.y > -0.01:
			dir.y = -0.01
		var t := -o.y / dir.y
		var g := o + dir * minf(t, 400.0)
		poly.append(_w2m(Vector2(g.x, g.z)).clamp(Vector2.ZERO, MM_SIZE))
	poly.append(poly[0])
	minimap.draw_polyline(poly, Color(1, 1, 0.9, 0.85), 1.5)


func _minimap_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		var w := _m2w(ev.position)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			game.rig.focus(Vector3(w.x, 0, w.y))
		elif ev.button_index == MOUSE_BUTTON_RIGHT and _own_units_selected():
			game.order_move(game.selected, w, false)
	elif ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var w := _m2w(ev.position)
		game.rig.focus(Vector3(w.x, 0, w.y))


# --- messages ------------------------------------------------------------------

func _build_msgs() -> void:
	msgs.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msgs.position = Vector2(-300, 66)
	msgs.custom_minimum_size = Vector2(600, 0)
	msgs.alignment = BoxContainer.ALIGNMENT_BEGIN
	msgs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(msgs)


func _on_message(text: String, col: Color) -> void:
	if audio and col == Color(1, 0.6, 0.5):
		audio.play("ui_error")
	var l := _label(text, 15, col.lerp(TEXT, 0.35))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(600, 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	msgs.add_child(l)
	while msgs.get_child_count() > 4:
		msgs.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


# --- lineages: a hyphal network grown out of the Heart -------------------------
# No panel: the screen dims and strands of mycelium grow from your Heart to each
# lineage along its prerequisites. Knots are the techs; researched strands turn
# into gold-beaded cords. Click a knot to research it, click outside to close.

const TECH_SIZE := Vector2(1120, 620)
const TECH_SPEED := 560.0          # how fast the strands grow, px/s
const GOLD := Color(1.0, 0.72, 0.28)

func _build_tech() -> void:
	tech_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	tech_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	tech_panel.visible = false
	tech_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_toggle_tech())
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.01, 0.008, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tech_panel.add_child(shade)
	tech_canvas.anchor_left = 0.5
	tech_canvas.anchor_right = 0.5
	tech_canvas.anchor_top = 0.5
	tech_canvas.anchor_bottom = 0.5
	tech_canvas.offset_left = -TECH_SIZE.x * 0.5
	tech_canvas.offset_right = TECH_SIZE.x * 0.5
	tech_canvas.offset_top = -TECH_SIZE.y * 0.5
	tech_canvas.offset_bottom = TECH_SIZE.y * 0.5
	tech_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	tech_canvas.draw.connect(_draw_tech)
	tech_canvas.gui_input.connect(_tech_input)
	tech_canvas.mouse_exited.connect(func(): _tech_hover = "")
	tech_panel.add_child(tech_canvas)
	tech_tip.visible = false
	tech_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tech_tip.add_theme_stylebox_override("panel", _box(Color(0.06, 0.05, 0.035, 0.95), 10, Color(1.0, 0.72, 0.28, 0.45)))
	tech_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tech_tip_lbl.custom_minimum_size = Vector2(290, 0)
	tech_tip_lbl.add_theme_font_size_override("font_size", 13)
	tech_tip.add_child(tech_tip_lbl)
	tech_canvas.add_child(tech_tip)
	root.add_child(tech_panel)


func _toggle_tech() -> void:
	tech_panel.visible = not tech_panel.visible
	if tech_panel.visible:
		if _tech_faction != game.player:
			_grow_tech_geometry(game.player)
		_tech_open_t = Time.get_ticks_msec() / 1000.0
		_tech_hover = ""
		tech_tip.visible = false
		tech_canvas.queue_redraw()


# Lay out the knots (Heart, then tier columns) and grow the strand geometry once.
func _grow_tech_geometry(f: int) -> void:
	_tech_faction = f
	_tech_nodes.clear()
	_tech_edges.clear()
	_tech_fuzz.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + f
	var mid := TECH_SIZE.y * 0.52
	_tech_nodes["heart"] = {"pos": Vector2(120, mid), "r": 62.0, "tier": 0}
	var techs: Array = Data.FACTIONS[f]["techs"]
	var cols := {1: [], 2: [], 3: []}
	for t in techs:
		cols[Data.TECHS[t]["tier"]].append(t)
	var xs := {1: 400.0, 2: 680.0, 3: 960.0}
	for tier in cols:
		var list: Array = cols[tier]
		for i in list.size():
			var y := mid if list.size() == 1 else lerpf(mid - 125.0, mid + 125.0, float(i) / (list.size() - 1))
			_tech_nodes[list[i]] = {"pos": Vector2(xs[tier], y), "r": 56.0, "tier": tier}
	for t in techs:
		var reqs: Array = Data.TECHS[t]["req"]
		if reqs.is_empty():
			reqs = ["heart"]
		for rq in reqs:
			_tech_edges.append(_strand(rq, t, rng))
	# faint wandering hyphae around every knot, for texture
	for id in _tech_nodes:
		var n: Dictionary = _tech_nodes[id]
		var start: float = _node_delay(id)
		for k in (14 if id == "heart" else 7):
			var a := rng.randf() * TAU
			var p: Vector2 = n["pos"] + Vector2(cos(a), sin(a)) * n["r"] * 0.9
			_tech_fuzz.append(_walk(p, a, rng.randi_range(8, 22), 9.0, 0.5, rng, start + rng.randf() * 0.3))


func _node_delay(id: String) -> float:
	# the moment the strand reaching this knot arrives
	var tier: int = _tech_nodes[id]["tier"]
	return 0.0 if tier == 0 else 0.15 + tier * 0.55


func _strand(from_id: String, to_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var a: Dictionary = _tech_nodes[from_id]
	var b: Dictionary = _tech_nodes[to_id]
	var dir: Vector2 = (b["pos"] - a["pos"]).normalized()
	var p0: Vector2 = a["pos"] + dir * a["r"] * 0.85
	var p1: Vector2 = b["pos"] - dir * b["r"] * 0.85
	var perp := Vector2(-dir.y, dir.x)
	var L := p0.distance_to(p1)
	var n := maxi(int(L / 6.0), 8)
	var ph := rng.randf() * TAU
	var amp := rng.randf_range(10.0, 22.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var wob := sin(t * PI) * (amp * sin(t * PI * 1.3 + ph) + 3.0 * sin(t * 23.0 + ph * 2.0))
		pts.append(p0.lerp(p1, t) + perp * wob)
	var cum := _cum(pts)
	var delay := _node_delay(from_id) + 0.05
	var branches := []
	for k in rng.randi_range(5, 9):
		var i := rng.randi_range(2, n - 2)
		var base_a := atan2(pts[i + 1].y - pts[i].y, pts[i + 1].x - pts[i].x)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var ang := base_a + side * rng.randf_range(0.5, 1.2)
		branches.append(_walk(pts[i], ang, rng.randi_range(4, 11), 7.0, 0.35, rng, delay + cum[i] / TECH_SPEED))
	return {"from": from_id, "to": to_id, "pts": pts, "cum": cum, "delay": delay, "branches": branches}


# A random-walking filament that sometimes forks once.
func _walk(p: Vector2, ang: float, steps: int, step: float, turn: float, rng: RandomNumberGenerator, delay: float) -> Dictionary:
	var pts := PackedVector2Array([p])
	var forks := []
	for i in steps:
		ang += rng.randf_range(-turn, turn)
		p += Vector2(cos(ang), sin(ang)) * step * rng.randf_range(0.7, 1.2)
		pts.append(p)
		if i > 2 and forks.is_empty() and rng.randf() < 0.12:
			forks.append(_walk(p, ang + rng.randf_range(-1.0, 1.0), maxi(steps - i - 2, 2), step * 0.8, turn, rng, delay + (i + 1) * step / TECH_SPEED))
	return {"pts": pts, "cum": _cum(pts), "delay": delay, "forks": forks}


func _cum(pts: PackedVector2Array) -> PackedFloat32Array:
	var c := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		c.append(c[i - 1] + pts[i].distance_to(pts[i - 1]))
	return c


# Draw a polyline up to `grown` pixels of its length.
func _draw_grown(pts: PackedVector2Array, cum: PackedFloat32Array, grown: float, col: Color, w: float) -> void:
	if grown <= 0.0 or pts.size() < 2:
		return
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		if cum[i] <= grown:
			out.append(pts[i])
		else:
			var k := (grown - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.001)
			out.append(pts[i - 1].lerp(pts[i], k))
			break
	if out.size() >= 2:
		tech_canvas.draw_polyline(out, col, w, true)


func _point_at(pts: PackedVector2Array, cum: PackedFloat32Array, d: float) -> Vector2:
	for i in range(1, pts.size()):
		if cum[i] >= d:
			return pts[i - 1].lerp(pts[i], (d - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.001))
	return pts[pts.size() - 1]


func _draw_filament(fl: Dictionary, t: float, col: Color, w: float) -> void:
	_draw_grown(fl["pts"], fl["cum"], (t - fl["delay"]) * TECH_SPEED * 0.6, col, w)
	for fk in fl["forks"]:
		_draw_filament(fk, t, col, w * 0.8)


func _draw_tech() -> void:
	if _tech_faction < 0:
		return
	var f: int = game.player
	var now := Time.get_ticks_msec() / 1000.0
	var t := now - _tech_open_t
	var gold := GOLD.lerp(Data.faction_color(f), 0.25)
	tech_canvas.draw_string(_font_b, Vector2(24, 46), "Lineages", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.97, 0.88, 0.62))
	tech_canvas.draw_string(_font, Vector2(26, 72), "Grown at your Heart, one at a time. Click a knot to research it. Tab or click outside to close.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	for tier in [1, 2, 3]:
		var x: float = [0.0, 400.0, 680.0, 960.0][tier]
		tech_canvas.draw_string(_font, Vector2(x - 60, 112), ["", "FIRST", "SECOND", "THIRD"][tier] + " FLUSH", HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(DIM, 0.7))
	for fl in _tech_fuzz:
		_draw_filament(fl, t, Color(0.88, 0.85, 0.75, 0.09), 1.0)
	for e in _tech_edges:
		var st := _tech_state(e["to"])
		var col: Color
		var w := 2.0
		match st:
			3:
				col = gold
				w = 3.4
			2:
				col = gold.lerp(Color(1, 1, 1), 0.2) * Color(1, 1, 1, 0.55 + 0.35 * sin(now * 4.0))
				w = 2.6
			1:
				col = Color(0.93, 0.91, 0.84, 0.7)
			_:
				col = Color(0.6, 0.55, 0.46, 0.3)
				w = 1.5
		for br in e["branches"]:
			_draw_filament(br, t, Color(col, col.a * 0.4), 1.0)
		var grown: float = (t - e["delay"]) * TECH_SPEED
		_draw_grown(e["pts"], e["cum"], grown, Color(0.02, 0.015, 0.01, 0.6), w + 3.0)
		_draw_grown(e["pts"], e["cum"], grown, col, w)
		var cum: PackedFloat32Array = e["cum"]
		var L: float = cum[cum.size() - 1]
		if st == 3 and grown >= L:
			# supply beads travelling toward the newer knot
			for k in 3:
				var u := fposmod(now * 0.22 + k / 3.0, 1.0)
				var p := _point_at(e["pts"], cum, u * L)
				tech_canvas.draw_circle(p, 6.5, Color(gold, 0.18))
				tech_canvas.draw_circle(p, 3.0, gold.lightened(0.35))
	for id in _tech_nodes:
		_draw_knot(id, t, now, gold, f)


func _tech_state(id: String) -> int:
	return 3 if id == "heart" else game.tech_state(game.player, id)


func _draw_knot(id: String, t: float, now: float, gold: Color, f: int) -> void:
	var n: Dictionary = _tech_nodes[id]
	var grow := clampf((t - _node_delay(id)) / 0.4, 0.0, 1.0)
	if grow <= 0.0:
		return
	grow = 1.0 - pow(1.0 - grow, 3.0)
	var st := _tech_state(id)
	var hover := id == _tech_hover
	var c: Vector2 = n["pos"]
	var r: float = n["r"] * grow * (1.06 if hover else 1.0)
	var seed := float(absi(id.hash()) % 1000) * 0.01
	var blob := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		var rr := r * (1.0 + 0.07 * sin(a * 3.0 + seed) + 0.05 * sin(a * 5.0 + seed * 2.0) + 0.02 * sin(a * 11.0 + now * 0.8))
		blob.append(c + Vector2(cos(a), sin(a)) * rr)
	var fill: Color
	var rim: Color
	match st:
		3:
			fill = Color(0.3, 0.22, 0.1, 0.96)
			rim = gold
		2:
			fill = Color(0.19, 0.15, 0.09, 0.96)
			rim = gold * Color(1, 1, 1, 0.6 + 0.4 * sin(now * 4.0))
		1:
			fill = Color(0.14, 0.115, 0.085, 0.96)
			rim = Color(0.92, 0.89, 0.8)
		_:
			fill = Color(0.08, 0.065, 0.05, 0.94)
			rim = Color(0.42, 0.38, 0.31)
	if hover:
		rim = rim.lightened(0.3)
	# fuzzy hairs where the hyphae enter the knot
	for i in 18:
		var a := TAU * i / 18.0 + seed
		var p0 := c + Vector2(cos(a), sin(a)) * r * 0.95
		tech_canvas.draw_line(p0, p0 + Vector2(cos(a + 0.3), sin(a + 0.3)) * (5.0 + 4.0 * sin(seed * 7.0 + i)), Color(rim, 0.35), 1.0, true)
	tech_canvas.draw_colored_polygon(blob, fill)
	blob.append(blob[0])
	tech_canvas.draw_polyline(blob, rim, 2.4 if st >= 1 else 1.4, true)
	if grow < 1.0:
		return
	if id == "heart":
		var hs: String = Data.STRUCTURES[Data.FACTIONS[f]["heart"]]["species"]
		var sz := r * 1.45
		tech_canvas.draw_texture_rect(icon(hs), Rect2(c - Vector2(sz, sz) * 0.5 - Vector2(0, 6), Vector2(sz, sz)), false)
		tech_canvas.draw_string(_font_b, c + Vector2(-r, r + 24), "Heart", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, gold)
		return
	var td: Dictionary = Data.TECHS[id]
	var words: PackedStringArray = td["name"].split(" ")
	var lines: Array[String] = []
	var line := ""
	for wd in words:
		if line != "" and (line + " " + wd).length() > 11:
			lines.append(line)
			line = wd
		else:
			line = wd if line == "" else line + " " + wd
	lines.append(line)
	var name_col: Color = [Color(0.6, 0.55, 0.46), Color(0.96, 0.93, 0.85), gold.lightened(0.3), gold.lightened(0.45)][st]
	var y0 := c.y - (lines.size() - 1) * 9.0 - 4.0
	for i in lines.size():
		tech_canvas.draw_string(_font_b, Vector2(c.x - r, y0 + i * 18.0), lines[i], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, name_col)
	var sub := ""
	match st:
		3:
			sub = "grown"
		2:
			var h = game.heart(game.player)
			var prog: float = h.research_t / td["time"] if h else 0.0
			sub = "%d%%" % int(prog * 100.0)
			tech_canvas.draw_arc(c, r + 7.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, gold, 3.0, true)
		1:
			sub = _cost_text(td["cost"], td.get("spores", 0.0))
		_:
			sub = "dormant"
	tech_canvas.draw_string(_font, Vector2(c.x - r, y0 + lines.size() * 18.0 + 2.0), sub, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 11, Color(name_col, 0.8))


func _tech_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var hit := ""
		for id in _tech_nodes:
			if id != "heart" and ev.position.distance_to(_tech_nodes[id]["pos"]) < _tech_nodes[id]["r"]:
				hit = id
		if hit != _tech_hover:
			_tech_hover = hit
			_show_tech_tip(hit)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tech_canvas.accept_event()
		if _tech_hover == "":
			return
		var err: String = game.start_research(game.player, _tech_hover)
		if err != "":
			_on_message(err, Color(1, 0.6, 0.5))
		else:
			_show_tech_tip(_tech_hover)


func _show_tech_tip(id: String) -> void:
	if id == "":
		tech_tip.visible = false
		return
	var td: Dictionary = Data.TECHS[id]
	var st := _tech_state(id)
	var reqs := ", ".join(td["req"].map(func(x): return Data.TECHS[x]["name"]))
	var status: String = ["Needs " + reqs, "Click to grow it: %s, %d s" % [_cost_text(td["cost"], td.get("spores", 0.0)), int(td["time"])],
		"Growing now", "Already grown"][st]
	tech_tip_lbl.text = "%s\n\n%s\n\n%s" % [td["name"], td["desc"], status]
	var n: Dictionary = _tech_nodes[id]
	var x: float = n["pos"].x + n["r"] + 18.0
	if x + 320.0 > TECH_SIZE.x:
		x = n["pos"].x - n["r"] - 330.0
	tech_tip.position = Vector2(x, n["pos"].y - 50.0)
	tech_tip.reset_size()
	tech_tip.visible = true


# --- start menu and end screen -------------------------------------------------

func show_menu() -> void:
	menu.visible = true
	_set_hud_visible(false)


func _build_menu() -> void:
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(cc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(900, 0)
	vb.add_theme_constant_override("separation", 9)
	cc.add_child(vb)
	var title := _label("RHIZOMORPH", 54, Color(0.97, 0.88, 0.62), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := _label("Three fungal courts. One forest floor. Each eats it a different way.", 15, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	# 1 - your court
	vb.add_child(_menu_head("1  ·  Your court"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for f in 3:
		var fd: Dictionary = Data.FACTIONS[f]
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 228)
		b.toggle_mode = true
		var tr := TextureRect.new()
		tr.texture = icon(Data.STRUCTURES[fd["heart"]]["species"])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(55, 6)
		tr.size = Vector2(150, 136)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
		var n := _label(fd["name"], 21, fd["color"].lerp(TEXT, 0.25), true)
		n.position = Vector2(0, 144)
		n.size = Vector2(260, 28)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(n)
		var m := _label(fd["motto"], 13, DIM)
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.position = Vector2(14, 176)
		m.size = Vector2(232, 44)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(m)
		b.pressed.connect(func():
			_menu_choice = f
			_refresh_menu())
		_menu_cards.append(b)
		row.add_child(b)

	# 2 - how many courts
	vb.add_child(_menu_head("2  ·  The battle"))
	var mrow := HBoxContainer.new()
	mrow.alignment = BoxContainer.ALIGNMENT_CENTER
	mrow.add_theme_constant_override("separation", 16)
	vb.add_child(mrow)
	for key in ["duel", "ffa"]:
		var mb := Button.new()
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(300, 62)
		var t := _label("Duel  ·  1 v 1" if key == "duel" else "Free-for-all  ·  3 courts", 19, TEXT, true)
		t.position = Vector2(0, 7)
		t.size = Vector2(300, 26)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mb.add_child(t)
		var d := _label("You against one rival court." if key == "duel" else "Everyone against everyone.", 13, DIM)
		d.position = Vector2(0, 35)
		d.size = Vector2(300, 20)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mb.add_child(d)
		mb.pressed.connect(func():
			_menu_mode = key
			_refresh_menu())
		_mode_btns[key] = mb
		mrow.add_child(mb)

	# 3 - who you face, and how hard they push
	vb.add_child(_menu_head("3  ·  Your rivals"))
	var rrow := HBoxContainer.new()
	rrow.alignment = BoxContainer.ALIGNMENT_CENTER
	rrow.add_theme_constant_override("separation", 16)
	vb.add_child(rrow)
	for i in 2:
		var cb := Button.new()
		cb.toggle_mode = true
		cb.custom_minimum_size = Vector2(300, 64)
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(10, 4)
		ic.size = Vector2(60, 56)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cb.add_child(ic)
		var nl := _label("", 18, TEXT, true)
		nl.position = Vector2(80, 9)
		nl.size = Vector2(210, 24)
		cb.add_child(nl)
		var ll := _label("", 13, DIM)
		ll.position = Vector2(80, 35)
		ll.size = Vector2(210, 20)
		cb.add_child(ll)
		var chip := {"b": cb, "icon": ic, "name": nl, "line": ll, "f": -1}
		cb.pressed.connect(func():
			# picking one rival is a duel against it
			_menu_mode = "duel"
			_menu_rival = chip["f"]
			_refresh_menu())
		_rival_chips.append(chip)
		rrow.add_child(cb)
	_rival_note = _label("", 13, DIM)
	_rival_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_rival_note)
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 10)
	vb.add_child(drow)
	var dl := _label("Rival strength", 15, DIM)
	dl.custom_minimum_size = Vector2(110, 0)
	drow.add_child(dl)
	var ddesc := _label("", 13, DIM)
	ddesc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pick_diff := func(key: String):
		settings["difficulty"] = key
		for k in _diff_btns:
			_diff_btns[k].button_pressed = k == key
		ddesc.text = Data.DIFFICULTY[key]["desc"]
	for key in Data.DIFFICULTY_ORDER:
		var db := Button.new()
		db.text = Data.DIFFICULTY[key]["name"]
		db.toggle_mode = true
		db.custom_minimum_size = Vector2(130, 36)
		db.pressed.connect(func(): pick_diff.call(key))
		drow.add_child(db)
		_diff_btns[key] = db
	vb.add_child(ddesc)
	pick_diff.call(settings["difficulty"] if Data.DIFFICULTY.has(settings["difficulty"]) else "fair")

	# the matchup, then go
	_menu_summary = RichTextLabel.new()
	_menu_summary.bbcode_enabled = true
	_menu_summary.fit_content = true
	_menu_summary.scroll_active = false
	_menu_summary.custom_minimum_size = Vector2(900, 30)
	_menu_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_summary.add_theme_font_override("bold_font", _font_b)
	_menu_summary.add_theme_font_size_override("bold_font_size", 21)
	_menu_summary.add_theme_font_size_override("normal_font_size", 17)
	vb.add_child(_menu_summary)
	var go := Button.new()
	go.text = "Awaken"
	go.custom_minimum_size = Vector2(220, 52)
	go.add_theme_font_override("font", _font_b)
	go.add_theme_font_size_override("font_size", 22)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func():
		menu.visible = false
		settings["court"] = _menu_choice
		settings["mode"] = _menu_mode
		settings["rival"] = _menu_rival
		_save_settings()
		game.difficulty = settings["difficulty"]
		game.start(_menu_choice, false, _menu_courts()))
	vb.add_child(go)
	var tips := _label("Court and Hollow buildings live on rhizomorph cords to the Heart: cut a rival's cords and everything past them starves. Esc: settings and controls.", 13, Color(0.8, 0.75, 0.65))
	tips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tips)
	root.add_child(menu)
	# start from the last match's choices
	_menu_choice = clampi(int(settings["court"]), 0, 2)
	_menu_mode = "duel" if settings["mode"] == "duel" else "ffa"
	_menu_rival = int(settings["rival"])
	if OS.get_cmdline_user_args().has("--menu=duel"):
		_menu_mode = "duel"   # automated screenshots of the duel setup
	_refresh_menu()


func _menu_head(text: String) -> Label:
	var l := _label(text, 16, Color(0.97, 0.88, 0.62), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.custom_minimum_size = Vector2(0, 34)   # breathing room above each step
	return l


# The courts in the chosen match: yours first.
func _menu_courts() -> Array:
	if _menu_mode == "duel":
		return [_menu_choice, _menu_rival]
	return [_menu_choice] + _menu_others()


func _menu_others() -> Array:
	return [0, 1, 2].filter(func(o): return o != _menu_choice)


func _court_bb(f: int) -> String:
	var fd: Dictionary = Data.FACTIONS[f]
	return "[b][color=#%s]%s[/color][/b]" % [fd["color"].lerp(TEXT, 0.25).to_html(false), fd["name"]]


func _refresh_menu() -> void:
	for i in _menu_cards.size():
		_menu_cards[i].button_pressed = i == _menu_choice
	for k in _mode_btns:
		_mode_btns[k].button_pressed = k == _menu_mode
	var others := _menu_others()
	if not others.has(_menu_rival):
		_menu_rival = others[0]
	var duel := _menu_mode == "duel"
	for i in _rival_chips.size():
		var c: Dictionary = _rival_chips[i]
		var o: int = others[i]
		var fd: Dictionary = Data.FACTIONS[o]
		c["f"] = o
		c["icon"].texture = icon(Data.STRUCTURES[fd["heart"]]["species"])
		c["name"].text = fd["name"]
		c["name"].add_theme_color_override("font_color", fd["color"].lerp(TEXT, 0.25))
		c["line"].text = COURT_LINES[o]
		var on: bool = not duel or o == _menu_rival
		c["b"].button_pressed = on
		c["b"].modulate = Color(1, 1, 1, 1.0 if on else 0.5)
	_rival_note.text = "Click the other court to face it instead." if duel else "Both rival courts take the field, and fight each other too. Click one to duel it alone."
	var vs := _court_bb(_menu_rival) if duel else "%s  and  %s" % [_court_bb(others[0]), _court_bb(others[1])]
	_menu_summary.text = "[center]%s   [color=#%s]against[/color]   %s[/center]" % [_court_bb(_menu_choice), DIM.to_html(false), vs]


# --- settings (Esc) -------------------------------------------------------------

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cf.get_value("settings", k, settings[k])
	_apply_settings()


func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func _apply_settings() -> void:
	if audio:
		audio.set_volumes(settings["master"], settings["music"], settings["sfx"])
	# render scale: FSR2 upscales a smaller 3D render (and does its own anti-aliasing)
	var vp := root.get_viewport()
	var rm: Array = RENDER_MODES.get(settings["render"], RENDER_MODES["quality"])
	var render_override := false
	for arg in OS.get_cmdline_user_args():
		if arg.get_slice("=", 0) in ["--fsr", "--fpstest"]:
			render_override = true
			break
	if not render_override:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if rm[1] >= 1.0 else Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = rm[1]
		vp.use_taa = rm[1] >= 1.0
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(want)


func _open_settings() -> void:
	_build_settings()
	_paused_before = game.paused
	if game.started and not game.paused:
		game.toggle_pause()
	settings_panel.visible = true


func _close_settings() -> void:
	settings_panel.visible = false
	_save_settings()
	if game.started and game.paused and not _paused_before:
		game.toggle_pause()


func _build_settings() -> void:
	for c in settings_panel.get_children():
		c.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(shade)
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(-280, -300)
	settings_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	var t := _label("Paused", 34, Color(0.97, 0.88, 0.62), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for row in [["master", "Master volume"], ["music", "Music"], ["sfx", "Effects"], ["cam_speed", "Camera speed"]]:
		var key: String = row[0]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var l := _label(row[1], 15, TEXT)
		l.custom_minimum_size = Vector2(150, 0)
		h.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0 if key != "cam_speed" else 0.4
		sl.max_value = 1.0 if key != "cam_speed" else 2.5
		sl.step = 0.01
		sl.value = settings[key]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size = Vector2(260, 24)
		var pct := _label("", 14, DIM)
		pct.custom_minimum_size = Vector2(56, 0)
		var show := func(v: float):
			pct.text = ("%d%%" % int(v * 100)) if key != "cam_speed" else ("x%.1f" % v)
		show.call(sl.value)
		sl.value_changed.connect(func(v: float):
			settings[key] = v
			show.call(v)
			_apply_settings())
		h.add_child(sl)
		h.add_child(pct)
		vb.add_child(h)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 12)
	var rl := _label("Render quality", 15, TEXT)
	rl.custom_minimum_size = Vector2(150, 0)
	rh.add_child(rl)
	var ob := OptionButton.new()
	var keys := ["native", "quality", "balanced", "performance"]
	for k in keys:
		ob.add_item("%s (%d%%)" % [RENDER_MODES[k][0], int(RENDER_MODES[k][1] * 100)])
	ob.selected = maxi(keys.find(settings["render"]), 0)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.item_selected.connect(func(i: int):
		settings["render"] = keys[i]
		_apply_settings())
	rh.add_child(ob)
	vb.add_child(rh)
	for row in [["fullscreen", "Fullscreen"], ["edge_pan", "Scroll at the screen edge"], ["show_fps", "Show frames per second"]]:
		var key: String = row[0]
		var cb := CheckBox.new()
		cb.text = row[1]
		cb.button_pressed = settings[key]
		cb.toggled.connect(func(on: bool):
			settings[key] = on
			_apply_settings())
		vb.add_child(cb)
	var ctl := _label("Left click: select your units and buildings, click the ground to move, click an enemy to attack, drag to box-select, double-click to select all of a kind. Ctrl+click: attack-move. With a trainer selected, click the ground to set its rally point.\nRight click: cancel, or drop the selection.   WASD / arrows: pan   Q / E: rotate   Wheel: zoom\nY stop   F sporulate (Choir) / brace (Cep Bulwark)   1-4 train   5 Coral Binder (Morel Patch)   Z X C V R spore actions   Tab lineages   Space your Heart   P pause   +/- speed", 13, DIM)
	ctl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctl.custom_minimum_size = Vector2(520, 0)
	vb.add_child(ctl)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	vb.add_child(btns)
	for spec in [["Resume", func(): _close_settings()],
			["Quit to menu", func():
				_save_settings()
				Engine.time_scale = 1.0
				get_tree().reload_current_scene()],
			["Quit game", func():
				_save_settings()
				get_tree().quit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(150, 42)
		b.pressed.connect(spec[1])
		btns.add_child(b)


func _build_end() -> void:
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.visible = false
	end_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(end_panel)


func _on_game_over(won: bool) -> void:
	for c in end_panel.get_children():
		c.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.add_child(shade)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-300, -100)
	vb.custom_minimum_size = Vector2(600, 0)
	vb.add_theme_constant_override("separation", 16)
	end_panel.add_child(vb)
	var t := _label("The forest floor is yours." if won else "Your Heart has rotted.", 40, Color(0.97, 0.88, 0.62) if won else Color(0.9, 0.5, 0.4), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var s := _label("%d minutes of mycelial war." % int(game.time / 60.0), 15, DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	var b := Button.new()
	b.text = "Again"
	b.custom_minimum_size = Vector2(200, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		Engine.time_scale = 1.0
		get_tree().reload_current_scene())
	vb.add_child(b)
	end_panel.visible = true


# --- per frame -----------------------------------------------------------------

var _was_started := false

func _process(delta: float) -> void:
	if not game.started:
		if menu.visible:
			game.rig.yaw += delta * 0.04
		return
	if not _was_started:
		_was_started = true
		_set_hud_visible(true)
		_populate_bars()
	_camera_keys(delta)
	_update_bars()
	_refresh_portraits()
	_ctx_refresh -= delta
	if _ctx_refresh <= 0.0:
		_ctx_refresh = 0.25
		_refresh_ctx()
	_update_ghost()
	if tech_panel.visible:
		tech_canvas.queue_redraw()
	var w: String = {"rain": "Rain", "dry": "Dry spell", "wind": "Windstorm"}.get(game.weather.now, "")
	if w == "" and game.weather.next_t <= game.weather.ANNOUNCE:
		w = "%s in %ds" % [{"rain": "Rain", "dry": "Dry spell", "wind": "Windstorm"}[game.weather.next], int(game.weather.next_t)]
	var fps := ("   %d fps" % Engine.get_frames_per_second()) if settings["show_fps"] else ""
	info_lbl.text = "%s%s  x%s   %d:%02d%s%s" % ["PAUSED  " if game.paused else "", Data.FACTIONS[game.player]["name"], str(game.speed), int(game.time) / 60, int(game.time) % 60, fps, ("
" + w) if w != "" else ""]
	pill.queue_redraw()
	overlay.queue_redraw()
	minimap.queue_redraw()


func _camera_keys(delta: float) -> void:
	var v := Vector2.ZERO
	if settings_panel.visible:
		return
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		v.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		v.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		v.y += 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		v.y -= 1
	var mp := root.get_viewport().get_mouse_position()
	var vs := root.get_viewport_rect().size
	if settings["edge_pan"] and DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, vs).has_point(mp) and not tech_panel.visible:
		var m := 4.0
		if mp.x < m:
			v.x -= 1
		elif mp.x > vs.x - m:
			v.x += 1
		if mp.y < m:
			v.y += 1
		elif mp.y > vs.y - m:
			v.y -= 1
	if Input.is_key_pressed(KEY_Q):
		game.rig.yaw -= delta * 1.6
	if Input.is_key_pressed(KEY_E):
		game.rig.yaw += delta * 1.6
	if v != Vector2.ZERO:
		var unscaled := delta / maxf(Engine.time_scale, 0.01)
		game.rig.pan_world(Vector2(v.x, -v.y) * game.rig.dist * 0.9 * unscaled * settings["cam_speed"])


# --- build ghost on the terrain ------------------------------------------------

func _update_ghost() -> void:
	var tm: ShaderMaterial = game.board.terrain_mat
	var mp := root.get_viewport().get_mouse_position()
	if mode in ["build", "cast", "binder_origin", "binder_aim"]:
		var g: Vector3 = game.ground_hit(mp)
		if g != Vector3.INF:
			var p := Vector2(g.x, g.z)
			var r: float
			if mode == "build":
				r = Data.STRUCTURES[mode_arg]["radius"]
				place_err = game.place_error(game.player, mode_arg, p)
			elif mode == "cast":
				r = Data.ABILITIES[mode_arg]["radius"]
				place_err = game.cast_error(game.player, mode_arg, p)
			else:
				r = 0.8
				if mode == "binder_aim":
					place_err = "Choose at least 1 m of clear ground" if game.binder_line_limit(_binder_origin, p) < 1.0 else game.binder_place_error(game.player, _binder_origin)
					p = _binder_origin
				else:
					place_err = game.binder_place_error(game.player, p)
			tm.set_shader_parameter("ghost_pos", p)
			tm.set_shader_parameter("ghost_r", r)
			tm.set_shader_parameter("ghost_col", Color(0.6, 1.0, 0.5) if place_err == "" else Color(1.0, 0.35, 0.3))
		var trees: bool = mode == "build" and Data.STRUCTURES[mode_arg].get("on", "") in ["tree", "gap"]
		tm.set_shader_parameter("show_grid", 1.0 if trees else 0.0)
		var zs := []
		for i in 24:
			var tr: Dictionary = game.forest.trees[i] if i < game.forest.trees.size() else {}
			zs.append(Vector4(tr["pos"].x, tr["pos"].y, tr["roots"] if tr["alive"] else 0.0, 1.0) if not tr.is_empty() else Vector4.ZERO)
		tm.set_shader_parameter("zones", zs)
	else:
		tm.set_shader_parameter("ghost_r", 0.0)
		tm.set_shader_parameter("show_grid", 0.0)


# --- overlay: health bars, drag box, placement hints ---------------------------

# Each tree's vigor as a leaf-green bar at its base; for the Hollow, how much is
# left in every log, snag and litter pile.
func _draw_forest(cam: Camera3D, vs: Vector2) -> void:
	for t in game.forest.trees:
		if not game.fog.visible(game.player, t["pos"]):
			continue
		var at: Vector3 = game._v3(t["pos"], 3.2)
		if cam.is_position_behind(at):
			continue
		var sp := cam.unproject_position(at)
		if not Rect2(Vector2.ZERO, vs).has_point(sp):
			continue
		if not t["alive"]:
			overlay.draw_string(_font, sp + Vector2(-20, 0), "snag", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.7, 0.55, 0.8))
			continue
		var v: float = t["vigor"]
		var col := Color(0.55, 0.4, 0.2).lerp(Color(0.5, 0.95, 0.35), v)
		var r := Rect2(sp + Vector2(-26, 0), Vector2(52, 4))
		overlay.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.55))
		overlay.draw_rect(Rect2(r.position, Vector2(52 * v, 4)), col)
		var fed: int = t["fed"][0] + t["fed"][1] + t["fed"][2]
		if fed > 0:
			overlay.draw_string(_font, sp + Vector2(30, 5), "x%d" % fed, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	if game.econ(game.player) != "saprotroph":
		return
	for d in game.forest.deposits:
		if d["kind"] == "corpse" or d["kind"] == "rubble":
			continue
		var full: float = d["c0"] + d["n0"]
		if full <= 0.0 or not game.fog.seen(game.player, d["pos"]):
			continue
		var at: Vector3 = game._v3(d["pos"], 1.5)
		if cam.is_position_behind(at):
			continue
		var sp := cam.unproject_position(at)
		var k := clampf((d["c"] + d["n"]) / full, 0.0, 1.0)
		var r := Rect2(sp + Vector2(-18, 0), Vector2(36, 3))
		overlay.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.5))
		overlay.draw_rect(Rect2(r.position, Vector2(36 * k, 3)), Color(0.85, 0.66, 0.38))

func _draw_overlay() -> void:
	if not game.started:
		return
	var cam: Camera3D = game.rig.cam
	var vs := root.get_viewport_rect().size
	for list in [game.units, game.structs, game.puffs]:
		for e in list:
			if not e.alive or not e.node.visible:
				continue
			var show: bool = e.selected or e.hp < e.max_hp - 0.5 or (e.kind == game.STRUCT and (e.built < 1.0 or not e.queue.is_empty() or e.research != ""))
			if not show:
				continue
			var top: Vector3 = e.node.global_position + Vector3(0, _top_of(e), 0)
			if cam.is_position_behind(top):
				continue
			var sp := cam.unproject_position(top)
			if not Rect2(Vector2(-50, -50), vs + Vector2(100, 100)).has_point(sp):
				continue
			var w := 44.0 if e.kind == game.STRUCT else 24.0
			var r := Rect2(sp + Vector2(-w * 0.5, -12), Vector2(w, 4))
			overlay.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.65))
			var c: Color = Data.faction_color(e.f)
			overlay.draw_rect(Rect2(r.position, Vector2(w * clampf(e.hp / e.max_hp, 0.0, 1.0), 4)), c.lightened(0.15))
			if e.kind == game.STRUCT:
				var prog := -1.0
				if e.built < 1.0:
					prog = e.built
				elif e.research != "":
					prog = e.research_t / Data.TECHS[e.research]["time"]
				elif not e.queue.is_empty():
					prog = e.train_t / Data.UNITS[e.queue[0]]["train"]
				if prog >= 0.0:
					overlay.draw_rect(Rect2(r.position + Vector2(0, 6), Vector2(w, 3)), Color(0, 0, 0, 0.6))
					overlay.draw_rect(Rect2(r.position + Vector2(0, 6), Vector2(w * prog, 3)), Color(1, 0.92, 0.6))
				if not e.connected and e.built >= 1.0:
					overlay.draw_string(_font, sp + Vector2(-30, -18), "CUT OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.5, 0.4))
	_draw_forest(cam, vs)
	# rally points of selected trainers
	for e in game.selected:
		if e.kind == game.STRUCT and e.f == game.player and not e.d.get("trains", []).is_empty() and e.rally != Vector2.INF:
			var a: Vector3 = game._v3(e.pos, 0.3)
			var b: Vector3 = game._v3(e.rally, 0.3)
			if not cam.is_position_behind(a) and not cam.is_position_behind(b):
				overlay.draw_dashed_line(cam.unproject_position(a), cam.unproject_position(b), Color(1, 0.95, 0.7, 0.6), 1.5, 6.0)
				overlay.draw_circle(cam.unproject_position(b), 4.0, Color(1, 0.95, 0.7, 0.8))
	# placement: show which structures the new cord will link to
	if mode == "build":
		var g: Vector3 = game.ground_hit(root.get_viewport().get_mouse_position())
		if g != Vector3.INF:
			var p := Vector2(g.x, g.z)
			for par in game._link_parents(game.player, p):
				var a: Vector3 = game._v3(p, 0.3)
				var b: Vector3 = game._v3(par.pos, 0.3)
				if not cam.is_position_behind(a) and not cam.is_position_behind(b):
					overlay.draw_dashed_line(cam.unproject_position(a), cam.unproject_position(b), Color(1.0, 0.85, 0.4, 0.9), 2.0, 8.0)
	if mode == "binder_origin" or mode == "binder_aim":
		var mouse := root.get_viewport().get_mouse_position()
		var text := "Click the root location" if mode == "binder_origin" else "Click the wall endpoint (maximum 12 m)"
		overlay.draw_string(_font, mouse + Vector2(18, -12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		if mode == "binder_aim":
			var hit: Vector3 = game.ground_hit(mouse)
			if hit != Vector3.INF:
				var q := Vector2(hit.x, hit.z)
				var length: float = game.binder_line_limit(_binder_origin, q)
				var end := _binder_origin + (_binder_origin.direction_to(q) * length)
				var a: Vector3 = game._v3(_binder_origin, 0.25)
				var b: Vector3 = game._v3(end, 0.25)
				if not cam.is_position_behind(a) and not cam.is_position_behind(b):
					overlay.draw_dashed_line(cam.unproject_position(a), cam.unproject_position(b), Color(1.0, 0.82, 0.32, 0.95), 3.0, 8.0)
	if mode in ["build", "cast", "binder_origin", "binder_aim"] and place_err != "":
		var mp := root.get_viewport().get_mouse_position()
		overlay.draw_string(_font, mp + Vector2(18, 28), place_err, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.6, 0.5))
	if mode == "amove":
		var mp := root.get_viewport().get_mouse_position()
		overlay.draw_arc(mp, 10.0, 0.0, TAU, 20, Color(1, 0.4, 0.3), 2.0)
	if _drag_from != Vector2.INF and _drag_from.distance_to(_drag_to) > 6.0:
		var r := Rect2(_drag_from, _drag_to - _drag_from).abs()
		overlay.draw_rect(r, Color(1, 0.95, 0.7, 0.08))
		overlay.draw_rect(r, Color(1, 0.95, 0.7, 0.7), false, 1.0)


func _top_of(e) -> float:
	if e.kind == game.UNIT:
		return FungusLib.height_of(e.d["species"]) + 0.4
	if e.kind == game.PUFF:
		return 6.5 * e.node.scale.y
	return FungusLib.height_of(e.d["species"]) * e.node.scale.y + 0.6


# --- input ---------------------------------------------------------------------

func _own_units_selected() -> bool:
	for e in game.selected:
		if e.kind == game.UNIT and e.f == game.player:
			return true
	return false


func _own_selected(kind: int) -> Array:
	var out := []
	for e in game.selected:
		if e.kind == kind and e.f == game.player:
			out.append(e)
	return out


func _enter_build(sid: String) -> void:
	var d: Dictionary = Data.STRUCTURES[sid]
	if d.has("req") and not game.has_tech(game.player, d["req"]):
		_on_message("Needs %s" % Data.TECHS[d["req"]]["name"], Color(1, 0.6, 0.5))
		return
	mode = "build"
	mode_arg = sid


func _enter_binder() -> void:
	_binder_origin = Vector2.INF
	mode = "binder_origin"
	_on_message("Choose a root location, then a wall endpoint.", TEXT)


func _enter_cast(ab: String) -> void:
	var err: String = game.ability_ready(game.player, ab)
	if err != "":
		_on_message(err, Color(1, 0.6, 0.5))
		return
	mode = "cast"
	mode_arg = ab


func _unhandled_input(ev: InputEvent) -> void:
	if not game.started or game.over:
		return
	if ev is InputEventMouseButton:
		_mouse_button(ev)
	elif ev is InputEventMouseMotion:
		if _drag_from != Vector2.INF:
			_drag_to = ev.position
		if _mmb_from != Vector2.INF:
			game.rig.yaw -= ev.relative.x * 0.006
			game.rig.pitch_bias = clampf(game.rig.pitch_bias + ev.relative.y * 0.15, -20.0, 25.0)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev)


func _mouse_button(ev: InputEventMouseButton) -> void:
	var f: int = game.player
	match ev.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if ev.pressed:
				game.rig.zoom(0.88)
		MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed:
				game.rig.zoom(1.14)
		MOUSE_BUTTON_MIDDLE:
			_mmb_from = ev.position if ev.pressed else Vector2.INF
		MOUSE_BUTTON_LEFT:
			if ev.pressed:
				if mode == "binder_origin" or mode == "binder_aim":
					var hit: Vector3 = game.ground_hit(ev.position)
					if hit != Vector3.INF:
						var point := Vector2(hit.x, hit.z)
						if mode == "binder_origin":
							var err: String = game.binder_place_error(f, point)
							if err != "":
								_on_message(err, Color(1, 0.6, 0.5))
							else:
								_binder_origin = point
								mode = "binder_aim"
						else:
							var err: String = game.try_plant_binder(f, _binder_origin, point)
							if err != "":
								_on_message(err, Color(1, 0.6, 0.5))
							else:
								mode = ""
								_binder_origin = Vector2.INF
					return
				if mode == "build":
					var g: Vector3 = game.ground_hit(ev.position)
					if g != Vector3.INF:
						var err: String = game.try_place(f, mode_arg, Vector2(g.x, g.z))
						if err != "":
							_on_message(err, Color(1, 0.6, 0.5))
						elif not ev.shift_pressed:
							mode = ""
					return
				if mode == "cast":
					var g: Vector3 = game.ground_hit(ev.position)
					if g != Vector3.INF:
						var err: String = game.cast(f, mode_arg, Vector2(g.x, g.z))
						if err != "":
							_on_message(err, Color(1, 0.6, 0.5))
						else:
							mode = ""
					return
				if mode == "amove":
					var g: Vector3 = game.ground_hit(ev.position)
					if g != Vector3.INF:
						game.order_move(_own_selected(game.UNIT), Vector2(g.x, g.z), true)
					mode = ""
					return
				_drag_from = ev.position
				_drag_to = ev.position
			else:
				if _drag_from == Vector2.INF:
					return
				var from := _drag_from
				_drag_from = Vector2.INF
				if from.distance_to(ev.position) > 6.0:
					var picked: Array = game.units_in_rect(Rect2(from, ev.position - from).abs(), f)
					game.select(picked, ev.shift_pressed)
				else:
					_left_click(ev)
				_ctx_refresh = 0.0
		MOUSE_BUTTON_RIGHT:
			# right click backs out: cancel placing or casting, else drop the selection
			if not ev.pressed:
				return
			if mode != "":
				mode = ""
			else:
				game.select([])
				_ctx_refresh = 0.0


# A left click (not a drag). Your own things are selected; with your units
# selected, the ground means "go there" (Ctrl: attack-move on the way) and
# anything else means "attack it"; with only a trainer selected, the ground
# sets its rally point.
func _left_click(ev: InputEventMouseButton) -> void:
	var f: int = game.player
	var e = game.pick(ev.position)
	var now := Time.get_ticks_msec() / 1000.0
	var double: bool = e != null and e == _last_pick and now - _last_click < 0.35
	_last_pick = e
	_last_click = now
	var us := _own_selected(game.UNIT)
	if e and e.kind != game.CORD and e.f == f:
		if double and e.kind == game.UNIT:
			game.select_same_type(e)
		else:
			game.select([e], ev.shift_pressed)
		return
	if e and e.alive and not us.is_empty():
		game.order_attack(us, e)
		_ping(e.pos, Color(1, 0.4, 0.3))
		return
	if e and e.kind != game.CORD:
		game.select([e])   # someone else's: just look at it
		return
	var g: Vector3 = game.ground_hit(ev.position)
	if g == Vector3.INF:
		return
	var p := Vector2(g.x, g.z)
	if not us.is_empty():
		game.order_move(us, p, ev.ctrl_pressed)
		_ping(p, Color(1, 0.55, 0.35) if ev.ctrl_pressed else Color(0.7, 1.0, 0.6))
		return
	var trainers := _own_selected(game.STRUCT).filter(func(s): return not s.d.get("trains", []).is_empty())
	if not trainers.is_empty():
		for s in trainers:
			game.set_rally(s, p)
		_ping(p, Color(1, 0.95, 0.7))
		return
	game.select([])


func _ping(p: Vector2, col: Color) -> void:
	game._burst(game._v3(p, 0.3), col, 12, 1.2, 0.5, 0.4)


func _key(ev: InputEventKey) -> void:
	var f: int = game.player
	var k := ev.keycode
	if k == KEY_ESCAPE:
		if settings_panel.visible:
			_close_settings()
		elif tech_panel.visible:
			tech_panel.visible = false
		elif mode != "":
			mode = ""
		else:
			_open_settings()
		return
	if settings_panel.visible:
		return
	if k == KEY_TAB:
		_toggle_tech()
		return
	if k == KEY_P:
		game.toggle_pause()
		return
	if k == KEY_M and ev.ctrl_pressed and audio:
		audio.toggle_mute()
		_on_message("Sound off" if audio.muted else "Sound on", TEXT)
		return
	if k == KEY_EQUAL or k == KEY_KP_ADD:
		game.set_speed(game.speed * 2.0)
		return
	if k == KEY_MINUS or k == KEY_KP_SUBTRACT:
		game.set_speed(game.speed * 0.5)
		return
	if k == KEY_SPACE:
		var h = game.heart(f)
		if h and h.alive:
			game.rig.focus(game._v3(h.pos))
			game.select([h])
		return
	if k == KEY_Y and _own_units_selected():
		game.order_stop(_own_selected(game.UNIT))
		return
	if k == KEY_F and _own_units_selected():
		game.order_sporulate(_own_selected(game.UNIT))
		game.order_brace(_own_selected(game.UNIT))
		return
	if k == KEY_5:
		for patch in _own_selected(game.STRUCT):
			if patch.id == "morel_patch" and patch.alive and patch.built >= 1.0 and patch.connected:
				_enter_binder()
				return
	if k >= KEY_1 and k <= KEY_4:
		var i := k - KEY_1
		for s in _own_selected(game.STRUCT):
			var trains: Array = s.d.get("trains", [])
			if i < trains.size():
				_train(trains[i])
				return
		return
	var bl: Array = Data.FACTIONS[f]["build"]
	for i in Data.BUILD_KEYS.size():
		if OS.get_keycode_string(k) == Data.BUILD_KEYS[i] and i < bl.size():
			_enter_build(bl[i])
			return
	var abs: Array = Data.FACTIONS[f]["abilities"]
	var ak := [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_R]
	for i in mini(abs.size(), ak.size()):
		if k == ak[i]:
			_enter_cast(abs[i])
			return
