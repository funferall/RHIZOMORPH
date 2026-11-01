"""Violet Webcap art build, run headless in Blender 4.2:

  blender -b --factory-startup -P tools/blender/webcap_build.py -- [--out=art/webcap] [--size=1024] [--cpu]

Builds a high-detail sculpt (cap fibrils, gill blades, bulb wrinkles, leg ridges) and
three low-poly game meshes that share one texture atlas. Cycles bakes the sculpt's
normals and ambient occlusion onto the game mesh; colour, roughness and the silk of
the cortina are painted into the same atlas. Writes:

  webcap_close.glb / webcap_battle.glb / webcap_distant.glb   game meshes, Y up, +X forward
  webcap_albedo.png   sRGB colour; alpha is the silk coverage of the web curtains
  webcap_normal.png   tangent-space normals (OpenGL, MikkTSpace)
  webcap_orm.png      R ambient occlusion, G roughness, B glow (gold silk and bulb veins)

Second UV map ("data"): u = kind + 0.98 * gait weight, v = tripod (0 or 1).
Kinds: 0 stalk and bulb, 1 cap, 2 gills, 3 leg, 4 web sheet, 5 hanging web (weight = how far down).
"""
import bpy
import math
import os
import random
import sys
import time

import numpy as np
from mathutils import Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else True) for a in ARGS}
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, OPT.get("out", "art/webcap"))
SIZE = int(OPT.get("size", 1024))
TAU = math.tau
T0 = time.time()

CAP_BASE = 1.50
RIM_R, RIM_Y = 0.475, 1.455
LEG_ANGLES = [-2.62, -1.52, -0.48, 0.52, 1.55, 2.58]

# Atlas regions, Blender UV space (v up). Polar disks for the cap and gills,
# rectangles for the stalk, the one leg strip all six legs share, and the silk.
CAP_C, GILL_C, DISK_R = (0.25, 0.75), (0.75, 0.75), 0.236
STALK_RECT = (0.016, 0.016, 0.234, 0.484)
LEG_RECT = (0.266, 0.016, 0.484, 0.484)
SILK_RECT = (0.508, 0.008, 0.992, 0.492)

CAP_PROFILE = [(0.462, -0.046), (0.505, -0.012), (0.522, 0.035), (0.505, 0.095), (0.462, 0.158),
	(0.39, 0.215), (0.295, 0.257), (0.19, 0.282), (0.09, 0.294), (0.0, 0.297)]
UNDER_PROFILE = [(0.084, 0.002), (0.17, -0.010), (0.27, -0.024), (0.38, -0.037), (0.462, -0.046)]
STALK_PROFILE = [(0.0, 0.595), (0.05, 0.612), (0.105, 0.655), (0.148, 0.725), (0.165, 0.80), (0.155, 0.88),
	(0.122, 0.955), (0.087, 1.035), (0.067, 1.14), (0.058, 1.27), (0.061, 1.39), (0.074, 1.465), (0.092, 1.505)]
# One leg along +X: (out, up) points, radius, gait weight
LEG_PATH = [(0.11, 0.80), (0.22, 0.875), (0.36, 1.02), (0.47, 1.12), (0.62, 0.743), (0.77, 0.367), (0.90, 0.04), (0.912, 0.0)]
LEG_RADII = [0.036, 0.031, 0.024, 0.029, 0.020, 0.016, 0.010, 0.002]
LEG_WEIGHTS = [0.0, 0.0, 0.15, 0.40, 0.60, 0.80, 1.0, 1.0]
KNEE = 3


def log(msg):
	print("[webcap %5.1fs] %s" % (time.time() - T0, msg), flush=True)


def g2b(p):
	"""Game space (Y up) to Blender (Z up); the glTF exporter turns it back."""
	return (p[0], -p[2], p[1])


def smooth(e0, e1, x):
	t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
	return t * t * (3 - 2 * t)


def lerp(a, b, t):
	return a + (b - a) * t


def mix3(a, b, t):
	return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t))


def wob(a):
	return 1.0 + 0.012 * (math.sin(a * 3.0 + 0.7) * 0.6 + math.cos(a * 7.0) * 0.4)


def catmull(p0, p1, p2, p3, t):
	t2, t3 = t * t, t * t * t
	return tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
		+ (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in range(len(p1)))


def resample(points, n):
	"""n + 1 points spaced evenly by arc length along a Catmull-Rom curve, with their fraction s."""
	dense = []
	for i in range(len(points) - 1):
		p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, len(points) - 1)]
		for k in range(60):
			dense.append(catmull(p0, p1, p2, p3, k / 60))
	dense.append(points[-1])
	cum = [0.0]
	for i in range(1, len(dense)):
		cum.append(cum[-1] + math.dist(dense[i], dense[i - 1]))
	total = cum[-1]
	out = []
	j = 0
	for k in range(n + 1):
		target = total * k / n
		while j < len(cum) - 2 and cum[j + 1] < target:
			j += 1
		f = (target - cum[j]) / max(cum[j + 1] - cum[j], 1e-9)
		out.append((tuple(lerp(dense[j][i], dense[j + 1][i], f) for i in range(len(dense[j]))), k / n))
	return out


