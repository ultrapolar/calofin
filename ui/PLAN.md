# Making the palette real

> **DONE, 2026-08-27.** Both halves shipped: `pool:*form*` /
> `pool:run-with-answers` and `spa:*form*` / `spa:run-with-answers`
> exist in the canonical routines, `tests/test_pool_form.py` and
> `tests/test_spa_form.py` pass at both tiers, and the palette has
> been reconciled with what SPA actually asks. The design below
> (D1-D6) is what got built, including the wrapper that keeps
> `askkw` at five arguments and the consume-once rule that stops
> `Back` deadlocking - both of which earned their place. Kept as the
> record of why the shape is what it is.
>
> Three things went further than this plan scoped. The store reaches
> POOL's gate questions too (`crec`, `mirror`, `perfect`, `cmode`,
> `gcross`, `dstyle`, `sstyle`), the three step routines have stores
> of their own with a step **count**, and the zero-install DCL forms
> - `LAZFORM`, `LAZSPA`, `LAZSTEP` - now drive all five routines
> without a DLL. The "out of scope" list at the foot of this file is
> still accurate about what was deliberately left alone, except that
> palette catalog drift has since been fixed.

An execution plan for the week of 2026-08-24. Scope: close the gap
between `ui/calofin_net/` and the canonical `lisp/pool/POOL.LSP` /
`lisp/spa/SPA.LSP`, so the two failing form tests go green and the
palette's forms actually drive the routines. No new palette surface.

## What is built today

| Layer | State |
| --- | --- |
| Palette shell — `CalofinPalette.vb`, `CommandsTab` | **done.** Dockable, grouped buttons, greys out what this session has not loaded |
| Availability glue — `ui/calofin_ui/calofin.lsp` | **done.** `calofin:loaded` reports which `C:` names exist |
| Wire format — `LispBridge.vb` | **done.** Alist literal, invariant-culture numbers, three-state nil handling |
| Shape art + field maps — `assets/` | **done.** 12 shapes, 12 bottoms, fractional field positions |
| Form views — `SpaFormView.vb`, `PoolFormView.vb` | **done.** Collect answers, build the call |
| **The receiving end in Lisp** | ~~**does not exist**~~ — **built**, see the note at the top |

## The finding

The README calls the two failing tests a prompt-sequence divergence
between the palette and "an earlier fork" of POOL/SPA. That is half the
story, and the smaller half.

`spa:run-with-answers`, `pool:run-with-answers`, `spa:*form*`,
`pool:*form*` and `pool:fkeyof` appear in `ui/calofin_net/*.vb`, in
`ui/calofin_net/README.md`, in `STANDARDS.md` and in the two tests.
They appear in **no `.lsp` file, on any branch, at any commit**:

```
git log --all -S "run-with-answers" -- '*.lsp' '*.LSP'   # no results
git log --all -S "spa:*form*"       -- '*.lsp' '*.LSP'   # no results
```

The VB assembly formats a call on a function that was never written.
Whatever fork it was built against is not in this repository's history.
So this is not a reconciliation of two drifted implementations — one
side is missing, and next week's job is to write it.

That is good news for sizing. There is no divergent fork to merge, no
archaeology; there is a documented contract with a complete caller and
an unbuilt callee, and the contract is small.

Two independent breaks, not one. Beyond the missing hook, the tests'
scripted answers are themselves stale — the prompts-only halves fail on
their own:

```
SPA : getkword: 'No' not among 'Watersedge Coversize'
      at "Is this drawing at the water's edge or the cover size"
POOL: getdist: Enter not allowed at "G - hopper length, 0 = slope bottom"
```

Canonical SPA now selects a Spa Cover Details block and asks
Watersedge/Coversize before the shape question; the scripts predate
both. Fixing the hook without re-scripting leaves the tests red.

## Done means

