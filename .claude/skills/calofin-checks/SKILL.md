---
name: calofin-checks
description: Decoding a failing check or test in the calofin repo - make check, make test, make parity, or any of check_lisp / check_scope / check_standards / check_lazdiag / check_osnap / check_color / check_perf / check_back / check_vb / check_dcl / check_registry, and the generator staleness checks (mirror_shared, release_lisp, build_shared_bundle, gen_ui_data, gen_ui_charts, gen_knobs, gen_ribbon_icons, gen_agents_md / a stale AGENTS.md). Use when a check is red, a test fails, or a tier has drifted, to find the cause and the fix without reading the checker's source.
---

# Decoding a calofin check failure

Ten checks, seven generator staleness checks, and a test suite. Each
exists because a specific defect shipped. This maps the message to the
cause to the fix.

**First, scope it.** `make check` takes minutes. If you know which file you
changed:

```bash
bash .claude/skills/calofin-lisp/scripts/precheck.sh lisp/<tool>/<TOOL>.lsp
```

Several checks take `--list` (what they cover) or `--tier lisp|shared|releases`.
`check_lisp` and `check_scope` take a file path. The rest read the tree.

---

## "generated tiers current" failures — nearly always this

`check_standards.py` says a tier has drifted, or
`mirror_shared.py --check` / `release_lisp.py --check` /
`build_shared_bundle.py --check` / `gen_*.py --check` exits 1.

**Cause:** you edited `lisp/` and did not regenerate, or you hand-edited
a generated file.

**Fix:**
```bash
bash .claude/skills/calofin-lisp/scripts/retier.sh <TOOL>
```

If it says a *twin* differs and you did not touch `lisp/`, you edited
the twin by hand — regenerating will discard that edit. Move the change
into `lisp/<tool>/` first, then regenerate. The only hand-edited files
under `shared/` are `CALOFIN-LIB.lsp`, `CALOFIN-LOADER.lsp` and
`parts/LISPLAB.lsp`.

`check_standards.py` also compares the two **version banners**, so a
twin left behind while `lisp/` moved on fails here rather than passing
quietly — that is the `shared/parts/SPA.lsp` bug it was written for.

---

## `check_lisp.py` — per-file statics

Hard failures (exit 1):

| Message | Cause | Fix |
| --- | --- | --- |
| unbalanced parens / extra `)` | a torn edit | count from the last defun you touched; `lspshow.py --map` shows where forms start |
| unterminated string literal | a stray `"` | — |
| bare atom or string at top level | a torn edit AutoLISP would silently swallow | wrap or delete it |
| `(if ...)` with more than 3 args | a missing `progn` | `(if c (progn a b))` |
| `(setq ...)` with an odd arg count | a dropped value | — |
| call to an undefined function in the file's own namespace | typo, or a helper you deleted | — |
| quoted `'tool:fn` the file never defines | the dispatch-table typo no runtime path reaches | — |
| **no load banner** | nothing after the last defun `princ`s | add the guarded banner (below) |
| **load banner is not quiet inside the build** | banner not wrapped | wrap it |
| unguarded `_Begin` (rule 3) / unguarded `_End` (rule 3c) | undo bracket not conditional | guard **both** halves on `UNDOCTL` |
| `*error*` not declared by its enclosing command | a handler that outlives its command | add `*error*` to the ` / ` locals |
| a `*push-error-using-command*` with no pop outside the handler | the mode stays stacked for the session | pop on every success exit too |

The banner, exactly:

```lisp
(if (not *calofin-quiet*)
  (princ (strcat "\nTOOLNAME " *toolname-version*
                 " loaded.  Type TOOLNAME to run.")))
(princ)
```

Advisories (printed, never fatal — cross-file references make them
unreliable): reads of an own-prefix global the file never `setq`s, and
defuns nothing in the file calls.

---

## `check_scope.py` — locals

**Message:** a variable is set but not declared.

**Fix:** add it after ` / ` (space each side) in the defun's arglist.
Remember AutoLISP symbols are **case-insensitive** — `sP` IS `sp`, and
the check has a case-collision rule for exactly that.

Genuine module globals live in `tools/scope_baseline.txt`. Add to that
file only when the symbol really is a module global, not to silence a
missing declaration.

---

## `check_lazdiag.py` — every command reports its failures

| Message | Meaning | Fix |
| --- | --- | --- |
| `... does not report failures to LAZDIAG` | a missing `lzd:` call site | `python3 tools/check_lazdiag.py --fix` |
| `<CMD> has no *error* handler to report from` | **`--fix` will not write this** | write the handler yourself, then re-run `--fix` |
| `the lzd:<kind> call <why>` | an injected call landed where it would change a meaning | move it so it is not the last form of a body, not a term of an `(and ...)`, and not a branch of an `(if ...)` |

