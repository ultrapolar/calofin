---
name: calofin-checks
description: Decoding a failing check or test in the calofin repo - make check, make test, make parity, or any of check_lisp / check_scope / check_standards / check_lazdiag / check_handlers / check_leaks / check_writes / check_offered / check_input / check_values / check_tier_parity / check_osnap / check_color / check_perf / check_back / check_vb / check_dcl / check_registry, and the generator staleness checks (mirror_shared, release_lisp, build_shared_bundle, gen_ui_data, gen_ui_charts, gen_knobs, gen_ribbon_icons, gen_agents_md / a stale AGENTS.md). Use when a check is red, a test fails, or a tier has drifted, to find the cause and the fix without reading the checker's source.
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

### One session, one name

`LAZPASS.lsp` loads every tool into ONE AutoLISP session, where a second
definition does not fail — it silently replaces the first.

| Message | Cause | Fix |
| --- | --- | --- |
| `X is defined in both shared/parts/A and shared/parts/B` | two tools define the same function — at the top **or nested** inside another function, which is global the first time that body runs | rename one with its own prefix, or declare a nested helper among its enclosing defun's locals (` / X`) |
| `X is defined twice in shared/parts/A` | one file defines it twice; the second wins | delete or rename one |
| `X is set to V by A and to W by B` | two files set one global to different values as they load; the later load wins for every tool | give each its own prefixed name, or make it a guarded default: `(if (not (boundp 'X)) (setq X ...))` |

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
| `<CMD> <- <store> (form answers) does not report ...` | a command a form runs (its `X:run-with-answers` sets `<store>`) does not write that store into the transcript, so a form-driven report cannot be replayed | `--fix` adds `(if lzd:state (lzd:state '(<store>)))` after the `lzd:begin`; add any run flag the form also sets by hand |
| `<CMD> has no *error* handler to report from` | **`--fix` will not write this** | write the handler yourself, then re-run `--fix` |
| `the lzd:<kind> call <why>` | an injected call landed where it would change a meaning | move it so it is not the last form of a body, not a term of an `(and ...)`, and not a branch of an `(if ...)` |

Write the handler on the STANDARDS section 5 skeleton — see
`../calofin-lisp/reference/standards.md`. It is editorial on purpose:
which sysvars *this* command changed, whether an undo group is open,
what it drew that has to be swept. A handler that puts back the wrong
thing is a bug the drafter meets in the **next** command they run.

`--fix` prints the regeneration commands after wiring; run `retier.sh`.

---

## `check_handlers.py` — every handler reaches its end

An `*error*` handler is the only code that runs on Esc. When it dies
part-way the drafter sees nothing wrong: no report, no FAIL in the log,
the undo group left open, the error mode left pushed. The check reads
each handler in evaluation order, helpers spliced in, under the error
mode its command put in force, and names the first form that cannot
work there. Reads all three tiers.

