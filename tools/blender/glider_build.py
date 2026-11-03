"""Splitgill Glider art build, run headless in Blender 4.2:

  blender -b --factory-startup -P tools/blender/glider_build.py -- --preview=C:/tmp/glider.png   # shape, ~1 s
  blender -b --factory-startup -P tools/blender/glider_build.py -- [--out=art/glider] [--size=1024] [--cpu]
  blender -b --factory-startup -P tools/blender/glider_build.py -- --rig=art/glider/rig/glider_rig.glb
  python tools/art/atlas_lint.py art/glider/glider

After the Morel Hollow combat roster ("Splitgill Glider, flying spore bomber"): two fans of
Schizophyllum commune, the split-gill, spread as wings from a pitted, morel-honeycombed body, a
ragged rust streamer for a tail, and a clutch of dark earthball spore bombs slung underneath.

Brief, by scale:
  Silhouette (60 px, from above): a wide pair of ruffled fans, rust on top with a pale lip, from a
    short pale body; a narrow rust streamer behind; a cluster of dark balls under the belly that
    shows from the RTS angle. It flies: nothing touches the ground.
  Mid scale: the fans are half funnels, concave on top. Underneath, cream gills radiate from the
    root, each split along its edge (the species' namesake), with short gills between; on top, a
    rust-red crust behind a thick cream lip, with concentric growth zones and radial fibres; lobed,
    wavy margins. The body is a morel's honeycomb of dark pits between pale ridges. The bombs are
    warty and near black, flecked with gold.
  Fine scale: hairs on the fan tops, crust granules, ridges between the pits, warts on the bombs.
  Material: dry, velvety fans (matte, rougher on the crust), a waxy cream body, glossy-dark bombs
    with glinting gold flecks (ORM B: the flecks and the gill edges glow faintly).

One opaque surface per LOD, one 1024 atlas. Writes glider_{close,battle,distant}.glb and
glider_{albedo,normal,orm}.png (orm: R occlusion, G roughness, B glow, A unused).

Data UV (glTF flips v; the shader reads 1 - UV2.y): u = kind + 0.98 * weight, v = group.
  kind 0 body   (weight 0 tail tip .. 1 nose)
  kind 1 wing   (weight = distance from the root, 0 .. 1 at the margin; group 0 left (z < 0), 1 right)
  kind 2 tail   (weight = distance from the root, 0 .. 1 at the tip)
  kind 3 bomb   (weight 0 at its top .. 1 at its bottom; group = bomb index)
  kind 4 cord   (weight 0 at the belly .. 1 at the bomb; group = bomb index)

Motion comes from bones (see rig()): UniMate generates the clips on the rig GLB, and
tools/unimate/glider_motion.py bakes them into a bone texture the shader plays back. The shader
skins each vertex from its data UV, so the GLBs carry no skin.
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
from paintlib import (PI, TAU, Acc, bake_atlas, cells, data_arr, g2b, grid_normals, mix, orient_out, pnoise,
	preview_render, ramp, rect_uv, smooth, sweep, texel_grid, tri_count, tube_points, vnoise)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else True) for a in ARGS}
OUT = os.path.join(ROOT, OPT.get("out", "art/glider"))
SIZE = int(OPT.get("size", 1024))
TAG = "glider"
BODY, WING, TAIL, BOMB, CORD = 0, 1, 2, 3, 4

# --- atlas (Blender UV, v up): the wings are what the camera sees, so they get the most ---------
RECTS = {
	"wing": (0.006, 0.430, 0.994, 0.994),
	"body": (0.006, 0.006, 0.470, 0.422),
	"tail": (0.478, 0.006, 0.720, 0.422),
	"bomb": (0.728, 0.216, 0.994, 0.422),
	"cord": (0.728, 0.006, 0.994, 0.208),
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


def rot_x(P, a):
	c, s = math.cos(a), math.sin(a)
	return np.stack([P[..., 0], P[..., 1] * c - P[..., 2] * s, P[..., 1] * s + P[..., 2] * c], axis=-1)


def rot_y(P, a):
	c, s = math.cos(a), math.sin(a)
	return np.stack([P[..., 0] * c + P[..., 2] * s, P[..., 1], -P[..., 0] * s + P[..., 2] * c], axis=-1)


def rot_z(P, a):
	c, s = math.cos(a), math.sin(a)
	return np.stack([P[..., 0] * c - P[..., 1] * s, P[..., 0] * s + P[..., 1] * c, P[..., 2]], axis=-1)


# --- the body: a pitted morel spindle, nose forward (+x), tapering back into the streamer ---------
BODY_PATH = [(-0.56, 1.37), (-0.42, 1.38), (-0.24, 1.39), (-0.04, 1.39), (0.16, 1.37), (0.32, 1.33), (0.44, 1.28),
	(0.50, 1.24)]
# (t, half-width, half-height)
BODY_PROFILE = [(0.0, 0.008, 0.008), (0.05, 0.045, 0.050), (0.18, 0.085, 0.095), (0.38, 0.135, 0.150),
	(0.56, 0.150, 0.165), (0.72, 0.135, 0.145), (0.85, 0.100, 0.105), (0.94, 0.062, 0.064), (0.985, 0.030, 0.030),
	(1.0, 0.002, 0.002)]
_SPINE = catmull_dense(BODY_PATH, 2000)
_seg = np.linalg.norm(np.diff(_SPINE, axis=0), axis=1)
_ARC = np.concatenate([[0.0], np.cumsum(_seg)]) / _seg.sum()
_PROF = catmull_dense(BODY_PROFILE, 2000)


def body_frame(t):
	t = np.asarray(t, np.float64)
	x = np.interp(t, _ARC, _SPINE[:, 0])
	y = np.interp(t, _ARC, _SPINE[:, 1])
	dt = 1e-3
	x1 = np.interp(np.minimum(t + dt, 1.0), _ARC, _SPINE[:, 0]) - np.interp(np.maximum(t - dt, 0.0), _ARC, _SPINE[:, 0])
	y1 = np.interp(np.minimum(t + dt, 1.0), _ARC, _SPINE[:, 1]) - np.interp(np.maximum(t - dt, 0.0), _ARC, _SPINE[:, 1])
	ln = np.maximum(np.hypot(x1, y1), 1e-9)
	tx, ty = x1 / ln, y1 / ln
	return x, y, -ty, tx


def body_radii(t):
	t = np.asarray(t, np.float64)
	return np.interp(t, _PROF[:, 0], _PROF[:, 1]), np.interp(t, _PROF[:, 0], _PROF[:, 2])


def body_point(a, t):
	"""a = 0 along the back, +-pi underneath (the seam); t tail tip (0) to nose (1)."""
	cx, cy, nx, ny = body_frame(t)
	w, h = body_radii(t)
	ca, sa = np.cos(a), np.sin(a)
	# a slow twist of lumps along it, like a morel's stem
	lump = 1.0 + 0.05 * np.sin(3.0 * a + 9.0 * t) * smooth(0.1, 0.3, t) * smooth(0.95, 0.8, t)
	h = h * lump * np.where(ca < 0, 1.0 + 0.10 * smooth(0.3, 0.6, t), 1.0)   # a fuller belly
	up = np.sign(ca) * np.abs(ca) ** 0.9 * h
	side = np.sign(sa) * np.abs(sa) ** 0.9 * w * lump
	P = np.stack([cx + nx * up, cy + ny * up, side], axis=-1)
	return P, None


def honeycomb(P):
	"""Round pores punched through the pale flesh, like a morel's stem or old bone: one in most
	cells (~3.5 cm apart), each its own size, with a slightly raised rim. Returns (pore, rim, cid)."""
	f1, f2, cid = cells(P * np.array([0.75, 1.0, 1.0]), 0.050, 2.0)
	rad = 0.22 + 0.30 * cid
	has = smooth(0.18, 0.26, cid)
	pore = smooth(rad, rad - 0.07, f1) * has
	rim = (smooth(rad + 0.14, rad, f1) * has - pore).clip(0.0, 1.0)
	return pore, rim, cid


def body_relief(a, t, P):
	pit, ridge, cid = honeycomb(P)
	m = smooth(0.04, 0.12, t) * smooth(0.99, 0.93, t)
	r = (-0.018 * pit * (0.6 + 0.4 * cid) + 0.003 * ridge) * m
	r = r + 0.0014 * pnoise(P * np.array([0.3, 1.0, 1.0]), 60.0)   # fibres running along the body
	return r + 0.0005 * pnoise(P, 220.0)


def build_closed(acc, fn, centre, rows, cols, rect, kind, group, weight_fn, relief=None):
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
	build_closed(acc, body_point, (0.0, 1.37, 0.0), rows, cols, RECTS["body"], BODY, 0.0, lambda a, t: t,
		body_relief if relief else None)


# --- the fans: Schizophyllum brackets, a half funnel concave on top -------------------------------
# A fan in its own frame: the root at the origin, +x forward, +z out along the span, +y up.
# u across the fan (0 back edge .. 1 front edge), t round its thickness: 0 underneath at the root,
# 0.5 the margin, 1 on top at the root. rho = distance from the root (0 .. 1 at the margin).
WING_L = 1.05       # root to margin along the span (m)
WING_TH = 1.30      # half the fan's opening angle (rad)
TAIL_L = 0.78
TAIL_TH = 0.40
GILLS = 58          # long gills across the fan
R_REF = WING_L      # the wing sculpt is built at full size, so relief is sized in metres


def fan_shape(x):
	"""Margin radius (fraction of L) across the fan, x in [-1, 1]: a broad lobed fan whose sides
	curve back into the root, so the surface closes on itself at x = +-1."""
	return np.maximum(1.0 - np.abs(x) ** 2.4, 0.0) ** 0.42


def fan_local(u, t, L, th, ruffle=1.0, seed=0.0):
	u = np.asarray(u, np.float64)
	t = np.asarray(t, np.float64)
	x = u * 2.0 - 1.0
	theta = x * th
	under = t < 0.5
	rho = np.where(under, 2.0 * t, 2.0 * (1.0 - t))
	rho = np.clip(rho, 0.0, 1.0)
	fs = fan_shape(x)
	lobes = 1.0 + 0.07 * np.sin(5.0 * theta + 0.7 + seed) + 0.035 * np.sin(11.0 * theta + 2.1 + seed) * ruffle
	R = L * fs * lobes
	d = rho * R
	# a trumpet: narrow where it grows from the body, flaring open toward the margin
	open_ = 0.22 + 0.78 * smooth(0.0, 0.8, rho) ** 0.7
	th_e = theta * open_
	px = d * np.sin(th_e)
	pz = d * np.cos(th_e)
	dn = d / L
	# thickness: a fat root thinning to a rounded margin, closing to nothing at the fan's sides
	T = (0.085 * (1.0 - rho) ** 1.6 + 0.016) * np.sqrt(np.maximum(1.0 - rho ** 12, 0.0)) * fs ** 0.5
	T = T * np.minimum(L / WING_L, 1.0) ** 0.5
	# a half funnel: the margin rises all round, most at the front and back edges; ruffled margin
	lift = L * (0.20 * dn ** 1.7 + 0.30 * rho ** 1.4 * x ** 2 * fs ** 0.3)
	lift = lift + L * ruffle * dn ** 3.5 * (0.050 * np.sin(8.0 * theta + 1.3 + seed) + 0.026 * np.sin(15.0 * theta + seed))
	# the margin is in-rolled: the last few cm curl down and under
	lift = lift - L * 0.05 * smooth(0.86, 1.0, rho)
	y = lift + np.where(under, -0.5 * T, 0.5 * T)
	P = np.stack([px, y, pz], axis=-1)
	return P, rho, theta, under


def gill_field(u, rho):
	"""Split gills underneath: long blades with a groove down each edge, short ones between."""
	ph = u * GILLS
	c = np.cos(TAU * ph)
	blade = np.maximum(c, 0.0) ** 6
	split = np.maximum(c, 0.0) ** 60                          # the groove along the blade's edge
	short = np.maximum(-c, 0.0) ** 6 * smooth(0.45, 0.6, rho)
	inner = smooth(0.06, 0.22, rho) * smooth(0.985, 0.93, rho)
	return (blade - 0.55 * split + 0.8 * short) * inner, blade * inner


def crust_mask(P, rho):
	"""Where the rust crust sits on top: the outer part of the fan, its inner edge ragged."""
	n = pnoise(P, 7.0, 3)
	patch = smooth(0.05, 0.35, pnoise(P, 9.0, 3, 4.0) + 0.3 * n)   # it breaks into patches inward
	band = smooth(0.62, 0.80, rho + 0.10 * n)
	inner = smooth(0.40, 0.62, rho + 0.10 * n) * patch
	return np.maximum(band, inner * 0.85) * smooth(0.975, 0.90, rho)


def top_ribs(u, rho):
	return np.maximum(np.cos(TAU * u * GILLS * 0.5), 0.0) ** 3 * smooth(0.08, 0.3, rho)


def lip_mask(rho, P):
	return smooth(0.86, 0.94, rho + 0.02 * pnoise(P, 30.0))


def fan_relief(u, t, P, rho, under):
	g, _ = gill_field(u, rho)
	r = 0.011 * g * under
	top = 1.0 - under
	f1, f2, cid = cells(P, 0.012, 4.0)
	gran = smooth(0.55, 0.15, f1) * (0.5 + 0.5 * cid)         # crust granules, ~1.2 cm
	cm = crust_mask(P, rho)
	r = r + top * (0.0035 * gran * cm)
	zones = np.cos(TAU * rho * 7.0 + 0.6 * pnoise(P, 6.0))      # concentric growth zones
	r = r + top * 0.0012 * zones * (1.0 - cm)
	fib = vnoise(u * 160.0, rho * 6.0, 0.5)                     # hairs running out from the root
	r = r + top * 0.0010 * fib
	r = r + top * 0.0018 * top_ribs(u, rho) * (1.0 - cm)         # the gills show through as ribs
	r = r + 0.0005 * pnoise(P, 180.0)
	return r


def wing_frame(side):
	"""The fan's frame in the body: root, and the rotations that place it. side -1 left, +1 right."""
	root = np.array([0.04, 1.46, 0.10 * side])
	return root, math.radians(16.0), math.radians(-6.0), math.radians(4.0)   # dihedral, sweep back, pitch


