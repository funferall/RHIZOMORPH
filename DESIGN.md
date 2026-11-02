# RHIZOMORPH — Design

The game is a real-time strategy game set on a forest floor. Three fungal courts fight over
one forest. Each court feeds in a different way, so each one wants a different forest.
That conflict is the game.

This document is the source of truth for the overhaul. Numbers are **first-pass values**.
They exist to be tuned in bot games and playtests, and once they are in code they belong in
`scripts/data.gd`. ROADMAP.md tracks progress; this file says what we are building and why.

---

## 1. Pillars

1. **How you eat is how you play.** Each court has its own income, its own key map
   feature, and its own reason to fight. None of them shares a build order with another.
2. **The forest is alive.** Trees grow sick and fall. Logs rot. Insects breed. Rain and wind
   change the board mid-match. The map at minute 15 should not look like the map at minute 1.
3. **Networks are the base.** Cords, hubs, and supply routes are what you defend and what
   you raid. Cutting a cord should always be a real threat.
4. **True to the biology.** Every mechanic has a real fungal behaviour behind it. When
   biology and fun conflict, we bend the numbers, not the story.

## 2. The conflict triangle

| | wants | key map feature | natural enemy of |
|---|---|---|---|
| **Amanita Court** (mycorrhizal symbiont) | trees **alive** and thriving | living trees | Hollow (which kills trees), insects (which eat them) |
| **Morel Hollow** (saprotroph rotters) | things **dead**: wood, litter, corpses | logs, snags, carrion | Court (which keeps trees standing) |
| **Veiled Choir** (parasite / insect puppeteer) | **insects** to be many, and hosts to infect | anthills, beetle logs, carrion flies | Hollow (which eats the logs beetles breed in), Court (which kills insects as pests) |

These conflicts are built into the economies:

- Hollow kills a tree with Honey Rot. The Court loses a sugar source and the Hollow gains a log.
- Hollow digests a log. That log stops breeding beetles, so the Choir loses hosts.
- The Court culls insects to protect its trees, which denies the Choir its hosts.
- The Choir's bark-beetle thralls bore into trees. That hurts the Court and turns trees into
  food for the Hollow.

The two courts that are not currently winning both have a reason to hit the one that is.

---

## 3. Shared core

These systems are the same for every court.

- **Heart (Sclerotium).** Losing it is losing the match. It researches techs and gives a
  small base income in the court's main resource.
- **Mycelium.** The GPU sim is unchanged. It spreads from structures and is the court's
  territory. Units fight better on their own mycelium (see Bootlaces-style techs).
- **Spores.** Every court spends spores on **spore actions**, which are targeted abilities.
  Each court earns spores in its own way (see below).
- **Population.** The cap is 100 (raised from 40 on 2026-11-01). For the Choir, the population is the number of thralls it has.
- **Selection, orders, combat, poison, slow, splash, arcs.** These are unchanged.

What changes is income, building rules, vision, and what each court is allowed to build.

### Resources per court

The engine keeps three resource slots per court: `res[0]`, `res[1]`, and `res[2]`. The HUD
labels them by court:

| slot | Court | Hollow | Choir |
|---|---|---|---|
| 0 (bulk) | **Minerals** | **Cellulose** | **Biomass** |
| 1 (elite) | **Sugar** | **Nitrogen** | **Hosts**, shown as the thrall count (not spent) |
| 2 | Spores | Spores | Spores |

---

## 4. The courts

### 4.1 Amanita Court — the Wood Wide Web

*"Feed the grove and the grove will feed you."* This court is a builder and turtle. It has
few strong anchors and a network that links trees, and its economy sits wherever its trees are.

**Economy loop**

- Mycelium digests the soil for **Minerals**. This is today's nutrient sim, renamed.
- A **Mantle** on a tree's root zone pays minerals to the tree, at 0.4 per second per
  mantle. The tree pays back **Sugar**.
- Sugar out = `tree.size × tree.vigor × partner_mult × SUGAR_SCALE`, split between mantles.
  - If mineral payments stop because the court is broke, a mantle still yields 40%.
- **Tree vigor** runs from 0 to 1 and drifts toward 0.55 with no partner.
  - Each fed mantle pushes the target vigor up by 0.15, up to 1.0.
  - Vigor moves about 0.01 per second toward its target, so it takes minutes to build.
