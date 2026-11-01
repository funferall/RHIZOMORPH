"""Morel Bruiser art build, run headless in Blender 4.2:

  blender -b --factory-startup -P tools/blender/bruiser_build.py -- [--out=art/bruiser] [--size=1024] [--cpu]

A hunched Morchella warrior: a conical honeycomb cap for a torso, two morel shoulders on
thick knuckle-walking arms, two short rear legs, padded clawed feet and knuckles, and golden cracks of
glowing hyphae. Builds a high-detail sculpt (Voronoi honeycomb pits about 5 cm deep,
fibres, creases, granules) and three low-poly game meshes sharing one atlas. Cycles bakes
normals and ambient occlusion; colour, roughness, glow and the pit height map (for the
shader's close-range parallax) are painted from the same functions that shaped the sculpt.

Writes bruiser_{close,battle,distant}.glb and bruiser_{albedo,normal,orm}.png
(orm: R occlusion, G roughness, B glow, A height: 1 ridge, 0 pit floor).
Data UV: u = kind + 0.98 * gait weight (0 belly, 1 cap, 2 shoulder morel, 3 limb, 4 toe or knuckle),
v = gait pair (0 or 1), plus 2 on the arms and their shoulder morels, which the attack swings.
"""
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(__file__))
from unitlib import (TAU, MeshData, bake, data_uv, export_glb, grid_surface, hide_from_rays, lerp, log, mix3,
	rect_uv, resample, save_png, setup_cycles, smooth, tube)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else True) for a in ARGS}
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, OPT.get("out", "art/bruiser"))
SIZE = int(OPT.get("size", 1024))
TAG = "bruiser"

# --- shape --------------------------------------------------------------------------------
CAP_PROFILE = [(0.48, 0.40), (0.56, 0.48), (0.59, 0.60), (0.565, 0.75), (0.505, 0.90), (0.42, 1.04),
	(0.325, 1.17), (0.22, 1.28), (0.11, 1.37), (0.0, 1.415)]
BELLY_PROFILE = [(0.0, 0.30), (0.14, 0.305), (0.28, 0.32), (0.40, 0.35), (0.48, 0.40)]
PAULDRON_PROFILE = [(0.20, -0.03), (0.225, 0.05), (0.21, 0.13), (0.165, 0.20), (0.095, 0.255), (0.0, 0.28)]
X_SCALE, Z_SCALE, LEAN = 1.06, 0.94, 0.06
# Limbs, left side (+z); the right side mirrors z. Two thick arms hang from the shoulder
# morels and it knuckle-walks on them; two short rear legs carry the back of the cap.
ARM = [(0.20, 0.64, 0.50), (0.27, 0.48, 0.62), (0.33, 0.32, 0.68), (0.37, 0.19, 0.66), (0.40, 0.10, 0.63),
	(0.41, 0.05, 0.62), (0.415, 0.0, 0.62)]
ARM_RADII = [0.16, 0.158, 0.14, 0.13, 0.13, 0.16, 0.004]
REAR_LEG = [(-0.22, 0.50, 0.28), (-0.27, 0.38, 0.44), (-0.29, 0.26, 0.51), (-0.29, 0.16, 0.51), (-0.29, 0.10, 0.49),
	(-0.29, 0.05, 0.49), (-0.29, 0.0, 0.49)]
LEG_RADII = [0.15, 0.15, 0.135, 0.13, 0.13, 0.15, 0.004]
PAULDRON_AT = Vector((0.20, 0.66, 0.52))
PAULDRON_AXIS = Vector((0.10, 0.8, 1.0)).normalized()
# (path, radii, side, gait pair, is arm). Diagonal pairs step together. In the data UV,
# arm vertices (and their shoulder morels) carry pair + 2, so the shader can swing them.
LIMBS = [(ARM, ARM_RADII, 1, 0, True), (ARM, ARM_RADII, -1, 1, True), (REAR_LEG, LEG_RADII, 1, 1, False),
	(REAR_LEG, LEG_RADII, -1, 0, False)]
BAKE_LIMB = 2

# --- atlas regions (Blender UV, v up) ----------------------------------------------------------
CAP_RECT = (0.006, 0.506, 0.994, 0.994)
LEG_RECT = (0.006, 0.006, 0.244, 0.494)
TOE_RECT = (0.256, 0.006, 0.369, 0.494)
PAULDRON_RECT = (0.381, 0.256, 0.744, 0.494)
BELLY_C, BELLY_R = (0.50, 0.125), 0.112


