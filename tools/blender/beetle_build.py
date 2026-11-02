"""Whitecoat Bulwark / bark-beetle art build, run headless in Blender 4.2:

  blender -b --factory-startup -P tools/blender/beetle_build.py -- [--out=art/beetle] [--size=1024] [--cpu]
  blender -b --factory-startup -P tools/blender/beetle_build.py -- --preview=C:/tmp/beetle.png

After the Veiled Choir roster sheet (reference_images/veiled_choir_roster.png): Leptinotarsa,
the Colorado potato beetle, as the Choir's armoured frontline. A tall, domed, cream-yellow
shell with five black stripes on each elytron, an orange pronotum and head spotted black,
stout orange legs with black knees and tarsi, short clubbed antennae. The infected form
(Beauveria bassiana, white muscardine) adds cottony white tufts bursting from the seams:
along the elytral margins, the suture, the pronotum, the neck and every leg joint.

One mesh per LOD carries both forms: the tufts are their own data kinds, so the game drops
them for a healthy beetle (scripts/whitecoat_beetle.gd) and the shader swells them out of
the seams as a beetle sickens (instance uniform `infect`).

A high-detail sculpt (elytral punctures in rows, the suture groove, the margin lip, the
abdomen's sternites, pronotum and head pits, leg setae and joints, cotton fibre on the
tufts) is baked by Cycles onto three low-poly meshes sharing one 1024 atlas. Colour,
roughness and the infection dust mask are painted from the same functions.

Writes beetle_{close,battle,distant}.glb and beetle_{albedo,normal,orm}.png
(orm: R occlusion, G roughness, B where white spore dust settles on an infected body, A unused).

Data UV (glTF flips v; the shader reads 1 - UV2.y):
  u = kind + 0.98 * weight. kind 0 shell, 1 leg, 2 pronotum, 3 head; 5..8 = a tuft riding kind - 5.
  weight: along a leg (0 hip .. 1 claw), or along an antenna.
  v = group + tuft radius. group: leg index 0..5 (side = k % 2, pair = k / 2) for legs;
  0 head capsule, 1 / 2 left / right antenna, 3 / 4 left / right mandible for the head.
"""
import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from unitlib import bake, frames_along, hide_from_rays, log, save_png, setup_cycles

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0].lstrip("-"): (a.split("=", 1)[1] if "=" in a else True) for a in ARGS}
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, OPT.get("out", "art/beetle"))
SIZE = int(OPT.get("size", 1024))
TAG = "beetle"
PI = math.pi
TAU = math.tau

SHELL, LEG, PRONOTUM, HEAD = 0, 1, 2, 3
TUFT = 5


# --- numpy noise: the same functions shape the sculpt and paint the atlas ------------------------

def _hash(ix, iy, iz):
	h = (ix * 374761393 + iy * 668265263 + iz * 2147483647) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def vnoise(x, y, z):
	"""Smooth value noise in [-1, 1] on arrays."""
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
	s, amp, f = 0.0, 0.5, 1.0
	for i in range(octaves):
		s = s + amp * vnoise(x * f + i * 17.3, y * f - i * 9.1, z * f + i * 5.7)
		amp *= 0.5
		f *= 2.03
	return s