- **Partner trees.** Amanita favours birch, pine, and spruce (×1.3). Oak gives ×1.0, and
  hemlock and beech give ×0.8. Tree species then decides where the court settles.
- **Wood Wide Web.** When two or more mantled trees are connected through your cord network,
  their sugar is pooled, and each linked tree adds +10% to the pool (up to +40%).
  - **Mother Tree:** an old-growth tree linked to 3 or more others. It gives +25% sugar, and
    its vigor heals the linked trees.
- **Spores** come from the fruiting season. Each mantle on a tree with vigor ≥ 0.7 adds
  +0.12 spores per second. The Heart adds 0.5. There are no Lanterns.

**Vision (fog of war)**

The court sees its network, its units, and every tree it is mantled on, including that tree's
full root zone.

It also sees **the trees adjacent to those trees, one hop out in the tree graph**: each
neighbour tree and its root zone. The tree graph is built when the map loads, by linking each
tree to its neighbours within 30 m, up to 4 per tree. The roots talk; the court hears what is
happening one tree over.

**Structures**

| structure | role | notes |
|---|---|---|
| Heart | research, +2 minerals/s, +0.5 spores/s | hp 2400 |
| Rhizomorph Node | network hub | shared |
| Hartig Mantle | sugar from a tree | root zone only, up to 3 per tree |
| Agaric Ring | trains Wartling and Muscarine Spitter | |
| Root Snare | defence tower built *on a tree's root zone* | Its roots grip and slow enemies. Damage scales with that tree's vigor (8 to 18 dps). It replaces the Clathrus Cage, which moves to the Choir. |
| Death Cap Grove | trains the Destroying Angel | needs Phalloides |

**Units:** Wartling (poison melee), Muscarine Spitter (poison ranged), and Destroying Angel
(elite assassin, strong against cords). Stats are unchanged.

- **Destroying Angel cloak (2026-11-01).** Enemies cannot see or target an Angel unless one of
  their units or finished structures is within 5 m, or for 2 s after it strikes (1.5 s after it is
  hurt). Splash still lands on it. Its owner sees it as a blue shimmer while it is unseen.
- **Cep Bulwark (2026-11-01).** *Boletus edulis*, trained at the Cortina Thicket (40/30, hp 300,
  bash 14 per 1.1 s, speed 4). **Brace (F):** it roots for 1 s, then cannot move or attack, but
  every hostile *direct* shot that crosses the 3 m circle around it bends into its cap for 25%
  damage, including shots aimed past it. Lobbed shots fly over. A move order uproots it (0.85 s)
  and then walks. The AI braces when 2+ enemy shooters are within 13 m and nothing bites it.

**Spore actions:** Muscimol Haze, Fairy Ring, Death Cap Bloom. These are unchanged.

**Pests.** Insects inside a mantled root zone drain that tree's vigor. The Court has a
reason to kill bugs, and that denies the Choir.

**What it fears:** Armillaria Honey Rot on its trees, cords cut between trees (which breaks the
Web bonus), and the Choir's beetle thralls.

### 4.2 Morel Hollow — everything dead is food

*"Every fight is a feast."* This court plays attrition and expansion. Its income grows from
fighting, but its food runs out, so it has to keep moving.

**Economy loop**

- **Deposits** are finite stocks on the map. Each one has `stock` and `kind`:

  | deposit | Cellulose | Nitrogen | where it comes from |
  |---|---|---|---|
  | Fallen log | 600–1200 | 0 | map start, trees that fall in storms |
  | Snag (standing dead tree) | 500 | 0 | a tree whose vigor reaches 0 |
  | Branch fall | 120 | 0 | windstorms |
  | Leaf litter pile | 200 | 20 | map start, autumn leaf fall |
  | **Corpse** | 0 | 15 (unit), 40 (elite) | every unit that dies, from any court, including neutral insects (5) |
  | **Rubble** (dead structure) | 60 | 10 | every structure that dies |

- A **Rot Bracket** (Ganoderma) on a log or snag digests it. It produces 1.8 cellulose per
  second until the deposit is gone.
- Corpses are picked up by any Hollow mycelium of density above 0.3, at 1.5 nitrogen per
  second per corpse. Corpses rot away in 60 s, so the Hollow has to have mycelium under the
  battlefield to cash in.
  - The **Inkcap Bed** structure pulls corpses within 10 m into itself, and they don't rot away.
