"""TEMPLATE unit art build: copy to tools/blender/<unit>_build.py and replace the example.

  blender -b --factory-startup -P tools/blender/<unit>_build.py -- --preview=C:/tmp/<unit>.png   # shape, ~1 s
  blender -b --factory-startup -P tools/blender/<unit>_build.py                                   # sculpt, bake, paint, export
  python tools/art/atlas_lint.py art/<unit>/<unit>                                                # must show 0 FAIL

The example is a small bolete-like sporeling (a cap with pores underneath on a stout,
net-veined stalk), so every step of the method is visible in about 200 lines:
  shape functions -> relief functions -> paint functions (same parameters) ->
  sculpt + bake targets -> bake_atlas -> paint -> three LODs -> GLBs + atlas.
Write the docstring of your copy as a description of the reference: what the silhouette
is, which mid-scale patterns it has (bands, spots, segments, joints) and which fine detail
(pits, fibres, pores), with real colours. That list is the brief the build must meet.

Data UV: u = kind + 0.98 * weight (0 cap, 1 stalk), v = group. Plan these for the shader:
anything that moves differently (legs, a head, a cap that nods) needs its own kind or group.
"""
import math
import os
import sys

import bpy
import numpy as np

# Run from the repo root. Finds paintlib / unitlib whether this file sits in tools/blender (where
# your copy belongs) or still in a skills folder.
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.getcwd() if os.path.exists("project.godot") else os.path.abspath(os.path.join(HERE, "..", ".."))
for d in (HERE, os.path.join(ROOT, "tools", "blender")):
	sys.path.insert(0, d)
from unitlib import export_glb, hide_from_rays, log, save_png, setup_cycles
from paintlib import (PI, TAU, Acc, bake_atlas, cells, mix, pnoise, preview_render, ramp, smooth, surface, sweep,
	texel_grid, tri_count, tube_points)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else True) for a in ARGS}
NAME = OPT.get("name", "example")
OUT = os.path.join(ROOT, OPT.get("out", "art/" + NAME))
SIZE = int(OPT.get("size", 1024))
CAP, STALK = 0, 1

# --- atlas: the most visible part gets the most texels -------------------------------------------
RECTS = {"cap": (0.006, 0.36, 0.994, 0.994), "stalk": (0.006, 0.006, 0.994, 0.35)}

# --- shape (game space: Y up, +X forward) --------------------------------------------------------
CAP_C = np.array([0.0, 0.95, 0.0])
CAP_R, CAP_H, CAP_UNDER = 0.62, 0.42, 0.16
STALK_PATH = [(0.0, 0.0, 0.0), (0.02, 0.25, 0.0), (0.0, 0.55, 0.0), (-0.03, 0.9, 0.0)]
STALK_RADII = [0.26, 0.24, 0.19, 0.15]


def cap_point(a, t):
	"""a round the cap (seam at the back, a = -pi), t from the pore centre (0) round the rim (0.5)
	to the top (1). Signed powers of cos / sin keep the margin rounded: a sharp crease there
	would leave bake artifacts and read as a hard plastic edge."""
	phi = t * PI
	c, s = np.cos(phi), np.sin(phi)
	r = CAP_R * s ** 0.55
	y = -np.sign(c) * np.abs(c) ** 0.75 * np.where(c > 0, CAP_UNDER, CAP_H)
	r = r * (1.0 + 0.04 * np.sin(3 * a + 1.0))   # a slightly lobed, irregular rim
	return np.stack([CAP_C[0] + r * np.cos(a), CAP_C[1] + y, CAP_C[2] + r * np.sin(a)], axis=-1), None


# --- relief: sculpt-only displacement (m). Size features in metres, not in texels. --------------
def cap_relief(a, t, P):
	under = smooth(0.49, 0.45, t)
	d, _, _ = cells(P, 0.018)                   # pores underneath, ~2 cm apart
	pores = -0.006 * smooth(0.45, 0.15, d) * under * smooth(0.02, 0.1, t)
	cracks = -0.004 * smooth(0.08, 0.0, np.abs(pnoise(P, 9.0, 2))) * (1 - under)   # dry, crazed top
	return pores + cracks + 0.0015 * pnoise(P, 60.0)


def stalk_relief(t, ang, P):
	f1, f2, _ = cells(P * np.array([1.0, 0.45, 1.0]), 0.03)   # a raised net, stretched along the stalk
	return 0.004 * smooth(0.12, 0.0, f2 - f1) + 0.001 * pnoise(P, 80.0)


def build_cap(acc, rows, cols, relief=False):
	surface(acc, cap_point, CAP_C, rows, cols, RECTS["cap"], CAP, relief=cap_relief if relief else None)


def build_stalk(acc, sides, samples, relief=False):
	sweep(acc, STALK_PATH, STALK_RADII, sides, samples, RECTS["stalk"], STALK, 0.0, lambda tt: 0.0 * tt,
		relief=stalk_relief if relief else None)


def build_lod(lod):
	acc = Acc()
	build_cap(acc, *[(16, 32), (9, 18), (5, 10)][lod])
	build_stalk(acc, *[(12, 10), (8, 6), (5, 3)][lod])
	return acc


