# Coral Binder

Stationary Morel Hollow area-control unit, based on `reference_images/morel_hollow_roster.jpg`. Select a connected Morel Patch, choose Coral Binder, click an owned root position and then the direction/end of its growing wall. Right-click or Escape cancels before planting. Growth, movement slowing, melee retaliation and AI placement are tested in `tools/tests/coral_binder.gd`.

The single-surface LODs have 9,864 / 3,924 / 882 triangles. Wall segments use instanced distant LODs. A shared 1024 atlas holds 3D-painted albedo, sculpt-baked normals and AO, and roughness/metalness. `binder_hero.png` and `binder_ingame.png` show the asset; `growth.gif` shows accelerated match growth.

Rebuild with Blender: `blender -b --factory-startup -P tools/blender/binder_build.py -- --cpu`. Inspect atlas with `python tools/art/atlas_lint.py art/binder/binder`; render with `tools/art/render_unit.gd -- --unit=binder`; capture wall growth with `tools/art/binder_ingame.gd`. Run `tools/tests/coral_binder.gd` and `tools/tests/court_units.gd`. Performance: `tools/art/perf_unit.gd -- --unit=binder --rounds=16`; add `--wall=1` for fully grown walls.

Two shape critiques widened the branching and added forks and thorns, then adjusted branch spread, bead color and occlusion. Close inspection still shows projected normal seams and repeated stem/branch joints; further sculpt and bake cleanup is needed to reach the beetle close-up quality bar.

On the RTX 4060 laptop, 16 rounds measured +0.16 ms for 60 battle-detail ungrown roots, and +0.08 ms for 10 fully grown walls with battle-detail roots.
