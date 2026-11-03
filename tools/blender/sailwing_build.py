"""Mycena Sailwing art build, run headless in Blender 4.2:

  blender -b --factory-startup -P tools/blender/sailwing_build.py -- --preview=C:/tmp/sailwing.png   # shape, ~1 s
  blender -b --factory-startup -P tools/blender/sailwing_build.py -- [--out=art/sailwing] [--size=1024] [--cpu]
  python tools/art/atlas_lint.py art/sailwing/sailwing

After the Amanita Court roster sheet ("Mycena Sailwing, flying skirmisher"): a colony of
Mycena bonnets (lilac like Mycena pura, glowing like M. chlorophos) carried aloft on a pale,
bird-like fruiting knot, trailing its hyphae like a jellyfish's tentacles.

Brief, by scale:
  Silhouette (60 px, from above): a chevron of seven lilac bells, the biggest in the middle,
    sweeping back and down on both sides like wings; an ivory hooked beak poking out in front;
    a skirt of thin gold strands trailing behind and below. It hovers: nothing touches the ground.
  Mid scale: bell caps with a darker violet centre (umbo) paling to a near-white translucent,
    scalloped margin; radial striae on the top over the gills; gold gills underneath, long ones
    with short ones between; thin ivory stems from the body to each cap; a perforated lattice
    on the back of the body, smooth horn on the beak.
  Fine scale: dew beads on the caps, fibrils along the stems, pores in the lattice.
  Material: waxy, moist caps (glossy dew, backlit translucency); gills and the strand tips glow
    gold (ORM B); dry bone body with a glossier beak.

One opaque surface per LOD, one 1024 atlas. Writes sailwing_{close,battle,distant}.glb and
sailwing_{albedo,normal,orm}.png (orm: R occlusion, G roughness, B glow, A unused).

Data UV (glTF flips v; the shader reads 1 - UV2.y): u = kind + 0.98 * weight, v = group.
  kind 0 body (weight 0 tail .. 1 beak tip)
  kind 1 cap  (weight = distance from the cap's axis, 0 centre .. 1 rim; group = cap index)
  kind 2 stem (weight 0 at the body .. 1 in the cap; group = cap index)
  kind 3 strand (weight 0 at the root .. 1 at the tip; group = strand index)
Caps: 0 the crown; then pairs going out along the wing, odd on the left (z < 0), even on the right.
"""
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from unitlib import export_glb, hide_from_rays, log, save_png, setup_cycles
from paintlib import (PI, TAU, Acc, bake_atlas, cells, data_arr, fbm, grid_normals, mix, orient_out, pnoise,
	preview_render, ramp, rect_uv, smooth, sweep, texel_grid, tri_count, tube_points, vnoise)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else True) for a in ARGS}
OUT = os.path.join(ROOT, OPT.get("out", "art/sailwing"))
SIZE = int(OPT.get("size", 1024))
TAG = "sailwing"
BODY, CAP, STEM, STRAND = 0, 1, 2, 3

# --- atlas (Blender UV, v up): the caps are what the camera sees, so they get the most ----------
RECTS = {
	"cap": (0.006, 0.420, 0.994, 0.994),
	"body": (0.006, 0.006, 0.560, 0.412),
	"stem": (0.568, 0.006, 0.776, 0.412),
	"strand": (0.784, 0.006, 0.994, 0.412),
}


def _norm(v):
	v = np.asarray(v, np.float64)
	return v / np.linalg.norm(v)


def catmull_dense(points, n):
	"""n + 1 points along a Catmull-Rom curve through `points` (any dimension), evenly in parameter."""
	pts = np.asarray(points, np.float64)
	k = len(pts) - 1
	f = np.linspace(0.0, k, n + 1)
	i = np.minimum(f.astype(int), k - 1)
	t = (f - i)[:, None]
	p0, p1, p2, p3 = pts[np.maximum(i - 1, 0)], pts[i], pts[i + 1], pts[np.minimum(i + 2, k)]
	t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


