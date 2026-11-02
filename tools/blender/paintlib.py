"""Vectorised building blocks for RHIZOMORPH unit art (Blender 4.2, numpy). Pairs with unitlib.py.

The method these support (see .claude/skills/unit-art/SKILL.md):
  1. Every surface is a parametric grid: a function (a, t) -> position, evaluated on numpy arrays.
  2. Relief (pits, ridges, fibres, seams) and paint (stripes, spots, bands, dust) are functions of
     the SAME parameters or 3D position, so the baked normals and the painted colour line up.
  3. A dense sculpt (relief on) is baked by Cycles onto smooth bake targets that share the game
     meshes' UVs; the game meshes are the same functions at low resolution.

Conventions: game space is Y up, +X forward (g2b converts for Blender). Atlas rects are
(u0, v0, u1, v1) in Blender UV, v up. Arrays here are float64; save_png takes float32.
"""
import math

import bpy
import numpy as np

from unitlib import bake, frames_along, log

PI = math.pi
TAU = math.tau


# --- noise and shaping (arrays in, arrays out; scalars work too) -------------------------------

def _hash(ix, iy, iz):
	h = (ix * 374761393 + iy * 668265263 + iz * 2147483647) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def vnoise(x, y, z):
	"""Smooth value noise in [-1, 1]. One unit of input = one feature: scale the input by
	1 / (feature size in metres) when you evaluate it on positions."""
	x, y, z = np.asarray(x, np.float64), np.asarray(y, np.float64), np.asarray(z, np.float64)
	fx, fy, fz = np.floor(x), np.floor(y), np.floor(z)
	ix, iy, iz = fx.astype(np.int64), fy.astype(np.int64), fz.astype(np.int64)
	tx, ty, tz = x - fx, y - fy, z - fz
	tx, ty, tz = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty), tz * tz * (3 - 2 * tz)
	out = 0.0
	for dx in (0, 1):
		for dy in (0, 1):
			for dz in (0, 1):
				w = (tx if dx else 1 - tx) * (ty if dy else 1 - ty) * (tz if dz else 1 - tz)
				out = out + w * _hash(ix + dx, iy + dy, iz + dz)
	return out * 2.0 - 1.0


def fbm(x, y, z, octaves=3):
	"""Fractal value noise, roughly [-1, 1]: big shapes with smaller ones riding on them."""
	s, amp, f = 0.0, 0.5, 1.0
	for i in range(octaves):
		s = s + amp * vnoise(x * f + i * 17.3, y * f - i * 9.1, z * f + i * 5.7)
		amp *= 0.5
		f *= 2.03
	return s


def pnoise(P, scale, octaves=1, seed=0.0):
	"""Noise on (..., 3) positions with features about 1 / scale metres across."""
	x, y, z = P[..., 0] * scale + seed, P[..., 1] * scale - seed * 0.7, P[..., 2] * scale + seed * 1.3
	return vnoise(x, y, z) if octaves == 1 else fbm(x, y, z, octaves)


def cells(P, size, seed=0.0):
	"""Voronoi cells of about `size` metres. Returns (f1, f2, cid): distance to the nearest and
	second-nearest feature point (in cell units) and a per-cell random in [0, 1).
	Round pits, warts, spots: smooth(r, 0, f1). A net, honeycomb or cracks between cells:
	smooth(w, 0, f2 - f1). Per-cell colour or height variation: cid."""
	q = P / size
	base = np.floor(q)
	best = np.full(q.shape[:-1], 9.0)
	second = np.full(q.shape[:-1], 9.0)
	cid = np.zeros(q.shape[:-1])
	for dx in (-1, 0, 1):
		for dy in (-1, 0, 1):
			for dz in (-1, 0, 1):
				c = base + np.array([dx, dy, dz])
				ci = c.astype(np.int64)
				jit = np.stack([_hash(ci[..., 0] + int(seed * 7), ci[..., 1], ci[..., 2]),
					_hash(ci[..., 0], ci[..., 1] + 911, ci[..., 2]), _hash(ci[..., 0], ci[..., 1], ci[..., 2] + 517)], axis=-1)
				d = np.linalg.norm(q - (c + jit), axis=-1)
				closer = d < best
				second = np.where(closer, best, np.minimum(second, d))
				best = np.where(closer, d, best)
				cid = np.where(closer, _hash(ci[..., 0] + 3, ci[..., 1] + 5, ci[..., 2] + 7), cid)
	return best, second, cid


