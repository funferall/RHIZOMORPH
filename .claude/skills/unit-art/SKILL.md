---
name: unit-art
description: Use when creating, rebuilding or improving any 3D art in RHIZOMORPH (the Godot fungal RTS) - a unit, thrall, insect, hero, building, Heart or prop, usually from a concept sheet in reference_images/ - or when a unit "looks flat", "looks cheap", "doesn't match the concept", or needs walk/attack animation. Covers the headless-Blender pipeline (parametric sculpt, Cycles bake to normal + AO, painted atlas, three LODs, one surface), the Godot loader and shader, integration, and the verification loop. Not for UI, sound or gameplay balance.
---

# Unit art for RHIZOMORPH: beautiful and cheap

Every unit is written as a Python script that drives Blender headless and exports GLBs and a texture
atlas, plus a GDScript loader and a shader that animates it. The quality bar is
`tools/blender/beetle_build.py` (Whitecoat Bulwark) and `tools/blender/spitter_build.py`. Read the
beetle build before writing a new one. Runner, Slinger, Bomber, Sniper and Inkcap Bed were built
without this method and fail or warn in `tools/art/atlas_lint.py`. Do not copy them.

**The core idea.** Triangles buy the silhouette; textures buy the surface. Detail lives in a baked
normal map, an AO map and a painted albedo, not in geometry. A unit is about 100 px tall on screen,
so sub-pixel triangles are wasted work. One baked texture lookup gives honeycomb, pores and fibres
for free. Keep one surface (one draw call) per unit, and avoid transparency, which causes overdraw.

## The method in one paragraph

Every surface is a **parametric function** (a, t) -> position, evaluated on numpy arrays. The
**relief** (pits, ridges, seams, fibres) and the **paint** (stripes, spots, bands, dust) are
functions of the **same parameters or the same 3D positions**, so the baked normals and the colours
line up. A dense version with relief (around 0.5-1M faces) is baked by Cycles onto smooth bake
targets that share the game meshes' UVs. The game meshes are the same functions at low resolution.
Never paint in atlas pixel coordinates with per-texel random noise. That makes TV static that
follows no form, and it is exactly why the weak units look cheap.

## Tools you have

| file | what |
|---|---|
| `tools/blender/paintlib.py` | `vnoise`/`fbm`/`pnoise` (smooth noise sized in metres), `cells` (Voronoi f1/f2/id: pits, spots, nets, honeycomb, cracks), `smooth`, `mix`, `ramp` (hue-shifting colour ramps), `Acc` (fast numpy mesh builder), `surface` (closed parametric surface), `sweep` (tube along a path), `ellipsoid`, `tube_points` (paint a tube in 3D), `texel_grid`, `bake_atlas`, `preview_render`, `tri_count` |
| `tools/blender/unitlib.py` | `setup_cycles`, `bake`, `hide_from_rays`, `save_png`, `export_glb`, `log`, `frames_along` |
| `template_build.py` (next to this file) | a complete, runnable build (about 200 lines) that passes the lint. Copy it to `tools/blender/<unit>_build.py` and replace the example |
| `tools/art/atlas_lint.py` | quality gate for the atlas: `python tools/art/atlas_lint.py art/<unit>/<unit>` must show **0 FAIL** |
| `tools/art/render_unit.gd`, `ingame_unit.gd`, `perf_unit.gd` | studio renders and frames, in-match captures, frame-time cost |
| `tools/tests/court_units.gd` | integration tests; add checks for every new unit |

Executables: Blender `"/c/Program Files/Blender Foundation/Blender 4.2/blender.exe"`, Godot
`../USNEA/engine/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe` (from the repo root).

## Workflow, with gates. Do not skip a gate.

1. **Study the reference.** Open the concept sheet and look at the unit. Identify the real organism
   (the sheets name host x fungus pairs) and use its true anatomy and colours. Write the brief at
   the top of the build docstring, listing what must read at each scale:
   - **Silhouette** (what reads at 60 px): proportions, the body masses, the poses of the limbs.
   - **Mid scale**: bands, stripes, spots, segments, joints, seams, the colour zones.
   - **Fine scale**: pits, pores, fibres, setae, cracks, powder.
   - **Material**: what is glossy or wet, dry or matte, translucent, glowing.