# --- the body: a pale fruiting knot shaped like a bird's head, hooked beak forward --------------
# A tube along a curve in the x-y plane, t from the tail (0) to the beak tip (1).
BODY_PATH = [(-0.42, 1.10), (-0.28, 1.14), (-0.10, 1.18), (0.08, 1.20), (0.22, 1.17), (0.33, 1.09), (0.39, 0.99),
	(0.40, 0.92)]
# (t, half-width, half-height): a deep, slightly flattened body, a full head, a short hooked beak
BODY_PROFILE = [(0.0, 0.010, 0.010), (0.04, 0.070, 0.065), (0.16, 0.130, 0.130), (0.36, 0.165, 0.175),
	(0.56, 0.160, 0.175), (0.70, 0.130, 0.145), (0.80, 0.080, 0.100), (0.89, 0.040, 0.055), (0.96, 0.016, 0.022),
	(1.0, 0.002, 0.002)]
_SPINE = catmull_dense(BODY_PATH, 2000)
_seg = np.linalg.norm(np.diff(_SPINE, axis=0), axis=1)
_ARC = np.concatenate([[0.0], np.cumsum(_seg)]) / _seg.sum()
_PROF = catmull_dense(BODY_PROFILE, 2000)


def body_frame(t):
	"""Centre, up-in-plane normal (a = 0 is the back) for t in [0, 1] (arrays)."""
	t = np.asarray(t, np.float64)
	x = np.interp(t, _ARC, _SPINE[:, 0])
	y = np.interp(t, _ARC, _SPINE[:, 1])
	dt = 1e-3
	x1 = np.interp(np.minimum(t + dt, 1.0), _ARC, _SPINE[:, 0]) - np.interp(np.maximum(t - dt, 0.0), _ARC, _SPINE[:, 0])
	y1 = np.interp(np.minimum(t + dt, 1.0), _ARC, _SPINE[:, 1]) - np.interp(np.maximum(t - dt, 0.0), _ARC, _SPINE[:, 1])
	ln = np.maximum(np.hypot(x1, y1), 1e-9)
	tx, ty = x1 / ln, y1 / ln
	return x, y, -ty, tx   # centre (x, y) and the normal turned up from the tangent


def body_radii(t):
	t = np.asarray(t, np.float64)
	return np.interp(t, _PROF[:, 0], _PROF[:, 1]), np.interp(t, _PROF[:, 0], _PROF[:, 2])


def body_point(a, t):
	"""a = 0 along the back, +-pi underneath (where the seam hides); t tail (0) to beak tip (1)."""
	cx, cy, nx, ny = body_frame(t)
	w, h = body_radii(t)
	ca, sa = np.cos(a), np.sin(a)
	# a keel along the back of the head, a fuller belly
	h = h * (1.0 + 0.10 * np.exp(-(a / 0.5) ** 2) * smooth(0.3, 0.6, t) * smooth(0.85, 0.65, t))
	h = h * np.where(ca < 0, 1.0 + 0.12 * smooth(0.5, 0.2, t), 1.0)
	up = np.sign(ca) * np.abs(ca) ** 0.92 * h
	side = np.sign(sa) * np.abs(sa) ** 0.92 * w
	P = np.stack([cx + nx * up, cy + ny * up, side], axis=-1)
	return P, None


def lattice(P):
	"""The perforated back: round pores (f1) in a raised net (f2 - f1), ~2.6 cm apart."""
	f1, f2, cid = cells(P, 0.022, 3.0)
	return smooth(0.06, 0.16, f2 - f1), smooth(0.07, 0.0, f2 - f1), cid   # open pores, thin walls


def lattice_mask(a, t):
	return smooth(1.15, 0.75, np.abs(a)) * smooth(0.20, 0.32, t) * smooth(0.72, 0.60, t)


