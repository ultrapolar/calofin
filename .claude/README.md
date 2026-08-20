# Claude Code setup for calofin

Two layers, and they do different jobs. The **cloud environment** is
configured once in the Claude Code web UI and cached in the container
image. The **SessionStart hook** in this folder is checked into the
repo and runs at the top of every session, cloud or local.

```
.claude/hooks/session-start.sh   runs per session: env vars, orientation, drift check
.claude/settings.json            registers the hook; allowlists the repo's own checkers
tools/check_standards.py         the drift check itself - also runnable by hand or in CI
```

## Cloud environment: variables

Set these in the environment's **Environment variables** panel:

| Variable | Value | Why |
| --- | --- | --- |
| `PYTHONDONTWRITEBYTECODE` | `1` | keeps `__pycache__` out of the tree |
| `PYTHONUNBUFFERED` | `1` | test output arrives as it happens, not in one lump at the end |

That is the whole list, and the shortness is the point: the suite runs
on the Python standard library alone. `tests/lispvm.py` is a
pure-Python AutoLISP interpreter, so there is no pip, no node, no
AutoCAD and no Blender to install or license.

The hook sets both of these too, via `$CLAUDE_ENV_FILE`, so a local
session gets them without the web UI. Setting them in the panel as
well is belt and braces - they then apply even if the hook is skipped.

### One variable to leave unset

**Do not put `CALOFIN_LISP_ROOT` in the panel.** Unset, it means
"read `lisp/`", which is what every test must do by default. Exported
globally it silently points the whole suite at `shared/`, and a
regression in the standalone build stops showing up. It is a
per-command override:

```
python3 tests/test_pool_runtime.py                        # standalone
CALOFIN_LISP_ROOT=shared python3 tests/test_pool_runtime.py   # grouped
```

Running both is the parity check that keeps the two builds honest.

## Cloud environment: setup script

Paste this into the environment's **Setup script**. It installs
nothing - it proves the container can run the suite, once, at build
time, so a broken image is caught before a session starts rather than
halfway through one:

```bash
#!/bin/bash
set -euo pipefail

python3 --version

# The tree is in the shape STANDARDS.md describes...
python3 tools/check_standards.py

# ...and the grouped build really does load as one session.
python3 tests/test_shared.py

echo "calofin: container ready (stdlib only, nothing to install)"
```

If you would rather the container build stay fast, drop the
`test_shared.py` line - the hook's drift check still runs every
session.

## What the hook does

It is synchronous and finishes in well under a second, because it has
nothing to download. Each session it:

1. exports the variables above through `$CLAUDE_ENV_FILE`,
2. prints the tier map with live file counts, the rules that bite, and
   the commands for checking and testing,
3. names the two tests that fail on a clean checkout
   (`test_pool_form.py`, `test_spa_form.py`) so nobody spends a session
   "fixing" a known gap,
4. runs `tools/check_standards.py` and, if the tiers have drifted,
   says so at the top of the session instead of in review.

It warns but never blocks: a drifted tree still opens, it just opens
loudly.

The hook is not gated on `CLAUDE_CODE_REMOTE`, so local sessions get
the same guardrail. To make it web-only, uncomment the guard near the
top of `session-start.sh`.

## What the drift check enforces

`tools/check_standards.py` covers the failures that only happen
*between* files - the ones `check_lisp.py` and `check_scope.py` cannot
see, because they read one file at a time:

- every tool in `lisp/` has a twin in `shared/`
  (`acady-loader.lsp` is the one deliberate exception - the grouped
  build replaces it with `CALOFIN-LOADER.lsp`),
- only `CALOFIN-LIB.lsp` defines `cal:` symbols,
- no two files in `shared/` define the same function, since they all
  load into one session,
- no command is lost between the tiers,
- `CALOFIN-LOADER.lsp` lists every file beside it,
- a versioned file's dated twin in `releases/` is not stale,
- `wip/`, once it exists, holds drafts and no dated releases.

Each failure prints the fix. Run it by hand any time:

```
python3 tools/check_standards.py
```
