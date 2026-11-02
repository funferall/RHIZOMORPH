"""Muscarine Spitter art build, run headless in Blender 4.2:

  blender -b --factory-startup -P tools/blender/spitter_build.py -- [--out=art/spitter] [--size=1024] [--cpu]

The Amanita Court's ranged gunner, after reference_images/amanita_court_roster.jpg: a tall,
top-heavy sporeling that waddles on four garlic-clove volva bulbs. A swollen, fibrous stalk
leans back and curls up into a squeezed, hooked cone of a cap, scarlet at the tip and
orange at the rim, with white warts. The cap's opening turns forward and down over cream
gills, and it spits muscarine from a golden throat where the stalk meets the gills.

Builds a high-detail sculpt (gill lamellae, raised warts, stalk fibres and scale rings,
lobed bulbs) and three low-poly game meshes sharing one atlas. Cycles bakes normals and
ambient occlusion; colour, roughness and glow are painted from the same functions that
shaped the sculpt.

Writes spitter_{close,battle,distant}.glb and spitter_{albedo,normal,orm}.png
(orm: R occlusion, G roughness, B glow, A unused).
Data UV: u = kind + 0.98 * gait weight (0 bulb, 1 stalk, 2 cap and gills), v = the bulb's gait
pair (0 or 1). The shader bends the stalk by height and moves the cap rigidly about NECK, so
the rig constants it needs are printed at the end.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(__file__))
from unitlib import (TAU, MeshData, bake, data_uv, export_glb, grid_surface, hide_from_rays, lerp, log, mix3,
	rect_uv, resample, save_png, setup_cycles, smooth, tube)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else True) for a in ARGS}
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, OPT.get("out", "art/spitter"))
SIZE = int(OPT.get("size", 1024))
TAG = "spitter"

# --- shape --------------------------------------------------------------------------------
# The cap is a lathe in its own frame (r out from the axis, h up it), traced from the gill
# centre out to the rim, round the lip and up the cone to the tip. Then it is squeezed side
# to side, bent back along its length into a hook, tilted back and set on the stalk.
CAP_PROFILE = [(0.0, 0.135), (0.09, 0.125), (0.18, 0.10), (0.27, 0.066), (0.34, 0.032), (0.385, 0.008),
	(0.41, 0.022), (0.419, 0.056), (0.406, 0.10), (0.38, 0.18), (0.345, 0.28), (0.302, 0.39), (0.253, 0.50),
	(0.198, 0.61), (0.143, 0.71), (0.092, 0.80), (0.046, 0.88), (0.0, 0.95)]
GILL_POINT, LIP_POINT = 5, 8   # profile points ending the gills and the lip
CAP_H = 1.0
RIM_R = 0.385
GILL_TOP = 0.135               # the gill centre, where the stalk meets the cap
SQUEEZE, SQUEEZE_TIP = 0.80, 0.24   # side-to-side squeeze at the rim, and how much more at the tip
CAP_TILT = 0.62                # the opening faces forward and down by this much (rad)
CAP_BEND = 0.46                # and the cone hooks back this much more by its tip
NECK = Vector((-0.28, 1.34, 0.0))
# The stalk: swollen at the foot, leaning back, then curling up under the cap.
STALK = [(0.03, 0.04, 0.0), (0.03, 0.10, 0.0), (0.02, 0.27, 0.0), (-0.04, 0.48, 0.0), (-0.13, 0.70, 0.0),
	(-0.22, 0.90, 0.0), (-0.28, 1.06, 0.0), (-0.30, 1.20, 0.0)]
STALK_RADII = [0.004, 0.17, 0.24, 0.22, 0.15, 0.105, 0.09, 0.088, 0.105, 0.07]
# Four volva bulbs, garlic cloves lying with their points out and down: (angle, scale, gait pair).
# Diagonal pairs step together.
BULBS = [(math.radians(42), 1.0, 0), (math.radians(136), 0.93, 1), (math.radians(224), 0.97, 0),
	(math.radians(316), 1.04, 1)]
BULB_PROFILE = [(0.0, 0.0), (0.075, 0.014), (0.13, 0.06), (0.163, 0.13), (0.172, 0.21), (0.162, 0.29),
	(0.13, 0.37), (0.083, 0.43), (0.034, 0.474), (0.012, 0.49), (0.0, 0.50)]
BULB_L = 0.50
BULB_DROOP = 0.36
BULB_LOBES = 5
BAKE_BULB = 0

# --- atlas regions (Blender UV, v up) ----------------------------------------------------------
CAP_RECT = (0.006, 0.400, 0.994, 0.994)
STALK_RECT = (0.006, 0.006, 0.380, 0.388)
BULB_RECT = (0.392, 0.006, 0.994, 0.388)


# --- the cap's frame -------------------------------------------------------------------------------

def bend_angle(h):
	return CAP_BEND * min(max(h / CAP_H, 0.0), 1.0) ** 1.6


_SPINE_N = 1500
_spine = []


def spine(h):
	"""The bent axis: where height h along the cap ends up, before the tilt."""
	dh = CAP_H * 1.05 / _SPINE_N
	if not _spine:
		x = y = 0.0
		_spine.append((x, y))
		for i in range(_SPINE_N):
			p = bend_angle((i + 0.5) * dh)
			x -= math.sin(p) * dh
			y += math.cos(p) * dh
			_spine.append((x, y))
	f = min(max(h / dh, 0.0), _SPINE_N - 1e-6)
	i = int(f)
	t = f - i
	return lerp(_spine[i][0], _spine[i + 1][0], t), lerp(_spine[i][1], _spine[i + 1][1], t)


def squeeze(h):
	return SQUEEZE - SQUEEZE_TIP * min(max(h / CAP_H, 0.0), 1.0) ** 1.4


def tilt(x, y):
	c, s = math.cos(CAP_TILT), math.sin(CAP_TILT)
	return x * c - y * s, x * s + y * c


def cap_local(a, r, h):
	"""The cap in its own frame, squeezed but not yet bent: a = 0 faces forward."""
	b = 1.0 + 0.022 * noise.noise(Vector((math.cos(a) * 1.6, math.sin(a) * 1.6, h * 2.5 + 3.0)))
	return Vector((r * b * math.cos(a), h, r * b * math.sin(a) * squeeze(h)))


def cap_place(q):
	phi = bend_angle(q.y)
	cx, cy = spine(q.y)
	x, y = tilt(cx + math.cos(phi) * q.x, cy + math.sin(phi) * q.x)
	return Vector((CAP_ORIGIN.x + x, CAP_ORIGIN.y + y, q.z))


def cap_dir(n, h):
	phi = bend_angle(h)
	c, s = math.cos(phi), math.sin(phi)
	x, y = tilt(n.x * c - n.y * s, n.x * s + n.y * c)
	return Vector((x, y, n.z))


_gx, _gy = tilt(*spine(GILL_TOP))
CAP_ORIGIN = Vector((NECK.x - _gx, NECK.y - _gy, 0.0))   # the rim's centre
CAP_UP = Vector((-math.sin(CAP_TILT), math.cos(CAP_TILT), 0.0))


def _profile_s(points):
	dense = resample(CAP_PROFILE, 3000)
	return [min(dense, key=lambda d: math.dist(d[0], CAP_PROFILE[k]))[1] for k in points]


S_GILL, S_LIP = _profile_s([GILL_POINT, LIP_POINT])


# --- surface functions: the sculpt's relief and the painted maps come from the same place ---------

N_GILL = 76
GILL_DEPTH = 0.014
WART_HEIGHT = 0.010


def gill_height(a, rr):
	"""1 on a gill's edge, 0 deep between gills. Short gills fill in toward the rim."""
	g = abs(math.cos(N_GILL * a * 0.5)) ** 4
	g2 = abs(math.sin(N_GILL * a * 0.5)) ** 4 * smooth(0.45, 0.62, rr)
	return max(g, 0.85 * g2)


