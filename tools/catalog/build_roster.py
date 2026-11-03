"""Build the order-of-battle page: every building and unit by court, what makes what, what each
costs and its stats, with the catalog's in-engine render of each. One self-contained HTML file to
publish as an artifact.

  G=../USNEA/engine/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe
  $G --headless --path . --script tools/catalog/dump_data.gd       # data.gd -> roster_data.json
  $G --path . -- --catalog=screenshots/catalog/img                 # the images (shared with the catalog)
  python tools/catalog/build_roster.py                              # -> screenshots/catalog/roster.html
"""

import base64
import datetime
import html
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAT = ROOT / "screenshots" / "catalog"
IMG = CAT / "img"
OUT = CAT / "roster.html"
sys.path.insert(0, str(Path(__file__).parent))
from build_catalog import LATIN  # noqa: E402

D = json.loads((CAT / "roster_data.json").read_text(encoding="utf-8"))
S, U, T, C = D["structures"], D["units"], D["techs"], D["constants"]
FACTIONS = D["factions"]
KEYS = ["amanita", "morel", "veiled"]

ECONOMY = {"mantle", "rot_bracket", "oyster_shelf", "inkcap_bed", "stinkhorn_lure"}
SUPPORT = {"nursery", "honey_rot", "brood_chamber"}
PLACE = {"tree": "In a tree's roots", "deposit": "On a log, snag or branch", "territory": "Anywhere in your territory",
	"gap": "In a sunlit gap", "trunk": "On a trunk"}
SHOT = {"spit": "Spit", "puff": "Spore puff", "egg": "Lobbed shot", "web": "Cobweb", "": "Melee"}
# what a unit is for, in a few words (the data has no role field)
ROLE = {
	"wartling": "Melee", "spitter": "Ranged", "angel": "Elite assassin", "milkcap": "Tank", "webcap": "Ranged control",
	"cep": "Heavy protector", "bruiser": "Melee tank", "slinger": "Ranged", "bomber": "Splash artillery",
	"runner": "Fast scout", "binder": "Rooted wall", "sniper": "Elite long range", "t_ant": "Fast melee",
	"t_beetle": "Armoured melee", "t_stag": "Heavy melee", "t_fly": "Flying scout", "zombie": "Converted melee",
	"stalker": "Elite infector", "ant": "Host", "beetle": "Host", "fly": "Host", "stag": "Host", "borer": "Pest",
	"springtail": "Pest",
}


def esc(s):
	return html.escape(str(s), quote=True)


def num(x, digits=1):
	if isinstance(x, (int, float)):
		v = round(float(x), digits)
		return str(int(v)) if v == int(v) else ("%.*f" % (digits, v)).rstrip("0").rstrip(".")
	return str(x)


def tech_name(key):
	return T[key]["name"] if key in T else key


def court_of(f):
	return FACTIONS[f]


def res_names(f):
	return FACTIONS[f]["res_names"]


def cost_chips(f, cost, spores=0, extra=None):
	names = res_names(f)
	out = []
	for i, amt in enumerate(cost[:2]):
		if amt:
			out.append('<span class="chip r%d"><b>%s</b> %s</span>' % (i, num(amt), esc(names[i])))
	if spores:
		out.append('<span class="chip r2"><b>%s</b> %s</span>' % (num(spores), esc(names[2])))
	if extra:
		out.append('<span class="chip rx">%s</span>' % esc(extra))
	if not out:
		out.append('<span class="chip free">Free</span>')
	return "".join(out)


def stat(label, value, unit="", title=""):
	t = ' title="%s"' % esc(title) if title else ""
	return '<div%s><dt>%s</dt><dd>%s<small>%s</small></dd></div>' % (t, esc(label), value, esc(unit))


def attack_stats(a):
	rows = [stat("Damage", num(a["dmg"])), stat("Interval", num(a["cd"], 2), " s")]
	if a.get("dmg"):
		rows.append(stat("DPS", num(a["dmg"] / a["cd"]), "", "damage ÷ interval, before armour and poison"))
	rows.append(stat("Range", num(a["range"]) if a["range"] else "—", " m" if a["range"] else ""))
	return rows