def body_relief(a, t, P):
	pore, net, cid = lattice(P)
	m = lattice_mask(a, t)
	r = (-0.010 * pore * (0.7 + 0.3 * cid) + 0.002 * net) * m
	fib = vnoise(np.cos(a) * 9.0, np.sin(a) * 9.0, t * 70.0)   # fibres along the knot
	r = r + 0.0011 * fib * (1.0 - m) * smooth(0.82, 0.7, t)
	r = r + 0.0007 * vnoise(np.cos(a) * 30.0, np.sin(a) * 30.0, t * 260.0) * smooth(0.75, 0.85, t)   # growth lines
	return r + 0.0006 * pnoise(P, 120.0)


def build_surface(acc, fn, centre, rows, cols, rect, kind, group, weight_fn, relief=None):
	j, i = np.mgrid[0:rows + 1, 0:cols + 1]
	t = j / rows
	u = i / cols
	a = u * TAU - PI
	P, _ = fn(a, t)
	N = orient_out(grid_normals(P[:, :-1]), P[:, :-1], np.asarray(centre))
	Pw = P[:, :-1]
	if relief is not None:
		Pw = Pw + N * relief(a[:, :-1], t[:, :-1], Pw)[..., None]
	acc.grid(Pw, N, rect_uv(rect, u, t), data_arr(kind, weight_fn(a, t), group, t.shape))


def build_body(acc, rows, cols, relief=False):
	build_surface(acc, body_point, (0.0, 1.15, 0.0), rows, cols, RECTS["body"], BODY, 0.0, lambda a, t: t,
		body_relief if relief else None)


# --- the caps: Mycena bells, one shape in a unit frame, placed seven times ------------------------
CAP_H, CAP_HI, CAP_LIP = 0.86, 0.50, 0.05   # bell height, how deep the hollow goes, the rim lip
GILLS = 22
R_REF = 0.33                                   # the sculpt's cap radius (m): relief is sized at it


def cap_local(a, t):
	"""Unit cap, axis +Y, the rim at y = 0, radius 1. t from the centre underneath (0) round the
	rim (0.5) to the apex (1). Returns (P, s, q, under): s = distance from the axis,
	q = 0 at the rim .. 1 at the apex on top."""
	phi = np.asarray(t, np.float64) * PI
	c, s = np.cos(phi), np.sin(phi)
	under = c > 0
	q = np.where(under, 0.0, -c)
	# a bell: shoulders falling straight to a flaring skirt, a small umbo; a scalloped, wavy margin
	r_top = (1.0 - q ** 1.8) ** 0.55 * (1.0 - 0.09 * np.sin(PI * q) ** 1.2)
	y_top = CAP_H * q ** 0.8 + 0.05 * np.exp(-(r_top / 0.2) ** 2)
	r_und = s ** 0.62
	y_und = CAP_HI * (1.0 - s ** 2) - CAP_LIP * np.abs(c) ** 0.8
	r = np.where(under, r_und, r_top)
	y = np.where(under, y_und, y_top)
	edge = s ** 6
	r = r * (1.0 + edge * (0.045 * np.sin(5 * a + 1.3) + 0.022 * np.sin(11 * a + 0.4)))
	y = y + edge * 0.035 * np.sin(7 * a + 2.1)
	P = np.stack([r * np.cos(a), y, r * np.sin(a)], axis=-1)
	return P, s, q, under


def gill_mask(a, s):
	inner = smooth(0.10, 0.25, s) * smooth(0.995, 0.96, s)
	blade = np.maximum(np.cos(a * GILLS), 0.0) ** 10
	short = np.maximum(np.cos(a * GILLS + PI), 0.0) ** 10 * smooth(0.48, 0.62, s)
	return (blade + 0.85 * short) * inner


def striae(a, q):
	"""Translucent lines on the top over the gills, fading out toward the apex."""
	return np.maximum(np.cos(a * GILLS), 0.0) ** 6 * smooth(0.55, 0.05, q)


def dew(P):
	f1, _, cid = cells(P, 0.020, 7.0)
	return smooth(0.32, 0.14, f1) * smooth(0.80, 0.86, cid)


