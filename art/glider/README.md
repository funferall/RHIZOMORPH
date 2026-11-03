# Splitgill Glider (Morel Hollow, flying spore bomber)

From the Morel Hollow combat roster sheet: two fans of *Schizophyllum commune*, the split-gill,
spread as wings from a pale, pored morel body, with a ragged rust streamer for a tail and a
clutch of dark earthball (*Scleroderma*) spore bombs slung underneath. **Art only for now:** it
is not yet in `data.gd`, so no building trains it. The catalog shows it as an "art preview"
plate.

This is the first unit whose motion was **generated rather than hand-written**, by
[UniMate](https://github.com/Friedrich-M/UniMate) (text-to-motion for any skeleton).

- **Build:** `tools/blender/glider_build.py`.
  - Each fan is a closed parametric slab: a trumpet narrow at the root, flaring to a lobed,
    ruffled, in-rolled margin, and concave on top like a half funnel.
  - Underneath, the gills radiate from the root, and each blade has a groove down its edge: the
    split gill.
  - On top, a rust crust breaks into patches inward behind a cream lip, over radial ribs and
    growth zones.
  - The body is a spindle punched with round pores.
- **Triangles:** close 7,760, battle 2,080, distant 692. One surface and one 1024 atlas (albedo,
  normal, ORM: occlusion, roughness, glow on the bombs' gold flecks).
- **Atlas:** the wings get the top 55%. Lint: 0 fail, 0 warn. The hue-variation NOTE is
  advisory: the palette is cream, rust and umber on purpose.

## Motion: UniMate clips baked into a bone texture

Nothing in the scene is skinned and there is no Skeleton3D. The shader skins on the GPU:

1. `glider_build.py --rig=<path>.glb` writes the close mesh skinned to a 14-bone, bird-named rig
   (`Bip01_Pelvis/Spine/Spine1/Neck/Head`, `BN_Tai_01..03`, `BN_Wing_L/R_01..03`), plus
   `rig/rig.json`.
   - The skin weights come from the data UV: the body blends along x, and a wing or the streamer
     blends along its distance from the root.
   - The shader uses the same rule, so the GLBs need no weights.
2. UniMate's `rig_preprocess` makes the conditioning (`rig/cond.npy`; the labels in
   `rig/annotation.json` all came out right offline, with no LLM). Its sampler then generated
   clips from text prompts.
3. `tools/unimate/glider_motion.py` decodes the chosen clips and runs FK.
   - It maps them back from UniMate's canonical frame. The rest-joint fit error is about 0 m.
   - It removes travel and turning, cuts the loops where the pose returns, and cross-fades the
     seam.
   - It writes `glider_bones.tres`, an RGBAF texture: one row a frame, and two texels per bone
     (the rotation quaternion and the translation).
   - It also writes `shaders/splitgill_glider_motion.gdshaderinc`: the clip table, the chains and
     the release.

| clip | prompt | sample | use |
|---|---|---|---|
| glide | "An object flaps its wings." | rep 1, loop [15, 55), 40 frames, amp 0.6 | hovering |
| fly | "An object glides with its wings spread." | rep 1, one beat, 18 frames, amp 0.5 | flying: one beat per stride (`gait`) |
| run | "An object dives forward and pulls up." | rep 1, 60 frames, amp 0.7 | the bomb run on `strike` |

The prompts don't map literally. "Glides" gave the cleanest steady wingbeat, and "flaps its
wings" gave the slow lazy beat. `amp` scales each joint's generated rotation toward rest: the raw
clips swing the wings about ±90°, too wild from the RTS camera.

**Bomb run** (`strike`, `SWING_SECONDS` 1.2):
- It climbs with its wings raised in a V, then drops into the dive.
- At `RELEASE` = 0.593 (the dive's fastest drop) the bombs let go, glowing. They fall whole for
  0.32 s and vanish, and new ones swell at the cords' ends as it pulls up.
- `WINDUP_SECONDS` = 0.71184 = RELEASE x SWING_SECONDS, checked in `court_units.gd`.

Shader cost: two bones a vertex and two clips blended (three during a run). Each blend is up to
two texel fetches per frame pair, which is cheap at these vertex counts.

## Rebuild

```
B="/c/Program Files/Blender Foundation/Blender 4.2/blender.exe"
$B -b --factory-startup -P tools/blender/glider_build.py -- --preview=C:/tmp/gl.png   # shape
$B -b --factory-startup -P tools/blender/glider_build.py                              # bake, ~45 s
python tools/art/atlas_lint.py art/glider/glider

# motion: the three chosen samples are kept in art/glider/motion/, so re-baking needs only UniMate's code
cd ../_ext/UniMate   # a UniMate checkout with its conda env (python 3.10, torch cu124, bpy 4.0)
python <repo>/tools/unimate/glider_motion.py --rhizo=<repo> --cond=<repo>/art/glider/rig/cond.npy \
  --glide=<repo>/art/glider/motion/glider-an_object_flaps_its_wings-rep_1-0.npy \
  --fly=<repo>/art/glider/motion/glider-an_object_glides_with_its_wings_spread-rep_1-1.npy \
  --run=<repo>/art/glider/motion/glider-an_object_dives_forward_and_pulls_up-rep_1-4.npy --amp=0.6,0.5,0.7

# new clips: rebuild the rig asset, then sample
$B -b --factory-startup -P tools/blender/glider_build.py -- --rig=work/glider/glider_rig.glb
python -m data_process.rig_preprocess run --input work/glider/glider_rig.glb --output_dir outputs/rig/glider \
  --profile general --name glider --annotation <repo>/art/glider/rig/annotation.json
python -m unimate.inference.sample --exp_dir outputs/unimate_uniml3d_f60_v3 --asset outputs/rig/glider \
  --prompt "An object flaps its wings." --num_repetitions 3 --output_dir outputs/samples/glider
python <repo>/tools/unimate/glider_motion.py --rhizo=<repo> --samples outputs/samples/glider/motions --report

$G --path . --script tools/art/render_unit.gd -- --unit=glider --frames=24
$G --path . --script tools/art/perf_unit.gd -- --unit=glider --rounds=16   # spawns Bombers wearing this mesh
```

If you change the mesh's shape or the bones, rebuild the rig and re-run `rig_preprocess`, then
re-bake. The clips are stored as rotations, so they still fit a re-sculpt that keeps the bones.

## Licence note

UniMate's code is MIT, but its released checkpoints are **CC BY-NC 4.0**. Whether motion
generated with them may ship in a commercial game is a question to settle before release.

## Not done yet

- **In a match:** wiring into `data.gd` and `game.gd` (a unit id, a trainer, `flies`, stats, the
  bomb drop as a shot with splash), plus an `ingame_unit.gd` capture once it can spawn.
- **Art:** the concept's rust crust is thicker and more crumbly, and its body twists more.
