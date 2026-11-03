"""Bake UniMate clips into the Splitgill Glider's bone texture and shader constants.

Run with UniMate's environment, from its repository root (it imports UniMate's motion decoding):

  cd ../_ext/UniMate
  python <RHIZOMORPH>/tools/unimate/glider_motion.py --rhizo=<RHIZOMORPH> \
      --glide=outputs/samples/glider/<clip>.npy --fly=... --run=... [--report]

  --report alone scores every clip in --samples (default outputs/samples/glider) and stops.

Each clip is a UniMate sample on the glider rig (outputs/rig/glider, built by rig_preprocess
from the rig GLB that glider_build.py --rig writes). For each frame this runs forward kinematics
in UniMate's canonical frame (facing +Z, scaled), maps every bone's transform back into game
space (Y up, +X forward, metres), and stores the transform that takes a rest-pose vertex to that
frame: a rotation quaternion and a translation, two RGBA float texels per bone. The game moves
the unit, so the clip's travel and turning are removed: the root keeps only its bob and its
pitch and roll. Loops (glide, fly) are cut where the pose comes back closest to where it began,
and the seam is cross-faded. The bomb run plays once.

Writes:
  art/glider/glider_bones.tres                ImageTexture, RGBAF, width 2 x bones, one row a frame
  shaders/splitgill_glider_motion.gdshaderinc   clip table, skinning chains, bomb rest positions
  art/glider/motion.json                        which samples were used, loop cuts, the release frame
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.getcwd())
from Quaternions import Quaternions  # noqa: E402  (UniMate's Motion package)
from unimate.utils.motion_utils import recover_unimate_anim_from_rot  # noqa: E402

FPS = 30.0
M = np.array([[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]])   # canonical -> game axes


# --- quaternion helpers (w, x, y, z) --------------------------------------------------------

def qmul(a, b):
	aw, ax, ay, az = np.moveaxis(a, -1, 0)
	bw, bx, by, bz = np.moveaxis(b, -1, 0)
	return np.stack([aw * bw - ax * bx - ay * by - az * bz, aw * bx + ax * bw + ay * bz - az * by,
		aw * by - ax * bz + ay * bw + az * bx, aw * bz + ax * by - ay * bx + az * bw], axis=-1)


def qconj(q):
	return q * np.array([1.0, -1.0, -1.0, -1.0])


def qrot(q, v):
	qv = np.concatenate([np.zeros(v.shape[:-1] + (1,)), v], axis=-1)
	return qmul(qmul(q, qv), qconj(q))[..., 1:]


def qfrom_axis(axis, ang):
	axis = np.asarray(axis, np.float64)
	h = np.asarray(ang)[..., None] * 0.5
	return np.concatenate([np.cos(h), np.sin(h) * axis], axis=-1)


def qmat(q):
	w, x, y, z = np.moveaxis(q, -1, 0)
	return np.stack([np.stack([1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)], -1),
		np.stack([2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)], -1),
		np.stack([2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)], -1)], -2)


def mat_to_q(m):
	"""Rotation matrices (..., 3, 3) to quaternions (w, x, y, z), w >= 0."""
	tr = m[..., 0, 0] + m[..., 1, 1] + m[..., 2, 2]
	w = np.sqrt(np.maximum(1.0 + tr, 1e-12)) * 0.5
	x = np.sqrt(np.maximum(1.0 + m[..., 0, 0] - m[..., 1, 1] - m[..., 2, 2], 0.0)) * 0.5 * np.sign(m[..., 2, 1] - m[..., 1, 2] + 1e-12)
	y = np.sqrt(np.maximum(1.0 - m[..., 0, 0] + m[..., 1, 1] - m[..., 2, 2], 0.0)) * 0.5 * np.sign(m[..., 0, 2] - m[..., 2, 0] + 1e-12)
	z = np.sqrt(np.maximum(1.0 - m[..., 0, 0] - m[..., 1, 1] + m[..., 2, 2], 0.0)) * 0.5 * np.sign(m[..., 1, 0] - m[..., 0, 1] + 1e-12)
	q = np.stack([w, x, y, z], -1)
	return q / np.linalg.norm(q, axis=-1, keepdims=True)


# --- decoding -------------------------------------------------------------------------------

def load_cond(path):
	return np.load(path, allow_pickle=True).item()["glider"]


def ease(q, amp):
	"""Scale a rotation's angle by amp (slerp from identity)."""
	q = q * np.sign(q[..., :1] + 1e-12)
	ang = 2.0 * np.arccos(np.clip(q[..., 0], -1.0, 1.0))
	ax = q[..., 1:] / np.maximum(np.linalg.norm(q[..., 1:], axis=-1, keepdims=True), 1e-9)
	return qfrom_axis(ax, ang * amp)