def polar_uv(c, s, a):
	return (c[0] + DISK_R * s * math.cos(a), c[1] + DISK_R * s * math.sin(a))


def rect_uv(r, u, v):
	return (lerp(r[0], r[2], u), lerp(r[1], r[3], v))


def data_uv(kind, weight=0.0, tripod=0):
	return (kind + 0.98 * weight, float(tripod))


# --- shared surface functions: the sculpt's relief and the painted colour agree ---------

def cap_fibril(a, s):
	return noise.noise(Vector((math.cos(a) * 46.0, math.sin(a) * 46.0, s * 4.0)))


def cap_relief(a, s, p):
	broad = noise.noise(Vector(p) * 5.0)
	fine = noise.noise(Vector(p) * 70.0)
	rim = smooth(0.80, 1.0, s)
	return 0.0024 * cap_fibril(a, s) + 0.0008 * fine + 0.0045 * broad * s - 0.002 * rim * noise.noise(Vector(p) * 22.0)


def gill_relief(a, s):
	"""Radial gill blades hanging below the underside: long ones, with short ones between."""
	inner = smooth(0.0, 0.18, s) * (1.0 - smooth(0.88, 1.0, s))
	blade = max(math.cos(a * 44.0), 0.0) ** 6
	short = max(math.cos(a * 44.0 + math.pi), 0.0) ** 6 * smooth(0.45, 0.6, s)
	return 0.030 * (blade + 0.8 * short) * inner


def stalk_fiber(a, y):
	return noise.noise(Vector((math.cos(a) * 26.0, math.sin(a) * 26.0, y * 2.2)))


def bulb_mask(y):
	return 1.0 - smooth(0.9, 1.08, y)


def stalk_relief(a, y, p):
	wrinkle = noise.noise(Vector(p) * 26.0)
	return 0.0016 * stalk_fiber(a, y) + 0.0034 * wrinkle * bulb_mask(y)


def bulb_vein(p):
	"""Thin gold veins on the bulb: a ridged band of 3-D noise."""
	n = noise.noise(Vector(p) * 7.0 + Vector((3.1, 0.7, 1.9)))
	return max(0.0, 1.0 - abs(n) / 0.018)


def leg_relief(t, a, p):
	ridge = noise.noise(Vector((math.cos(a) * 3.0, math.sin(a) * 3.0, t * 42.0)))
	knee = math.exp(-((t - 0.40) / 0.06) ** 2)
	knob = noise.noise(Vector(p) * 60.0)
	return 0.0011 * ridge + 0.0035 * knee * knob


# --- mesh building ---------------------------------------------------------------------

class MeshData:
	def __init__(self):
		self.verts = []
		self.faces = []
		self.uv = []
		self.data = []

	def vert(self, p):
		self.verts.append(g2b(p))
		return len(self.verts) - 1

	def face(self, idx, uvs, datas, normal_hint=None):
		if normal_hint is not None:
			a, b, c = (Vector(self.verts[i]) for i in idx[:3])
			if (b - a).cross(c - a).dot(Vector(g2b(normal_hint))) < 0.0:
				idx, uvs, datas = idx[::-1], uvs[::-1], datas[::-1]
		self.faces.append(tuple(idx))
		self.uv.extend(uvs)
		self.data.extend(datas)

	def obj(self, name, smooth_shading=True):
		me = bpy.data.meshes.new(name)
		me.from_pydata(self.verts, [], self.faces)
		uv = me.uv_layers.new(name="UVMap")
		data = me.uv_layers.new(name="data")
		uv.data.foreach_set("uv", [c for p in self.uv for c in p])
		data.data.foreach_set("uv", [c for p in self.data for c in p])
		me.polygons.foreach_set("use_smooth", [smooth_shading] * len(me.polygons))
		me.uv_layers.active = uv
		uv.active_render = True
		me.update()
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		return ob


def lathe(md, profile, rows, sides, uv_fn, kind, wobble=0.0, relief=None, wobble_fade=None):
	"""Surface of revolution. profile is (r, y) in game units; uv_fn(a, s) -> atlas uv."""
	pts = resample(profile, rows)
	grid = []
	for j, ((r, y), s) in enumerate(pts):
		jp = pts[min(j + 1, rows)][0]
		jm = pts[max(j - 1, 0)][0]
		tr, ty = jp[0] - jm[0], jp[1] - jm[1]
		row = []
		for k in range(sides):
			a = TAU * k / sides
			w = 1.0 + (wob(a) - 1.0) * (wobble_fade(s) if wobble_fade else 1.0) * (1.0 if wobble else 0.0)
			p = Vector((r * w * math.cos(a), y, r * w * math.sin(a)))
			n = Vector((ty * math.cos(a), -tr, ty * math.sin(a)))
			if n.length > 1e-9:
				n.normalize()
			if relief:
				p = p + n * relief(a, s, tuple(p))
			row.append((md.vert(p), n))
		grid.append(row)
	data = data_uv(kind)
	for j in range(rows):
		s0, s1 = pts[j][1], pts[j + 1][1]
		for k in range(sides):
			k1 = (k + 1) % sides
			a0, a1 = TAU * k / sides, TAU * (k + 1) / sides
			idx = [grid[j][k][0], grid[j][k1][0], grid[j + 1][k1][0], grid[j + 1][k][0]]
			hint = grid[j][k][1] + grid[j + 1][k1][1]
			md.face(idx, [uv_fn(a0, s0), uv_fn(a1, s0), uv_fn(a1, s1), uv_fn(a0, s1)], [data] * 4,
				tuple(hint) if hint.length > 1e-6 else None)


