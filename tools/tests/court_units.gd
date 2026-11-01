extends SceneTree
# Run with Godot --path . --script tools/tests/court_units.gd [-- --shots=DIR]
# Real game, real HUD, real rendering. Checks the three integrated Court units:
# Wartling, Webcap and Morel Bruiser art, Cep Bulwark brace / shot capture, Destroying Angel rig and cloak.

const CepActions = preload("res://scripts/cep_actions.gd")
const Data = preload("res://scripts/data.gd")
const FungusLib = preload("res://scripts/fungus_lib.gd")

var failures := 0
var g
var main


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func _initialize() -> void:
	run.call_deferred()


func step(seconds: float) -> void:
	var n := ceili(seconds / 0.05)
	for i in n:
		g._step(0.05)


func run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	g = main.game
	var hud = main.hud
	g.start(0, false)
	g.toggle_pause()   # the test drives the simulation by hand
	hud.menu.visible = false
	var home: Vector2 = g.heart(0).pos
	var at := home + (Vector2.ZERO - home).normalized() * 14.0

	# --- Cep Bulwark ---
	var cep = g._spawn_unit(0, "cep", at)
	check(cep.act != null and cep.radius > 1.0, "Cep spawns with its action controller and a heavy footprint")
	check("cep" in Data.STRUCTURES["cortina_thicket"]["trains"], "Cortina Thicket trains the Cep")
	g.order_brace([cep])
	step(0.5)
	check(cep.act.state == CepActions.State.ROOTING, "Cep is rooting half a second after Brace")
	step(0.7)
	check(cep.act.state == CepActions.State.BRACED and g.rooted(cep), "Cep is braced after its 1 s root")
	var p0: Vector2 = cep.pos
	g.order_move([cep], cep.pos + Vector2(10, 0))
	step(0.4)
	check(cep.act.state == CepActions.State.UPROOTING and cep.pos.distance_to(p0) < 0.05, "A move order uproots first without sliding")
	step(1.0)
	check(cep.act.state == CepActions.State.WALK and cep.pos.distance_to(p0) > 0.5, "After uprooting the Cep walks to its goal")
	g.order_stop([cep])
	g.order_brace([cep])
	step(1.2)
	# an enemy spitter shoots a friend standing beside the braced Cep
	var friend = g._spawn_unit(0, "wartling", cep.pos + Vector2(0, 2.0))
	friend.goal = friend.pos
	var spitter = g._spawn_unit(2, "spitter", cep.pos + Vector2(-9, 0))
	var cep_hp: float = cep.hp
	var friend_hp: float = friend.hp
	var raw: float = Data.UNITS["spitter"]["dmg"]
	g._fire(spitter, friend, spitter.d)
	var shot: Dictionary = g.shots[g.shots.size() - 1]
	for i in 40:
		g._update_shots(0.05)
		if not g.shots.has(shot):
			break
	check(shot.has("bend") and shot["target"] == cep, "A shot at a neighbour bends into the braced Cep")
	check(is_equal_approx(cep_hp - cep.hp, raw * 0.25), "The Cep takes exactly 25%% of the shot (%.2f of %.0f)" % [cep_hp - cep.hp, raw])
	check(friend.hp == friend_hp, "The neighbour is untouched")
	# a lob flies over the roots
	var bomber = g._spawn_unit(2, "spitter", cep.pos + Vector2(-9, 1))
	bomber.d = Data.UNITS["bomber"]
	g._fire(bomber, friend, bomber.d)
	var lob: Dictionary = g.shots[g.shots.size() - 1]
	for i in 60:
		g._update_shots(0.05)
		if not g.shots.has(lob):
			break
	check(not lob.has("bend"), "Lobbed shots are not caught")
	bomber.alive = false
	spitter.alive = false
	bomber.node.visible = false
	spitter.node.visible = false

	# --- Destroying Angel ---
	var angel = g._spawn_unit(0, "angel", at + Vector2(6, -4))
	check(angel.anim != null and angel.anim.has_animation("Attack"), "Angel uses the skinned rig with its clips")
	angel.goal = angel.pos   # held on a move order so it does not strike (and unveil) on its own
	step(0.4)
	check(g.hidden_from(angel, 1) and g.hidden_from(angel, 2), "A lone Angel is cloaked from both rivals")
	var scout = g._spawn_unit(1, "bruiser", angel.pos + Vector2(12, 0))
	scout.goal = scout.pos
	step(0.4)
	check(g._find_target(scout, 20.0, false) != angel, "An enemy 12 m away cannot target the cloaked Angel")
	scout.pos = angel.pos + Vector2(4, 0)
	g._rebuild_grid()
	g._sense_cloak(angel)
	check(not g.hidden_from(angel, 1) and g.hidden_from(angel, 2), "Within 5 m only that rival senses it")
	scout.pos = angel.pos + Vector2(14, 0)
	scout.goal = scout.pos
	g._rebuild_grid()
	g._sense_cloak(angel)
	check(g.hidden_from(angel, 1), "It cloaks again once the rival backs off")
	g._damage(angel, 1.0, 1, scout)
	check(not g.hidden_from(angel, 1), "Being hurt shimmers it into view")
	angel.reveal_t = 0.0
	var victim = g._spawn_unit(1, "slinger", angel.pos + Vector2(1.8, 0))
	victim.goal = victim.pos
	var vhp: float = victim.hp
	angel.goal = Vector2.INF
	angel.target = victim
	angel.cd = 0.0
	step(0.1)
	check(not g.hidden_from(angel, 2), "Striking throws off the cloak")
	check(victim.hp == vhp, "The blade has not landed before the lunge's impact frame")
	step(0.4)
	check(victim.hp < vhp, "The blade lands on the impact frame")
	victim.alive = false
	victim.node.visible = false
	scout.alive = false
	scout.node.visible = false

	# --- Wartling ---
	var w = g._spawn_unit(0, "wartling", at + Vector2(-3, 3))
	check(w.mi.mesh.resource_name.begins_with("Wartling"), "Wartling uses the new shared LOD mesh")
	var wc = g._spawn_unit(0, "webcap", at + Vector2(-6, 3))
	check(wc.mi.mesh.resource_name.begins_with("Webcap_") and wc.mi.mesh.get_surface_count() == 2,
		"Webcap uses the Blender-built mesh: body and silk surfaces")
	check(FungusLib.mesh("u_webcap").resource_name == "Webcap_close",
		"HUD icons use the new Webcap")
	var br = g._spawn_unit(1, "bruiser", at + Vector2(-8, 3))
	check(br.mi.mesh.resource_name.begins_with("Bruiser_"), "Morel Bruiser uses the Blender-built mesh")
	br.goal = br.pos
	var dummy = g._spawn_unit(0, "wartling", br.pos + Vector2(1.6, 0))
	dummy.goal = dummy.pos
	var dhp: float = dummy.hp
	br.target = dummy
	br.cd = 0.0
	step(0.1)
	check(br.strike > 0.0 and dummy.hp == dhp, "The Bruiser's arms go up before its blow lands")
	step(0.4)
	check(dummy.hp < dhp, "The smash lands the blow")

	# --- pictures ---
	var dir: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.trim_prefix("--shots=")
	if dir != "":
		for i in 3:
			g._spawn_unit(0, "wartling", at + Vector2(-4 + i * 1.5, 4.5)).goal = at + Vector2(-4 + i * 1.5, 4.5)
		var cep2 = g._spawn_unit(0, "cep", at + Vector2(3, 3))
		cep2.goal = cep2.pos
		var angel2 = g._spawn_unit(1, "angel", at + Vector2(-5, -1))
		angel2.reveal_t = 999.0
		angel2.goal = angel2.pos
		angel.goal = angel.pos
		angel.reveal_t = 0.0   # the player's own Angel, cloaked: drawn as a blue shimmer
		angel.detected = 0
		hud.visible = false
		for view in [["court_units_wide", 0.6, 16.0], ["court_units_angel", -0.2, 7.0]]:
			main.rig.set_view(view[1], view[2], Vector3(at.x, 0, at.y))
			main.rig.snap()
			for i in 20:
				g._update_visuals(1.0 / 30.0)
				await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			img.save_png(dir.path_join(view[0] + ".png"))
			print("SHOT ", dir.path_join(view[0] + ".png"))
	print("court_units: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
