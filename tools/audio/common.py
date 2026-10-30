"""Shared bits for the RHIZOMORPH audio generators: talking to a ComfyUI server
and the small amount of DSP needed to make game-ready clips (trim, fades,
loudness, seamless loops)."""

import json
import time
import urllib.request
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / "audio"


# --- ComfyUI -------------------------------------------------------------------

def _post(server: str, path: str, body: dict) -> dict:
    req = urllib.request.Request(server + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def _get(server: str, path: str) -> dict:
    with urllib.request.urlopen(server + path, timeout=30) as r:
        return json.loads(r.read())


def run(server: str, wf: dict, comfy_out: Path, prefix: str) -> list[Path]:
    """Queue an API workflow, wait, and return the audio files it wrote."""
    pid = _post(server, "/prompt", {"prompt": wf})["prompt_id"]
    while True:
        h = _get(server, "/history/" + pid)
        if pid in h:
            break
        time.sleep(1.5)
    st = h[pid].get("status", {})
    if st.get("status_str") == "error":
        raise RuntimeError(json.dumps(st.get("messages", [])[-1:], indent=1))
    files = []
    for out in h[pid]["outputs"].values():
        for item in out.get("audio", []):
            files.append(comfy_out / item.get("subfolder", "") / item["filename"])
    if not files:
        # some savers (MusicGen-HF) don't report their file; find it by prefix
        found = sorted(comfy_out.rglob(prefix + "*"), key=lambda p: p.stat().st_mtime)
        files = found[-1:]
    if not files:
        raise RuntimeError("no audio for %s in %s" % (prefix, comfy_out))
    return files


# --- DSP -----------------------------------------------------------------------

def _rms_db(a: np.ndarray, win: int) -> np.ndarray:
    m = a.mean(axis=1)
    n = len(m) // win
    frames = m[: n * win].reshape(n, win)
    return 20 * np.log10(np.sqrt((frames ** 2).mean(axis=1)) + 1e-9)


def trim(a: np.ndarray, sr: int, below_peak_db: float = 40.0, head: bool = True, tail: bool = True) -> np.ndarray:
    """Cut silence (quieter than peak - below_peak_db) off the ends."""
    win = max(sr // 100, 1)
    r = _rms_db(a, win)
    if len(r) == 0:
        return a
    loud = np.nonzero(r > r.max() - below_peak_db)[0]
    if len(loud) == 0:
        return a
    s = max(loud[0] - 1, 0) * win if head else 0
    e = min((loud[-1] + 2) * win, len(a)) if tail else len(a)
    return a[s:e]


def fade(a: np.ndarray, sr: int, fade_in: float, fade_out: float) -> np.ndarray:
    a = a.copy()
    fi, fo = int(fade_in * sr), int(fade_out * sr)
    if fi > 0:
        a[:fi] *= np.linspace(0.0, 1.0, fi)[:, None]
    if fo > 0:
        a[-fo:] *= np.linspace(1.0, 0.0, fo)[:, None]
    return a


def loop(a: np.ndarray, sr: int, xfade: float) -> np.ndarray:
    """Fold the tail over the head with an equal-power crossfade."""
    n = int(xfade * sr)
    if len(a) <= 3 * n:
        return a
    t = np.linspace(0.0, 1.0, n)[:, None]
    head = a[:n] * np.sin(t * np.pi / 2)
    tail = a[-n:] * np.cos(t * np.pi / 2)
    return np.concatenate([head + tail, a[n:-n]])


def normalize(a: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    peak = np.abs(a).max()
    return a * (10 ** (peak_db / 20) / peak) if peak > 0 else a


def load(p: Path) -> tuple[np.ndarray, int]:
    a, sr = sf.read(p, always_2d=True)
    return a, sr


def save(p: Path, a: np.ndarray, sr: int) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    sf.write(p, a, sr, subtype="PCM_16")


def manifest(kind: str) -> tuple[Path, dict]:
    p = AUDIO / kind / "prompts.json"
    return p, json.loads(p.read_text(encoding="utf-8"))