def cap_relief(a, t, P):
	Pl, s, q, under = cap_local(a, t)
	Pm = Pl * R_REF
	top = 1.0 - under
	r = 0.014 * gill_mask(a, s) * under
	r = r - 0.0022 * striae(a, q) * top
	r = r + 0.0028 * dew(Pm) * top * smooth(0.95, 0.7, q)
	r = r + 0.0008 * pnoise(Pm, 60.0) * top
	return r


# The caps fan out from a hub in the body like a bouquet, so each one's gills face the body:
# (sideways angle from vertical, lean forward (+) or back (-), distance from the hub, radius).
HUB = np.array([-0.10, 1.12, 0.0])
FAN = [(0.0, -0.15, 0.62, 0.40), (33.0, 0.30, 0.74, 0.34), (60.0, -0.28, 0.94, 0.31), (86.0, -0.80, 1.08, 0.26)]
CAP_LAYOUT = []
for _i, (_side, _lean, _dist, _r) in enumerate(FAN):
	for _sd in ((0.0,) if _i == 0 else (-1.0, 1.0)):
		_th = math.radians(_side)
		_d = _norm((_lean, math.cos(_th), _sd * math.sin(_th)))
		_axis = _norm(_d + np.array([0.0, 0.55 + 0.3 * _side / 90.0, 0.0]))     # tipped up from the radial, tops toward the sky
		CAP_LAYOUT.append((tuple(HUB + _d * _dist), tuple(_axis), _r))


def cap_frame(k):
	c, u, r = CAP_LAYOUT[k]
	U = _norm(u)
	back = np.array([-1.0, 0.0, 0.0])   # the seam (a = -pi) faces the tail
	e1 = _norm(-(back - U * np.dot(back, U)))
	e2 = np.cross(e1, U)
	return np.asarray(c, np.float64), U, e1, e2, r


def cap_world(k, Pl):
	c, U, e1, e2, r = cap_frame(k)
	return c + r * (Pl[..., 0:1] * e1 + Pl[..., 1:2] * U + Pl[..., 2:3] * e2)


def build_cap(acc, k, rows, cols, relief=False, origin=None):
	"""Cap k in place; or, with origin, the sculpt cap at R_REF with its axis up at origin."""
	j, i = np.mgrid[0:rows + 1, 0:cols + 1]
	t = j / rows
	u = i / cols
	a = u * TAU - PI
	Pl, s, q, under = cap_local(a, t)
	if origin is not None:
		P = np.asarray(origin) + Pl * R_REF
		centre = np.asarray(origin) + np.array([0.0, 0.3 * R_REF, 0.0])
	else:
		P = cap_world(k, Pl)
		c, U, _, _, r = cap_frame(k)
		centre = c + U * 0.3 * r
	N = orient_out(grid_normals(P[:, :-1]), P[:, :-1], centre)
	Pw = P[:, :-1]
	if relief:
		Pw = Pw + N * cap_relief(a[:, :-1], t[:, :-1], Pw)[..., None]
	acc.grid(Pw, N, rect_uv(RECTS["cap"], u, t), data_arr(CAP, s, float(k), t.shape))


# --- stems: from the back of the body up into each cap ---------------------------------------
STEM_ROOTS = [(-0.10, 1.30, 0.0), (0.02, 1.30, 0.05), (-0.14, 1.28, 0.08), (-0.28, 1.24, 0.07)]


def stem_path(k):
	c, U, e1, e2, r = cap_frame(k)
	pair = (k + 1) // 2
	sd = 0.0 if k == 0 else (-1.0 if k % 2 else 1.0)
	root = np.array(STEM_ROOTS[pair]) * np.array([1.0, 1.0, sd])
	top = c + U * (CAP_HI - CAP_LIP) * r          # the centre of the cap's underside
	# a quadratic curve that leaves the body upward and enters the cap along its axis
	L = np.linalg.norm(top - root)
	ctrl = top - U * L * 0.5
	pts = [root - np.array([0.0, 0.06, 0.0])]
	for f in (0.0, 0.3, 0.6, 0.85, 1.0):
		pts.append((1 - f) ** 2 * root + 2 * (1 - f) * f * ctrl + f * f * top)
	pts.append(top + U * 0.04)
	return [tuple(p) for p in pts]


