# Painting an atlas that looks alive

The albedo is where most units are won or lost. A rich atlas has **structure at three scales**,
**hue that moves**, **dark accents and pale highlights**, and **patterns that obey the body**.
`tools/art/atlas_lint.py` measures some of this, but your eyes are the real gate. Check the PNG
and the hero render.

## 1. Paint in 3D, with the same functions as the sculpt

```python
sl, u, v = texel_grid(RECTS["shell"], SIZE)        # every texel of the rect, as the mesh maps it
a = u * TAU - PI                                    # the same (a, t) the surface used
P, s = shell_point(a, v)                            # 3D positions of those texels
albedo[sl] = ...                                    # any function of a, v and P
orm[sl + (1,)] = ...                                # roughness
```

- For tubes, `P = tube_points(PATH, RADII, u, v, radius_fn)` puts each texel exactly where the sculpt
  put its relief.
- Reuse the relief's own mask functions in the paint (`stripe_mask`, `pronotum_mask`, the `cells`
  calls with the same size and seed). Then a pit is dark exactly where the bake made it a pit.

## 2. Three scales of structure

| scale | size on the unit | what it is | tools |
|---|---|---|---|
| large | 10-50 cm | colour zones: top vs belly, cap vs gills, gradients along the body, mottling | `ramp` over t or a, `pnoise(P, 2-5, 3)` |
| mid | 1-10 cm | the species' pattern: stripes, spots, bands, segment rings, nets, honeycomb, cracks | analytic masks, `cells` f1 (spots, pits), f2 - f1 (nets, cracks, honeycomb) |
| fine | 1-10 mm | speckle, fibres, pores, powder | `pnoise(P, 30-120)`, small `cells` |

**Most weak atlases have only large and fine** (a gradient plus static). Mid scale is what makes a
unit read as a specific creature. Give each mid-scale feature a crisp edge (`smooth` over a few mm),
with a little noise warping the edge so it isn't vector-art perfect:

```python
wob = 0.15 * pnoise(P, 90.0)                       # edge irregularity
spot = smooth(1.0, 0.75, dist_3d / radius + wob)   # a round spot with a living edge
```

## 3. Value and hue

- **Accents:** a unit needs both a near-black and a near-white somewhere, so the 2nd-98th percentile
  of luminance should span at least about 0.6. A uniformly mid-tone unit dissolves into the moss.
- **Hue:** shift hue as the value changes:
  ```python
  col = ramp([(0.0, (0.30, 0.13, 0.06)),          # dark: deep, saturated chestnut
              (0.5, (0.52, 0.27, 0.11)),
              (1.0, (0.74, 0.50, 0.26))], t)       # light: warmer, paler tan
  ```
- **Black is not (0, 0, 0):** use a tinted near-black, such as (0.035, 0.03, 0.025) for a beetle
  stripe or (0.05, 0.04, 0.06) for violet-black.
- **Per-feature variation:** each spot, pore or plate differs a little. Use the `cid` from `cells`:
  `col *= 0.92 + 0.16 * cid[..., None]`.

## 4. Cavities, edges and wear

- **Baked AO goes into the ORM map**, and the shader applies it. Do not also multiply it into the
  albedo (it would darken twice).
- **Crevices:** paint them where the biology puts colour, such as darker sternite seams, pale flesh
  in cracks, or dust in seams. Reuse the relief mask:
  `col = mix(col, crevice_colour, crack_mask * 0.7)`.
- **Edges and tips:** worn margins lighten, wet margins darken, and spore-bearing tips whiten.
  Drive them from t or from distance to the edge.

## 5. Roughness tells the material

- **Glossy:** lacquered chitin, wet caps and eyes, roughness 0.12-0.35.
- **Matte:** dry flesh, stalks and dust, 0.6-0.8. Cotton, mycelium and powder, 0.85-0.95.
- **Within a part:** stripes slightly glossier than the ground, dust rougher, pits rougher.
- **Range:** the lint warns if the range (2nd-98th percentile) is under 0.15.

## 6. Masks for the shader (ORM B channel)

Spare channels drive shader effects at no extra texture cost:
- **Glow:** the Spitter's golden throat.
- **Dust:** the beetle's white spore dust, shown by the shader as infection rises.
- **Wetness or slime:** brightens specular when it rains.

Paint the mask with the same functions as everything else.

## 7. Soft materials without alpha

- **Cotton, fluff and mycelium:**
  - Bright, low-contrast albedo (0.84-0.97).
  - A sculpt of rounded `smooth(...)` lumps plus faint fibre, not ridged `1 - |noise|` (which reads
    as marble or rock).
  - In the shader: `NORMAL_MAP_DEPTH` about 0.55, a rim brightening, `BACKLIGHT`, and the frayed-edge
    discard.
- **Translucent flesh** (gills, jelly, young caps): `BACKLIGHT = col * 0.1-0.35`.

## 8. Checklist before you call the atlas done

- [ ] The lint shows 0 FAIL, and the NOTEs were considered.
- [ ] Every part has a mid-scale pattern from the reference, not just a gradient.
- [ ] There is a dark accent and a pale accent. Hue shifts between light and dark.
- [ ] Spots are round on the model, and stripes converge with the body.
- [ ] Roughness separates glossy, matte and fibrous materials.
- [ ] There are no seams on top, no stretched pattern at the poles, and no bake blobs.
- [ ] The hero render next to the concept: the colours read as the same creature.