def gill_fade(rr):
	return smooth(0.22, 0.34, rr) * smooth(1.0, 0.93, rr)


def wart(q, k):
	"""A raised white wart (0..1) at local cap point q; k runs 0 at the rim to 1 at the tip."""
	d, pts = noise.voronoi(q * 13.0, distance_metric="DISTANCE", exponent=2.5)
	cell = noise.noise(pts[0] * 0.71 + Vector((3.1, 1.7, 0.3)))
	rad = 0.37 * (0.78 + 0.32 * cell) * (1.0 - 0.45 * k)
	x = d[0] / rad
	edge = 0.06 * noise.noise(q * 90.0)
	return smooth(1.0 + edge, 0.55, x) ** 0.7


def cap_fibre(a, h):
	return noise.noise(Vector((math.cos(a) * 7.0, h * 1.4, math.sin(a) * 7.0)))


def cap_relief(a, prof):
	(r, h), s = prof
	if s <= S_GILL:
		rr = r / RIM_R
		return -GILL_DEPTH * (1.0 - gill_height(a, rr)) * gill_fade(rr)
	if s < S_LIP:
		return 0.0
	w = wart(cap_local(a, r, h), h / CAP_H) * smooth(S_LIP, S_LIP + 0.05, s)
	return WART_HEIGHT * w + 0.0015 * cap_fibre(a, h)


