# calofin changelog

Per-tool version banners (`POOL 082726 REV17`, `DIMCHECK v1.4`, ...) say
what changed in one file and drive its `releases/` twin. This file says
which set of them shipped together. The release name lives in
`RELEASE` at the top of `tools/build_shared_bundle.py`, so
`shared/LAZPASS.lsp` announces it on load and cannot drift from it.

## v3.1 -- 2026-09-01

A stability pass over the one-file build. Nothing new to type; what was
there fails less, and two of the ways it could have failed the NEXT tool
in the session are closed.

### Fixed

- **`DRONE v1.3` / `TYDRN v1.3` no longer install their error handler by
  swapping the global `*error*`.** Both saved the global, set their own,
  and put it back on each exit -- so one exit missed (a throw inside the
  handler's own `EndUndoMark`, say) left that tool's cleanup live for
  every command run afterwards in the loaded-together build: closing an
  undo mark it never opened, re-locking layers it never touched. The
  handler is local to the command now, as the skeleton in STANDARDS 5
  has always said, sees the run's state through dynamic scope rather
  than through `*drone-doc*` / `*drone-unlocked*` globals, and closes
  only a mark the run actually opened.
- **`PADDLE v1.9`'s handler closed an undo mark it might never have
  opened.** An Esc at the perimeter prompt comes before
  `StartUndoMark`; the handler's unconditional `EndUndoMark` then threw
  from inside `*error*`, where nothing catches it. It tracks the mark now
  and closes it through `vl-catch-all-apply`.
- **`CALOFIN-LIB v1.5`: the shared sysvar snapshot merges instead of
  skipping.** Every tool in the grouped build shares `cal:*sysold*`, and
  the tools list different variables. After a run cut short, the next
  tool's `cal:syssave` used to save NOTHING -- so a variable the dead run
  never listed (`CLAYER`, `CMDECHO`) was changed and never put back. A
  variable already pending keeps its true value exactly as before; one
  the snapshot lacks is added. `tests/test_calofin_lib.py` pins both
  halves.

### The checks got stricter

- `check_lisp` fails a `(defun *error* ...)` or `(setq *error* ...)`
  whose enclosing command does not declare `*error*` local, and a
  handler at top level. Zero findings tree-wide once the two above were
  fixed; the deprecated acady matcher keeps its swap idiom.
- The VM can now run `*error*` (`vm.handle_errors = True`): a failure
  outside `vl-catch-all-apply` reaches the handler the failing code can
  see, with every frame still live, and the command is then aborted the
  way AutoCAD aborts it. It also carries just enough ActiveX -- the
  document, its undo marks, the layer collection with `Lock`, and the
  entity properties the cleanup tools put -- for `DRONE` and `TYDRN` to
  run under test for the first time: `tests/test_drone.py` drives the
  happy path, an error mid-run and an Esc at the prompt, at both tiers.

## v3.0 -- 2026-08-27

The release that made the whole toolset drivable from a filled-in chart,
and made the tree able to prove it is in step with itself.

### Zero-install GUI: fill the chart in, press Insert

- **`LAZSPA`** (new) -- `LAZFORM`'s argument applied to `SPA`: three
  charts (Rectangle, Octagon, Round), the boxes wedged into the
  dimension rows, and the spa drawn from what you typed.
- **`LAZSTEP`** (new) -- say how many steps, and the drawing is built
  for that count: N treads with their widths, N risers and N+1 drops,
  every dimension carrying its letter until you type over it.
- **`LAZFORM v2.5`** -- one authority decides what is greyed, and the
  letters it was missing are there.
- All three are plain DCL the file writes for itself, so there is no
  DLL to `NETLOAD` and no artwork to ship.

### The routines take answers from a form

`POOL`, `SPA` and the three step routines each carry an answer store the
ask helpers read before they prompt, so a filled-in chart drives the run
and a half-filled one shortens it. One contract everywhere: a key that
is absent is asked for as usual, `(key . nil)` answers NA without a
prompt, `(key . 84.0)` answers the measurement -- and **an answer is
removed as it is used**, which is what stops `Back` deadlocking on a
question the form already answered.

- `pool:*form*`, `spa:*form*`, `*cs-form*` / `*hs-form*` / `*ns-form*`,
  each with its own `run-with-answers`, cleared on both exits.
- POOL's gate questions and the step routines' count take form answers
  too -- the count is a question the step tools never had before.
- The VB palette caught up with what `SPA` actually asks, and its
  catalog with the tree.

### FITABHD fits the oasis pools too

- **`FITABHD v2.0`** -- the type list gains `OAsis`, and the survey of a
  continuous-tangent pool is fitted with **`OASIS`'s own ring solver**,
  carried into `FITABHD.lsp` under its own prefix so the two files
  cannot draw different pools from the same numbers.
  `test_oasis_ring_is_oasis_lsp_s_own` runs both through the VM and
  compares them element by element.
- Step 2, which has no corners to ask about on an oasis, asks which of
  OASIS's five families it is instead -- in OASIS's own words
  (`Center/TopRight/CLoud/Kidney/NXTcloud`). Steps 5 and 6 are skipped
  the way they are for a Round pool: neither shape has a wall to swing
  or to bow.
- **Everything else about the shape is measured.** An oasis has no walls
  for the edge vote to find a rotation from, so the frame is swept right
  round the pool and the best few placements fitted properly; the
  envelope then falls out of the bounding box, because every bulge is
  tangent to a bound.
- **A cloud's flat bottom is found, not declared.** Every joiner is
  carried as `U = h / (h + R)` rather than as a radius, so the straight
  run -- the reverse arc with an infinite radius -- is just `U = 0`,
  with no special case at either end. The report names the shape
  `straight-bottom cloud` or `rounded-bottom cloud` from what came out.
  Which way a kidney was given is settled the same way: both
  parameterisations are fitted and the points choose, with the freer one
  held to the both-ends evidence margin.
- The report prints every fitted radius under OASIS's own question
  wording, and all of them snap under the *feature* rule -- a measured
  radius, never a design dimension.
- An oasis wants at least 12 survey points, and its hopper is square to
  the envelope rather than to a wall, so all four bounds are offered as
  ends.

### Fixed

- **Output layers are repaired, not just created.** `POOL`, `SPA` and
  the four check tools drew onto a frozen or switched-off layer and
  reported success while producing nothing visible.
- **`LITELINFINSCAN` silently dropped the steps rule** -- a sheet with an
  obvious staircase reported "no step patterns detected" and lost its
  rise-vs-wall-height comparison. The one a drafter would have been
  burned by.
- **`Back` un-counted a defpoint move it could not undo**, so the report
  claimed "points adjusted: 0" over a drawing whose points had moved.
- **Scan findings never rendered red**, on the report whose whole job is
  to make problems findable.
- One canonical cancel test repo-wide (a `*break,` typo had already been
  copy-pasted into a second file), and every living tool now has an
  `*error*` handler that puts back what it changed -- including
  `AUTOBEAD`, which closed an undo group it might never have opened, and
  `PADDLE`, whose block import could leave `CMDECHO` and `ATTREQ`
  clobbered.
- `SPA` speaks the canonical `Square / Radius / Cut / NotGiven`
  treatment, with the sheet-legend words (`90`, `Diagonal`) still
  accepted and normalised -- so `LAZSPA`'s dropdown keeps the drafter's
  vocabulary while the routine keeps the standard's.
- Brackets a click can actually send, one tutorial selector, one pause
  spelling, `ROUnd` everywhere.

### The tree can now prove it is in step

- `mirror_shared.py`, `release_lisp.py` and `build_shared_bundle.py`
  each grew a `--check` mode, and `check_standards.py` runs all three:
  a hand-edited generated twin, an orphaned release or a stale bundle
  body now fails a check instead of shipping.
- `check_lisp.py` exited 0 on the unbalanced parens it advertised;
  `check_scope.py` had no exit code at all. Both gate now, with their
  false-positive classes fixed and a baseline so new findings surface.
- **47 of the 51 grouped twins are generated** (was 14), which is what
  stops the drift class that put two defects into `LAZPASS.lsp`.
- `tools/run_tests.py` + a `Makefile`: `make check`, `make test`,
  `make parity`. The canonical test list was prose in four documents and
  two files had already fallen out of it; the runner globs the directory.
- End-to-end tests for `DIMCHECK`, `LINFINCHECK` and `COVERCHECK` -- the
  three largest tools that had none -- plus `LAZSPA`, `LAZSTEP` and the
  step form suites.
- Nothing is expected to fail on a clean checkout: `EXPECTED_FAILURES`
  in `tools/run_tests.py` is empty, and a test that starts passing there
  fails the run until its entry goes.

### Deliberately deferred

Recorded in `STANDARDS.md` section 8 with reasons rather than left as
silent gaps: the uppercase `.LSP` filenames, SPA's spillaway corner-pick
keywords, `cal:askkw`'s signature (pinned by every generated twin at
once), the `prefix-` naming styles, and the VB palette's button catalog
(it cannot be compiled or tested here).
