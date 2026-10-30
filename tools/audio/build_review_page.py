"""Build the RHIZOMORPH sound review page (published as a claude.ai artifact).

Converts every candidate in audio/{music,sfx}/candidates to MP3 under
audio/review_site/a/, and writes audio/review_site/index.html with the item list
(name, what it's for, prompt, takes) embedded. Decisions and comments are saved
by the page into its `db` store (collection `reviews`, one doc per item:
{decision, keep[], comment, round, updatedAt}), where Claude reads them back.

  python build_review_page.py
"""

import argparse
import json
from pathlib import Path

import soundfile as sf

import common

SITE = common.AUDIO / "review_site"
GROUP_TITLES = {"music": "Music", "building": "Building & supply", "units": "Units", "structures": "Structures",
                "abilities": "Spore actions", "ambience": "Ambience", "ui": "Interface"}


def convert(src: Path, dst: Path) -> float:
    a, sr = sf.read(src, always_2d=True)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
        sf.write(dst, a, sr, format="MP3", bitrate_mode="CONSTANT", compression_level=0.35)
    return round(len(a) / sr, 2)


def wanted(it: dict, since: float) -> bool:
    # a later round only shows items still being worked on
    return since == 0 or it.get("status", "todo") in ("todo", "more", "redo", "review")


def fresh(p: Path, since: float) -> bool:
    return p.stat().st_mtime >= since


def last_note(it: dict) -> str:
    notes = [n.strip() for n in it.get("notes", "").split("|") if n.strip().startswith("round")]
    return notes[-1] if notes else ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", type=float, default=0.0, help="only takes newer than this unix time (later rounds)")
    args = ap.parse_args()
    items = []
    _, music = common.manifest("music")
    for t in music["tracks"]:
        if not wanted(t, args.since):
            continue
        takes = []
        for f in sorted((common.AUDIO / "music" / "candidates").glob(f"{t['name']}_s*.wav")):
            if not fresh(f, args.since):
                continue
            dur = convert(f, SITE / "a" / "music" / (f.stem + ".mp3"))
            takes.append({"id": f.stem, "src": f"a/music/{f.stem}.mp3", "dur": dur})
        items.append({"key": "music-" + t["name"], "kind": "music", "group": "music", "name": t["name"],
                      "use": t.get("use", ""), "prompts": [t["prompt"]], "takes": takes, "loop": t.get("loop", False),
                      "note": last_note(t), "in_game": len(t.get("in_game", []))})
    _, sfx = common.manifest("sfx")
    for s in sfx["sounds"]:
        if not wanted(s, args.since):
            continue
        takes = []
        files = sorted((common.AUDIO / "sfx" / "candidates").glob(f"{s['name']}_[0-9]*.wav"), key=lambda p: int(p.stem.rsplit("_", 1)[1]))
        for f in files:
            if not fresh(f, args.since):
                continue
            dur = convert(f, SITE / "a" / "sfx" / (f.stem + ".mp3"))
            takes.append({"id": f.stem, "src": f"a/sfx/{f.stem}.mp3", "dur": dur})
        items.append({"key": "sfx-" + s["name"], "kind": "sfx", "group": s["group"], "name": s["name"],
                      "use": s.get("use", ""), "prompts": s.get("prompts") or [s["prompt"]], "takes": takes, "loop": s.get("loop", False),
                      "note": last_note(s), "in_game": len(s.get("in_game", []))})
    data = {"groups": GROUP_TITLES, "items": items}
    tpl = (Path(__file__).parent / "review_page.html").read_text(encoding="utf-8")
    html = tpl.replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
    (SITE / "index.html").write_text(html, encoding="utf-8")
    (SITE / ".gdignore").touch()
    files = sorted(t["src"] for it in items for t in it["takes"])
    (SITE / "files.json").write_text(json.dumps(files, indent=0), encoding="utf-8")
    size = sum((SITE / f).stat().st_size for f in files)
    print(f"{len(items)} items, {len(files)} takes, {size / 1e6:.1f} MB -> {SITE / 'index.html'}")


if __name__ == "__main__":
    main()
