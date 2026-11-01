# Performance optimization results

Implemented and validated on 2026-11-01. Changes are uncommitted.

## Changes

- Mycelium skips source-edge noise when the unperturbed distance is beyond a conservative influence bound. All source kinds retain their original calculations inside that bound.
- Moss rejects fragments outside a strand before evaluating cushion noise and Voronoi detail. Shell count, geometry, lighting and surviving-fragment shading are unchanged.
- The selection panel retains its controls. Health, construction/research status, affordability and queue progress update in place; queue membership changes rebuild only queue controls.
- Entity visuals cache typed last-uploaded values for growth, wither, walk, cords, hit flashes and selection. Position and active animation still update every frame.
- The benchmark uses wall-clock frame times, excludes warmup/fast-forward from phase averages, and continues camera-dependent moss LOD/canopy updates. It recognizes both bare and valued benchmark flags and reports actual render scale, FSR mode and viewport size.

No graphics settings, gameplay rules or simulation frequencies were reduced. Asynchronous readback and the lower-priority stationary building-grid optimization remain outside this change.

## Correctness and visual checks

- GPU compute: byte-identical reference/optimized fields over 12 steps with 96 sources on the full 576 x 432 grid. Includes all source types, degenerate geometry, established competing colonies and uninitialized cells. Readback size is checked.
- Moss: byte-identical rendered images at camera distances 18 and 36, with matching LOD and temporal effects disabled. A hidden-board reference ensures empty/failed draws cannot pass.
- Real-game HUD/state regression: passes health, training, repeated queue changes, cancellation, affordability, keyboard focus retention, construction, research, enemy inspection, death/reselection, group/empty selection, hit flashes, selection rings, growth/wither and cord transitions.
- Selected-building screenshot visually inspected. No layout regression observed.
- Sol reviews found no shader-bound or cached-visual correctness issues. The regression harness was fixed to create its test cord explicitly.
- Full rendered bot runs at 60 and 300 simulated seconds completed with no script errors.

## Measurements

Hardware: NVIDIA GeForce RTX 4060 Laptop GPU; Godot 4.7.2, Vulkan Forward+.

Controlled mycelium test: six alternating measured rounds after warmup, 10 fixed-input dispatches per sample, identical inputs and 96 sources. Time includes CPU submission plus GPU completion waiting; readback is outside the timed region.

| Variant | Median wall milliseconds per dispatch |
|---|---:|
| Original | 2.6522 |
| Optimized | 1.0338 |

This is about **61% less dispatch time in this controlled test**, not a claim of 61% higher whole-game FPS.

The settled-scene visual-update microbenchmark was noisy: median approximately 371 us before and 344 us after over three samples. The last optimized sample was slower; do not treat the CPU result as a guaranteed improvement across scenes.

Final whole-game checks at native 1600 x 900, FSR disabled, camera distance 45:

| Fast-forward target | Average FPS | 1% low FPS | Reported render GPU ms | Units at end |
|---|---:|---:|---:|---:|
| 60 seconds | 30.0 | 29.6 | 27.3 | 100 |
| 300 seconds | 27.6 | 11.4 | 25.1 | 101 |

These two scenes are smoke/performance checks, not controlled before/after matches. The earlier reported 20.5 -> 17.4 ms comparison is superseded: the valued benchmark flag could previously allow saved scaling settings while reporting native resolution. There is no verified whole-game FPS gain to report. The near-30 FPS behavior in the early scene and later frame-time spikes merit separate profiling if further optimization is desired.

Full-game and HUD regression runs still emit shutdown ObjectDB warnings; the earlier unmodified baseline also emitted ObjectDB warnings. Compute and moss equivalence exit cleanly. The moss-test resource warning was traced to the menu-only unparented weather node and handled in test teardown. General game shutdown cleanup remains separate follow-up work.

## Reproducing checks

Run GPU tests sequentially using a graphical rendering device, not the headless dummy renderer. The local executable used was `../USNEA/engine/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe`.

Reference files, logs and images currently reside under `.godot/perf_review/` (ignored local artifacts). If they are missing, recreate the three reference files from baseline commit `fb9cef5f6a148d64df662f7e156d24752f2e483e`:

```python
from pathlib import Path
import subprocess
out = Path('.godot/perf_review')
out.mkdir(parents=True, exist_ok=True)
revision = 'fb9cef5f6a148d64df662f7e156d24752f2e483e'
for source, target in [
    ('shaders/myc_sim.glsl', 'myc_sim_before.glsl'),
    ('shaders/moss.gdshader', 'moss_before.gdshader'),
    ('scripts/game.gd', 'game_before.gd'),
]:
    (out / target).write_bytes(subprocess.check_output(['git', 'show', f'{revision}:{source}']))
```

```text
godot --path . --script tools/tests/performance_regression.gd -- --reference-game=res://.godot/perf_review/game_before.gd
godot --path . --script tools/tests/mycelium_equivalence.gd -- --reference-sim=res://.godot/perf_review/myc_sim_before.glsl --benchmark
godot --path . --script tools/tests/moss_equivalence.gd -- --reference-moss=res://.godot/perf_review/moss_before.gdshader
godot --path . --max-fps 0 --delta-smoothing disable -- --bot --seconds=60 --speed=8 --fpstest=45 --profile
```

Use `--seconds=300` for the later-match check. The HUD regression can run without the optional `--reference-game` microbenchmark. GPU-driver blocking requires an external process timeout; the moss test also has a render watchdog.

The previous handoff is complete: regression errors were repaired, comparisons and rendered checks completed, the HUD image reviewed, and unrelated generated import artifacts removed. Further FPS investigation and shutdown cleanup are follow-up work, not pending implementation of the four requested priorities.