def wing_world(P, side):
	root, dihedral, sweep_back, pitch = wing_frame(side)
	Q = rot_x(P, -dihedral)               # the tip rises (z out, y up)
	Q = rot_y(Q, sweep_back)              # the tip sweeps back
	Q = rot_z(Q, pitch)                   # the front edge lifts a little
	Q = Q * np.array([1.0, 1.0, side])
	return Q + root


def build_fan(acc, rows, cols, rect, kind, group, place, L, th, ruffle, seed, relief=False):
	j, i = np.mgrid[0:rows + 1, 0:cols + 1]
	t = j / rows
	u = i / cols
	Pl, rho, theta, under = fan_local(u, t, L, th, ruffle, seed)
	if relief:
		# relief along the local normal, then place; sculpt with the same functions as the paint
		Pl = Pl +_fan_normals(Pl, under) * fan_relief(u, t, Pl, rho, under.astype(np.float64))[..., None]
	P = place(Pl)
	N = _fan_normals(P, under, world=True, place=place)
	acc.grid(P, N, rect_uv(rect, u, t), data_arr(kind, rho, group, t.shape), wrap=False)


def _fan_normals(P, under, world=False, place=None):
	"""Normals of the fan's grid that point away from the slab: down underneath, up on top."""
	N = grid_normals(P, wrap=False)
	if world:
		up = place(np.array([[0.0, 1.0, 0.0]])) - place(np.array([[0.0, 0.0, 0.0]]))
		up = up[0] / np.linalg.norm(up[0])
	else:
		up = np.array([0.0, 1.0, 0.0])
	# the grid runs round the slab continuously, so one global sign orients it: up on the top half
	want = np.where(under, -1.0, 1.0)
	s = np.sign(np.mean(np.einsum("...i,i->...", N, up) * want))
	return N * (1.0 if s >= 0 else -1.0)