def leg_weight(t):
	return smooth(0.08, 0.45, t) * 0.5 + smooth(0.45, 0.85, t) * 0.5


def toe_weight(t):
	return 1.0


# --- surface functions: the sculpt's relief and the painted maps come from the same place ---------

def broad(a, y):
	return 0.025 * noise.noise(Vector((math.cos(a) * 1.8, math.sin(a) * 1.8, y * 2.2 + 4.0)))


def cap_point(a, s, pts):
	(r, y) = pts
	r = r * (1.0 + broad(a, y))
	return Vector((r * math.cos(a) * X_SCALE + LEAN * s ** 1.5, y, r * math.sin(a) * Z_SCALE))


def honey(p, scale, seed=0.0):
	"""Morel honeycomb at p. Returns height (1 ridge, 0 pit floor), webbing, per-cell tint."""
	q = Vector((p.x * scale, p.y * scale * 0.62, p.z * scale)) + Vector((seed, seed * 0.7, 0))
	d, pts = noise.voronoi(q, distance_metric="DISTANCE", exponent=2.5)
	e = d[1] - d[0]
	h = 1.0 - smooth(0.035, 0.30, e)
	d2, _ = noise.voronoi(q * 3.1 + Vector((7.3, 1.1, 2.9)), distance_metric="DISTANCE", exponent=2.5)
	web = (1.0 - smooth(0.0, 0.075, d2[1] - d2[0])) * 0.34 * (1.0 - h)
	h = min(max(h + web + 0.06 * noise.noise(p * 35.0) * h, 0.0), 1.0)
	cell = noise.noise(pts[0] * 0.37 + Vector((0.5, 0.5, 0.5)))
	return h, web, cell


PIT_DEPTH = 0.052


def leg_fibre(a, t):
	return noise.noise(Vector((math.cos(a) * 9.0, math.sin(a) * 9.0, t * 2.6)))


def leg_crease(t):
	return math.exp(-((t - 0.40) / 0.09) ** 2) * (0.5 + 0.5 * math.sin(t * 95.0))


def leg_relief(t, a, p):
	granule = smooth(0.80, 0.9, t) * noise.noise(Vector((math.cos(a) * 22, math.sin(a) * 22, t * 60)))
	return 0.0045 * leg_fibre(a, t) - 0.008 * leg_crease(t) + 0.004 * granule


def crack(a, t):
	"""A glowing seam of golden hyphae running down one face of each limb."""
	# two seams, on the outer and the forward face of each limb
	band = max(math.exp(-((math.atan2(math.sin(a - 2.2), math.cos(a - 2.2))) / 0.9) ** 2),
		math.exp(-((math.atan2(math.sin(a - 5.2), math.cos(a - 5.2))) / 0.9) ** 2))
	n = noise.noise(Vector((math.cos(a) * 2.2, math.sin(a) * 2.2, t * 5.0)) + Vector((2.0, 9.0, 4.0)))
	branch = noise.noise(Vector((math.cos(a) * 4.0, math.sin(a) * 4.0, t * 9.0)) + Vector((5.0, 1.0, 7.0)))
	seam = max(max(0.0, 1.0 - abs(n) / 0.11), 0.6 * max(0.0, 1.0 - abs(branch) / 0.06))
	return seam * band * smooth(0.10, 0.22, t) * (1.0 - smooth(0.74, 0.86, t))


def toe_relief(t, a, p):
	return -0.0025 * max(0.0, math.sin(t * 40.0)) * (1.0 - smooth(0.55, 0.65, t))


# --- part builders ------------------------------------------------------------------------------

def build_cap(md, rows, cols, relief=False):
	pts = resample(CAP_PROFILE, rows)
	data = data_uv(1)

	def point(i, j):
		a = TAU * i / cols + math.pi
		(r, y), s = pts[j]
		p = cap_point(a, s, (r, y))
		jp, jm = pts[min(j + 1, rows)][0], pts[max(j - 1, 0)][0]
		tr, ty = jp[0] - jm[0], jp[1] - jm[1]
		return p, Vector((ty * math.cos(a), -tr, ty * math.sin(a)))

	rel = (lambda i, j, p, n: (honey(p, 7.5)[0] - 1.0) * PIT_DEPTH) if relief else None
	grid_surface(md, rows, cols, point, lambda i, j: rect_uv(CAP_RECT, i / cols, pts[j][1]), lambda i, j: data,
		relief=rel)


