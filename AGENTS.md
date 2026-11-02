# Agent notes for RHIZOMORPH

Godot 4.7.2 fungal RTS, GDScript only. `ROADMAP.md` is the handoff log and `DESIGN.md` the design.
Commit directly on `main`. Other agent sessions work in this repo at the same time, so stage and
commit only your own changes.

## Making or improving 3D art (units, insects, buildings, props)

Follow the **unit-art** skill before writing any art code:
- Claude Code: `.claude/skills/unit-art/SKILL.md`, loaded automatically in this repo.
- Codex: `~/.codex/skills/unit-art/` (a copy). The repo copy is canonical. After it changes, refresh
  the Codex copy with `rm -rf ~/.codex/skills/unit-art && cp -r .claude/skills/unit-art ~/.codex/skills/unit-art`.

In short:
- **Build:** a headless Blender script builds a parametric sculpt, Cycles bakes normals and AO onto
  three LODs sharing one painted atlas, and the unit draws as one surface with shader-driven motion.
- **Reference:** `tools/blender/beetle_build.py`. Shared code lives in `tools/blender/paintlib.py`.
- **Gate:** `python tools/art/atlas_lint.py art/<unit>/<unit>` must show 0 FAIL.
