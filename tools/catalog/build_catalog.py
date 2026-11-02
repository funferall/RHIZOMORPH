"""Build the asset catalog page (one plate per species) from the renders that
`main.gd --catalog=screenshots/catalog/img` writes, with the images embedded so the
page is a single file to publish as an artifact.

  G=../USNEA/engine/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe
  $G --path . -- --catalog=screenshots/catalog/img        # add --only=a,b to re-render a few
  python tools/catalog/build_catalog.py                    # -> screenshots/catalog/catalog.html

tools/catalog/seen.json remembers when each species first appeared, so new ones get a tag.
"""

import base64
import datetime
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMG = ROOT / "screenshots" / "catalog" / "img"
OUT = ROOT / "screenshots" / "catalog" / "catalog.html"
SEEN = Path(__file__).with_name("seen.json")

# what each model is meant to be, in the field guide's terms
LATIN = {
    "giant_agaric": "Amanita muscaria, colossal",
    "fly_agaric": "Amanita muscaria",
    "agaric_button": "Amanita muscaria, button stage",
    "clathrus": "Clathrus ruber",
    "death_cap": "Amanita phalloides",
    "armillaria": "Armillaria mellea",
    "chanterelle": "Cantharellus cibarius",
    "mycena_lantern": "Mycena chlorophos",
    "mycena_white": "Mycena galericulata",
    "bracket": "Trametes versicolor",
    "giant_morel": "Morchella esculenta, colossal",
    "morel": "Morchella esculenta",
    "morel_small": "Morchella esculenta",
    "earthstar": "Geastrum triplex",
    "cordyceps": "Cordyceps militaris",
    "giant_veiled": "Phallus indusiatus, colossal",
    "veiled_lady": "Phallus indusiatus",
    "birds_nest": "Cyathus striatus",
    "pilobolus": "Pilobolus crystallinus",
    "giant_puffball": "Calvatia gigantea",
    "puffball_small": "Lycoperdon perlatum",
    "inkcap": "Coprinellus micaceus",
    "inkcap_bed": "Coprinus comatus",
    "elf_cup_small": "Sarcoscypha coccinea",
    "anthill": "Formica rufa mound",
    "u_wartling": "Amanita muscaria, walking",
    "u_spitter": "Amanita muscaria, walking",
    "u_angel": "Amanita virosa, walking",
    "u_bruiser": "Morchella esculenta, walking",
    "u_slinger": "Sarcoscypha coccinea, walking",
    "u_bomber": "Lycoperdon perlatum, walking",
    "u_sniper": "Pilobolus crystallinus, walking",
    "u_stalker": "Cordyceps militaris",
    "u_zombie": "Ophiocordyceps in a sporeling host",
    "i_ant": "Formica rufa",
    "t_ant": "Ophiocordyceps unilateralis in Formica",
    "i_beetle": "Ips typographus",
    "t_beetle": "Cordyceps in Ips typographus",
    "i_fly": "Lucilia caesar",
    "t_fly": "Entomophthora muscae in Lucilia",
    "i_springtail": "Tomocerus (Collembola), swarm",
    "i_stag": "Lucanus cervus, male",
    "t_stag": "Ophiocordyceps in Lucanus cervus",
    "i_borer": "Agrilus planipennis",
    "truffle": "Tuber melanosporum",
    "panther_ring": "Amanita pantherina",
    "morel_blond": "Morchella esculenta, yellow",
    "common_stinkhorn": "Phallus impudicus",
    "honey_rot": "Armillaria ostoyae",
    "root_snare": "Tree roots with Amanita buttons",
    "brood_chamber": "Isaria on insect cocoons",
    "oyster_shelf": "Pleurotus ostreatus",
    "cortina_thicket": "Cortinarius violaceus with Lactarius deliciosus",
    "nursery": "Betula sapling with Cantharellus",
    "u_webcap": "Cortinarius violaceus, walking",
    "u_milkcap": "Lactarius deliciosus, walking",
    "u_cep_bulwark": "Boletus edulis, walking",
}

COURTS = [
    (0, "amanita", "Amanita Court", "Mycorrhizal. Feeds the trees and is fed by them."),
    (1, "morel", "Morel Hollow", "Saprotroph. Eats the dead: logs, litter and the fallen."),
    (2, "veiled", "Veiled Choir", "Parasite. Rides insects and grows from their bodies."),
    (3, "forest", "The forest floor", "Neutral wildlife and nests, belonging to no court."),
]
KIND_ORDER = {"structure": 0, "unit": 1, "insect": 1, "prop": 2, "decor": 3}
KIND_LABEL = {"structure": "Structure", "unit": "Unit", "insect": "Insect", "prop": "Prop", "decor": "Decor"}