def build_belly(md, rows, cols, relief=False):
	pts = resample(BELLY_PROFILE, rows)

	def point(i, j):
		a = TAU * i / cols
		(r, y), s = pts[j]
		rr = r * (1.0 + broad(a, y) * smooth(0.6, 1.0, s))
		jp, jm = pts[min(j + 1, rows)][0], pts[max(j - 1, 0)][0]
		tr, ty = jp[0] - jm[0], jp[1] - jm[1]
		return Vector((rr * math.cos(a) * X_SCALE, y, rr * math.sin(a) * Z_SCALE)), Vector((ty * math.cos(a), -tr, ty * math.sin(a)))

	def uv(i, j):
		a, s = TAU * i / cols, pts[j][1]
		return (BELLY_C[0] + BELLY_R * s * math.cos(a), BELLY_C[1] + BELLY_R * s * math.sin(a))

	rel = (lambda i, j, p, n: 0.003 * noise.noise(Vector((math.cos(TAU * i / cols) * 14, math.sin(TAU * i / cols) * 14, pts[j][1] * 2)))) if relief else None
	grid_surface(md, rows, cols, point, uv, lambda i, j: data_uv(0), relief=rel)


def pauldron_frame(side):
	at = Vector((PAULDRON_AT.x, PAULDRON_AT.y, PAULDRON_AT.z * side))
	up = Vector((PAULDRON_AXIS.x, PAULDRON_AXIS.y, PAULDRON_AXIS.z * side)).normalized()
	fwd = (Vector((1, 0, 0)) - up * up.x).normalized()
	side_v = up.cross(fwd)
	return at, up, fwd, side_v


def pauldron_local(a, s, pts):
	(r, h) = pts
	r = r * (1.0 + 0.05 * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, h * 6 + 1))))
	return Vector((r * math.cos(a), h, r * math.sin(a)))


def build_pauldron(md, side, rows, cols, relief=False):
	pts = resample(PAULDRON_PROFILE, rows)
	at, up, fwd, sv = pauldron_frame(side)
	to_world = lambda v: at + fwd * v.x + up * v.y + sv * v.z
	to_dir = lambda v: fwd * v.x + up * v.y + sv * v.z

	def point(i, j):
		a = TAU * i / cols
		(r, h), s = pts[j]
		local = pauldron_local(a, s, (r, h))
		jp, jm = pts[min(j + 1, rows)][0], pts[max(j - 1, 0)][0]
		tr, th = jp[0] - jm[0], jp[1] - jm[1]
		return to_world(local), to_dir(Vector((th * math.cos(a), -tr, th * math.sin(a))))

	def rel(i, j, p, n):
		a = TAU * i / cols
		local = pauldron_local(a, pts[j][1], pts[j][0])
		return (honey(local, 13.0, seed=3.0)[0] - 1.0) * PIT_DEPTH * 0.6

	arm_group = limb_group(0 if side > 0 else 1)
	grid_surface(md, rows, cols, point, lambda i, j: rect_uv(PAULDRON_RECT, i / cols, pts[j][1]),
		lambda i, j: data_uv(2, 0.0, arm_group), relief=rel if relief else None)


def mirror(path, side):
	return [Vector((x, y, z * side)) for (x, y, z) in path]


def limb_group(k):
	path, radii, side, group, arm = LIMBS[k]
	return group + (2 if arm else 0)


def build_leg(md, leg_index, sides, samples, relief=False):
	path, radii, side, group, arm = LIMBS[leg_index]
	tube(md, mirror(path, side), radii, sides, samples, LEG_RECT, 3, leg_weight, limb_group(leg_index),
		relief=leg_relief if relief else None)


def toe_paths(leg_index):
	path, radii, side, group, arm = LIMBS[leg_index]
	group = limb_group(leg_index)
	pad = Vector((path[5][0], 0.05, path[5][2] * side))
	paths = []
	for k, spread in enumerate((-0.66, -0.22, 0.22, 0.66)):
		d = Vector((math.cos(spread), 0, math.sin(spread)))
		base = pad + d * 0.10 + Vector((0, 0.0, 0))
		paths.append([base, base + d * 0.04 + Vector((0, -0.006, 0)), base + d * 0.075 + Vector((0, -0.028, 0)),
			base + d * 0.095 + Vector((0, -0.048, 0))])
	return paths, group