| Rule | Cause | Fix |
| --- | --- | --- |
| H1 | a command that pushes `*push-error-using-command*` has a handler calling a helper **declared in the command's arglist** — undefined once AutoCAD resets the evaluator | make it a top-level defun over global state |
| H2 | ...or reading a **command local** (directly or through a helper) — under a push it reads the GLOBAL, normally nil, so the cleanup keyed on it is skipped | keep what the handler reads in prefixed globals reset at the top of the run, before the push — or drop the push |
| H3 | `command-s` while the mode is still pushed — refused past any `vl-catch-all-apply` (SPA's death) | pop first, or use ActiveX (`vla-put-ActiveDimStyle`, `vla-EndUndoMark`) |
| H4 | a bare `(command)` in a default-mode handler (no push, or after the pop) — refused | `command-s`, or ActiveX |
| H5 | a command that ran `lzd:begin` calls a defun with its own `*error*` and `lzd:begin` — a failure in there runs ONLY the inner handler | do the outer's cleanup before the hand-off; accepted pairs go in `tools/handler_baseline.txt` with a reason. `LOG-MISFILED` on top means the outer began under a name that is not its command's: LAZDIAG joins an inner run to the outer only when CMDNAMES still names it, so begin under the command's own name |
| H6 | a pushing command pops (through its finish) and then `(exit)`s — the handler runs again with nothing to pop | end with `(princ)`, or guard the second pass |

---

## `check_leaks.py` — what a run borrows comes back

Every way out of a run -- each early exit, the handler, a hand-off to another command -- gives back what the run holds. Reads all three tiers.

| Rule | Cause | Fix |
| --- | --- | --- |
| EXIT / HANDLER / BYPASS / STALE / SIBLING / ERRNO / HANDOFF | one way out of a run skips a release, and the drafter meets it in the NEXT command. EXIT: an early exit leaves the undo group, the error mode, the LAZDIAG run or a sysvar held; the finding names the exit ('still held on the way out at ...'), and a release under `(if rows ...)` does not count for the no-rows path. HANDLER: `*error*` does not put back what was held at a prompt, or dies at `command-s` under the push first. BYPASS: a c: command, or a helper with its own `*error*`, is called while holding them, so an Esc in there runs only ITS handler. STALE: a flag or snapshot a dead run can leave set is read by the next run before it writes it. SIBLING: the same, but nothing in the tier ever clears it while other tools clear the same thing. ERRNO: read with no reset. HANDOFF: `(command "X")` of an AutoLISP command | close or restore ONCE in the common tail after the `cond`, not per branch, under the acquire's own flag; put it back from the handler; restore before the hand-off, or call the scan's handler-less core; reset the global at the top of the run, beside its siblings, and in the handler; `(setvar "ERRNO" 0)` before the pick; call `(c:X)`, or queue it with `vla-SendCommand`. A site that is genuinely fine goes in `tools/leaks_baseline.txt` as `file|defun|RULE|resource|reason`. `*` as the defun is allowed only on a STALE/SIBLING line, for a global kept between runs on purpose. A line nothing matches, or a malformed one, fails the run |

## `check_writes.py` — a write nobody looks at

An entmod, entdel or edit command on the drafter's own objects answers nil on a locked layer and changes nothing -- quietly. Reads all three tiers.

| Rule | Cause | Fix |
| --- | --- | --- |
| W1 / W2 / stale baseline line | W1: a layer maker (an entmake of a LAYER record, or `vla-Add` on the Layers collection) never clears bit 4 when the layer is already there, so what the tool draws on it can never be erased. W2: an entmod / entdel / caught `vla-` write, or an edit command, on an object this run did not make, answer thrown away, then COUNTED (`(1+ n)`, `cons`, `ssadd`, a returned `T`) or CLAIMED ("erased", "moved", "marked") in the next statements -- or, for a write inside a loop, in the statements after the loop. A locked layer refuses the write without a word, so the report is false. `stale baseline line ... what it rests on is gone`: the `needs=` code a `write_baseline.txt` line names has left its defun, so the reason the site was accepted no longer holds | W1: clear bit 4 of group 70 when the layer exists (the `pool:rulerlayer` idiom), or `vla-put-Lock ... :vlax-false` after the `vla-Add`. W2: count on the answer, `(if (entdel e) (setq n (1+ n)) (setq stuck (1+ stuck)))`, and say what stayed; or unlock the selection's layers for the run BEFORE the write (not behind a question the drafter can refuse) and relock them; or stop when a lock reader says locked. `--list` shows why every other write passed (TABLE / FRESH / SCREENED / GATED / OBSERVED). A site that is genuinely fine goes in `tools/write_baseline.txt` as `file|defun|what|needs=TOKEN[@DEFUN]|reason`, where the token is the code that makes it fine. A real defect is fixed, never baselined. For a stale line: put the gate back, or delete the line and fix the site |

## `check_offered.py` — an answer the prompt never offered

Reads **all three tiers**, `releases/` included, like `check_osnap`. What a prompt hands back WITHOUT a keystroke is the code's own choice, and nothing in AutoCAD checks it: Enter's default, a remembered answer, a LAZTUNE knob, a form's stored answer.

| Cause | Fix |
| --- | --- |
| **E**: a knob, a literal or a registry-read global reaches a keyword prompt's Enter answer unchecked (FITABHD's `<radius>`) | canonicalise it where it is USED: `(cond ((x:kwcanon knob '("Square" "Radius"))) ("Radius"))`, the `pool:treat-canon` / `ptr:dircanon` shape. A member test that only picks a branch is no guard |
| **N**: a knob reaches Enter at a number prompt that refuses zero or negatives, either through its initget bits or through the code's own `(if (or (not v) (< v 1)) (setq v knob))`, with no LOWER bound on the way | vet the knob BEFORE the prompt shows it: `(if (not (and (numberp d) (> d 0))) (setq d <shipped>))` at the top of the helper. An upper-only clamp does not count. A clamp on the Enter branch alone does not count either: it shows `<1500>` and takes 1.0 |
| **T1**: a bit-128 typed word is compared with one the prompt never offers, or offers only under a condition | gate the compare on whatever offers the word, or have every caller test the sentinel |
| **T2**: a bit-128 answer is used as a point or a number without a `(type v)` test | test `(type v)` first |
| **S**: a form's stored answer stands in for the prompt, taken raw | vet it the way the prompt would |
| **I**: the initget is outside the loop that re-asks | move the initget inside the loop |

