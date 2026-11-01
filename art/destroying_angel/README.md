# Destroying Angel — first rigged 3D asset pass

A self-contained Godot review project and three portable, skinned GLB assets.
The design uses exactly two legs, a flat fungal torso, an asymmetric ivory hood,
forearm blades and three mantle plates. This is a procedural interpretation of
the approved concept, not a finished sculpt matching all of its surface detail.

## Open and inspect

Open `project.godot` in Godot 4.7.2, allow imports to finish, then press F6 on
`review.tscn` or run the project normally. No Python dependencies are needed to
use the assets or the Godot preview.

- W: toggle the stalking walk.
- A: play the blade-lunge attack.
- S: toggle the test "spotted" input.
- L: switch close, battle and distant models.
- P: pause the animation.
- Left drag / wheel: orbit and zoom.

The character auto-cloaks while unspotted and not attacking. Spotting or attacking
switches to its solid ivory material. After the attack ends, it cloaks again if
still unspotted. S simulates detection for review; the actual RTS must supply its
visibility/detection result through `set_spotted()`.

## Assets and animation

`assets/destroying_angel.glb`, `destroying_angel_battle.glb` and
`destroying_angel_distant.glb` each contain one skinned mesh primitive, one shared
PBR material, two embedded images, 13 joints, and three real animation clips:

| Clip | Duration | Purpose |
|---|---:|---|
| Idle | 2.4 s | Subtle upper-stalk and hood movement |
| Walk | 1.2 s | Alternating two-leg stalking cycle |
| Attack | 0.95 s | Windup, forward blade lunge and recovery |

Idle/Walk have matching endpoint poses; the review sets them to loop. Attack is
one-shot. The attack's forward displacement returns to its start, so game movement
should remain controlled by the simulation. `assets/stats_*.json` contains the
measured triangle and vertex counts for each level. All levels retain the same
joint names and animations.

The GLBs' revealed materials and animations are portable. Blue transparency and
rim emission are supplied separately by `scripts/cloak.gdshader` in Godot; that
effect is not embedded as a portable glTF material. The review swaps material
only when state changes. Revealed rendering uses the opaque material; cloaking
uses an alpha blend with a depth prepass. There are no attached lights or cloud
particle effects. Texture maps are 512 x 512.

## Connect to gameplay

The review root provides these hooks, which can be moved into your unit visual
controller:

```gdscript
angel.set_spotted(enemy_can_see_this_unit)
angel.set_walking(unit_speed > 0.0)
angel.attack()  # returns false if already attacking
angel.attack_impact.connect(on_melee_contact)
```

`attack_impact` fires once per attack at 43% of the clip. The visual code does not
apply damage, decide targets or implement enemy fog visibility. It demonstrates
material visibility for the local player; an enemy renderer must hide genuinely
undetected units according to the game's rules. No changes have been made to the
original game's combat data, training queues or source checkout.

## Source and checks

`tools/build_angel.py` regenerates the meshes, skeleton, skin and animation data.
It needs Python with numpy and Pillow. Run it with 0, 1 or 2 for the three LODs.
The exported assets do not depend on those packages at runtime.

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tools/check_asset.gd
godot --path . -- --capture
```

The checks load all three GLBs in Godot and verify one mesh/material surface,
13 bones, normalized skin weights, finite positions, decreasing geometry counts,
three animation tracks, cloak activation, spotted reveal, attack reveal and
re-cloaking. Preview PNGs/GIFs are actual Godot Compatibility renders, produced
using Mesa software rendering. Target-GPU frame time, crowd performance, combat
contact alignment and final art polish still need work in the actual game.
