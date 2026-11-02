extends SceneTree
## Real game checks for Coral Binder placement, wall growth, slowing and thorns.
const Data = preload("res://scripts/data.gd")
const Binder = preload("res://scripts/coral_binder.gd")
var failures := 0
var g
var main

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func click(hud: Node, p: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = g.rig.cam.unproject_position(g._v3(p))
	hud._mouse_button(event)

func run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	g = main.game
	g.start(1, false)
	g.toggle_pause()
	main.hud.menu.visible = false
	var home: Vector2 = g.heart(1).pos
	var patch_pos := home.lerp(Vector2.ZERO, 0.10)
	var patch = g._spawn_struct(1, "morel_patch", patch_pos, true)
	patch.connected = true
	# Seed a small owned patch in the coarse field: a headless test starts before
	# the renderer has propagated or read back mycelium from the new Patch.
	for x in range(-8, 9):
		for y in range(-8, 9):
			var q: Vector2 = patch_pos + Vector2(x, y)
			if q.distance_to(patch_pos) < 7.0:
				g.myc.coarse[g.myc._idx(q) + 1] = 1.0
	var origin := Vector2.INF
	var end := Vector2.INF
	for radius in [4.5, 5.0, 5.5, 6.0]:
		for i in 32:
			var a := float(i) * TAU / 32.0
			var p: Vector2 = patch_pos + Vector2(cos(a), sin(a)) * radius
			if g.binder_place_error(1, p) != "":
				continue
			for j in 8:
				var b := float(j) * TAU / 8.0
				var q := p + Vector2(cos(b), sin(b)) * 7.0
				if g.binder_line_limit(p, q) >= 6.9:
					origin = p
					end = q
					break
			if origin != Vector2.INF:
				break
		if origin != Vector2.INF:
			break
	if origin == Vector2.INF:
		print("DIAG home ", home, " patch ", patch_pos, " myc ok ", g.myc.ok, " coarse ", g.myc.coarse.size(), " funds ", g.res(1), " pop ", g.pop(1), "/", g.pop_cap(1))
		for a in 8:
			var q: Vector2 = patch_pos + Vector2.RIGHT.rotated(float(a)*TAU/8.0)*5.0
			print("DIAG ", q, " -> ", g.binder_place_error(1, q), " owns ", g.forest.owns(1,q))
	check(origin != Vector2.INF, "A valid rooted wall site exists in connected territory")
	if origin == Vector2.INF:
		quit(1)
		return
	var funds: Array = g.res(1).duplicate()
	check(g.try_plant_binder(1, origin, origin) != "" and g.res(1) == funds, "Invalid direction does not charge resources")
	g.select([patch])
	main.hud._refresh_ctx()
	check(main.hud._ctx_train_buttons.any(func(item): return item[1] == "binder"), "Morel Patch offers the placement command")
	g.rig.set_view(0.55, 22.0, Vector3(origin.x, 0, origin.y))
	g.rig.snap()
	await process_frame
	main.hud._enter_binder()
	click(main.hud, origin)
	check(main.hud.mode == "binder_aim" and g.res(1) == funds, "First click fixes the root without paying")
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	main.hud._mouse_button(cancel)
	check(main.hud.mode == "" and g.res(1) == funds and g._binders.is_empty(), "Cancel between clicks leaves no unit or charge")
	main.hud._enter_binder()
	click(main.hud, origin)
	click(main.hud, end)
	check(main.hud.mode == "" and g._binders.size() == 1, "Second click plants a directed Binder")
	if g._binders.is_empty():
		quit(1)
		return
	var wall = g._binders.back()
	check(wall.id == "binder" and wall.kind == g.UNIT and wall.wall_limit > 6.5, "The root is a unit with a bounded wall")
	check(is_equal_approx(g.res(1)[0], funds[0] - Data.UNITS["binder"]["cost"][0]) and is_equal_approx(g.res(1)[1], funds[1] - Data.UNITS["binder"]["cost"][1]), "Placement pays exactly once")
	check(wall.mi.mesh == Binder.mesh(1) and Binder.stats(1)["surfaces"] == 1 and Binder.stats(1)["triangles"] <= 4000, "Binder uses its one-surface battle mesh")
	check(Binder.stats(0)["triangles"] > Binder.stats(1)["triangles"] and Binder.stats(1)["triangles"] > Binder.stats(2)["triangles"], "Binder has decreasing LODs")
	var root_pos: Vector2 = wall.pos
	g.order_move([wall], root_pos + Vector2(9, 0))
	g._update_unit(wall, 12.0)
	check(wall.pos == root_pos and wall.goal == Vector2.INF and is_equal_approx(wall.wall_length, 3.0), "Binder stays rooted and grows linearly at 0.25 m/s")
	var held: float = wall.wall_length
	g._process(0.2)
	check(is_equal_approx(wall.wall_length, held), "Paused game does not grow the wall")
	var dir: Vector2 = wall.wall_dir
	var perp := Vector2(-dir.y, dir.x)
	var enemy = g._spawn_unit(0, "wartling", root_pos + dir * 2.0 + perp * 0.3)
	var ally = g._spawn_unit(1, "wartling", enemy.pos)
	var old_len: float = wall.wall_length
	wall.wall_length = 0.0
	var normal_speed: float = g._unit_speed(enemy)
	var ally_speed: float = g._unit_speed(ally)
	wall.wall_length = old_len
	check(is_equal_approx(g._unit_speed(enemy), normal_speed * 0.3), "The grown wall slows enemy ground units by 70%")
	check(is_equal_approx(g._unit_speed(ally), ally_speed), "The wall does not slow allies")
	var flyer = g._spawn_unit(0, "fly", enemy.pos)
	wall.wall_length = 0.0
	var fly_speed: float = g._unit_speed(flyer)
	wall.wall_length = old_len
	check(is_equal_approx(g._unit_speed(flyer), fly_speed), "Flying units pass over the wall without slowdown")
	wall.wall_length = wall.wall_limit - 0.1
	g._update_unit(wall, 10.0)
	check(is_equal_approx(wall.wall_length, wall.wall_limit), "Growth stops exactly at the selected endpoint")
	wall.wall_length = old_len
	enemy.pos = root_pos + dir * 5.0
	check(is_equal_approx(g._unit_speed(enemy), normal_speed), "Ungrown ground beyond the tip does not slow")
	wall.wall_length = minf(6.5, wall.wall_limit)
	enemy.pos = root_pos + dir * 5.0 + perp * 0.3
	g._rebuild_grid()
	check(g._find_target(enemy, 2.0, false) == wall and g._aim_point(enemy, wall).distance_to(root_pos + dir * 5.0) < 0.01, "Enemies can find and aim at a distant wall segment")
	check(g._enemies_in(0, enemy.pos, 0.5, true, false).has(wall), "Area effects can hit the wall away from its root")
	var enemy_hp: float = enemy.hp
	var wall_hp: float = wall.hp
	g._melee_hit(enemy, wall, 10.0, enemy.d)
	check(is_equal_approx(enemy.hp, enemy_hp - 5.0) and is_equal_approx(wall.hp, wall_hp - 10.0), "A melee hit damages both Binder and attacker")
	enemy_hp = enemy.hp
	g._damage(wall, 4.0, enemy.f, enemy, false, {"shot": "spit"})
	check(is_equal_approx(enemy.hp, enemy_hp), "Ranged damage does not trigger the thorns")
	enemy_hp = enemy.hp
	g._melee_hit(enemy, wall, wall.hp + 1.0, enemy.d)
	check(is_equal_approx(enemy.hp, enemy_hp - 5.0), "A lethal melee blow still takes thorn damage")
	check(not wall.alive and not g._binders.has(wall) and is_equal_approx(g._unit_speed(enemy), normal_speed), "Destroying the Binder removes its wall and slowdown")
	# The Morel AI uses the same placement validation and must not order the
	# stationary Binder into an army or scout route.
	g.res(1)[0] = 400.0
	g.res(1)[1] = 200.0
	g.time = 200.0
	var ai = load("res://scripts/ai.gd").new()
	ai.setup(g, 1)
	ai._plant_binder()
	check(g._binders.size() == 1 and g._binders[0].f == 1, "Morel AI plants a defensive Binder when its economy and site allow")
	if not g._binders.is_empty():
		var ai_wall = g._binders[0]
		ai._scout()
		ai._army()
		check(ai.scout != ai_wall and ai_wall.goal == Vector2.INF, "Morel AI does not assign the rooted Binder as scout or army")
	print("coral_binder: %d failure(s)" % failures)
	quit(1 if failures else 0)