def build_wing(acc, side, rows, cols, relief=False):
	g = 0.0 if side < 0 else 1.0
	build_fan(acc, rows, cols, RECTS["wing"], WING, g, lambda P: wing_world(P, side), WING_L, WING_TH, 1.0, 0.0, relief)


def tail_world(P):
	"""The streamer: a long narrow fan out of the tail, trailing back and a little down, twisted."""
	Q = rot_y(P, -PI / 2)                 # its span runs back (-x)
	Q = rot_x(Q, math.radians(-12.0))
	Q = rot_z(Q, math.radians(9.0))      # droops
	return Q + np.array([-0.50, 1.38, 0.0])


def build_tail(acc, rows, cols, relief=False):
	build_fan(acc, rows, cols, RECTS["tail"], TAIL, 0.0, tail_world, TAIL_L, TAIL_TH, 1.4, 2.0, relief)


# --- the bombs: earthball spore sacs slung under the belly on gold cords ------------------------
BOMBS = [  # (centre, radius)
	((0.10, 1.04, 0.07), 0.090),
	((-0.06, 1.00, -0.06), 0.098),
	((-0.20, 1.07, 0.05), 0.078),
	((0.02, 0.92, 0.00), 0.070),
]
BOMB_REF = 0.09


def sphere_point(a, t):
	th = PI * np.asarray(t, np.float64)
	# slightly pear-shaped: narrower at the top where the cord holds it
	r = 1.0 - 0.10 * smooth(0.5, 0.0, t)
	P = np.stack([np.sin(th) * np.cos(a) * r, -np.cos(th), np.sin(th) * np.sin(a) * r], axis=-1)
	return P * np.array([1.0, -1.0, 1.0]), None   # t = 0 at the top