def leg_frames(samples):
	"""Centre, radius, weight and t along the leg (pointing +X), Catmull-Rom through LEG_PATH."""
	out = []
	n = len(LEG_PATH) - 1
	for j in range(samples + 1):
		f = j / samples * n
		i = min(int(f), n - 1)
		lt = f - i
		p0, p1, p2, p3 = LEG_PATH[max(i - 1, 0)], LEG_PATH[i], LEG_PATH[i + 1], LEG_PATH[min(i + 2, n)]
		c = catmull(p0, p1, p2, p3, lt)
		rad = lerp(LEG_RADII[i], LEG_RADII[i + 1], smooth(0.0, 1.0, lt))
		w = lerp(LEG_WEIGHTS[i], LEG_WEIGHTS[i + 1], lt)
		out.append((Vector((c[0], c[1], 0.0)), rad, w, j / samples))
	return out


def leg(md, angle, tripod, sides, samples, relief=False):
	frames = leg_frames(samples)
	ca, sa = math.cos(angle), math.sin(angle)
	rot = lambda v: Vector((v.x * ca - v.z * sa, v.y, v.x * sa + v.z * ca))
	rings = []
	prev_u = None
	for j, (c, rad, w, t) in enumerate(frames):
		ahead = frames[min(j + 1, samples)][0] - frames[max(j - 1, 0)][0]
		axis = ahead.normalized()
		u = Vector((0, 0, 1)) if prev_u is None else (prev_u - axis * prev_u.dot(axis)).normalized()
		prev_u = u
		v = axis.cross(u)
		ring = []
		for k in range(sides):
			a = TAU * k / sides
			nrm = u * math.cos(a) + v * math.sin(a)
			p = c + nrm * rad
			if relief:
				p = p + nrm * leg_relief(t, a, tuple(p)) * (rad / 0.03)
			ring.append((md.vert(rot(p)), rot(nrm), w))
		rings.append((ring, t))
	for j in range(samples):
		(r0, t0), (r1, t1) = rings[j], rings[j + 1]
		for k in range(sides):
			k1 = (k + 1) % sides
			u0, u1 = k / sides, (k + 1) / sides
			uvs = [rect_uv(LEG_RECT, u0, t0), rect_uv(LEG_RECT, u1, t0), rect_uv(LEG_RECT, u1, t1), rect_uv(LEG_RECT, u0, t1)]
			ds = [data_uv(3, r0[k][2], tripod), data_uv(3, r0[k1][2], tripod), data_uv(3, r1[k1][2], tripod), data_uv(3, r1[k][2], tripod)]
			hint = r0[k][1] + r1[k1][1]
			md.face([r0[k][0], r0[k1][0], r1[k1][0], r1[k][0]], uvs, ds, tuple(hint))


def knee(k):
	a = LEG_ANGLES[k]
	return Vector((math.cos(a) * 0.47, 1.12, math.sin(a) * 0.47))


def rim_point(a):
	return Vector((math.cos(a) * RIM_R * wob(a), RIM_Y, math.sin(a) * RIM_R * wob(a)))


def bulb_point(a, y):
	r = 0.165 * math.sqrt(min(max(1.0 - ((y - 0.80) / 0.20) ** 2, 0.05), 1.0))
	return Vector((math.cos(a) * r, y, math.sin(a) * r))


def curtain(md, top, bottom, rows, sag, u0, u1, w_top, w_bot, tripod, rng):
	"""A two-sided sheet of silk hung between two edges (lists of points, same count)."""
	cols = len(top) - 1
	grid = []
	for j in range(rows + 1):
		t = j / rows
		row = []
		for i in range(cols + 1):
			p = top[i].lerp(bottom[i], t)
			out = Vector((p.x, 0.0, p.z))
			out = out.normalized() if out.length > 1e-6 else Vector((1, 0, 0))
			p = p + out * sag * math.sin(math.pi * t) + Vector((0, -abs(sag) * 0.3 * math.sin(math.pi * t), 0))
			p = p + out * 0.008 * math.sin(i * 1.7 + j * 2.3 + rng.random() * 6.0) * math.sin(math.pi * t)
			row.append((p, lerp(w_top, w_bot, t)))
		grid.append(row)
	for side in (1.0, -1.0):
		ids = [[md.vert(p) for (p, w) in row] for row in grid]
		for j in range(rows):
			for i in range(cols):
				q = [(j, i), (j, i + 1), (j + 1, i + 1), (j + 1, i)]
				uvs = [rect_uv(SILK_RECT, lerp(u0, u1, b / cols), 1.0 - a / rows) for (a, b) in q]
				ds = [data_uv(4, grid[a][b][1], tripod) for (a, b) in q]
				pa, pb, pc = grid[j][i][0], grid[j][i + 1][0], grid[j + 1][i][0]
				n = (pb - pa).cross(pc - pa)
				out = Vector((pa.x, 0, pa.z))
				if n.dot(out) < 0:
					n = -n
				md.face([ids[a][b] for (a, b) in q], uvs, ds, tuple(n * side))


