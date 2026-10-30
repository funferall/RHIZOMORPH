"""Write audio/review.html: every candidate clip next to its prompt, status and
notes, for auditioning in a browser. Re-run after each generation batch.

  python review.py
"""

import html

import common


def section(kind: str, items: list, files_for) -> str:
    rows = []
    for it in items:
        name = it["name"]
        clips = files_for(name)
        players = "".join(
            f'<figure><audio controls preload="none" src="{kind}/candidates/{c.name}"></audio><figcaption>{c.name}</figcaption></figure>'
            for c in clips) or '<p class="none">not generated yet</p>'
        chosen = [p for p in (common.AUDIO / kind).glob(f"{name}*.wav")]
        keep = " ".join(p.name for p in chosen)
        rows.append(f"""
<section class="{html.escape(it.get('status', 'todo'))}">
  <h3>{html.escape(name)} <span class="st">{html.escape(it.get('status', 'todo'))}</span>{f' <span class="kept">in game: {html.escape(keep)}</span>' if keep else ''}</h3>
  {''.join(f'<p class="prompt">{html.escape(t)}</p>' for t in (it.get('prompts') or [it['prompt']]))}
  {f'<p class="notes">{html.escape(it["notes"])}</p>' if it.get("notes") else ''}
  <div class="clips">{players}</div>
</section>""")
    return "".join(rows)


def main() -> None:
    _, music = common.manifest("music")
    _, sfx = common.manifest("sfx")
    mc = common.AUDIO / "music" / "candidates"
    sc = common.AUDIO / "sfx" / "candidates"
    body = "<h2>Music</h2>" + section("music", music["tracks"], lambda n: sorted(mc.glob(f"{n}_s*.wav")))
    groups = []
    for s in sfx["sounds"]:
        if s["group"] not in groups:
            groups.append(s["group"])
    for g in groups:
        body += f"<h2>SFX: {html.escape(g)}</h2>" + section(
            "sfx", [s for s in sfx["sounds"] if s["group"] == g], lambda n: sorted(sc.glob(f"{n}_[0-9]*.wav")))
    page = f"""<!doctype html><html><head><meta charset="utf-8"><title>RHIZOMORPH audio review</title>
<style>
body {{ background:#14100c; color:#e8dfcc; font:14px/1.45 'Segoe UI',sans-serif; margin:24px auto; max-width:1100px; padding:0 16px; }}
h2 {{ font-family:Georgia,serif; color:#f2d9a0; border-bottom:1px solid #4a3d2a; padding-bottom:4px; margin-top:36px; }}
section {{ background:#1e1812; border:1px solid #3a2f22; border-radius:10px; padding:10px 14px; margin:10px 0; }}
section.keep {{ border-color:#6f9a4a; }} section.redo {{ border-color:#a9553f; }}
h3 {{ margin:0 0 4px; font-size:15px; }} .st {{ font-weight:normal; font-size:12px; color:#a39880; margin-left:8px; }}
.kept {{ font-weight:normal; font-size:12px; color:#9fd07a; margin-left:8px; }}
.prompt {{ color:#b9ae96; margin:0 0 8px; }} .notes {{ color:#e0b070; margin:0 0 8px; }} .none {{ color:#6d6252; margin:0; }}
.clips {{ display:flex; flex-wrap:wrap; gap:10px; }} figure {{ margin:0; }} audio {{ width:250px; height:34px; }}
figcaption {{ font-size:11px; color:#8a7f6a; }}
</style></head><body><h1 style="font-family:Georgia,serif">RHIZOMORPH audio review</h1>
<p>Pick favourites by copying them out of <code>candidates/</code> into <code>audio/sfx</code> or <code>audio/music</code> as <code>&lt;name&gt;.wav</code> (variants: <code>&lt;name&gt;_1.wav</code>, <code>_2</code>...). Notes and status live in each folder's <code>prompts.json</code>.</p>
{body}</body></html>"""
    (common.AUDIO / "review.html").write_text(page, encoding="utf-8")
    print(common.AUDIO / "review.html")


if __name__ == "__main__":
    main()