def stalk_fibre(a, t):
	return noise.noise(Vector((math.cos(a) * 7.0, math.sin(a) * 7.0, t * 3.5)))


def stalk_scales(a, t):
	"""Ragged rings of scales round the swollen foot, the remains of the universal veil."""
	band = smooth(0.06, 0.14, t) * smooth(0.44, 0.28, t)
	n = noise.noise(Vector((math.cos(a) * 5.0, math.sin(a) * 5.0, t * 22.0)))
	ring = max(0.0, math.sin(t * 95.0 + 2.5 * n)) ** 3
	patch = smooth(-0.1, 0.3, noise.noise(Vector((math.cos(a) * 3.0, math.sin(a) * 3.0, t * 6.0 + 11.0))))
	return band * ring * patch


def stalk_relief(t, a, p):
	return 0.003 * stalk_fibre(a, t) + 0.007 * stalk_scales(a, t)


def bulb_lobe(a, l):
	return math.cos(BULB_LOBES * a) * math.sin(math.pi * min(max(l / BULB_L, 0.0), 1.0))


def bulb_streak(a, l):
	return noise.noise(Vector((math.cos(a) * 14.0, math.sin(a) * 14.0, l * 5.0)))


# --- part builders ------------------------------------------------------------------------------

def build_cap(md, rows, cols, relief=False):
	pts = resample(CAP_PROFILE, rows)
	data = data_uv(2)

	def point(i, j):
		a = TAU * i / cols + math.pi   # the seam runs up the back
		(r, h), s = pts[j]
		jp, jm = pts[min(j + 1, rows)][0], pts[max(j - 1, 0)][0]
		tr, th = jp[0] - jm[0], jp[1] - jm[1]
		n = Vector((th * math.cos(a), -tr, th * math.sin(a) / squeeze(h)))
		return cap_place(cap_local(a, r, h)), cap_dir(n, h)

	rel = (lambda i, j, p, n: cap_relief(TAU * i / cols + math.pi, pts[j])) if relief else None
	grid_surface(md, rows, cols, point, lambda i, j: rect_uv(CAP_RECT, i / cols, pts[j][1]), lambda i, j: data,
		relief=rel)


def stalk_path():
	return [Vector(p) for p in STALK] + [NECK.copy(), NECK + CAP_UP * 0.08]