2. **Plan before coding.**
   - **Parts:** list them, each a `surface` / `sweep` / `ellipsoid` with its own atlas rect. Give the
     most visible part the most texels. Symmetric repeats share one rect (all legs share one).
   - **Data UV:** u = kind + 0.98 * weight, v = group. Plan these for animation. Anything that moves
     differently gets its own kind or group (legs by index, head, cap, mandibles, removable layers
     such as the beetle's infection tufts).
   - **Budget:** see the table below.

3. **Shape loop.** Write the low-poly functions first. Run `--preview` (Workbench, about 1 s) and
   look at all three views next to the concept. Iterate until the silhouette matches, and note what
   you changed and why. These mistakes happened on earlier units:
   - **Hidden joints:** legs read as stilts when the femur and knee hide under the body. Push the
     knees out past the body's margin.
   - **Blocks:** superellipse exponents below about 0.8 make parts look like boxes.
   - **Timid features:** the signature feature (tufts, a cap, mandibles) is too small. Exaggerate it.
     This is a game, read from above.
   - **Seam on top:** the UV seam must sit where nobody looks (put a = -pi underneath or at the back).

4. **Sculpt and bake.** Add relief functions (sculpt only) and size every feature in metres, never
   in texels. Bake with `bake_atlas`, then **look at the normal and ORM PNGs**:
   - Colourful blobs at tight bends mean the ray reach is too long. Shorten the part's `reach`.
   - Lopsided AO means an occluder is missing. Give `ao_from` every nearby part (all legs, not one).
   - Noise at lathe poles: set `poles`.

5. **Paint.** Follow `references/painting.md`. Paint every part by evaluating its own surface
   function on `texel_grid` (u, v) and working in 3D.
   - **Gate:** `atlas_lint` shows 0 FAIL.
   - **Read the NOTEs:** hue variation is advisory but usually worth acting on.

6. **Godot.** Follow `references/godot.md`. You need:
   - a loader script, a shader and the import settings;
   - wiring in `game.gd`, `fungus_lib.gd` and `data.gd`;
   - the walk and attack motion in the shader, driven by the game clock and `strike`;
   - a `windup` that lands the blow on the animation's impact frame.

7. **Verify and critique, at least two rounds.**
   - **Studio:** `render_unit.gd` gives the hero, detail and LOD sheet, plus walk and attack frames.
     Tile them into a contact sheet with ffmpeg and look at every frame.
   - **In a match:** `ingame_unit.gd`.
   - **Critique:** put the hero render next to the concept and write down the **three biggest
     differences**, then fix them and re-render. Stop only when the remaining differences are ones
     the camera distance throws away.
   - **Gates:** `perf_unit.gd` (60 units at battle LOD should add under about 0.5 ms; compare with
     the old model) and `court_units.gd` (0 failures).

8. **Document and commit** only your files. Other sessions work in this repo at the same time, so
   stage your own hunks. Write `art/<unit>/README.md` (what it is, triangle counts, motion, rebuild
   commands), add a ROADMAP entry and a `.gitignore` line for `art/<unit>/frames_*/`, and commit the
   GIFs.

## Budgets (one opaque surface, one 1024 atlas)

| | close | battle | distant |
|---|---|---|---|
| common unit, thrall, insect | <= 10k | <= 2.5-4k | <= 1.2k |
| elite or hero | <= 16k | <= 6k | <= 2k |
| building | one mesh, <= 20k, no LODs needed if it is static and large |

- **Resolution goes where the silhouette needs it:** the round profiles of big masses and the joints
  of limbs. Flat-ish regions need few rows.
- **Thin parts:** antennae, claws and hairs at distant LOD can drop to 3 sides or be dropped
  entirely.
- **No alpha-blended layers on units.** For a soft edge (cotton, fur, slime), use the beetle's
  fresnel-gated, stable per-texel `discard` in the same surface.
- **Textures:** albedo sRGB; normal non-colour with `compress/normal_map=1`; ORM non-colour (R
  occlusion, G roughness, B a mask such as glow, dust or wetness). All are VRAM-compressed with
  mipmaps (copy a spitter `.import` file's settings).

## Hard rules

- No `rng.random(...)` per texel in an albedo or a height. Noise is always `vnoise`/`fbm`/`cells`,
  scaled so one feature has a real-world size.
- No normal maps made from `np.gradient(noise)` in atlas space. Normals come from a baked sculpt.
- Every atlas needs a baked AO and a roughness map with real variation (wet vs dry, gloss vs dust).
- Patterns follow anatomy: stripes run along the body's own coordinates, so they converge where the
  body tapers. Spots are round in 3D (use distance in 3D, not in (a, t)). Bands follow segments.
- A colour change is also a hue change. Use `ramp`, with warm lights and cooler or more saturated
  darks, never a plain lerp between two greys.
- Use the game clock (`motion_time`), never `TIME`, for anything gameplay can pause.
- Never commit other sessions' changes. Never leave the build only half-verified. If you skip a gate,
  say so.

## When the procedural FungusLib path is fine

`scripts/fungus_lib.gd` lathes with flat material colours are for small, repeated decor (buttons,
pebbles, background clusters). Anything the player selects or looks at often should use this
pipeline instead: units, insects, thralls, faction buildings, Hearts and resource sites.
