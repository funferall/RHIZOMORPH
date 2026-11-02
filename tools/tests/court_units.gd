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
	g._fire(spitter, friend, spitter.d, true)   # released: skip the coil
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

	# --- Muscarine Spitter: coils, then spits on the lash ---
	var sp = g._spawn_unit(0, "spitter", at + Vector2(-12, 8))
	var sp_art = load("res://scripts/muscarine_spitter.gd")
	check(sp.mi.mesh.resource_name.begins_with("Spitter_") and FungusLib.mesh("u_spitter") == sp_art.mesh(0),
		"Muscarine Spitter uses the Blender-built mesh in matches and portraits")
	check(sp_art.stats(0)["triangles"] > sp_art.stats(1)["triangles"] and sp_art.stats(1)["triangles"] > sp_art.stats(2)["triangles"],
		"Spitter has three decreasing LODs")
	var sp_target = g._spawn_unit(1, "wartling", sp.pos + Vector2(5, 0))
	var shots_before: int = g.shots.size()
	g._fire(sp, sp_target, sp.d)
	check(sp.strike == 1.0 and g.shots.size() == shots_before, "The Spitter coils before it spits")
	check(is_equal_approx(Data.UNITS["spitter"]["windup"], sp_art.WINDUP_SECONDS), "Its windup matches the animation's release frame")
	g._update_swings(sp_art.WINDUP_SECONDS + 0.01)
	var spit: Dictionary = g.shots.back()
	check(g.shots.size() == shots_before + 1 and spit["src"] == sp, "The glob leaves on the lash")
	var mouth: Vector3 = sp.node.global_position + Basis(Vector3.UP, -sp.facing) * sp_art.MUZZLE
	check(spit["from"].distance_to(mouth) < 0.001, "It spits from its throat")
	var sp_hp: float = sp_target.hp
	g._update_shots(float(spit["dur"]) + 0.01)
	check(sp_target.hp < sp_hp, "The spit lands")
	sp.alive = false
	sp.node.visible = false
	sp_target.alive = false
	sp_target.node.visible = false

	# --- Elf-cup Slinger: its new visual preserves the ranged shot contract. ---
	var sl = g._spawn_unit(1, "slinger", at + Vector2(15, 12))
	var target = g._spawn_unit(2, "wartling", sl.pos + Vector2(4, 0))
	var art = load("res://scripts/elf_cup_slinger.gd")
	check(sl.mi.mesh.resource_name == "Slinger_battle" and FungusLib.mesh("u_slinger") == art.mesh(0), "Slinger mesh is used in matches and portraits")
	check(art.stats(0)["triangles"] > art.stats(1)["triangles"] and art.stats(1)["triangles"] > art.stats(2)["triangles"], "Slinger has three decreasing LODs")
	sl.facing = 0.7
	var hp_before: float = target.hp
	g._fire(sl, target, sl.d)
	var cup_shot: Dictionary = g.shots.back()
	check(sl.strike == 1.0 and cup_shot["shot"] == "puff" and cup_shot["dmg"] == 10, "Slinger release starts recoil and retains its projectile damage")
	var expected: Vector3 = sl.node.global_position + Basis(Vector3.UP, -sl.facing) * art.MUZZLE
	check(cup_shot["from"].distance_to(expected) < 0.001, "Slinger launches from its oriented cup")
	check(target.hp == hp_before, "Slinger causes no damage before projectile arrival")
	g._update_shots(float(cup_shot["dur"]) + 0.01)
	check(is_equal_approx(target.hp, hp_before - 10.0), "Slinger projectile lands its original 10 damage")

	# Puffball art and lobbed area attack.
	var bomber_test = g._spawn_unit(1, "bomber", at + Vector2(20, 18))
	var bomb_target = g._spawn_unit(2, "wartling", bomber_test.pos + Vector2(5, 0))
	var bomb_near = g._spawn_unit(2, "wartling", bomb_target.pos + Vector2(1, 0))
	var bomb_art = load("res://scripts/puffball_bomber.gd")
	check(bomber_test.mi.mesh.resource_name == "Bomber_battle" and FungusLib.mesh("u_bomber") == bomb_art.mesh(0), "Bomber uses its new match and portrait meshes")
	check(bomb_art.stats(0)["triangles"] > bomb_art.stats(1)["triangles"] and bomb_art.stats(1)["triangles"] > bomb_art.stats(2)["triangles"], "Bomber has three decreasing LODs")
	check(bomb_art.stats(1)["surfaces"] == 1 and bomb_art.stats(1)["triangles"] <= 4000 and bomb_art.material().get_shader_parameter("orm_map") != null, "Bomber has a single budgeted surface and ORM atlas")
	bomber_test.facing = 0.7
	g._rebuild_grid()
	var hp_target: float = bomb_target.hp
	var hp_near: float = bomb_near.hp
	g._fire(bomber_test, bomb_target, bomber_test.d)
	var bomb_shot: Dictionary = g.shots.back()
	var bomb_origin: Vector3 = bomber_test.node.global_position + Basis(Vector3.UP, -bomber_test.facing) * bomb_art.MUZZLE
	check(bomber_test.strike == 1.0 and bomb_shot["arc"] and bomb_shot["dmg"] == 14, "Bomber triggers recoil and keeps its 14-damage lob")
	check(bomb_shot["from"].distance_to(bomb_origin) < 0.001, "Bomber launches from its oriented vent")
	g._update_shots(float(bomb_shot["dur"]) + 0.01)
	check(bomb_target.hp < hp_target and bomb_near.hp < hp_near, "Bomber impact damages enemies in its splash radius")

	# Pilobolus Sniper: precision projectile and visual integration.
	var sn = g._spawn_unit(1, "sniper", at + Vector2(30, 20))
	var sn_target = g._spawn_unit(2, "wartling", sn.pos + Vector2(6, 0))
	var sn_art = load("res://scripts/pilobolus_sniper.gd")
	check(sn.mi.mesh.resource_name == "Sniper_battle" and FungusLib.mesh("u_sniper") == sn_art.mesh(0), "Sniper uses its match and portrait meshes")
	check(sn_art.stats(0)["surfaces"] == 2 and sn_art.stats(1)["surfaces"] == 2 and sn_art.stats(2)["surfaces"] == 2, "Sniper separates transparent gel and opaque cap at each LOD")
	check(sn_art.stats(0)["triangles"] > sn_art.stats(1)["triangles"] and sn_art.stats(1)["triangles"] > sn_art.stats(2)["triangles"], "Sniper has three decreasing LODs")
	sn.facing = 0.8
	var sn_hp: float = sn_target.hp
	var shot_count: int = g.shots.size()
	g._fire(sn, sn_target, sn.d)
	check(sn.strike == 1.0 and g.shots.size() == shot_count, "Sniper coils before firing")
	g.time += sn_art.WINDUP_SECONDS * 0.5
	g._update_sniper_windups()
	check(g.shots.size() == shot_count, "Sniper does not launch before its windup completes")
	g.time += sn_art.WINDUP_SECONDS * 0.5 + 0.001
	g._update_sniper_windups()
	check(g.shots.size() == shot_count + 1, "Sniper launches one projectile at the end of its windup")
	var sn_shot: Dictionary = g.shots.back()
	var sn_origin: Vector3 = sn.node.global_position + Basis(Vector3.UP, -sn.facing) * sn_art.MUZZLE
	check(not sn_shot["arc"] and sn_shot["dmg"] == 34 and sn_shot["shot"] == "egg", "Sniper preserves precision projectile damage")
	check(sn_shot["from"].distance_to(sn_origin) < 0.001, "Sniper projectile starts at its extended capsule")
	var sn_mat: StandardMaterial3D = sn_shot["node"].material_override
	check(sn_mat.albedo_color.r < 0.03 and not sn_mat.emission_enabled, "Sniper sporangium projectile is black")
	g._update_shots(float(sn_shot["dur"]) + 0.01)
	check(is_equal_approx(sn_target.hp, sn_hp - 34.0), "Sniper precision shot lands its original damage")
	g._fire(sn, sn_target, sn.d)
	var count_before_cancel: int = g.shots.size()
	sn_target.alive = false
	g.time += sn_art.WINDUP_SECONDS + 0.01
	g._update_sniper_windups()
	check(g.shots.size() == count_before_cancel, "Sniper cancels a shot when its target dies during windup")

	# Candlesnuff Runner: trainable scout and timed melee lunge.
	var runner_unit = g._spawn_unit(1, "runner", at + Vector2(36, 24))
	var runner_target = g._spawn_unit(2, "wartling", runner_unit.pos + Vector2(3.4, 0))
	var runner_art = load("res://scripts/candlesnuff_runner.gd")
	check("runner" in Data.STRUCTURES["morel_patch"]["trains"], "Morel Patch trains the Candlesnuff Runner")
	var runner_patch = g._spawn_struct(1, "morel_patch", at + Vector2(40, 24), true)
	runner_patch.connected = true
	var queue_result: String = g.queue_train(runner_patch, "runner")
	check(queue_result == "" and runner_patch.queue.has("runner"), "Runner can be queued at a connected Morel Patch")
	if queue_result == "":
		g.cancel_train(runner_patch)
	check(runner_unit.mi.mesh.resource_name == "Runner_battle" and FungusLib.mesh("u_runner") == runner_art.mesh(0), "Runner uses its match and portrait meshes")
	check(runner_art.stats(0)["triangles"] > runner_art.stats(1)["triangles"] and runner_art.stats(1)["triangles"] > runner_art.stats(2)["triangles"], "Runner has three decreasing LODs")
	check(runner_art.stats(1)["surfaces"] == 1 and runner_art.stats(1)["triangles"] <= 4000 and runner_art.material().get_shader_parameter("orm_map") != null, "Runner has a single budgeted surface and ORM atlas")
	check(is_equal_approx(float(runner_unit.d["windup"]), runner_art.SWING_SECONDS * 0.4), "Runner impact matches the retained windup")
	check(g.fog.sight(runner_unit) == 16.0 and runner_unit.d["speed"] == 8.6, "Runner has extended sight and scout speed")
	runner_unit.f = g.player  # Make the impact visible to the test player.
	runner_target.slow = 0.4
	runner_target.slow_t = 3.0
	runner_target.vel = Vector2(5.0, 0.0)
	var runner_hp: float = runner_target.hp
	var spike_count: int = g._runner_spikes.size()
	g._fire(runner_unit, runner_target, runner_unit.d)
	g._update_swings(0.16)
	check(runner_unit.strike == 1.0 and runner_target.hp == runner_hp and g._runner_spikes.size() == spike_count, "Runner plants its arms before the distant strike")
	g._update_swings(0.17)
	check(is_equal_approx(runner_target.hp, runner_hp - 6.0), "Runner ground strike hits its distant target for configured damage")
	check(is_equal_approx(runner_target.immobilize_t, 1.0) and runner_target.vel == Vector2.ZERO and g._unit_speed(runner_target) == 0.0, "Spike hit immediately immobilizes a moving unit for one second")
	var stuck_pos: Vector2 = runner_target.pos
	runner_target.target = null
	runner_target.think_t = 100.0
	runner_target.goal = stuck_pos + Vector2(8, 0)
	g._update_unit(runner_target, 0.6)
	check(runner_target.pos == stuck_pos and is_equal_approx(runner_target.immobilize_t, 0.4), "Root prevents movement and separation pushes")
	g._damage(runner_target, 1.0, runner_unit.f, runner_unit, false, runner_unit.d)
	check(is_equal_approx(runner_target.immobilize_t, 1.0), "Another hit refreshes the root to one second")
	runner_target.target = null
	runner_target.think_t = 100.0
	g._update_unit(runner_target, 0.5)
	g._update_unit(runner_target, 0.5)
	check(runner_target.pos == stuck_pos and runner_target.immobilize_t == 0.0, "Target stays rooted for the full second")
	check(is_equal_approx(runner_target.slow, 0.4) and runner_target.slow_t > 0.0, "Existing slows survive immobilization")
	g._update_unit(runner_target, 0.05)
	check(runner_target.pos != stuck_pos, "Target resumes its prior movement order after the root expires")
	check(g._runner_spikes.size() == spike_count + 1, "Xylaria spikes appear at impact")
	var spike_effect: Dictionary = g._runner_spikes.back()
	var effect_node: MultiMeshInstance3D = spike_effect["node"]
	check(Vector2(effect_node.position.x, effect_node.position.z).distance_to(stuck_pos) < 0.01 and is_equal_approx(effect_node.position.y, g.board.ground_y(stuck_pos)), "Spike cluster is centered on the target at ground level")
	g._update_runner_spikes(0.0)
	check(float(spike_effect["age"]) == 0.0, "Spike growth pauses with game time")
	g._update_runner_spikes(0.13)
	check(effect_node.scale.y > 0.9, "Spikes rise out of the ground")
	g._update_runner_spikes(1.1)
	check(g._runner_spikes.size() == spike_count, "Spikes retreat and clean up")

	# The effect holds movement only: the rooted unit can still attack.
	var rooted_fighter = g._spawn_unit(2, "wartling", at + Vector2(15, -15))
	var nearby_enemy = g._spawn_unit(0, "wartling", rooted_fighter.pos + Vector2(1.0, 0))
	rooted_fighter.immobilize_t = 1.0
	rooted_fighter.target = nearby_enemy
	rooted_fighter.cd = 0.0
	rooted_fighter.think_t = 100.0
	var rooted_pos: Vector2 = rooted_fighter.pos
	var nearby_hp: float = nearby_enemy.hp
	g._update_unit(rooted_fighter, 0.05)
	check(rooted_fighter.pos == rooted_pos and nearby_enemy.hp < nearby_hp, "Immobilized units can still attack without moving")
	g._damage(runner_patch, 1.0, runner_unit.f, runner_unit, false, runner_unit.d)
	check(runner_patch.immobilize_t == 0.0, "Ground strike does not apply a movement root to structures")

	# A strike cancelled by moving out of reach must not root its target.
	var missed_target = g._spawn_unit(2, "wartling", runner_unit.pos + Vector2(3.0, 0))
	g._fire(runner_unit, missed_target, runner_unit.d)
	missed_target.pos += Vector2(30, 0)
	g._update_swings(0.33)
	check(missed_target.immobilize_t == 0.0, "A missed spike strike does not immobilize")

	# The selectable Rot Bracket uses its static baked mesh.
	var rot_art = load("res://scripts/rot_bracket.gd")
	var rot = g._spawn_struct(1, "rot_bracket", at + Vector2(23, -18), true)
	check(rot.mi.mesh == rot_art.mesh() and FungusLib.mesh("bracket") == rot_art.mesh(), "Rot Bracket uses its baked mesh in matches and portraits")
	check(rot_art.stats()["surfaces"] == 1 and rot_art.stats()["triangles"] <= 20000 and rot_art.mesh().surface_get_material(0).get_shader_parameter("orm_map") != null, "Rot Bracket has one budgeted surface and ORM atlas")

	# Inkcap Bed art and unchanged corpse-gathering behavior.
	var inkbed = g._spawn_struct(1, "inkcap_bed", at + Vector2(20, -18), true)
	inkbed.connected = true
	check(inkbed.mi.mesh.resource_name == "InkcapBed" and inkbed.d["gather"] == 10.0, "Inkcap Bed uses the new clustered mesh and retains its gather range")
	var corpse_at: Vector2 = inkbed.pos + Vector2(2.0, 0)
	var bed_corpse: Dictionary = g.forest._deposit("corpse", corpse_at, 0.0, 6.0)
	bed_corpse["life"] = 40.0
	var ink_rates: Array = [0.0, 0.0, 0.0]
	g.forest._hollow(1, ink_rates)
	check(bed_corpse["kept"] and bed_corpse["pos"].distance_to(inkbed.pos) < 2.0 and ink_rates[1] >= Data.CORPSE_RATE, "Inkcap Bed still preserves, pulls and digests nearby corpses")
	inkbed.f = g.player
	inkbed.node.visible = true
	g.time += 0.1
	g._update_visuals(0.1)
	var drip_clock: float = inkbed.mi.get_instance_shader_parameter("motion_time")
	check(is_equal_approx(drip_clock, g.time), "Inkcap droplets use game time")
	g._update_visuals(0.1)
	check(is_equal_approx(float(inkbed.mi.get_instance_shader_parameter("motion_time")), drip_clock), "Inkcap droplets remain paused when game time stops")

	# --- the beetle: wild, sickening, and as the Choir's Whitecoat Bulwark ---
	var bt_art = load("res://scripts/whitecoat_beetle.gd")
	var bt = g._spawn_unit(2, "t_beetle", at + Vector2(-16, -14))
	bt.goal = bt.pos
	check(bt.mi.mesh == bt_art.mesh(bt.visual_lod, true) and FungusLib.mesh("t_beetle") == bt_art.mesh(0, true)
		and FungusLib.mesh("i_beetle") == bt_art.mesh(0, false), "Beetles use the Blender-built meshes in matches and portraits")
	for infected in [true, false]:
		check(bt_art.stats(0, infected)["triangles"] > bt_art.stats(1, infected)["triangles"]
			and bt_art.stats(1, infected)["triangles"] > bt_art.stats(2, infected)["triangles"], "Beetle has three decreasing LODs (infected %s)" % infected)
	var clean_uv2: PackedVector2Array = bt_art.mesh(1, false).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	var tufted := 0
	for v in clean_uv2:
		if v.x > bt_art.TUFT_KIND:
			tufted += 1
	check(tufted == 0 and bt_art.stats(1, false)["triangles"] < bt_art.stats(1, true)["triangles"], "A healthy beetle has no Beauveria tufts")
	check(float(bt.mi.get_instance_shader_parameter("infect")) == 1.0, "A thrall is fully white")
	var bt_target = g._spawn_unit(0, "wartling", bt.pos + Vector2(1.5, 0))
	bt_target.goal = bt_target.pos
	var bt_hp: float = bt_target.hp
	g._fire(bt, bt_target, bt.d)
	check(bt.strike == 1.0 and bt_target.hp == bt_hp, "The thrall rears before it bites")
	check(is_equal_approx(Data.UNITS["t_beetle"]["windup"], bt_art.WINDUP_SECONDS)
		and is_equal_approx(bt_art.WINDUP_SECONDS, bt_art.IMPACT * bt_art.SWING_SECONDS), "Its windup matches the animation's impact frame")
	g._update_swings(bt_art.WINDUP_SECONDS + 0.01)
	check(bt_target.hp < bt_hp, "The bite lands on the slam")
	var wild = g._spawn_unit(Data.NEUTRAL, "beetle", bt.pos + Vector2(0, 3))
	check(wild.mi.mesh == bt_art.mesh(wild.visual_lod, false), "A wild beetle starts healthy")
	wild.infect = 0.5
	g.fog.reveal(0, wild.pos, 6.0, 60.0)   # fogged units skip their art updates until seen
	g.fog.update()
	g._update_visuals(0.05)
	check(wild.mi.mesh == bt_art.mesh(wild.visual_lod, true) and is_equal_approx(float(wild.mi.get_instance_shader_parameter("infect")), 0.5),
		"A sickening wild beetle grows tufts as its infection rises")
	for u in [bt, bt_target, wild]:
		u.alive = false
		u.node.visible = false

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