def build_stalk(md, sides, samples, relief=False):
	tube(md, stalk_path(), STALK_RADII, sides, samples, STALK_RECT, 1, lambda t: 0.0, 0,
		relief=stalk_relief if relief else None)


def bulb_frame(k):
	theta, scale, pair = BULBS[k]
	axis = Vector((math.cos(theta) * math.cos(BULB_DROOP), -math.sin(BULB_DROOP), math.sin(theta) * math.cos(BULB_DROOP)))
	side = Vector((0.0, 1.0, 0.0)).cross(axis).normalized()
	up = axis.cross(side).normalized()
	base = Vector((math.cos(theta) * 0.12, 0.0, math.sin(theta) * 0.12))
	low = min(bulb_local(base, axis, up, side, scale, TAU * i / 48, r, l).y
		for (r, l), _ in resample(BULB_PROFILE, 60) for i in range(48))
	base.y = -low
	return base, axis, up, side, scale, pair


def bulb_local(base, axis, up, side, scale, a, r, l):
	r = r * (1.0 + 0.035 * bulb_lobe(a, l))
	return base + (axis * l + (up * math.cos(a) + side * math.sin(a)) * r) * scale


def build_bulb(md, k, sides, rows, relief=False):
	base, axis, up, side, scale, pair = bulb_frame(k)
	pts = resample(BULB_PROFILE, rows)

	def point(i, j):
		a = TAU * i / sides + math.pi   # the seam runs underneath
		(r, l), s = pts[j]
		jp, jm = pts[min(j + 1, rows)][0], pts[max(j - 1, 0)][0]
		dr, dl = jp[0] - jm[0], jp[1] - jm[1]
		e = up * math.cos(a) + side * math.sin(a)
		return bulb_local(base, axis, up, side, scale, a, r, l), e * dl - axis * dr

	def rel(i, j, p, n):
		a = TAU * i / sides + math.pi
		(r, l), s = pts[j]
		return 0.0022 * bulb_streak(a, l) * smooth(0.0, 0.1, s) * smooth(1.0, 0.9, s)

	def data(i, j):
		return data_uv(0, lerp(0.3, 1.0, smooth(0.0, 0.6, pts[j][1])), pair)

	grid_surface(md, rows, sides, point, lambda i, j: rect_uv(BULB_RECT, i / sides, pts[j][1]), data,
		relief=rel if relief else None)


def build_lod(lod):
	md = MeshData()
	rows, cols = [(30, 48), (16, 26), (8, 12)][lod]
	build_cap(md, rows, cols)
	build_stalk(md, [14, 9, 6][lod], [26, 14, 8][lod])
	for k in range(4):
		build_bulb(md, k, [12, 8, 6][lod], [10, 6, 4][lod])
	return md


# --- painting ----------------------------------------------------------------------------------

CAP_TIP = (0.50, 0.045, 0.03)
CAP_MID = (0.82, 0.15, 0.045)
CAP_LOW = (0.95, 0.40, 0.09)
LIP = (0.96, 0.80, 0.50)
WART = (0.96, 0.93, 0.84)
GILL = (0.94, 0.87, 0.71)
GILL_DEEP = (0.66, 0.53, 0.33)
GOLD = (1.0, 0.74, 0.16)
IVORY = (0.94, 0.91, 0.84)
FIBRE = (0.82, 0.75, 0.60)
FLECK = (0.88, 0.44, 0.11)