def fk(cond, data, amp=1.0):
	"""Global rotations (T, J, 4 wxyz) and positions (T, J, 3), canonical frame and units.
	amp < 1 calms the motion: every joint below the root turns that share of its generated angle."""
	parents = cond["parents"]
	anim = recover_unimate_anim_from_rot(data, parents, cond["tpos_offsets"].copy())
	lq = np.asarray(anim.rotations.qs)          # (T, J, 4) wxyz local
	if amp != 1.0:
		lq[:, 1:] = ease(lq[:, 1:], amp)
	pos = np.asarray(anim.positions)            # local offsets; root = trajectory
	T, J = lq.shape[:2]
	gq = np.zeros_like(lq)
	gp = np.zeros((T, J, 3))
	for j in range(J):
		p = parents[j]
		if p < 0:
			gq[:, j] = lq[:, j]
			gp[:, j] = pos[:, j]
		else:
			gq[:, j] = qmul(gq[:, p], lq[:, j])
			gp[:, j] = gp[:, p] + qrot(gq[:, p], pos[:, j])
	return gq, gp


def similarity(cond, rig):
	"""Scale s and offset o with game = s * M @ canon + o, fitted on the rest joints."""
	names = list(cond["joint_names"])
	game = np.array([next(b["head"] for b in rig["bones"] if b["name"] == n) for n in names])
	canon = np.asarray(cond["tpos_first_frame"]) @ M.T
	gc, cc = game - game.mean(0), canon - canon.mean(0)
	s = float((gc * cc).sum() / (cc * cc).sum())
	o = game.mean(0) - s * canon.mean(0)
	err = np.abs(s * canon + o - game).max()
	return s, o, game, err


def to_game(cond, rig, data, keep_travel=0.0, bob=1.0, amp=1.0):
	"""Per-frame bone deltas in game space: q (T, J, 4 wxyz), t (T, J, 3) with v' = q v + t."""
	gq, gp = fk(cond, data, amp)
	s, o, rest, _ = similarity(cond, rig)
	Mq = mat_to_q(M)
	q = qmul(qmul(Mq[None, None], gq), qconj(Mq)[None, None])     # M R M^T
	p = s * gp @ M.T + o                                          # joint positions, game
	# remove the travel and the turning: the root stays over its rest spot, facing +X
	root = p[:, 0].copy()
	fwd = qrot(q[:, 0], np.array([1.0, 0.0, 0.0]) * np.ones((len(q), 3)))
	yaw = np.arctan2(-fwd[:, 2], fwd[:, 0])
	yaw = yaw - yaw[0] * 0.0
	unyaw = qfrom_axis([0.0, 1.0, 0.0], -yaw)
	q = qmul(unyaw[:, None], q)
	# UniMate flies the body up off its rest "ground": keep only the bob about the clip's mean
	# height (scaled by `bob`), and a share of the forward travel (`keep_travel`, for the dive)
	travel = root - root[:1]
	shift = np.stack([travel[:, 0] * keep_travel, (root[:, 1] - root[:, 1].mean()) * bob, travel[:, 2] * 0.0], -1)
	p = qrot(unyaw[:, None], p - root[:, None]) + (rest[0] + shift)[:, None]
	t = p - qrot(q, rest[None].repeat(len(q), 0))
	return q, t, p


# --- loops and scores -----------------------------------------------------------------------