STEM_RADII = [0.022, 0.019, 0.014, 0.012, 0.012, 0.016, 0.012]


def stem_relief(t, ang, P):
	return 0.0012 * vnoise(np.cos(ang) * 5.0, np.sin(ang) * 5.0, t * 40.0) + 0.0005 * pnoise(P, 150.0)


def build_stem(acc, k, sides, samples, relief=False):
	sweep(acc, stem_path(k), STEM_RADII, sides, samples, RECTS["stem"], STEM, float(k), lambda tt: tt,
		relief=stem_relief if relief else None)


# --- strands: hyphae trailing from the belly and tail, like a jellyfish's tentacles -------------
STRANDS = []   # (root, length, side, curl, phase)
for _i, (_x, _z, _len) in enumerate(((-0.40, 0.0, 0.95), (-0.30, -0.07, 0.85), (-0.30, 0.07, 0.88), (-0.18, -0.10, 0.80),
		(-0.18, 0.10, 0.78), (-0.05, -0.08, 0.70), (-0.05, 0.08, 0.72), (0.08, -0.05, 0.58), (0.08, 0.05, 0.60))):
	STRANDS.append(((_x, 1.06 if _x < -0.35 else 1.02, _z), _len, 1.0 if _z >= 0 else -1.0, 0.6 + 0.35 * ((_i * 7) % 5) / 4,
		_i * 1.7))


def strand_path(i, n=7):
	root, ln, sd, curl, ph = STRANDS[i]
	root = np.array(root)
	pts = [root + np.array([0.02, 0.04, 0.0])]
	for j in range(1, n + 1):
		f = j / n
		drop = 0.62 * ln * f ** 0.8                                  # down ...
		trail = -0.70 * ln * f ** 1.25                                # ... and back
		spread = sd * (0.10 * f + 0.06 * math.sin(f * 4.0 + ph)) + root[2] * 1.5 * f
		wav = 0.05 * math.sin(f * 6.5 + ph) * f
		hook = curl * 0.10 * smooth(0.65, 1.0, f) * ln                # the tips curl up
		pts.append(root + np.array([trail + wav, -drop + hook, spread]))
	return [tuple(p) for p in pts]


STRAND_RADII = [0.016, 0.012, 0.010, 0.008, 0.007, 0.006, 0.005, 0.004]


def strand_radius(t):
	return 1.0 + 0.6 * np.exp(-((t - 0.985) / 0.02) ** 2)   # a bead of a spore at the tip


def strand_relief(t, ang, P):
	return 0.0006 * pnoise(P, 140.0)


def build_strand(acc, i, sides, samples, relief=False):
	sweep(acc, strand_path(i), STRAND_RADII, sides, samples, RECTS["strand"], STRAND, float(i), lambda tt: tt,
		relief=strand_relief if relief else None, radius_fn=strand_radius)


# --- whole models ------------------------------------------------------------------------------

def build_lod(lod):
	acc = Acc()
	build_body(acc, *[(26, 22), (13, 12), (7, 8)][lod])
	cr, cc = [(14, 26), (8, 14), (6, 8)][lod]   # even rows: one lands on the rim (t = 0.5)
	for k in range(len(CAP_LAYOUT)):
		build_cap(acc, k, cr, cc)
	ss, sn = [(5, 9), (4, 4), (3, 2)][lod]
	for k in range(len(CAP_LAYOUT)):
		build_stem(acc, k, ss, sn)
	strands = [range(len(STRANDS)), (0, 1, 2, 3, 4, 7, 8), (0, 3, 4)][lod]
	ts, tn = [(4, 14), (3, 7), (3, 4)][lod]
	for i in strands:
		build_strand(acc, i, ts, tn)
	return acc


# --- paint -------------------------------------------------------------------------------------

