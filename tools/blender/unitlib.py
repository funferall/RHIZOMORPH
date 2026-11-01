"""Shared helpers for RHIZOMORPH unit art built headless in Blender 4.2.

Game space is Y up, +X forward; g2b() converts to Blender (Z up) and the glTF exporter
converts back. Meshes carry two UV maps: "UVMap" (the unit's texture atlas) and "data"
(u = kind + 0.98 * gait weight, v = gait group), read by the unit's Godot shader.
Atlas images are numpy arrays (SIZE, SIZE, C), row 0 at the bottom, as Blender stores them.
"""
import math
import os
import time

import bpy
import numpy as np
from mathutils import Vector

TAU = math.tau
_T0 = time.time()


def log(tag, msg):
	print("[%s %5.1fs] %s" % (tag, time.time() - _T0, msg), flush=True)


def g2b(p):
	return (p[0], -p[2], p[1])


def smooth(e0, e1, x):
	t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
	return t * t * (3 - 2 * t)


def lerp(a, b, t):
	return a + (b - a) * t


def mix3(a, b, t):
	return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t))


def catmull(p0, p1, p2, p3, t):
	t2, t3 = t * t, t * t * t
	return tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
		+ (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in range(len(p1)))


def resample(points, n):
	"""n + 1 points evenly spaced by arc length along a Catmull-Rom curve, with fraction s."""
	dense = []
	for i in range(len(points) - 1):
		p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, len(points) - 1)]
		for k in range(60):
			dense.append(catmull(p0, p1, p2, p3, k / 60))
	dense.append(tuple(points[-1]))
	cum = [0.0]
	for i in range(1, len(dense)):
		cum.append(cum[-1] + math.dist(dense[i], dense[i - 1]))
	total = cum[-1]
	out, j = [], 0
	for k in range(n + 1):
		target = total * k / n
		while j < len(cum) - 2 and cum[j + 1] < target:
			j += 1
		f = (target - cum[j]) / max(cum[j + 1] - cum[j], 1e-9)
		out.append((tuple(lerp(dense[j][i], dense[j + 1][i], f) for i in range(len(dense[j]))), k / n))
	return out


def rect_uv(r, u, v):
	return (lerp(r[0], r[2], u), lerp(r[1], r[3], v))


def data_uv(kind, weight=0.0, group=0):
	return (kind + 0.98 * min(max(weight, 0.0), 1.0), float(group))


class MeshData:
	def __init__(self):
		self.verts, self.faces, self.uv, self.data = [], [], [], []

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

	def obj(self, name):
		me = bpy.data.meshes.new(name)
		me.from_pydata(self.verts, [], self.faces)
		uv = me.uv_layers.new(name="UVMap")
		data = me.uv_layers.new(name="data")
		uv.data.foreach_set("uv", [c for p in self.uv for c in p])
		data.data.foreach_set("uv", [c for p in self.data for c in p])
		me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
		me.uv_layers.active = uv
		uv.active_render = True
		me.update()
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		return ob


def grid_surface(md, rows, cols, point_fn, uv_fn, data_fn, wrap=True, relief=None):
	"""A (rows+1) x cols(+1) grid. point_fn(i, j) -> (position, outward normal) in game space;
	uv_fn(i, j) and data_fn(i, j) give per-corner UVs. relief(i, j, p, n) pushes along n."""
	ncols = cols if wrap else cols + 1
	grid = []
	for j in range(rows + 1):
		row = []
		for i in range(ncols):
			p, n = point_fn(i, j)
			p, n = Vector(p), Vector(n)
			if n.length > 1e-9:
				n.normalize()
			if relief:
				p = p + n * relief(i, j, p, n)
			row.append((md.vert(p), n))
		grid.append(row)
	for j in range(rows):
		for i in range(cols):
			i1 = (i + 1) % ncols if wrap else i + 1
			idx = [grid[j][i][0], grid[j][i1][0], grid[j + 1][i1][0], grid[j + 1][i][0]]
			hint = grid[j][i][1] + grid[j + 1][i1][1]
			md.face(idx, [uv_fn(i, j), uv_fn(i + 1, j), uv_fn(i + 1, j + 1), uv_fn(i, j + 1)],
				[data_fn(i, j), data_fn(i + 1, j), data_fn(i + 1, j + 1), data_fn(i, j + 1)],
				tuple(hint) if hint.length > 1e-6 else None)


