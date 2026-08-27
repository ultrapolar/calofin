# calofin changelog

Per-tool version banners (`POOL 082726 REV17`, `DIMCHECK v1.4`, ...) say
what changed in one file and drive its `releases/` twin. This file says
which set of them shipped together. The release name lives in
`RELEASE` at the top of `tools/build_shared_bundle.py`, so
`shared/LAZPASS.lsp` announces it on load and cannot drift from it.

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
