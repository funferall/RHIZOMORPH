# Destroying Angel

The Amanita Court assassin uses an ivory swept hood, warm gill ribs, layered pointed veils, a slender stalk, splayed legs with fungal husks, and two long integral forearm scythes. Built against `reference_images/amanita_court_roster.jpg`.

## Runtime

Three GLBs share a 13-joint skeleton and one mesh surface. Close/battle/distant geometry is 23,864 / 7,441 / 1,704 triangles. Idle (2.4 s), Walk (1.2 s), and Attack (0.95 s) are embedded clips. Attack holds anticipation, snaps through a crossing cut at 43%, then recovers; gameplay accelerates the clip to its 0.85 s cooldown and retains the 0.36 s damage windup.

`scripts/destroying_angel.gd` supplies LODs and revealed/cloaked materials. The revealed shader uses mesh colors for ivory skin and warm gills. The original blue shimmer, enemy concealment, proximity detection, and reveal rules remain in place.

`scripts/angel_slice_trails.gd` samples the actual blade bones during the cut, drawing three short ribbons per blade with a 0.12 s lifetime. Sampling uses game time, including pause/speed, and subdivides fast motion at 120 Hz (capped at 24 samples per visual update). Ribbons live under the unit's visibility root and clear on cloak. No timers or independently visible world effects are used.

## Rebuild and review

From the repository root, with Python, NumPy and Pillow:

```powershell
python tools/destroying_angel/build_angel.py 0
python tools/destroying_angel/build_angel.py 1
python tools/destroying_angel/build_angel.py 2
godot --headless --path . --editor --import --quit
godot --path . --script tools/destroying_angel/render_angel.gd
godot --path . --script tools/art/ingame_unit.gd -- --unit=angel --out=res://art/destroying_angel
godot --headless --path . --script tools/tests/angel_visual.gd
godot --headless --path . --script tools/tests/court_units.gd
```

Review images: `revealed.png`, `cloaked.png`, `angel_ingame.png`, and `angel_ingame_close.png`. `attack.gif` and `walk.gif` show engine-rendered animation. Source frame directories are ignored by Git and Godot.

Verified in Godot 4.7.2: all three LODs load, both blades produce trails, pause freezes trails, trails expire and clear on cloak. Court integration tests pass detection, re-cloaking, attack reveal, and damage timing. The broader Court test reports seven ObjectDB instances at shutdown; no script or rendering errors occurred during asset preview.
