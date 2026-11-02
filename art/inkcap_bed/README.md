# Inkcap Bed

The existing Morel Hollow Inkcap Bed uses a clustered seven-mushroom model based on the supplied shaggy inkcap references. It has pale stems, rounded caps with overlapping scales, dark deliquescing rims, a mature black cap, hanging ink and 28 independently phased falling droplets.

The model is one mesh surface (41,160 triangles). UV2 identifies the animated droplets; the shader uses the match's game clock so they continue falling during normal play and stop when paused. The existing Inkcap Bed's costs, gathering radius and corpse-preservation mechanics are unchanged. Portraits and the building use the same mesh.

Rebuild and review with Blender 4.2 and Godot 4.7.2:

```powershell
blender -b --factory-startup -P tools/blender/inkcap_bed_build.py
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/inkcap_bed_render.gd
godot --path . --script tools/art/inkcap_bed_ingame.gd
godot --headless --path . --script tools/tests/court_units.gd
```

See `inkcap_bed_hero.png`, `inkcap_bed_ingame_close.png` and `dripping.gif`. Frame directories are ignored. Integration checks verify the mesh, gathering range, corpse preservation and movement, nitrogen production, game-time drip clock and pause behavior. The Court test reports ObjectDB cleanup warnings at exit.