# --- paint: colour, roughness and masks from the SAME functions, in 3D -------------------------
def paint(size):
	albedo = np.zeros((size, size, 3))
	orm = np.ones((size, size, 4))
	orm[..., 1] = 0.6
	orm[..., 2] = 0.0

	sl, u, v = texel_grid(RECTS["cap"], size)
	a = u * TAU - PI
	P, _ = cap_point(a, v)
	under = smooth(0.49, 0.45, v)
	# the top: a hue-shifting ramp (dark chestnut -> warm tan) driven by broad mottling and the rim
	mott = pnoise(P, 4.0, 3) * 0.5 + 0.5
	top = ramp([(0.0, (0.30, 0.13, 0.06)), (0.5, (0.52, 0.27, 0.11)), (1.0, (0.74, 0.50, 0.26))],
		0.25 + 0.5 * mott + 0.25 * smooth(0.6, 0.45, v))
	crack = smooth(0.08, 0.0, np.abs(pnoise(P, 9.0, 2))) * (1 - under)
	top = mix(top, (0.86, 0.72, 0.50), crack * 0.7)   # pale flesh shows in the cracks
	top = mix(top, (0.20, 0.08, 0.04), smooth(0.62, 0.5, v) * 0.5)   # darker, wetter at the margin
	# underneath: yellow pores bruising blue-green where touched
	d, _, cid = cells(P, 0.018)
	pores = mix((0.80, 0.70, 0.22), (0.45, 0.38, 0.10), smooth(0.45, 0.15, d))
	pores = pores * (0.92 + 0.16 * cid[..., None])   # each pore a little different
	bruise = smooth(0.35, 0.7, pnoise(P, 6.0, 2) * 0.5 + 0.5)
	pores = mix(pores, (0.18, 0.32, 0.36), bruise * 0.6)
	albedo[sl] = mix(top, pores, under)
	orm[sl + (1,)] = np.clip(0.42 + 0.25 * crack + 0.25 * under - 0.1 * mott, 0.2, 0.95)

	sl, u, v = texel_grid(RECTS["stalk"], size)
	P = tube_points(STALK_PATH, STALK_RADII, u, v)   # exactly where the sculpt raised its net
	f1, f2, _ = cells(P * np.array([1.0, 0.45, 1.0]), 0.03)
	net = smooth(0.12, 0.0, f2 - f1)
	base = ramp([(0.0, (0.55, 0.42, 0.25)), (1.0, (0.86, 0.78, 0.58))], v)   # darker, earthier at the foot
	albedo[sl] = mix(base, (0.42, 0.24, 0.10), net * 0.75)
	orm[sl + (1,)] = 0.7 - 0.1 * net
	return albedo, orm


def main():
	os.makedirs(OUT, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	setup_cycles(NAME, bool(OPT.get("cpu")), ao_distance=0.12)
	hi, lo = {}, {}
	acc = Acc(); build_cap(acc, 400, 900, relief=True); hi["cap"] = acc.obj("hi_cap")
	acc = Acc(); build_stalk(acc, 300, 260, relief=True); hi["stalk"] = acc.obj("hi_stalk")
	acc = Acc(); build_cap(acc, 120, 240); lo["cap"] = acc.obj("lo_cap")     # smooth bake targets, same UVs
	acc = Acc(); build_stalk(acc, 48, 60); lo["stalk"] = acc.obj("lo_stalk")
	for ob in lo.values():
		hide_from_rays(ob)
	all_hi = list(hi.values())
	parts = {
		"cap": {"low": lo["cap"], "normal_from": [hi["cap"]], "ao_from": all_hi, "reach": (0.012, 0.025), "poles": (0.03, 0.97)},
		"stalk": {"low": lo["stalk"], "normal_from": [hi["stalk"]], "ao_from": all_hi, "reach": (0.008, 0.018), "poles": (0.03, 0.97)},
	}
	normal, ao, u, v, masks = bake_atlas(parts, RECTS, SIZE, NAME)
	albedo, orm = paint(SIZE)
	orm[..., 0] = ao
	alb = np.ones((SIZE, SIZE, 4), np.float32)
	alb[..., :3] = albedo
	save_png(os.path.join(OUT, NAME + "_albedo.png"), alb, False)
	save_png(os.path.join(OUT, NAME + "_normal.png"), normal, True)
	save_png(os.path.join(OUT, NAME + "_orm.png"), orm.astype(np.float32), True)
	for ob in all_hi + list(lo.values()):
		bpy.data.objects.remove(ob)
	stats = []
	for lod, name in enumerate(("close", "battle", "distant")):
		ob = build_lod(lod).obj("%s_%s" % (NAME, name))
		stats.append("%s %d" % (name, tri_count(ob)))
		export_glb([ob], os.path.join(OUT, "%s_%s.glb" % (NAME, name)))
	log(NAME, "done: " + ", ".join(stats))


if OPT.get("preview"):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	ob = build_lod(0).obj("preview")
	ob.color = (0.8, 0.6, 0.4, 1.0)
	preview_render([ob], os.path.abspath(OPT["preview"]), target=(0.0, 0.7, 0.0), scale=2.4)
else:
	main()