def unit_traits(uid, u):
	t = []
	if u.get("elite"):
		t.append(("Elite", "hi"))
	if u.get("flies"):
		t.append(("Flies, crosses water", ""))
	if u.get("poison"):
		t.append(("Poison %s/s for 3 s" % num(u["poison"]), ""))
	if u.get("splash"):
		t.append(("Splash %s m" % num(u["splash"]), ""))
	if u.get("arc"):
		t.append(("Lobbed", ""))
	if u.get("root"):
		t.append(("Roots its target %s s" % num(u["root"]), ""))
	if u.get("immobilize"):
		t.append(("Pins its target %s s" % num(u["immobilize"]), ""))
	if u.get("regen"):
		t.append(("Regenerates %s hp/s" % num(u["regen"]), ""))
	if u.get("armor"):
		t.append(("Takes %d%% less from shots" % round(u["armor"] * 100), ""))
	if u.get("latex"):
		lx = u["latex"]
		t.append(("Latex: melee attackers take %s and slow %d%%" % (num(lx["dmg"]), round(lx["slow"] * 100)), ""))
	if u.get("cloak"):
		t.append(("Cloaked beyond %s m" % num(u["cloak"]), "hi"))
	if u.get("brace"):
		t.append(("Brace: catches shots within 3 m", ""))
	if u.get("cutter"):
		t.append(("Cord cutter", ""))
	if u.get("bores"):
		t.append(("Bores into trees", ""))
	if u.get("infects"):
		t.append(("Infects on %d%% of hits" % round(C["infect_stalker"] * 100), "hi"))
	if u.get("thrall"):
		life = 1.0 / C["thrall_decay"] / 60.0
		t.append(("Decays: %s%% hp/s (about %s min)" % (num(C["thrall_decay"] * 100, 2), num(life)), "warn"))
	if u.get("wall_max"):
		t.append(("Wall up to %s m, grows %s m/s" % (num(u["wall_max"]), num(u["wall_growth"], 2)), ""))
		t.append(("Wall slows enemies %d%%; thorns %s" % (round(u["wall_slow"] * 100), num(u["thorns"])), ""))
	if u.get("grazes"):
		t.append(("Grazes mycelium", "warn"))
	if u.get("life"):
		t.append(("Lives %s s" % num(u["life"]), ""))
	return t


def structure_traits(sid, s):
	t = []
	if s.get("on"):
		where = PLACE.get(s["on"], s["on"])
		if s.get("fed_tree"):
			where = "In the roots of a tree you feed"
		t.append((where, ""))
	if s.get("hidden"):
		t.append(("Hidden until enemies are close", "hi"))
	if s.get("income"):
		t.append(("+%s income/s" % num(s["income"]), ""))
	if s.get("spores"):
		t.append(("+%s spores/s" % num(s["spores"]), ""))
	if s.get("lure"):
		t.append(("Lures insects within %s m" % num(s["lure"]), ""))
	if s.get("gather"):
		t.append(("Gathers corpses within %s m" % num(s["gather"]), ""))
	if s.get("brood"):
		t.append(("Thralls within %s m stop decaying" % num(s["brood"]), ""))
	if s.get("research"):
		t.append(("Researches lineages", "hi"))
	a = s.get("attack")
	if a:
		if a.get("splash"):
			t.append(("Splash %s m" % num(a["splash"]), ""))
		if a.get("poison"):
			t.append(("Poison %s/s for 3 s" % num(a["poison"]), ""))
		if a.get("slow"):
			t.append(("Slows %d%% for %s s" % (round(a["slow"] * 100), num(a.get("slow_t", 2))), ""))
		if a.get("arc"):
			t.append(("Lobbed", ""))
		if a.get("vigor"):
			t.append(("Hits harder the healthier its tree", ""))
	m = s.get("mine")
	if m:
		t.append(("Bursts for %s in %s m, slows %d%%" % (num(m["dmg"]), num(m["radius"]), round(m["slow"] * 100)), "hi"))
	if s.get("grows_tree"):
		t.append(("Grows into a birch", ""))
	return t


def chips(traits):
	return "".join('<li class="%s">%s</li>' % (cls, esc(txt)) for txt, cls in traits)


def struct_role(sid, s):
	if sid.startswith("heart_"):
		return "Heart"
	if s.get("trains") or sid == "morel_patch":
		return "Producer"
	if s.get("mine"):
		return "Trap"
	if s.get("attack"):
		return "Tower"
	if sid == "node":
		return "Network"
	if sid in ECONOMY:
		return "Economy"
	return "Support"


def pic(species, cls="pic", label=""):
	if not (IMG / f"{species}.webp").exists():
		return '<div class="%s none" role="img" aria-label="%s (no render yet)"></div>' % (cls, esc(label))
	return '<div class="%s" data-sp="%s" role="img" aria-label="%s"></div>' % (cls, esc(species), esc(label))


# --- who makes what --------------------------------------------------------------------------

def producers(f):
	"""(structure id, [unit ids]) for every structure of court f that trains or plants units."""
	fd = FACTIONS[f]
	out = []
	for sid in [fd["heart"]] + fd["build"]:
		trains = list(S[sid].get("trains", []))
		if sid == "morel_patch":
			trains.append("binder")
		if trains:
			out.append((sid, trains))
	return out


