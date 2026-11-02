# Elf-cup Slinger

Blender-built Morel Hollow ranged unit, based on the top-row Elf-cup Slinger in `reference_images/morel_hollow_roster.jpg`.

The sculpt has a deep scarlet hymenium, a continuous rolled ivory rim, a speckled coral-orange outer cup, a short rear stalk and three curled supports. The red surface is glossier than the stalk. A shared 1024 albedo/normal atlas serves three single-surface LODs: 22,792 / 8,656 / 2,128 triangles.

The runtime shader supplies breathing, alternating support movement, cup flex and a 0.72-second firing recoil with a damped return. This is shader animation, not embedded skeletal GLB clips. `strike` starts at 1 on projectile release; `motion_time` and strike decay use the game's clock. The existing damage, cooldown, range and interception behavior remain unchanged. The golden projectile starts inside the oriented cup, accompanied by a short directional spore burst using the game's existing particle system.

## Reproduce

From the repository root (Blender 4.2, Godot 4.7.2):

```powershell
blender -b --factory-startup -P tools/blender/slinger_build.py
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=slinger --frames=36
godot --path . --script tools/art/ingame_unit.gd -- --unit=slinger
godot --path . --script tools/art/slinger_attack.gd
godot --headless --path . --script tools/tests/court_units.gd
```

The GLBs contain mesh geometry and two UV sets; the runtime script applies the shader and atlas. UV2 stores part identity, support weight and gait pair. `scripts/fungus_lib.gd` supplies the new mesh to HUD portraits as well as the match.

Review: `slinger_hero.png`, `slinger_detail.png`, `slinger_lods.png`, `slinger_ingame_close.png`, `attack.gif`, `walk.gif`, and `combat.gif`. Reproducible frame directories are ignored.

Validation: Court integration checks pass, including the Slinger mesh/portrait hookup, decreasing LOD complexity, oriented muzzle, release animation trigger, no pre-arrival damage and the original 10 damage on impact. The existing Court test reports seven ObjectDB instances at shutdown.