LILAC_RIM = (0.96, 0.93, 0.98)
LILAC = (0.86, 0.79, 0.95)
VIOLET = (0.70, 0.58, 0.87)
UMBO = (0.62, 0.49, 0.80)
DEW = (0.98, 0.97, 1.0)
GILL_EDGE = (1.0, 0.90, 0.60)
GILL = (0.96, 0.70, 0.26)
GILL_DEEP = (0.42, 0.20, 0.05)
BONE = (0.93, 0.89, 0.80)
BONE_WARM = (0.86, 0.76, 0.60)
PORE = (0.30, 0.19, 0.11)
HORN = (0.60, 0.52, 0.44)


def paint(size):
	albedo = np.zeros((size, size, 3))
	albedo[...] = BONE
	orm = np.ones((size, size, 4))
	orm[..., 1] = 0.6
	orm[..., 2] = 0.0

	# caps
	sl, u, v = texel_grid(RECTS["cap"], size)
	a = u * TAU - PI
	Pl, s, q, under = cap_local(a, v)
	P = Pl * R_REF
	mott = pnoise(P, 9.0, 3) * 0.5 + 0.5
	top = ramp([(0.0, LILAC_RIM), (0.2, LILAC), (0.6, (0.80, 0.71, 0.93)), (0.88, VIOLET), (1.0, UMBO)],
		np.clip(q ** 0.9 + 0.16 * (mott - 0.5), 0.0, 1.0))
	st = striae(a, q)
	# the striae: the gold gills showing through the thin margin, violet higher up
	top = mix(top, mix((0.62, 0.48, 0.80), (0.98, 0.80, 0.42), smooth(0.35, 0.05, q)), st * 0.6)
	top = mix(top, (0.97, 0.93, 0.99), smooth(0.08, 0.0, q) * 0.6)   # the thin translucent margin
	dw = dew(P) * smooth(0.95, 0.7, q)
	top = mix(top, DEW, dw * 0.9)
	g = gill_mask(a, s)
	# blades lit gold to their edges, amber between them, dark only deep in the crevice
	wide = (np.maximum(np.cos(a * GILLS), 0.0) ** 3 + 0.85 * np.maximum(np.cos(a * GILLS + PI), 0.0) ** 3
		* smooth(0.48, 0.62, s)) * smooth(0.10, 0.25, s)
	gl = ramp([(0.0, GILL_DEEP), (0.18, (0.78, 0.46, 0.13)), (0.55, GILL), (1.0, GILL_EDGE)],
		np.clip(0.12 + 0.55 * wide + 0.45 * g, 0.0, 1.0))
	gl = mix(gl, (0.95, 0.88, 0.72), smooth(0.25, 0.08, s))        # pale where the stem joins
	gl = mix(gl, (0.84, 0.70, 0.86), smooth(0.462, 0.494, v) * 0.7)   # the lip is lilac again
	und = under.astype(np.float64)
	albedo[sl] = mix(top, gl, und)
	orm[sl + (1,)] = np.where(under, 0.55 - 0.15 * g, np.clip(0.44 + 0.12 * (mott - 0.5) + 0.06 * st - 0.36 * dw, 0.06, 0.9))
	orm[sl + (2,)] = np.where(under, np.clip(0.35 + 0.35 * wide + 0.3 * g, 0.0, 1.0) * smooth(0.10, 0.3, s) * smooth(0.494, 0.465, v),
		0.30 * smooth(0.14, 0.0, q) + 0.55 * st * smooth(0.4, 0.05, q))

	# body: bone white, warmer underneath, the lattice's pores dark, the beak horn
	sl, u, v = texel_grid(RECTS["body"], size)
	a = u * TAU - PI
	P, _ = body_point(a, v)
	pore, net, cid = lattice(P)
	m = lattice_mask(a, v)
	n1 = pnoise(P, 14.0, 3) * 0.5 + 0.5
	col = ramp([(0.0, BONE_WARM), (1.0, BONE)], np.clip(0.55 + 0.35 * np.cos(a) + 0.2 * (n1 - 0.5), 0.0, 1.0))
	col = mix(col, (0.88, 0.70, 0.40), smooth(-0.3, -0.85, np.cos(a)) * smooth(0.5, 0.15, v) * 0.6)   # gold where the strands root
	col = mix(col, mix(PORE, (0.62, 0.40, 0.16), cid), pore * m * 0.85)
	col = mix(col, (0.98, 0.95, 0.88), net * m * 0.5)
	beak = smooth(0.80, 0.92, v)
	col = mix(col, HORN, beak * 0.75)
	col = mix(col, (0.30, 0.24, 0.20), smooth(0.95, 1.0, v) * 0.8)
	albedo[sl] = col
	orm[sl + (1,)] = np.clip(0.62 + 0.25 * pore * m - 0.32 * beak + 0.05 * (n1 - 0.5), 0.15, 0.95)
	orm[sl + (2,)] = 0.5 * smooth(-0.4, -0.9, np.cos(a)) * smooth(0.45, 0.1, v) + 0.35 * pore * m * cid

	# stems: translucent ivory, gold at the body, lilac into the cap
	sl, u, v = texel_grid(RECTS["stem"], size)
	P = tube_points(stem_path(3), STEM_RADII, u, v)
	fib = pnoise(P * np.array([1.0, 0.25, 1.0]), 90.0, 2)   # fibrils run along the stem
	col = ramp([(0.0, (0.90, 0.72, 0.40)), (0.18, (0.97, 0.94, 0.86)), (0.75, (0.96, 0.93, 0.90)), (1.0, (0.84, 0.76, 0.92))], v)
	albedo[sl] = col * (0.94 + 0.08 * fib[..., None])
	orm[sl + (1,)] = 0.42 + 0.08 * fib
	orm[sl + (2,)] = 0.4 * smooth(0.2, 0.0, v)

	# strands: cream at the root, gold out along, a glowing bead at the tip
	sl, u, v = texel_grid(RECTS["strand"], size)
	ang = u * TAU
	n1 = vnoise(np.cos(ang) * 3.0, np.sin(ang) * 3.0, v * 30.0)
	col = ramp([(0.0, (0.93, 0.87, 0.70)), (0.6, (0.88, 0.66, 0.28)), (0.95, (0.80, 0.52, 0.14)), (1.0, (1.0, 0.92, 0.62))],
		np.clip(v + 0.04 * n1, 0.0, 1.0))
	albedo[sl] = col
	orm[sl + (1,)] = 0.5 - 0.2 * smooth(0.95, 0.99, v)
	orm[sl + (2,)] = 0.15 + 0.35 * smooth(0.5, 0.95, v) + 0.5 * smooth(0.95, 0.985, v)
	return albedo, orm