def court_units(f):
	fd = FACTIONS[f]
	seen = []
	for sid, trains in producers(f):
		for uid in trains:
			if uid not in seen:
				seen.append(uid)
	for uid in fd["starters"]:
		if uid not in seen:
			seen.append(uid)
	if fd["key"] == "veiled":
		for uid, u in U.items():
			if (u.get("thrall") or uid == "stalker") and uid not in seen:
				seen.append(uid)
	return seen


def made_at(f, uid):
	at = []
	for sid, trains in producers(f):
		if uid in trains:
			at.append(S[sid]["name"] + (" (planted)" if uid == "binder" else ""))
	hosts = [U[i]["name"] for i, u in U.items() if u.get("insect") and u.get("host") == uid]
	if hosts:
		at.append("Infecting a " + " or ".join(hosts))
	if uid == "zombie":
		at.append("Zombify, or infecting an enemy unit")
	if uid in FACTIONS[f]["starters"]:
		at.append("Starting army")
	return at


def unit_req(f, uid):
	for sid, trains in producers(f):
		if uid in trains and S[sid].get("req"):
			return S[sid]["req"]
	return ""


def node(species, name, sub="", href=""):
	inner = '%s<span><b>%s</b>%s</span>' % (pic(species, "thumb", name), esc(name), '<small>%s</small>' % sub if sub else "")
	return '<a class="node" href="#%s">%s</a>' % (esc(href), inner) if href else '<span class="node">%s</span>' % inner


def production(f):
	fd = FACTIONS[f]
	key = fd["key"]
	heart = S[fd["heart"]]
	rows = []
	builds = "".join(node(S[sid]["species"], S[sid]["name"], "needs " + esc(tech_name(S[sid]["req"])) if S[sid].get("req") else "",
		"s-" + sid) for sid in fd["build"])
	how = {"amanita": "Grows on your mycelium, linked to the Heart by cords",
		"morel": "Grows on your mycelium, linked to the Heart by cords",
		"veiled": "Each grows out of a thrall standing within %s m, which it consumes" % num(C["host_range"])}[key]
	rows.append('<div class="flow"><div class="src">%s<p>%s</p></div><span class="arrow" aria-hidden="true"></span><div class="dst">%s</div></div>'
		% (node(heart["species"], "Your territory", "builds"), esc(how), builds))
	for sid, trains in producers(f):
		s = S[sid]
		dst = "".join(node(U[u]["species"], U[u]["name"], cost_line(f, u), "u-" + u) for u in trains)
		req = '<p class="req">Needs %s</p>' % esc(tech_name(s["req"])) if s.get("req") else ""
		rows.append('<div class="flow"><div class="src">%s%s</div><span class="arrow" aria-hidden="true"></span><div class="dst">%s</div></div>'
			% (node(s["species"], s["name"], "trains", "s-" + sid), req, dst))
	if key == "veiled":
		ins = [(i, u) for i, u in U.items() if u.get("insect") and u.get("host")]
		dst = "".join(node(U[u["host"]]["species"], U[u["host"]]["name"], "from " + esc(u["name"]), "u-" + u["host"]) for i, u in ins)
		rows.append('<div class="flow"><div class="src">%s<p>Insects drawn in by the Heart, Stinkhorn Lures and Stench Lure turn on infection; any Choir hit infects an insect.</p></div><span class="arrow" aria-hidden="true"></span><div class="dst">%s</div></div>'
			% (node("i_ant", "Wild insects", "infected"), dst))
		rows.append('<div class="flow"><div class="src">%s<p>%d%% of Choir hits on another court\'s ordinary unit infect it; %d infecting hits turn it, alive. Zombify turns up to 4 at once.</p></div><span class="arrow" aria-hidden="true"></span><div class="dst">%s</div></div>'
			% (node("u_wartling", "Enemy units", "infected"), round(C["infect_chance"] * 100), round(1 / C["infect_dose"]),
				node(U["zombie"]["species"], U["zombie"]["name"], "converted", "u-zombie")))
	counts = {}
	for u in fd["starters"]:
		counts[u] = counts.get(u, 0) + 1
	st = "".join(node(U[u]["species"], U[u]["name"], "×%d" % n if n > 1 else "", "u-" + u) for u, n in counts.items())
	rows.append('<div class="flow start"><div class="src"><span class="node"><span><b>Starting army</b><small>on the field at the first second</small></span></span></div><span class="arrow" aria-hidden="true"></span><div class="dst">%s</div></div>' % st)
	return "".join(rows)


