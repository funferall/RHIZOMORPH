# Mycena Sailwing (Amanita Court, flying skirmisher)

From the Amanita Court roster sheet: seven lilac Mycena bonnets (coloured like *Mycena pura*,
glowing like *M. chlorophos*) fanned out like wings from a pale fruiting knot with a hooked beak,
trailing gold hyphae like a jellyfish's tentacles. **Art only for now:** it is not yet in
`data.gd`, so no building trains it. The catalog shows it as an "art preview" plate.

- **Build:** `tools/blender/sailwing_build.py`. The bells are one parametric cap placed seven
  times on a fan from a hub in the body. Each is tipped up from the radial so the lilac tops face
  the sky and the gold gills face the body. A quadratic stem runs into each cap along its axis.
- **Triangles:** close 7,878, battle 2,398, distant 940. One surface and one 1024 atlas
  (albedo, normal, ORM: occlusion, roughness, glow).
- **Atlas:** the caps get the top 58%. The body, the stems and the strands share the bottom row.
  Lint: 0 fail, 0 warn.
- **Paint:**
  - Pale lilac bells deepening to a violet umbo, with dew beads.
  - Striae near the margin show the gold gills through (they glow).
  - Gold gills with amber between them.
  - A bone-white body with an open honeycomb lattice on its back (gold-lit pores) and a horn
    beak.
  - Ivory stems and gold strands with a glowing bead at each tip.

## Motion (`shaders/mycena_sailwing.gdshader`)

Nothing is skinned. It always hovers: there are no feet, and the lowest strand tip is about
0.3 m up.

- **Bells:** each contracts toward its axis, the rim most, like a jellyfish. The pulse ripples
  from the crown out to the wingtips. At rest it beats slowly (2.2 rad/s). In flight it beats
  once per stride (`gait` rad/s).
- **Wings:** each cap and its stem roll about the stem's root (`STEM_ROOT`). They rise as the
  bell opens and fall as it closes, and sweep back in flight. The crown nods instead.
- **Strands:** a travelling wave that streams back in flight.
- **Body:** a hover bob, a slow roll, and the nose dips in flight.
- **Volley** (`strike`, `SWING_SECONDS` 0.8):
  - It rears with its bells flared and wings raised.
  - At `CLAP` = 0.4 the wings beat down, the bells snap shut and the glow flares, and it lunges
    forward.
  - It shivers back to the hover.
  - `WINDUP_SECONDS` = 0.32 = CLAP x SWING_SECONDS, checked in `court_units.gd`.
  - `MUZZLE` is in front of the beak.

The rig constants in the shader come from the build: `blender ... sailwing_build.py -- --rig`.

## Rebuild

```
"/c/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b --factory-startup -P tools/blender/sailwing_build.py -- --preview=C:/tmp/sw.png
"/c/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b --factory-startup -P tools/blender/sailwing_build.py
python tools/art/atlas_lint.py art/sailwing/sailwing
$G --headless --path . --editor --import --quit
$G --path . --script tools/art/render_unit.gd -- --unit=sailwing --frames=24
$G --path . --script tools/art/perf_unit.gd -- --unit=sailwing --rounds=16   # spawns Spitters wearing this mesh
```

## Not done yet

- **In a match:** wiring into `data.gd` and `game.gd` (a unit id, a trainer, `flies`, stats, the
  dart shot), plus an `ingame_unit.gd` capture once it can spawn.
- **Performance:** the benchmark ran but measured nothing. Every variant, including "none", sat
  at 33.3 ms (a 30 fps cap on this laptop at the time), so the cost was hidden. Re-run it on mains
  power or uncapped.