- **Ordinary soil** still gives a trickle of cellulose through mycelium, at **40% of the
  Court's rate**. The Hollow is never broke, but it is slow without deposits.
- **Exhausted deposits become Humus.** A humus patch is a permanent +30% mycelium digestion
  bonus in its area for **whoever holds it**, so cleared ground stays worth fighting over.
- **Honey Rot** (Armillaria) is a structure placed in a living tree's root zone.
  - It drains that tree's vigor by 0.02 per second, and faster if the tree is weak.
  - When vigor hits 0, the tree becomes a Snag, and the next storm fells it into a Log.
  - Any court can kill the Honey Rot; the Court has every reason to.
- **Spores** come from the Heart (+0.5), Earthstars, and digestion: +0.02 spores per unit of
  deposit consumed per second.

**Vision:** the court sees its mycelium, structures, and units, plus every deposit and corpse
it is digesting.

**Structures**

| structure | role | notes |
|---|---|---|
| Heart | research, +2 cellulose/s, +0.5 spores/s | hp 2700 |
| Rhizomorph Node | network hub | shared |
| Rot Bracket | +1.65 cellulose/s (and 0.165 nitrogen/s) from a log, snag, or branch deposit | placed on the deposit |
| Oyster Shelf | +0.4 nitrogen/s from nematodes in the wood | placed on a log, snag or branch |
| Inkcap Bed | gathers and preserves corpses within 10 m, digests litter | |
| Honey Rot | kills a living tree | root zone, needs Armillaria Bootlaces |
| Morel Patch | trains Bruiser, Slinger, and Puffball Bomber | |
| Earthstar | splash tower | moves from the old Morel roster |
| Bird's Nest | long-range artillery tower | moves from the Choir |
| Pilobolus Bed | trains the Pilobolus Sniper | Pilobolus is a dung fungus, so it belongs here. Needs Pilobolus Lineage. |

**Units:** Morel Bruiser (regen tank), Elf-Cup Slinger (ranged), Puffball Bomber (arcing splash,
moved from the Choir), and Pilobolus Sniper (elite; costs nitrogen).

**Coral Binder:** A connected Morel Patch can plant a stationary Binder on owned
mycelium. Click the root, then a direction and endpoint; cancel before the second
click without paying. Its spiked wall grows at 0.25 m/s up to 12 m, stops before
terrain obstacles, slows enemy ground units crossing the grown portion by 70%,
and deals 5 retaliation damage to direct melee attackers. All segments share
the root's health; destroying it removes the wall. Current cost 65 cellulose and
12 nitrogen and 180 health are initial tuning values.

**Spore actions:** Ascus Volley, Wildfire, Giant Puffball (moved from the Choir).

- **Wildfire** kills everything in the area and leaves Ash, where morels fruit.
- In Ash, the Hollow's mycelium grows ×2 and digests ×1.5 for 60 s.

**Nitrogen bootstrap (added 2026-10-30, after playtesting showed the Hollow could not raise an army).**
Wood is very poor in nitrogen, and real wood-rot fungi have ways round that. The Hollow now has all of these:
- **Oyster Shelf** (*Pleurotus*): built on a log or snag. It traps and digests the nematodes living in the
  wood, for +0.4 nitrogen/s while the wood lasts. The income rides the cords like a bracket's.
- **Rot carries nitrogen.** Rot Brackets yield 1 nitrogen for every 10 cellulose (in real logs,
  nitrogen-fixing bacteria build it up).
- **The Bruiser costs no nitrogen,** so the Hollow can always field a basic army. Nitrogen buys
  quality: Slingers, Bombers, Snipers and the lineages.
- **Reclaiming its own dead:** a Hollow unit dying on Hollow mycelium returns half its nitrogen cost at once.
- **Hunting insects:** an insect the Hollow kills is eaten where it falls, for +4 nitrogen at once. It
  leaves no corpse, so the Choir can't raise it. The Hollow now competes with the Choir for insects.
- **Starting nitrogen** is 120 (was 60).

**What it fears:** running out of food. A Hollow that turtles starves. It also fears a Court
that keeps every tree healthy.

### 4.3 Veiled Choir — hosts, not buildings

