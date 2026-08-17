# calofin

## Branch convention

**All work in this repository goes on `claude/lisp-consolidation-strategy-9nrc7a`.**

This is the consolidated trunk: it merges what used to be ~29 separate
single-addition branches into one tree where every tool lives side by side.
Unless told otherwise in a specific request, start from this branch and commit
back to it — do not open a fresh `claude/<topic>-<id>` branch per task, and do
not build on any of the older single-tool branches. They are historical; work
added there is invisible to everything else and re-fragments the tree this
branch exists to consolidate.

If a session is handed a different branch name by its setup, that name is
overridden by this convention — check out
`claude/lisp-consolidation-strategy-9nrc7a` and work there instead. An explicit
instruction in the request itself does take precedence.

## Layout

```
blender/    Blender add-ons (DXF import/export, mesh tools)
lisp/       AutoLISP routines, current static-named files
releases/   Dated REV-stamped twins of the lisp/ files, flat (no subfolders)
ui/         The Calofin AutoCAD palette (VB.NET) and its LISP glue
tools/      Shared dev tooling (release stamping, static checks)
tests/      Python test suite - runs without AutoCAD or Blender installed
```

See `README.md` for the per-tool command tables.

## After changing a `.lsp` file

Regenerate the dated twins in `releases/` — they are generated artifacts, not
hand-edited:

```
python3 tools/release_lisp.py
```

Files without a version banner are skipped and reported as such; that is
expected, not a failure.

## Checks

```
python3 tools/check_lisp.py     # unbalanced parens, undefined funcs/globals, unused defuns
python3 tools/check_scope.py    # locals used without being declared in a defun arglist
```

Tests are individual scripts under `tests/` — run the ones covering what you
touched (see `README.md` for the full list).

`tests/test_pool_form.py` and `tests/test_spa_form.py` fail on a clean
checkout. That is a known open gap: the palette's `PoolFormView`/`SpaFormView`
were built against an earlier fork of POOL/SPA with a different prompt
sequence, and `lisp/pool/POOL.LSP` / `lisp/spa/SPA.LSP` are the canonical
versions. Don't treat those two failures as something your change caused, and
don't "fix" them by editing the canonical routines to match the palette.