def loop_cut(p, min_len=24):
	"""(start, end) whose poses match best: the clip loops over [start, end)."""
	T = len(p)
	flat = (p - p[:, :1]).reshape(T, -1)
	best = (1e9, 0, T - 1)
	for i in range(0, T // 3):
		for j in range(i + min_len, T):
			d = np.linalg.norm(flat[i] - flat[j]) + 0.3 * np.linalg.norm((flat[i + 1] - flat[i]) - (flat[min(j + 1, T - 1)] - flat[j]))
			if d < best[0]:
				best = (d, i, j)
	return best


def make_loop(q, t, i, j, fade=6):
	q, t = q[i:j].copy(), t[i:j].copy()
	n = len(q)
	qs, ts = q[:fade].copy(), t[:fade].copy()
	for k in range(fade):
		f = (k + 1) / (fade + 1)
		a = n - fade + k
		qb = qs[k] * np.sign((q[a] * qs[k]).sum(-1, keepdims=True) + 1e-9)
		qq = q[a] * (1 - f) + qb * f
		q[a] = qq / np.linalg.norm(qq, axis=-1, keepdims=True)
		t[a] = t[a] * (1 - f) + ts[k] * f
	return q, t


def score(cond, p):
	names = list(cond["joint_names"])
	tips = [names.index("BN_Wing_L_03"), names.index("BN_Wing_R_03")]
	tip_y = p[:, tips, 1]
	flap = float(np.ptp(tip_y, axis=0).mean())
	sym = float(np.abs((tip_y[:, 0] - tip_y[:, 0].mean()) - (tip_y[:, 1] - tip_y[:, 1].mean())).mean())
	jerk = float(np.abs(np.diff(p, 3, axis=0)).mean()) * FPS ** 3
	root_dy = float(np.ptp(p[:, 0, 1]))
	head = names.index("Bip01_Head")
	lunge = float(np.ptp(p[:, head, 0]))
	return {"flap": flap, "asym": sym, "jerk": jerk, "bob": root_dy, "lunge": lunge, "frames": len(p)}


# --- output ---------------------------------------------------------------------------------

def tres(path, rows, width):
	"""A Godot ImageTexture resource holding RGBAF texels (rows: (H, W, 4) float32)."""
	h = rows.shape[0]
	raw = rows.astype("<f4").tobytes()
	body = ", ".join(str(b) for b in raw)
	with open(path, "w", newline="\n") as fh:
		fh.write('[gd_resource type="ImageTexture" load_steps=2 format=3]\n\n')
		fh.write('[sub_resource type="Image" id="Image_bones"]\n')
		fh.write('data = {\n"data": PackedByteArray(%s),\n"format": "RGBAFloat",\n"height": %d,\n"mipmaps": false,\n"width": %d\n}\n\n'
			% (body, h, width))
		fh.write('[resource]\nimage = SubResource("Image_bones")\n')


def write_include(path, rig, order, clips, release, swing):
	"""The shader constants: clip rows, chains in texture bone order, bomb rest centres."""
	idx = {n: i for i, n in enumerate(order)}
	names = [b["name"] for b in rig["bones"]]
	remap = lambda bi: idx[names[bi]]
	chains = [rig["body_chain"], rig["tail_chain"], rig["wing_chain"]["L"], rig["wing_chain"]["R"]]
	bone, cen, ln = [], [], []
	for c in chains:
		ln.append(len(c))
		pad = c + [c[-1]] * (8 - len(c))
		bone += [remap(b) for b, _ in pad]
		cen += [float(x) for _, x in pad]
	lines = ["// Written by tools/unimate/glider_motion.py from UniMate clips. Do not edit by hand.",
		"const int BONE_COUNT = %d;" % len(order),
		"const float CLIP_FPS = %.1f;" % FPS,
		"// one flight loop is one stride: at gait g (rad/s) it plays at g / GAIT_REF of its own speed",
		"const float GAIT_REF = %.4f;" % (2.0 * np.pi * FPS / dict(clips)["FLY"])]
	start = 0
	for key, n in clips:
		lines.append("const int %s_START = %d;" % (key, start))
		lines.append("const int %s_LEN = %d;" % (key, n))
		start += n
	lines += ["const float RELEASE = %.4f;   // the bomb run lets go of its bombs here (fraction of the swing)" % release,
		"const float SWING_SECONDS = %.2f;" % swing,
		"const int BOMB_BONE = %d;" % remap(rig["bomb_bone"]),
		"// chains: 0 body (by vertex x), 1 tail streamer, 2 left wing, 3 right wing (by data-UV weight)",
		"const int CHAIN_LEN[4] = {%s};" % ", ".join(map(str, ln)),
		"const int CHAIN_BONE[32] = {%s};" % ", ".join(map(str, bone)),
		"const float CHAIN_C[32] = {%s};" % ", ".join("%.4f" % c for c in cen),
		"const vec3 BOMB_CENTRE[4] = {%s};" % ", ".join("vec3(%.4f, %.4f, %.4f)" % tuple(c) for c in rig["bombs"])]
	with open(path, "w", newline="\n") as fh:
		fh.write("\n".join(lines) + "\n")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--rhizo", required=True)
	ap.add_argument("--samples", default="outputs/samples/glider")
	ap.add_argument("--cond", default="outputs/rig/glider/cond.npy")
	ap.add_argument("--glide")
	ap.add_argument("--fly")
	ap.add_argument("--run")
	ap.add_argument("--swing", type=float, default=1.2)
	ap.add_argument("--fly_min", type=int, default=14, help="shortest flight loop (frames): one wingbeat")
	ap.add_argument("--glide_min", type=int, default=30)
	ap.add_argument("--run_window", default="0,60", help="frames of the bomb-run sample to use")
	ap.add_argument("--run_bob", type=float, default=0.35, help="how much of the dive's height change to keep")
	ap.add_argument("--amp", default="0.55,0.6,0.7", help="motion strength for glide, fly and run (1 = as generated)")
	ap.add_argument("--report", action="store_true")
	a = ap.parse_args()
	cond = load_cond(a.cond)
	rig = json.load(open(os.path.join(a.rhizo, "art", "glider", "rig", "rig.json")))
	s, o, rest, err = similarity(cond, rig)
	print("canonical -> game: scale %.4f, offset %s, rest-joint fit error %.4f m" % (s, np.round(o, 3), err))
	if a.report:
		for f in sorted(os.listdir(a.samples)):
			if not f.endswith(".npy") or "-gt" in f:
				continue
			data = np.load(os.path.join(a.samples, f))
			_, _, p = to_game(cond, rig, data)
			sc = score(cond, p)
			d, i, j = loop_cut(p)
			print("%-70s flap %.3f asym %.3f jerk %6.1f bob %.3f lunge %.3f loop [%d,%d) err %.3f" % (
				f, sc["flap"], sc["asym"], sc["jerk"], sc["bob"], sc["lunge"], i, j, d))
		return
	order = list(cond["joint_names"])
	rows, clips, meta = [], [], {}
	r0, r1 = (int(x) for x in a.run_window.split(","))
	amps = dict(zip(("GLIDE", "FLY", "RUN"), (float(x) for x in a.amp.split(","))))
	for key, path, loop in (("GLIDE", a.glide, True), ("FLY", a.fly, True), ("RUN", a.run, False)):
		data = np.load(path)
		if key == "RUN":
			data = data[r0:r1]
		q, t, p = to_game(cond, rig, data, keep_travel=0.15 if key == "RUN" else 0.0,
			bob=a.run_bob if key == "RUN" else 0.6, amp=amps[key])
		if loop:
			d, i, j = loop_cut(p, a.fly_min if key == "FLY" else a.glide_min)
			q, t = make_loop(q, t, i, j)
			meta[key] = {"sample": os.path.basename(path), "loop": [int(i), int(j)], "seam_error": float(d), "amp": amps[key]}
		else:
			# the release: where the body drops fastest, in the dive
			vy = np.gradient(p[:, 0, 1])
			rel = int(np.argmin(vy))
			meta[key] = {"sample": os.path.basename(path), "window": [r0, r1], "amp": amps[key], "release_frame": rel, "frames": len(q)}
		texel = np.zeros((len(q), len(order) * 2, 4), np.float32)
		texel[:, 0::2, :3] = q[..., 1:]
		texel[:, 0::2, 3] = q[..., 0]
		texel[:, 1::2, :3] = t
		rows.append(texel)
		clips.append((key, len(q)))
	release = meta["RUN"]["release_frame"] / max(meta["RUN"]["frames"] - 1, 1)
	meta["release"] = release
	allrows = np.concatenate(rows, 0)
	out = os.path.join(a.rhizo, "art", "glider")
	tres(os.path.join(out, "glider_bones.tres"), allrows, len(order) * 2)
	write_include(os.path.join(a.rhizo, "shaders", "splitgill_glider_motion.gdshaderinc"), rig, order, clips, release, a.swing)
	json.dump(meta, open(os.path.join(out, "motion.json"), "w"), indent=1)
	print("baked %d rows (%s), release at %.3f" % (len(allrows), ", ".join("%s %d" % c for c in clips), release))


if __name__ == "__main__":
	main()