TOE_RADII = [0.062, 0.058, 0.04, 0.004]


def build_toes(md, leg_index, sides, samples, relief=False, only_first=False):
	paths, group = toe_paths(leg_index)
	for k, path in enumerate(paths):
		if only_first and k > 0:
			break
		tube(md, path, TOE_RADII, sides, samples, TOE_RECT, 4, toe_weight, group,
			relief=toe_relief if relief else None)


def build_lod(lod):
	md = MeshData()
	cap_rows, cols = [(22, 56), (12, 32), (6, 14)][lod]
	build_cap(md, cap_rows, cols)
	build_belly(md, [4, 3, 2][lod], cols)
	for side in (1, -1):
		build_pauldron(md, side, [6, 4, 3][lod], [16, 10, 6][lod])
	for k in range(4):
		build_leg(md, k, [12, 8, 5][lod], [16, 10, 6][lod])
		if lod < 2:
			build_toes(md, k, [6, 4][lod], [5, 3][lod])
	return md


# --- painting ----------------------------------------------------------------------------------

RIDGE = (0.87, 0.64, 0.33)
RIDGE_HI = (0.95, 0.80, 0.52)
WALL = (0.60, 0.40, 0.19)
FLOOR = (0.27, 0.16, 0.07)
WEB = (0.72, 0.53, 0.30)
CREAM = (0.91, 0.86, 0.75)
GROOVE = (0.64, 0.52, 0.36)
GOLD = (1.0, 0.76, 0.30)


def honey_colour(h, web, cell, s):
	col = mix3(FLOOR, WALL, smooth(0.0, 0.5, h))
	col = mix3(col, RIDGE, smooth(0.45, 0.92, h))
	col = mix3(col, RIDGE_HI, smooth(0.88, 1.0, h) * 0.45)
	col = mix3(col, WEB, smooth(0.05, 0.25, web) * 0.7)
	k = 1.0 + 0.10 * cell
	col = (col[0] * k, col[1] * k, col[2] * k)
	col = mix3(col, (col[0] * 1.06, col[1] * 1.04, col[2] * 0.9), smooth(0.4, 0.0, s))  # warmer near the rim
	return col