1. `python3 tests/test_spa_form.py` passes.
2. `python3 tests/test_pool_form.py` passes.
3. Both pass at the grouped tier too:
   `CALOFIN_LISP_ROOT=shared python3 tests/test_*_form.py`.
4. `python3 tools/check_standards.py` clean; `check_lisp.py` and
   `check_scope.py` clean on both touched files.
5. `README.md` and `CLAUDE.md` lose the "known failing on a clean
   checkout" carve-out, because it is no longer true.

Exit criterion 3 is the one that is easy to skip and expensive to skip.
The hook is new code in `spa:askseqb` / `pool:askseqb`, and those have
twins in `shared/parts/` — this is exactly the shape of drift that put
`shared/parts/SPA.lsp` two revisions behind.

## Design

### D1 — the store

One global per tool, an alist, set before the command runs and read by
the ask helpers:

```lisp
(setq spa:*form* '((mode . "Watersedge") (shape . "Rectangle")
                   (w . 84.0) (l . nil)))
```

`spa:run-with-answers` is a three-liner: set the global, call `c:SPA`,
clear it. The tests set the global directly and call `c:SPA`
themselves, so both entry paths must work — do not put logic in
`run-with-answers` that the direct path misses.

### D2 — the four hook sites

The keys live at different depths, which is why this is four small
changes rather than one:

| Site | Has a key? | Hook |
| --- | --- | --- |
| `spa:askseqb` `SPA.LSP:796`, `pool:askseqb` `POOL.LSP:601` | yes — `(car it)` | read the key before calling `asks`; 18 keyed items in SPA, 93 in POOL |
| `pool:askh` `POOL.LSP:675`, `pool:askdeep` `:3249`, `pool:askc2` `:3257` | no — land in locals | derive from the prompt's `"<letter> - "` prefix via a new `pool:fkeyof`; covers exactly `c`, `c2`, `d` |
| `spa:askkw` `SPA.LSP:708`, `pool:askkw` `POOL.LSP:563` | no | **not** a new argument — see D6. Wrap it: `spa:askkwf (key msg kws shown dflt back)` reads the store, else calls `spa:askkw`. 9 SPA call sites, 14 POOL (`pool:askyn` is one of them); only the three or four the form answers call the wrapper |
| `spa:askcorner` `SPA.LSP:1953`, `pool:askcorner` `POOL.LSP:2751` | label only | key off the label — `cornera-ty` / `cornera-sz` |

Hook the helpers, not the call sites. `spa:asks` and `pool:asks` are
the single distance chokepoints and `askseqb` is the only thing that
knows a key, so the whole distance surface is covered by one edit per
file.

`pool:fkeyof` must insist on the exact `"<letter> - "` shape. The
trap is real and has an address: `POOL.LSP:4535` calls `pool:askh`
with *"Total pool length (arc tip to arc tip)"*, no letter prefix.
`fkeyof` must return nil there and let it prompt. The four prompts
that *do* qualify are `"C - wall height (shallow depth)"`,
`"C2 - depth where the shallow floor meets the break"`, `"D - deep
depth"` and `"D - deep end depth"` — two spellings of `d`, both
correct.

One thing `ui/calofin_net/README.md` gets wrong: it says
`pool:askdeep` and `pool:askc2` re-ask through `pool:askh-prompt`
rather than `pool:askh`, so a value failing their range check cannot
spin forever. **`pool:askh-prompt` does not exist** in canonical POOL —
both re-ask through plain `pool:askh` (`:3254`, `:3262`). Do not add
it. Consume-once (D3) already gives that guarantee, for every hook
rather than these two: the second pass finds an empty store and
prompts. Fix the README instead.

### D3 — consume once

**A form answer is removed from the store when it is used.** Not
"marked used" — removed.

Without this, Back deadlocks. The user backs up from question 5 to
question 4, question 4 is form-supplied, the hook answers it
instantly, and the flow walks straight forward to 5 again. There is no
key the user can press to get out. Both `askseqb` and the corner loops
support Back, so this is reachable in normal use, not a corner case.