def cap_colour(a, r, h, s):
	"""Albedo, roughness and glow on the cap and gills."""
	if s <= S_GILL:
		rr = r / RIM_R
		g = gill_height(a, rr)
		col = mix3(GILL_DEEP, GILL, smooth(0.0, 0.8, g) * gill_fade(rr) + (1.0 - gill_fade(rr)) * 0.75)
		col = mix3(col, (0.98, 0.84, 0.52), smooth(0.85, 1.0, rr) * 0.5)   # warm near the rim
		# the throat: golden, wet, brightest on the side it spits from
		front = 0.55 + 0.45 * math.cos(a)
		n = noise.noise(Vector((math.cos(a) * 5.0, math.sin(a) * 5.0, rr * 4.0)))
		throat = smooth(0.52, 0.24, rr + 0.06 * n) * front
		col = mix3(col, GOLD, throat * 0.85)
		return col, lerp(0.82, 0.30, throat), throat * (0.75 + 0.25 * n)
	k = h / CAP_H
	if s < S_LIP:
		f = smooth(S_GILL, S_LIP, s)
		return mix3(LIP, mix3(LIP, CAP_LOW, 0.4), f), 0.55, 0.0
	q = cap_local(a, r, h)
	col = mix3(CAP_LOW, CAP_MID, smooth(0.04, 0.45, k))
	col = mix3(col, CAP_TIP, smooth(0.40, 0.98, k))
	col = mix3(col, LIP, smooth(S_LIP + 0.06, S_LIP, s) * 0.6)
	f = cap_fibre(a, h)
	m = noise.noise(q * 9.0 + Vector((1.0, 7.0, 3.0)))
	shade = 1.0 + 0.07 * f + 0.06 * m
	col = (col[0] * shade, col[1] * shade, col[2] * shade)
	w = wart(q, k) * smooth(S_LIP, S_LIP + 0.05, s)
	col = mix3(col, WART, smooth(0.0, 0.35, w))
	col = mix3(col, (0.86, 0.80, 0.66), smooth(0.25, 0.0, w) * smooth(0.0, 0.05, w) * 0.6)   # a dusky edge
	return col, lerp(0.34, 0.78, smooth(0.0, 0.4, w)), 0.0


def stalk_colour(a, t):
	f = stalk_fibre(a, t)
	col = mix3(IVORY, FIBRE, smooth(-0.1, -0.55, f) * 0.8)
	sc = stalk_scales(a, t)
	col = mix3(col, (0.86, 0.66, 0.40), sc * 0.55)
	speck = smooth(0.42, 0.68, noise.noise(Vector((math.cos(a) * 26.0, math.sin(a) * 26.0, t * 34.0))))
	speck *= 0.35 + 0.65 * smooth(0.75, 0.15, t)
	col = mix3(col, FLECK, speck * 0.85)
	streak = smooth(0.2, 0.6, noise.noise(Vector((math.cos(a) * 3.0, math.sin(a) * 3.0, t * 1.5 + 5.0))))
	col = mix3(col, (0.93, 0.70, 0.42), streak * 0.30 * smooth(0.9, 0.3, t))
	col = mix3(col, (0.97, 0.80, 0.46), smooth(0.86, 0.97, t) * 0.6)   # gold where it enters the gills
	return col, 0.66 + 0.12 * smooth(-0.1, -0.55, f) - 0.12 * speck, smooth(0.92, 1.0, t) * 0.35


def bulb_colour(a, l):
	u = l / BULB_L
	lobe = bulb_lobe(a, l)
	col = mix3(IVORY, FIBRE, smooth(-0.35, -0.9, lobe) * 0.55)   # tan in the grooves between lobes
	st = bulb_streak(a, l)
	col = mix3(col, (0.99, 0.97, 0.92), smooth(0.2, 0.7, st) * 0.4)
	speck = smooth(0.50, 0.72, noise.noise(Vector((math.cos(a) * 20.0, math.sin(a) * 20.0, l * 45.0))))
	speck *= 0.3 + 0.7 * smooth(0.6, 0.2, u) * (0.5 + 0.5 * math.cos(a))   # mostly on top, near the stalk
	col = mix3(col, FLECK, speck * 0.8)
	col = mix3(col, (0.70, 0.48, 0.18), smooth(0.86, 0.97, u))   # a golden-brown point
	return col, 0.55 - 0.1 * smooth(0.86, 0.97, u), 0.0