def frames_along(path, radii, samples):
	"""Centre, radius, t and a parallel-transported (axis, u, v) frame along a Catmull-Rom path."""
	n = len(path) - 1
	out = []
	prev_u = None
	pts = []
	for j in range(samples + 1):
		f = j / samples * n
		i = min(int(f), n - 1)
		lt = f - i
		c = catmull(path[max(i - 1, 0)], path[i], path[i + 1], path[min(i + 2, n)], lt)
		pts.append((Vector(c), lerp(radii[i], radii[i + 1], smooth(0.0, 1.0, lt)), j / samples))
	for j, (c, r, t) in enumerate(pts):
		axis = (pts[min(j + 1, samples)][0] - pts[max(j - 1, 0)][0]).normalized()
		if prev_u is None:
			seed = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
			u = (seed - axis * seed.dot(axis)).normalized()
		else:
			u = (prev_u - axis * prev_u.dot(axis)).normalized()
		prev_u = u
		out.append((c, r, t, axis, u, axis.cross(u)))
	return out


def tube(md, path, radii, sides, samples, uv_rect, kind, weight_fn, group, relief=None, transform=None):
	"""Swept tube; weight_fn(t) is the gait weight; relief(t, a, p) pushes along the normal."""
	fr = frames_along(path, radii, samples)
	xf = transform or (lambda v, is_dir: v)

	def point(i, j):
		c, r, t, axis, u, v = fr[j]
		a = TAU * i / sides
		n = u * math.cos(a) + v * math.sin(a)
		p = c + n * r
		if relief:
			p = p + n * relief(t, a, p)
		return xf(p, False), xf(n, True)

	grid_surface(md, samples, sides, point, lambda i, j: rect_uv(uv_rect, i / sides, fr[j][2]),
		lambda i, j: data_uv(kind, weight_fn(fr[j][2]), group))


# --- baking --------------------------------------------------------------------------------

def setup_cycles(tag, use_cpu=False, ao_distance=0.15):
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	if not use_cpu:
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
					log(tag, "baking on %s: %s" % (backend, ", ".join(d.name for d in gpus)))
					break
			except Exception:
				continue
	world = bpy.data.worlds.new("bake_world")
	scene.world = world
	world.light_settings.distance = ao_distance
	scene.render.bake.margin = 6
	scene.render.bake.margin_type = "EXTEND"


def hide_from_rays(ob):
	for attr in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_transmission",
			"visible_volume_scatter", "visible_shadow"):
		setattr(ob, attr, False)


def pixels(img, size):
	buf = np.empty(size * size * 4, dtype=np.float32)
	img.pixels.foreach_get(buf)
	return buf.reshape(size, size, 4)


def bake(kind, low, highs, extrusion, distance, samples, size):
	scene = bpy.context.scene
	scene.cycles.samples = samples
	img = bpy.data.images.new("bake_%s_%s" % (kind, low.name), size, size, alpha=True, float_buffer=False)
	img.colorspace_settings.name = "Non-Color"
	mat = bpy.data.materials.new(low.name + "_bake")
	mat.use_nodes = True
	node = mat.node_tree.nodes.new("ShaderNodeTexImage")
	node.image = img
	mat.node_tree.nodes.active = node
	low.data.materials.clear()
	low.data.materials.append(mat)
	bpy.ops.object.select_all(action="DESELECT")
	for h in highs:
		h.select_set(True)
	low.select_set(True)
	bpy.context.view_layer.objects.active = low
	bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=extrusion,
		max_ray_distance=distance, normal_space="TANGENT", margin=6)
	return pixels(img, size)


def save_png(path, rgba, non_color):
	size = rgba.shape[0]
	img = bpy.data.images.new(os.path.basename(path), size, size, alpha=True, float_buffer=False)
	img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
	img.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).astype(np.float32).ravel())
	img.filepath_raw = path
	img.file_format = "PNG"
	img.save()


def export_glb(objects, path):
	bpy.ops.object.select_all(action="DESELECT")
	for ob in objects:
		ob.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_texcoords=True,
		export_normals=True, export_tangents=True, export_materials="NONE", export_vertex_color="NONE",
		export_yup=True, export_apply=False)
	return sum(len(p.vertices) - 2 for ob in objects for p in ob.data.polygons)
