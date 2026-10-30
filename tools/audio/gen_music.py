"""Generate RHIZOMORPH music with MusicGen (medium) through ComfyUI.

Reads audio/music/prompts.json; each track is generated in `variants` seeds into
audio/music/candidates/<name>_s<seed>.wav. Loop tracks get trailing quiet trimmed
(MusicGen likes to fade out) and their tail crossfaded into the head; stings get
a fade-out.

  python gen_music.py --comfy-out <server output dir> [--only calm,battle] [--force]
"""

import argparse
import time
from pathlib import Path

import common

SEEDS = [11, 23, 37, 41]


def workflow(prompt: str, seconds: float, seed: int, prefix: str) -> dict:
    return {
        "1": {"class_type": "HuggingFaceMusicGen", "inputs": {
            "model_size": "medium", "duration": seconds, "guidance_scale": 3.5, "do_sample": True,
            "max_new_tokens": 1503, "seed": seed, "prompt": prompt, "temperature": 1.0, "duration_override": 0.0}},
        "2": {"class_type": "SaveAudioStandalone", "inputs": {
            "audio": ["1", 0], "filename_prefix": prefix, "format": "wav", "quality": "320k"}},
    }


def finish(src: Path, dst: Path, looped: bool) -> float:
    a, sr = common.load(src)
    if looped:
        a = common.trim(a, sr, 24.0, head=False)
        a = common.loop(a, sr, 3.0)
    else:
        a = common.fade(a, sr, 0.05, 2.5)
    a = common.normalize(a, -1.5)
    common.save(dst, a, sr)
    return len(a) / sr


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="http://127.0.0.1:8199")
    ap.add_argument("--comfy-out", required=True, help="the server's --output-directory")
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    comfy_out = Path(args.comfy_out)
    (comfy_out / "audio").mkdir(parents=True, exist_ok=True)   # MusicGen-HF's saver doesn't create it
    _, m = common.manifest("music")
    out = common.AUDIO / "music" / "candidates"
    only = [s for s in args.only.split(",") if s]
    for t in m["tracks"]:
        if only and t["name"] not in only:
            continue
        for seed in SEEDS[: int(t.get("variants", 2))]:
            dst = out / f"{t['name']}_s{seed}.wav"
            if dst.exists() and not args.force:
                print("skip", dst.name)
                continue
            t0 = time.time()
            prefix = f"rhizo_{t['name']}_s{seed}"
            src = common.run(args.server, workflow(t["prompt"], float(t["seconds"]), seed, prefix), comfy_out, prefix)[0]
            length = finish(src, dst, t.get("loop", False))
            print(f"{dst.name}  {length:.1f}s  ({time.time() - t0:.0f}s)", flush=True)


if __name__ == "__main__":
    main()
