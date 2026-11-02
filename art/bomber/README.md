# Puffball Bomber

Morel Hollow area bombardment unit based on `reference_images/morel_hollow_roster.jpg`: a pale warted puffball on stout segmented supports with a dark spore vent. Its shared 1024 albedo, sculpt-baked normal and ORM atlas serves one surface per LOD: 6,080 / 2,204 / 808 triangles (close / battle / distant).

UV2 carries the leg weights and alternating gait groups. The game-time shader steps and compresses the sac on firing; the existing 0.8-second recoil, oriented muzzle and lobbed attack remain unchanged. On the RTX 4060 laptop GPU, 16 interleaved rounds measured a median -0.00 ms for 60 battle-detail units versus the empty baseline, below the benchmark resolution.

Review: `bomber_hero.png`, `bomber_detail.png`, `bomber_lods.png`, `bomber_ingame_close.png`, `walk.gif` and `attack.gif`. Frame directories are reproducible and ignored.

```powershell
blender -b --factory-startup -P tools/blender/bomber_build.py -- --preview=C:/tmp/bomber.png
blender -b --factory-startup -P tools/blender/bomber_build.py
python tools/art/atlas_lint.py art/bomber/bomber
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=bomber --frames=36
godot --path . --script tools/art/ingame_unit.gd -- --unit=bomber
godot --path . --script tools/art/perf_unit.gd -- --unit=bomber --rounds=16
godot --headless --path . --script tools/tests/court_units.gd
```
