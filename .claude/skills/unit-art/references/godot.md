# Bringing a Blender-built unit into the game (Godot 4.7.2, GDScript)

Working examples to copy:
- **Loader:** `scripts/muscarine_spitter.gd` (simple), `scripts/whitecoat_beetle.gd` (two forms
  from one mesh).
- **Shader:** `shaders/muscarine_spitter.gdshader`, `shaders/whitecoat_beetle.gdshader`.

## 1. Import

```
godot --headless --path . --editor --import --quit
```

The first import of a new PNG comes out **uncompressed and without mipmaps**, because Godot hasn't
yet seen it used in 3D. Fix every `art/<unit>/*_{albedo,normal,orm}.png.import`:

```
compress/mode=2
mipmaps/generate=true
detect_3d/compress_to=0
compress/normal_map=1        # the normal map only
```

Then import again and diff the settings against `art/spitter/spitter_*.png.import` (everything
except uid and paths should match).

## 2. The loader script (`scripts/<unit>.gd`)

It must provide these members, which `game.gd` relies on:
- `mesh(lod)`: an ArrayMesh with the material set and `custom_aabb` grown by the motion's reach
  (otherwise animated parts get culled).
- `stats(lod)` and `choose_lod(pixels, current)` (with hysteresis; copy the Spitter's).
- The constants `LOD_SIZE`, `HEIGHT` and `SWING_SECONDS`.
- `WINDUP_SECONDS` (= impact fraction x `SWING_SECONDS`) if it has a windup, and `MUZZLE` if it
  shoots.

Rebuild the mesh with `add_surface_from_arrays(..., mi.mesh.surface_get_arrays(0))` and set **one
static ShaderMaterial** shared by all LODs and instances. Per-unit state goes in instance uniforms.

## 3. The shader

Start from one of the examples. Conventions:

```glsl
instance uniform float flash, wither, growing, walk, gait, motion_time = -1.0, strike;
instance uniform vec4 team;   // team.a = how much faction rim tint (0 insects, 0.18 thralls, 0.45 units)
float kind = floor(UV2.x + 0.001);
float w = clamp((UV2.x - kind) / 0.98, 0.0, 1.0);
float group = floor(1.0 - UV2.y + 0.002);   // glTF flips v
float clock = motion_time >= 0.0 ? motion_time : TIME;   // the game clock: pause freezes it
```

**Motion without a skeleton:**
- **Legs:** swing rigidly about each hip (store hip positions as const arrays printed by the build
  script). Lift on the forward swing, `max(cos(phase), 0)`. Tripods or diagonal pairs alternate by
  group.
- **Body:** bob at twice the stride frequency and roll a little. Blend the body motion into legs by
  `1 - planted` so the feet stay put.
- **Stalks and stems:** bend by height with a lag that grows up the stem (the Spitter), so the top
  wobbles behind the base.
- **Rotations:** rotate `NORMAL`, `TANGENT` and `BINORMAL` with every rotation of `VERTEX`, or the
  normal map lights the wrong side.

**The attack:**
- `strike` goes 1 -> 0 over `SWING_SECONDS` (`game.gd` decays it). Use `t = 1 - strike`.
- Shape it as anticipation, then a fast action at `IMPACT`, then follow-through and settle (a shiver,
  `sin(after * 40) * exp(-after * 8)`).
- **Anticipation must read from above:** rear up, coil back, raise the arms.
- **Match the impact to `Data` `windup` = IMPACT x SWING_SECONDS,** and add a test for it.

**Fragment:**
- **Surface:** albedo, `NORMAL_MAP`, `ROUGHNESS = orm.g`, `AO = orm.r`, `AO_LIGHT_AFFECT` about 0.4.
- **Faction:** the team rim mix, `col = mix(col, team.rgb, rim * team.a * 0.22)`.
- **States:** wither greying, growing darkening, and the flash emission. Copy them exactly from an
  example.
- **Optional extras:** `BACKLIGHT` for translucent flesh, `CLEARCOAT` for lacquered chitin, emission
  from an ORM mask.
- **Use `discard` only for small, fresnel-gated soft edges.**

## 4. Wiring

**`scripts/game.gd`:**
- `const X = preload("res://scripts/<unit>.gd")`, and add `"<unit id>": X` to `BAKED`. `BAKED` units
  get LOD switching, `motion_time` and the strike decay in `_update_visuals`.
- **Spawning:** in `_spawn_unit`, the `match uid:` sets the mesh, and the `elif uid == ...` chain
  sets `gait` (radians per second of stride; insects about 12-19, big units 4-7). Set any other
  instance uniforms there.
- **The strike:** for a melee unit with a windup, add its id to the list in `_fire` that sets
  `src.strike = 1.0` when the swing starts. Ranged units with a windup get it automatically.
- **Hit effects:** per-unit effects go in `_melee_hit` (`_burst(...)` only when `src.node.visible`).

**`scripts/fungus_lib.gd`:** in `mesh(id)`, return the loader's `mesh(0)` for the species id and set
`_heights[id]`. Portraits and the showcase use this.

**`scripts/data.gd`:** add `"windup"` if there is one. Keep gameplay numbers unchanged unless asked,
and say so if a windup changes when blows land.

## 5. Tools and tests

- **Tools:** add the unit to `UNITS` in `tools/art/render_unit.gd` (title, subtitle, team colour) and
  to its gait and swing-time choices, and to `ART` in `tools/art/perf_unit.gd`.
- **Tests:** in `tools/tests/court_units.gd`, check that:
  - matches and portraits use the new mesh;
  - the LODs decrease;
  - `strike` starts on `_fire` and the damage waits for the windup;
  - `windup` equals the shader's impact frame;
  - any special state works.

  Units in fog skip visual updates, so reveal the spot first (`g.fog.reveal(0, pos, 6.0, 60.0);
  g.fog.update()`).
- **Perf:** `perf_unit.gd` interleaves variants over rounds because laptop GPU clocks drift. Use
  `--rounds=16` for a number you can trust.

## 6. Known noise (not your bug)

- `ingame_unit.gd` prints `Can't add child ... already has a parent`.
- A headless `--sim` leaks 31 ObjectDB instances at exit.

Both happen without any new unit.