Consume-once also gives the range-check behaviour for free, and is
why the README's `pool:askh-prompt` split is unnecessary.
`pool:askdeep` and `pool:askc2` re-ask through plain `pool:askh` when
a value fails their range check; on the second pass the store is
already empty, so the user types the correction at the keyboard
instead of the form re-feeding the same bad number forever. One rule,
applied at one place, covering what the README solved with a second
entry point that was never built.

### D4 — clear the global, including on error

`c:SPA` `SPA.LSP:2803` and `c:POOL` `POOL.LSP:5932` both install an
`*error*` handler (`:2805`, `:5934`). The store must be cleared in
both the normal exit and the handler. A stale `spa:*form*` surviving a
cancelled run means the next command-line SPA silently answers itself
with last time's numbers — a wrong drawing with no error message,
which is the worst failure this feature can have.

### D5 — the three-state contract is the feature

Already specified in `ui/calofin_net/README.md` and already emitted
correctly by `LispBridge.NumPair`. Restating because the hook is where
it gets honoured or lost:

| In the form | On the wire | The hook must |
| --- | --- | --- |
| left empty | key absent | fall through and prompt |
| explicitly cleared | `(key . nil)` | return nil — same as `NA` — without prompting |
| filled | `(key . 84.0)` | return the value without prompting |

`(assoc key store)` distinguishes absent from present-nil; `(cdr
(assoc ...))` alone does not. Getting this backwards makes a
half-filled form either impossible or silent, and the half-filled form
is the entire point of the feature.

### D6 — the mirror pins `askkw`'s signature

`SPA` is in `tools/mirror_shared.py`'s `TOOLS` table and
`shared/parts/SPA.lsp` is **generated**. One of its swaps is
`spa:askkw` → `cal:askkw`: the twin drops the local `defun` entirely
and rewrites all nine call sites onto the library.

So `spa:askkw` cannot grow a sixth argument. `cal:askkw`
(`CALOFIN-LIB.lsp:38`) takes five, the two signatures are identical
today, and widening only the standalone one makes the generated twin
call the library with an argument it does not accept — a grouped build
that loads fine and dies at the first keyword question.

Hence the wrapper. `spa:askkwf` is not in the swap table, so the
mirror leaves it alone, while the `spa:askkw` call *inside* it is
rewritten to `cal:askkw` like any other — the wrapper works at both
tiers with no special casing. The same wrapper shape suits POOL, for
symmetry rather than necessity.

The three helpers that carry the distance hooks — `spa:asks` `:672`,
`spa:askseqb` `:796`, `spa:askcorner` `:1953` — are **not** swapped and
survive verbatim in the twin (`shared/parts/SPA.lsp:650`, `:761`,
`:1911`). Those edits mirror cleanly. Only `askkw` is constrained.

**POOL is not in `TOOLS`.** Its twin is hand-mirrored. Two files, two
different procedures — see Day 5.

## The week

### Day 1 — the recorder, and re-scripting

`tests/lispvm.py` already keeps `vm.prompts` as a `(prompt, answer)`
log (`:201`, `:229`), so the recorder is a dozen lines: drive the
command with a script, dump the sequence.

Add it as `tests/record_prompts.py`, then use it to rebuild the
`PROMPTS` and `RAD_PROMPTS` scripts in `test_spa_form.py` and the POOL
equivalents against canonical prompt order. Re-scripting by hand
against a 2,900-line and a 6,000-line file is where this week could
quietly lose two days; this makes it mechanical.

Land it as its own commit. It has value past this week — every future
POOL/SPA prompt change makes these scripts stale again.

**End of day:** prompts-only halves of both tests pass. Form halves
still fail; nothing to receive them yet.

### Day 2 — SPA