*"The forest walks for us."* This court's army is its base. Its units are mobile, swarming,
and short-lived, it has almost no structures, and it must keep hunting or it collapses.

**Economy loop**

- **Neutral insects** live in the forest and breed at nests (§5). They are the Choir's real
  resource.
- **Infection.** An insect rises as a thrall of matching type when the Choir kills it, or
  when it dies within 8 m of a Choir unit or structure. An enemy non-elite unit rises when a
  Stalker kills it (60%), or 20% of the time when any Choir body does. Anything that dies inside a
  Pandemic rises. Insects sitting at a Lure (or the Heart) fall sick and rise on their own:

  | dead body | becomes |
  |---|---|
  | ant | Ant Thrall |
  | beetle | Beetle Thrall |
  | fly | Fly Thrall |
  | springtail | (too small: gives +4 spores instead) |
  | enemy unit | a Cordyceps Thrall, which is today's zombie |

- **Thralls decay.** They lose 0.42% of their max hp per second, roughly a 4 minute life.
  On the Choir's own mycelium they lose half that. The Choir must keep converting.
- **Sporulate (the summit command).** You order a thrall to a high point: a tree trunk,
  rock, or stump.
  - Once there, it bursts after 3 s.
  - The burst gives **+20 spores and +15 biomass**, deals 40 damage in 4 m, and reveals a
    16 m radius for 20 s.
  - It also **infects insects in 6 m**, which rise as new thralls.
  - This is how the Choir turns bodies into currency.
- **Biomass** pays for structures.
  - It comes from sporulation, from the Heart (+1.5 per second), and from Lures digesting
    the insects they attract (+0.4 per insect per pass).
- **Structures are grown from hosts.** Placing a Choir structure needs a thrall within 6 m of
  the spot. That thrall dies, and the structure grows out of it.
  - This costs biomass + one thrall. There are **no cords**: every Choir structure stands
    alone and never starves. There is nothing to cut, but every structure is paid for in bodies.
- **Spores** are the Choir's main currency. They pay for spore actions, for the Stalker
  elite, and for most of each tech (techs cost a little biomass plus 60 to 150 spores). The
  cap is higher: 200.

**Vision:** units (Fly Thralls see 18 m), structures, and sporulation reveals. The Choir does
**not** see through its mycelium, which is thin, endophytic, and only around its structures.

**Structures**

| structure | role | notes |
|---|---|---|
| Heart | research, +1.8 biomass/s, +1.0 spores/s | hp 2300. It spits at intruders (it has no network to hide behind), and slowly infects insects that wander within 12 m. |
| Stinkhorn Lure (Veiled Lady) | pulls insects within 18 m toward it and infects arrivals over 6 s | Breeds flies. +0.4 biomass/s, +0.4 spores/s. |
| Clathrus Cage | slow tower | moved from the Court |
| Cordyceps Spire | converts **spores into Stalkers**; research access | needs Hypocreales |
| Brood Chamber | heals thralls nearby and pauses their decay | late-game turtle tool |

**Units**

| unit | source | role |
|---|---|---|
| Ant Thrall | ants | fast, cheap melee; swarms; good cord cutter |
| Beetle Thrall | beetles | armoured tank (hp 180, 30% armour vs ranged). **Bores**: attacking a tree drains vigor. |
| Fly Thrall | flies | flies over water and cliffs; fragile scout and harasser; sight 18 |
| Stag Thrall | stag beetles | the heaviest thrall: hp 220, 40% armour, slow and crushing |
| Cordyceps Thrall | enemy units | the old zombie |
| Cordyceps Stalker | made from spores at the Spire | Elite ranged infector: its kills always rise. Costs 85 spores. |

**Spore actions**

- **Stench Lure:** drags enemies and insects to a point.
- **Zombify:** moves here from the Hollow. Up to 4 enemy non-elite units become thralls.
- **Pandemic** (tier 3): for 15 s, *anything* that dies in a 10 m area rises as a Choir thrall.

**What it fears:** an insect famine. If the Court culls the bugs and the Hollow eats the logs,
the Choir's income dries up. It also fears being caught in the open, since it has no towers
spread around the map.

---

## 5. Insects (neutral wildlife)

Insects are bred by **nests**: each one adds an insect every so often while it is below its cap.
Nests follow the state of the forest, so changing the forest changes which insects live in it:

| insect | bred by | hp | behaviour | effect on the world |
|---|---|---|---|---|
| Wood Ant (*Formica*) | anthills (map features, never consumed); cap 6, every 36 s | 25 | forages in columns; fast | carries off corpses within 10 m, which takes nitrogen from the Hollow |
| Bark Beetle (*Ips*) | **snags** (cap 3, every 30 s) and **weakened trees** (vigor below 0.4: cap 2, every 40 s), because stressed trees give off the scent bark beetles track | 60 | slow and armoured | bores into nearby living trees for −0.004 vigor/s each, finishing off weak trees |
| Stag Beetle (*Lucanus cervus*) | **rotting logs** (its larvae live in deadwood for years); cap 1, every 75 s | 110 | very slow, heavily armoured | none, but it becomes the Choir's heaviest thrall |
| Carrion Fly | corpses (half of them breed one), Stinkhorn Lures | 15 | fast, erratic | harmless; Choir food |
| Springtail swarm | leaf litter; cap 3, every 34 s | 30 | grazes mycelium | −0.15/s to whichever court's ground it sits on |
| Agrilus borer | only summoned by the Choir's Agrilus Swarm | 14 | clings to its tree, lives 45 s | −0.007 vigor/s each, scaled by the tree's susceptibility |

**Global cap:** 60 insects. Digesting a log removes its stag-beetle nest. A dead tree becomes a
bark-beetle nest. Phase 4 adds weather: rain halves breeding and dry spells raise it by half.

**The Agrilus cascade.** The jewel-beetle genus *Agrilus* has a specialist for each broadleaf:
the two-lined chestnut borer on oak, the bronze birch borer on birch, and the emerald ash borer on
ash. Conifers such as hemlock have none, so they resist (×0.4).

The Choir's tier-3 **Agrilus Swarm** drops 7 borers on a tree. In about 15–20 s they drag a healthy
broadleaf below 0.4 vigor, and the bark beetles then home in. A tree that dies stands as a snag,
which breeds bark beetles (more hosts for the Choir) and is wood for the Hollow's brackets. In
Phase 4 the next storm fells the snag into a log, which then breeds stag beetles.

The counterplay is to kill the borers (14 hp each); the Court's units cull pests on trees it feeds.
The Court can also lean on hemlock and conifers. (Ash, *Fraxinus*, is arbuscular-mycorrhizal, not
ectomycorrhizal. When ash trees arrive with the forest map, the Court should get little or no sugar
from them, which makes ash a tree for the other courts to fight over.)

## 6. Fog of war (built: `scripts/fog.gd`)

- **Vision grid.** There is one vision grid per court, at 1 cell per m (192 × 144), and it is
  rebuilt every 0.25 s.
- **Cell states:** *unexplored*, *explored* and *visible*.
  - Unexplored ground is near black.
  - Explored ground is dim and grey: you keep the lie of the land but lose the live faction
    tint, so the fog can't be used to watch enemy mycelium spread.
  - Visible ground is shown as normal.
- **What each court sees by:**
  - **All courts:** their units (10 m; elites 12 m; Fly Thralls 18 m) and their structures
    (their `myc` radius + 2 m).
  - **Court and Hollow:** also every cell where their own mycelium density is above 0.25.
  - **Amanita Court:** also **through the roots**. Every tree it feeds lights its whole root
    zone, and so does each neighbour of that tree on the root graph (one hop; two hops with
    Root Signalling).
  - **Veiled Choir:** **only through its parasitised hosts** (its thralls and Stalkers), its
    structures, and sporulation. Its mycelium gives no sight. A sporulating thrall reveals 16 m
    around its summit for 20 s (40 s with Summit Disease).
- **Rendering.**
  - The terrain, moss and water shaders and the minimap all sample one fog texture
    (`fog.gdshaderinc`).
  - Enemy units and insects outside sight are hidden.
  - An enemy structure appears once spotted and then stays on the map. (It is currently shown
    live, not frozen as a ghost.)
  - Enemy decor sprouts hide in the fog.
  - You can't pick what you can't see, and the player can only cast spore actions on explored
    ground.
  - `--nofog` turns it off for debugging.
- **AI.** The AI still sees everything. Making it scout and respect fog is Phase 5.