def cost_line(f, uid):
	u = U[uid]
	names = res_names(f)
	parts = ["%s %s" % (num(u["cost"][i]), names[i]) for i in range(2) if u["cost"][i]]
	if u.get("spores"):
		parts.append("%s %s" % (num(u["spores"]), names[2]))
	if u.get("train"):
		parts.append("%s s" % num(u["train"]))
	return esc(" · ".join(parts) if parts else "free")


# --- cards -----------------------------------------------------------------------------------

def structure_card(f, sid):
	s = S[sid]
	role = struct_role(sid, s)
	extra = "+ 1 thrall" if FACTIONS[f]["key"] == "veiled" and not sid.startswith("heart_") else None
	cost = cost_chips(f, s.get("cost", [0, 0]), 0, extra) if "cost" in s else '<span class="chip free">Starts in play</span>'
	stats = [stat("Health", num(s["hp"]))]
	if s.get("build"):
		stats.append(stat("Build", num(s["build"]), " s"))
	stats.append(stat("Mycelium", num(s.get("myc", 0)), " m", "radius of mycelium it feeds"))
	stats.append(stat("Footprint", num(s["radius"]), " m", "click and placement radius"))
	if s.get("attack"):
		stats += attack_stats(s["attack"])
	makes = s.get("trains", []) + (["binder"] if sid == "morel_patch" else [])
	links = ""
	if makes:
		links = '<p class="links"><span>Trains</span> %s</p>' % ", ".join('<a href="#u-%s">%s</a>' % (u, esc(U[u]["name"])) for u in makes)
	req = '<p class="links"><span>Needs</span> %s</p>' % esc(tech_name(s["req"])) if s.get("req") else ""
	latin = LATIN.get(s["species"], "")
	return f"""
      <article class="card" id="s-{esc(sid)}">
        <header>{pic(s["species"], "pic", s["name"])}<div class="head"><span class="role">{esc(role)}</span><h4>{esc(s["name"])}</h4>{f'<p class="latin">{esc(latin)}</p>' if latin else ''}<div class="cost">{cost}</div></div></header>
        <dl class="stats">{''.join(stats)}</dl>
        <ul class="traits">{chips(structure_traits(sid, s))}</ul>
        <p class="desc">{esc(s["desc"])}</p>{links}{req}
      </article>"""


def unit_card(f, uid):
	u = U[uid]
	stats = [stat("Health", num(u["hp"]))]
	if u.get("speed"):
		stats += attack_stats(u) + [stat("Speed", num(u["speed"]), " m/s")]
	else:
		stats.append(stat("Speed", "Rooted"))
	if u.get("train"):
		stats.append(stat("Train", num(u["train"]), " s"))
	if u.get("sight"):
		stats.append(stat("Sight", num(u["sight"]), " m"))
	where = made_at(f, uid) if f is not None else []
	req = unit_req(f, uid) if f is not None else ""
	links = '<p class="links"><span>Made by</span> %s</p>' % esc("; ".join(where)) if where else ""
	if req:
		links += '<p class="links"><span>Needs</span> %s</p>' % esc(tech_name(req))
	if f is None and u.get("host"):
		links += '<p class="links"><span>Becomes</span> <a href="#u-%s">%s</a></p>' % (u["host"], esc(U[u["host"]]["name"]))
	cost = cost_chips(f, u["cost"], u.get("spores", 0)) if f is not None else '<span class="chip free">Wild</span>'
	if f is not None and not any(u["cost"]) and not u.get("spores"):
		cost = '<span class="chip free">No cost</span>'
	attack = SHOT.get(u.get("shot", ""), "")
	role = ROLE.get(uid, "")
	latin = LATIN.get(u["species"], "")
	return f"""
      <article class="card" id="u-{esc(uid)}">
        <header>{pic(u["species"], "pic", u["name"])}<div class="head"><span class="role">{esc(role)}{' · ' + esc(attack) if attack and u.get('dmg') and attack.lower() not in role.lower() else ''}</span><h4>{esc(u["name"])}</h4>{f'<p class="latin">{esc(latin)}</p>' if latin else ''}<div class="cost">{cost}</div></div></header>
        <dl class="stats">{''.join(stats)}</dl>
        <ul class="traits">{chips(unit_traits(uid, u))}</ul>
        <p class="desc">{esc(u["desc"])}</p>{links}
      </article>"""