def paint(size):
	albedo = np.zeros((size, size, 3), np.float32)
	orm = np.zeros((size, size, 4), np.float32)
	orm[..., 0] = 1.0
	orm[..., 1] = 0.7
	orm[..., 3] = 1.0
	cap_pts = resample(CAP_PROFILE, 400)
	paul_pts = resample(PAULDRON_PROFILE, 200)

	def px_range(r):
		return range(int(r[1] * size), int(math.ceil(r[3] * size))), range(int(r[0] * size), int(math.ceil(r[2] * size)))

	# cap
	ys, xs = px_range(CAP_RECT)
	for y in ys:
		v = min(max(((y + 0.5) / size - CAP_RECT[1]) / (CAP_RECT[3] - CAP_RECT[1]), 0.0), 1.0)
		prof, s = cap_pts[int(round(v * 400))]
		for x in xs:
			u = min(max(((x + 0.5) / size - CAP_RECT[0]) / (CAP_RECT[2] - CAP_RECT[0]), 0.0), 1.0)
			a = TAU * u + math.pi
			p = cap_point(a, s, prof)
			h, web, cell = honey(p, 7.5)
			albedo[y, x] = honey_colour(h, web, cell, s)
			orm[y, x, 1] = lerp(0.88, 0.52, h)
			orm[y, x, 2] = (1.0 - h) ** 3 * smooth(0.32, 0.0, s) * smooth(0.55, 0.8, noise.noise(p * 4.0)) * 0.8
			orm[y, x, 3] = h
	log(TAG, "painted cap")
	# pauldrons (both share one region; painted from the left one)
	ys, xs = px_range(PAULDRON_RECT)
	for y in ys:
		v = min(max(((y + 0.5) / size - PAULDRON_RECT[1]) / (PAULDRON_RECT[3] - PAULDRON_RECT[1]), 0.0), 1.0)
		prof, s = paul_pts[int(round(v * 200))]
		for x in xs:
			u = min(max(((x + 0.5) / size - PAULDRON_RECT[0]) / (PAULDRON_RECT[2] - PAULDRON_RECT[0]), 0.0), 1.0)
			local = pauldron_local(TAU * u, s, prof)
			h, web, cell = honey(local, 13.0, seed=3.0)
			albedo[y, x] = honey_colour(h, web, cell, 0.6)
			orm[y, x, 1] = lerp(0.88, 0.52, h)
			orm[y, x, 3] = h
	log(TAG, "painted pauldrons")
	# legs
	ys, xs = px_range(LEG_RECT)
	for y in ys:
		t = min(max(((y + 0.5) / size - LEG_RECT[1]) / (LEG_RECT[3] - LEG_RECT[1]), 0.0), 1.0)
		for x in xs:
			u = min(max(((x + 0.5) / size - LEG_RECT[0]) / (LEG_RECT[2] - LEG_RECT[0]), 0.0), 1.0)
			a = TAU * u
			f = leg_fibre(a, t)
			col = mix3(CREAM, GROOVE, smooth(-0.15, -0.55, f) * 0.85)
			col = mix3(col, (col[0] * 0.82, col[1] * 0.78, col[2] * 0.72), leg_crease(t) * 0.7)
			speck = smooth(0.55, 0.75, noise.noise(Vector((math.cos(a) * 30, math.sin(a) * 30, t * 90))))
			col = mix3(col, (0.55, 0.42, 0.26), speck * 0.6)
			col = mix3(col, (0.80, 0.70, 0.55), smooth(0.84, 0.95, t) * 0.4)   # a dusty pad
			col = mix3(col, (0.86, 0.66, 0.38), smooth(0.24, 0.05, t) * 0.55)  # warm where the cap meets the limb
			c = crack(a, t)
			col = mix3(col, GOLD, c)
			albedo[y, x] = col
			orm[y, x, 1] = 0.62 + 0.18 * smooth(-0.15, -0.55, f) - 0.15 * c
			orm[y, x, 2] = c
	log(TAG, "painted legs")
	# toes: pale, ending in dark glossy claws
	ys, xs = px_range(TOE_RECT)
	for y in ys:
		t = min(max(((y + 0.5) / size - TOE_RECT[1]) / (TOE_RECT[3] - TOE_RECT[1]), 0.0), 1.0)
		claw = smooth(0.70, 0.80, t)
		for x in xs:
			u = ((x + 0.5) / size - TOE_RECT[0]) / (TOE_RECT[2] - TOE_RECT[0])
			n = noise.noise(Vector((math.cos(TAU * u) * 6, math.sin(TAU * u) * 6, t * 20)))
			col = mix3(mix3(CREAM, GROOVE, smooth(0.2, 0.7, n) * 0.4), (0.24, 0.16, 0.10), claw)
			albedo[y, x] = col
			orm[y, x, 1] = lerp(0.62, 0.32, claw)
	# belly: pale stalk flesh, fibrous
	yy, xx = np.mgrid[0:size, 0:size]
	du = (xx + 0.5) / size - BELLY_C[0]
	dv = (yy + 0.5) / size - BELLY_C[1]
	mask = du * du + dv * dv <= (BELLY_R + 5.0 / size) ** 2
	for y, x in zip(*np.nonzero(mask)):
		a = math.atan2(dv[y, x], du[y, x])
		s = min(math.hypot(du[y, x], dv[y, x]) / BELLY_R, 1.0)
		n = noise.noise(Vector((math.cos(a) * 14, math.sin(a) * 14, s * 2)))
		albedo[y, x] = mix3(CREAM, GROOVE, smooth(0.1, 0.6, n) * 0.5)
		orm[y, x, 1] = 0.7
	log(TAG, "painted toes and belly")
	return albedo, orm


def region_masks(size):
	yy, xx = np.mgrid[0:size, 0:size]
	u = (xx + 0.5) / size
	v = (yy + 0.5) / size
	pad = 5.0 / size
	rect = lambda r: (u >= r[0] - pad) & (u <= r[2] + pad) & (v >= r[1] - pad) & (v <= r[3] + pad)
	disk = (u - BELLY_C[0]) ** 2 + (v - BELLY_C[1]) ** 2 <= (BELLY_R + pad) ** 2
	return u, v, {"cap": rect(CAP_RECT), "pauldron": rect(PAULDRON_RECT), "leg": rect(LEG_RECT),
		"toe": rect(TOE_RECT), "belly": disk}