def warts(P):
	f1, f2, cid = cells(P, 0.022, 5.0)
	return smooth(0.62, 0.20, f1), smooth(0.10, 0.0, f2 - f1), cid


def bomb_relief(a, t, P, c, r):
	Pm = (P - c) / r * BOMB_REF
	w, crack, cid = warts(Pm)
	return 0.0055 * w * (0.6 + 0.4 * cid) - 0.0015 * crack + 0.0004 * pnoise(Pm, 200.0)


def build_bomb(acc, k, rows, cols, relief=False, origin=None):
	c, r = BOMBS[k]
	c = np.asarray(origin if origin is not None else c, np.float64)
	if origin is not None:
		r = BOMB_REF
	fn = lambda a, t: ((sphere_point(a, t)[0] * r) + c, None)
	rel = (lambda a, t, P: bomb_relief(a, t, P, c, r)) if relief else None
	build_closed(acc, fn, c, rows, cols, RECTS["bomb"], BOMB, float(k), lambda a, t: t, rel)


def cord_path(k):
	c, r = BOMBS[k]
	c = np.asarray(c)
	top = c + np.array([0.0, r * 0.92, 0.0])
	root = np.array([c[0] * 0.6 - 0.04, 1.27, c[2] * 0.5])
	mid = (root + top) * 0.5 + np.array([0.02, 0.0, 0.01])
	return [tuple(root + np.array([0.0, 0.04, 0.0])), tuple(root), tuple(mid), tuple(top), tuple(top - np.array([0.0, 0.02, 0.0]))]


CORD_RADII = [0.012, 0.010, 0.007, 0.008, 0.010]


def cord_relief(t, ang, P):
	return 0.0006 * pnoise(P, 160.0)


def build_cord(acc, k, sides, samples, relief=False):
	sweep(acc, cord_path(k), CORD_RADII, sides, samples, RECTS["cord"], CORD, float(k), lambda tt: tt,
		relief=cord_relief if relief else None)


# --- whole models ------------------------------------------------------------------------------

def build_lod(lod):
	acc = Acc()
	build_body(acc, *[(28, 22), (14, 12), (8, 8)][lod])
	wr, wc = [(28, 44), (14, 22), (8, 12)][lod]   # even rows: one lands on the margin (t = 0.5)
	for side in (-1.0, 1.0):
		build_wing(acc, side, wr, wc)
	build_tail(acc, *[(20, 16), (10, 8), (6, 5)][lod])
	br, bc = [(8, 12), (5, 7), (4, 5)][lod]
	bombs = [range(len(BOMBS)), range(len(BOMBS)), (0, 1, 3)][lod]
	for k in bombs:
		build_bomb(acc, k, br, bc)
	cs, cn = [(4, 6), (3, 3), (3, 2)][lod]
	for k in bombs:
		if lod < 2:
			build_cord(acc, k, cs, cn)
	return acc


