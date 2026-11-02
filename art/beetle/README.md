# Beetle / Whitecoat Bulwark

The wild beetle (`beetle`, species `i_beetle`) and the Veiled Choir's beetle thrall (`t_beetle`), after the
Whitecoat Bulwark on `reference_images/veiled_choir_roster.png`: *Leptinotarsa* (the Colorado potato beetle)
taken by *Beauveria bassiana* (white muscardine).

- **Healthy:** a tall, domed, cream-yellow shell with five black stripes on each elytron and rows of punctures,
  an orange pronotum and head spotted black, stout orange legs with black knees and tarsi, clubbed antennae.
- **Infected:** cottony white tufts burst from the seams: along the elytral margins and suture, at the pronotum,
  the neck and every leg joint, plus white spore dust settling into the shell's seams.

Both forms come from one set of GLBs. `scripts/whitecoat_beetle.gd` drops the tuft triangles for a healthy beetle,
and the shader's `infect` uniform swells the tufts out of the seams. A wild beetle sickening near a Choir lure
(`Ent.infect`) visibly turns white before it rises as a thrall.

| LOD | infected | healthy |
|---|---|---|
| close | 13,984 tris | 5,728 tris |
| battle | 3,872 tris | 2,000 tris |
| distant | 1,236 tris | 708 tris |

There is one opaque surface and one 1024 atlas (albedo, normal, orm = occlusion / roughness / dust mask). The sculpt of
~1M faces is baked by Cycles in about 50 s on the RTX 4060.

**Motion** is in `shaders/whitecoat_beetle.gdshader` with no skeleton:
- **Walk:** alternating tripods swing about their hips, with body bob and roll, and the antennae flick.
- **Attack:** it rears onto its hind legs with its mandibles spread and front legs pawing, then slams down and
  forward and snaps the mandibles shut. The bite lands at 40% of a 0.75 s clip (`windup` 0.3 in `Data`). On a
  thrall, the tufts puff out and the game shakes a burst of white conidia off it.
- **Tufts:** their edges fray at grazing angles (a stable per-texel discard), so the cotton has no hard outline.

Rebuild and inspect (Blender 4.2, Godot 4.7.2):

```powershell
blender -b --factory-startup -P tools/blender/beetle_build.py               # ~50 s
blender -b --factory-startup -P tools/blender/beetle_build.py -- --preview=C:/tmp/beetle.png   # shape only, ~1 s
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=t_beetle --out=res://art/beetle --frames=32
godot --path . --script tools/art/render_unit.gd -- --unit=beetle --out=res://art/beetle --frames=40   # the infection clip
godot --path . --script tools/art/ingame_unit.gd -- --unit=t_beetle --faction=2 --out=res://art/beetle
godot --path . --script tools/art/perf_unit.gd -- --unit=t_beetle
```

`walk.gif`, `attack.gif` and `infect.gif` are built from the ignored `frames_*` directories with ffmpeg.