A site that is right on purpose goes in `tools/offered_baseline.txt` as `file|defun|RULE word|reason`. A real defect never does. `--all` also lists the advisories (what the trace could not follow, never fatal) and the baselined sites.

## `check_input.py` — a miss, and a space

A click on empty paper at an `entsel` answers nil exactly as Enter does. Only ERRNO 7 tells them apart, and a read means THIS pick only when ERRNO was zeroed right before it. At every input but `(getstring T ...)` the spacebar is Enter. Reads all three tiers.

| Rule | Cause | Fix |
| --- | --- | --- |
| PICK | an `entsel`'s nil DECIDES something (ends a loop, takes the default, skips the offer or the item), so a click just beside the thing is taken as Enter with nothing said. A nil that only speaks passes only if the SAME question comes round again: a `while` that does not move its own test on, or a recursive call. A `foreach`, `repeat` or `mapcar` asks about the next item | put `(vl-catch-all-apply 'setvar (list "ERRNO" 0))` right before the pick, and a clause `((and (null sel) (= 7 (getvar "ERRNO"))) (princ "...nothing there..."))` ahead of the `((null sel) ...)` that stays Enter's (`ptr:ask-perim` is the pattern). "Enter should mean what it says" is not a baseline reason, because the zero-and-7 keeps Enter as it was. A line in `tools/input_baseline.txt` is only for a miss that costs no more than the retype and says so |
| STICKY | ERRNO is read after a pick but does not answer for it: it was not zeroed before the pick in that same pass (an earlier miss's 7 turns a real Enter into "Nothing there"), or it was zeroed again between the pick and the read (the 7 is wiped) | zero it inside the loop, right before the pick, and nowhere between the pick and the read. A helper with no loop of its own may leave the zero to every caller, right before the call. Never baselined |
| SPACE | a prompt, hint or caption shows `44 1/2` or `4'-4 1/2"`, or a prompt shows `1524 MM`, where the spacebar is Enter, so it arrives as two answers | dash it (`44-1/2`, `4'-4-1/2"`) or close the unit up (`1524mm`). A `(getstring T ...)` prompt is exempt, unless the same file reads text at an `(initget 128)` prompt |

## `check_values.py` — a value AutoCAD does not promise

