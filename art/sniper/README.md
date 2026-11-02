# Pilobolus Sniper

A Morel Hollow precision unit based on `reference_images/morel_hollow_roster.jpg`: four dark jointed stilts, a clear, glossy gelatinous stalk and swollen vesicle with droplets, topped by an opaque black sporangium. The glass-like gel uses alpha blending as a separate surface; the legs and cap remain opaque. Transparency sorting can vary when multiple units overlap.

Two surfaces per LOD; three LODs: 22,332 / 7,424 / 2,944 triangles. The shader supplies alternating stilt steps, body sway and a cobra-like rear, forward snap, and recovery with game time. These are shader animations rather than embedded GLB skeletal clips. After a 0.24-second windup the existing 34-damage straight projectile fires from the extended capsule, with small dark sporangium flecks; its original speed, range, targeting and interception remain in use. Portraits use the close mesh.

Rebuild with Blender 4.2 and Godot 4.7.2:

```powershell
blender -b --factory-startup -P tools/blender/sniper_build.py
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=sniper --frames=36
godot --path . --script tools/art/ingame_unit.gd -- --unit=sniper
godot --path . --script tools/art/sniper_attack.gd
godot --headless --path . --script tools/tests/court_units.gd
```

See `sniper_hero.png`, `sniper_ingame_close.png`, `walk.gif`, `attack.gif`, and `combat.gif` for engine captures. Frame directories are ignored. Court tests cover portrait and match meshes, LOD ordering, recoil trigger, windup timing, black projectile, cancellation, shot origin and original 34 damage. The test process reports ObjectDB/resource cleanup warnings at exit.
