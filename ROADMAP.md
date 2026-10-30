# RHIZOMORPH — roadmap & handoff

Fungal-faction RTS on a terrarium diorama. Godot 4.7.2 (Forward+, RTX 4060), GDScript only.
Launch: `play.bat`. Art targets: the two screen recordings (fungal terrarium diorama, moss
digested to grey by spreading fungi, tilt-shift DOF, ground-level close-ups) and
`inspiration_art/*.png` (golden-hour light, glowing rhizomorph cords with gold beads,
legged mushroom units, faction-tinted territory, glowing root network in the cut side,
top-centre resource pill, left portrait column, bottom build bar with mushroom icons,
ability group, bottom-right minimap with territory + node graph).

## Design (agreed)

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

Controls (in game): LMB select / drag box / double-click same type, RMB move / attack / set rally,
A attack-move, S stop, N M B T G L K build (Shift keeps placing), Z X C spore actions, 1-3 train,
Tab lineages, Q/E or MMB-drag rotate, wheel zoom, arrows / screen edge pan, Space Heart, P pause,
+/- speed, Esc cancel.

## Pick up here next

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
- Per-unit sounds: game emits `hit_<unit id>` and `spawn_light|heavy|elite`; audio.gd mixes them with the generic
  `hit_melee` / `spawn` family (35% generic) and falls back to it when a specific one is missing.
- Run `--headless --import` (and let it finish) after copying new wavs, or Godot won't list them.
- Headless ComfyUI for this: from `ComfyUI-Installs\ComfyUI\ComfyUI` run the Documents venv python `main.py
  --base-directory Documents\ComfyUI --models-directory C:\Users\mmulq\ComfyUI-Shared\models --port 8199
  --user-directory <scratch> --output-directory <scratch>` with `PYTHONUTF8=1 PYTHONIOENCODING=utf-8`
  (a node prints emoji and crashes the server on cp1252 when output is redirected).

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