# --- paint -------------------------------------------------------------------------------------

CREAM = (0.94, 0.88, 0.75)
CREAM_PALE = (0.97, 0.93, 0.84)
TAN = (0.70, 0.57, 0.42)
GILL_SHADE = (0.50, 0.38, 0.30)
GROOVE = (0.62, 0.48, 0.45)        # Schizophyllum gills are a pinkish grey where they split
RUST_DEEP = (0.32, 0.09, 0.04)
RUST = (0.62, 0.22, 0.08)
ORANGE = (0.86, 0.46, 0.15)
GOLD = (0.93, 0.70, 0.34)
PIT = (0.17, 0.10, 0.06)
PIT_WARM = (0.42, 0.26, 0.11)
BOMB_DARK = (0.06, 0.045, 0.035)
BOMB_WART = (0.22, 0.15, 0.10)
FLECK = (0.80, 0.56, 0.16)


def paint_fan(albedo, orm, rect, L, th, ruffle, seed, size, rust_bias=0.0):
	sl, u, v = texel_grid(rect, size)
	P, rho, theta, under = fan_local(u, v, L, th, ruffle, seed)
	und = under.astype(np.float64)
	n1 = pnoise(P, 4.0, 3) * 0.5 + 0.5
	# underneath: split gills, cream on the blades, shaded between, grey-pink in each split
	g, blade = gill_field(u, rho)
	ph = u * GILLS
	c = np.cos(TAU * ph)
	split = np.maximum(c, 0.0) ** 60 * smooth(0.06, 0.22, rho) * smooth(0.985, 0.93, rho)
	between = 1.0 - np.clip(blade + 0.8 * np.maximum(-c, 0.0) ** 6 * smooth(0.45, 0.6, rho), 0.0, 1.0)
	gl = ramp([(0.0, CREAM_PALE), (0.45, CREAM), (0.8, TAN), (1.0, GILL_SHADE)],
		np.clip(0.15 + 0.7 * between * smooth(0.06, 0.25, rho) + 0.15 * (n1 - 0.5), 0.0, 1.0))
	gl = mix(gl, GROOVE, split * 0.7)
	gl = mix(gl, mix(GOLD, RUST, smooth(0.96, 1.0, rho)), smooth(0.93, 0.99, rho) * 0.8)   # the rust lip shows under the edge
	# on top: growth zones near the root, a rust crust outward behind a cream lip
	f1, f2, cid = cells(P, 0.012, 4.0)
	gran = smooth(0.55, 0.15, f1) * (0.5 + 0.5 * cid)
	cm = np.clip(crust_mask(P, rho) + rust_bias * smooth(0.1, 0.4, rho), 0.0, 1.0)
	zones = 0.5 + 0.5 * np.cos(TAU * rho * 7.0 + 0.6 * pnoise(P, 6.0))
	fib = vnoise(u * 160.0, rho * 6.0, 0.5)
	inner = ramp([(0.0, TAN), (0.5, (0.84, 0.74, 0.58)), (1.0, CREAM)],
		np.clip(0.45 + 0.18 * zones + 0.12 * fib + 0.25 * top_ribs(u, rho) + 0.2 * (n1 - 0.5), 0.0, 1.0))
	crust = ramp([(0.0, RUST_DEEP), (0.45, RUST), (0.8, ORANGE), (1.0, GOLD)],
		np.clip(0.25 + 0.55 * gran + 0.25 * (n1 - 0.5) + 0.1 * fib, 0.0, 1.0))
	top = mix(inner, crust, cm)
	lip = lip_mask(rho, P)
	top = mix(top, mix(GOLD, CREAM_PALE, smooth(0.90, 0.97, rho)), lip * 0.9)
	# a few pores where the fan grows out of the honeycomb body
	pit, _, pcid = honeycomb(P + np.array([3.0, 0.0, 0.0]))
	stalk = smooth(0.28, 0.08, rho)
	col = mix(top, gl, und)
	col = mix(col, mix(PIT, PIT_WARM, pcid), pit * stalk * 0.85)
	albedo[sl] = col
	orm[sl + (1,)] = np.where(under, 0.62 + 0.12 * between, 0.70 + 0.16 * cm * gran - 0.08 * lip) + 0.1 * pit * stalk
	orm[sl + (2,)] = 0.0