def table(f, uids):
	names = res_names(f)
	rows = []
	for uid in uids:
		u = U[uid]
		dps = u["dmg"] / u["cd"] if u.get("dmg") and u.get("cd") else 0
		c0, c1, sp = u["cost"][0], u["cost"][1], u.get("spores", 0)
		cost = " + ".join(x for x in [num(c0) if c0 else "", num(c1) if c1 else "", ("%s sp" % num(sp)) if sp else ""] if x) or "—"
		rows.append(
			f'<tr><th scope="row"><a href="#u-{uid}">{esc(u["name"])}</a></th>'
			f'<td data-v="{c0 + c1 + sp}">{cost}</td><td data-v="{u.get("train", 0)}">{num(u["train"]) if u.get("train") else "—"}</td>'
			f'<td data-v="{u["hp"]}">{num(u["hp"])}</td><td data-v="{u["dmg"]}">{num(u["dmg"])}</td>'
			f'<td data-v="{dps}">{num(dps) if dps else "—"}</td><td data-v="{u["range"]}">{num(u["range"]) if u["range"] else "—"}</td>'
			f'<td data-v="{u["speed"]}">{num(u["speed"]) if u["speed"] else "—"}</td></tr>')
	head = "".join(f'<th scope="col"><button type="button" data-col="{i + 1}">{h}</button></th>' for i, h in
		enumerate([f"Cost ({esc(names[0][:3])} + {esc(names[1][:3])})", "Train s", "Health", "Damage", "DPS", "Range m", "Speed m/s"]))
	return f"""<div class="tablewrap"><table class="cmp"><thead><tr><th scope="col"><button type="button" data-col="0">Unit</button></th>{head}</tr></thead><tbody>{''.join(rows)}</tbody></table></div>"""


def faction_section(f):
	fd = FACTIONS[f]
	key = fd["key"]
	start = "".join('<div><dt>%s</dt><dd>%s</dd></div>' % (esc(n), num(v)) for n, v in zip(fd["res_names"], fd["start_res"]))
	sids = [fd["heart"]] + fd["build"]
	uids = court_units(f)
	note = ""
	if key == "veiled":
		note = '<p class="note">The Choir pays no resources for thralls: it takes them from the forest and its enemies. Every Choir hit has a %d%% chance to infect another court\'s ordinary unit.</p>' % round(C["infect_chance"] * 100)
	if key == "amanita" and (IMG / "u_sailwing.webp").exists():
		note = '<div class="soon">%s<p><b>In development: Mycena Sailwing.</b> A flying skirmisher. The art is built; it has no stats or trainer yet.</p></div>' % pic("u_sailwing", "thumb", "Mycena Sailwing")
	return f"""
  <section class="court {key}" id="{key}" data-court="{key}">
    <header class="banner">
      <div class="title"><p class="eyebrow">{esc(fd["economy"])}</p><h2>{esc(fd["name"])}</h2><p class="motto">{esc(fd["motto"])}</p></div>
      <div class="purse"><p class="eyebrow">Resources · starting stock</p><dl>{start}</dl></div>
    </header>
    {note}
    <h3>What makes what</h3>
    <div class="flows">{production(f)}</div>
    <h3>Buildings <span>{len(sids)}</span></h3>
    <div class="grid">{''.join(structure_card(f, sid) for sid in sids)}
    </div>
    <h3>Units <span>{len(uids)}</span></h3>
    <div class="grid">{''.join(unit_card(f, uid) for uid in uids)}
    </div>
    <h3>Units side by side</h3>
    {table(f, uids)}
  </section>"""


def forest_section():
	ins = [uid for uid, u in U.items() if u.get("insect")]
	return f"""
  <section class="court forest" id="forest" data-court="forest">
    <header class="banner">
      <div class="title"><p class="eyebrow">neutral wildlife</p><h2>The forest's insects</h2><p class="motto">Nobody trains them. Nests breed them, and the Choir turns them.</p></div>
    </header>
    <div class="grid">{''.join(unit_card(None, uid) for uid in ins)}
    </div>
  </section>"""


def image_css():
	used = set()
	for s in S.values():
		used.add(s["species"])
	for u in U.values():
		used.add(u["species"])
	used.add("u_sailwing")
	rules = []
	for sp in sorted(used):
		p = IMG / f"{sp}.webp"
		if p.exists():
			rules.append('[data-sp="%s"]{background-image:url(data:image/webp;base64,%s)}' % (sp, base64.b64encode(p.read_bytes()).decode()))
	return "\n".join(rules)


def main():
	body = "".join(faction_section(f) for f in range(3)) + forest_section()
	page = TEMPLATE.replace("{{IMAGES}}", image_css()).replace("{{SECTIONS}}", body)
	page = page.replace("{{DATE}}", datetime.date.today().strftime("%d %B %Y").lstrip("0"))
	page = page.replace("{{POP}}", str(C["pop_cap"]))
	OUT.write_text(page, encoding="utf-8")
	print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