# --- the bake ----------------------------------------------------------------------------------

def main():
	os.makedirs(OUT, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	setup_cycles(TAG, bool(OPT.get("cpu")), ao_distance=0.12)
	log(TAG, "building sculpt")
	hi, lo = {}, {}
	CAP_O = (0.0, 6.0, 0.0)   # the sculpt cap stands alone, away from the body
	acc = Acc(); build_body(acc, 500, 700, relief=True); hi["body"] = acc.obj("hi_body")
	acc = Acc(); build_cap(acc, 0, 520, 1100, relief=True, origin=CAP_O); hi["cap"] = acc.obj("hi_cap")
	acc = Acc(); build_stem(acc, 3, 48, 300, relief=True); hi["stem"] = acc.obj("hi_stem")
	acc = Acc(); build_strand(acc, 0, 24, 400, relief=True); hi["strand"] = acc.obj("hi_strand")
	shade = Acc()   # the rest only shades the body
	for k in range(len(CAP_LAYOUT)):
		build_cap(shade, k, 24, 40)
		build_stem(shade, k, 8, 20)
	for i in range(len(STRANDS)):
		build_strand(shade, i, 6, 20)
	shade = shade.obj("ao_rest")
	log(TAG, "sculpt: %d faces" % sum(len(o.data.polygons) for o in hi.values()))
	acc = Acc(); build_body(acc, 120, 160); lo["body"] = acc.obj("lo_body")
	acc = Acc(); build_cap(acc, 0, 140, 280, origin=CAP_O); lo["cap"] = acc.obj("lo_cap")
	acc = Acc(); build_stem(acc, 3, 16, 80); lo["stem"] = acc.obj("lo_stem")
	acc = Acc(); build_strand(acc, 0, 12, 120); lo["strand"] = acc.obj("lo_strand")
	for ob in lo.values():
		hide_from_rays(ob)
	parts = {
		"body": {"low": lo["body"], "normal_from": [hi["body"]], "ao_from": [hi["body"], shade], "reach": (0.013, 0.024),
			"poles": (0.02, 0.985)},
		"cap": {"low": lo["cap"], "normal_from": [hi["cap"]], "ao_from": [hi["cap"]], "reach": (0.016, 0.03),
			"poles": (0.03, 0.985)},
		"stem": {"low": lo["stem"], "normal_from": [hi["stem"]], "ao_from": [hi["stem"]], "reach": (0.004, 0.008),
			"poles": None},
		"strand": {"low": lo["strand"], "normal_from": [hi["strand"]], "ao_from": [hi["strand"]], "reach": (0.003, 0.006),
			"poles": None},
	}
	normal, ao, u, v, masks = bake_atlas(parts, RECTS, SIZE, TAG)
	log(TAG, "painting")
	albedo, orm = paint(SIZE)
	orm[..., 0] = ao
	# thin tubes self-shade into speckle in the AO bake: give them a clean gradient instead
	sl, u, v = texel_grid(RECTS["stem"], SIZE)
	orm[sl + (0,)] = 0.72 + 0.28 * smooth(0.0, 0.25, v)
	sl, u, v = texel_grid(RECTS["strand"], SIZE)
	orm[sl + (0,)] = 0.8 + 0.2 * smooth(0.0, 0.3, v)
	alb = np.ones((SIZE, SIZE, 4), np.float32)
	alb[..., :3] = albedo
	save_png(os.path.join(OUT, TAG + "_albedo.png"), alb, False)
	save_png(os.path.join(OUT, TAG + "_normal.png"), normal, True)
	save_png(os.path.join(OUT, TAG + "_orm.png"), orm.astype(np.float32), True)
	for ob in list(hi.values()) + list(lo.values()) + [shade]:
		bpy.data.objects.remove(ob)
	stats = []
	for lod, name in enumerate(("close", "battle", "distant")):
		ob = build_lod(lod).obj("Sailwing_" + name)
		stats.append("%s %d" % (name, tri_count(ob)))
		export_glb([ob], os.path.join(OUT, "%s_%s.glb" % (TAG, name)))
	rig()
	log(TAG, "done: " + ", ".join(stats))


def rig():
	"""Constants for the shader: each cap's stem root (its hinge) and its rim centre and axis."""
	fmt = lambda v: "vec3(%s)" % ", ".join("%.4f" % float(c) for c in v)
	roots = [stem_path(k)[1] for k in range(len(CAP_LAYOUT))]
	log(TAG, "rig: const vec3 STEM_ROOT[7] = {%s};" % ", ".join(fmt(r) for r in roots))
	log(TAG, "rig: const vec3 CAP_AXIS[7] = {%s};" % ", ".join(fmt(cap_frame(k)[1]) for k in range(len(CAP_LAYOUT))))
	log(TAG, "rig: const vec3 CAP_CENTRE[7] = {%s};" % ", ".join(fmt(cap_frame(k)[0]) for k in range(len(CAP_LAYOUT))))


def preview(path):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	ob = build_lod(int(OPT.get("lod", 0))).obj("preview")
	ob.color = (0.82, 0.74, 0.90, 1.0)
	log(TAG, "preview tris %d" % tri_count(ob))
	preview_render([ob], path, target=(-0.1, 1.25, 0.0), scale=3.9,
		views=(("side", 0.0, 0.12), ("q", 0.8, 0.5), ("top", 0.0, 1.45), ("front", PI / 2, 0.15)))


if OPT.get("preview"):
	preview(os.path.abspath(OPT["preview"]))
elif OPT.get("rig"):
	rig()
else:
	main()