## 7. Cord throughput (built: `game.gd _route_flows`)

Before this, a structure was either connected or cut off. Throughput makes the shape of the
network matter.

- **What is routed.** A mantle's sugar and a Rot Bracket's cellulose flow to the Heart along
  the **shortest path (fewest hops)** through live cords. Soil digestion, Heart income and spores
  are not routed.
- **Distance loss.** Each hop loses 3% (`HOP_LOSS`), so long supply lines leak.
- **Capacity.** Each cord carries **4/s** (`CORD_CAP`), or 8/s with either Bootlaces tech.
  Flow above capacity is lost, and every source routed through a bottleneck is scaled down by
  that cord's overload.
- **Visible load.** Busier cords carry more, faster beads. Over capacity, the beads turn hot
  red and pulse, marking the artery worth hitting. In bot games the Hollow's bracket chains run
  up to about 3× capacity.
- **Not built yet:**
  - load-weighted routing, where new flow takes a spare route if one exists;
  - cord thickness by load;
  - a tooltip on a selected cord.
- **Scope.** The Choir has no cords and ignores this system.

---

## 8. The forest map (first 2× version built)

**Built (2026-10-30):**
- A 192 × 144 m board: the GPU sim at 3 cells/m (576 × 432), heights at 3 vertices/m, and
  terrain generated feature by feature (`board.gd _stamp`). Startup is about 8 s.
- 16 trees:
  - a central old-growth stand (Old Oak, Great Hemlock, Elder Oak);
  - a birch stand by the Court's start;
  - an oak, a birch and a hemlock by each other start;
  - scattered trees between.
- A stream down the west side (`STREAM`, slows units, but flies cross freely), with a log bridge
  and three stepping stones.
- 8 logs, including a windfall of three by the Hollow's start; 11 litter piles; 6 anthills;
  13 rocks; 8 puddles.
- Camera zoom-out raised to 170 m; root-zone rings support up to 24 trees.

**Still to build:** the burn-scar clearing, the rocky outcrop's range bonus,
cords crossing the stream only at crossings, and the minimap is still the original size.

The original plan:

- **Size.** The board grows from 96 × 72 m to **192 × 144 m**, four times the area.
  - The GPU sim drops to 3 cells per m (576 × 432).
  - The coarse grid is 192 × 144 at 1 cell per m.
  - A **minimap** becomes mandatory.
- **Zones.** These are hand-authored for the first map and generated later.
  - **Old-growth stand** (centre): 3–4 huge oaks and hemlocks. These are Mother Tree
    candidates, and the richest sugar.
  - **Birch and pine stand:** many small trees, Amanita's favourite partners.
  - **Windfall:** a log jam of 5–6 big fallen logs. A Hollow paradise and a beetle nursery.
  - **Burn scar clearing:** few trees, ash soil (permanent morel bonus), anthills.
  - **Stream:** crosses the map. It slows units ×0.5, and there are 2–3 crossings: fallen-log
    bridges and stepping stones. Cords can cross only at crossings, so crossings are chokepoints.
  - **Rocky outcrop:** high ground. Ranged units get +15% range, and it is a summit point
    for the Choir.
  - ~~Fern understory~~ **Dropped (2026-10-30).** Cover that hides your own units fights the
    camera, not the enemy. Fog of war already supplies the hidden-information game.
  - **Anthills:** 3–4, spread so that every court has one nearby.
- **Start positions.** There are three starts. Each one has a fair *mix* of nearby trees,
  deadwood, and an anthill, so any court can play from any start.

## 9. The living world

**Built (`scripts/weather.gd`, `forest.gd fell / add_branch / leaf_fall`):**
- **Weather.** A rain, dry spell or windstorm comes every 2–4 min and is announced 15 s ahead,
  with a countdown in the top-right HUD.
  - **Rain:** mycelium grows ×1.5, building and training run ×1.25, insects breed ×0.5. Rain
    falls around the camera and the sun dims.
  - **Dry spell:** insects breed ×1.5.
  - **Windstorm:**
    - every snag falls into a long log (+600 cellulose, and it becomes a stag-beetle nest);
    - a tree below 0.3 vigor has a 25% chance to die and fall with them;
    - gusts drop small branch deposits that Rot Brackets can eat.
  - **Testing:** `--weather=wind|rain|dry` brings that weather in at 20 s; `--snag=N` kills
    tree N at the start.
