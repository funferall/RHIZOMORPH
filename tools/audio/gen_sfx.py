"""Generate RHIZOMORPH sound effects with Stable Audio 3 Small SFX via ComfyUI.

Reads audio/sfx/prompts.json; each sound is one batched job (variants = batch
size), post-processed (trim silence, short fades, normalise, optional seamless
loop) into audio/sfx/candidates/<name>_<n>.wav. Already generated candidates are
skipped unless --force.

  python gen_sfx.py --comfy-out <server output dir> [--only hit_melee,spawn] [--group units] [--force]
"""

import argparse
import time
from pathlib import Path

import common

CKPT = "stable_audio_3_small_sfx.safetensors"
TEXT_ENCODER = "t5gemma_b_b_ul2.safetensors"


def workflow(prompt: str, seconds: float, batch: int, seed: int, prefix: str) -> dict:
    # the distilled checkpoint wants 8 LCM steps at cfg 1 (from ComfyUI's SA3 template)
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CKPT}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": TEXT_ENCODER, "type": "stable_audio", "device": "default"}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["2", 0]}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": "", "clip": ["2", 0]}},
        "5": {"class_type": "EmptyLatentAudio", "inputs": {"seconds": seconds, "batch_size": batch}},
        "6": {"class_type": "KSampler", "inputs": {
            "seed": seed, "steps": 8, "cfg": 1.0, "sampler_name": "lcm", "scheduler": "simple", "denoise": 1.0,
            "model": ["1", 0], "positive": ["3", 0], "negative": ["4", 0], "latent_image": ["5", 0]}},
        "7": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveAudio", "inputs": {"audio": ["7", 0], "filename_prefix": prefix}},
    }


def finish(src: Path, dst: Path, looped: bool) -> float:
    a, sr = common.load(src)
    if looped:
        a = common.trim(a, sr, 45.0)
        a = common.loop(a, sr, min(1.0, len(a) / sr * 0.15))
    else:
        a = common.trim(a, sr, 42.0)
        a = common.fade(a, sr, 0.003, min(0.08, len(a) / sr * 0.2))
    a = common.normalize(a, -1.0)
    common.save(dst, a, sr)
    return len(a) / sr


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="http://127.0.0.1:8199")
    ap.add_argument("--comfy-out", required=True, help="the server's --output-directory")
    ap.add_argument("--only", default="")
    ap.add_argument("--group", default="")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    _, m = common.manifest("sfx")
    out = common.AUDIO / "sfx" / "candidates"
    only = [s for s in args.only.split(",") if s]
    for s in m["sounds"]:
        name = s["name"]
        if only and name not in only or args.group and s["group"] != args.group:
            continue
        # one prompt, or a list of prompt variations (the distilled model barely varies by seed)
        prompts = s.get("prompts") or [s["prompt"]]
        n = int(s.get("variants", 2))
        total = n * len(prompts)
        if not args.force and all((out / f"{name}_{i + 1}.wav").exists() for i in range(total)):
            print("skip", name)
            continue
        if args.force:
            for old in out.glob(f"{name}_[0-9]*.wav"):
                old.unlink()
        t0 = time.time()
        lens = []
        for k, prompt in enumerate(prompts):
            prefix = f"rhizo_sfx_{name}_p{k}"
            files = common.run(args.server, workflow(prompt, float(s["seconds"]), n, args.seed + k * 101, prefix), Path(args.comfy_out), prefix)
            for f in files:
                lens.append(finish(f, out / f"{name}_{len(lens) + 1}.wav", s.get("loop", False)))
        print(f"{name}: {len(lens)} x [{', '.join('%.2fs' % x for x in lens)}]  ({time.time() - t0:.0f}s)", flush=True)


if __name__ == "__main__":
    main()