def paint(size):
	albedo = np.zeros((size, size, 3))
	albedo[...] = CREAM
	orm = np.ones((size, size, 4))
	orm[..., 1] = 0.6
	orm[..., 2] = 0.0
	paint_fan(albedo, orm, RECTS["wing"], WING_L, WING_TH, 1.0, 0.0, size)
	paint_fan(albedo, orm, RECTS["tail"], TAIL_L, TAIL_TH, 1.4, 2.0, size, rust_bias=0.5)

	# body: the morel honeycomb, pale waxy ridges and dark pits, warmer underneath, a rust nose
	sl, u, v = texel_grid(RECTS["body"], size)
	a = u * TAU - PI
	P, _ = body_point(a, v)
	pit, ridge, cid = honeycomb(P)
	m = smooth(0.04, 0.12, v) * smooth(0.99, 0.93, v)
	n1 = pnoise(P, 6.0, 3) * 0.5 + 0.5
	ground = ramp([(0.0, (0.80, 0.66, 0.48)), (0.6, CREAM), (1.0, CREAM_PALE)], np.clip(0.55 + 0.3 * np.cos(a) + 0.3 * (n1 - 0.5), 0.0, 1.0))
	pitc = ramp([(0.0, PIT), (0.6, (0.30, 0.18, 0.09)), (1.0, PIT_WARM)], cid)
	col = mix(ground, pitc, pit * m * (0.75 + 0.25 * cid))
	col = mix(col, CREAM_PALE, ridge * m * 0.4)
	col = mix(col, RUST, smooth(0.92, 0.995, v) * 0.6 + smooth(0.10, 0.02, v) * 0.5)
	albedo[sl] = col
	orm[sl + (1,)] = np.clip(0.42 + 0.42 * pit * m + 0.06 * (n1 - 0.5), 0.2, 0.95)

	# bombs: near-black earthballs, warts glossier, gold flecks in the cracks between them
	sl, u, v = texel_grid(RECTS["bomb"], size)
	a = u * TAU - PI
	P = sphere_point(a, v)[0] * BOMB_REF
	w, crack, cid = warts(P)
	f1, _, fid = cells(P, 0.008, 9.0)
	fleck = smooth(0.30, 0.10, f1) * smooth(0.75, 0.80, fid) * (1.0 - w)
	col = ramp([(0.0, BOMB_DARK), (0.6, (0.13, 0.09, 0.06)), (1.0, BOMB_WART)], np.clip(0.2 + 0.8 * w * (0.6 + 0.4 * cid), 0.0, 1.0))
	col = mix(col, (0.34, 0.24, 0.14), crack * 0.5)
	col = mix(col, FLECK, fleck)
	col = mix(col, (0.55, 0.42, 0.24), smooth(0.12, 0.0, v) * 0.6)   # pale where the cord grips
	albedo[sl] = col
	orm[sl + (1,)] = np.clip(0.55 - 0.25 * w + 0.25 * crack - 0.2 * fleck, 0.18, 0.9)
	orm[sl + (2,)] = 0.7 * fleck

	# cords: gold hyphae, paler at the bomb
	sl, u, v = texel_grid(RECTS["cord"], size)
	P = tube_points(cord_path(1), CORD_RADII, u, v)
	fib = pnoise(P * np.array([1.0, 0.25, 1.0]), 120.0, 2)
	col = ramp([(0.0, (0.86, 0.70, 0.40)), (0.5, GOLD), (1.0, (0.95, 0.86, 0.66))], v)
	albedo[sl] = col * (0.92 + 0.1 * fib[..., None])
	orm[sl + (1,)] = 0.5 + 0.08 * fib
	orm[sl + (2,)] = 0.1
	return albedo, orm


# --- the bake ----------------------------------------------------------------------------------