- **Leaf fall.** Every 8 min the litter piles refill by 30%, and new piles (each a springtail
  nest) gather under the big trees.
- **Not built yet:** saplings, puddles swelling in rain, Wildfire spreading in a dry spell, and
  units sheltering from rain.

The original plan:

- **Tree lifecycle:** healthy, then weak (vigor below 0.3), then snag (vigor 0), then log
  after the next windstorm.
- **Saplings.**
  - Sunlit gaps (where a tree fell, or the burn scar) sprout a sapling every few minutes.
  - A sapling grows into a small tree over 6 minutes, or 3 minutes if it is mantled. The
    Court plants its own forest.
- **Weather.** A cycle is drawn every 2–4 minutes and announced 15 s ahead:
  - **Rain** (45 s): mycelium growth ×1.5, build and train speed ×1.25 (a fruiting flush),
    insects spawn ×0.5, fire impossible. It is visual and audible: rain particles and the
    puddles swell.
  - **Dry spell** (60 s): Wildfire spreads to adjacent ash-free cells, and insects spawn ×1.5.
  - **Windstorm** (20 s): drops 3–6 branch-fall deposits, fells every snag, and has a 25%
    chance to fell weak trees.
- **Leaf fall.** Every 8 minutes the canopy drops litter: +30% stock to every litter pile,
  and new piles appear under big trees.

## 10. Win conditions

- **Default:** destroy every enemy Heart.
- **Ecological victories:** a stretch goal, toggled in the menu.
  - **Court:** hold a Mother Tree linked to 5 or more trees for 3 minutes.
  - **Hollow:** decompose 8,000 total stock.
  - **Choir:** keep 30 or more thralls at once for 2 minutes.

## 11. Tech trees (each court has its own; the shared three are gone)

Every court gets three tiers ("flushes") and about eight techs. Each tree is a DAG, and the
HUD tree already draws per court.

**Amanita Court**

- **First flush**
  - *Hartig Net:* mantles +35% sugar, and vigor rises twice as fast.
  - *Muscarine:* poison +50%.
- **Second flush**
  - *Root Signalling*, needs Hartig Net:
    - Linked trees share vigor.
    - You are alerted when a linked tree is attacked.
    - Tree vision extends **two** hops.
  - *Phalloides*, needs Muscarine: unlocks Death Cap Grove, Angels, and Fairy Ring.
  - *Rhizomorph Bootlaces*: cords get +6 range and ×2 hp and throughput.
- **Third flush**
  - *Universal Veil:* +25% unit hp, and unlocks Bloom.
  - *Old-Growth Pact:* each tree gets one more mantle slot, saplings grow ×3, and Mother
    Tree needs only 2 links.

**Morel Hollow**

- **First flush**
  - *Exoenzymes:* +35% digestion of soil and deposits.
  - *Necrophagy:* corpses give +50% and rot 2× slower.
- **Second flush**
  - *Armillaria Bootlaces*: cords get +6 range and ×2 hp and throughput, and unlocks Honey Rot.
  - *Pilobolus Lineage*: unlocks the Pilobolus Bed and Snipers.
  - *Pyrophilous*: structures regenerate, and unlocks Wildfire.
- **Third flush**
  - *Calvatia Gigantea:* unlocks Giant Puffball, and Bombers gain +30% splash.
  - *Humus Engine:* humus bonus ×2, and exhausted deposits regrow 20% stock over 5 minutes.

**Veiled Choir**

- **First flush**
  - *Stench Glands:* Lure (structure and Heart) radius +50%. The Stench Lure spore action is
    available from the start.
  - *Chitin Lysis:* thralls decay 40% slower and gain +15% hp.
- **Second flush**
  - *Hypocreales*: unlocks the Cordyceps Spire, Stalkers, and Zombify.
  - *Summit Disease*: sporulation bursts are bigger (+50% spores, 70 damage) and reveal
    for twice as long.
  - *Ophiocordyceps*: Beetle Thralls bore trees ×2, and insects near any thrall slowly
    become infected.
- **Third flush**
  - *Pandemic*, needs Hypocreales: unlocks the Pandemic spore action.
  - *Brood Chamber*: unlocks the Brood Chamber structure, and the population cap rises by 10.
  - *Agrilus Swarm*, needs Ophiocordyceps: unlocks the Agrilus Swarm spore action (V). See §5.

