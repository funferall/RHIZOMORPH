# Candlesnuff Runner

Morel Hollow scout based on the Xylaria hypoxylon Runner in `reference_images/morel_hollow_roster.jpg`: branching charcoal tissue with powder-white conidial tips. The shared 1024 albedo, sculpt-baked normal and ORM atlas serves one surface per LOD: 5,088 / 1,904 / 696 triangles (close / battle / distant).

UV2 stores branch class, motion weight and alternating support groups. The shader uses game time for the walk and keeps the 0.80-second ground strike and 0.32-second impact. The existing spike, immobilization and training behavior is unchanged. On the RTX 4060 laptop GPU, 16 interleaved rounds measured a median +0.07 ms for 60 battle-detail units over the empty baseline.

Review: `runner_hero.png`, `runner_detail.png`, `runner_lods.png`, `runner_ingame_close.png`, `walk.gif`, `attack.gif` and `combat.gif`. Frame directories are reproducible and ignored.

```powershell
blender -b --factory-startup -P tools/blender/runner_build.py -- --preview=C:/tmp/runner.png
blender -b --factory-startup -P tools/blender/runner_build.py
python tools/art/atlas_lint.py art/runner/runner
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=runner --frames=36
godot --path . --script tools/art/ingame_unit.gd -- --unit=runner
godot --path . --script tools/art/runner_attack.gd
godot --path . --script tools/art/perf_unit.gd -- --unit=runner --rounds=16
godot --headless --path . --script tools/tests/court_units.gd
```