| Rule | What the red means | Fix |
| --- | --- | --- |
| rtos-ftin | rtos text in feet and inches reaches the DRAWING: an entity's group 1 or 3, a TextString, a TEXT/MTEXT/LEADER command, or the text after "_T" in a DIM command. The finding names how it gets there. The mode is 3 or 4, a knob that nothing on the way sends elsewhere, or omitted (LUNITS). rtos follows DIMZIN, so at 0, 2 or 8 a whole foot is written `15'`, which SPACHECK, COVERCHECK and LINFINCHECK reject. Prompts and princ are never flagged. | Spell it with the tool's own `<prefix>:ftin`: a copy of `cal:ftin` taking rtos's arguments, plus one mirror_shared swap line. A knob or LUNITS mode goes behind `(if (member m '(3 4)) (x:ftin v m p) (rtos v m p))`. Never bind DIMZIN. A label the command removes on every path out is baselined, with the removal named. |
| rtos-shape | CDATE through rtos, or rtos text cut with `substr` or `vl-string-search`, or `read` back. DIMZIN 8 and 4 move the digits. | Decode CDATE arithmetically (`cal:datestr`). Slice numbers, not text. |
| rtos-bound | A max, min, between or or-less limit printed with round-to-nearest inside the loop that asks again against it. rtos, a `:ftin` call and the file's own formatters all count. A max that rounds up is refused when typed back. | `(rtos (x:floor-shown cap))` for a max, `x:ceil-shown` for a min. Do not widen the test. |
| vl-sort-dedupe | The comment trusts `vl-sort` to drop duplicate REALS, but it drops only EQ items (integers, symbols). | Skip `r` when `(equal r prev 1e-9)` after the sort. |
| getobject-nil | A `vlax-get-object` or `vlax-create-object` result is tested with `vl-catch-all-error-p` alone. Nothing running, or nothing registered, answers nil. | Add `(null v)` beside the test, or a `((null v) ...)` clause before the one that uses v. |
| typed-angle | angtos is typed into `(command ...)` in a file that never borrows ANGBASE, ANGDIR and AUNITS. | Borrow and zero all three for the run, and restore them on both paths. |

A site that is genuinely right goes in `tools/values_baseline.txt`, one line per site with its reason. Identical sites pair with lines in order. `--update-baseline` writes new sites as UNREVIEWED, and neither that nor an empty reason passes. The check reads lisp/ plus the three hand-edited shared/parts files.

## `check_tier_parity.py` — both builds read the same things

A helper `mirror_shared.py` swaps for a `cal:` one must read the same knobs, profile keys and sysvars as the library's, or a setting works in one build and not the other.

| Rule | Cause | Fix |
| --- | --- | --- |
| finding | the two builds read different things where `mirror_shared.py` swaps a helper for a `cal:` one, or a hand-kept twin has drifted. The tag says which. **P1** `standalone-only`/`grouped-only` + `global:` (a LAZTUNE knob such as `lin:*back-words*`, or a sibling's knob), `env:` (a profile key such as `CalofinInk-*`), `sysvar:` (a typed expand list, as with SPACHECK's CLAYER, or a DIM* in a snapshot table), `implicit:` (rtos/angtos reading DIMZIN, or LUNITS/LUPREC when the mode or precision is left out), `sym:` (a Back sentinel), `effect:`/`fn:` (a LAZDIAG hook). **P2**: the twin names a knob fewer times than lisp/. **P3**: a twin `(cal:X ...)` with the wrong argument count, `'(lambda ...)` bodies included. **P4**: a dropped table or a swapped-away slot (`tool:*sysold*`) still named in the twin, or a knob the mirror drops or renames. **P5**: a hand twin (LISPLAB) whose code, not its prose, differs from lisp/, usually a LAZDIAG hook `check_lazdiag --fix` put only in lisp/. **P0**: the mirror refused the twin | fix the Lisp or the mirror entry: keep the helper local (drop the swap), give both bodies the same read, pass the knob through a collapse/expand, or add the `symbols` rename, then `retier.sh <TOOL>`. For P5, copy the lisp/ lines into the hand twin. `--list TOOL` prints both footprints. Only a genuinely harmless P1/P2 goes in `tools/tier_parity_baseline.txt`, under the key the check prints (the TOOL's own src\|helper\|atom\|reason). P0 and P3-P5 never do |

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
| the save is in a helper's own local | move it to a local **of the command**, or to `tool:*sysold*` — the handler is nested inside the command and can only see what the command can. **If the command pushes `*push-error-using-command*`, only the global works**: a pushed handler sees no locals at all |

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