def paint(size):
	albedo = np.zeros((size, size, 3), np.float32)
	orm = np.ones((size, size, 4), np.float32)
	orm[..., 1] = 0.7
	orm[..., 2] = 0.0

	def px_range(r):
		return range(int(r[1] * size), int(math.ceil(r[3] * size))), range(int(r[0] * size), int(math.ceil(r[2] * size)))

	def frac(px, lo, hi):
		return min(max(((px + 0.5) / size - lo) / (hi - lo), 0.0), 1.0)

	cap_pts = resample(CAP_PROFILE, 1200)
	ys, xs = px_range(CAP_RECT)
	for y in ys:
		(r, h), s = cap_pts[int(round(frac(y, CAP_RECT[1], CAP_RECT[3]) * 1200))]
		for x in xs:
			a = TAU * frac(x, CAP_RECT[0], CAP_RECT[2]) + math.pi
			col, rough, glow = cap_colour(a, r, h, s)
			albedo[y, x] = col
			orm[y, x, 1] = rough
			orm[y, x, 2] = glow
	log(TAG, "painted cap")
	ys, xs = px_range(STALK_RECT)
	for y in ys:
		t = frac(y, STALK_RECT[1], STALK_RECT[3])
		for x in xs:
			col, rough, glow = stalk_colour(TAU * frac(x, STALK_RECT[0], STALK_RECT[2]), t)
			albedo[y, x] = col
			orm[y, x, 1] = rough
			orm[y, x, 2] = glow
	log(TAG, "painted stalk")
	bulb_pts = resample(BULB_PROFILE, 600)
	ys, xs = px_range(BULB_RECT)
	for y in ys:
		(r, l), s = bulb_pts[int(round(frac(y, BULB_RECT[1], BULB_RECT[3]) * 600))]
		for x in xs:
			col, rough, glow = bulb_colour(TAU * frac(x, BULB_RECT[0], BULB_RECT[2]) + math.pi, l)
			albedo[y, x] = col
			orm[y, x, 1] = rough
	log(TAG, "painted bulbs")
	return albedo, orm


def region_masks(size):
	yy, xx = np.mgrid[0:size, 0:size]
	u = (xx + 0.5) / size
	v = (yy + 0.5) / size
	pad = 5.0 / size
	rect = lambda r: (u >= r[0] - pad) & (u <= r[2] + pad) & (v >= r[1] - pad) & (v <= r[3] + pad)
	return u, v, {"cap": rect(CAP_RECT), "stalk": rect(STALK_RECT), "bulb": rect(BULB_RECT)}