`spa:*form*`, `spa:run-with-answers`, hooks in `spa:askseqb` and
`spa:askcorner`, and the new `spa:askkwf` wrapper — **not** a widened
`spa:askkw`, per D6. Clear-on-exit and clear-on-error. Bump
`spa:*version*` `SPA.LSP:175`.

Regenerate the twin as you go (`python3 tools/mirror_shared.py SPA`)
rather than saving it for Friday. The `askkw` swap is the one thing
here that can look correct standalone and break grouped, and you want
that feedback on the day you write it.

SPA first because it is the smaller surface — 18 keyed items over 14
distinct keys, 3 shapes, and its shape roster already matches the
field map exactly (`Rectangle` / `OCtagon` / `ROund`).

**End of day:** `test_spa_form.py` green at the standalone tier.

### Day 3 — POOL

Same shape of change, plus `pool:fkeyof` and the three unkeyed depth
asks. 93 keyed items over 46 distinct keys. Bump `pool:*version*`
`POOL.LSP:109`.

The Pool tab only sends a bottom type and its depths — shape, corners
and cross dims stay at the command line — so the surface is narrower
than the key count suggests.

**End of day:** `test_pool_form.py` green at the standalone tier.

### Day 4 — pin the wire

The audit is done; it is in this document. Every key either field map
can send exists as a canonical key. There is nothing to reconcile:

| Form sends | Canonical | Verdict |
| --- | --- | --- |
| rectangle `w l` | `spa:askseqb` | matches |
| octagon `b a tt ss s1 s2 vv` | `spa:octflow` | matches |
| round `b a` | `spa:roundflow` | matches |
| `_secondOutline` `b2 a2 f2` | `spa:octflow` | matches |
| Pool `h g f e e1 e2 f1 f2` | `pool:askseqb` | matches |
| Pool `c c2 d` | `pool:askh` / `askdeep` / `askc2` | via `pool:fkeyof` |

Two SPA keys, `w2` and `l2`, are asked at the command line and never
sent by a form. That is allowed — the form fills what it can.

So Day 4 is not repair work, it is *pinning* work. Extend both tests
so that a key the form sends which the routine never reads is a
**failure**, not a value that vanishes silently. Walk the two
`fieldmap.json` files, walk the extracted key lists, assert the
first is a subset of the second.

That check is the deliverable. Without it, the alignment this document
records is true on Friday and unverified forever after — and a prompt
edit six months from now breaks the forms with no test to say so.

Budget the rest of the day for the `pool:fkeyof` prefix rules, which
are the fiddliest code of the week and want their own unit test:
`"C - wall height (shallow depth)"` → `c`, `"C2 - depth where..."` →
`c2`, both `D` spellings → `d`, and `"Total pool length (arc tip to
arc tip)"` → nil.

### Day 5 — mirror, regenerate, verify, document

Per `CLAUDE.md`, in one commit each:

```
python3 tools/mirror_shared.py SPA          # SPA is generated - never hand-edit its twin
#   POOL is NOT in TOOLS: shared/parts/POOL.lsp is mirrored by hand
python3 tools/release_lisp.py
python3 tools/build_shared_bundle.py
python3 tools/check_standards.py
python3 tools/check_lisp.py lisp/spa/SPA.LSP && python3 tools/check_scope.py lisp/spa/SPA.LSP
python3 tools/check_lisp.py lisp/pool/POOL.LSP && python3 tools/check_scope.py lisp/pool/POOL.LSP
python3 tests/test_shared.py
python3 tests/test_pool_runtime.py && python3 tests/test_spa_runtime.py
CALOFIN_LISP_ROOT=shared python3 tests/test_pool_runtime.py
CALOFIN_LISP_ROOT=shared python3 tests/test_spa_runtime.py
CALOFIN_LISP_ROOT=shared python3 tests/test_spa_form.py
CALOFIN_LISP_ROOT=shared python3 tests/test_pool_form.py
```