def main():
	os.makedirs(OUT, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	setup_cycles(TAG, bool(OPT.get("cpu")), ao_distance=0.12)
	log(TAG, "building sculpt")
	hi, lo = {}, {}
	BOMB_O = (0.0, 6.0, 0.0)   # the sculpt bomb hangs alone, away from the body
	acc = Acc(); build_body(acc, 520, 640, relief=True); hi["body"] = acc.obj("hi_body")
	acc = Acc(); build_wing(acc, 1.0, 640, 760, relief=True); hi["wing"] = acc.obj("hi_wing")
	acc = Acc(); build_tail(acc, 400, 300, relief=True); hi["tail"] = acc.obj("hi_tail")
	acc = Acc(); build_bomb(acc, 0, 240, 360, relief=True, origin=BOMB_O); hi["bomb"] = acc.obj("hi_bomb")
	acc = Acc(); build_cord(acc, 1, 16, 120, relief=True); hi["cord"] = acc.obj("hi_cord")
	shade = Acc()   # the rest only shades
	build_wing(shade, -1.0, 40, 60)
	for k in range(len(BOMBS)):
		build_bomb(shade, k, 12, 16)
		build_cord(shade, k, 6, 10)
	shade = shade.obj("ao_rest")
	log(TAG, "sculpt: %d faces" % sum(len(o.data.polygons) for o in hi.values()))
	acc = Acc(); build_body(acc, 140, 180); lo["body"] = acc.obj("lo_body")
	acc = Acc(); build_wing(acc, 1.0, 160, 240); lo["wing"] = acc.obj("lo_wing")
	acc = Acc(); build_tail(acc, 100, 80); lo["tail"] = acc.obj("lo_tail")
	acc = Acc(); build_bomb(acc, 0, 60, 90, origin=BOMB_O); lo["bomb"] = acc.obj("lo_bomb")
	acc = Acc(); build_cord(acc, 1, 8, 40); lo["cord"] = acc.obj("lo_cord")
	for ob in lo.values():
		hide_from_rays(ob)
	parts = {
		"body": {"low": lo["body"], "normal_from": [hi["body"]], "ao_from": [hi["body"], hi["wing"], hi["tail"], shade],
			"reach": (0.018, 0.034), "poles": (0.03, 0.97)},
		"wing": {"low": lo["wing"], "normal_from": [hi["wing"]], "ao_from": [hi["wing"], hi["body"], shade],
			"reach": (0.008, 0.016), "poles": (0.02, 0.98)},
		"tail": {"low": lo["tail"], "normal_from": [hi["tail"]], "ao_from": [hi["tail"], hi["body"]],
			"reach": (0.006, 0.012), "poles": (0.03, 0.97)},
		"bomb": {"low": lo["bomb"], "normal_from": [hi["bomb"]], "ao_from": [hi["bomb"]], "reach": (0.008, 0.016),
			"poles": (0.03, 0.97)},
		"cord": {"low": lo["cord"], "normal_from": [hi["cord"]], "ao_from": [hi["cord"]], "reach": (0.003, 0.006),
			"poles": None},
	}
	normal, ao, u, v, masks = bake_atlas(parts, RECTS, SIZE, TAG)
	log(TAG, "painting")
	albedo, orm = paint(SIZE)
	orm[..., 0] = ao
	sl, u, v = texel_grid(RECTS["cord"], SIZE)
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
		ob = build_lod(lod).obj("Glider_" + name)
		stats.append("%s %d" % (name, tri_count(ob)))
		export_glb([ob], os.path.join(OUT, "%s_%s.glb" % (TAG, name)))
	log(TAG, "done: " + ", ".join(stats))


def preview(path):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	ob = build_lod(int(OPT.get("lod", 0))).obj("preview")
	ob.color = (0.86, 0.74, 0.60, 1.0)
	log(TAG, "preview tris %d" % tri_count(ob))
	preview_render([ob], path, target=(-0.05, 1.3, 0.0), scale=3.0,
		views=(("side", 0.0, 0.12), ("q", 0.8, 0.5), ("top", PI / 2, 1.5), ("front", PI / 2, 0.15)))


# --- the rig: bones for UniMate, and the skinning the shader repeats --------------------------
# Bird-style bone names (like UniMate's eagle example) so its joint labeller reads them as a bird.
# Each part blends between neighbouring bones along one coordinate: the body by x, a wing or the
# streamer by its data-UV weight (distance from the root). A chain is [(bone, centre), ...]; a vertex
# between two centres blends linearly between those two bones (two-bone linear blend skinning).

def wing_axis_point(side, rho):
	"""A point on the wing's mid-surface along its centre line, rho from the root (0) to the margin."""
	rho = np.atleast_1d(np.asarray(rho, np.float64))
	Pu, _, _, _ = fan_local(np.full_like(rho, 0.5), rho * 0.5, WING_L, WING_TH)
	Pt, _, _, _ = fan_local(np.full_like(rho, 0.5), 1.0 - rho * 0.5, WING_L, WING_TH)
	return wing_world((Pu + Pt) * 0.5, side)


def tail_axis_point(rho):
	rho = np.atleast_1d(np.asarray(rho, np.float64))
	Pu, _, _, _ = fan_local(np.full_like(rho, 0.5), rho * 0.5, TAIL_L, TAIL_TH, 1.4, 2.0)
	Pt, _, _, _ = fan_local(np.full_like(rho, 0.5), 1.0 - rho * 0.5, TAIL_L, TAIL_TH, 1.4, 2.0)
	return tail_world((Pu + Pt) * 0.5)


def rig_bones():
	"""[(name, parent, head, tail)] in game space (Y up, +X forward)."""
	b = [
		("Bip01_Pelvis", None, (-0.30, 1.385, 0.0), (-0.08, 1.39, 0.0)),
		("Bip01_Spine", "Bip01_Pelvis", (-0.08, 1.39, 0.0), (0.10, 1.38, 0.0)),
		("Bip01_Spine1", "Bip01_Spine", (0.10, 1.38, 0.0), (0.28, 1.345, 0.0)),
		("Bip01_Neck", "Bip01_Spine1", (0.28, 1.345, 0.0), (0.40, 1.30, 0.0)),
		("Bip01_Head", "Bip01_Neck", (0.40, 1.30, 0.0), (0.53, 1.235, 0.0)),
		("BN_Tai_01", "Bip01_Pelvis", (-0.30, 1.385, 0.0), tuple(tail_axis_point(0.0)[0])),
		("BN_Tai_02", "BN_Tai_01", tuple(tail_axis_point(0.0)[0]), tuple(tail_axis_point(0.45)[0])),
		("BN_Tai_03", "BN_Tai_02", tuple(tail_axis_point(0.45)[0]), tuple(tail_axis_point(1.0)[0])),
	]
	for side, s in ((-1.0, "L"), (1.0, "R")):
		p = wing_axis_point(side, [0.0, 0.33, 0.66, 1.0])
		b.append(("BN_Wing_%s_01" % s, "Bip01_Spine1", tuple(p[0]), tuple(p[1])))
		b.append(("BN_Wing_%s_02" % s, "BN_Wing_%s_01" % s, tuple(p[1]), tuple(p[2])))
		b.append(("BN_Wing_%s_03" % s, "BN_Wing_%s_02" % s, tuple(p[2]), tuple(p[3])))
	return b


BONE_NAMES = [b[0] for b in rig_bones()]
BI = {n: i for i, n in enumerate(BONE_NAMES)}
# chains: (bone index, centre). The body by vertex x; the streamer and the wings by their weight.
BODY_CHAIN = [(BI["BN_Tai_01"], -0.40), (BI["Bip01_Pelvis"], -0.19), (BI["Bip01_Spine"], 0.01),
	(BI["Bip01_Spine1"], 0.19), (BI["Bip01_Neck"], 0.34), (BI["Bip01_Head"], 0.47)]
TAIL_CHAIN = [(BI["BN_Tai_01"], -0.25), (BI["BN_Tai_02"], 0.22), (BI["BN_Tai_03"], 0.72)]
WING_CHAIN = {s: [(BI["Bip01_Spine1"], -0.12), (BI["BN_Wing_%s_01" % s], 0.165), (BI["BN_Wing_%s_02" % s], 0.50),
	(BI["BN_Wing_%s_03" % s], 0.83)] for s in ("L", "R")}
BOMB_BONE = BI["Bip01_Spine"]


def chain_weights(chain, x):
	"""(bone a, bone b, f): blend (1 - f) a + f b for coordinate x along the chain."""
	cs = [c for _, c in chain]
	if x <= cs[0]:
		return chain[0][0], chain[0][0], 0.0
	for k in range(len(cs) - 1):
		if x <= cs[k + 1]:
			return chain[k][0], chain[k + 1][0], (x - cs[k]) / (cs[k + 1] - cs[k])
	return chain[-1][0], chain[-1][0], 0.0


def vertex_skin(kind, weight, group, pos):
	"""The skinning the shader does, for one vertex (game-space pos)."""
	if kind == BODY:
		return chain_weights(BODY_CHAIN, pos[0])
	if kind == WING:
		return chain_weights(WING_CHAIN["L" if group < 0.5 else "R"], weight)
	if kind == TAIL:
		return chain_weights(TAIL_CHAIN, weight)
	return BOMB_BONE, BOMB_BONE, 0.0


def rig(path):
	"""Write the rig GLB UniMate reads (the close mesh skinned to an armature) and rig.json
	(bones, chains) beside it."""
	import json
	bpy.ops.wm.read_factory_settings(use_empty=True)
	ob = build_lod(0).obj("Glider")
	bones = rig_bones()
	arm_data = bpy.data.armatures.new("GliderRig")
	arm = bpy.data.objects.new("GliderRig", arm_data)
	bpy.context.scene.collection.objects.link(arm)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	from mathutils import Vector
	eb = {}
	for name, parent, head, tail in bones:
		e = arm_data.edit_bones.new(name)
		e.head = Vector(g2b(np.array(head)))
		e.tail = Vector(g2b(np.array(tail)))
		e.roll = 0.0
		if parent:
			e.parent = eb[parent]
			e.use_connect = False
		eb[name] = e
	bpy.ops.object.mode_set(mode="OBJECT")
	# skin weights from the data UV, the way the shader will read it
	me = ob.data
	data = me.uv_layers["data"].data
	vdata = np.zeros((len(me.vertices), 2))
	li = np.zeros(len(me.loops), np.int64)
	me.loops.foreach_get("vertex_index", li)
	du = np.zeros(len(me.loops) * 2, np.float32)
	data.foreach_get("uv", du)
	vdata[li] = du.reshape(-1, 2)
	groups = [ob.vertex_groups.new(name=n) for n in BONE_NAMES]
	for vi, v in enumerate(me.vertices):
		kind = int(math.floor(vdata[vi, 0] + 0.001))
		w = min(max((vdata[vi, 0] - kind) / 0.98, 0.0), 1.0)
		g = vdata[vi, 1]
		pb = v.co
		pos = (pb[0], pb[2], -pb[1])   # Blender -> game
		a, b, f = vertex_skin(kind, w, g, pos)
		groups[a].add([vi], 1.0 - f, "REPLACE")
		if b != a and f > 0.0:
			groups[b].add([vi], f, "ADD")
	mod = ob.modifiers.new("Armature", "ARMATURE")
	mod.object = arm
	ob.parent = arm
	os.makedirs(os.path.dirname(path), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	ob.select_set(True)
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_materials="NONE",
		export_yup=True, export_apply=False, export_skins=True, export_animations=False)
	spec = {"bones": [{"name": n, "parent": p, "head": list(map(float, h)), "tail": list(map(float, t))} for n, p, h, t in bones],
		"body_chain": BODY_CHAIN, "tail_chain": TAIL_CHAIN, "wing_chain": WING_CHAIN, "bomb_bone": BOMB_BONE,
		"bombs": [list(map(float, c)) for c, _ in BOMBS]}
	os.makedirs(os.path.join(OUT, "rig"), exist_ok=True)
	with open(os.path.join(OUT, "rig", "rig.json"), "w") as fh:
		json.dump(spec, fh, indent=1)
	log(TAG, "rig: %d bones -> %s" % (len(bones), path))


if __name__ == "__main__":
	if OPT.get("preview"):
		preview(os.path.abspath(OPT["preview"]))
	elif OPT.get("rig"):
		rig(os.path.abspath(OPT["rig"]))
	else:
		main()
