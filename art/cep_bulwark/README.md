# Cep Bulwark — art and animation prototype

A Boletus-inspired heavy protector for the Amanita Court. A broad, uneven
chestnut cap overhangs a yellow pore sponge and reticulate cream stalk. Four
short, flared limbs end in blunt toe pads. Their planted stance and staggered
four-beat crawl give this unit a heavier movement language than the Wartling.

Bracing now buries the limbs, leaving the cap exposed. The review scene also
demonstrates projectile capture and reduced damage. The unit is still a proposed
roster addition: this change supplies the asset and review scene, without adding
combat statistics, training queues or a damage-blocking ability.

## Inspect it

Open `scenes/art_review/cep_bulwark.tscn` in Godot 4.7.2 and press F6, or run:

```sh
godot --path . scenes/art_review/cep_bulwark.tscn
```

| Control | Action |
|---|---|
| Space | Toggle idle / walk |
| A / B / M / V | Bash / brace / move / incoming shots |
| L | Cycle close, battle, distant mesh |
| C | Toggle Wartling at the same world scale |
| Drag left mouse | Orbit |
| Wheel | Zoom |
| R | Switch low / RTS camera angle |
| P | Pause the animation and transitions |

The review scene uses the actual shared unit meshes and shaders. Rendering with
`--rendering-method gl_compatibility` is supported on systems without Vulkan.

## Geometry and material cost

| Level | Triangles | Indexed vertices | Surfaces |
|---|---:|---:|---:|
| Close | 8,672 | 5,486 | 1 |
| Battle | 2,896 | 2,081 | 1 |
| Distant | 668 | 560 | 1 |

All three levels and every instance share one opaque material and two mipmapped
512 x 512 RGBA8 atlases (about 2.67 MiB combined before renderer allocation).
One atlas stores color; the other packs tangent-space normals and roughness.
The four padded regions have separate chestnut cuticle, netted stalk, pore sponge
and foot skin details. Surface patterns bake once on the CPU when the material is
first requested. The fragment shader samples two textures and evaluates no noise.

Geometry is cached. The four limbs are part of the indexed mesh, with no limb
nodes, skeletal rig, CPU skinning, per-frame mesh rebuilds, transparency or lights.
Vertex alpha holds foot flex or the cap's pale edge mask, selected by surface
kind. UV2 stores surface kind and the four distinct crawl phases.

Close and battle detail retain twelve rounded toe pads. Distant detail retains
four flared feet and the cap/body silhouette. The asset's LOD helper uses
projected cap width: close enters above 100 pixels and leaves below 80; distant
enters below 22 and leaves above 28. The review scene allows manual inspection.
The future RTS unit must call this helper when its runtime integration is added.

## Integration and exports

- `scripts/cep_bulwark.gd`: cached meshes, atlases, material and LOD helper.
- `shaders/cep_bulwark.gdshader`: heavy walk, brace, team tint, hit flash,
  growth and withering. Supply game time through `motion_time` to support pause.
- `FungusLib.mesh("u_cep_bulwark")`: registered close mesh and height metadata.
- Three `.res` files: native meshes with embedded atlases, referencing the Cep
  shader at its normal project path.
- Three `.glb` files: self-contained static meshes with embedded color and normal
  maps. Their standard material approximates the shader; cap-edge blending,
  surface-specific roughness, animation and instance effects remain Godot-only.
- `cep_bulwark_hero.png`, `cep_bulwark_lods.png`, `cep_bulwark_poses.png`,
  `cep_bulwark_walk.gif`: actual Godot renders.
- `cep_bulwark_review.png`: the interactive review scene with the Wartling for
  scale and silhouette comparison.

The source generator does not depend on the exported meshes or preview images.
The review scene's comparator uses the previously implemented Wartling source.

## Validation and reproduction

```sh
godot --headless --path . --script tools/cep_bulwark/check_cep_bulwark.gd
godot --path . --script tools/cep_bulwark/render_cep_bulwark.gd -- --out=art/cep_bulwark --frames=24
godot --headless --path . --script tools/cep_bulwark/check_cep_bulwark.gd -- --exports
ffmpeg -y -framerate 18 -i art/cep_bulwark/frames/%03d.png -filter_complex '[0:v]split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a' -loop 0 art/cep_bulwark/cep_bulwark_walk.gif
```

Checked with the matching Godot 4.7.2 engine: finite positions, normals, tangents
and UVs; normalized normals; clockwise winding; nondegenerate triangles; valid
atlas coordinates and alpha weights; four distinct leg phases; indexed reuse;
shared mesh/material caches; decreasing LOD counts; animated bounds; texture sizes
and mipmaps; mesh-registry identity and LOD hysteresis. Native exports reload with
their embedded maps. Portable GLBs have matching counts and embedded images.

The shader, idle/walk/brace states and review scene render in Compatibility mode
using Mesa software rendering. The existing Wartling checks and a five-second
all-faction simulation also pass. Target-hardware Forward+ frame time and
large-army performance remain unmeasured. This is a procedural art pass; an
authored sculpt and baked detail can refine the remaining surface finish.

## Cap bash and rooted capture update

The action review now includes a complete cap-bash windup, impact and recovery,
and a one-second rooting animation. Roots sink 0.85 world units below the floor,
leaving the chestnut cap exposed. Bracing ends with a 0.85-second uproot.
The expanded native mesh bounds account for burial and the forward attack.

`cep_actions.gd` supplies the reusable state controller. A bash emits one impact
signal at 43% of its 1.1-second cycle. Attacks are locked while rooting, braced or
uprooting. Move orders leave brace, finish uprooting, then enter walk. The default
RTS design is automatic melee attacks through normal attack orders, plus a
Brace/Uproot toggle on the selected unit's command card. The animation follows
state rather than requiring the player to select animation clips.

The interactive scene demonstrates this with clickable buttons and shortcuts:
A = test bash, B = brace/uproot, M = move, V = toggle incoming test shots.
Space toggles walk; the previous camera/LOD/comparison/pause controls remain.

`cep_action_demo.gd` is a projectile fixture, separate from the RTS match's
projectile manager. While fully braced, its radius-three circle captures incoming
hostile direct projectiles, bends their paths into the cap, and applies 25% of
incoming damage exactly once. Capture switches off as soon as uprooting starts;
a shot already captured finishes its committed path and reduced hit. Friendly
shots should be excluded by a combat caller. Overlapping Cep fields and other
attack categories need explicit policy during future match integration.

The demo uses a swept segment/circle query, so fast shots crossing the whole
area in one frame can be captured. The shot visuals share mesh/material data;
curved trails and soil clods use MultiMesh batches. The unit itself retains its
one opaque material and original triangle counts. The area indicator is shown
for review; a match should generally show range rings only for selected units.

New actual-engine deliverables:

- `cep_bulwark_bash.gif`: cap bash against a target dummy.
- `cep_bulwark_brace.gif`: sink, capture four shots, then uproot.
- `cep_bulwark_braced.png`: buried shield pose with capture area.
- `cep_bulwark_action_review.png`: the interactive command buttons and counters.

Run the controller checks and render both sequences:

```sh
godot --headless --path . --script tools/cep_bulwark/check_cep_actions.gd
godot --path . --script tools/cep_bulwark/render_cep_actions.gd
```

The fixture asserts four 100-damage shots produce four 25-damage hits and zero
escaped damage. Controller checks cover one impact per attack, attack locking,
root activation timing, the damage multiplier, move-after-uproot and swept
intersection including outside-to-outside crossings. This update remains a
review prototype, rather than a trainable unit in the RTS match.