---

## 12. Build plan

Each phase ends with a bot-game check (`--bot --log`) and a hand playtest before the next phase
starts.

### Phase 1 — Three economies on the current map (first pass done)

1. **World objects.** These are new entity kinds for map content, which works fine with the
   existing ROCKS and LOGS layout:
   - `DEPOSIT`: stock, kind, and nest state.
   - `INSECT`: neutral, with no court.
   - `trees[]`: per-tree runtime state (vigor, mantles, Honey Rot, alive, snag).
2. **Roster reshuffle in `data.gd`:**
   - Clathrus moves to the Choir.
   - Earthstar, Bird's Nest, Bomber, and Pilobolus move to the Hollow.
   - Zombify and Cordyceps move to the Choir.
   - Root Snare is new for the Court.
3. **Court:** the mineral→sugar mantle loop, tree vigor, partner multipliers, the Web
   pooling bonus, and fruiting spores.
4. **Hollow:** deposits, Rot Bracket, corpses and nitrogen, Inkcap Bed, Honey Rot, humus.
5. **Choir:** insects and nests, infection, thrall types and decay, sporulation, Lures,
   structures grown from hosts, and no cords.
6. **HUD:** per-court resource labels, tree vigor rings, deposit stock bars, the sporulate
   command, and a placement ghost for grow-from-thrall.
7. **AI:** one economy script per court. The Court mantles trees and defends them. The Hollow
   chases deposits and fights. The Choir hunts insects and sporulates.
8. **Art:** insects (ant, beetle, fly, springtail) and their thrall versions, plus Root
   Snare, Rot Bracket, Inkcap Bed, Honey Rot, Stinkhorn Lure, and Brood Chamber.
   - Placeholder primitives are fine at first.
   - USNEA's insect body plans are worth mining for this.

### Phase 2 — Per-court tech trees (§11) (done in data and the HUD tree)

### Phase 3 — Fog of war, cord throughput, minimap (§6, §7) (first pass done)

### Phase 4 — The forest map: 192 × 144 m, zones, stream, weather, treefall, saplings, leaf fall (§8, §9) (map, weather, treefall and leaf fall built; saplings and the remaining zones next)

### Phase 5 — AI that respects fog (first pass done), Physarum roaming hazard, ecological victories

The AI now acts only on what its court can see now or has spotted before, plus the three start
positions. It sends a scout early, and armies with no spotted target march on the rival's start.

### Tooling — a headless simulation harness for balance (built: `tools/sim/run_batch.py`, see ROADMAP)

Today every balance test is a full rendered game at 8× speed: about 1.5 min of wall time per
10-min match. That allows three seeds per change, and three seeds are mostly noise.

`game.gd` is already a state machine: the whole match is its state, advanced by `_step(dt)`. A
headless mode would run that same code, with no separate model to keep in sync:
- **No presentation.** Skip meshes, particles, decor, the fog texture and audio. Ents keep a
  bare `Node3D` so the rest of the code is unchanged.
- **No frame clock.** Step the simulation as fast as the CPU allows (fixed `dt`, many steps per
  frame), with no 8× cap.
- **CPU mycelium.** Territory, income and vision depend on the GPU sim, which headless Godot
  can't run. Use a coarse 2 m CPU stand-in, or the existing structure-reach estimate. Check it
  against a few rendered games, because headless balance can drift a little from the real thing.
- **A batch runner.** Run N seeds in parallel (one process per core) and aggregate: win rate per
  court, time to first Heart kill, income curves, units trained, and spore-action use.

**Expected:** 20–50× faster per game. Balance changes judged on 30+ seeds instead of 3.

**Not worth it:** a separate abstract model (equations or a spreadsheet). It would drift from
the real game the moment either changed.

## 13. Open questions

- **Sporulate input.** Should it be its own command key (S), or automatic when an idle thrall
  sits on a summit point?
- **Fern understory.** Does it hide units from towers too, or only from units?
- **Starting position.** Is it fixed per court, or random with the fair-mix starts? Random
  needs the AI to read the terrain.
- **Thrall decay.** Can the Choir's player see a thrall's remaining life? Probably yes, as a
  thin ring that drains.
