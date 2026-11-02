# RHIZOMORPH — roadmap & handoff

## Roles, counters and controls (proposal, 2026-11-02; not started)

A roster review against the usual RTS roles. The design and the full role table are in DESIGN §4.5.
The short version: the roster has no siege that outranges towers, the Court has no fast raider,
nobody has anti-air, and the Choir has no cheap ranged unit. Under all of that, the controls are
too thin to show tactical depth.

**Build order:**
1. **Controls.** Everything else depends on these.
   - Control groups: Ctrl+1–9 to set, 1–9 to select, double tap to jump the camera. Training
     moves off 1–4 (`hud.gd` key handling, around `KEY_1`…`KEY_4`).
   - Shift-queued move, attack and build orders, with waypoint lines.
   - Patrol and hold position (next to Y stop).
   - Right-click to move or attack, A then click to attack-move, left-click select only. Keep the
     current left-click scheme as a setting. Update the controls list in this file and the Esc
     page.
2. **Siege that outranges towers (more than 13 m, the Bird's Nest's range), and AI that brings it.**
   - Court: Root Heave (breaks structures inside a fed tree's root zone).
   - Hollow: rework the Bomber or Sniper to about 15–16 m, with setup time or a minimum range.
   - Choir: a summit sporulation burst that damages structures.
   - `ai.gd`: when towers have been spotted, waves wait for siege.
   - Check it in a 48-seed batch, and against the turtle from the first human win.
3. **Fast raiders.** Court: a truffle vole ally (fast, fragile, a cord cutter). Hollow: a
   rhizomorph lunge to go with the Runner.
4. **Roster depth, one at a time,** each followed by a 48-seed batch:
   - Damage kinds against armor kinds: poison, crushing and enzyme against chitin, soft flesh and
     woody. This replaces the thralls' single `armor`.
   - Webcap nets that ground flyers.
   - A bombardier beetle thrall for the Choir (plus its nest).
   - Burrow as sclerotia on your own ground.
   - Travel through the cords, from node to node (Court and Hollow).
   - A detector role for the Angel's cloak.

## First human win, and polish from it (2026-11-02)

**The game.** The user won as the Morel Hollow on Gentle, a 26-minute free-for-all
(`playtests/20261102_144105_morel.json`). Notes from it:
- **A tower turtle won it.** The user built about 45 Bird's Nests and 11 Earthstars, and ended
  with 107 structures.
- **The corpse creep fed the turtle.** It produced 6,144 nitrogen from 1,178 corpses as enemy
  waves died at the towers. That contradicts "a Hollow that turtles starves". One possible fix:
  only kills made by units grow mycelium toward corpses.
- **Nitrogen famine between fights.** Nitrogen sat at 0–0.1/s for about 5 minutes in total, with
  only 6 Rot Brackets and 4 Oyster Shelves. A small Heart nitrogen trickle would help.
- **The Choir still snowballs on Gentle.** It had 76 units at minute 7. Gentle should also scale
  its infection, not just income.
- **The playtest save mixes all courts' stats.** `built_*` and `cast_*` are global, and kills
  aren't saved. Add per-court keys.

**Done from the user's feedback:**
- **Tech tree:** the grow-in animation plays 3x faster (`TECH_ANIM` in `hud.gd`).
- **Cords:** half as many travelling beads (`cord.gdshader`).
- **Mycelium:** each court's ground now looks different (`terrain.gdshader`, blended by share):
  - Court: dark soil under silky rose-white mycorrhizal fans, with red root tips.
  - Hollow: white rot, bleached cream with black spalting zone lines and amber stain.
  - Choir: mauve ground with clustered, powdery violet-white spore colonies.

  The hyphal front takes the advancing court's colour. GPU cost after reusing the shared domain
  warp is about +0.3 to +1 ms in noisy A/B runs at `--fpstest=60`.

## Match setup: duel or free-for-all (2026-11-02)

The start menu now walks through three steps:
1. **Your court:** pick one of three cards.
2. **The battle:** *Duel · 1 v 1* or *Free-for-all · 3 courts*.
3. **Your rivals:** chips for the two other courts, plus Rival strength (Gentle / Fair / Cruel).

In a duel the chips pick the one opponent. Clicking a single rival during a free-for-all switches
to a duel against it. A summary line shows the matchup ("Morel Hollow against Amanita Court").
Choices are saved in `user://settings.cfg` (`court`, `mode`, `rival`).

**How it works:**
- `game.start(faction, bot, courts)` takes the list of courts in the match. A court left out gets
  `fs[f]["present"] = false` and `alive = false` from the start: no Heart, no starters, no AI.
- Everything that already skips fallen courts (AI rival choice, win check, income, fog) works
  unchanged.
- **Test flags:** `--courts=1,2` (also in `--sim`), and `--menu=duel` stages the duel menu for
  screenshots.
- `sim_summary` records `present` per court. `run_batch.py` still assumes three courts; teach it
  about `present` before running duel batches.

### Team play (not built yet; noted for later)

Teams such as 2 v 2, or 2 v 1 against a stronger AI. What it needs:
- **More than one of a court.** Today a court and a faction index are the same thing (`Data.FACTIONS[f]`,
  `fs[f]`, and the mycelium sim's three channels). A 2 v 2 needs four players, so two of them
  would share a court. That means splitting "player slot" from "court kind", and a fourth
  mycelium channel, or two allies sharing one channel.
- **Teams.** A `team` per slot. Every `f != o` hostility check (`_enemies_in`, targeting, cord
  cutting, fog sharing, Choir infection via `_hostable`, Hollow digestion of enemy ground)
  becomes a team check. Allies share vision, and perhaps cords: a Court cord feeding a Hollow
  bracket is a fun question.
- **Start positions** for four (the map has three), plus a team win check.
- **Menu:** a fourth step for team assignment, shown only when there are more than three slots.
- **Cheaper first step:** 2 v 1 with the current three courts. Two courts allied against the
  third needs only a team table and the hostility changes, not more slots.

## The living and the dead (2026-11-02)

This implements DESIGN §4.4. The Choir now infects the living, and the Hollow eats the dead.

**Choir.** Choir hits do their normal damage and roll to infect:
- Host insects are infected on every hit, so they turn on the first one.
- The other courts' ordinary units are infected 20% of the time (60% for the Stalker). Each
  success adds `INFECT_DOSE` 0.34, so three successes turn the unit, alive and keeping its wounds.
- Infection fades after 5 s without a dose.
- Pandemic and sporulation add doses.
- Plain kills never rise.
- A host that dies at 0.5 infection or more bursts for spores and leaves a husk with 30% of the
  usual nitrogen.

The code is `game.gd` `_hostable` / `_dose` / `_turn`, plus the infection block at the top of `_damage`.

**Hollow.** A corpse or rubble within `CREEP_REACH` of a connected Hollow structure or a Hollow unit
becomes a Hollow mycelium source (`_push_creep`). The sim summary now reports `eco_` counters:
corpses left, nitrogen taken from corpses, husks, and turned insects and units.

**24-seed batches** (wins for Court / Hollow / Choir; each result has a ±20-point margin):

| run | change | Court | Hollow | Choir |
|---|---|---|---|---|
| `baseline_1102` | before | 13 | 2 | 5 |
| `creep` | corpse creep only (reach 14 m, radius 3 m, strength 0.9) | 6 | 8 | 1 |
| `living` | creep + living infection (committed values) | 2 | 8 | 8 |
| `creep_soft` | living, with creep at 10 m / 2 m / 0.7 | 3 | 4 | 15 |
| `grove48` (**48 seeds**, current) | living + grove resistance + `INFECT_DOSE` 0.25 | 14 (29%) | 17 (35%) | 10 (21%) |

**Current values (`grove48`).**
- **Grove resistance:** Court units in a fed tree's roots (`u.grove`) take half of every dose
  (`GROVE_RESIST`), and their infection fades without the 5 s wait.
- **Dose:** four infecting hits turn a unit. About 30 Court and Hollow units turn per match, plus
  about 180 insects.
- **Unresolved:** 7 of the 48 matches ran out the clock.

**The rival direction decides a lot.** The court that hunts the Choir wins:
- Hollow → Choir: the Hollow won 17 of 24.
- Court → Choir: the Court won 13 of 24.

The court the Choir hunts almost never wins (Court 1 of 24, Hollow 0 of 24): the Choir wears its
target down and the third court cleans up. This is mostly about how the bots pick fights.

**Next.** The three courts are roughly level now. A human game is the next real test. The items
below date from before `grove48`.

Earlier note: the Court was the weak court in both of the 24-seed runs, losing about 45–60
ordinary units per match to infection.

Options for the Court:
- A resistance. The open question in DESIGN §4.4 suggests Universal Veil halving infection.
- A smaller `INFECT_DOSE`.
- Fed-tree (grove) units resisting infection.

The Hollow's late income is still about twice the baseline's (cellulose about 18–21/s). A creep
setting between the two runs tested is worth a try. Use 48 seeds per change from here on, because
24 seeds swing too much.

## Coral Binder (2026-11-02)

The Morel Patch now plants a stationary Coral Binder through a two-click root and wall-end command. The wall grows linearly, slows enemy ground movement, can be targeted along its length and retaliates against direct melee; its segments share the root's health. The Morel AI can place defensive walls. Cost, health and rates are initial tuning values; multiplayer-scale and strategic balance still need playtesting. See `art/binder/README.md` and `DESIGN.md` for controls and details.

The Blender art uses a 1024 painted albedo and sculpt-baked normal/ORM, with one surface per LOD and 9,864 / 3,924 / 882 triangles. Atlas lint: 0 failures, 0 warnings. `tools/tests/coral_binder.gd` and `tools/tests/court_units.gd`: 0 failures. On the RTX 4060 laptop, 16 rounds with 60 ungrown battle roots measured median +0.16 ms. Ten fully grown walls plus battle roots measured median +0.08 ms in the same 16-round test; each wall can instance up to twelve 882-triangle modules.

Two critiques widened the shape, added forked arms and thorns, adjusted bead colors and ambient occlusion, and removed unsupported barbs from the distant wall mesh. Remaining art quality work: the normal bake has visible projection artifacts, and the branch junctions and repeated modules still look simplified at close range compared with the roster and beetle quality bar. Further sculpt, UV and normal-bake cleanup is needed.

## Elf-cup Slinger art (2026-11-02)

Rebuilt the Slinger with a sculpted scarlet cup and curled supports, painted 1024 albedo, normal and ORM atlas and one surface per LOD. Two critiques opened the bowl to the camera, shortened supports, softened ribs, adjusted rim and flecks and corrected projection artifacts on the rim and support bends. LOD triangles: 4,416 / 1,568 / 480. Atlas lint: 0 failures, 0 warnings. Court suite: 0 failures. RTX 4060 laptop, 16 interleaved rounds: 60 battle units median +0.05 ms over empty baseline. See `art/slinger/` for studio, match and motion captures. Existing firing timing and muzzle remain unchanged.


## Rot Bracket art (2026-11-02)

Replaced the selectable bracket's procedural lathe with a static Blender-built turkey tail colony on a decayed stump. Two critiques reduced repetitive bands, increased overlapping shelves, varied margins and stump shape, and shortened normal bake reach at the thin rim. One surface, 15,696 triangles, a 1024 albedo/normal/ORM atlas; atlas lint 0 failures and 0 warnings; Court suite 0 failures. `art/bracket/` contains studio and match captures. It is static, so the unit LOD performance benchmark does not apply. The separate turkey-tail text and data changes remain uncommitted from another session.


## Puffball Bomber art (2026-11-02)

Rebuilt the Bomber with a sculpt-baked warted puffball, segmented supports and vent, a painted 1024 albedo, normal and ORM atlas and one surface per LOD. Two studio critiques softened mechanical leg rings, replaced striped toe paint, reduced the vent, softened seams and enlarged the feet. LOD triangles: 6,080 / 2,204 / 808. Atlas lint: 0 failures, 0 warnings. Court suite: 0 failures. RTX 4060 laptop, 16 interleaved rounds: 60 battle units median -0.00 ms over empty baseline, below measurement resolution. See `art/bomber/` for captures and motion GIFs. Existing attack numbers and muzzle timing are unchanged.


## Candlesnuff Runner art (2026-11-02)

Rebuilt the Runner from a parametric Xylaria sculpt with a painted 1024 albedo, baked normal and ORM atlas, one surface per LOD, and game-time alternating supports and retained strike timing. Shape review addressed pointed tips, branching, oversized body, symmetry and the old gait lifting the whole model. LOD triangles: 5,088 / 1,904 / 696. Atlas lint: 0 failures, 0 warnings. Court suite: 0 failures. RTX 4060 laptop, 16 interleaved rounds: 60 battle units median +0.07 ms over empty baseline. See `art/runner/` for hero, match captures and motion GIFs.


## Remaining Morel Hollow close-up art polish (2026-11-02)

The four rebuilds pass the numerical atlas, mesh-budget and integration checks, but
the close-up visual bar is not fully met: the Slinger and Bomber supports still show
longitudinal UV seams and simplified joints; the Runner's branching is more regular
than the roster; and the Bracket shelves reuse a visibly similar band pattern.
Further sculpt and UV iteration against the roster and `beetle_build.py` is needed
before treating those close-view differences as resolved.

> **Resume here (2026-10-31):** graphics plan step 2 (shadow-only tree crowns) is built and waiting for
> the user's sign-off; step 3 is next. See "Graphics plan" and "Performance" below. Show the user each
> step before starting the next. The user's wider wishlist is under "Wishlist".

Fungal-faction RTS on a terrarium diorama. Godot 4.7.2 (Forward+, RTX 4060), GDScript only.
Launch: `play.bat`. Art targets: the two screen recordings (fungal terrarium diorama, moss
digested to grey by spreading fungi, tilt-shift DOF, ground-level close-ups) and
`inspiration_art/*.png` (golden-hour light, glowing rhizomorph cords with gold beads,
legged mushroom units, faction-tinted territory, glowing root network in the cut side,
top-centre resource pill, left portrait column, bottom build bar with mushroom icons,
ability group, bottom-right minimap with territory + node graph).

## Overhaul in progress (started 2026-10-30): see DESIGN.md

DESIGN.md is now the source of truth. The section below this one describes the original
symmetric design, kept for history.

**Phase 1 — the three economies on the current map: first pass DONE (2026-10-30).**

| Piece | Where |
|---|---|
| Forest state: trees (vigor, partners, root links, Honey Rot, death into a snag), deposits (log/litter/snag/corpse/rubble with stock and drain), humus, insect nests and breeding | `scripts/forest.gd` (new) |
| Insects are units of `Data.NEUTRAL` (3). They wander near their nest, retaliate only when hit, ants carry off corpses, beetles bore trees, springtails graze, and they fall sick at Lures | `game.gd` `_insect_think`, `_bore` |
| Court: mantles pay minerals for sugar scaled by vigor and partner species; Web bonus for linked trees, Mother Tree, fruiting spores; Root Snare scales with tree vigor; units cull pests on fed trees | `forest.gd` `_court`, `game.gd` `_hunts` |
| Hollow: Rot Bracket on wood deposits; corpses and rubble give nitrogen under Hollow mycelium; Inkcap Bed gathers and keeps corpses and digests litter; Honey Rot kills trees | `forest.gd` `_hollow` |
| Choir: no cords and never starves; structures grow from a thrall within 6 m; infection rules (`_infector`), thrall decay, sporulation (F key, `order_sporulate`), Lures, Brood Chamber, Pandemic, Heart spits | `game.gd` |
| Per-court rosters, resource names, start resources, starters, tech trees (7 each) | `data.gd` |
| AI: one build brain per economy; Choir builder thrall, hunting grounds (`_ours`), auto-sporulate; Court sends its army at Honey Rot on its trees | `ai.gd` |
| HUD: per-court resource names and costs, tree vigor bars, deposit stock bars (Hollow), Pandemic glyph, F sporulate, mute moved to Ctrl+M (M was eating the M build key) | `hud.gd` |
| Meshes: `i_ant/beetle/fly/springtail`, `t_ant/beetle/fly` (with cordyceps clubs), `inkcap_bed`, `anthill`; bark `dead` uniform for snags | `fungus_lib.gd`, `bark.gdshader` |

Bot balance (`--match=N` varies seeds): across 3 seeds after tuning, the Hollow won 2 and the Choir 1,
and the Court survived to 10:00 in one. The Hollow still banks too much nitrogen late. Results swing a
lot by seed, so judge balance from several matches. Run: `bash` loop over `--match=1..3 --seconds=600 --speed=8`.

**Phase 3 + map (2026-10-30, while the user was away):**
- **2× forest map:** 192 × 144 m, 16 trees with an old-growth centre, a stream with a log bridge
  and stepping stones, a windfall, 6 anthills. Everything that maps world to UV now reads the
  real `half_size`. Startup is about 8 s.
- **Fog of war:** `scripts/fog.gd`. The Court sees through its roots (fed trees plus their
  neighbours); the Choir sees only through thralls, structures and sporulation. Enemy units hide
  outside sight; enemy structures stay once spotted. `--nofog` disables it.
- **Cord throughput:** `game.gd _route_flows`. Mantle sugar and bracket cellulose ride the cords
  home, losing 3% per hop, and each cord carries 4/s (8/s with Bootlaces). Overloaded cords glow red.
- **AI:** armies come home when their Heart is attacked, and all three Hearts now have a
  defensive attack.
- **Agrilus Swarm** (Choir T3, V key), **stag beetles** (logs), **bark beetles** (snags and weak
  trees), and Ophiocordyceps-style thrall models.
- **Weather and treefall** (`scripts/weather.gd`): rain, dry spells, windstorms that fell snags
  into logs, branch falls and leaf fall. See DESIGN §9.
- **Bot balance after all of this:** five three-seed batches on the big map. Every court has won
  at least once, and games now last 5–15 min. Small changes swing the winner, so the last batch
  (Hollow 3/3) is noise as much as signal. Hand-play next.
- **New test flags:** `--nofog`, `--weather=wind|rain|dry`, `--snag=N`, `--match=N`.

**Next in the overhaul:**
1. Hand playtest on the big map with fog.
2. The headless simulation harness (DESIGN "Tooling"), so balance can use 30+ seeds per change.
3. Phase 4 leftovers: saplings, burn scar, stream crossings for cords (fern understory dropped).
4. Phase 5: the Physarum hazard and ecological victories. The fog-aware AI is done.

The older note follows: hand playtest Phase 1 (especially the Choir's grow-from-thrall placement and
sporulation by hand), then Phase 2 is mostly done in data (per-court tech trees exist), so Phase 3: fog
of war (the Court sees trees one hop out on the root graph), cord throughput, then Phase 4: the forest map.

## Design (original, superseded by DESIGN.md)

- **Factions**: Amanita Court (red, poison), Morel Hollow (gold, tanky/regenerating,
  Cordyceps zombies, wildfire), Veiled Choir (violet, stinkhorns/puffballs, speed,
  spore artillery). Slime mold (Physarum) = later neutral hazard.
- **Resources**: Nutrients (digesting ground under your mycelium; ground depletes, so
  expand), Sugar (Chanterelle mantles in tree root zones; a tree's sugar is shared among
  every mantle on it), Spores (spent on spore actions). The art also shows Water and
  Minerals, which are possible additions.
- **Supply lines**: every structure links to the Heart by black Armillaria rhizomorph
  cords with glowing gold pulses. Enemies cut cords, which starves everything downstream
  (no income, mycelium recedes, slow HP loss). Cords regrow after a delay, and redundant
  links self-heal.
- **Mycelium** is a GPU compute sim: reach from connected structures, cords and units,
  creeping growth, inter-faction digestion at fronts, and nutrient depletion. It feeds
  the terrain, moss and cut-side shaders directly.
- **Tech tree** (5 per faction, researched at the Heart): Exoenzymes, Spore Sacs,
  Bootlaces + 2 faction lineages (Phalloides/Universal Veil, Hypocreales/Pyrophilous,
  Pilobolus/Calvatia) unlocking new fruiting bodies, elite units and spore actions.
- **Spore actions** (Z/X/C): Haze, Fairy Ring, Death Cap Bloom, Ascus Volley, Zombify,
  Wildfire, Stench Lure, Spore Barrage, Giant Puffball.
- All numbers are in `scripts/data.gd`.

## Done

**2026-10-29:** data.gd, GPU mycelium (myc_sim/myc_summary + mycelium.gd), board.gd, board shaders,
camera_rig.gd, main.gd, fungus_lib.gd + fungus/legs shaders.

**2026-10-30:** the game is playable end to end (menu -> pick court -> play vs 2 AIs -> win/lose -> Again).

| File | State |
|---|---|
| art pass | golden-hour light (sun -21 deg, warm sky used only for reflections, SSR), cushion moss with voronoi domes + 4 species + bare patches, walnut table, one opaque water sheet (false puddles removed by soft-clamping low ground), darker rock, snapped-off trunk tops (ragged cut, dark heartwood), only trunk butts cast shadows |
| `scripts/fungus_lib.gd` | SPECIES_SCALE, rebuilt bracket (tiered conks, pattern 10 growth zones), `morel_cap_big/small`, `veil_big`; legs.gdshader instance uniforms now match fungus.gdshader order |
| `scripts/game.gd` | entities (Ent: UNIT/STRUCT/CORD/PUFF), placement rules + cord links to the 2 nearest connected structures, connectivity BFS, starving, cord sever/regrow, economy from `myc.coarse` (headless fallback), training, research, towers, projectiles (homing / arcing / splash), poison/slow/regen/infect, all 9 spore actions, decor MultiMesh sprouts, particles, screen shake, win/lose, `--log` stats |
| `scripts/ai.gd` | research order, build wants list (skips sugar-blocked items), army target that grows with time, waves, cord raids, defence, ability casts on clumps, cyclic rival + gang up on a runaway leader |
| `scripts/hud.gd` | resource pill, portrait column, build bar + abilities (icons rendered from FungusLib in SubViewports), context panel (train/queue/research/rally), minimap (myc texture + cord graph + camera footprint, click to jump, RMB to move), messages, tech tree (Tab), start menu, end screen, all input |
| `shaders/cord.gdshader` | dark bootlace with travelling gold beads, red glowing gap when severed |
| `shaders/ring.gdshader` | depth-test off but hidden behind solid things via the depth texture |
| `shaders/myc_sim.glsl` | source reach is noise-wobbled, so territory edges are lobed, not circles |

Controls (in game, since 2026-10-30):
- **Left click:** select your units and buildings; click the ground to move the selected units; click
  an enemy (or an insect) to attack it; drag to box-select; double-click selects all of that kind.
  **Ctrl+click:** attack-move. With only a trainer selected, click the ground to set its rally point.
- **Right click:** cancel placing or casting, otherwise drop the selection.
- **Camera:** WASD or arrows (and the screen edge, which can be turned off) to pan, Q/E or middle-drag
  to rotate, wheel to zoom.
- **Keys:** Y stop, F sporulate (Choir) / brace (Cep Bulwark); build keys N M B T G L K H (Shift keeps placing); Z X C V R
  spore actions; 1-3 train; Tab lineages; Space your Heart; P pause; +/- speed.
- **Esc:** opens the settings page, which pauses the game. It has Master / Music / Effects volume
  (audio buses, saved to user://settings.cfg; default 50/55/60%), camera speed, fullscreen, edge
  scrolling, the controls, and Resume / Quit to menu / Quit game. `--settings` stages it for screenshots.

**2026-11-01:** three Court units integrated from art kits (sources in `art/<unit>/README.md`;
roster sheets for all three courts in `reference_images/`).

| Unit | State |
|---|---|
| Wartling | second art pass: `scripts/wartling.gd` + `shaders/wartling.gdshader`, cached close / battle / distant meshes chosen by projected cap width |
| Cep Bulwark | new trainable unit at the Cortina Thicket. `scripts/cep_bulwark.gd` meshes and LODs, `scripts/cep_actions.gd` bash / brace states driven by game.gd; braced Ceps catch direct shots in `_catch_shot`. Review scene: `scenes/art_review/cep_bulwark.tscn` |
| Destroying Angel | skinned GLBs (13 joints, Idle / Walk / Attack) in `art/destroying_angel/`, `scripts/destroying_angel.gd`; clips advance with game time; LOD swaps mesh + skin; cloak hides it from enemies (`game.hidden_from`) |

Melee blows with a `windup` (Cep, Angel) now land on the animation's impact frame (`_swings`).
Check: `$G --path . --script tools/tests/court_units.gd [-- --shots=DIR]` (22 assertions, real renderer).

**Violet Webcap v2, the first Blender-built unit.** `tools/blender/webcap_build.py` (headless Blender 4.2,
`blender -b --factory-startup -P tools/blender/webcap_build.py`, ~25 s on OptiX) builds a 350k-face sculpt,
bakes normals and occlusion onto three low-poly LODs that share one 1024 atlas, paints colour, roughness,
glow and silk, and exports `art/webcap/webcap_{close,battle,distant}.glb`. `scripts/webcap.gd` loads them as
one mesh with two surfaces: the opaque body (`shaders/webcap.gdshader`: clear coat and anisotropic sheen on
the cap) and the blended silk veil (`shaders/webcap_silk.gdshader`); both step with
`shaders/webcap_gait.gdshaderinc`. Reuse this pipeline for the next units. Renders and the preview scene:
`tools/webcap/`; `tools/webcap/perf_webcap.gd` measured 60 Webcaps at battle LOD at +0.25 ms per frame
(today's old model +0.08, v1 procedural +0.15) on an RTX 4060 laptop; vsync off, interleaved rounds.

**Morel Bruiser, the second Blender-built unit.** `tools/blender/bruiser_build.py` (shared helpers in
`tools/blender/unitlib.py`) sculpts a Voronoi honeycomb cap with pits about 5 cm deep, two morel shoulders
on thick knuckle-walking arms, two rear legs, padded clawed feet and glowing golden cracks, and bakes it
onto 5.8k / 2.1k / 0.5k-triangle LODs sharing one 1024 atlas (orm alpha = pit height). One opaque surface.
`shaders/morel_bruiser.gdshader`: diagonal knuckle-walk, breathing, close-range parallax on the honeycomb
(fades out by 16 m), and the attack: both arms rise overhead and smash down at 45% of a 0.9 s swing, where
`windup` 0.4 lands the blow. glTF flips the data UV's v: the shader reads `1.0 - UV2.y`.
Generic tools for any Blender-built unit: `tools/art/render_unit.gd`, `ingame_unit.gd`, `perf_unit.gd`
(`--unit=bruiser|webcap`); `FungusLib.legacy_mesh(id)` still builds the old procedural model for comparisons.

**Muscarine Spitter, Blender-built after the Amanita Court roster sheet.** `tools/blender/spitter_build.py`
(`-- --preview=out.png` renders the bare mesh in Workbench in about a second, for shape work) builds a tall,
top-heavy Amanita: four garlic-clove volva bulbs, a swollen fibrous stalk that leans back, and a laterally
squeezed cone of a cap that hooks back to its tip, its opening turned forward over gill lamellae and a
golden throat. Sculpt of 470k faces (gills, raised warts, stalk scale rings, lobed bulbs), baked onto
4.6k / 1.5k / 0.5k-triangle LODs sharing one 1024 atlas. One opaque surface. `shaders/muscarine_spitter.gdshader`
has no skeleton: the stalk bends by height with a lag that grows up it, so the cap wobbles behind the bulbs as
they waddle in diagonal pairs. To spit, the stalk coils back while the cap rears, squeezes and its throat
glows, then it lashes forward; the glob leaves at 35% of a 0.85 s clip. Ranged units can now have a
`windup` too: `_fire` parks the shot in `_swings` until the release frame (the Sniper still uses its own list).
Gold muscarine glob with a droplet spray (`_shot_node("muscarine")`). In-game capture: `tools/art/spitter_attack.gd`.
60 Spitters at battle detail add +0.07 ms per frame against +0.21 ms for the old procedural model (`perf_unit.gd`).

**Beetle / Whitecoat Bulwark (2026-11-02), Blender-built after the Veiled Choir roster sheet.**
`tools/blender/beetle_build.py` builds a Colorado potato beetle (*Leptinotarsa*) with *Beauveria* tufts as their
own data kinds: one set of GLBs serves the wild `beetle` (tufts dropped at load by `scripts/whitecoat_beetle.gd`)
and the `t_beetle` thrall. The shader's `infect` swells the tufts out of the seams and dusts the shell white, so
a wild beetle sickening near a lure (`Ent.infect`) visibly whitens before it rises. Tripod walk; the attack rears
it onto its hind legs with mandibles spread, then slams and bites at 40% of 0.75 s (`windup` 0.3 added to
both beetles, so their blows now land 0.3 s after the swing starts, and miss if the target has left reach).
A thrall's bite shakes off a puff of white conidia. Tuft edges fray with a per-texel discard. The display names
are still "Bark Beetle" / "Beetle Thrall". Details and commands: `art/beetle/README.md`.

**unit-art skill (2026-11-02).** `.claude/skills/unit-art/` (copied to `~/.codex/skills/unit-art`; `AGENTS.md`
points Codex at it) teaches the Blender pipeline to any model: a workflow with gates, painting and Godot
references, and a runnable `template_build.py`. Shared code: `tools/blender/paintlib.py` (noise, Voronoi cells,
colour ramps, parametric surfaces, sweeps, `bake_atlas`, previews). `tools/art/atlas_lint.py` gates atlas quality.
It currently fails Runner and Slinger (per-pixel noise), fails Bomber's normal map, and warns on Sniper and Inkcap
Bed (no baked normals or ORM). Those are candidates for a rebuild with the skill.

**Balance (2026-11-01).** Population cap 40 -> 100 for every court (Brood Chamber now +10). Every Choir
unit at 80% hp and 85% damage. Bot batches (24 seeds each, Court / Hollow / Choir wins): cap 40 at full
stats 3 / 2 / 17; cap 100 at full stats 0 / 3 / 20 (a higher cap alone helps the Choir, whose army is free
thralls); cap 100 at 75% hp / 85% dmg 15 / 2 / 4; at 50% / 70% 15 / 4 / 0. 80% / 85% is untested; the Choir
is very sensitive to thrall stats. The Hollow loses in every setup: the next balance problem.

## Pick up here next

0. **Roles, counters and controls** (top of this file, DESIGN §4.5): control groups and queueing
   first, then siege that outranges towers and AI that uses it.
1. **Play it by hand.** Every automated check is bot-vs-bot. The HUD input paths (placement,
   right-click orders, box select, minimap clicks, tech buttons) parse and are wired, but no human has
   clicked through them yet.
2. **Balance.** With `--bot --log` games end around 5-6 min for the first Heart. Veiled Choir is still the
   weakest (lower income at its start: Heart gets `"nutrients": 3.5` vs 2.0 to compensate). Watch
   `stats` (kills by faction, units trained). Elite units/lineage tier 3 rarely come online before
   someone dies; consider slower early aggression or tougher Hearts.
3. **Feel.** Hit flashes, bursts and shake exist; still missing: death-cap / fairy-ring props growing in
   rather than popping, sound, unit facing on melee, a selected-unit move line.
4. **Art.** Armillaria nodes read pale tan under the sun (could be darker honey), puddles read as
   black pits (no SSR hits from steep angles), digested ground speckle aliases at distance, the cut-side
   soil glow under owned ground barely shows. Physarum slime mold hazard not started.
5. Win condition is "kill both other Hearts"; a fallen court's leftovers rot over ~25 s.

## Audio (started 2026-10-30)

- `scripts/audio.gd` plays picked clips from `audio/sfx/<name>.wav` (or `<name>_1.wav`, `_2`... chosen at random)
  and `audio/music/<name>.wav`; missing ones are silent. `game.gd` emits `sound(name, at)` for every event.
  Music: menu / calm / tension / battle by how much of the player's army is fighting, victory / defeat stings. M mutes.
- Prompts + review status: `audio/sfx/prompts.json`, `audio/music/prompts.json` (each entry has `use`, `prompt` or
  `prompts` [list], `seconds`, `variants`, `loop`, `status`, `notes`).
- Generators (`tools/audio/`, run with `Documents\ComfyUI\.venv\Scripts\python.exe`, need a ComfyUI server):
  `gen_sfx.py` (Stable Audio 3 Small SFX, ~1 s per sound) and `gen_music.py` (MusicGen medium, ~1-2 min per 30 s clip);
  candidates go to `audio/*/candidates/` (Godot-ignored). `--only a,b --force` regenerates.
- Review: `build_review_page.py` -> `audio/review_site/` (MP3s + page from `review_page.html`), published as
  https://claude.ai/artifact/S1YWWFcNq7z1kpcP2bgMpN . Decisions live in its db collection `reviews`
  (doc `sfx-<name>` / `music-<name>`: decision approve|regenerate|more|reject, keep[take ids], comment).
- Review rounds: export decisions with ArtifactData `list` + `out_dir` -> `audio/review_site/decisions_roundN/`,
  `apply_review.py <dir> --round N` (copies kept takes to `audio/*/<name>_N.wav`, records `in_game` as `rN:<take>`,
  sets status keep/more/redo/rejected), write new prompts (`prompts` lists, more variety per item), regenerate with
  `--force`, delete those items' docs in `reviews` (pin `if_version`), then `build_review_page.py --since <export mtime>`
  and republish the same file path. Rounds 1 and 2 done 2026-10-30: every item settled (40 sfx + 6 music in game,
  ambient_terrarium rejected). Raw decision exports are in `audio/review_site/decisions_round1|2/`.
- **Round 3 (2026-10-30), awaiting review:** 15 new sounds × 3 takes, published to the same review
  artifact (groups "The living forest" and "Weather"). They cover the borer swarm, Pandemic,
  sporulate, thrall rise, a stag-thrall hit, tree death, treefall, branch fall, leaf fall, thunder
  and gust (weather warnings), rain/wind/dry loops, and `ambient_forest` (replacing the rejected
  terrarium bed). The game already emits all of them; they stay silent until approved and copied
  in by `apply_review.py <dir> --round 3`. The weather loops fade in `audio.gd` (`WEATHER_LOOPS`).
- Per-unit sounds: game emits `hit_<unit id>` and `spawn_light|heavy|elite`; audio.gd mixes them with the generic
  `hit_melee` / `spawn` family (35% generic) and falls back to it when a specific one is missing.
- Run `--headless --import` (and let it finish) after copying new wavs, or Godot won't list them.
- Headless ComfyUI for this: from `ComfyUI-Installs\ComfyUI\ComfyUI` run the Documents venv python `main.py
  --base-directory Documents\ComfyUI --models-directory C:\Users\mmulq\ComfyUI-Shared\models --port 8199
  --user-directory <scratch> --output-directory <scratch>` with `PYTHONUTF8=1 PYTHONIOENCODING=utf-8`
  (a node prints emoji and crashes the server on cp1252 when output is redirected).

## Asset catalog (keep it current)

https://claude.ai/artifact/RbSKyxbFiprYQz7kWZBFqK holds one in-engine plate per species, grouped by court.
The user asked for it to grow as assets are built. **After adding or changing any model**, run:
```
$G --path . -- --catalog=screenshots/catalog/img          # --only=id1,id2 re-renders just those
python tools/catalog/build_catalog.py                      # writes screenshots/catalog/catalog.html
```
Then republish `screenshots/catalog/catalog.html` to that URL. Species come from data.gd (structures, units,
insects, decor), plus the props listed in `main.gd _catalog_entries`. Add a binomial to `LATIN` in the builder.
`tools/catalog/seen.json` dates each species' first render, so new ones get a "new" tag.

## Balance harness (headless)

```
python tools/sim/run_batch.py --seeds 24 --label baseline          # parallel all-bot matches -> sim_runs/baseline/report.md
python tools/sim/run_batch.py --seeds 24 --label after_change      # same seeds after a change
python tools/sim/run_batch.py --compare baseline after_change      # win rates side by side
$G --headless --path . --fixed-fps 10 -- --sim --profile --match=11 --seconds=900   # one match, time per phase
```

- **Sim mode.** `main.gd --sim` runs the real game code: no HUD, audio, visuals, particles or
  decor. It ends when one court is left or at `--seconds`, and prints one `SIM {json}` line
  (winner, deaths, income per minute, units trained, techs, spore actions, `profile_ms`).
- **No frame clock.** `--headless --fixed-fps 10` steps 0.1 game-seconds per frame as fast as
  the CPU allows.
- **CPU mycelium.** With no GPU, `mycelium.gd` runs a 2 m port of `myc_sim.glsl`
  (`CPU_SPREAD` 0.35). It was calibrated against a rendered game on the same seed: Hollow
  cellulose income per minute 7.4 / 10.5 / 13.3 headless vs 7.4 / 11.2 / 14.8 on the GPU; the
  Court within about 15%.
- **Speed.** About 9× real time for one process alone; the parallel runs contend for the CPU
  (each slows to about 3× with 6 running). The default is 10 jobs; tune `--jobs`.
- **Seeds.** `--match=N` seeds the AI, the forest and the weather, so the same seed list compares
  two versions like for like.
- **First reading** (12 seeds, before the speed fixes): the Veiled Choir won 10 of 12, and the
  Amanita Court fell first in 9 of 12.

## Graphics plan (agreed 2026-10-30, continue here)

The user wants to **see each step (screenshots and FPS) before the next one starts.** Measure every
step with `--fpstest=60` and `--fpstest=150` (`--bot --faction=0 --match=2 --seconds=300 --speed=8`)
and compare against the table under Performance. The aim is better graphics without dropping below
about 35 fps at FSR Quality.

1. **Done: FPS budget plus FSR2.** Tiled, LOD'd moss and a render-quality setting (numbers below).
2. **Built (awaiting sign-off): shadow-only tree crowns.** `board._crown_cards` makes leaf-card crowns
   (oak lobed, birch columnar, hemlock tiered) drawn only into the shadow map (`shaders/crown.gdshader`,
   holes from one leaf-texture read). `build_forest_canopy` adds a band of forest beyond the board on the
   sun's side, kept only where its shade lands on the board (21 m spacing). A dead or felled tree drops
   its crown; windstorms shake the dapples; the leaves open up as the camera zooms out
   (`set_canopy_zoom`); `sun.shadow_opacity = 0.8` keeps units readable in shade. `--perf-nocanopy`
   hides it for A/B. Cost at `--fpstest=60`, FSR Quality: +0.8 to +2.9 ms GPU (40.8 -> 39.4 and
   40.9 -> 37.8 fps). The first version (noise per texel, 15 m band) cost 13 ms. Spore motes halved
   to 1250 (no measurable FPS change).
3. **Next: lower limbs on the trunks.** A few branches below the cut height so trees read as trees, not
   stalks: birch thin and upswept, oak thick and crooked, hemlock drooping. Add them in
   `board._trunk_meshes` / `add_tree`. They must survive the `cut_h` dither and new trees (nurseries).
4. **Canopy frame when zoomed out.** Visible crowns that are opaque at the screen edges and dissolve
   (dither) toward the centre and near the camera focus, fading out entirely when zoomed in. A gap in
   the trees looking down, never covering the play area.
5. **Ground clutter and life.** MultiMesh twigs, pine needles, pebbles and fern fronds (low, kept clear
   of units' readability), wind sway on moss and small fungi tied to the weather, drifting leaves
   (more in leaf fall and windstorms), and moss and brackets on felled logs.

Also noted: rain particles look thin; the minimap is still the original size for a 4x board.

## Wishlist (from the user, 2026-10-30; not yet scheduled)

Art and engine
- Improve all assets, using Blender for them (driven headless from Python, exporting glTF).
- Rethink the legs on the mushroom units.
- Make buildings more distinct from one another.
- More performance.

Factions and gameplay
- Really focus on the gameplay differences between the courts so each has its own character.
- Amanita Court and Morel Hollow each get an expensive, charismatic hero unit: strong and hard to kill.
- A different win condition for each faction.
- Grow a second Heart elsewhere, so a court is not pinned to defending one spot.
- Remove the unit limit (and its bar in the resource pill).
- Team play (2 v 2, 2 v 1). Duel and free-for-all are built; see "Team play" at the top.
- Rebalance. The 2026-10-30 Amanita playtest: on Gentle the Choir still reached 47 units, because
  difficulty scales only income and its army comes from infected insects; Zombify and Pandemic turned
  the Court's army.

Interface
- Improve the UI generally.
- A tech-tree button that shows a notification when a research completes.
- ~~Make the tech-tree menu 50% faster to draw.~~ The grow-in now plays 3x faster (2026-11-02).
- A simple tutorial for each faction.

Release
- A browser build hosted on Cloudflare, staying inside the user's $5/month plan (optimise for the web).
- The full Godot (desktop) version on itch.io.

## Performance (2026-10-30)

`--fpstest[=camera distance]` fast-forwards (with `--seconds`), turns vsync off, frames the biggest fight
and times 20 s at 1x. It prints average and 1%-low FPS plus a CPU/GPU split. `--perf-nomoss`,
`--perf-nofx`, `--perf-noshadow` and `--perf-nomyc` switch suspects off, and `--fsr --scale=0.77` tests
upscaling. RTX 4060 laptop, 1600x900, mid-game, about 100 units:
- **Baseline:** 23 fps, GPU 37.7 ms. The 20-shell moss alone cost about 22 ms; post-processing, shadows
  and the mycelium compute were each under 2 ms.
- **Moss fix:** the moss now draws in 24 m tiles (frustum-culled), each with distance LOD (20 shells near,
  down to 5 far, spread over the same height via the `shells_drawn` instance uniform), and the mask and
  lean are computed per vertex. That gives 37 fps (GPU 22 ms) with no visible change.
- **FSR2:** Quality (77%) gives 39.5 fps; Performance (59%) gives 54 fps. Settings > Render quality, default
  FSR Quality. Settings > Show frames per second.
- **Next limit:** the CPU, at roughly 18-25 ms per frame.

## Difficulty

The start menu has a **Rival courts** row after the court cards: Gentle / Fair / Cruel (`Data.DIFFICULTY`,
remembered in settings; default Fair). It changes only the rival courts: how often they decide, how fast
their army target grows, when the first wave and first cord raid come, wave size, how big a clump a spore
action waits for, and income (Gentle 80%). Cruel is the old behaviour, and the balance harness stays on
it (`--difficulty=` overrides for test runs). An idle Court lasted 3.9 min on Cruel and 7.5 min on Gentle.
The Choir's thralls come from insects, so Gentle delays its attacks but not its numbers.

## Playtests (humans)

Every human game that ends (win or loss) saves the harness summary to `playtests/<date>_<court>.json`:
court, result, length, income per minute, units, techs, buildings, spore actions.
`python tools/sim/run_batch.py --playtests` lines them up against the bots' averages from the latest
batch. Bots and humans play very differently; use both.

**Fair rival cycle.** The AIs used to always press round the table one way, so the Choir hunted the
Court in every seed. Now `game.rival_step` alternates by seed (even: Court > Hollow > Choir > Court;
odd: the reverse), and reports split by direction. With it (24 seeds, 2026-10-30): Choir 13, Court 8,
Hollow 1. The Court's earlier weakness was mostly the cycle; the Morel Hollow is now the outlier.

## Verify loop

```
G=../USNEA/engine/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . --import                        # after adding/changing .glsl or class files
$G --path . -- --viewtest --wait=25 --shot=screenshots/viewtest.png
$G --path . -- --showcase --group=0 --wait=3 --shot=screenshots/showcase0.png   # 0 structures, 1 units, 2 decor
$G --path . -- --bot --log --faction=1 --seconds=600 --speed=8 --wait=3 --shot=screenshots/bot.png  # balance; grep "^t=\|stats"
$G --path . -- --bot --faction=0 --seconds=150 --speed=6 --wait=2 --hot=28 --shot=screenshots/fight.png  # frames the biggest fight
$G --path . -- --bot --faction=0 --seconds=70 --speed=6 --wait=3 --selheart --shot=screenshots/hud.png  # also --tech
$G --path . -- --menu --wait=4 --shot=screenshots/menu.png
```

Always grep the output for `ERROR`: a GDScript parse error in game/ai/hud does not stop the run, it
just leaves the board idle (and `--log` happily prints a frozen economy).

Compute shaders need a real GPU device, so visual and gameplay runs are **not headless** (a
window pops up briefly). Then Read the PNG.

## Footguns

- GDScript `cond and a or b` returns a bool, not a value. Use `a if cond else b`.
- `var x := expr` fails when `expr` touches untyped Array elements; annotate the type.
- After `sed` edits, the Edit tool wants a fresh Read.
- `for x in [1, 2]: var o := f + x` fails to infer; annotate (`var o: int = ...`).
- Setting `Control.position` on an anchored control inside a `resized` callback uses parent coordinates
  (off-screen); set `offset_*` instead. In `_ready` it happens to behave anchor-relative because the
  parent has no size yet.
- Instance uniforms shared between materials on one mesh must be declared in the same order in every
  shader (fungus.gdshader and legs.gdshader), or Godot warns and only one works.
- Main processes before HUD each frame; automated `--selheart`/`--tech` staging waits 1 s before the shot.