def arc(a0, a1, n, fn):
	return [fn(lerp(a0, a1, i / n)) for i in range(n + 1)]


def fringe(md, top, lengths, rows, u0, u1, rng):
	"""Silk that hangs free from the rim with a ragged lower edge. Kind 5: the gait
	weight carries how far down the fringe a vertex is, and the shader sways it."""
	cols = len(top) - 1
	longest = max(lengths)
	grid = []
	for j in range(rows + 1):
		t = j / rows
		row = []
		for i in range(cols + 1):
			drop = lengths[i] * t
			out = Vector((top[i].x, 0.0, top[i].z)).normalized()
			p = top[i] + Vector((0, -drop, 0)) + out * (0.02 * math.sin(math.pi * t) - 0.03 * t * t)
			p = p + Vector((math.sin(i * 2.1 + j), 0, math.cos(i * 1.3 + j * 1.7))) * 0.006 * t
			row.append((p, drop / longest, 1.0 - drop / longest))
		grid.append(row)
	for side in (1.0, -1.0):
		ids = [[md.vert(p) for (p, d, v) in row] for row in grid]
		for j in range(rows):
			for i in range(cols):
				q = [(j, i), (j, i + 1), (j + 1, i + 1), (j + 1, i)]
				uvs = [rect_uv(SILK_RECT, lerp(u0, u1, b / cols), grid[a][b][2]) for (a, b) in q]
				ds = [data_uv(5, grid[a][b][1], 0) for (a, b) in q]
				pa, pb, pc = grid[j][i][0], grid[j][i + 1][0], grid[j + 1][i][0]
				n = (pb - pa).cross(pc - pa)
				if n.dot(Vector((pa.x, 0, pa.z))) < 0:
					n = -n
				md.face([ids[a][b] for (a, b) in q], uvs, ds, tuple(n * side))


def build_cortina(md, lod, rng):
	"""A light veil: narrow sheets tie the rim to each knee (they ride with the legs) and to
	the bulb on alternate sides; between them, ragged fringes hang free and sway."""
	rows, cols = [(6, 3), (4, 2), (3, 2)][lod]
	sheets = []
	for k in range(6):
		a = LEG_ANGLES[k]
		kn = knee(k)
		side = Vector((-math.sin(a), 0, math.cos(a)))
		sheets.append((arc(a - 0.22, a + 0.22, cols, rim_point), [kn + side * (i / cols - 0.5) * 0.03 for i in range(cols + 1)],
			0.03, 0.0, 0.40, k % 2))
	if lod < 2:
		for k in (0, 2, 4):
			a0, a1 = LEG_ANGLES[k], LEG_ANGLES[(k + 1) % 6]
			mid = (a0 + a1) * 0.5
			sheets.append((arc(mid - 0.24, mid + 0.24, cols, rim_point), arc(mid - 0.35, mid + 0.35, cols, lambda x: bulb_point(x, 0.76)),
				0.05, 0.0, 0.0, 0))
	for (top, bottom, sag, wt, wb, tri) in sheets:
		u0 = rng.uniform(0.0, 0.6)
		curtain(md, top, bottom, rows, sag, u0, u0 + 0.38, wt, wb, tri, rng)
	count = [10, 6, 3][lod]
	fcols, frows = [(4, 4), (3, 3), (2, 2)][lod]
	for i in range(count):
		mid = TAU * (i + 0.5) / count + rng.uniform(-0.15, 0.15)
		width = rng.uniform(0.18, 0.34)
		lengths = [rng.uniform(0.12, 0.55) for _ in range(fcols + 1)]
		u0 = rng.uniform(0.0, 0.7)
		fringe(md, arc(mid - width, mid + width, fcols, lambda x: rim_point(x) + Vector((0, -0.004, 0))), lengths, frows, u0, u0 + 0.28, rng)


CAP_UV = lambda a, s: polar_uv(CAP_C, 1.0 - s, a)      # profile runs rim -> crown
GILL_UV = lambda a, s: polar_uv(GILL_C, s, a)          # stalk -> rim
STALK_UV = lambda a, s: rect_uv(STALK_RECT, a / TAU, s)


def build_lod(lod, rng):
	"""Returns (body, silk) mesh data: the silk becomes the mesh's second, blended surface."""
	md = MeshData()
	cap_rows, cap_sides = [(16, 64), (9, 36), (5, 14)][lod]
	lathe(md, shift_profile(CAP_PROFILE, CAP_BASE), cap_rows, cap_sides, CAP_UV, 1, wobble=True)
	lathe(md, [(r, CAP_BASE + y) for (r, y) in UNDER_PROFILE], [5, 3, 2][lod], cap_sides, GILL_UV, 2,
		wobble=True, wobble_fade=lambda s: smooth(0.4, 1.0, s))
	lathe(md, STALK_PROFILE, [20, 11, 6][lod], [24, 14, 8][lod], STALK_UV, 0)
	for k, a in enumerate(LEG_ANGLES):
		leg(md, a, k % 2, [10, 6, 4][lod], [22, 12, 7][lod])
	silk = MeshData()
	build_cortina(silk, lod, rng)
	return md, silk