Write the handler on the STANDARDS section 5 skeleton — see
`../calofin-lisp/reference/standards.md`. It is editorial on purpose:
which sysvars *this* command changed, whether an undo group is open,
what it drew that has to be swept. A handler that puts back the wrong
thing is a bug the drafter meets in the **next** command they run.

`--fix` prints the regeneration commands after wiring; run `retier.sh`.

---

## `check_osnap.py` — the drafter's object snaps

Reads **all three tiers**, `releases/` included, because a dated twin is
what a shop pins to and it only gets a fix when `release_lisp.py` re-runs.

| Cause | Fix |
| --- | --- |
| a command mutes OSMODE and does not restore it before returning | add the restore at the bottom |
| ...and does not restore it from `*error*` | **the half that matters** — Esc is the likeliest way out and never reaches the bottom |
| the restore sits **behind** something that can throw in the handler | move the `setvar`s to the top of the handler; an error inside `*error*` skips every later line. A bare `(command ...)` can throw |
| the snapshot is dropped behind a form that can throw | move the drop ahead of it, or every LATER run restores this run's OSMODE |
| a sysvar table lists `OSMODE` but the tool never mutes it | **remove it** — listing it hands the drafter the opening snapshot over any snap they ticked mid-run |
| the save is in a helper's own local | move it to a local **of the command**, or to `tool:*sysold*` — the handler is nested inside the command and can only see what the command can |

---

## `check_color.py` — CECOLOR, CLAYER, and where ink may go

Same audit as `check_osnap`, for the two settings every line the drafter
draws *next* is born with — plus the ink rule:

| Cause | Fix |
| --- | --- |
| a command moves CECOLOR/CLAYER and does not put it back on both paths | restore on the clean exit AND from `*error*`, ahead of anything that can throw |
| a sysvar table lists one the tool never moves | remove it |
| **an `ink` call is an argument of a call that makes a LAYER** | pass a plain ACI **number** — a layer record outlives the command and colours everything ByLayer on it for whoever opens the drawing next |
| **a knob that colours a layer is not a number** | make it a number where its block sets it |

The rule in one line: **a theme colour reaches a CUE only** — something
the command draws and takes away again. Anything still in the drawing
when the command returns takes a number. Both stay knobs; `LAZTUNE`
retunes either.

---

## `check_perf.py` — an `'auto` colour resolved inside a loop

`ink` answers a `'fade` or `'guide` role by **measuring the drawing's
background** — a `vla-get-GraphicsWinModelBackgrndColor` COM round trip.
Resolved outside a loop that costs once per run; resolved inside one it
costs once per iteration, and the review tools touch every entity in the
drawing.

The other roles never reach that measurement: `dim`/`hi` follow the
interface theme, and the eight kind-roles (`flag`, `arc`, `olap`,
`orig`, `sugg`, `point`, `constr`, `report`) are plain constants. A
numeric knob or a CALSET override short-circuits it too. **So the check
fires on `'fade` and `'guide` only.**

**Fix:** hoist it into a local before the loop.

```lisp
(setq grey (tool:ink tool:*grey-color* 'fade))   ; once
(foreach e ents (tool:set-color e grey))
```

It is a **call-graph** check, not a lexical one — it reuses
`check_osnap.py`'s reach machinery. So the ink call does not have to be
written inside the loop to fail: a loop calling a helper one `defun`
away, whose body resolves the role, fails too. That is exactly what
DIMCHECK, COVERCHECK and LINFINCHECK did — each had an `unstage` helper
re-resolving the grey on every call instead of taking the value its
caller had already hoisted.

Being syntactic, it misses leniently: a role passed through a variable
rather than written `'fade`/`'guide` is not flagged. It never fails
wrongly. `--tier` and `--list` as usual.

## `check_back.py` — one-way prompts

**Message:** a prompt offers no Back and is not accounted for.

