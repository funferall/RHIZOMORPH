# Elf-cup Slinger

Morel Hollow ranged unit based on the Sarcoscypha Slinger in `reference_images/morel_hollow_roster.jpg`: a scarlet cup, pale flecked exterior and curling supports. The shared 1024 albedo, sculpt-baked normal and ORM atlas serves one surface per LOD: 4,416 / 1,568 / 480 triangles (close / battle / distant).

UV2 carries support weights and gait groups. The game-time shader animates the supports, cup and 0.72-second recoil; projectile release and the existing oriented muzzle remain unchanged. On the RTX 4060 laptop GPU, 16 interleaved rounds measured a median +0.05 ms for 60 battle-detail units versus the empty baseline.

Review: `slinger_hero.png`, `slinger_detail.png`, `slinger_lods.png`, `slinger_ingame_close.png`, `walk.gif` and `attack.gif`. Frame directories are reproducible and ignored.

```powershell
blender -b --factory-startup -P tools/blender/slinger_build.py -- --preview=C:/tmp/slinger.png
blender -b --factory-startup -P tools/blender/slinger_build.py
python tools/art/atlas_lint.py art/slinger/slinger
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=slinger --frames=36
godot --path . --script tools/art/ingame_unit.gd -- --unit=slinger
godot --path . --script tools/art/perf_unit.gd -- --unit=slinger --rounds=16
godot --headless --path . --script tools/tests/court_units.gd
```