def smooth(e0, e1, x):
	t = np.clip((np.asarray(x, np.float64) - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3 - 2 * t)


def mix(a, b, t):
	t = np.asarray(t)[..., None]
	return np.asarray(a) * (1 - t) + np.asarray(b) * t


def g2b(p):
	return np.stack([p[..., 0], -p[..., 2], p[..., 1]], axis=-1)


# --- a fast mesh accumulator (numpy grids, one from_pydata) ------------------------------------

class Acc:
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
	"""Outward-ish normals of a (rows, cols) grid from central differences."""
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
	u = np.broadcast_to(kind + 0.98 * np.clip(weight, 0.0, 1.0), shape)
	v = np.broadcast_to(np.asarray(group, np.float64), shape)
	return np.stack([u, v], axis=-1)


def orient_out(N, P, centre):
	s = np.sign(np.einsum("...i,...i->...", N, P - centre).mean())
	return N * (1.0 if s >= 0 else -1.0)


# --- atlas regions (Blender UV, v up) -----------------------------------------------------------
SHELL_RECT = (0.006, 0.400, 0.994, 0.994)
PRONOTUM_RECT = (0.006, 0.204, 0.400, 0.392)
HEAD_RECT = (0.408, 0.204, 0.640, 0.392)
ANT_RECT = (0.648, 0.204, 0.700, 0.392)
MAND_RECT = (0.708, 0.204, 0.740, 0.392)
EYE_RECT = (0.748, 0.204, 0.790, 0.392)
LEG_RECT = (0.006, 0.006, 0.400, 0.196)
TUFT_RECTS = [(0.798, 0.204, 0.994, 0.392), (0.408, 0.006, 0.698, 0.196), (0.706, 0.006, 0.994, 0.196)]


# --- the shell: elytra over the abdomen ---------------------------------------------------------
# a runs round the long axis (0 on top, +-pi underneath), t from the rear (0) to the front (1).
SX, SY, SL = -0.10, 0.43, 0.47     # centre x, centre y, half-length
SW, SHU, SHL = 0.40, 0.39, 0.19   # half-width, dome height, belly depth
AM = 1.95                          # the elytral margin, as an angle from the top
STRIPES = [0.31, 0.64, 0.97, 1.31, 1.66]   # stripe centres on each elytron
STRIPE_W = 0.068


def _spow(x, e):
	return np.sign(x) * np.abs(x) ** e


def shell_point(a, t):
	th = PI * np.clip(t, 0.0, 1.0)
	e = 0.66 - 0.30 * t
	s = np.maximum(np.sin(th), 0.0) ** e
	x = SX - SL * np.cos(th)
	ca, sa = np.cos(a), np.sin(a)
	H = np.where(ca > 0, SHU * (1.0 + 0.07 * np.sin(th * 1.2)), SHL)
	y = SY + _spow(ca, 0.82) * H * s
	z = _spow(sa, 0.86) * SW * s * (1.0 + 0.05 * np.sin(th))
	return np.stack([x, y, z], axis=-1), s


def stripe_mask(a, t):
	"""1 on the black stripes and the suture, 0 on the cream ground."""
	aa = np.abs(a)
	wob = 0.012 * vnoise(aa * 9.0, t * 6.0, 1.3)
	m = smooth(0.034, 0.022, aa)                      # the suture
	for k, c in enumerate(STRIPES):
		w = STRIPE_W * (1.0 + 0.15 * (k == 0)) * (0.65 + 0.35 * smooth(0.0, 0.35, t))
		m = np.maximum(m, smooth(w + 0.012, w - 0.006, np.abs(aa - c + wob)))
	front = smooth(0.965, 0.93, t)                   # the elytral base stays cream
	rear = smooth(0.015, 0.05, t)
	return m * front * rear * smooth(AM - 0.03, AM - 0.1, aa)


def shell_relief(a, t, P, s):
	aa = np.abs(a)
	ely = smooth(AM + 0.02, AM - 0.04, aa)
	r = -0.0055 * np.exp(-(aa / 0.02) ** 2) * smooth(0.02, 0.08, t) * smooth(0.97, 0.9, t)   # suture groove
	r = r + 0.0025 * np.exp(-((aa - 0.045) / 0.025) ** 2)
	r = r + 0.008 * np.exp(-((aa - AM + 0.06) / 0.06) ** 2)          # the margin's lip
	r = r - 0.009 * smooth(AM - 0.02, AM + 0.16, aa)                 # the abdomen sits inside it
	# punctures: rows down both edges of every stripe
	x = P[..., 0]
	pit = 0.0
	for c in STRIPES:
		for off in (-0.045, 0.045):
			ac = c + off
			dz = (aa - ac) * SW * np.maximum(s, 0.05)
			cell = np.round(x / 0.019)
			dx = x - cell * 0.019
			pit = np.maximum(pit, smooth(0.0068, 0.0025, np.sqrt(dx * dx + dz * dz)))
	r = r - 0.0035 * pit * ely * smooth(0.04, 0.1, t) * smooth(0.96, 0.9, t)
	# the abdomen's sternites
	belly = smooth(AM + 0.1, AM + 0.25, aa)
	seg = np.abs(np.sin((t - 0.12) * PI * 6.5))
	r = r - 0.006 * belly * smooth(0.12, 0.0, seg) * smooth(0.1, 0.2, t) * smooth(0.8, 0.7, t)
	r = r + 0.0012 * fbm(P[..., 0] * 60, P[..., 1] * 60, P[..., 2] * 60, 2)
	return r


def build_shell(acc, rows, cols, relief=False):
	j, i = np.mgrid[0:rows + 1, 0:cols + 1]
	t = j / rows
	u = i / cols
	a = u * TAU - PI   # the seam runs underneath: u = 0.5 is the top
	P, s = shell_point(a, t)
	N = orient_out(grid_normals(P[:, :-1]), P[:, :-1], np.array([SX, SY, 0.0]))
	Pw = P[:, :-1]
	if relief:
		Pw = Pw + N * shell_relief(a[:, :-1], t[:, :-1], Pw, s[:, :-1])[..., None]
	UV = rect_uv(SHELL_RECT, u, t)
	acc.grid(Pw, N, UV, data_arr(SHELL, 0.0, 0.0, t.shape))


# --- pronotum and head: small domes, each in its own frame ---------------------------------------

def dome_point(a, t, c, hl, w, hu, hd, pitch, front_e, rear_e, flare=0.0, taper=0.0):
	th = PI * t
	e = rear_e + (front_e - rear_e) * t
	s = np.maximum(np.sin(th), 0.0) ** e
	x = -hl * np.cos(th)
	ca, sa = np.cos(a), np.sin(a)
	H = np.where(ca > 0, hu, hd)
	y = _spow(ca, 0.8) * H * s
	z = _spow(sa, 0.8 - flare) * w * s * (1.0 + flare * 0.3 * (1.0 - t)) * (1.0 - taper * t ** 1.5)
	cp, sp = math.cos(pitch), math.sin(pitch)
	X = c[0] + x * cp - y * sp
	Y = c[1] + x * sp + y * cp
	return np.stack([X, Y, z + c[2]], axis=-1), s


PRO_C, PRO_HL, PRO_W, PRO_HU, PRO_HD, PRO_PITCH = (0.35, 0.49, 0.0), 0.145, 0.30, 0.17, 0.12, -0.30
HEAD_C, HEAD_HL, HEAD_W, HEAD_HU, HEAD_HD, HEAD_PITCH = (0.53, 0.40, 0.0), 0.10, 0.145, 0.09, 0.08, -0.6
NECK = (0.46, 0.44, 0.0)


def pronotum_point(a, t):
	return dome_point(a, t, PRO_C, PRO_HL, PRO_W, PRO_HU, PRO_HD, PRO_PITCH, 0.42, 0.34, flare=0.06, taper=0.32)


def head_point(a, t):
	return dome_point(a, t, HEAD_C, HEAD_HL, HEAD_W, HEAD_HU, HEAD_HD, HEAD_PITCH, 0.5, 0.42)


# black marks on the pronotum, in (a, t): two long central dashes forming a V, ringed by spots
PRO_SPOTS = [(0.10, 0.52, 0.055, 0.26), (-0.10, 0.52, 0.055, 0.26), (0.0, 0.84, 0.05, 0.07)]
for _sd in (-1, 1):
	PRO_SPOTS += [(_sd * 0.48, 0.38, 0.09, 0.09), (_sd * 0.52, 0.70, 0.08, 0.08), (_sd * 0.86, 0.55, 0.085, 0.10),
		(_sd * 1.18, 0.40, 0.08, 0.08), (_sd * 1.22, 0.72, 0.07, 0.07), (_sd * 0.80, 0.18, 0.07, 0.06)]


# black spots on the pronotum: (a, t, radius in m); the middle ones make a V
PRO_DOTS = [(0.0, 0.86, 0.016)]
for _sd in (-1, 1):
	PRO_DOTS += [(_sd * 0.07, 0.62, 0.018), (_sd * 0.10, 0.48, 0.019), (_sd * 0.14, 0.34, 0.018),
		(_sd * 0.45, 0.62, 0.024), (_sd * 0.55, 0.32, 0.022), (_sd * 0.85, 0.52, 0.026), (_sd * 1.15, 0.30, 0.021),
		(_sd * 1.2, 0.70, 0.02), (_sd * 0.75, 0.82, 0.017)]


def _dots(fn, P, dots, wob):
	m = 0.0
	for (sa, st, rad) in dots:
		c, _ = fn(np.array(sa), np.array(st))
		d = np.linalg.norm(P - c, axis=-1) / rad + wob
		m = np.maximum(m, smooth(1.0, 0.75, d))
	return m


def pronotum_mask(a, t):
	P, _ = pronotum_point(a, t)
	wob = 0.15 * vnoise(P[..., 0] * 90, P[..., 1] * 90, P[..., 2] * 90)
	return _dots(pronotum_point, P, PRO_DOTS, wob) * smooth(1.75, 1.6, np.abs(a))


HEAD_DOTS = [(0.0, 0.32, 0.026), (-0.32, 0.42, 0.014), (0.32, 0.42, 0.014), (0.0, 0.52, 0.012)]


def head_mask(a, t):
	# a small black mark on the vertex, a dark rim at the clypeus
	P, _ = head_point(a, t)
	wob = 0.12 * vnoise(P[..., 0] * 90, P[..., 1] * 90, P[..., 2] * 90)
	clyp = smooth(0.9, 0.97, t) * smooth(1.2, 0.8, np.abs(a))
	return np.maximum(_dots(head_point, P, HEAD_DOTS, wob), clyp * 0.7)


def build_dome(acc, kind, group, rect, fn, centre, rows, cols, relief=None):
	j, i = np.mgrid[0:rows + 1, 0:cols + 1]
	t = j / rows
	u = i / cols
	a = u * TAU - PI
	P, s = fn(a, t)
	N = orient_out(grid_normals(P[:, :-1]), P[:, :-1], np.array(centre))
	Pw = P[:, :-1]
	if relief is not None:
		Pw = Pw + N * relief(a[:, :-1], t[:, :-1], Pw)[..., None]
	acc.grid(Pw, N, rect_uv(rect, u, t), data_arr(kind, 0.0, group, t.shape))


def pronotum_relief(a, t, P):
	aa = np.abs(a)
	r = 0.006 * np.exp(-((aa - 1.62) / 0.07) ** 2)                  # the lateral bead
	cell = fbm(P[..., 0] * 70, P[..., 1] * 70, P[..., 2] * 70, 1)
	pits = smooth(0.55, 0.8, vnoise(P[..., 0] * 140, P[..., 1] * 140, P[..., 2] * 140))
	r = r - 0.0025 * pits * smooth(1.5, 1.2, aa) + 0.001 * cell
	r = r - 0.004 * smooth(0.05, 0.0, t) - 0.004 * smooth(0.95, 1.0, t)
	return r


def head_relief(a, t, P):
	pits = smooth(0.55, 0.8, vnoise(P[..., 0] * 160, P[..., 1] * 160, P[..., 2] * 160))
	r = -0.002 * pits - 0.003 * np.exp(-((t - 0.82) / 0.025) ** 2) * smooth(1.3, 0.9, np.abs(a))
	return r


# --- eyes, antennae, mandibles ---------------------------------------------------------------

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
	"""A tube along a Catmull-Rom path, radius lerped through radii (one per path point)."""
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


def antenna_path(sd):
	return [(0.60, 0.445, sd * 0.085), (0.655, 0.48, sd * 0.13), (0.715, 0.52, sd * 0.19), (0.775, 0.535, sd * 0.25),
		(0.835, 0.535, sd * 0.30)]


def antenna_radius(t):
	seg = np.abs(np.sin(t * PI * 11.0))
	club = 1.0 + 1.1 * smooth(0.55, 0.9, t)
	return (0.8 + 0.25 * seg ** 0.5) * club * smooth(1.02, 0.94, t) ** 0.4 + 0.02


def build_antennae(acc, sides, samples):
	for g, sd in ((1, -1.0), (2, 1.0)):
		sweep(acc, antenna_path(sd), [0.011, 0.010, 0.010, 0.012, 0.010], sides, samples, ANT_RECT, HEAD, g,
			lambda tt: tt, radius_fn=antenna_radius)


def mandible_path(sd):
	return [(0.585, 0.33, sd * 0.06), (0.615, 0.315, sd * 0.064), (0.64, 0.307, sd * 0.046), (0.655, 0.304, sd * 0.016)]


def build_mandibles(acc, sides, samples):
	for g, sd in ((3, -1.0), (4, 1.0)):
		sweep(acc, mandible_path(sd), [0.022, 0.018, 0.011, 0.003], sides, samples, MAND_RECT, HEAD, g, lambda tt: 0.0 * tt)


EYES = [((0.553, 0.425, sd * 0.122), (0.032, 0.042, 0.022)) for sd in (-1.0, 1.0)]


def build_eyes(acc, rows, cols):
	for c, r in EYES:
		ellipsoid(acc, c, r, HEAD, 0, EYE_RECT, rows, cols, rot=-0.4)


# --- legs ---------------------------------------------------------------------------------------
# leg k: side k % 2 (0 left, z < 0), pair k / 2 (0 front, 1 middle, 2 hind)
HIP_X = [0.30, 0.10, -0.10]
HIP_Y = 0.23
HIP_Z = 0.13
LEG_YAW = [0.78, 0.05, -0.78]    # forward (+) or back (-) of straight out
LEG_SCALE = [0.9, 1.0, 1.1]
# along the leg (distance out, height): hip, trochanter, femur, knee, tibia, ankle, tarsus, claw
LEG_PROFILE = [(0.0, 0.0), (0.05, -0.02), (0.15, 0.05), (0.27, 0.11), (0.315, 0.12), (0.35, 0.09),
	(0.41, -0.03), (0.46, -0.15), (0.49, -0.2), (0.55, -0.212), (0.60, -0.218)]
LEG_RADII = [0.062, 0.058, 0.072, 0.054, 0.046, 0.042, 0.038, 0.041, 0.032, 0.034, 0.011]
LEG_KNEE_T, LEG_ANKLE_T = 0.37, 0.76


def leg_frame(k):
	side = -1.0 if k % 2 == 0 else 1.0
	pair = k // 2
	yaw = LEG_YAW[pair]
	d = np.array([math.sin(yaw), 0.0, side * math.cos(yaw)])
	hip = np.array([HIP_X[pair], HIP_Y, side * HIP_Z])
	return hip, d, LEG_SCALE[pair], side, pair


def leg_path(k):
	hip, d, sc, side, pair = leg_frame(k)
	pts = []
	for (o, h) in LEG_PROFILE:
		p = hip + d * o * sc + np.array([0.0, h * (0.93 + 0.07 * sc), 0.0])
		pts.append(tuple(p))
	return pts


def leg_point_at(k, t):
	"""A point on the leg's axis at fraction t, for tufts."""
	path = leg_path(k)
	f = t * (len(path) - 1)
	i = min(int(f), len(path) - 2)
	return np.array(path[i]) + (np.array(path[i + 1]) - np.array(path[i])) * (f - i)


def leg_radius(t):
	# tarsal segments bead up into pads
	tars = smooth(LEG_ANKLE_T, LEG_ANKLE_T + 0.03, t)
	beads = 1.0 + 0.22 * tars * np.abs(np.sin((t - LEG_ANKLE_T) * PI * 13.0)) ** 0.6
	knee = 1.0 + 0.10 * np.exp(-((t - LEG_KNEE_T) / 0.03) ** 2)
	return beads * knee


def leg_relief(t, a, P):
	seta = smooth(0.62, 0.85, vnoise(P[..., 0] * 260, P[..., 1] * 260, P[..., 2] * 260))
	r = 0.0016 * seta + 0.0008 * vnoise(P[..., 0] * 90, P[..., 1] * 90, P[..., 2] * 90)
	r = r - 0.0035 * np.exp(-((t - LEG_KNEE_T - 0.035) / 0.008) ** 2)
	for tj in (0.07, LEG_ANKLE_T):
		r = r - 0.003 * np.exp(-((t - tj) / 0.008) ** 2)
	return r


def build_leg(acc, k, sides, samples, relief=False):
	sweep(acc, leg_path(k), LEG_RADII, sides, samples, LEG_RECT, LEG, k, lambda tt: tt,
		relief=leg_relief if relief else None, radius_fn=leg_radius)


# --- tufts of Beauveria: three cotton-ball variants, instanced ---------------------------------

def tuft_shape(n, var, detail):
	"""Radius multiplier for unit direction(s) n on tuft variant var. detail 0 shared lumps
	(the silhouette, in every mesh), 1 adds the cotton and fibre (sculpt only)."""
	x, y, z = n[..., 0], n[..., 1], n[..., 2]
	o = var * 31.7
	r = 1.0 + 0.2 * fbm(x * 1.4 + o, y * 1.4, z * 1.4 - o, 2) + 0.17 * smooth(-0.3, 0.7, vnoise(x * 3.0 - o, y * 3.0 + o, z * 3.0))
	r = r * (1.0 - 0.32 * smooth(-0.15, -0.85, y))   # flattened where it sits on the body
	if detail:
		puffs = smooth(-0.1, 0.8, vnoise(x * 7.5 + o, y * 7.5, z * 7.5 + o))
		r = r + 0.05 * puffs
		fib = vnoise(x * 48.0 + o, y * 48.0, z * 48.0) * 0.6 + vnoise(x * 110.0, y * 110.0 - o, z * 110.0) * 0.4
		r = r + 0.012 * fib
	return r


def tuft_grid(rows, cols, var, detail):
	j, i = np.mgrid[0:rows + 1, 0:cols + 1]
	v = j / rows
	u = i / cols
	th = PI * v
	ph = u * TAU
	n = np.stack([np.sin(th) * np.cos(ph), -np.cos(th), np.sin(th) * np.sin(ph)], axis=-1)
	return n * tuft_shape(n, var, detail)[..., None], u, v


def _frame(up):
	up = np.asarray(up, np.float64)
	up = up / np.linalg.norm(up)
	seed = np.array([1.0, 0.0, 0.0]) if abs(up[0]) < 0.9 else np.array([0.0, 0.0, 1.0])
	e1 = np.cross(up, seed)
	e1 /= np.linalg.norm(e1)
	e2 = np.cross(e1, up)
	return e1, up, e2


def tuft(acc, centre, up, radius, flat, var, kind, weight, group, rows, cols, detail=0, spin=0.0):
	Q, u, v = tuft_grid(rows, cols, var, detail)
	e1, e2, e3 = _frame(up)
	c, s = math.cos(spin), math.sin(spin)
	e1, e3 = e1 * c + e3 * s, e3 * c - e1 * s
	M = np.stack([e1 * radius, e2 * radius * flat, e3 * radius])   # local x, y (up), z
	P = Q @ M + np.asarray(centre)
	N = orient_out(grid_normals(P[:, :-1]), P[:, :-1], np.asarray(centre))
	acc.grid(P[:, :-1], N, rect_uv(TUFT_RECTS[var], u, v), data_arr(TUFT + kind, weight, group + min(radius, 0.45), v.shape))


def tuft_list():
	"""(centre, up, radius, flatness, variant, rides kind, weight, group)."""
	out = []
	rng = np.random.default_rng(7)

	def on_shell(a, t, r, flat=0.8, sink=0.45):
		P, s = shell_point(np.array(a), np.array(t))
		eps = 0.01
		Pa, _ = shell_point(np.array(a + eps), np.array(t))
		Pt, _ = shell_point(np.array(a), np.array(t + eps))
		n = np.cross(Pt - P, Pa - P)
		n /= np.linalg.norm(n)
		if np.dot(n, P - np.array([SX, SY, 0.0])) < 0:
			n = -n
		out.append((P - n * r * sink, n, r, flat, int(rng.integers(3)), SHELL, 0.0, 0.0))

	for sd in (-1.0, 1.0):
		for t, r in ((0.13, 0.13), (0.29, 0.17), (0.47, 0.19), (0.65, 0.17), (0.82, 0.13)):
			on_shell(sd * (AM - 0.05), t, r + rng.uniform(-0.015, 0.015), 0.72, 0.38)
		on_shell(sd * 0.75, 0.93, 0.09, 0.6, 0.5)      # where the elytra meet the pronotum
		on_shell(sd * 1.42, 0.9, 0.11, 0.7, 0.42)
		on_shell(sd * 0.9, 0.18, 0.11, 0.6, 0.5)       # high on the rear slope
		on_shell(sd * 0.04, 0.4 if sd < 0 else 0.6, 0.085, 0.55, 0.55)   # along the suture
		on_shell(sd * 0.55, 0.33 if sd < 0 else 0.4, 0.07, 0.7, 0.5)    # low patches on the back
		on_shell(sd * 1.15, 0.62 if sd < 0 else 0.7, 0.08, 0.7, 0.5)
	on_shell(0.0, 0.04, 0.16, 0.8, 0.45)                 # the elytral apex
	for sd in (-1.0, 1.0):
		P, _ = pronotum_point(np.array(sd * 1.52), np.array(0.45))
		n = P - np.array(PRO_C)
		n[0] *= 0.3
		n /= np.linalg.norm(n)
		out.append((P - n * 0.035, n, 0.095, 0.7, int(rng.integers(3)), PRONOTUM, 0.0, 0.0))
		P, _ = head_point(np.array(sd * 1.2), np.array(0.12))
		n = P - np.array(HEAD_C)
		n /= np.linalg.norm(n)
		out.append((P - n * 0.02, n + np.array([0.0, 0.6, 0.0]), 0.06, 0.75, int(rng.integers(3)), HEAD, 0.0, 0.0))
	for k in range(6):
		hip, d, sc, side, pair = leg_frame(k)
		knee = leg_point_at(k, LEG_KNEE_T)
		out.append((knee + np.array([0.0, 0.02, 0.0]), d * 0.4 + np.array([0.0, 1.0, 0.0]), 0.07 + 0.008 * pair, 0.8,
			int(rng.integers(3)), LEG, LEG_KNEE_T, float(k)))
		out.append((hip + d * 0.05 + np.array([0.0, 0.01, 0.0]), d + np.array([0.0, 0.2, 0.0]), 0.08, 0.75,
			int(rng.integers(3)), LEG, 0.04, float(k)))
		ank = leg_point_at(k, LEG_ANKLE_T - 0.02)
		if pair != 1:
			out.append((ank, d + np.array([0.0, 0.5, 0.0]), 0.045, 0.8, int(rng.integers(3)), LEG, LEG_ANKLE_T - 0.02, float(k)))
	return out


# --- whole models ------------------------------------------------------------------------------

def build_lod(lod, tufts=True):
	acc = Acc()
	sr, sc = [(28, 40), (15, 24), (8, 14)][lod]
	build_shell(acc, sr, sc)
	pr, pc = [(14, 26), (8, 16), (5, 10)][lod]
	build_dome(acc, PRONOTUM, 0.0, PRONOTUM_RECT, pronotum_point, PRO_C, pr, pc)
	hr, hc = [(10, 18), (6, 12), (4, 8)][lod]
	build_dome(acc, HEAD, 0.0, HEAD_RECT, head_point, HEAD_C, hr, hc)
	er, ec = [(5, 8), (3, 6), (2, 4)][lod]
	build_eyes(acc, er, ec)
	if lod < 2:
		build_antennae(acc, [5, 4][lod], [22, 10][lod])
		build_mandibles(acc, [5, 4][lod], [6, 3][lod])
	else:
		build_antennae(acc, 3, 4)
	ls, lsamp = [(7, 20), (5, 10), (4, 5)][lod]
	for k in range(6):
		build_leg(acc, k, ls, lsamp)
	if tufts:
		tr, tc = [(8, 12), (4, 6), (2, 4)][lod]
		for (c, up, r, flat, var, kind, w, g) in tuft_list():
			if (lod == 1 and r < 0.05) or (lod == 2 and r < 0.075):
				continue
			tuft(acc, c, up, r, flat, var, kind, w, g, tr, tc, spin=r * 40.0)
	return acc


# --- painting ------------------------------------------------------------------------------------

CREAM = np.array([0.93, 0.83, 0.52])
CREAM_WARM = np.array([0.95, 0.74, 0.32])
STRIPE = np.array([0.035, 0.03, 0.025])
ORANGE = np.array([0.92, 0.50, 0.12])
ORANGE_PALE = np.array([0.96, 0.70, 0.30])
BELLY = np.array([0.80, 0.42, 0.12])
BLACK = np.array([0.03, 0.025, 0.02])
LEG_ORANGE = np.array([0.90, 0.56, 0.15])
COTTON = np.array([0.97, 0.965, 0.93])
COTTON_SHADE = np.array([0.84, 0.83, 0.77])


def texel_grid(rect, size):
	x0, x1 = int(rect[0] * size), int(math.ceil(rect[2] * size))
	y0, y1 = int(rect[1] * size), int(math.ceil(rect[3] * size))
	ys, xs = np.mgrid[y0:y1, x0:x1]
	u = np.clip(((xs + 0.5) / size - rect[0]) / (rect[2] - rect[0]), 0.0, 1.0)
	v = np.clip(((ys + 0.5) / size - rect[1]) / (rect[3] - rect[1]), 0.0, 1.0)
	return (slice(y0, y1), slice(x0, x1)), u, v


def paint(size):
	albedo = np.zeros((size, size, 3), np.float64)
	albedo[...] = CREAM
	orm = np.ones((size, size, 4), np.float64)
	orm[..., 1] = 0.6
	orm[..., 2] = 0.0

	# shell
	sl, u, t = texel_grid(SHELL_RECT, size)
	a = u * TAU - PI
	P, s = shell_point(a, t)
	aa = np.abs(a)
	n1 = fbm(P[..., 0] * 18, P[..., 1] * 18, P[..., 2] * 18, 3)
	ground = mix(CREAM, CREAM_WARM, smooth(0.6, 1.0, aa / AM) * 0.6 + 0.15 * n1)
	ground = mix(ground, CREAM_WARM, smooth(0.25, 0.0, t) * 0.4)
	col = mix(ground, STRIPE, stripe_mask(a, t))
	belly = smooth(AM - 0.02, AM + 0.08, aa)
	bcol = mix(BELLY, BELLY * 0.7, smooth(0.0, 0.15, np.abs(np.sin((t - 0.12) * PI * 6.5))) * 0)
	seg = np.abs(np.sin((t - 0.12) * PI * 6.5))
	bspots = smooth(0.6, 0.85, vnoise(P[..., 0] * 30, P[..., 2] * 30, 3.0)) * smooth(0.3, 0.05, seg)
	bcol = mix(bcol, BLACK, bspots * 0.9)
	bcol = mix(bcol, bcol * 0.55, smooth(0.12, 0.0, seg) * smooth(0.1, 0.2, t) * smooth(0.8, 0.7, t))
	col = mix(col, bcol, belly)
	albedo[sl] = col
	stripe = stripe_mask(a, t)
	orm[sl + (1,)] = np.clip(0.30 - 0.06 * stripe + 0.05 * n1 + 0.25 * belly, 0.15, 0.9)
	# where the white muscardine dust settles: seams, the margin, the sternites, a mottle on top
	seam = np.maximum(np.exp(-(aa / 0.06) ** 2), np.exp(-((aa - AM) / 0.12) ** 2))
	mott = smooth(0.15, 0.6, fbm(P[..., 0] * 9, P[..., 1] * 9, P[..., 2] * 9, 3))
	orm[sl + (2,)] = np.clip(seam * 0.9 + mott * 0.55 + belly * 0.35 + smooth(0.12, 0.0, t) * 0.6, 0.0, 1.0)

	# pronotum
	sl, u, t = texel_grid(PRONOTUM_RECT, size)
	a = u * TAU - PI
	P, s = pronotum_point(a, t)
	n1 = fbm(P[..., 0] * 22, P[..., 1] * 22, P[..., 2] * 22, 3)
	col = mix(ORANGE, ORANGE_PALE, smooth(1.0, 1.6, np.abs(a)) * 0.7 + 0.12 * n1)
	col = mix(col, BLACK, pronotum_mask(a, t))
	col = mix(col, BELLY * 0.8, smooth(1.75, 2.0, np.abs(a)))
	albedo[sl] = col
	orm[sl + (1,)] = np.clip(0.34 + 0.05 * n1, 0.2, 0.8)
	orm[sl + (2,)] = np.clip(np.exp(-((np.abs(a) - 1.6) / 0.25) ** 2) + smooth(0.15, 0.0, t) * 0.8
		+ smooth(0.2, 0.6, fbm(P[..., 0] * 11, P[..., 1] * 11, P[..., 2] * 11, 2)) * 0.5, 0.0, 1.0)

	# head
	sl, u, t = texel_grid(HEAD_RECT, size)
	a = u * TAU - PI
	P, s = head_point(a, t)
	col = mix(ORANGE, BLACK, head_mask(a, t))
	col = mix(col, BELLY * 0.7, smooth(1.6, 2.2, np.abs(a)))
	albedo[sl] = col
	orm[sl + (1,)] = 0.36
	orm[sl + (2,)] = np.clip(smooth(0.2, 0.0, t) + smooth(1.4, 2.0, np.abs(a)) * 0.6, 0.0, 1.0)

	# antennae: dark, the club darker; mandibles black-brown with a reddish base; eyes black glass
	sl, u, t = texel_grid(ANT_RECT, size)
	albedo[sl] = mix(np.array([0.30, 0.16, 0.06]), BLACK, smooth(0.3, 0.7, t))
	orm[sl + (1,)] = 0.45
	orm[sl + (2,)] = 0.2
	sl, u, t = texel_grid(MAND_RECT, size)
	albedo[sl] = mix(np.array([0.42, 0.14, 0.04]), BLACK, smooth(0.15, 0.6, t))
	orm[sl + (1,)] = 0.3
	orm[sl + (2,)] = 0.0
	sl, u, t = texel_grid(EYE_RECT, size)
	albedo[sl] = np.array([0.02, 0.018, 0.016])
	orm[sl + (1,)] = 0.12
	orm[sl + (2,)] = 0.0

	# legs: orange femur, black knee, orange tibia darkening down, black tarsi and claws
	sl, u, t = texel_grid(LEG_RECT, size)
	ang = u * TAU
	n1 = vnoise(np.cos(ang) * 4, np.sin(ang) * 4, t * 30)
	col = mix(LEG_ORANGE, ORANGE_PALE, 0.25 + 0.15 * n1)
	col = mix(col, BLACK, smooth(LEG_KNEE_T - 0.06, LEG_KNEE_T - 0.01, t) * smooth(LEG_KNEE_T + 0.07, LEG_KNEE_T + 0.03, t))
	col = mix(col, col * 0.55, smooth(0.5, LEG_ANKLE_T, t))
	col = mix(col, BLACK, smooth(LEG_ANKLE_T - 0.03, LEG_ANKLE_T, t))
	col = mix(col, BLACK, smooth(0.06, 0.0, t) * 0.6)
	albedo[sl] = col
	orm[sl + (1,)] = 0.4 + 0.15 * smooth(LEG_ANKLE_T - 0.03, LEG_ANKLE_T, t)
	orm[sl + (2,)] = np.clip(np.exp(-((t - LEG_KNEE_T) / 0.05) ** 2) + np.exp(-((t - LEG_ANKLE_T) / 0.04) ** 2)
		+ smooth(0.1, 0.0, t), 0.0, 1.0)

	# tufts: off-white cotton, creamier in the folds, a faint yellow cast at the base
	for var, rect in enumerate(TUFT_RECTS):
		sl, u, v = texel_grid(rect, size)
		th = PI * v
		ph = u * TAU
		n = np.stack([np.sin(th) * np.cos(ph), -np.cos(th), np.sin(th) * np.sin(ph)], axis=-1)
		o = var * 31.7
		puffs = smooth(-0.1, 0.8, vnoise(n[..., 0] * 7.5 + o, n[..., 1] * 7.5, n[..., 2] * 7.5 + o))
		f = vnoise(n[..., 0] * 48.0 + o, n[..., 1] * 48.0, n[..., 2] * 48.0)
		col = mix(COTTON_SHADE, COTTON, 0.65 + 0.25 * puffs + 0.1 * f)
		col = mix(col, np.array([0.88, 0.84, 0.68]), smooth(-0.3, -0.9, n[..., 1]) * 0.6)
		albedo[sl] = col
		orm[sl + (1,)] = 0.92
		orm[sl + (2,)] = 0.0
	return albedo, orm


# --- the bake ----------------------------------------------------------------------------------

def region_masks(size):
	yy, xx = np.mgrid[0:size, 0:size]
	u = (xx + 0.5) / size
	v = (yy + 0.5) / size
	pad = 4.0 / size

	def rect(r):
		return (u >= r[0] - pad) & (u <= r[2] + pad) & (v >= r[1] - pad) & (v <= r[3] + pad)

	m = {"shell": rect(SHELL_RECT), "pronotum": rect(PRONOTUM_RECT), "head": rect(HEAD_RECT), "leg": rect(LEG_RECT),
		"ant": rect(ANT_RECT), "mand": rect(MAND_RECT), "eye": rect(EYE_RECT)}
	for k, r in enumerate(TUFT_RECTS):
		m["tuft%d" % k] = rect(r)
	return u, v, m


def main():
	os.makedirs(OUT, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	setup_cycles(TAG, bool(OPT.get("cpu")), ao_distance=0.12)
	log(TAG, "building sculpt")
	hi, lo = {}, {}
	acc = Acc(); build_shell(acc, 560, 1100, relief=True); hi["shell"] = acc.obj("hi_shell")
	acc = Acc(); build_dome(acc, PRONOTUM, 0.0, PRONOTUM_RECT, pronotum_point, PRO_C, 220, 420, pronotum_relief); hi["pronotum"] = acc.obj("hi_pronotum")
	acc = Acc(); build_dome(acc, HEAD, 0.0, HEAD_RECT, head_point, HEAD_C, 140, 260, head_relief); hi["head"] = acc.obj("hi_head")
	acc = Acc(); build_leg(acc, 2, 72, 420, relief=True); hi["leg"] = acc.obj("hi_leg")
	others = []
	for k in (0, 1, 3, 4, 5):   # the other legs only shade the body
		acc = Acc(); build_leg(acc, k, 16, 60); others.append(acc.obj("ao_leg%d" % k))
	for k in range(3):
		acc = Acc(); tuft(acc, (0.0, 3.0 + k, 0.0), (0.0, 1.0, 0.0), 0.12, 0.8, k, SHELL, 0.0, 0.0, 180, 360, detail=1)
		hi["tuft%d" % k] = acc.obj("hi_tuft%d" % k)
	log(TAG, "sculpt: %d faces" % sum(len(o.data.polygons) for o in hi.values()))
	acc = Acc(); build_shell(acc, 160, 320); lo["shell"] = acc.obj("lo_shell")
	acc = Acc(); build_dome(acc, PRONOTUM, 0.0, PRONOTUM_RECT, pronotum_point, PRO_C, 60, 120); lo["pronotum"] = acc.obj("lo_pronotum")
	acc = Acc(); build_dome(acc, HEAD, 0.0, HEAD_RECT, head_point, HEAD_C, 40, 80); lo["head"] = acc.obj("lo_head")
	acc = Acc(); build_leg(acc, 2, 24, 140); lo["leg"] = acc.obj("lo_leg")
	for k in range(3):
		acc = Acc(); tuft(acc, (0.0, 3.0 + k, 0.0), (0.0, 1.0, 0.0), 0.12, 0.8, k, SHELL, 0.0, 0.0, 40, 72)
		lo["tuft%d" % k] = acc.obj("lo_tuft%d" % k)
	for ob in lo.values():
		hide_from_rays(ob)
	body_hi = [hi["shell"], hi["pronotum"], hi["head"], hi["leg"]] + others
	reach = {"shell": (0.02, 0.04), "pronotum": (0.012, 0.03), "head": (0.01, 0.025), "leg": (0.005, 0.009)}
	for k in range(3):
		reach["tuft%d" % k] = (0.03, 0.06)
	u, v, masks = region_masks(SIZE)
	normal = np.zeros((SIZE, SIZE, 4), np.float32)
	normal[...] = (0.5, 0.5, 1.0, 1.0)
	ao = np.ones((SIZE, SIZE), np.float32)
	for part, low in lo.items():
		ext, dist = reach[part]
		src = [hi[part]]
		px = bake("NORMAL", low, src, ext, dist, 8, SIZE)
		normal[masks[part]] = px[masks[part]]
		occl = body_hi if not part.startswith("tuft") else src
		px = bake("AO", low, occl, ext, dist, 96, SIZE)
		ao[masks[part]] = px[..., 0][masks[part]]
		log(TAG, "baked " + part)
	# fade bake noise at the poles of every lathe and the ends of the leg
	flat = np.array((0.5, 0.5, 1.0, 1.0), np.float32)
	keep = np.ones((SIZE, SIZE), np.float32)
	poles = [("shell", SHELL_RECT, 0.025, 0.975), ("pronotum", PRONOTUM_RECT, 0.04, 0.96), ("head", HEAD_RECT, 0.05, 0.95),
		("leg", LEG_RECT, 0.02, 0.985)] + [("tuft%d" % k, TUFT_RECTS[k], 0.05, 0.95) for k in range(3)]
	for part, rect, lo_end, hi_end in poles:
		f = (v - rect[1]) / (rect[3] - rect[1])
		m = masks[part]
		keep[m] = np.clip((f[m] - lo_end * 0.4) / (lo_end * 0.6), 0.0, 1.0) * np.clip((hi_end - f[m]) / 0.03 + 0.0, 0.0, 1.0) ** 0.5
	normal = flat + (normal - flat) * keep[..., None]
	ao = 1.0 + (ao - 1.0) * keep
	log(TAG, "painting")
	albedo, orm = paint(SIZE)
	orm[..., 0] = ao
	for part in ("ant", "mand", "eye"):
		orm[..., 0][masks[part]] = 0.85
	alb = np.ones((SIZE, SIZE, 4), np.float32)
	alb[..., :3] = albedo
	save_png(os.path.join(OUT, "beetle_albedo.png"), alb, False)
	save_png(os.path.join(OUT, "beetle_normal.png"), normal, True)
	save_png(os.path.join(OUT, "beetle_orm.png"), orm.astype(np.float32), True)
	for ob in list(hi.values()) + list(lo.values()) + others:
		bpy.data.objects.remove(ob)
	stats = []
	for lod, name in enumerate(("close", "battle", "distant")):
		ob = build_lod(lod).obj("Beetle_" + name)
		tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
		clean = sum(len(p.vertices) - 2 for p in build_lod(lod, tufts=False).obj("tmp").data.polygons)
		from unitlib import export_glb
		export_glb([ob], os.path.join(OUT, "beetle_%s.glb" % name))
		stats.append("%s %d (healthy %d)" % (name, tris, clean))
	hips = [tuple(round(float(c), 4) for c in leg_frame(k)[0]) for k in range(6)]
	log(TAG, "rig: HIPS %s NECK %s" % (hips, NECK))
	log(TAG, "rig: mandible bases %s" % [mandible_path(sd)[0] for sd in (-1.0, 1.0)])
	log(TAG, "done: " + ", ".join(stats))


def preview(path):
	"""Shape check without the sculpt or bakes: healthy and infected close meshes, two views."""
	bpy.ops.wm.read_factory_settings(use_empty=True)
	a = build_lod(int(OPT.get("lod", 0)), tufts=False).obj("healthy")
	b = build_lod(int(OPT.get("lod", 0)), tufts=True).obj("infected")
	b.location = (0.0, 1.6, 0.0)
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.display.shading.light = "STUDIO"
	scene.display.shading.color_type = "OBJECT"
	a.color = (0.85, 0.65, 0.30, 1.0)
	b.color = (0.85, 0.80, 0.70, 1.0)
	scene.render.resolution_x, scene.render.resolution_y = 1200, 800
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = 3.4
	from mathutils import Vector
	for name, yaw, pitch in (("side", 0.0, 0.15), ("q", 0.8, 0.45), ("top", 0.3, 1.4)):
		d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))).normalized()
		target = Vector((0.0, 0.8, 0.35))
		cam.location = target + d * 6.0
		cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = path.replace(".png", "_%s.png" % name)
		bpy.ops.render.render(write_still=True)


if OPT.get("preview"):
	preview(os.path.abspath(OPT["preview"]))
else:
	main()