def main():
	os.makedirs(OUT, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	setup_cycles(TAG, bool(OPT.get("cpu")), ao_distance=0.16)
	log(TAG, "building sculpt")
	hi = {}
	md = MeshData(); build_cap(md, 260, 720, relief=True); hi["cap"] = md.obj("hi_cap")
	md = MeshData(); build_belly(md, 40, 720, relief=True); hi["belly"] = md.obj("hi_belly")
	md = MeshData(); build_pauldron(md, 1, 90, 260, relief=True); hi["pauldron"] = md.obj("hi_pauldron")
	md = MeshData(); build_pauldron(md, -1, 90, 260, relief=True); hi["pauldron_r"] = md.obj("hi_pauldron_r")
	for k in range(4):
		md = MeshData(); build_leg(md, k, 56, 260, relief=True); hi["leg%d" % k] = md.obj("hi_leg%d" % k)
		md = MeshData(); build_toes(md, k, 16, 50, relief=True); hi["toes%d" % k] = md.obj("hi_toes%d" % k)
	log(TAG, "sculpt: %d faces" % sum(len(o.data.polygons) for o in hi.values()))
	# bake targets: smooth, dense, same UVs as the game meshes
	lows = {}
	md = MeshData(); build_cap(md, 130, 360); lows["cap"] = md.obj("lo_cap")
	md = MeshData(); build_belly(md, 20, 360); lows["belly"] = md.obj("lo_belly")
	md = MeshData(); build_pauldron(md, 1, 45, 130); lows["pauldron"] = md.obj("lo_pauldron")
	md = MeshData(); build_leg(md, BAKE_LIMB, 28, 130); lows["leg"] = md.obj("lo_leg")
	md = MeshData(); build_toes(md, BAKE_LIMB, 10, 30, only_first=True); lows["toe"] = md.obj("lo_toe")
	for ob in lows.values():
		hide_from_rays(ob)
	sources = {"cap": [hi["cap"]], "belly": [hi["belly"]], "pauldron": [hi["pauldron"]], "leg": [hi["leg%d" % BAKE_LIMB]],
		"toe": [hi["toes%d" % BAKE_LIMB]]}
	reach = {"cap": (0.012, 0.08), "belly": (0.006, 0.02), "pauldron": (0.01, 0.06), "leg": (0.012, 0.03), "toe": (0.004, 0.012)}
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
	# fade bake noise at poles: the cap's apex, the belly's centre, the foot pad's sole, claw tips
	flat = np.array((0.5, 0.5, 1.0, 1.0), np.float32)
	keep = np.ones((SIZE, SIZE), np.float32)
	vc = (v - CAP_RECT[1]) / (CAP_RECT[3] - CAP_RECT[1])
	keep[masks["cap"]] = np.clip((0.985 - vc[masks["cap"]]) / 0.03, 0.0, 1.0)
	sb = np.hypot(u - BELLY_C[0], v - BELLY_C[1]) / BELLY_R
	keep[masks["belly"]] = np.clip((sb[masks["belly"]] - 0.03) / 0.06, 0.0, 1.0)
	vl = (v - LEG_RECT[1]) / (LEG_RECT[3] - LEG_RECT[1])
	keep[masks["leg"]] = np.clip((0.975 - vl[masks["leg"]]) / 0.04, 0.0, 1.0)
	vt = (v - TOE_RECT[1]) / (TOE_RECT[3] - TOE_RECT[1])
	keep[masks["toe"]] = np.clip((0.96 - vt[masks["toe"]]) / 0.06, 0.0, 1.0)
	normal = flat + (normal - flat) * keep[..., None]
	ao = 1.0 + (ao - 1.0) * keep
	for part in ("cap", "pauldron"):
		ao[masks[part]] = 0.22 + 0.78 * ao[masks[part]]
	log(TAG, "painting")
	albedo, orm = paint(SIZE)
	orm[..., 0] = ao
	alb = np.ones((SIZE, SIZE, 4), np.float32)
	alb[..., :3] = albedo
	save_png(os.path.join(OUT, "bruiser_albedo.png"), alb, False)
	save_png(os.path.join(OUT, "bruiser_normal.png"), normal, True)
	save_png(os.path.join(OUT, "bruiser_orm.png"), orm, True)
	for ob in all_hi + list(lows.values()):
		bpy.data.objects.remove(ob)
	stats = []
	for lod, name in enumerate(("close", "battle", "distant")):
		ob = build_lod(lod).obj("Bruiser_" + name)
		stats.append("%s %d" % (name, export_glb([ob], os.path.join(OUT, "bruiser_%s.glb" % name))))
	log(TAG, "done: " + ", ".join(stats))


main()