`TOOLS` currently holds `SPA`, `TUTORIALSPA`, `xftconv` and
`SPACHECK`. `POOL` is not among them, so its twin is hand-work: drop
the helper copies the library provides and rewrite those call sites
onto `cal:`, changing nothing else. If this is the second time you
have hand-mirrored POOL, add it to `TOOLS` instead — that is exactly
the trigger `CLAUDE.md` names, and POOL is the largest file in the
tree to keep doing by hand.

Then delete the carve-out. `README.md:269-275`, `CLAUDE.md:181-185`
and the KNOWN FAILING docstrings at the top of both test files all
describe a state that no longer exists.

## Risks

**The VB cannot be built or run here.** No `dotnet`, no AutoCAD, no
CI. `Calofin.vbproj` targets `net48` against AutoCAD.NET 24.3
reference assemblies. Everything above is verified through the Python
tests against the wire format — which is precisely why
`LispBridge.BuildCall` emits a printed literal instead of a
`ResultBuffer`. Keep the changes on the Lisp side of the wire wherever
there is a choice; anything that must change in VB is unverifiable
until someone opens AutoCAD.

**The audit above was wrong once already.** A first pass matched only
`REQ`/`SUG`/`ZER` items and reported the octagon's `tt ss s1 s2 vv` as
unmatched — they are `NAX` items, and they match fine. The corrected
pass is what the Day 4 table records. The lesson for next week: the
kind symbols in play are `REQ`, `SUG`, `ZER` and `NAX`, and any script
that extracts keys must accept all four. Re-derive rather than trusting
this table if a result surprises you.

**Back is the subtle one.** D3 is the whole of it. Write the
deadlock test before the hook: form-supply question 4, Back from
question 5, assert the user gets a prompt. It is a five-line test and
it will fail loudly if consume-once is ever refactored away.

**Two version banners, four generated tiers.** `check_standards.py`
compares banners across tiers, so a forgotten mirror fails the check
rather than passing quietly. Trust it, run it, do not batch Day 5 into
the other days.

## Out of scope

Named so they do not creep in:

- **Generalizing the hook into `cal:`.** `cal:askkw` / `cal:askdist` /
  `cal:asktreat` in `shared/parts/CALOFIN-LIB.lsp` are the chokepoint
  for a dozen tools in the grouped build — putting the hook there would
  make every tool form-drivable. Real payoff, real design risk, and it
  wants the POOL/SPA hook proven first. Next iteration.
- **Palette catalog drift.** `calofin.lsp` lists 28 commands; `lisp/`
  defines 96 `C:` names. Of the 68 with no button, 13 are `*VER`
  reporters, 18 are `TUTORIAL*` variants and 4 are `*RESCUE`
  companions, leaving 33 — though nine of those are the drone-height
  tool's `DD*` sub-commands and several more are `-CFG` / `-SETUP`
  partners. The genuinely missing headline tools are `ABFIND`,
  `ABMOVE`, `CABHD`, `CDCREATE`, `CDCALLOUT`, `BPCALLOUT`, `FITABHD`,
  `OASIS`, `SPACHECK`, `STOCKCOVER`, `XFTCONV`, `CPERPPTS`,
  `LINFINCHECK`, `NORMIESTEP`, `ALTABCDEF`, `CCPRECHECK`. Mechanical,
  additive, independent of this work — but check `cal:*held-back*`
  first: `LISPLAB` is `OMITTED` and must not get a button.
- **The nine POOL shapes "awaiting phase 3".** Shape, corners and
  cross dims stay at the command line. The Pool tab is the bottom
  only, as its README says.
- **`STANDARDS.md` §8 migration.** The corner-treatment rename to
  `Square/Radius/Cut/NotGiven` touches `SpaFormView.vb` and the shape
  field map, and §8.5 lists both form tests as things that break. It
  is a much larger job with its own sequencing. Do not start it inside
  this week — but read §8.5 before renaming anything, because the wire
  values `90`/`Radius`/`Diagonal` are pinned in three places.