def shift_profile(profile, dy):
	return [(r, y + dy) for (r, y) in profile]


def build_sculpt():
	"""High-detail sources for baking: one object per part. Only leg 0 is baked."""
	parts = {}
	md = MeshData()
	lathe(md, shift_profile(CAP_PROFILE, CAP_BASE), 180, 720, CAP_UV, 1, wobble=True,
		relief=lambda a, s, p: cap_relief(a, 1.0 - s, p))
	parts["cap"] = md.obj("hi_cap")
	md = MeshData()
	lathe(md, [(r, CAP_BASE + y) for (r, y) in UNDER_PROFILE], 70, 1056, GILL_UV, 2, wobble=True,
		wobble_fade=lambda s: smooth(0.4, 1.0, s), relief=lambda a, s, p: gill_relief(a, s) + 0.0006 * noise.noise(Vector(p) * 80))
	parts["gill"] = md.obj("hi_gill")
	md = MeshData()
	lathe(md, STALK_PROFILE, 220, 320, STALK_UV, 0, relief=lambda a, s, p: stalk_relief(a, p[1], p))
	parts["stalk"] = md.obj("hi_stalk")
	for k, a in enumerate(LEG_ANGLES):
		md = MeshData()
		leg(md, a, 0, 40, 320, relief=True)
		parts["leg%d" % k] = md.obj("hi_leg%d" % k)
	return parts


def build_bake_lows():
	"""Bake targets: the sculpt's shapes without their relief, dense and smooth, with the
	game meshes' atlas UVs. Same parameterisation means the same tangent frames, so the
	baked tangent-space normals fit every LOD, and no low-poly chord can miss the rays."""
	lows = {}
	md = MeshData()
	lathe(md, shift_profile(CAP_PROFILE, CAP_BASE), 90, 360, CAP_UV, 1, wobble=True)
	lows["cap"] = md.obj("lo_cap")
	md = MeshData()
	lathe(md, [(r, CAP_BASE + y) for (r, y) in UNDER_PROFILE], 35, 528, GILL_UV, 2, wobble=True, wobble_fade=lambda s: smooth(0.4, 1.0, s))
	lows["gill"] = md.obj("lo_gill")
	md = MeshData()
	lathe(md, STALK_PROFILE, 110, 160, STALK_UV, 0)
	lows["stalk"] = md.obj("lo_stalk")
	md = MeshData()
	leg(md, LEG_ANGLES[0], 0, 20, 160)
	lows["leg"] = md.obj("lo_leg")
	return lows


# --- baking --------------------------------------------------------------------------------

def setup_cycles():
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	if not OPT.get("cpu"):
		try:
			prefs = bpy.context.preferences.addons["cycles"].preferences
			for backend in ("OPTIX", "CUDA"):
				try:
					prefs.compute_device_type = backend
					prefs.get_devices()
					gpus = [d for d in prefs.devices if d.type == backend]
					if gpus:
						for d in prefs.devices:
							d.use = d.type == backend
						scene.cycles.device = "GPU"
						log("baking on %s: %s" % (backend, ", ".join(d.name for d in gpus)))
						break
				except Exception:
					continue
		except Exception as e:
			log("GPU setup failed (%s); baking on CPU" % e)
	# occlusion is local: the gill furrows, the knee, the stalk under the cap
	world = bpy.data.worlds.new("bake_world")
	scene.world = world
	world.light_settings.distance = 0.18
	scene.render.bake.margin = 6
	scene.render.bake.margin_type = "EXTEND"


def bake_target(ob, img):
	mat = bpy.data.materials.new(ob.name + "_bake")
	mat.use_nodes = True
	node = mat.node_tree.nodes.new("ShaderNodeTexImage")
	node.image = img
	mat.node_tree.nodes.active = node
	ob.data.materials.clear()
	ob.data.materials.append(mat)


def new_image(name, color, non_color=True):
	img = bpy.data.images.new(name, SIZE, SIZE, alpha=True, float_buffer=False)
	img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
	img.generated_color = color
	return img


def pixels(img):
	buf = np.empty(SIZE * SIZE * 4, dtype=np.float32)
	img.pixels.foreach_get(buf)
	return buf.reshape(SIZE, SIZE, 4)


def bake(kind, low, highs, extrusion, distance, samples):
	scene = bpy.context.scene
	scene.cycles.samples = samples
	img = new_image("bake_%s_%s" % (kind, low.name), (0.5, 0.5, 1.0, 1.0) if kind == "NORMAL" else (1, 1, 1, 1))
	bake_target(low, img)
	bpy.ops.object.select_all(action="DESELECT")
	for h in highs:
		h.select_set(True)
	low.select_set(True)
	bpy.context.view_layer.objects.active = low
	bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=extrusion,
		max_ray_distance=distance, normal_space="TANGENT", margin=6)
	return pixels(img)