def smooth(e0, e1, x):
	"""smoothstep; e0 > e1 gives a falling edge."""
	t = np.clip((np.asarray(x, np.float64) - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3 - 2 * t)


def mix(a, b, t):
	"""Blend colours a -> b by mask t (any shape); a and b are (3,) or (..., 3)."""
	t = np.asarray(t)[..., None]
	return np.asarray(a) * (1 - t) + np.asarray(b) * t


def ramp(stops, t):
	"""A colour ramp: stops = [(t0, (r, g, b)), (t1, ...), ...] with increasing t. Use it to put a
	hue shift into a value change (e.g. dark rust -> orange -> pale gold), not just a lerp."""
	t = np.asarray(t, np.float64)
	out = np.zeros(t.shape + (3,))
	out[...] = stops[0][1]
	for (t0, c0), (t1, c1) in zip(stops[:-1], stops[1:]):
		f = np.clip((t - t0) / max(t1 - t0, 1e-9), 0.0, 1.0)
		inside = t >= t0
		out = np.where(inside[..., None], mix(c0, c1, f), out)
	return out


def g2b(p):
	return np.stack([p[..., 0], -p[..., 2], p[..., 1]], axis=-1)


# --- meshes: numpy grids gathered into one Blender object ------------------------------------

class Acc:
	"""Collects grids; .obj(name) makes one Blender mesh with UVMap (atlas) and data UV layers."""

	def __init__(self):
		self.verts, self.quads, self.uv, self.data = [], [], [], []
		self.n = 0

	def grid(self, P, N, UV, D, wrap=True):
		"""P, N: (R+1, C, 3) if wrap else (R+1, C+1, 3); UV, D: (R+1, C+1, 2). Faces point along N."""
		R = P.shape[0] - 1
		C = UV.shape[1] - 1
		cols = P.shape[1]
		idx = np.arange(P.shape[0] * cols).reshape(P.shape[0], cols) + self.n
		j, i = np.mgrid[0:R, 0:C]
		i1 = (i + 1) % cols if wrap else i + 1
		q = np.stack([idx[j, i], idx[j, i1], idx[j + 1, i1], idx[j + 1, i]], axis=-1).reshape(-1, 4)
		uvq = np.stack([UV[j, i], UV[j, i + 1], UV[j + 1, i + 1], UV[j + 1, i]], axis=2).reshape(-1, 4, 2)
		dq = np.stack([D[j, i], D[j, i + 1], D[j + 1, i + 1], D[j + 1, i]], axis=2).reshape(-1, 4, 2)
		# orient every face along the given normals
		flat = P.reshape(-1, 3)
		a, b, c = flat[q[:, 0] - self.n], flat[q[:, 1] - self.n], flat[q[:, 2] - self.n]
		d4 = flat[q[:, 3] - self.n]
		fn = np.cross(c - a, d4 - b)
		hint = N.reshape(-1, 3)[q[:, 0] - self.n] + N.reshape(-1, 3)[q[:, 2] - self.n]
		flip = np.einsum("ij,ij->i", fn, hint) < 0
		ok = np.einsum("ij,ij->i", fn, fn) > 1e-18
		if ok.any() and flip[ok].mean() > 0.5:
			q, uvq, dq = q[:, ::-1], uvq[:, ::-1], dq[:, ::-1]
		self.verts.append(flat)
		self.quads.append(q)
		self.uv.append(uvq.reshape(-1, 2))
		self.data.append(dq.reshape(-1, 2))
		self.n += flat.shape[0]

	def obj(self, name):
		verts = g2b(np.concatenate(self.verts))
		quads = np.concatenate(self.quads)
		me = bpy.data.meshes.new(name)
		me.from_pydata(verts.tolist(), [], quads.tolist())
		uv = me.uv_layers.new(name="UVMap")
		data = me.uv_layers.new(name="data")
		uv.data.foreach_set("uv", np.concatenate(self.uv).astype(np.float32).ravel())
		data.data.foreach_set("uv", np.concatenate(self.data).astype(np.float32).ravel())
		me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
		me.uv_layers.active = uv
		uv.active_render = True
		me.update()
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		return ob


def grid_normals(P, wrap=True):
	"""Normals of a (rows, cols) grid from central differences (orient them with orient_out)."""
	if wrap:
		da = np.roll(P, -1, axis=1) - np.roll(P, 1, axis=1)
	else:
		da = np.gradient(P, axis=1)
	dt = np.gradient(P, axis=0)
	n = np.cross(dt, da)
	ln = np.linalg.norm(n, axis=-1, keepdims=True)
	return n / np.maximum(ln, 1e-12)


def rect_uv(rect, u, v):
	return np.stack([rect[0] + (rect[2] - rect[0]) * u, rect[1] + (rect[3] - rect[1]) * v], axis=-1)


def data_arr(kind, weight, group, shape):
	"""The data UV: u = kind + 0.98 * weight, v = group (glTF flips v: shaders read 1 - UV2.y)."""
	u = np.broadcast_to(kind + 0.98 * np.clip(weight, 0.0, 1.0), shape)
	v = np.broadcast_to(np.asarray(group, np.float64), shape)
	return np.stack([u, v], axis=-1)


def orient_out(N, P, centre):
	s = np.sign(np.einsum("...i,...i->...", N, P - centre).mean())
	return N * (1.0 if s >= 0 else -1.0)


def surface(acc, fn, centre, rows, cols, rect, kind, group=0.0, relief=None, weight=0.0):
	"""A closed parametric surface: fn(a, t) -> (P (..., 3), extra) with a in [-pi, pi) round it
	(seam at a = -pi, so put -pi where nobody looks) and t in [0, 1] pole to pole.
	relief(a, t, P) -> displacement along the normal in metres (sculpt only).
	The atlas rect maps u = (a + pi) / tau, v = t: paint with the same fn via texel_grid."""
	j, i = np.mgrid[0:rows + 1, 0:cols + 1]
	t = j / rows
	u = i / cols
	a = u * TAU - PI
	P, _ = fn(a, t)
	N = orient_out(grid_normals(P[:, :-1]), P[:, :-1], np.asarray(centre))
	Pw = P[:, :-1]
	if relief is not None:
		Pw = Pw + N * relief(a[:, :-1], t[:, :-1], Pw)[..., None]
	acc.grid(Pw, N, rect_uv(rect, u, t), data_arr(kind, weight, group, t.shape))


def ellipsoid(acc, centre, radii, kind, group, rect, rows, cols, rot=0.0):
	j, i = np.mgrid[0:rows + 1, 0:cols + 1]
	v = j / rows
	u = i / cols
	th = PI * v
	ph = u * TAU
	n = np.stack([np.sin(th) * np.cos(ph), -np.cos(th), np.sin(th) * np.sin(ph)], axis=-1)
	P = n * np.array(radii)
	c, s = math.cos(rot), math.sin(rot)
	P = np.stack([P[..., 0] * c - P[..., 1] * s, P[..., 0] * s + P[..., 1] * c, P[..., 2]], axis=-1) + np.array(centre)
	N = orient_out(grid_normals(P[:, :-1]), P[:, :-1], np.array(centre))
	acc.grid(P[:, :-1], N, rect_uv(rect, u, v), data_arr(kind, 0.0, group, v.shape))


def sweep(acc, path, radii, sides, samples, rect, kind, group, weight_fn, relief=None, radius_fn=None):
	"""A tube along a Catmull-Rom path, radius lerped through radii (one per path point).
	weight_fn(t) -> gait weight along it; relief(t, angle, P) -> displacement; radius_fn(t) scales
	the radius (beads, joints, clubs). Atlas u = round the tube, v = t along it."""
	from mathutils import Vector
	fr = frames_along([Vector(p) for p in path], radii, samples)
	C = np.array([list(f[0]) for f in fr])
	R = np.array([f[1] for f in fr])
	T = np.array([f[2] for f in fr])
	U = np.array([list(f[4]) for f in fr])
	V = np.array([list(f[5]) for f in fr])
	if radius_fn is not None:
		R = R * radius_fn(T)
	ang = np.arange(sides + 1) / sides * TAU
	n = U[:, None, :] * np.cos(ang)[None, :, None] + V[:, None, :] * np.sin(ang)[None, :, None]
	P = C[:, None, :] + n * R[:, None, None]
	if relief is not None:
		P = P + n * relief(T[:, None], ang[None, :], P)[..., None]
	uu, tt = np.meshgrid(np.arange(sides + 1) / sides, T)
	acc.grid(P[:, :-1], n[:, :-1], rect_uv(rect, uu, tt), data_arr(kind, weight_fn(tt), group, tt.shape))
	return C, T


def tube_points(path, radii, u, t, radius_fn=None, samples=400):
	"""Positions on a sweep() tube at atlas coordinates u (round it) and t (along it), for painting
	tubes in 3D exactly where the sculpt put its relief."""
	from mathutils import Vector
	fr = frames_along([Vector(p) for p in path], radii, samples)
	C = np.array([list(f[0]) for f in fr])
	R = np.array([f[1] for f in fr])
	T = np.array([f[2] for f in fr])
	U = np.array([list(f[4]) for f in fr])
	V = np.array([list(f[5]) for f in fr])
	f = np.clip(np.asarray(t), 0.0, 1.0) * samples
	i = np.minimum(f.astype(np.int64), samples - 1)
	w = (f - i)[..., None]
	lerp = lambda A: A[i] * (1 - w) + A[i + 1] * w
	r = R[i] * (1 - w[..., 0]) + R[i + 1] * w[..., 0]
	if radius_fn is not None:
		r = r * radius_fn(np.asarray(t))
	ang = np.asarray(u) * TAU
	n = lerp(U) * np.cos(ang)[..., None] + lerp(V) * np.sin(ang)[..., None]
	return lerp(C) + n * r[..., None]


def tri_count(ob):
	return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# --- the atlas -------------------------------------------------------------------------------

def texel_grid(rect, size):
	"""Every texel of an atlas rect: (slice for atlas[...], u, v), u and v in [0, 1] as the mesh
	maps them. Evaluate the part's own surface function on (u, v) to paint it in 3D."""
	x0, x1 = int(rect[0] * size), int(math.ceil(rect[2] * size))
	y0, y1 = int(rect[1] * size), int(math.ceil(rect[3] * size))
	ys, xs = np.mgrid[y0:y1, x0:x1]
	u = np.clip(((xs + 0.5) / size - rect[0]) / (rect[2] - rect[0]), 0.0, 1.0)
	v = np.clip(((ys + 0.5) / size - rect[1]) / (rect[3] - rect[1]), 0.0, 1.0)
	return (slice(y0, y1), slice(x0, x1)), u, v


def rect_masks(size, rects, pad_px=4.0):
	"""u, v of every texel and a boolean mask per named rect (padded for the bake margin)."""
	yy, xx = np.mgrid[0:size, 0:size]
	u = (xx + 0.5) / size
	v = (yy + 0.5) / size
	pad = pad_px / size
	masks = {k: (u >= r[0] - pad) & (u <= r[2] + pad) & (v >= r[1] - pad) & (v <= r[3] + pad) for k, r in rects.items()}
	return u, v, masks


def bake_atlas(parts, rects, size, tag, normal_samples=8, ao_samples=96):
	"""Bake every part's sculpt onto its smooth bake target and gather one atlas.
	parts: {name: {"low": obj, "normal_from": [hi objs], "ao_from": [hi objs], "reach": (cage, max ray),
	"poles": (lo_end, hi_end) or None}}; rects: {name: rect} covering at least the parts.
	reach: keep max ray just above the relief depth; too long and rays hit neighbouring parts.
	ao_from: include every nearby part (all legs, the body) or occlusion comes out lopsided.
	poles: fade bake noise near v = 0 and v = 1 of lathe-like parts (where grids pinch).
	Returns normal (size, size, 4), ao (size, size), u, v, masks."""
	u, v, masks = rect_masks(size, rects)
	normal = np.zeros((size, size, 4), np.float32)
	normal[...] = (0.5, 0.5, 1.0, 1.0)
	ao = np.ones((size, size), np.float32)
	for name, p in parts.items():
		ext, dist = p["reach"]
		m = masks[name]
		px = bake("NORMAL", p["low"], p["normal_from"], ext, dist, normal_samples, size)
		normal[m] = px[m]
		px = bake("AO", p["low"], p["ao_from"], ext, dist, ao_samples, size)
		ao[m] = px[..., 0][m]
		log(tag, "baked " + name)
	flat = np.array((0.5, 0.5, 1.0, 1.0), np.float32)
	keep = np.ones((size, size), np.float32)
	for name, p in parts.items():
		if not p.get("poles"):
			continue
		lo_end, hi_end = p["poles"]
		rect = rects[name]
		f = (v - rect[1]) / (rect[3] - rect[1])
		m = masks[name]
		keep[m] = np.clip((f[m] - lo_end * 0.4) / (lo_end * 0.6), 0.0, 1.0) * np.clip((hi_end - f[m]) / 0.03, 0.0, 1.0) ** 0.5
	normal = flat + (normal - flat) * keep[..., None]
	ao = 1.0 + (ao - 1.0) * keep
	return normal, ao, u, v, masks


# --- quick shape previews (Workbench, about a second) ------------------------------------------

def preview_render(objects, path, target=(0.0, 0.0, 0.5), scale=3.0, views=None, size=(1200, 800)):
	"""Render solid-shaded views of objects (game space target; Blender is Z up) to
	path_<view>.png. Use it for every shape change before paying for a sculpt and bake."""
	from mathutils import Vector
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.display.shading.light = "STUDIO"
	scene.display.shading.color_type = "OBJECT"
	scene.render.resolution_x, scene.render.resolution_y = size
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = scale
	views = views or (("side", 0.0, 0.15), ("q", 0.8, 0.45), ("top", 0.3, 1.4))
	tgt = Vector(g2b(np.array(target, np.float64)))
	for name, yaw, pitch in views:
		d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))).normalized()
		cam.location = tgt + d * 6.0
		cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = path.replace(".png", "_%s.png" % name)
		bpy.ops.render.render(write_still=True)
