"""Headless balance harness for RHIZOMORPH.

Runs many all-bot matches in parallel through `main.gd --sim` (Godot --headless
--fixed-fps: no rendering, the CPU stand-in for the mycelium, simulated time as fast
as the CPU allows) and aggregates what they report: win rate per court, how long
games last, who falls first, income per minute, units trained, spore actions.

  python tools/sim/run_batch.py --seeds 24 --label baseline
  python tools/sim/run_batch.py --compare baseline after_nerf

Each run's raw summary lands in sim_runs/<label>/match_<n>.json and the report in
sim_runs/<label>/report.md (sim_runs/ is git-ignored). Seeds are --match values, so
the same seed list gives a like-for-like comparison between two versions of the game.
"""

import argparse
import json
import math
import os
import statistics
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT.parent / "USNEA" / "engine" / "godot-4.7.2" / "Godot_v4.7.2-stable_win64_console.exe"
RUNS = ROOT / "sim_runs"
COURTS = ["amanita", "morel", "veiled"]
NAMES = {"amanita": "Amanita Court", "morel": "Morel Hollow", "veiled": "Veiled Choir"}


def run_one(seed: int, seconds: float, fps: int, out: Path) -> dict:
    cmd = [str(GODOT), "--headless", "--path", str(ROOT), "--fixed-fps", str(fps), "--",
           "--sim", f"--match={seed}", f"--seconds={seconds}"]
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=max(600, seconds * 2))
    except subprocess.TimeoutExpired as e:
        res = {"match": seed, "failed": True, "errors": ["timed out"], "tail": str(e.stdout or "")[-800:], "wall": round(time.time() - t0, 1)}
        (out / f"match_{seed}.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
        return res
    line = next((ln for ln in p.stdout.splitlines() if ln.startswith("SIM ")), None)
    errors = [ln for ln in (p.stdout + p.stderr).splitlines() if "SCRIPT ERROR" in ln]
    if line is None:
        res = {"match": seed, "failed": True, "errors": errors[:5], "tail": p.stdout[-800:]}
    else:
        res = json.loads(line[4:])
        res["errors"] = errors[:5]
    res["wall"] = round(time.time() - t0, 1)
    (out / f"match_{seed}.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
    return res


def wilson(k: int, n: int) -> tuple:
    """95% interval for a win rate of k out of n."""
    if n == 0:
        return (0.0, 0.0)
    z = 1.96
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def load(label: str) -> list:
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted((RUNS / label).glob("match_*.json"))]


def report(label: str, runs: list) -> str:
    ok = [r for r in runs if not r.get("failed")]
    n = len(ok)
    lines = [f"# Balance report: {label}", "",
             f"{n} matches ({len(runs) - n} failed), headless with CPU mycelium."]
    errs = sum(1 for r in runs if r.get("errors"))
    if errs:
        lines.append(f"**{errs} runs printed script errors.**")
    lines += ["", "| court | wins | win rate (95% range) | fell first | mean time of death |",
              "|---|---|---|---|---|"]
    for i, c in enumerate(COURTS):
        wins = sum(1 for r in ok if r["winner"] == i)
        lo, hi = wilson(wins, n)
        deaths = [r["courts"][i]["died"] for r in ok if r["courts"][i]["died"] >= 0]
        first = 0
        for r in ok:
            ds = [(r["courts"][k]["died"], k) for k in range(3) if r["courts"][k]["died"] >= 0]
            if ds and min(ds)[1] == i:
                first += 1
        mean_d = f"{statistics.mean(deaths) / 60:.1f} min" if deaths else "never"
        lines.append(f"| {NAMES[c]} | {wins} | {wins / max(n, 1):.0%} ({lo:.0%} to {hi:.0%}) | {first} | {mean_d} |")
    # the rival cycle alternates by seed; show each direction so a predator bias is visible
    for step, label in [(1, "Court hunts Hollow, Hollow hunts Choir, Choir hunts Court"), (2, "the reverse")]:
        sub = [r for r in ok if r.get("rival_step", 1) == step]
        if sub:
            wins = ", ".join(f"{NAMES[c].split()[1]} {sum(1 for r in sub if r['winner'] == i)}" for i, c in enumerate(COURTS))
            lines.append("")
            lines.append(f"Rival cycle {step} ({label}), {len(sub)} matches: wins {wins}.")
    unresolved = sum(1 for r in ok if r["winner"] < 0)
    lens = [r["time"] for r in ok]
    if lens:
        lines += ["", f"Game length: median {statistics.median(lens) / 60:.1f} min, "
                      f"range {min(lens) / 60:.1f} to {max(lens) / 60:.1f} min. Unresolved at the time limit: {unresolved}."]
    # income per minute (mean over the matches where that court was still alive)
    lines += ["", "## Income per minute (mean while alive)", "",
              "| court | resource | m1 | m2 | m3 | m4 | m5 | m6 | m8 | m10 |", "|---|---|---|---|---|---|---|---|---|---|"]
    res_names = {"amanita": ["minerals", "sugar"], "morel": ["cellulose", "nitrogen"], "veiled": ["biomass", "spores"]}
    for i, c in enumerate(COURTS):
        for ri, rname in enumerate(res_names[c]):
            idx = 2 if (c == "veiled" and ri == 1) else ri
            cells = []
            for m in [1, 2, 3, 4, 5, 6, 8, 10]:
                vals = [r["courts"][i]["hist"][m - 1][idx] for r in ok
                        if len(r["courts"][i]["hist"]) >= m and (r["courts"][i]["died"] < 0 or r["courts"][i]["died"] > m * 60)]
                cells.append(f"{statistics.mean(vals):.1f}" if vals else "-")
            lines.append(f"| {NAMES[c]} | {rname} | " + " | ".join(cells) + " |")
    lines += ["", "## Activity (mean per match)", "", "| court | units trained | techs | structures at end |", "|---|---|---|---|"]
    for i, c in enumerate(COURTS):
        lines.append(f"| {NAMES[c]} | {statistics.mean(r['courts'][i]['trained'] for r in ok):.0f} | "
                     f"{statistics.mean(r['courts'][i]['techs'] for r in ok):.1f} | "
                     f"{statistics.mean(r['courts'][i]['structs'] for r in ok):.1f} |")
    casts = {}
    for r in ok:
        for k, v in r.get("casts", {}).items():
            casts[k] = casts.get(k, 0) + v
    if casts:
        lines += ["", "Spore actions and sporulations per match: " +
                  ", ".join(f"{k.replace('cast_', '')} {v / n:.1f}" for k, v in sorted(casts.items()))]
    walls = [r["wall"] for r in runs]
    lines += ["", f"Wall time per match: median {statistics.median(walls):.0f} s."]
    return "\n".join(lines) + "\n"


def compare(a: str, b: str) -> str:
    ra, rb = [r for r in load(a) if not r.get("failed")], [r for r in load(b) if not r.get("failed")]
    lines = [f"# {a} vs {b}", "", f"| court | {a} win rate | {b} win rate |", "|---|---|---|"]
    for i, c in enumerate(COURTS):
        wa = sum(1 for r in ra if r["winner"] == i)
        wb = sum(1 for r in rb if r["winner"] == i)
        la, ha = wilson(wa, len(ra))
        lb, hb = wilson(wb, len(rb))
        lines.append(f"| {NAMES[c]} | {wa}/{len(ra)} ({la:.0%} to {ha:.0%}) | {wb}/{len(rb)} ({lb:.0%} to {hb:.0%}) |")
    return "\n".join(lines) + "\n"


def playtests() -> str:
    """Human games from playtests/ beside the bots' averages for the same court."""
    games = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "playtests").glob("*.json"))]
    if not games:
        return "No playtests yet: finish a game (win or lose) and it is saved to playtests/."
    bots = []
    for d in sorted(RUNS.iterdir(), key=lambda p: p.stat().st_mtime) if RUNS.exists() else []:
        bots = [r for r in load(d.name) if not r.get("failed")] or bots
    lines = ["# Playtests", "", "| date | court | result | length | units trained | techs | income at m3 (bots) | income at m6 (bots) |",
             "|---|---|---|---|---|---|---|---|"]
    for g in games:
        i = COURTS.index(g["human"])
        me = g["courts"][i]

        def inc(runs, m):
            vals = [r["courts"][i]["hist"][m - 1][0] for r in runs if len(r["courts"][i]["hist"]) >= m]
            return statistics.mean(vals) if vals else float("nan")

        mine3 = me["hist"][2][0] if len(me["hist"]) >= 3 else float("nan")
        mine6 = me["hist"][5][0] if len(me["hist"]) >= 6 else float("nan")
        lines.append(f"| {g['date'][:16]} | {NAMES[g['human']]} | {'won' if g['won'] else 'lost'} | {g['time'] / 60:.1f} min | "
                     f"{me['trained']} | {me['techs']} | {mine3:.1f} ({inc(bots, 3):.1f}) | {mine6:.1f} ({inc(bots, 6):.1f}) |")
    lines.append("\nIncome is the court's main resource per second; the bots' figure is the mean from the latest batch.")
    return "\n".join(lines) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=24)
    ap.add_argument("--first", type=int, default=1, help="first --match seed")
    ap.add_argument("--jobs", type=int, default=max(1, min(10, (os.cpu_count() or 4) // 2)))
    ap.add_argument("--seconds", type=float, default=900.0, help="time limit per match (game seconds)")
    ap.add_argument("--fps", type=int, default=10, help="simulated frames per game second")
    ap.add_argument("--label", default=time.strftime("run_%Y%m%d_%H%M%S"))
    ap.add_argument("--compare", nargs=2, metavar=("A", "B"))
    ap.add_argument("--playtests", action="store_true", help="show human games beside the bots")
    args = ap.parse_args()
    if args.playtests:
        print(playtests())
        return
    if args.compare:
        print(compare(*args.compare))
        return
    out = RUNS / args.label
    out.mkdir(parents=True, exist_ok=True)
    seeds = list(range(args.first, args.first + args.seeds))
    print(f"{len(seeds)} matches, {args.jobs} at a time -> {out}", flush=True)
    t0 = time.time()
    runs = []
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(run_one, s, args.seconds, args.fps, out): s for s in seeds}
        for fut in as_completed(futs):
            r = fut.result()
            runs.append(r)
            who = "FAILED" if r.get("failed") else (NAMES[COURTS[r["winner"]]] if r["winner"] >= 0 else "unresolved")
            print(f"  match {r['match']:>3}: {who:14s} {r.get('time', 0) / 60:5.1f} min  ({r['wall']:.0f} s wall)", flush=True)
    runs.sort(key=lambda r: r["match"])
    text = report(args.label, runs)
    (out / "report.md").write_text(text, encoding="utf-8")
    print(f"\n{text}\nTotal wall time {time.time() - t0:.0f} s.")


if __name__ == "__main__":
    main()