def main() -> None:
    entries = json.loads((IMG / "catalog.json").read_text(encoding="utf-8"))
    today = datetime.date.today().isoformat()
    seen = json.loads(SEEN.read_text(encoding="utf-8")) if SEEN.exists() else {}
    for e in entries:
        seen.setdefault(e["id"], today)
    SEEN.write_text(json.dumps(seen, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    newest = max(seen[e["id"]] for e in entries)
    all_same = all(seen[e["id"]] == newest for e in entries)

    sections = []
    for f, key, name, blurb in COURTS:
        items = [e for e in entries if e["faction"] == f]
        items.sort(key=lambda e: (KIND_ORDER.get(e["kind"], 9), e["used_by"][0]))
        cards = []
        for e in items:
            img = IMG / f"{e['id']}.webp"
            if not img.exists():
                continue
            data = base64.b64encode(img.read_bytes()).decode()
            is_new = not all_same and seen[e["id"]] == newest
            title = html.escape(e["used_by"][0])
            also = ", ".join(html.escape(u) for u in e["used_by"][1:])
            latin = html.escape(LATIN.get(e["id"], ""))
            cards.append(f"""
      <figure class="plate" data-kind="{e['kind']}">
        <button class="shot" type="button" aria-label="Enlarge {title}"><img src="data:image/webp;base64,{data}" alt="{title}" loading="lazy" width="640" height="640"></button>
        <figcaption>
          <div class="row"><h3>{title}</h3>{'<span class="new">new</span>' if is_new else ''}</div>
          {f'<p class="latin">{latin}</p>' if latin else ''}
          {f'<p class="also">Also: {also}</p>' if also else ''}
          <dl>
            <div><dt>Kind</dt><dd>{KIND_LABEL.get(e['kind'], e['kind'])}</dd></div>
            <div><dt>Height</dt><dd>{e.get('height_m', 0):.2f} m</dd></div>
            <div><dt>Spread</dt><dd>{e.get('width_m', 0):.2f} m</dd></div>
          </dl>
          <code>{e['id']}</code>
        </figcaption>
      </figure>""")
        if cards:
            sections.append(f"""
  <section class="court {key}" id="{key}" data-court="{key}">
    <header><h2>{name}</h2><p>{blurb}</p><span class="count">{len(cards)} plates</span></header>
    <div class="grid">{''.join(cards)}
    </div>
  </section>""")

    page = TEMPLATE.replace("{{SECTIONS}}", "".join(sections))
    page = page.replace("{{COUNT}}", str(sum(1 for e in entries if (IMG / f"{e['id']}.webp").exists())))
    page = page.replace("{{DATE}}", datetime.date.today().strftime("%d %B %Y").lstrip("0"))
    OUT.write_text(page, encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


TEMPLATE = """<title>RHIZOMORPH Specimen Plates</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Barlow+Condensed:wght@500;600&family=IBM+Plex+Mono:wght@400&display=swap">
<style>
/* Layout: a field guide's plate pages. One band per court, specimen plates in a grid, each tagged like a herbarium label. */
:root {
  --loam: #15100b;
  --bark: #201810;
  --rule: #3a2c1e;
  --bone: #eadfc8;
  --dust: #a8977b;
  --amber: #e0a94a;
  --amanita: #e2493a;
  --morel: #e9c24a;
  --veiled: #b98cf5;
  --forest: #9c8d6a;
  --display: "Cormorant Garamond", "Iowan Old Style", Georgia, serif;
  --label: "Barlow Condensed", "Arial Narrow", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, Consolas, monospace;
  color-scheme: dark;
}
* { box-sizing: border-box; }
body {
  background: var(--loam);
  color: var(--bone);
  font-family: var(--label);
  font-size: 16px;
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
  padding-block: 28px 64px;
}
.wrap { max-width: 1240px; margin: 0 auto; display: grid; gap: 40px; }
.masthead { display: grid; gap: 14px; border-bottom: 1px solid var(--rule); padding-bottom: 22px; }
.masthead .eyebrow { font-family: var(--mono); font-size: 12px; color: var(--dust); letter-spacing: 0.08em; text-transform: uppercase; }
h1 { font-family: var(--display); font-weight: 600; font-size: clamp(34px, 6vw, 58px); line-height: 1; margin: 0; text-wrap: balance; }
h1 em { color: var(--amber); font-style: italic; font-weight: 500; }
.masthead p { margin: 0; max-width: 62ch; color: var(--dust); font-size: 17px; line-height: 1.45; }
nav { display: flex; flex-wrap: wrap; gap: 8px; }
nav button {
  font: 600 14px var(--label); letter-spacing: 0.06em; text-transform: uppercase;
  color: var(--dust); background: transparent; border: 1px solid var(--rule);
  border-radius: 999px; padding: 6px 14px; cursor: pointer;
}
nav button:hover { color: var(--bone); border-color: var(--dust); }
nav button[aria-pressed="true"] { color: var(--loam); background: var(--bone); border-color: var(--bone); }
nav button:focus-visible, .shot:focus-visible { outline: 2px solid var(--amber); outline-offset: 2px; }
nav .sw { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 7px; vertical-align: 1px; }

.court { display: grid; gap: 18px; }
.court > header { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 16px; border-top: 3px solid var(--c); padding-top: 12px; }
.court h2 { font-family: var(--display); font-weight: 600; font-size: 30px; margin: 0; color: var(--c); }
.court header p { margin: 0; color: var(--dust); font-size: 16px; flex: 1 1 260px; min-width: 0; }
.court .count { font-family: var(--mono); font-size: 12px; color: var(--dust); }
.amanita { --c: var(--amanita); } .morel { --c: var(--morel); } .veiled { --c: var(--veiled); } .forest { --c: var(--forest); }

.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 230px), 1fr)); gap: 18px; }
.plate { margin: 0; background: var(--bark); border: 1px solid var(--rule); display: grid; grid-template-rows: auto 1fr; }
.shot { display: block; padding: 0; border: 0; background: #0d0a07; cursor: zoom-in; }
.shot img { display: block; width: 100%; height: auto; aspect-ratio: 1; object-fit: cover; }
figcaption { padding: 12px 14px 14px; display: grid; gap: 6px; align-content: start; border-left: 3px solid var(--c); }
.row { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; }
h3 { font: 600 19px/1.15 var(--label); margin: 0; letter-spacing: 0.01em; }
.new { font: 600 11px var(--mono); text-transform: uppercase; letter-spacing: 0.08em; color: var(--loam); background: var(--amber); padding: 2px 6px; border-radius: 3px; flex: none; }
.latin { font-family: var(--display); font-style: italic; font-size: 17px; color: var(--bone); opacity: 0.85; margin: 0; }
.also { margin: 0; font-size: 14px; color: var(--dust); }
dl { display: flex; flex-wrap: wrap; gap: 4px 16px; margin: 4px 0 0; }
dl div { display: grid; }
dt { font: 11px var(--mono); color: var(--dust); text-transform: uppercase; letter-spacing: 0.08em; }
dd { margin: 0; font-size: 15px; font-variant-numeric: tabular-nums; }
code { font: 12px var(--mono); color: var(--dust); }

dialog { border: 1px solid var(--rule); background: var(--loam); color: var(--bone); padding: 0; max-width: min(92vw, 820px); }
dialog::backdrop { background: rgba(8, 6, 4, 0.85); }
dialog img { display: block; width: 100%; height: auto; }
dialog form { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 10px 14px; }
dialog p { margin: 0; font-family: var(--display); font-size: 20px; }
dialog button { font: 600 14px var(--label); text-transform: uppercase; letter-spacing: 0.06em; color: var(--bone); background: transparent; border: 1px solid var(--rule); padding: 6px 14px; cursor: pointer; }
footer { color: var(--dust); font-size: 14px; border-top: 1px solid var(--rule); padding-top: 16px; }
footer code { font-size: 12px; }
</style>

<div class="wrap">
  <div class="masthead">
    <span class="eyebrow">RHIZOMORPH &middot; {{COUNT}} plates &middot; rendered {{DATE}}</span>
    <h1>Specimen plates <em>of the war beneath the leaves</em></h1>
    <p>Every model in the game, rendered in-engine under the game's golden-hour light and tinted the way its court wears it. New models are added as they are built.</p>
    <nav aria-label="Show">
      <button type="button" data-show="all" aria-pressed="true">All</button>
      <button type="button" data-show="amanita" aria-pressed="false"><span class="sw" style="background:var(--amanita)"></span>Amanita Court</button>
      <button type="button" data-show="morel" aria-pressed="false"><span class="sw" style="background:var(--morel)"></span>Morel Hollow</button>
      <button type="button" data-show="veiled" aria-pressed="false"><span class="sw" style="background:var(--veiled)"></span>Veiled Choir</button>
      <button type="button" data-show="forest" aria-pressed="false"><span class="sw" style="background:var(--forest)"></span>Forest floor</button>
    </nav>
  </div>
{{SECTIONS}}
  <footer>Rendered by <code>main.gd --catalog</code>, assembled by <code>tools/catalog/build_catalog.py</code>. Sizes are the model's bounding box in metres; a unit stands about 1 m tall.</footer>
</div>

<dialog id="zoom">
  <img id="zoom-img" alt="">
  <form method="dialog"><p id="zoom-name"></p><button id="zoom-close" value="close">Close</button></form>
</dialog>

<script>
const buttons = document.querySelectorAll("nav button");
function show(which) {
  buttons.forEach(b => b.setAttribute("aria-pressed", String(b.dataset.show === which)));
  document.querySelectorAll(".court").forEach(s => { s.hidden = which !== "all" && s.dataset.court !== which; });
}
buttons.forEach(b => b.addEventListener("click", () => {
  show(b.dataset.show);
  if (b.dataset.show !== "all") history.replaceState(null, "", "#" + b.dataset.show);
  else history.replaceState(null, "", location.pathname + location.search);
}));
const start = location.hash.slice(1);
if (["amanita", "morel", "veiled", "forest"].includes(start)) show(start);
const dlg = document.getElementById("zoom");
document.querySelectorAll(".shot").forEach(btn => btn.addEventListener("click", () => {
  const img = btn.querySelector("img");
  document.getElementById("zoom-img").src = img.src;
  document.getElementById("zoom-img").alt = img.alt;
  document.getElementById("zoom-name").textContent = img.alt;
  dlg.showModal();
}));
dlg.addEventListener("click", e => { if (e.target === dlg) dlg.close(); });
</script>
"""

if __name__ == "__main__":
    main()
