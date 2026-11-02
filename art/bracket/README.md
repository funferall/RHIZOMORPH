# Rot Bracket

Turkey tail (*Trametes versicolor*) grows as overlapping thin fan shelves on a decaying stump. The atlas carries slate, rust, tan and cream zones with a pale pore surface. The static mesh has 15,696 triangles and one surface, and uses a 1024 albedo, sculpt-baked normal and ORM atlas. `FungusLib.mesh("bracket")` provides it to structures and portraits.

Review: `bracket_hero.png`, `bracket_detail.png` and `bracket_ingame_close.png`.

```powershell
blender -b --factory-startup -P tools/blender/bracket_build.py -- --preview=C:/tmp/bracket.png
blender -b --factory-startup -P tools/blender/bracket_build.py
python tools/art/atlas_lint.py art/bracket/bracket
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=bracket
godot --path . --script tools/art/ingame_bracket.gd
godot --headless --path . --script tools/tests/court_units.gd
```