def region_masks():
	ys, xs = np.mgrid[0:SIZE, 0:SIZE]
	u = (xs + 0.5) / SIZE
	v = (ys + 0.5) / SIZE
	pad = 5.0 / SIZE
	disk = lambda c: (u - c[0]) ** 2 + (v - c[1]) ** 2 <= (DISK_R + pad) ** 2
	rect = lambda r: (u >= r[0] - pad) & (u <= r[2] + pad) & (v >= r[1] - pad) & (v <= r[3] + pad)
	return u, v, {"cap": disk(CAP_C), "gill": disk(GILL_C), "stalk": rect(STALK_RECT), "leg": rect(LEG_RECT), "silk": rect(SILK_RECT)}


# --- painting ------------------------------------------------------------------------------

def paint_body(u, v, masks):
	"""Colour, roughness and glow for the solid parts, from their atlas coordinates."""
	albedo = np.zeros((SIZE, SIZE, 3), np.float32)
	rough = np.full((SIZE, SIZE), 0.6, np.float32)
	glow = np.zeros((SIZE, SIZE), np.float32)
	for part in ("cap", "gill", "stalk", "leg"):
		ys, xs = np.nonzero(masks[part])
		for y, x in zip(ys.tolist(), xs.tolist()):
			uu, vv = u[y, x], v[y, x]
			if part in ("cap", "gill"):
				c = CAP_C if part == "cap" else GILL_C
				dx, dy = uu - c[0], vv - c[1]
				s = min(math.hypot(dx, dy) / DISK_R, 1.0)
				a = math.atan2(dy, dx)
				if part == "cap":
					# s: crown (0) to rim (1)
					p = (math.cos(a) * s * 0.5, 1.8 - s * 0.3, math.sin(a) * s * 0.5)
					base = mix3((0.36, 0.15, 0.56), (0.62, 0.45, 0.81), smooth(0.05, 1.0, s) * 0.9)
					mott = noise.noise(Vector(p) * 5.0)
					base = mix3(base, (0.30, 0.12, 0.47), max(mott, 0.0) * 0.35)
					f = cap_fibril(a, s)
					silk = smooth(0.15, 0.65, f) * 0.55 + smooth(0.55, 0.8, noise.noise(Vector(p) * 70.0)) * 0.25
					col = mix3(base, (0.84, 0.77, 0.94), silk)
					veil = smooth(0.9, 1.0, s) * smooth(0.1, 0.5, noise.noise(Vector(p) * 18.0))
					col = mix3(col, (0.92, 0.89, 0.86), veil * 0.6)
					r = 0.26 + 0.10 * silk + 0.10 * veil + 0.05 * mott
				else:
					g = gill_relief(a, s) / 0.030
					col = mix3((0.30, 0.18, 0.44), (0.55, 0.40, 0.70), g * 0.8 + 0.1)
					col = mix3(col, (0.62, 0.52, 0.42), smooth(0.85, 1.0, s) * 0.35)
					r = 0.72
			elif part == "stalk":
				a = (uu - STALK_RECT[0]) / (STALK_RECT[2] - STALK_RECT[0]) * TAU
				s = (vv - STALK_RECT[1]) / (STALK_RECT[3] - STALK_RECT[1])
				height = lerp(0.595, 1.505, s)
				p = (math.cos(a) * 0.12, height, math.sin(a) * 0.12)
				violet = smooth(0.95, 1.38, height)
				pale = mix3((0.91, 0.87, 0.95), (0.80, 0.72, 0.90), 0.5 + 0.5 * noise.noise(Vector(p) * 9.0))
				col = mix3(pale, (0.52, 0.35, 0.74), violet)
				fib = stalk_fiber(a, height)
				col = mix3(col, (0.95, 0.92, 0.98), smooth(0.25, 0.7, fib) * 0.35)
				vein = bulb_vein(p) * bulb_mask(height) * smooth(0.6, 0.7, height)
				col = mix3(col, (0.93, 0.70, 0.34), vein * 0.6)
				glow[y, x] = vein * 0.45
				r = 0.42 + 0.12 * smooth(0.25, 0.7, fib) - 0.1 * violet
			else:
				a = (uu - LEG_RECT[0]) / (LEG_RECT[2] - LEG_RECT[0]) * TAU
				t = (vv - LEG_RECT[1]) / (LEG_RECT[3] - LEG_RECT[1])
				ridge = noise.noise(Vector((math.cos(a) * 3.0, math.sin(a) * 3.0, t * 42.0)))
				lilac = (0.77, 0.67, 0.90)
				col = mix3(lilac, (0.86, 0.80, 0.93), math.exp(-((t - 0.40) / 0.07) ** 2) * 0.6)
				col = mix3(col, (0.70, 0.58, 0.45), smooth(0.70, 0.92, t))
				col = mix3(col, (0.18, 0.12, 0.08), smooth(0.93, 0.985, t))
				col = mix3(col, (col[0] * 0.8, col[1] * 0.78, col[2] * 0.85), smooth(0.2, 0.8, ridge) * 0.5)
				r = 0.38 + 0.15 * smooth(0.2, 0.8, ridge) - 0.1 * smooth(0.93, 0.99, t)
			albedo[y, x] = col
			rough[y, x] = r
	return albedo, rough, glow


