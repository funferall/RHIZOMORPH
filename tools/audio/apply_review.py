"""Apply a review round's decisions (exported from the review artifact's `reviews`
collection as JSON files) to the game's audio folders and the prompt manifests.

  approve     copy the starred takes (all takes if none starred) into audio/<kind>/<name>_N.wav
  more        copy the starred takes now; the item is flagged so new takes get generated
  regenerate  copy nothing; flagged for new takes
  reject      copy nothing; flagged rejected

Copies are recorded in each manifest entry's `in_game` list ("r<round>:<take id>"), so
re-running a round never duplicates a take. The reviewer's comment is appended to `notes`.

  python apply_review.py <dir with reviews/*.json> [--round 1]
"""

import argparse
import json
import shutil
from pathlib import Path

import common

STATUS = {"approve": "keep", "more": "more", "regenerate": "redo", "reject": "rejected"}


def next_index(folder: Path, name: str) -> int:
    used = [int(p.stem.rsplit("_", 1)[1]) for p in folder.glob(f"{name}_[0-9]*.wav") if p.stem.rsplit("_", 1)[1].isdigit()]
    return max(used, default=0) + 1


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--round", type=int, default=1)
    args = ap.parse_args()
    files = sorted(Path(args.dir).rglob("*.json"))
    manifests = {k: common.manifest(k) for k in ("music", "sfx")}
    entries = {}
    for kind, (_, m) in manifests.items():
        for it in m["tracks" if kind == "music" else "sounds"]:
            entries[f"{kind}-{it['name']}"] = (kind, it)
    for f in files:
        key = f.stem
        if key not in entries:
            print("unknown item", key)
            continue
        kind, it = entries[key]
        d = json.loads(f.read_text(encoding="utf-8"))
        decision = d.get("decision", "")
        if not decision:
            continue
        name = it["name"]
        cand = common.AUDIO / kind / "candidates"
        keep = list(d.get("keep") or [])
        if decision == "approve" and not keep:
            # numbered takes only, so "spawn" doesn't swallow "spawn_elite_1"
            pattern = f"{name}_s[0-9]*.wav" if kind == "music" else f"{name}_[0-9]*.wav"
            keep = sorted(p.stem for p in cand.glob(pattern))
        copied = []
        if decision in ("approve", "more"):
            in_game = it.setdefault("in_game", [])
            for take in keep:
                src = cand / f"{take}.wav"
                tag = f"r{args.round}:{take}"   # take names repeat between rounds
                if tag in in_game or not src.exists():
                    continue
                dst = common.AUDIO / kind / f"{name}_{next_index(common.AUDIO / kind, name)}.wav"
                shutil.copy(src, dst)
                in_game.append(tag)
                copied.append(dst.name)
        it["status"] = STATUS[decision]
        comment = (d.get("comment") or "").strip()
        if comment:
            note = f"round {args.round}: {comment}"
            if note not in it.get("notes", ""):
                it["notes"] = (it.get("notes", "") + " | " + note).strip(" |")
        print(f"{key:24s} {decision:10s} {' '.join(copied)}")
    for kind, (path, m) in manifests.items():
        path.write_text(json.dumps(m, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
