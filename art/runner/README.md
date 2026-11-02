# Candlesnuff Runner

Morel Hollow scout based on the unit roster and the supplied candlesnuff photograph: charcoal-black branching fungal tissue with powdery white tips. The model has two opposite weight-bearing arms and three LODs (14,400 / 4,800 / 1,600 triangles, one surface each).

Walking is a shader-driven two-step rocking cycle: the body rotates over one arm, stands, then shifts onto the other. The shader follows game time. On attack, both arms press into the ground; after 0.32 seconds, a cluster of nine sharp, pale-tipped Xylaria spikes rises around the target and retreats. A successful hit holds a unit in place for one second, refreshing the duration on another hit; the victim may still attack. The cluster is a single MultiMesh, uses game-time animation, is limited by visibility, and has no effect in simulation-only mode. The attack applies a single target hit; the extra spikes are visual.

The Morel Patch trains Runners as its fourth option (keyboard 4). The scout's initial balance is provisional: 55 HP, 6 damage, 4 range, 2-second cooldown, 8.6 speed, 16 sight, 4-second training and cost 20 cellulose / 4 nitrogen. These values are intended for playtesting.

Rebuild and review with Blender 4.2 and Godot 4.7.2:

```powershell
blender -b --factory-startup -P tools/blender/runner_build.py
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=runner --frames=36
godot --path . --script tools/art/ingame_unit.gd -- --unit=runner
godot --path . --script tools/art/runner_attack.gd
godot --headless --path . --script tools/tests/court_units.gd
```

The GLBs use UV2 for part and motion weight; movement and attack are shader-driven rather than embedded skeletal clips. See `runner_hero.png`, `runner_ingame_close.png`, `walk.gif`, `attack.gif`, and `combat.gif`. Review frame directories are ignored. Integration checks cover training, sight, LODs, delayed damage, one-second immobilization, ground-level placement, pause, growth and cleanup. The Court test reports ObjectDB cleanup warnings on exit.