def paint_silk(rng):
	"""Cobweb silk for the cortina curtains: fine wandering threads from top to bottom,
	sagging cross threads, a few gold threads and dew beads. Returns alpha, gold, bead."""
	x0, y0 = int(SILK_RECT[0] * SIZE), int(SILK_RECT[1] * SIZE)
	x1, y1 = int(SILK_RECT[2] * SIZE), int(SILK_RECT[3] * SIZE)
	w, h = x1 - x0, y1 - y0
	alpha = np.zeros((h, w), np.float32)
	gold = np.zeros((h, w), np.float32)
	bead = np.zeros((h, w), np.float32)

	def segment(ax, ay, bx, by, width, inten, is_gold):
		lo_x, hi_x = int(max(min(ax, bx) - width - 2, 0)), int(min(max(ax, bx) + width + 2, w - 1))
		lo_y, hi_y = int(max(min(ay, by) - width - 2, 0)), int(min(max(ay, by) + width + 2, h - 1))
		if hi_x < lo_x or hi_y < lo_y:
			return
		yy, xx = np.mgrid[lo_y:hi_y + 1, lo_x:hi_x + 1].astype(np.float32)
		dx, dy = bx - ax, by - ay
		ll = max(dx * dx + dy * dy, 1e-6)
		t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / ll, 0.0, 1.0)
		d = np.hypot(xx - (ax + t * dx), yy - (ay + t * dy))
		a = np.clip(width * 0.5 + 0.5 - d, 0.0, 1.0) * inten
		sub = alpha[lo_y:hi_y + 1, lo_x:hi_x + 1]
		alpha[lo_y:hi_y + 1, lo_x:hi_x + 1] = 1.0 - (1.0 - sub) * (1.0 - a)
		if is_gold:
			g = gold[lo_y:hi_y + 1, lo_x:hi_x + 1]
			gold[lo_y:hi_y + 1, lo_x:hi_x + 1] = np.maximum(g, a)

	def polyline(pts, width, inten, is_gold):
		for i in range(len(pts) - 1):
			segment(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], width, inten, is_gold)

	threads = []
	tips = []   # threads that stop short end in a dew drop, so they read as hanging strands
	for i in range(38):
		x = rng.uniform(4, w - 4)
		y = h - 1.0
		end = rng.uniform(0.0, h * 0.25) if rng.random() < 0.55 else rng.uniform(h * 0.3, h * 0.8)
		drift = rng.uniform(-0.12, 0.12)
		pts = [(x, y)]
		while y > end:
			y -= rng.uniform(10, 22)
			drift = max(min(drift + rng.uniform(-0.08, 0.08), 0.3), -0.3)
			x = min(max(x + drift * 16 + rng.uniform(-1.5, 1.5), 2), w - 3)
			pts.append((x, max(y, end)))
		is_gold = rng.random() < 0.12
		polyline(pts, rng.uniform(1.6, 2.2) if is_gold else rng.uniform(0.9, 1.6), rng.uniform(0.6, 0.95), is_gold)
		threads.append(pts)
		if end > h * 0.3:
			tips.append(pts[-1])
	threads.sort(key=lambda p: p[0][0])
	for i in range(170):
		a = rng.randrange(len(threads) - 1)
		ta, tb = threads[a], threads[a + 1 + (1 if rng.random() < 0.3 and a + 2 < len(threads) else 0)]
		pa = ta[rng.randrange(len(ta))]
		pb = tb[min(max(0, rng.randrange(len(tb))), len(tb) - 1)]
		if abs(pa[1] - pb[1]) > 45:
			continue
		mid = ((pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5 - rng.uniform(2, 9))
		polyline([pa, mid, pb], rng.uniform(0.8, 1.3), rng.uniform(0.45, 0.8), rng.random() < 0.05)
	drops = [threads[rng.randrange(len(threads))] for i in range(28)]
	drops = [p[rng.randrange(len(p))] for p in drops] + tips
	for (cx, cy) in drops:
		r = rng.uniform(1.4, 2.6)
		lo_x, hi_x = int(max(cx - r - 2, 0)), int(min(cx + r + 2, w - 1))
		lo_y, hi_y = int(max(cy - r - 2, 0)), int(min(cy + r + 2, h - 1))
		yy, xx = np.mgrid[lo_y:hi_y + 1, lo_x:hi_x + 1].astype(np.float32)
		d = np.hypot(xx - cx, yy - cy)
		a = np.clip(r + 0.5 - d, 0.0, 1.0)
		alpha[lo_y:hi_y + 1, lo_x:hi_x + 1] = np.maximum(alpha[lo_y:hi_y + 1, lo_x:hi_x + 1], a)
		bead[lo_y:hi_y + 1, lo_x:hi_x + 1] = np.maximum(bead[lo_y:hi_y + 1, lo_x:hi_x + 1], a)
	return (x0, y0, x1, y1), alpha, gold, bead


def save_png(name, rgba, non_color):
	img = bpy.data.images.new(name, SIZE, SIZE, alpha=True, float_buffer=False)
	img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
	img.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).astype(np.float32).ravel())
	img.filepath_raw = os.path.join(OUT, name + ".png")
	img.file_format = "PNG"
	img.save()
	log("wrote " + name + ".png")


# --- export --------------------------------------------------------------------------------

