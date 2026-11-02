"""Atlas lint: is a unit's texture atlas rich enough, and is its detail real detail?

  python tools/art/atlas_lint.py art/beetle/beetle            # reads <prefix>_albedo.png, _normal.png, _orm.png
  python tools/art/atlas_lint.py art/runner/runner --tiles=4  # judge it in a 4x4 grid of cells

Flat or noisy albedos are the commonest way a unit ends up looking cheap. This measures,
over each used cell of the atlas:
  - value structure: luminance spread at a mid scale (forms, bands, spots) vs pixel scale
    (static). Good atlases have mid-scale structure and little per-pixel noise.
  - hue variation: real surfaces shift hue (warmer in the light parts, cooler or more
    saturated in the shadows, different hues in patterns), not just brightness.
  - contrast: the darkest and lightest accents (the 2nd and 98th percentiles).
And for the normal map, whether it carries baked forms (mid-scale slopes) or only per-pixel
noise; and whether an ORM map exists with real occlusion and roughness variation.
Exit code 1 if anything FAILs, so a build can gate on it.
"""
import os
import sys

import numpy as np
from PIL import Image


def load(path):
	return np.asarray(Image.open(path).convert("RGB"), np.float32) / 255.0


def box(img, r):
	"""Box blur of radius r on a 2D array (edge-clamped), via a summed-area table."""
	if r <= 0:
		return img
	p = np.pad(img, r + 1, mode="edge")
	s = p.cumsum(0).cumsum(1)
	k = 2 * r + 1
	out = s[k:, k:] - s[:-k, k:] - s[k:, :-k] + s[:-k, :-k]
	return out[: img.shape[0], : img.shape[1]] / (k * k)


def lum(rgb):
	return rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)


def hue_spread(rgb):
	"""Spread of chroma direction (0 = one hue everywhere), weighted by saturation."""
	mx, mn = rgb.max(-1), rgb.min(-1)
	sat = (mx - mn) / np.maximum(mx, 1e-4)
	r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
	a = np.arctan2(np.sqrt(3.0) * (g - b), 2 * r - g - b)
	w = sat * (mx - mn)
	if w.sum() < 1e-3:
		return 0.0
	c = (np.cos(a) * w).sum() / w.sum()
	s = (np.sin(a) * w).sum() / w.sum()
	return float(1.0 - np.hypot(c, s))   # circular variance of hue


def scales(L, size):
	r_fine, r_mid = max(1, size // 512), max(4, size // 48)
	fine = L - box(L, r_fine)
	mid = box(L, r_fine) - box(L, r_mid)
	return float(fine.std()), float(mid.std())


def main():
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	opt = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
	if not args:
		print(__doc__)
		sys.exit(2)
	prefix = args[0]
	tiles = int(opt.get("tiles", 4))
	fails, warns = [], []
	alb = load(prefix + "_albedo.png")
	size = alb.shape[0]
	L = lum(alb)
	fine, mid = scales(L, size)
	print("ALBEDO %s  %dpx" % (prefix + "_albedo.png", size))
	print("  whole atlas: mid-scale structure %.3f, pixel noise %.3f, hue spread %.2f, accents %.2f..%.2f"
		% (mid, fine, hue_spread(alb), np.percentile(L, 2), np.percentile(L, 98)))
	n = size // tiles
	flat_cells = 0
	used = 0
	for ty in range(tiles):
		for tx in range(tiles):
			cell = alb[ty * n:(ty + 1) * n, tx * n:(tx + 1) * n]
			cl = lum(cell)
			f, m = scales(cl, size)
			if cl.std() < 0.004:
				continue   # padding or one flat filler
			used += 1
			tag = ""
			if m < 0.012:
				flat_cells += 1
				tag = "  <- flat: no mid-scale pattern"
			elif f > m * 1.2:
				tag = "  <- noise dominates: per-pixel static, not forms"
			print("  cell %d,%d: mid %.3f  noise %.3f  hue %.2f%s" % (tx, ty, m, f, hue_spread(cell), tag))
	if mid < 0.02:
		fails.append("albedo has almost no mid-scale structure (%.3f < 0.02): paint patterns, bands, spots, cavities" % mid)
	if fine > mid * 0.9:
		fails.append("albedo detail is mostly per-pixel noise (%.3f vs mid %.3f): use smooth value noise / fbm at the size of real features, not rng.random per texel" % (fine, mid))
	if hue_spread(alb) < 0.02:
		print("NOTE  little hue variation (%.2f): consider shifting hue with value (warmer lights, cooler or more"
			" saturated darks) and giving accents their own hue" % hue_spread(alb))
	if used and flat_cells / used > 0.34:
		warns.append("%d of %d used cells are flat" % (flat_cells, used))

	if os.path.exists(prefix + "_normal.png"):
		nm = load(prefix + "_normal.png") * 2.0 - 1.0
		slope = np.hypot(nm[..., 0], nm[..., 1])
		r_fine, r_mid = max(1, size // 512), max(4, size // 48)
		nx = nm[..., 0]
		nfine = float((nx - box(nx, r_fine)).std())
		nmid = float((box(nx, r_fine) - box(nx, r_mid)).std())
		print("NORMAL  mean slope %.3f, mid-scale %.3f, pixel noise %.3f" % (slope.mean(), nmid, nfine))
		if nfine > nmid * 1.2:
			fails.append("normal map is per-pixel noise (%.3f vs mid %.3f): bake it from a sculpt (unitlib.bake) instead of np.gradient(random)" % (nfine, nmid))
		if slope.mean() < 0.02:
			warns.append("normal map is nearly flat: the sculpt needs relief (pits, ridges, fibres, segment seams)")
	else:
		fails.append("no normal map")

	if os.path.exists(prefix + "_orm.png"):
		orm = load(prefix + "_orm.png")
		ao, rough = orm[..., 0], orm[..., 1]
		print("ORM     occlusion %.2f..%.2f, roughness %.2f..%.2f"
			% (np.percentile(ao, 2), np.percentile(ao, 98), np.percentile(rough, 2), np.percentile(rough, 98)))
		if np.percentile(ao, 2) > 0.8:
			warns.append("baked occlusion barely darkens anything: bake AO with all the sculpt's parts as occluders")
		if np.percentile(rough, 98) - np.percentile(rough, 2) < 0.15:
			warns.append("roughness is nearly uniform: gloss the wet/lacquered parts, roughen the dry, dusty or fibrous ones")
	else:
		warns.append("no ORM map: no baked occlusion and no roughness variation")

	for w in warns:
		print("WARN  " + w)
	for f in fails:
		print("FAIL  " + f)
	print("atlas_lint: %d fail, %d warn" % (len(fails), len(warns)))
	sys.exit(1 if fails else 0)


if __name__ == "__main__":
	main()