TEMPLATE = """<title>RHIZOMORPH Order of Battle</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,650&family=Public+Sans:wght@400;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
/* Layout: one ledger per court. A production strip (what makes what), then specimen cards with stat
   ledgers, then a sortable comparison table. Neutrals lean lichen-green; each court keeps its colour. */
:root {
  --bg: #eceee7;
  --surface: #f8f9f4;
  --sunk: #e2e5dc;
  --ink: #1a1c17;
  --muted: #5b6156;
  --rule: #cfd4c7;
  --court: #c63a2a;
  --hollow: #a77808;
  --choir: #6f45cf;
  --wild: #6b6a4a;
  --warn: #9a5b00;
  --plate: #15120e;
  --display: "Fraunces", "Iowan Old Style", Georgia, serif;
  --body: "Public Sans", "Segoe UI", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, Consolas, monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #11130f; --surface: #191c16; --sunk: #0d0f0b; --ink: #e6e9df; --muted: #9ba293; --rule: #2b3027;
    --court: #f0604c; --hollow: #e5b743; --choir: #ab88f7; --wild: #b4b28a; --warn: #e9a23b; color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --bg: #11130f; --surface: #191c16; --sunk: #0d0f0b; --ink: #e6e9df; --muted: #9ba293; --rule: #2b3027;
  --court: #f0604c; --hollow: #e5b743; --choir: #ab88f7; --wild: #b4b28a; --warn: #e9a23b; color-scheme: dark;
}
* { box-sizing: border-box; }
body {
  background: var(--bg); color: var(--ink); font: 15px/1.5 var(--body);
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
  padding-block: 28px 72px;
}
a { color: inherit; }
.wrap { max-width: 1280px; margin: 0 auto; display: grid; gap: 48px; }
.masthead { display: grid; gap: 14px; }
.eyebrow { margin: 0; font: 500 11px var(--mono); letter-spacing: 0.1em; text-transform: uppercase; color: var(--muted); }
h1 { font: 650 clamp(36px, 6vw, 64px)/0.98 var(--display); margin: 0; letter-spacing: -0.01em; text-wrap: balance; }
.masthead > p { margin: 0; max-width: 66ch; color: var(--muted); font-size: 16px; }
nav { display: flex; flex-wrap: wrap; gap: 8px; }
nav button {
  font: 600 13px var(--body); color: var(--ink); background: var(--surface); border: 1px solid var(--rule);
  border-radius: 999px; padding: 6px 14px 6px 12px; cursor: pointer; display: inline-flex; align-items: center; gap: 8px;
}
nav button::before { content: ""; width: 9px; height: 9px; border-radius: 50%; background: var(--c, var(--muted)); }
nav button[aria-pressed="true"] { background: var(--ink); color: var(--bg); border-color: var(--ink); }
button:focus-visible, a:focus-visible { outline: 2px solid var(--c, var(--ink)); outline-offset: 2px; }
.legend { display: flex; flex-wrap: wrap; gap: 6px 18px; font-size: 13px; color: var(--muted); }
.legend b { color: var(--ink); font-weight: 600; }

.amanita { --c: var(--court); } .morel { --c: var(--hollow); } .veiled { --c: var(--choir); } .forest { --c: var(--wild); }
nav [data-show="amanita"] { --c: var(--court); } nav [data-show="morel"] { --c: var(--hollow); }
nav [data-show="veiled"] { --c: var(--choir); } nav [data-show="forest"] { --c: var(--wild); }

.court { display: grid; gap: 20px; }
.banner { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: end; gap: 16px 32px; border-top: 4px solid var(--c); padding-top: 14px; }
.banner .title { display: grid; gap: 4px; min-width: 0; }
h2 { font: 650 clamp(30px, 4.4vw, 44px)/1 var(--display); margin: 0; color: var(--c); }
.motto { margin: 0; font: italic 500 18px var(--display); color: var(--muted); }
.purse { display: grid; gap: 6px; }
.purse dl { display: flex; gap: 6px; margin: 0; flex-wrap: wrap; }
.purse dl div { background: var(--surface); border: 1px solid var(--rule); padding: 6px 12px; display: grid; min-width: 92px; }
.purse dt { font: 500 11px var(--mono); text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); }
.purse dd { margin: 0; font: 500 20px var(--mono); font-variant-numeric: tabular-nums; }
h3 { font: 600 13px var(--mono); text-transform: uppercase; letter-spacing: 0.1em; margin: 12px 0 0; color: var(--muted); display: flex; gap: 10px; align-items: baseline; }
h3 span { color: var(--c); }
.note { margin: 0; max-width: 72ch; color: var(--muted); }
.soon { display: flex; gap: 12px; align-items: center; background: var(--surface); border: 1px dashed var(--rule); padding: 8px 12px; max-width: 640px; }
.soon p { margin: 0; font-size: 14px; color: var(--muted); }
.soon b { color: var(--ink); }

/* what makes what */
.flows { display: grid; gap: 8px; }
.flow { display: grid; grid-template-columns: minmax(0, 300px) 28px minmax(0, 1fr); gap: 10px; align-items: center; background: var(--surface); border: 1px solid var(--rule); padding: 10px 12px; }
.flow .src { display: grid; gap: 4px; min-width: 0; }
.flow .src p { margin: 0; font-size: 13px; color: var(--muted); }
.flow .src .req { color: var(--warn); font: 500 12px var(--mono); }
.arrow { height: 2px; background: var(--c); position: relative; }
.arrow::after { content: ""; position: absolute; right: -1px; top: -4px; border: 5px solid transparent; border-left: 7px solid var(--c); border-right: 0; }
.dst { display: flex; flex-wrap: wrap; gap: 6px; min-width: 0; }
.node { display: inline-flex; align-items: center; gap: 8px; text-decoration: none; padding: 3px 10px 3px 3px; border-radius: 6px; background: var(--bg); border: 1px solid transparent; min-width: 0; }
a.node:hover { border-color: var(--c); }
.node span { display: grid; line-height: 1.2; min-width: 0; }
.node b { font-weight: 600; font-size: 14px; }
.node small { font: 12px var(--mono); color: var(--muted); }
.flow .src .node { background: transparent; padding-left: 0; }
.thumb { width: 40px; height: 40px; flex: none; border-radius: 4px; background: var(--plate) center / cover no-repeat; }
.flow.start { background: transparent; border-style: dashed; }

/* cards */
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 330px), 1fr)); gap: 14px; }
.card { background: var(--surface); border: 1px solid var(--rule); padding: 12px; display: grid; gap: 10px; align-content: start; scroll-margin-top: 16px; }
.card:target { outline: 2px solid var(--c); }
.card header { display: grid; grid-template-columns: 116px minmax(0, 1fr); gap: 12px; }
.pic { width: 100%; max-width: 100%; aspect-ratio: 1; background: var(--plate) center / cover no-repeat; border-radius: 4px; }
.pic.none, .thumb.none { background: repeating-linear-gradient(45deg, var(--sunk) 0 6px, var(--surface) 6px 12px); }
.head { display: grid; gap: 3px; align-content: start; min-width: 0; }
.role { font: 500 11px var(--mono); text-transform: uppercase; letter-spacing: 0.08em; color: var(--c); }
h4 { margin: 0; font: 650 21px/1.1 var(--display); text-wrap: balance; }
.latin { margin: 0; font: italic 14px var(--display); color: var(--muted); }
.cost { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 6px; }
.chip { font: 12px var(--mono); padding: 2px 7px; border-radius: 3px; background: var(--sunk); white-space: nowrap; }
.chip b { font-weight: 500; font-variant-numeric: tabular-nums; }
.chip.r0 { box-shadow: inset 3px 0 var(--c); }
.chip.r1 { box-shadow: inset 3px 0 var(--muted); }
.chip.r2 { box-shadow: inset 3px 0 var(--warn); }
.chip.rx, .chip.free { color: var(--muted); }
.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 0 10px; margin: 0; }
.stats div { border-top: 1px solid var(--rule); padding: 5px 0 3px; display: grid; min-width: 0; }
.stats dt { font: 10px var(--mono); text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); }
.stats dd { margin: 0; font: 500 16px var(--mono); font-variant-numeric: tabular-nums; }
.stats small { font-size: 11px; color: var(--muted); }
.traits { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 4px; }
.traits:empty { display: none; }
.traits li { font-size: 12px; padding: 2px 8px; border-radius: 999px; border: 1px solid var(--rule); }
.traits li.hi { border-color: var(--c); color: var(--c); }
.traits li.warn { border-color: var(--warn); color: var(--warn); }
.desc { margin: 0; font-size: 14px; color: var(--muted); max-width: 65ch; }
.links { margin: 0; font-size: 13px; }
.links span { font: 500 11px var(--mono); text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); margin-right: 6px; }
.links a { text-decoration-color: var(--c); text-underline-offset: 2px; }

/* comparison */
.tablewrap { overflow-x: auto; border: 1px solid var(--rule); background: var(--surface); }
table.cmp { border-collapse: collapse; width: 100%; min-width: 720px; font-size: 14px; }
.cmp th, .cmp td { padding: 6px 10px; text-align: right; border-bottom: 1px solid var(--rule); font-variant-numeric: tabular-nums; }
.cmp td { font-family: var(--mono); font-size: 13px; }
.cmp th:first-child { text-align: left; font-weight: 600; }
.cmp tbody tr:last-child > * { border-bottom: 0; }
.cmp thead th { background: var(--sunk); }
.cmp thead button { font: 500 11px var(--mono); text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted); background: none; border: 0; padding: 0; cursor: pointer; }
.cmp thead button[aria-sort] { color: var(--c); }
.cmp thead button[aria-sort="descending"]::after { content: " ↓"; }
.cmp thead button[aria-sort="ascending"]::after { content: " ↑"; }
.cmp tbody a { text-decoration: none; }
.cmp tbody a:hover { text-decoration: underline; text-decoration-color: var(--c); }

footer { color: var(--muted); font-size: 13px; border-top: 1px solid var(--rule); padding-top: 16px; }
footer code { font: 12px var(--mono); }
@media (max-width: 640px) {
  .flow { grid-template-columns: minmax(0, 1fr); }
  .arrow { width: 2px; height: 14px; margin-left: 20px; }
  .arrow::after { right: -4px; top: auto; bottom: -6px; border: 5px solid transparent; border-top: 7px solid var(--c); border-bottom: 0; }
  .card header { grid-template-columns: 92px minmax(0, 1fr); }
  .stats { grid-template-columns: repeat(3, minmax(0, 1fr)); }
}
@media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
{{IMAGES}}
</style>

<div class="wrap">
  <div class="masthead">
    <p class="eyebrow">RHIZOMORPH · from data.gd · {{DATE}}</p>
    <h1>Order of Battle</h1>
    <p>Every building and unit of the three courts: what makes what, what each one costs, and how it fights. Numbers come straight from the game's data; images are in-engine renders.</p>
    <nav aria-label="Show">
      <button type="button" data-show="all" aria-pressed="true">All courts</button>
      <button type="button" data-show="amanita" aria-pressed="false">Amanita Court</button>
      <button type="button" data-show="morel" aria-pressed="false">Morel Hollow</button>
      <button type="button" data-show="veiled" aria-pressed="false">Veiled Choir</button>
      <button type="button" data-show="forest" aria-pressed="false">Forest insects</button>
    </nav>
    <div class="legend"><span><b>DPS</b> damage ÷ interval, before armour and poison</span><span><b>Mycelium</b> radius of ground the building feeds</span><span><b>Spores</b> the shared third resource</span><span><b>Population cap</b> {{POP}}</span></div>
  </div>
{{SECTIONS}}
  <footer>Generated by <code>tools/catalog/build_roster.py</code> from <code>scripts/data.gd</code> (via <code>tools/catalog/dump_data.gd</code>) and the catalog's renders. Costs are in each court's own resources, in the order shown in its banner.</footer>
</div>

<script>
const buttons = document.querySelectorAll("nav button");
const courts = ["amanita", "morel", "veiled", "forest"];
function show(which) {
  buttons.forEach(b => b.setAttribute("aria-pressed", String(b.dataset.show === which)));
  document.querySelectorAll(".court").forEach(s => { s.hidden = which !== "all" && s.dataset.court !== which; });
}
buttons.forEach(b => b.addEventListener("click", () => {
  show(b.dataset.show);
  history.replaceState(null, "", b.dataset.show === "all" ? location.pathname + location.search : "#" + b.dataset.show);
}));
function route() {
  const h = location.hash.slice(1);
  if (courts.includes(h)) { show(h); return; }
  const el = h && document.getElementById(h);
  if (el) { show("all"); el.scrollIntoView({ block: "start" }); }
}
route();
window.addEventListener("hashchange", route);
document.querySelectorAll("table.cmp").forEach(t => {
  t.querySelectorAll("thead button").forEach(btn => btn.addEventListener("click", () => {
    const col = +btn.dataset.col;
    const desc = btn.getAttribute("aria-sort") !== "descending";
    t.querySelectorAll("thead button").forEach(o => o.removeAttribute("aria-sort"));
    btn.setAttribute("aria-sort", desc ? "descending" : "ascending");
    const rows = [...t.tBodies[0].rows];
    rows.sort((a, b) => {
      if (col === 0) return (desc ? -1 : 1) * a.cells[0].textContent.localeCompare(b.cells[0].textContent);
      const va = +a.cells[col].dataset.v, vb = +b.cells[col].dataset.v;
      return desc ? vb - va : va - vb;
    });
    rows.forEach(r => t.tBodies[0].appendChild(r));
  }));
});
</script>
"""

if __name__ == "__main__":
	main()