def export_glb(objects, path):
	bpy.ops.object.select_all(action="DESELECT")
	for ob in objects:
		ob.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_texcoords=True,
		export_normals=True, export_tangents=True, export_materials="NONE", export_vertex_color="NONE",
		export_yup=True, export_apply=False)
	tris = sum(len(p.vertices) - 2 for ob in objects for p in ob.data.polygons)
	log("wrote %s (%d triangles)" % (os.path.basename(path), tris))
	return tris


def main():
	os.makedirs(OUT, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	rng = random.Random(60317)
	setup_cycles()
	log("building sculpt")
	hi = build_sculpt()
	lows = build_bake_lows()
	for ob in lows.values():
		for attr in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_transmission", "visible_volume_scatter", "visible_shadow"):
			setattr(ob, attr, False)
	log("sculpt: %d faces" % sum(len(o.data.polygons) for o in hi.values()))
	u, v, masks = region_masks()
	normal = np.zeros((SIZE, SIZE, 4), np.float32)
	normal[...] = (0.5, 0.5, 1.0, 1.0)
	ao = np.ones((SIZE, SIZE), np.float32)
	all_hi = list(hi.values())
	sources = {"cap": [hi["cap"]], "gill": [hi["gill"]], "stalk": [hi["stalk"]], "leg": [hi["leg0"]]}
	# ray reach: the gill blades stand 3 cm proud of the flat underside
	reach = {"cap": (0.008, 0.02), "gill": (0.034, 0.07), "stalk": (0.006, 0.015), "leg": (0.003, 0.008)}
	for part, low in lows.items():
		ext, dist = reach[part]
		px = bake("NORMAL", low, sources[part], ext, dist, 8)
		normal[masks[part]] = px[masks[part]]
		log("normals baked: " + part)
		px = bake("AO", low, all_hi, ext, dist, 96)
		ao[masks[part]] = px[..., 0][masks[part]]
		log("occlusion baked: " + part)
	# Poles and the needle-thin foot tip are where bake rays misbehave: fade them to flat.
	flat = np.array((0.5, 0.5, 1.0, 1.0), np.float32)
	s_cap = np.hypot(u - CAP_C[0], v - CAP_C[1]) / DISK_R
	s_stalk = (v - STALK_RECT[1]) / (STALK_RECT[3] - STALK_RECT[1])
	t_leg = (v - LEG_RECT[1]) / (LEG_RECT[3] - LEG_RECT[1])
	keep = np.ones((SIZE, SIZE), np.float32)
	keep[masks["cap"]] = np.clip((s_cap[masks["cap"]] - 0.02) / 0.05, 0.0, 1.0)
	keep[masks["stalk"]] = np.clip(s_stalk[masks["stalk"]] / 0.04, 0.0, 1.0)
	keep[masks["leg"]] = np.clip((0.975 - t_leg[masks["leg"]]) / 0.05, 0.0, 1.0)
	normal = flat + (normal - flat) * keep[..., None]
	ao = 1.0 + (ao - 1.0) * keep
	# Deep gill furrows are truly dark; lift them so the underside still reads in play.
	ao[masks["gill"]] = 0.45 + 0.55 * ao[masks["gill"]]
	log("painting")
	albedo, rough, glow = paint_body(u, v, masks)
	(sx0, sy0, sx1, sy1), silk, gold, bead = paint_silk(rng)
	silk_rgb = np.empty((sy1 - sy0, sx1 - sx0, 3), np.float32)
	silk_rgb[...] = (0.93, 0.91, 0.88)
	spread = np.clip(gold * 1.6, 0.0, 1.0)[..., None]
	silk_rgb = silk_rgb * (1.0 - spread) + np.array((1.0, 0.78, 0.38), np.float32) * spread
	silk_rgb = silk_rgb * (1.0 - bead[..., None]) + bead[..., None]
	alb = np.zeros((SIZE, SIZE, 4), np.float32)
	alb[..., :3] = albedo
	alb[..., 3] = 1.0
	alb[sy0:sy1, sx0:sx1, :3] = silk_rgb
	alb[sy0:sy1, sx0:sx1, 3] = silk
	orm = np.zeros((SIZE, SIZE, 4), np.float32)
	orm[..., 0] = ao
	orm[..., 1] = rough
	orm[..., 2] = glow
	orm[..., 3] = 1.0
	orm[sy0:sy1, sx0:sx1, 1] = 0.45
	orm[sy0:sy1, sx0:sx1, 2] = np.maximum(gold * 0.9, bead * 0.25)
	save_png("webcap_albedo", alb, False)
	save_png("webcap_normal", normal, True)
	save_png("webcap_orm", orm, True)
	for ob in list(hi.values()) + list(lows.values()):
		bpy.data.objects.remove(ob)
	stats = {}
	for lod, name in enumerate(("close", "battle", "distant")):
		body, silk = build_lod(lod, random.Random(60317 + lod))
		objects = [body.obj("Webcap_%s_body" % name), silk.obj("Webcap_%s_silk" % name)]
		stats[name] = export_glb(objects, os.path.join(OUT, "webcap_%s.glb" % name))
	log("done: " + ", ".join("%s %d" % kv for kv in stats.items()))


main()
