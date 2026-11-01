# Wartling: second art pass

A rebuilt procedural prototype of the Amanita Court's poison infantry. The first
pass constrained the battle mesh to 760 triangles before resolving the design.
This pass prioritizes the fungal silhouette and materials, then reduces geometry
at distance. It is still a procedural interpretation: it does not reproduce the
concept sheet's sculpted surface finish.

The new model has an uneven tilted scarlet cap, scattered flattened ivory veil
fragments, a pale bulbous stalk, real radial gill blades, and six curved root legs
with swollen knees and branching toes. Shared surface and normal maps add skin
grain and mottling. The shader animates a forward alternating-tripod step.
Combat stats and collision radius are unchanged.

## Geometry and material cost

| Level | Triangles | Indexed vertices | Surfaces |
|---|---:|---:|---:|
| Close | 7,636 | 11,084 | 1 |
| Battle | 3,086 | 4,700 | 1 |
| Distant | 565 | 693 | 1 |

All instances and levels share one opaque material and two 256 x 256 RGBA8 maps,
including mipmaps (about 683 KiB combined before renderer-specific allocation).
The maps bake once on the CPU when the shared material is first requested.
The fragment shader samples both maps; it does not evaluate procedural noise.
Paint and gait weights are vertex data. The six roots, gills and veil fragments
are in one indexed mesh, with no attached lights, alpha blending, individual leg
nodes, CPU skinning, or per-frame mesh regeneration.

The close view deliberately spends more geometry than the first pass. It retains
forked toes, 48 gill blades, 64 primary veil fragments and smaller chips. Battle
retains six forked roots, 24 blades and 42 primary fragments. Distant retains the
cap, stalk, six tapered roots and 13 white landmarks; its underside uses a simple
surface. This is an art allocation, not a measured frame-rate improvement.

## Game integration

- `scripts/wartling.gd` owns deterministic cached meshes, maps and material.
- `scripts/fungus_lib.gd` supplies the close mesh to portraits and catalogs.
- `scripts/game.gd` starts at battle detail and checks projected cap width every
  0.2 game seconds. Close detail enters above 90 pixels and leaves below 75.
  Distant enters below 18 pixels and leaves above 24. Hysteresis limits flicker.
- `shaders/wartling.gdshader` supports the game's hit flash, withering, growth and
  team parameters. Game time drives the gait so pause freezes it. UV2 encodes
  surface kind and tripod phase; vertex alpha is deformation weight.
- Random generators are local and do not consume gameplay randomness.

## Review and asset files

- `wartling_hero.png`: actual Godot close-up of the close mesh.
- `wartling_lods.png`: actual engine comparison, enlarged equally for inspection.
  The distant model is intended for less than 18 pixels of cap width.
- `wartling_walk.gif`: actual engine shader animation.
- `wartling_ingame.png`: actual game scene with the new unit. Compatibility mode
  omits the world's Forward+-only effects.
- Three `.res` files: native meshes with their shared maps embedded, referring
  to `res://shaders/wartling.gdshader`.
- Three `.glb` files: portable static vertex-colored meshes with embedded normal
  maps. Their standard material approximates the Godot shader. Shader gait,
  poison emission, surface variation and hit/team effects remain Godot-only.

The game builds cached meshes from source; it does not need the exported meshes
or review images to run.

## Reproduce and validate

Use Godot 4.7.2 from the repository root:

```sh
godot --headless --path . --script tools/wartling/check_wartling.gd
godot --path . --script tools/wartling/render_wartling.gd -- --out=art/wartling --frames=16
ffmpeg -y -framerate 25 -i art/wartling/frames/%03d.png -filter_complex '[0:v]split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a' -loop 0 art/wartling/wartling_walk.gif
```

Verified with the matching Linux engine: indexed mesh budgets, cache reuse,
shared material, finite positions/normals/tangents, normalized normals, valid
clockwise winding, nondegenerate faces, shader-motion bounds, mipmapped texture
sizes, decreasing LOD counts and LOD hysteresis. The project imports, the shader
compiles and renders, and an all-faction five-second headless match completes.
GLB containers have matching counts, one primitive and an embedded normal map.

Screenshots and animation use Compatibility mode with Mesa software rendering.
The in-game capture runs the visual and LOD integration without script or shader
errors. Target-hardware Forward+ frame time and large-army performance still
need measurement with the repository's `--fpstest` workflow.

The next quality step is an authored sculpt and baked surface details, preserving
this unit's silhouette and the shared-material/LOD integration. Increasing the
procedural mesh count further is unlikely to close that remaining finish gap.