def main():
	os.makedirs(OUT, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	setup_cycles(TAG, bool(OPT.get("cpu")), ao_distance=0.14)
	log(TAG, "building sculpt")
	hi = {}
	md = MeshData(); build_cap(md, 300, 1400, relief=True); hi["cap"] = md.obj("hi_cap")
	md = MeshData(); build_stalk(md, 72, 320, relief=True); hi["stalk"] = md.obj("hi_stalk")
	for k in range(4):
		md = MeshData(); build_bulb(md, k, 96, 80, relief=True); hi["bulb%d" % k] = md.obj("hi_bulb%d" % k)
	log(TAG, "sculpt: %d faces" % sum(len(o.data.polygons) for o in hi.values()))
	# bake targets: smooth, dense, same UVs as the game meshes
	lows = {}
	md = MeshData(); build_cap(md, 150, 400); lows["cap"] = md.obj("lo_cap")
	md = MeshData(); build_stalk(md, 32, 160); lows["stalk"] = md.obj("lo_stalk")
	md = MeshData(); build_bulb(md, BAKE_BULB, 32, 40); lows["bulb"] = md.obj("lo_bulb")
	for ob in lows.values():
		hide_from_rays(ob)
	sources = {"cap": [hi["cap"]], "stalk": [hi["stalk"]], "bulb": [hi["bulb%d" % BAKE_BULB]]}
	reach = {"cap": (0.02, 0.05), "stalk": (0.012, 0.03), "bulb": (0.008, 0.02)}
	u, v, masks = region_masks(SIZE)
	normal = np.zeros((SIZE, SIZE, 4), np.float32)
	normal[...] = (0.5, 0.5, 1.0, 1.0)
	ao = np.ones((SIZE, SIZE), np.float32)
	all_hi = list(hi.values())
	for part, low in lows.items():
		ext, dist = reach[part]
		px = bake("NORMAL", low, sources[part], ext, dist, 8, SIZE)
		normal[masks[part]] = px[masks[part]]
		px = bake("AO", low, all_hi, ext, dist, 128, SIZE)
		ao[masks[part]] = px[..., 0][masks[part]]
		log(TAG, "baked " + part)
	# fade bake noise at the poles: the gill centre and cap tip, the stalk's ends, the bulbs' ends
	flat = np.array((0.5, 0.5, 1.0, 1.0), np.float32)
	keep = np.ones((SIZE, SIZE), np.float32)
	for part, rect, lo, hi_end in (("cap", CAP_RECT, 0.02, 0.985), ("stalk", STALK_RECT, 0.03, 0.97),
			("bulb", BULB_RECT, 0.04, 0.95)):
		f = (v - rect[1]) / (rect[3] - rect[1])
		m = masks[part]
		keep[m] = np.clip((f[m] - lo * 0.5) / (lo * 0.5), 0.0, 1.0) * np.clip((hi_end - f[m]) / 0.03, 0.0, 1.0)
	normal = flat + (normal - flat) * keep[..., None]
	ao = 1.0 + (ao - 1.0) * keep
	ao[masks["cap"]] = 0.25 + 0.75 * ao[masks["cap"]]
	log(TAG, "painting")
	albedo, orm = paint(SIZE)
	orm[..., 0] = ao
	alb = np.ones((SIZE, SIZE, 4), np.float32)
	alb[..., :3] = albedo
	save_png(os.path.join(OUT, "spitter_albedo.png"), alb, False)
	save_png(os.path.join(OUT, "spitter_normal.png"), normal, True)
	save_png(os.path.join(OUT, "spitter_orm.png"), orm, True)
	for ob in all_hi + list(lows.values()):
		bpy.data.objects.remove(ob)
	stats = []
	for lod, name in enumerate(("close", "battle", "distant")):
		ob = build_lod(lod).obj("Spitter_" + name)
		stats.append("%s %d" % (name, export_glb([ob], os.path.join(OUT, "spitter_%s.glb" % name))))
	throat = cap_place(cap_local(0.0, 0.14, 0.11))
	log(TAG, "rig: NECK %s CAP_ORIGIN %s CAP_UP %s throat %s" % (tuple(round(c, 4) for c in NECK),
		tuple(round(c, 4) for c in CAP_ORIGIN), tuple(round(c, 4) for c in CAP_UP), tuple(round(c, 4) for c in throat)))
	log(TAG, "done: " + ", ".join(stats))


def preview(path):
	"""Shape check without the sculpt or bakes: the close mesh, side and three-quarter views."""
	bpy.ops.wm.read_factory_settings(use_empty=True)
	ob = build_lod(0).obj("preview")
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.display.shading.light = "STUDIO"
	scene.display.shading.color_type = "OBJECT"
	ob.color = (0.85, 0.45, 0.30, 1.0)
	scene.render.resolution_x, scene.render.resolution_y = 900, 900
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = 2.8
	for name, yaw in (("side", 0.0), ("q", 0.75)):
		# game +X forward is Blender +X; look from the unit's left side (Blender -Y)
		d = Vector((math.sin(yaw), -math.cos(yaw), 0.25)).normalized()
		target = Vector((-0.15, 0.0, 1.0))
		cam.location = target + d * 6.0
		cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = path.replace(".png", "_%s.png" % name)
		bpy.ops.render.render(write_still=True)


if OPT.get("preview"):
	preview(os.path.abspath(OPT["preview"]))
else:
	main()