**Fix:** offer Back (a helper taking a `back` argument counts — that is
the repo's idiom for "the caller decides"), or add a line to
`tools/back_baseline.txt` **with the reason**. `--update-baseline`
rewrites it, but a new one-way prompt is supposed to be a decision
somebody made, so write the reason.

The first question of a command never offers Back, and that is fine.

---

## `check_registry.py` — a half-registered tool

**It has no line of its own in the Makefile**: `check_standards.py`
imports it and calls `check_registry.check()`, so a registration gap
surfaces as a `check_standards` failure. `precheck.sh` runs
`check_standards`, so it is covered in the inner loop too.

A tool must be registered in six places: a caption and a placement in
`LAZPANEL.lsp`, a slot in `CALOFIN-LOADER.lsp`, a row plus derived
counts in `README.md`, a tooltip in `ui/calofin_net/blurbs.txt`, and a
name in `ui/calofin_ui/calofin.lsp`'s probe list.

**Fix:** `python3 tools/check_registry.py --fix`. It inserts the caption
row and a `Rest`-page placement, rewrites every derived count, and bumps
LAZPANEL's banner — then **names the three things it will not decide**:

1. the **caption text** (editorial),
2. the **category page** — `Layout`/`Points`/`Dimensions`/`Converters`/`Checking`,
3. the **tooltip blurb** in `blurbs.txt`.

Write those three and re-run. `test_lazpanel.py` refuses to go green on
an empty caption. Then `python3 tools/gen_ui_data.py` — the palette and
ribbon catalogs are generated, so a tool on the panel is in the palette
by construction.

See the `calofin-new-tool` skill for the full add/remove sequence.

---

## `check_dcl.py` — a dialog that will not open

DCL does not scroll. A dialog taller or wider than the screen makes
AutoCAD **refuse to open it** and the command dies where it stands.

**Cause:** a generator grew — usually because a tool was registered and
landed on the `Rest` page, which is the page every new tool joins.

**Fix:** the pages wrap into balanced columns at `lzp:*colbudget*` in
`LAZPANEL.lsp`; the two strips a drafter grows (Pinned, Recent) are
capped both at the tick and on the way in. Adjust the budget or the cap.
`--list` shows what it measured; `tools/dclsize.py` does the measuring.

---

## `check_vb.py` / `check_netapi.py` — the palette

`check_vb.py` reads the palette **as code** for a tree with no VB
compiler: blocks closed by the right closer, quotes and parens balanced,
every member and constructor arity of the assembly's own types resolved,
and every bare framework type (`SystemColors`, `Registry`) brought in by
an `Imports`.

`check_netapi.py` is the half `check_vb` cannot see — does this AutoCAD
type really have this member, and is it in a referenced package. It is
**opt-in**: with no `--refs <dir>` it lists what it would check and
exits 0, so `make check` does not run it. Run it on a machine that has
AutoCAD, before a build.

Never hand-edit `ui/calofin_net/Generated/`,
`ui/calofin_ribbon/Generated/` or `ui/calofin_ribbon/icons/` — re-run
`gen_ui_data.py`, `gen_ui_charts.py`, `gen_ribbon_icons.py`.

`gen_ribbon_icons.py --check` also fails on an **orphan**: a glyph for a
routine that is no longer featured. A name in `gen_ui_data.FEATURED`
needs a glyph in `gen_ribbon_icons.DESIGN`, and the check fails both ways.

---

## `gen_agents_md.py --check` — a stale agent router

**Cause:** you edited a skill under `.claude/skills/` — added, renamed,
re-described, or dropped a script or reference file beside one — and
`AGENTS.md` still routes to the old shape. Or you hand-edited
`AGENTS.md`, which is generated.

**Fix:** `python3 tools/gen_agents_md.py`.

`AGENTS.md` is what non-Claude agents (Codex, Jules, Aider…) read;
Claude Code finds `.claude/skills/` by itself and never reads it. It is
a **router**, not a second copy — the detail stays in the skills, so
there is no duplicated prose to drift. To change what it *says* rather
than what it lists, edit the `HEADER`/`RULES`/`PIPELINE` constants in
`tools/gen_agents_md.py`, not the output.

`tests/test_agent_docs.py` holds the rest: every skill and script
reaches the router, every path it names exists, and the branch it names
is the one CLAUDE.md pins.

## `gen_knobs.py --check` — a knob not on offer

**Cause:** you added a knob to a tunables block. It is not offered to a
drafter through `LAZTUNE` until the catalog is regenerated.

**Fix:** `python3 tools/gen_knobs.py` (in `retier.sh`). It writes
`lzp:*knobs*` and `lzp:*knobfam*` — the latter is which knobs are ONE
shop decision spelled in several tools, so "Set everywhere" can move all
twelve copies of the survey-point layer at once.

---

## Tests

**Nothing under `tests/` is expected to fail on a clean checkout.**
`EXPECTED_FAILURES` in `tools/run_tests.py` is the authoritative list
and it is **empty** — so a failure IS your change. (An entry there that
starts *passing* also fails the run, until it is removed.)

| Symptom | Cause |
| --- | --- |
| `SCRIPT EXHAUSTED at <kind> prompt` | the command asked more than the test scripted — you added a prompt |
| `N scripted answers left over` | it asked fewer — you removed a prompt or changed a branch |
| `returned with N undo group(s) still open` | an unbalanced `_Begin`/`_End` |
| `returned with the error mode still pushed` | a `*push-error-using-command*` not popped on the success exit |
| passes on `lisp/` but fails on `shared/` | a twin/mirror problem — a helper swapped that the library does not reproduce exactly, or a Back sentinel not moved to `CAL-BACK` |
| a `test_*_form.py` fails after a prompt edit | **fix the form, never the canonical routine** |
| `test_ruler_copies.py` fails | an embedded ruler copy was edited — change `CALOFIN-LIB.lsp` and copy out |

Run one tier, then both:

```bash
python3 tests/test_<tool>.py
CALOFIN_LISP_ROOT=shared python3 tests/test_<tool>.py
make parity
```

Never export `CALOFIN_LISP_ROOT` — it points the whole suite at
`shared/` and hides standalone regressions.
